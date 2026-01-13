import Foundation
import SwiftData
import CloudKit

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#endif

/// Manual CloudKit sync layer for per-record opt-in syncing.
///
/// Why manual?
/// SwiftData's built-in CloudKit integration is store-level, not per-record.
/// This service keeps the SwiftData store local-only and mirrors opted-in records to CloudKit.
@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    private let containerIdentifier = "iCloud.com.furfarch.MyHealthData"

    // Shares can't exist in the default zone. Use a dedicated private zone for shareable records.
    private let shareZoneName = "MyHealthDataShareZone"
    private var shareZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: shareZoneName, ownerName: CKCurrentUserDefaultName)
    }
    
    // Delay to allow server-side processing of share URL (in nanoseconds)
    private let shareURLPopulationDelay: UInt64 = 500_000_000 // 0.5 seconds

    /// CloudKit record type used for MedicalRecord mirrors.
    /// IMPORTANT:
    /// - CloudKit schemas are environment-specific (Development vs Production).
    /// - You can't create new record types in the Production schema from the client.
    ///   If you see: "Cannot create new type … in production schema",
    ///   create the record type in the CloudKit Dashboard (Development), then deploy to Production.
    private let medicalRecordType = "MedicalRecord"

    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }
    private var database: CKDatabase { container.privateCloudDatabase }

    private init() {}

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    // MARK: - Zone

    private func ensureShareZoneExists() async throws {
        do {
            _ = try await database.recordZone(for: shareZoneID)
        } catch {
            if let ck = error as? CKError, ck.code == .zoneNotFound {
                ShareDebugStore.shared.appendLog("ensureShareZoneExists: zone not found, creating zone=\(shareZoneName)")
                let zone = CKRecordZone(zoneID: shareZoneID)
                _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
                ShareDebugStore.shared.appendLog("ensureShareZoneExists: created zone=\(shareZoneName)")
            } else {
                ShareDebugStore.shared.appendLog("ensureShareZoneExists: failed: \(error)")
                throw error
            }
        }
    }

    private func zonedRecordID(for record: MedicalRecord) -> CKRecord.ID {
        let recordName = record.cloudRecordName ?? record.uuid
        return CKRecord.ID(recordName: recordName, zoneID: shareZoneID)
    }

    private func migrateRootRecordToShareZoneIfNeeded(record: MedicalRecord) async throws {
        let zonedID = zonedRecordID(for: record)
        do {
            _ = try await database.record(for: zonedID)
            return
        } catch {
            if let ck = error as? CKError, ck.code == .unknownItem {
                let recordName = record.cloudRecordName ?? record.uuid
                let defaultID = CKRecord.ID(recordName: recordName) // default zone

                do {
                    let legacy = try await database.record(for: defaultID)
                    ShareDebugStore.shared.appendLog("migrateRootRecordToShareZoneIfNeeded: found legacy default-zone record id=\(legacy.recordID.recordName); migrating to zone=\(shareZoneName)")

                    let migrated = CKRecord(recordType: medicalRecordType, recordID: zonedID)
                    for key in legacy.allKeys() {
                        migrated[key] = legacy[key]
                    }
                    applyMedicalRecord(record, to: migrated)

                    _ = try await database.save(migrated)
                    ShareDebugStore.shared.appendLog("migrateRootRecordToShareZoneIfNeeded: saved migrated record id=\(migrated.recordID.recordName) zone=\(shareZoneName)")

                    do {
                        _ = try await database.deleteRecord(withID: defaultID)
                        ShareDebugStore.shared.appendLog("migrateRootRecordToShareZoneIfNeeded: deleted legacy default-zone record id=\(defaultID.recordName)")
                    } catch {
                        ShareDebugStore.shared.appendLog("migrateRootRecordToShareZoneIfNeeded: failed deleting legacy default-zone record id=\(defaultID.recordName): \(error)")
                    }

                    record.cloudRecordName = recordName
                } catch {
                    if let ck2 = error as? CKError, ck2.code == .unknownItem {
                        return
                    }
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    // MARK: - Sync

    func syncIfNeeded(record: MedicalRecord) async throws {
        guard record.isCloudEnabled else { return }

        // Check iCloud account availability
        let status = try await accountStatus()
        guard status == .available else {
            let err = NSError(
                domain: "CloudSyncService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "iCloud account not available (status: \(status))."]
            )

            ShareDebugStore.shared.appendLog("syncIfNeeded: account not available for record=\(record.uuid) status=\(status)")
            throw err
        }

        try await ensureShareZoneExists()
        try await migrateRootRecordToShareZoneIfNeeded(record: record)

        let ckID = zonedRecordID(for: record)

        let ckRecord: CKRecord
        do {
            ckRecord = try await database.record(for: ckID)
        } catch {
            ckRecord = CKRecord(recordType: medicalRecordType, recordID: ckID)
        }

        applyMedicalRecord(record, to: ckRecord)

        do {
            let saved = try await database.save(ckRecord)

            // Persist back CloudKit identity and mark success
            record.cloudRecordName = saved.recordID.recordName
            ShareDebugStore.shared.appendLog("syncIfNeeded: saved id=\(saved.recordID.recordName) zone=\(shareZoneName) type=\(saved.recordType) for local uuid=\(record.uuid)")
        } catch {
            ShareDebugStore.shared.appendLog("syncIfNeeded: failed to save record=\(record.uuid) error=\(error)")
            throw enrichCloudKitError(error)
        }
    }

    func disableCloud(for record: MedicalRecord) {
        // Turn off local flags immediately.
        record.isCloudEnabled = false
        record.isSharingEnabled = false

        // Best-effort cleanup in CloudKit (share + root record).
        Task {
            do {
                try await revokeSharingAndDeleteFromCloud(record: record)
            } catch {
                ShareDebugStore.shared.appendLog("disableCloud: cleanup failed for record=\(record.uuid) error=\(error)")
            }

            // OFF means: this record is not on iCloud. Clear local CloudKit identifiers.
            record.cloudRecordName = nil
            record.cloudShareRecordName = nil
            record.shareParticipantsSummary = ""

            // Bump updatedAt so UI ordering reflects the change.
            record.updatedAt = Date()
        }
    }

    private func revokeSharingAndDeleteFromCloud(record: MedicalRecord) async throws {
        try await ensureShareZoneExists()

        // 1) Delete existing share record (if we know it)
        if let shareRecordName = record.cloudShareRecordName {
            let shareID = CKRecord.ID(recordName: shareRecordName, zoneID: shareZoneID)
            do {
                _ = try await database.deleteRecord(withID: shareID)
                ShareDebugStore.shared.appendLog("revokeSharingAndDeleteFromCloud: deleted CKShare id=\(shareRecordName) zone=\(shareZoneName) for record=\(record.uuid)")
            } catch {
                if let ck = error as? CKError, ck.code == .unknownItem {
                    ShareDebugStore.shared.appendLog("revokeSharingAndDeleteFromCloud: share already missing id=\(shareRecordName)")
                } else {
                    throw error
                }
            }
            record.cloudShareRecordName = nil
        }

        // 2) Delete root record from share zone
        let rootID = zonedRecordID(for: record)
        do {
            _ = try await database.deleteRecord(withID: rootID)
            ShareDebugStore.shared.appendLog("revokeSharingAndDeleteFromCloud: deleted root record id=\(rootID.recordName) zone=\(shareZoneName) for record=\(record.uuid)")
        } catch {
            if let ck = error as? CKError, ck.code == .unknownItem {
                ShareDebugStore.shared.appendLog("revokeSharingAndDeleteFromCloud: root record already missing id=\(rootID.recordName)")
            } else {
                throw error
            }
        }
    }

    // MARK: - Sharing

    func createShare(for record: MedicalRecord) async throws -> CKShare {
        try await ensureShareZoneExists()
        try await syncIfNeeded(record: record)

        let rootID = zonedRecordID(for: record)
        let root = try await database.record(for: rootID)

        // Reuse existing share if we know its record name.
        if let shareRecordName = record.cloudShareRecordName {
            let shareID = CKRecord.ID(recordName: shareRecordName, zoneID: shareZoneID)
            do {
                if let existing = try await database.record(for: shareID) as? CKShare {
                    ShareDebugStore.shared.lastShareURL = existing.url
                    ShareDebugStore.shared.appendLog("createShare: reusing existing share id=\(existing.recordID.recordName) zone=\(shareZoneName) url=\(String(describing: existing.url))")
                    return existing
                }
            } catch {
                if let ck = error as? CKError, ck.code == .unknownItem {
                    ShareDebugStore.shared.appendLog("createShare: stored share id not found in share zone, recreating. id=\(shareRecordName)")
                    record.cloudShareRecordName = nil
                } else {
                    ShareDebugStore.shared.appendLog("createShare: failed to fetch existing share id=\(shareRecordName): \(error)")
                }
            }
        }

        // Check if root already has a share reference
        if let existingShareRef = root.share {
            ShareDebugStore.shared.appendLog("createShare: root record already has share reference id=\(existingShareRef.recordID.recordName), attempting to fetch")
            do {
                if let existingShare = try await database.record(for: existingShareRef.recordID) as? CKShare {
                    record.cloudShareRecordName = existingShare.recordID.recordName
                    ShareDebugStore.shared.lastShareURL = existingShare.url
                    ShareDebugStore.shared.appendLog("createShare: found existing share via root reference id=\(existingShare.recordID.recordName) url=\(String(describing: existingShare.url))")
                    return existingShare
                }
            } catch {
                ShareDebugStore.shared.appendLog("createShare: failed to fetch share via root reference: \(error)")
                // Continue to create new share
            }
        }

        // Create new share
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Shared Medical Record" as CKRecordValue

        do {
            // Strategy: Use CKModifyRecordsOperation for better control over the save process
            // This gives us more reliable callbacks compared to modifyRecords
            ShareDebugStore.shared.appendLog("createShare: saving root=\(root.recordID.recordName) and share=\(share.recordID.recordName) in zone=\(shareZoneName)")
            
            // First, save the records using the operation
            let operationResult: CKShare? = try await withCheckedThrowingContinuation { continuation in
                let operation = CKModifyRecordsOperation(recordsToSave: [root, share], recordIDsToDelete: [])
                operation.savePolicy = .changedKeys
                operation.qualityOfService = .userInitiated
                
                var savedShareRecord: CKShare?
                
                // Track individual record saves
                operation.perRecordSaveBlock = { recordID, result in
                    switch result {
                    case .success(let record):
                        ShareDebugStore.shared.appendLog("createShare: saved record=\(recordID.recordName) type=\(record.recordType)")
                        if let share = record as? CKShare {
                            savedShareRecord = share
                            ShareDebugStore.shared.appendLog("createShare: captured CKShare in perRecordSaveBlock id=\(share.recordID.recordName)")
                        }
                    case .failure(let error):
                        ShareDebugStore.shared.appendLog("createShare: failed to save record=\(recordID.recordName) error=\(error)")
                    }
                }
                
                // Final result callback
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        if let savedShare = savedShareRecord {
                            ShareDebugStore.shared.appendLog("createShare: operation succeeded with share id=\(savedShare.recordID.recordName) url=\(String(describing: savedShare.url))")
                            continuation.resume(returning: savedShare)
                        } else {
                            ShareDebugStore.shared.appendLog("createShare: operation succeeded but share not captured in callbacks, will try fallback fetch")
                            continuation.resume(returning: nil)
                        }
                    case .failure(let error):
                        ShareDebugStore.shared.appendLog("createShare: operation failed: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
                
                database.add(operation)
            }
            
            // If share wasn't captured in operation callbacks, fetch it directly
            let savedShare: CKShare
            if let operationShare = operationResult {
                savedShare = operationShare
            } else {
                ShareDebugStore.shared.appendLog("createShare: fetching share directly after operation completed")
                if let fetchedShare = try await database.record(for: share.recordID) as? CKShare {
                    ShareDebugStore.shared.appendLog("createShare: fetched share after operation id=\(fetchedShare.recordID.recordName)")
                    savedShare = fetchedShare
                } else {
                    throw NSError(domain: "CloudSyncService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Share was saved but could not be retrieved from CloudKit"])
                }
            }
            
            // Store the share record name and URL
            record.cloudShareRecordName = savedShare.recordID.recordName
            ShareDebugStore.shared.lastShareURL = savedShare.url
            
            // If URL is nil, refetch to get the server-populated URL
            // Also refetch the root record to ensure the share reference is properly established
            if savedShare.url == nil {
                ShareDebugStore.shared.appendLog("createShare: share URL is nil after save, refetching from server")
                
                // Small delay to allow server-side processing
                try await Task.sleep(nanoseconds: shareURLPopulationDelay)
                
                do {
                    if let refetchedShare = try await database.record(for: savedShare.recordID) as? CKShare {
                        ShareDebugStore.shared.lastShareURL = refetchedShare.url
                        ShareDebugStore.shared.appendLog("createShare: refetched share url=\(String(describing: refetchedShare.url))")
                        
                        // Verify the root record has the share reference
                        do {
                            let refetchedRoot = try await database.record(for: root.recordID)
                            if let shareRef = refetchedRoot.share {
                                ShareDebugStore.shared.appendLog("createShare: root record has share reference=\(shareRef.recordID.recordName)")
                            } else {
                                ShareDebugStore.shared.appendLog("createShare: WARNING - root record does not have share reference")
                            }
                        } catch {
                            ShareDebugStore.shared.appendLog("createShare: WARNING - failed to refetch root record: \(error)")
                        }
                        
                        return refetchedShare
                    }
                } catch {
                    ShareDebugStore.shared.appendLog("createShare: WARNING - refetch of share failed: \(error)")
                }
            }
            
            ShareDebugStore.shared.appendLog("createShare: successfully created share id=\(savedShare.recordID.recordName) url=\(String(describing: savedShare.url))")
            return savedShare
            
        } catch let error as NSError where error.domain == "CloudSyncService" {
            // Re-throw our custom errors as-is
            ShareDebugStore.shared.lastError = error
            ShareDebugStore.shared.appendLog("createShare: failed with custom error: \(error)")
            throw error
        } catch {
            ShareDebugStore.shared.lastError = error
            ShareDebugStore.shared.appendLog("createShare: failed: \(error)")
            throw enrichCloudKitError(error)
        }
    }

    // MARK: - UICloudSharingController Integration

#if os(iOS) || targetEnvironment(macCatalyst)
    private var activeSharingDelegate: CloudSharingDelegate? // retain delegate while sheet is presented
    private var sharingTimeoutTask: Task<Void, Never>? = nil

    func makeCloudSharingController(for record: MedicalRecord, onComplete: @escaping (Result<URL?, Error>) -> Void) async throws -> UICloudSharingController {
        let container = CKContainer(identifier: containerIdentifier)

        // Check account status early
        let status = try await container.accountStatus()
        guard status == .available else {
            let err = NSError(domain: "CloudSyncService", code: 3, userInfo: [NSLocalizedDescriptionKey: "iCloud account not available (status: \(status)). Please sign in to iCloud."])
            ShareDebugStore.shared.appendLog("makeCloudSharingController: account not available: \(status)")
            throw err
        }

        // Ensure zone + record exist in CloudKit
        try await ensureShareZoneExists()
        try await syncIfNeeded(record: record)

        // IMPORTANT: Fetch root from share zone (not default zone)
        let rootID = zonedRecordID(for: record)

        let root: CKRecord
        do {
            root = try await database.record(for: rootID)
            ShareDebugStore.shared.appendLog("makeCloudSharingController: fetched root record id=\(root.recordID.recordName) zone=\(shareZoneName) for record=\(record.uuid)")
        } catch {
            ShareDebugStore.shared.appendLog("makeCloudSharingController: failed fetching root record from share zone: \(error)")
            throw enrichCloudKitError(error)
        }

        // Create delegate and retain it while controller is presented
        let delegate = CloudSharingDelegate()
        self.activeSharingDelegate = delegate
        delegate.onComplete = { [weak self] result in
            onComplete(result)
            DispatchQueue.main.async { self?.activeSharingDelegate = nil }
        }

        let savedShare: CKShare
        do {
            savedShare = try await createShare(for: record)
            ShareDebugStore.shared.appendLog("makeCloudSharingController: obtained CKShare id=\(savedShare.recordID.recordName) zone=\(shareZoneName)")
        } catch {
            ShareDebugStore.shared.appendLog("makeCloudSharingController: failed to obtain share: \(error)")
            throw enrichCloudKitError(error)
        }

        let controller = UICloudSharingController(share: savedShare, container: container)
        controller.delegate = delegate
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        controller.title = "Shared Medical Record"
        
        ShareDebugStore.shared.appendLog("makeCloudSharingController: created UICloudSharingController with share url=\(String(describing: savedShare.url))")
        return controller
    }
#endif

    // MARK: - Deletion

    // Convenience compatibility wrapper for earlier API name
    func deleteCloudRecord(for record: MedicalRecord) async throws {
        try await deleteSyncRecord(forLocalRecord: record)
    }

    func deleteSyncRecord(forLocalRecord record: MedicalRecord) async throws {
        try await ensureShareZoneExists()

        // Best-effort: delete CKShare first (shares live in the share zone).
        if let shareRecordName = record.cloudShareRecordName {
            let shareID = CKRecord.ID(recordName: shareRecordName, zoneID: shareZoneID)
            do {
                _ = try await database.deleteRecord(withID: shareID)
                ShareDebugStore.shared.appendLog("[CloudSyncService] Deleted CKShare id=\(shareRecordName) zone=\(shareZoneName) for local uuid=\(record.uuid)")
            } catch {
                if let ck = error as? CKError, ck.code == .unknownItem {
                    ShareDebugStore.shared.appendLog("[CloudSyncService] CKShare already missing id=\(shareRecordName) zone=\(shareZoneName)")
                } else {
                    ShareDebugStore.shared.appendLog("[CloudSyncService] Failed deleting CKShare id=\(shareRecordName) zone=\(shareZoneName): \(error)")
                    // don't block root deletion on share cleanup
                }
            }
            record.cloudShareRecordName = nil
        }

        // Root records live in the share zone.
        let ckID = zonedRecordID(for: record)

        // First try to delete by record ID directly
        do {
            let deleted = try await database.deleteRecord(withID: ckID)
            ShareDebugStore.shared.appendLog("[CloudSyncService] Deleted CloudKit root id=\(deleted.recordName) zone=\(shareZoneName) for local uuid=\(record.uuid)")
            return
        } catch {
            ShareDebugStore.shared.appendLog("[CloudSyncService] Direct zoned delete failed id=\(ckID.recordName) zone=\(shareZoneName): \(error)")
            // fall through to query-by-uuid in the same zone
        }

        // Fallback: delete by matching uuid field (must query the same custom zone)
        let predicate = NSPredicate(format: "uuid == %@", record.uuid)
        let query = CKQuery(recordType: medicalRecordType, predicate: predicate)

        let idsToDelete: [CKRecord.ID] = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecord.ID], Error>) in
            var foundIDs: [CKRecord.ID] = []
            let op = CKQueryOperation(query: query)
            op.zoneID = shareZoneID
            op.recordMatchedBlock = { (_: CKRecord.ID, matchedResult: Result<CKRecord, Error>) in
                switch matchedResult {
                case .success(let rec): foundIDs.append(rec.recordID)
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            op.queryResultBlock = { result in
                switch result {
                case .success: cont.resume(returning: foundIDs)
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            database.add(op)
        }

        if !idsToDelete.isEmpty {
            for id in idsToDelete {
                do {
                    let deleted = try await database.deleteRecord(withID: id)
                    ShareDebugStore.shared.appendLog("[CloudSyncService] Deleted CloudKit record id=\(deleted.recordName) via uuid match zone=\(shareZoneName) local uuid=\(record.uuid)")
                } catch {
                    ShareDebugStore.shared.appendLog("[CloudSyncService] Failed deleting matched CloudKit record id=\(id.recordName): \(error)")
                    throw enrichCloudKitError(error)
                }
            }
        } else {
            ShareDebugStore.shared.appendLog("[CloudSyncService] No CloudKit record found for uuid=\(record.uuid) in zone=\(shareZoneName)")
        }
    }

    // MARK: - Mapping

    private func applyMedicalRecord(_ record: MedicalRecord, to ckRecord: CKRecord) {
        ckRecord["uuid"] = record.uuid as NSString
        ckRecord["createdAt"] = record.createdAt as NSDate
        ckRecord["updatedAt"] = record.updatedAt as NSDate

        ckRecord["isPet"] = record.isPet as NSNumber

        ckRecord["personalFamilyName"] = record.personalFamilyName as NSString
        ckRecord["personalGivenName"] = record.personalGivenName as NSString
        ckRecord["personalNickName"] = record.personalNickName as NSString
        ckRecord["personalGender"] = record.personalGender as NSString
        if let birthdate = record.personalBirthdate {
            ckRecord["personalBirthdate"] = birthdate as NSDate
        } else {
            ckRecord["personalBirthdate"] = nil
        }

        ckRecord["personalSocialSecurityNumber"] = record.personalSocialSecurityNumber as NSString
        ckRecord["personalAddress"] = record.personalAddress as NSString
        ckRecord["personalHealthInsurance"] = record.personalHealthInsurance as NSString
        ckRecord["personalHealthInsuranceNumber"] = record.personalHealthInsuranceNumber as NSString
        ckRecord["personalEmployer"] = record.personalEmployer as NSString

        ckRecord["personalName"] = record.personalName as NSString
        ckRecord["personalAnimalID"] = record.personalAnimalID as NSString
        ckRecord["ownerName"] = record.ownerName as NSString
        ckRecord["ownerPhone"] = record.ownerPhone as NSString
        ckRecord["ownerEmail"] = record.ownerEmail as NSString

        ckRecord["emergencyName"] = record.emergencyName as NSString
        ckRecord["emergencyNumber"] = record.emergencyNumber as NSString
        ckRecord["emergencyEmail"] = record.emergencyEmail as NSString

        // Simple versioning to allow future schema changes
        ckRecord["schemaVersion"] = 1 as NSNumber
    }

    private func enrichCloudKitError(_ error: Error) -> Error {
        // Try to map common CKError codes to friendlier messages
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                return NSError(domain: "CloudSyncService", code: ck.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "Not signed in to iCloud. Please sign in and try again."])
            case .permissionFailure:
                return NSError(domain: "CloudSyncService", code: ck.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "Permission failure. Check CloudKit dashboard roles and container permissions."])
            case .serverRejectedRequest:
                return NSError(domain: "CloudSyncService", code: ck.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "Server rejected request. Try again later."])
            case .zoneNotFound:
                return NSError(domain: "CloudSyncService", code: ck.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "CloudKit zone not found. Ensure your CloudKit schema and zone are set up."])
            default:
                break
            }
        }
        return error
    }
}

