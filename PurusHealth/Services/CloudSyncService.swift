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

    private let containerIdentifier = AppConfig.CloudKit.containerID

    // Shares can't exist in the default zone. Use a dedicated private zone for shareable records.
    private let shareZoneName = AppConfig.CloudKit.shareZoneName
    private var shareZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: shareZoneName, ownerName: CKCurrentUserDefaultName)
    }
    
    // Delay to allow server-side processing of share URL (in nanoseconds)
    private let shareURLPopulationDelay: UInt64 = 1_000_000_000 // 1 second
    private let shareURLMaxRetries = 3 // Maximum number of refetch attempts
    private let nanosecondsPerSecond: Double = 1_000_000_000 // For logging conversion

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
                    // Only write supported fields to avoid schema errors in Production
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

        // Do not resurrect locally deleted records
        if record.isMarkedForDeletion == true { return }

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

        // If this record is part of a CloudKit share, attempt to write back to the shared database
        // so receivers with write permission can sync their edits back to the owner and other participants.
        if record.isSharingEnabled, let _ = record.cloudShareRecordName {
            do {
                try await syncSharedRecordIfNeeded(record)
                return
            } catch {
                // If the user has read-only permission, CloudKit will return a permission failure.
                // In that case, surface a friendly error and fall through to private DB sync only if this device is the owner.
                if let ck = error as? CKError, ck.code == .permissionFailure {
                    ShareDebugStore.shared.appendLog("syncIfNeeded: shared write denied (read-only participant) for record=\(record.uuid)")
                    throw NSError(domain: "CloudSyncService", code: 8, userInfo: [NSLocalizedDescriptionKey: "You don't have permission to edit this shared record."])
                } else {
                    ShareDebugStore.shared.appendLog("syncIfNeeded: shared write failed for record=\(record.uuid) error=\(error)")
                    throw error
                }
            }
        }

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

    // MARK: - Shared write-back (for receivers with write permission)
    private func syncSharedRecordIfNeeded(_ record: MedicalRecord) async throws {
        let sharedDB = container.sharedCloudDatabase

        // Find the shared CKRecord by uuid across all shared zones
        let zones: [CKRecordZone] = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecordZone], Error>) in
            sharedDB.fetchAllRecordZones { zones, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: zones ?? [])
            }
        }

        var foundRecord: CKRecord? = nil
        zoneLoop: for zone in zones {
            let predicate = NSPredicate(format: "uuid == %@", record.uuid)
            let query = CKQuery(recordType: medicalRecordType, predicate: predicate)
            let op = CKQueryOperation(query: query)
            op.zoneID = zone.zoneID

            foundRecord = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CKRecord?, Error>) in
                var captured: CKRecord?
                op.recordMatchedBlock = { (_, result) in
                    if case .success(let rec) = result { captured = rec }
                }
                op.queryResultBlock = { result in
                    switch result {
                    case .success:
                        cont.resume(returning: captured)
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
                sharedDB.add(op)
            }

            if foundRecord != nil { break zoneLoop }
        }

        guard let sharedCKRecord = foundRecord else {
            // No-op: shared zone not yet attached or record not visible; avoid surfacing an error while acceptance is pending.
            ShareDebugStore.shared.appendLog("syncSharedRecordIfNeeded: shared record not found yet for uuid=\(record.uuid); skipping write-back")
            return
        }

        // Apply local changes and save to the shared database
        applyMedicalRecord(record, to: sharedCKRecord)
        do {
            let saved = try await sharedDB.save(sharedCKRecord)
            ShareDebugStore.shared.appendLog("syncSharedRecordIfNeeded: saved shared record id=\(saved.recordID.recordName) zone=\(saved.recordID.zoneID.zoneName) for local uuid=\(record.uuid)")
            
            // Update participants summary locally
            await CloudKitShareParticipantsService.shared.refreshParticipantsSummary(for: record)
        } catch {
            if let ck = error as? CKError, ck.code == .permissionFailure {
                ShareDebugStore.shared.appendLog("syncSharedRecordIfNeeded: permission failure (read-only) for uuid=\(record.uuid)")
                throw NSError(domain: "CloudSyncService", code: ck.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "You don't have permission to edit this shared record."])
            }
            throw enrichCloudKitError(error)
        }
    }

    func disableCloud(for record: MedicalRecord) {
        // Turn off local flags immediately.
        record.isCloudEnabled = false
        record.isSharingEnabled = false

        // Create tombstone in CloudKit to remove from all other synced devices.
        // This makes "Set Local" behave like "Stop Sharing" - removes from all devices except this one.
        Task {
            do {
                try await createTombstone(for: record)
                ShareDebugStore.shared.appendLog("disableCloud: created tombstone to remove from other devices uuid=\(record.uuid)")
            } catch {
                ShareDebugStore.shared.appendLog("disableCloud: tombstone creation failed uuid=\(record.uuid) error=\(error)")
            }

            // Clear CloudKit identifiers locally
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

    /// Stops sharing for a record by deleting the CKShare only, keeping the root record intact.
    func stopSharing(for record: MedicalRecord) async throws {
        try await ensureShareZoneExists()
        guard let shareRecordName = record.cloudShareRecordName else { return }
        let shareID = CKRecord.ID(recordName: shareRecordName, zoneID: shareZoneID)
        do {
            _ = try await database.deleteRecord(withID: shareID)
            ShareDebugStore.shared.appendLog("stopSharing: deleted CKShare id=\(shareRecordName) zone=\(shareZoneName) for record=\(record.uuid)")
        } catch {
            if let ck = error as? CKError, ck.code == .unknownItem {
                ShareDebugStore.shared.appendLog("stopSharing: share already missing id=\(shareRecordName)")
            } else {
                throw error
            }
        }
        record.cloudShareRecordName = nil
        record.isSharingEnabled = false
        record.shareParticipantsSummary = ""
        record.updatedAt = Date()
    }

    // MARK: - Sharing

    func createShare(for record: MedicalRecord) async throws -> CKShare {
        try await ensureShareZoneExists()
        try await syncIfNeeded(record: record)

        // Safety: shares can't exist in the default zone. Ensure the root is in our share zone.
        try await migrateRootRecordToShareZoneIfNeeded(record: record)

        let rootID = zonedRecordID(for: record)
        let root = try await database.record(for: rootID)

        // Reuse existing share if we know its record name.
        if let shareRecordName = record.cloudShareRecordName {
            let shareID = CKRecord.ID(recordName: shareRecordName, zoneID: shareZoneID)
            do {
                let existingRecord = try await database.record(for: shareID)
                if let existing = existingRecord as? CKShare {
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
                let existingShareRecord = try await database.record(for: existingShareRef.recordID)
                if let existingShare = existingShareRecord as? CKShare {
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
        // Configure default permissions; only invited users, allow read-write by default via UI controller
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = (root["personalName"] as? NSString) ?? "Shared Medical Record"

        do {
            // Use CKModifyRecordsOperation with .allKeys save policy
            // This ensures the root record is saved along with the share, even if the root hasn't changed
            // This is critical for establishing the share-root relationship in CloudKit
            ShareDebugStore.shared.appendLog("createShare: saving root=\(root.recordID.recordName) and share=\(share.recordID.recordName) in zone=\(shareZoneName)")
            
            let saveResults: [CKRecord.ID: CKRecord] = try await withCheckedThrowingContinuation { continuation in
                let operation = CKModifyRecordsOperation(recordsToSave: [root, share], recordIDsToDelete: [])
                operation.savePolicy = .allKeys  // Force save even if root hasn't changed
                operation.qualityOfService = .userInitiated
                
                var recordsSaved: [CKRecord.ID: CKRecord] = [:]
                var recordErrors: [CKRecord.ID: Error] = [:]
                
                operation.perRecordSaveBlock = { recordID, result in
                    switch result {
                    case .success(let record):
                        recordsSaved[recordID] = record
                        ShareDebugStore.shared.appendLog("createShare: saved record id=\(recordID.recordName) type=\(record.recordType)")
                    case .failure(let error):
                        recordErrors[recordID] = error
                        ShareDebugStore.shared.appendLog("createShare: failed to save record id=\(recordID.recordName) error=\(error)")
                    }
                }
                
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        // Check if any records failed to save
                        if !recordErrors.isEmpty {
                            ShareDebugStore.shared.appendLog("createShare: operation completed but \(recordErrors.count) record(s) failed")
                            // Log all errors
                            for (recordID, error) in recordErrors {
                                ShareDebugStore.shared.appendLog("createShare: record \(recordID.recordName) error: \(error)")
                            }
                            // Create a composite error with all failures
                            let errorDescription = recordErrors.map { "\($0.key.recordName): \($0.value.localizedDescription)" }.joined(separator: ", ")
                            let compositeError = NSError(
                                domain: "CloudSyncService",
                                code: 7,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to save \(recordErrors.count) record(s): \(errorDescription)"]
                            )
                            continuation.resume(throwing: compositeError)
                        } else {
                            ShareDebugStore.shared.appendLog("createShare: operation succeeded with \(recordsSaved.count) saved records")
                            continuation.resume(returning: recordsSaved)
                        }
                    case .failure(let error):
                        ShareDebugStore.shared.appendLog("createShare: operation failed: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
                
                database.add(operation)
            }
            
            // Process save results and extract saved records
            var savedShare: CKShare?
            
            for (_, record) in saveResults {
                if let share = record as? CKShare {
                    savedShare = share
                    ShareDebugStore.shared.appendLog("createShare: saved CKShare id=\(share.recordID.recordName) url=\(String(describing: share.url))")
                } else {
                    ShareDebugStore.shared.appendLog("createShare: saved root record id=\(record.recordID.recordName) type=\(record.recordType)")
                }
            }
            
            // Verify we got the share back
            guard let finalShare = savedShare else {
                ShareDebugStore.shared.appendLog("createShare: ERROR - no CKShare found in save results")
                throw NSError(domain: "CloudSyncService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Share was not returned in save results"])
            }
            
            ShareDebugStore.shared.appendLog("createShare: obtained saved share id=\(finalShare.recordID.recordName) url=\(String(describing: finalShare.url))")
            
            // Store the share record name and URL
            record.cloudShareRecordName = finalShare.recordID.recordName
            ShareDebugStore.shared.lastShareURL = finalShare.url
            
            // If URL is nil, retry fetching to get the server-populated URL
            // The URL is generated asynchronously by CloudKit servers and might not be available immediately
            if finalShare.url == nil {
                ShareDebugStore.shared.appendLog("createShare: share URL is nil after save, will retry fetching with exponential backoff")
                
                // Retry with exponential backoff
                var retryCount = 0
                var currentDelay = shareURLPopulationDelay
                var refetchedShare: CKShare?
                
                while retryCount < shareURLMaxRetries {
                    ShareDebugStore.shared.appendLog("createShare: retry attempt \(retryCount + 1)/\(shareURLMaxRetries) after \(Double(currentDelay) / nanosecondsPerSecond)s delay")
                    try await Task.sleep(nanoseconds: currentDelay)
                    
                    do {
                        let fetchedRecord = try await database.record(for: finalShare.recordID)
                        if let fetchedShare = fetchedRecord as? CKShare {
                            ShareDebugStore.shared.appendLog("createShare: refetched share id=\(fetchedShare.recordID.recordName) url=\(String(describing: fetchedShare.url))")
                            
                            if fetchedShare.url != nil {
                                refetchedShare = fetchedShare
                                ShareDebugStore.shared.lastShareURL = fetchedShare.url
                                ShareDebugStore.shared.appendLog("createShare: SUCCESS - share URL populated after \(retryCount + 1) retries")
                                break
                            } else {
                                ShareDebugStore.shared.appendLog("createShare: URL still nil after retry \(retryCount + 1)")
                            }
                        } else {
                            ShareDebugStore.shared.appendLog("createShare: WARNING - refetch did not return a CKShare on retry \(retryCount + 1)")
                        }
                    } catch {
                        ShareDebugStore.shared.appendLog("createShare: WARNING - refetch failed on retry \(retryCount + 1): \(error)")
                    }
                    
                    retryCount += 1
                    currentDelay *= 2  // Exponential backoff
                }
                
                // If we got a refetched share with URL, verify root has share reference and return it
                if let refetchedShare = refetchedShare, refetchedShare.url != nil {
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
                } else {
                    ShareDebugStore.shared.appendLog("createShare: WARNING - share URL still nil after all retries. This may indicate a CloudKit configuration issue or simulator limitation.")
                }
            }
            
            ShareDebugStore.shared.appendLog("createShare: returning share id=\(finalShare.recordID.recordName) url=\(String(describing: finalShare.url))")
            return finalShare
            
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

    func makeCloudSharingController(for record: MedicalRecord, preferredPermissions: UICloudSharingController.PermissionOptions? = nil, onComplete: @escaping (Result<URL?, Error>) -> Void) async throws -> UICloudSharingController {
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
        if let preferred = preferredPermissions {
            controller.availablePermissions = [preferred, .allowPrivate]
        } else {
            controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        }
        controller.modalPresentationStyle = .formSheet
        controller.title = "Shared Medical Record"
        
        ShareDebugStore.shared.appendLog("makeCloudSharingController: created UICloudSharingController with share url=\(String(describing: savedShare.url))")
        return controller
    }
#endif

    // MARK: - Deletion
    
    /// Creates a minimal tombstone record in CloudKit with only deletion metadata.
    /// This ensures devices that sync weeks/months later still see the deletion.
    /// Storage: ~100 bytes vs 5-50 KB for full record (99% reduction)
    private func createTombstone(for record: MedicalRecord) async throws {
        try await ensureShareZoneExists()
        let ckID = zonedRecordID(for: record)
        let ckRecord = CKRecord(recordType: medicalRecordType, recordID: ckID)
        
        // Minimal data - only deletion metadata, no personal/medical information
        ckRecord["uuid"] = record.uuid as NSString
        ckRecord["isDeleted"] = 1 as NSNumber
        ckRecord["deletedAt"] = Date() as NSDate
        ckRecord["updatedAt"] = Date() as NSDate
        ckRecord["schemaVersion"] = 1 as NSNumber
        
        _ = try await database.save(ckRecord)
        ShareDebugStore.shared.appendLog("[CloudSyncService] Created tombstone uuid=\(record.uuid)")
    }

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
                    // don't block tombstone creation on share cleanup
                }
            }
            record.cloudShareRecordName = nil
        }

        // Create tombstone instead of deleting entirely
        // This ensures devices that sync weeks/months later still see the deletion
        try await createTombstone(for: record)
        
        // Clear local CloudKit identifiers
        record.cloudRecordName = nil
        record.isSharingEnabled = false
        record.isCloudEnabled = false
        record.shareParticipantsSummary = ""
        record.updatedAt = Date()
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
        ckRecord["petBreed"] = record.petBreed as NSString
        ckRecord["petColor"] = record.petColor as NSString
        ckRecord["ownerName"] = record.ownerName as NSString
        ckRecord["ownerPhone"] = record.ownerPhone as NSString
        ckRecord["ownerEmail"] = record.ownerEmail as NSString

        // Veterinary fields
        ckRecord["vetClinicName"] = record.vetClinicName as NSString
        ckRecord["vetContactName"] = record.vetContactName as NSString
        ckRecord["vetPhone"] = record.vetPhone as NSString
        ckRecord["vetEmail"] = record.vetEmail as NSString
        ckRecord["vetAddress"] = record.vetAddress as NSString
        ckRecord["vetNote"] = record.vetNote as NSString

        ckRecord["emergencyName"] = record.emergencyName as NSString
        ckRecord["emergencyNumber"] = record.emergencyNumber as NSString
        ckRecord["emergencyEmail"] = record.emergencyEmail as NSString

        // Serialize relationship arrays as JSON
        // Blood entries
        let codableBlood = record.blood.map { CodableBloodEntry(date: $0.date?.timeIntervalSince1970, name: $0.name, comment: $0.comment) }
        if let bloodJSON = try? JSONEncoder().encode(codableBlood), let bloodString = String(data: bloodJSON, encoding: .utf8) {
            ckRecord["bloodEntries"] = bloodString as NSString
        }

        // Drug entries
        let codableDrugs = record.drugs.map { CodableDrugEntry(date: $0.date?.timeIntervalSince1970, nameAndDosage: $0.nameAndDosage, comment: $0.comment) }
        if let drugsJSON = try? JSONEncoder().encode(codableDrugs), let drugsString = String(data: drugsJSON, encoding: .utf8) {
            ckRecord["drugEntries"] = drugsString as NSString
        }

        // Vaccination entries
        let codableVaccinations = record.vaccinations.map { CodableVaccinationEntry(date: $0.date?.timeIntervalSince1970, name: $0.name, information: $0.information, place: $0.place, comment: $0.comment) }
        if let vaccinationsJSON = try? JSONEncoder().encode(codableVaccinations), let vaccinationsString = String(data: vaccinationsJSON, encoding: .utf8) {
            ckRecord["vaccinationEntries"] = vaccinationsString as NSString
        }

        // Allergy entries
        let codableAllergy = record.allergy.map { CodableAllergyEntry(date: $0.date?.timeIntervalSince1970, name: $0.name, information: $0.information, comment: $0.comment) }
        if let allergyJSON = try? JSONEncoder().encode(codableAllergy), let allergyString = String(data: allergyJSON, encoding: .utf8) {
            ckRecord["allergyEntries"] = allergyString as NSString
        }

        // Illness entries
        let codableIllness = record.illness.map { CodableIllnessEntry(date: $0.date?.timeIntervalSince1970, name: $0.name, informationOrComment: $0.informationOrComment) }
        if let illnessJSON = try? JSONEncoder().encode(codableIllness), let illnessString = String(data: illnessJSON, encoding: .utf8) {
            ckRecord["illnessEntries"] = illnessString as NSString
        }

        // Risk entries
        let codableRisks = record.risks.map { CodableRiskEntry(date: $0.date?.timeIntervalSince1970, name: $0.name, descriptionOrComment: $0.descriptionOrComment) }
        if let risksJSON = try? JSONEncoder().encode(codableRisks), let risksString = String(data: risksJSON, encoding: .utf8) {
            ckRecord["riskEntries"] = risksString as NSString
        }

        // Medical history entries
        let codableHistory = record.medicalhistory.map { CodableMedicalHistoryEntry(date: $0.date?.timeIntervalSince1970, name: $0.name, contact: $0.contact, informationOrComment: $0.informationOrComment) }
        if let historyJSON = try? JSONEncoder().encode(codableHistory), let historyString = String(data: historyJSON, encoding: .utf8) {
            ckRecord["medicalHistoryEntries"] = historyString as NSString
        }

        // Medical document entries
        let codableDocuments = record.medicaldocument.map { CodableMedicalDocumentEntry(date: $0.date?.timeIntervalSince1970, name: $0.name, note: $0.note) }
        if let documentJSON = try? JSONEncoder().encode(codableDocuments), let documentString = String(data: documentJSON, encoding: .utf8) {
            ckRecord["medicalDocumentEntries"] = documentString as NSString
        }

        // Human doctor entries
        let codableDoctors = record.humanDoctors.map { CodableHumanDoctorEntry(uuid: $0.uuid, createdAt: $0.createdAt.timeIntervalSince1970, updatedAt: $0.updatedAt.timeIntervalSince1970, type: $0.type, name: $0.name, phone: $0.phone, email: $0.email, address: $0.address, note: $0.note) }
        if let doctorsJSON = try? JSONEncoder().encode(codableDoctors), let doctorsString = String(data: doctorsJSON, encoding: .utf8) {
            ckRecord["humanDoctorEntries"] = doctorsString as NSString
        }
        
        // Weight entries
        let codableWeights = record.weights.map { CodableWeightEntry(uuid: $0.uuid, createdAt: $0.createdAt.timeIntervalSince1970, updatedAt: $0.updatedAt.timeIntervalSince1970, date: $0.date?.timeIntervalSince1970, weightKg: $0.weightKg, comment: $0.comment) }
        if let weightsJSON = try? JSONEncoder().encode(codableWeights), let weightsString = String(data: weightsJSON, encoding: .utf8) {
            ckRecord["weightEntries"] = weightsString as NSString
        }
        
        // Pet yearly cost entries
        let codablePetCosts = record.petYearlyCosts.map { CodablePetYearlyCostEntry(uuid: $0.uuid, createdAt: $0.createdAt.timeIntervalSince1970, updatedAt: $0.updatedAt.timeIntervalSince1970, date: $0.date.timeIntervalSince1970, year: $0.year, category: $0.category, amount: $0.amount, note: $0.note) }
        if let petCostsJSON = try? JSONEncoder().encode(codablePetCosts), let petCostsString = String(data: petCostsJSON, encoding: .utf8) {
            ckRecord["petYearlyCostEntries"] = petCostsString as NSString
        }
        
        // Emergency contacts
        let codableEmergencyContacts = record.emergencyContacts.map { CodableEmergencyContact(id: $0.id.uuidString, name: $0.name, phone: $0.phone, email: $0.email, note: $0.note) }
        if let emergencyContactsJSON = try? JSONEncoder().encode(codableEmergencyContacts), let emergencyContactsString = String(data: emergencyContactsJSON, encoding: .utf8) {
            ckRecord["emergencyContactEntries"] = emergencyContactsString as NSString
        }

        // Simple versioning to allow future schema changes
        ckRecord["schemaVersion"] = 1 as NSNumber

        // Tombstone/flags are tracked locally; avoid mirroring to CloudKit to prevent schema drift
        // Intentionally not writing isDeleted / isSharingEnabled fields to CloudKit
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
        onComplete?(.failure(error))
    }
    func cloudSharingControllerDidSaveShare(_ c: UICloudSharingController) {
        let url = c.share?.url
        ShareDebugStore.shared.appendLog("CloudSharingDelegate: didSaveShare url=\(String(describing: url))")
        onComplete?(.success(url))
    }
    func cloudSharingControllerDidStopSharing(_ c: UICloudSharingController) {
        ShareDebugStore.shared.appendLog("CloudSharingDelegate: didStopSharing")
        onComplete?(.success(nil))
    }
    func itemTitle(for c: UICloudSharingController) -> String? { "Shared Medical Record" }
    func itemThumbnailData(for c: UICloudSharingController) -> Data? { nil }
    func itemType(for c: UICloudSharingController) -> String? { "public.data" }
}
#endif

