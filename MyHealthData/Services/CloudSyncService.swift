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

    // MARK: - Sync

    func syncIfNeeded(record: MedicalRecord) async throws {
        guard record.isCloudEnabled else { return }

        let status = try await accountStatus()
        guard status == .available else {
            throw NSError(
                domain: "CloudSyncService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "iCloud account not available (status: \(status))."]
            )
        }

        let recordName = record.cloudRecordName ?? record.uuid
        let ckID = CKRecord.ID(recordName: recordName)

        let ckRecord: CKRecord
        do {
            ckRecord = try await database.record(for: ckID)
        } catch {
            // If it doesn't exist yet, create a new one.
            ckRecord = CKRecord(recordType: medicalRecordType, recordID: ckID)
        }

        applyMedicalRecord(record, to: ckRecord)

        let saved = try await database.save(ckRecord)

        // Persist back CloudKit identity
        record.cloudRecordName = saved.recordID.recordName
    }

    func disableCloud(for record: MedicalRecord) {
        record.isCloudEnabled = false
        // Keep cloudRecordName so it can be re-enabled later without duplicating, if desired.
    }

    // MARK: - Sharing

    func createShare(for record: MedicalRecord) async throws -> CKShare {
        // Ensure record exists in CloudKit and fetch root record
        try await syncIfNeeded(record: record)

        let recordName = record.cloudRecordName ?? record.uuid
        let rootID = CKRecord.ID(recordName: recordName)
        let root = try await database.record(for: rootID)

        // Prepare CKShare and set a title
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Shared Medical Record" as CKRecordValue

        do {
            // Use the async modifyRecords API which returns a mapping of record ID -> Result<CKRecord, Error>.
            // Extract successful CKRecord values and find the CKShare among them. This avoids races where
            // a freshly-saved CKShare isn't yet queryable via record(for:).
            let (savedRecordsByID, _) = try await database.modifyRecords(saving: [root, share], deleting: [])

            // savedRecordsByID: [CKRecord.ID: Result<CKRecord, Error>]
            let savedValues: [CKRecord] = savedRecordsByID.values.compactMap { result in
                switch result {
                case .success(let rec): return rec
                case .failure(_): return nil
                }
            }

            if let savedShare = savedValues.compactMap({ $0 as? CKShare }).first {
                print("[CloudSyncService] Created CKShare id=\(savedShare.recordID.recordName) for record=\(record.uuid) url=\(String(describing: savedShare.url))")
                return savedShare
            }

            // Fallback: fetch the share by its recordID
            let fetched = try await database.record(for: share.recordID)
            if let fetchedShare = fetched as? CKShare { return fetchedShare }

            throw NSError(domain: "CloudSyncService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain saved CKShare from server."])
        } catch {
            throw enrichCloudKitError(error)
        }
    }

    // MARK: - UICloudSharingController Integration

#if os(iOS) || targetEnvironment(macCatalyst)
    private var activeSharingDelegate: CloudSharingDelegate? // retain delegate while sheet is presented
    private var sharingTimeoutTask: Task<Void, Never>? = nil

    func makeCloudSharingController(for record: MedicalRecord, onComplete: @escaping (Result<URL?, Error>) -> Void) async throws -> UICloudSharingController {
        let recordName = record.cloudRecordName ?? record.uuid
        let rootID = CKRecord.ID(recordName: recordName)
        let container = CKContainer(identifier: containerIdentifier)

        // Check account status early
        let status = try await container.accountStatus()
        guard status == .available else {
            let err = NSError(domain: "CloudSyncService", code: 3, userInfo: [NSLocalizedDescriptionKey: "iCloud account not available (status: \(status)). Please sign in to iCloud."])
            ShareDebugStore.shared.appendLog("makeCloudSharingController: account not available: \(status)")
            throw err
        }

        // Ensure record exists in CloudKit
        try await syncIfNeeded(record: record)

        // Fetch the root record from CloudKit (fresh copy)
        let root: CKRecord
        do {
            root = try await database.record(for: rootID)
            ShareDebugStore.shared.appendLog("makeCloudSharingController: fetched root record id=\(root.recordID.recordName) for record=\(record.uuid)")
        } catch {
            ShareDebugStore.shared.appendLog("makeCloudSharingController: failed fetching root record: \(error)")
            throw enrichCloudKitError(error)
        }

        // Create delegate and retain it while controller is presented
        let delegate = CloudSharingDelegate()
        self.activeSharingDelegate = delegate
        delegate.onComplete = { [weak self] result in
            onComplete(result)
            DispatchQueue.main.async { self?.activeSharingDelegate = nil }
        }

        // Pre-create (or fetch) the CKShare so we can initialize the UI controller using the
        // modern `UICloudSharingController(share:container:)` initializer and avoid the
        // deprecated preparation-handler initializer and its closure captures.
        let savedShare: CKShare
        do {
            savedShare = try await createShare(for: record)
            ShareDebugStore.shared.appendLog("makeCloudSharingController: obtained CKShare id=\(savedShare.recordID.recordName)")
        } catch {
            ShareDebugStore.shared.appendLog("makeCloudSharingController: failed to obtain share: \(error)")
            throw enrichCloudKitError(error)
        }

        let controller = UICloudSharingController(share: savedShare, container: container)
        controller.delegate = delegate
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        controller.title = "Shared Medical Record"
        return controller
    }