#if os(iOS) || targetEnvironment(macCatalyst)
class CloudSharingDelegate: NSObject, UICloudSharingControllerDelegate {
    var onComplete: ((Result<URL?, Error>) -> Void)?

    func cloudSharingController(_ c: UICloudSharingController, failedToSaveShareWithError error: Error) {
        ShareDebugStore.shared.appendLog("CloudSharingDelegate: failedToSaveShareWithError: \(error)")
        print("CloudKit sharing failed: \(error)")
        onComplete?(.failure(error))
    }
    func cloudSharingControllerDidSaveShare(_ c: UICloudSharingController) {
        let url = c.share?.url
        ShareDebugStore.shared.appendLog("CloudSharingDelegate: didSaveShare url=\(String(describing: url))")
        print("CloudKit share saved: \(String(describing: url))")
        onComplete?(.success(url))
    }
    func cloudSharingControllerDidStopSharing(_ c: UICloudSharingController) {
        ShareDebugStore.shared.appendLog("CloudSharingDelegate: didStopSharing")
        print("CloudKit sharing stopped")
        onComplete?(.success(nil))
    }
    func itemTitle(for c: UICloudSharingController) -> String? { "Shared Medical Record" }
    func itemThumbnailData(for c: UICloudSharingController) -> Data? { nil }
    func itemType(for c: UICloudSharingController) -> String? { "public.data" }
}
#endif
