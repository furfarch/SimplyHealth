import Foundation
import SwiftData
import CloudKit
import UIKit

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
        // Ensure record exists in CloudKit
        try await syncIfNeeded(record: record)

        let recordName = record.cloudRecordName ?? record.uuid
        let rootID = CKRecord.ID(recordName: recordName)
        let root = try await database.record(for: rootID)

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Shared Medical Record" as CKRecordValue

        let modify = CKModifyRecordsOperation(recordsToSave: [root, share], recordIDsToDelete: nil)
        modify.savePolicy = .changedKeys

        return try await withCheckedThrowingContinuation { cont in
            modify.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: share)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
            self.database.add(modify)
        }
    }

    // MARK: - UICloudSharingController Integration

    func makeCloudSharingController(for record: MedicalRecord, onComplete: @escaping (Result<URL?, Error>) -> Void) async throws -> UICloudSharingController {
        let recordName = record.cloudRecordName ?? record.uuid
        let rootID = CKRecord.ID(recordName: recordName)
        let container = CKContainer(identifier: containerIdentifier)

        // Ensure record exists in CloudKit
        try await syncIfNeeded(record: record)

        // Fetch the root record from CloudKit
        let root = try await database.record(for: rootID)
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Shared Medical Record" as CKRecordValue

        let modify = CKModifyRecordsOperation(recordsToSave: [root, share], recordIDsToDelete: nil)
        modify.savePolicy = .changedKeys

        // Save the share to CloudKit
        try await withCheckedThrowingContinuation { [unowned self] cont in
            modify.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: ())
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
            self.database.add(modify)
        }

        let delegate = CloudSharingDelegate()
        delegate.onComplete = onComplete
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = delegate
        controller.modalPresentationStyle = .formSheet
        controller.title = "Shared Medical Record"
        return controller
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
}

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