#endif

    // MARK: - Deletion

    // Convenience compatibility wrapper for earlier API name
    func deleteCloudRecord(for record: MedicalRecord) async throws {
        try await deleteSyncRecord(forLocalRecord: record)
    }

    func deleteSyncRecord(forLocalRecord record: MedicalRecord) async throws {
        let recordName = record.cloudRecordName ?? record.uuid
        let ckID = CKRecord.ID(recordName: recordName)

        // First try to delete by record ID directly
        do {
            let deleted = try await database.deleteRecord(withID: ckID)
            print("[CloudSyncService] Deleted CloudKit record id=\(deleted.recordName) for local record=\(record.uuid)")
            return
        } catch {
            print("[CloudSyncService] Direct delete failed for CloudKit record id=\(ckID.recordName): \(error)")
            // Try to enrich and rethrow the error
            // We'll fall through to fallback query approach instead of rethrowing here
        }

        // Fallback: delete by matching uuid field
        let predicate = NSPredicate(format: "uuid == %@", record.uuid)
        let query = CKQuery(recordType: medicalRecordType, predicate: predicate)

        // Run the query operation and collect matched record IDs using a continuation
        let idsToDelete: [CKRecord.ID] = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecord.ID], Error>) in
            var foundIDs: [CKRecord.ID] = []
            let op = CKQueryOperation(query: query)
            op.recordMatchedBlock = { (matchedID: CKRecord.ID, matchedResult: Result<CKRecord, Error>) in
                switch matchedResult {
                case .success(let rec): foundIDs.append(rec.recordID)
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }
            op.queryResultBlock = { (result: Result<CKQueryOperation.Cursor?, Error>) in
                switch result {
                case .success(_): cont.resume(returning: foundIDs)
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            database.add(op)
        }

        if !idsToDelete.isEmpty {
            // Delete found records (can delete multiple matches just in case)
            for id in idsToDelete {
                do {
                    let deleted = try await database.deleteRecord(withID: id)
                    print("[CloudSyncService] Deleted CloudKit record id=\(deleted.recordName) via uuid match for local uuid=\(record.uuid)")
                } catch {
                    print("[CloudSyncService] Failed to delete matched CloudKit record id=\(id.recordName): \(error)")
                    throw enrichCloudKitError(error)
                }
            }
        } else {
            // nothing found to delete - not an error
            print("[CloudSyncService] No CloudKit record found matching uuid=\(record.uuid)")
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
        print("CloudKit sharing failed: \(error)")
        onComplete?(.failure(error))
    }
    func cloudSharingControllerDidSaveShare(_ c: UICloudSharingController) {
        print("CloudKit share saved: \(String(describing: c.share?.url))")
        onComplete?(.success(c.share?.url))
    }
    func cloudSharingControllerDidStopSharing(_ c: UICloudSharingController) {
        print("CloudKit sharing stopped")
        onComplete?(.success(nil))
    }
    func itemTitle(for c: UICloudSharingController) -> String? { "Shared Medical Record" }
    func itemThumbnailData(for c: UICloudSharingController) -> Data? { nil }
    func itemType(for c: UICloudSharingController) -> String? { "public.data" }
}
#endif
