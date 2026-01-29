import Foundation
import CloudKit
import SwiftData

/// Accepts a CloudKit share invitation and imports the shared root record so it appears in the app.
@MainActor
final class CloudKitShareAcceptanceService {
    static let shared = CloudKitShareAcceptanceService()

    private let containerIdentifier = AppConfig.CloudKit.containerID
    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }

    private init() {}

    func acceptShare(from url: URL, modelContext: ModelContext) async {
        ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: acceptShare url=\(url.absoluteString)")

        do {
            let metadata = try await fetchShareMetadata(for: url)
            try await acceptShareMetadata(metadata)

            let sharedDB = container.sharedCloudDatabase

            // Fetch just the shared root record (so it appears immediately).
            let rootID = Self.rootRecordID(from: metadata)
            let recordsByID = try await fetchRecords(by: [rootID], from: sharedDB)

            // Best-effort: also fetch the share record for participant display.
            var fetchedShare: CKShare?
            do {
                let shareByID = try await fetchRecords(by: [metadata.share.recordID], from: sharedDB)
                fetchedShare = shareByID[metadata.share.recordID] as? CKShare
            } catch {
                ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: unable to fetch CKShare for participants: \(error)")
            }

            let importedNames = try CloudKitSharedImporter.upsertSharedMedicalRecords(
                recordsByID.values,
                share: fetchedShare,
                modelContext: modelContext
            )

            ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: import complete (count=\(recordsByID.count))")

            // Post notification so ContentView can refresh and show the imported records
            NotificationCenter.default.post(
                name: NotificationNames.didAcceptShare,
                object: nil,
                userInfo: ["names": importedNames]
            )
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: accept failed error=\(error)")
            ShareDebugStore.shared.lastError = error
        }
    }

    private static func rootRecordID(from metadata: CKShare.Metadata) -> CKRecord.ID {
        // CloudKit sharing has been iOS 16+ for our acceptance flow.
        if #available(iOS 16.0, macOS 13.0, *) {
            if let id = metadata.hierarchicalRootRecordID { return id }
            // If this ever happens, we can't safely resolve the root record.
            return metadata.share.recordID
        }

        // Older OS versions are not supported for sharing flow.
        return metadata.share.recordID
    }

    // MARK: - CloudKit helpers

    private func fetchShareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CKShare.Metadata, Error>) in
            let op = CKFetchShareMetadataOperation(shareURLs: [url])
            var captured: CKShare.Metadata?

            op.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let md):
                    captured = md
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            op.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let md = captured {
                        cont.resume(returning: md)
                    } else {
                        cont.resume(throwing: NSError(domain: "CloudKitShareAcceptanceService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No share metadata returned."]))
                    }
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            self.container.add(op)
        }
    }

    private func acceptShareMetadata(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.qualityOfService = .userInitiated

            op.perShareResultBlock = { md, result in
                switch result {
                case .success(let share):
                    ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: perShare success share=\(share.recordID.recordName) container=\(md.containerIdentifier)")
                case .failure(let err):
                    ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: perShare error=\(err)")
                }
            }

            op.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: ())
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            self.container.add(op)
        }
    }

    private func fetchRecords(by ids: [CKRecord.ID], from database: CKDatabase) async throws -> [CKRecord.ID: CKRecord] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecord.ID: CKRecord], Error>) in
            let op = CKFetchRecordsOperation(recordIDs: ids)
            var fetched: [CKRecord.ID: CKRecord] = [:]

            op.perRecordResultBlock = { recordID, result in
                if case .success(let rec) = result { fetched[recordID] = rec }
            }

            op.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: fetched)
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            database.add(op)
        }
    }
}

@MainActor
private enum CloudKitSharedImporter {
    /// Upserts shared medical records and returns the display names of imported records.
    /// Throws if the save fails so callers can handle the error appropriately.
    @discardableResult
    static func upsertSharedMedicalRecords(_ ckRecords: some Sequence<CKRecord>, share: CKShare?, modelContext: ModelContext) throws -> [String] {
        var importedNames: [String] = []
        for ckRecord in ckRecords {
            guard ckRecord.recordType == "MedicalRecord" else { continue }
            guard let uuid = ckRecord["uuid"] as? String else { continue }

            let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.uuid == uuid })
            let existing = (try? modelContext.fetch(fetchDescriptor))?.first
            let record = existing ?? MedicalRecord(uuid: uuid)

            record.createdAt = ckRecord["createdAt"] as? Date ?? record.createdAt
            record.updatedAt = (ckRecord["updatedAt"] as? Date) ?? record.updatedAt

            record.personalFamilyName = ckRecord["personalFamilyName"] as? String ?? ""
            record.personalGivenName = ckRecord["personalGivenName"] as? String ?? ""
            record.personalNickName = ckRecord["personalNickName"] as? String ?? ""
            record.personalGender = ckRecord["personalGender"] as? String ?? ""
            record.personalBirthdate = ckRecord["personalBirthdate"] as? Date
            record.personalSocialSecurityNumber = ckRecord["personalSocialSecurityNumber"] as? String ?? ""
            record.personalAddress = ckRecord["personalAddress"] as? String ?? ""
            record.personalHealthInsurance = ckRecord["personalHealthInsurance"] as? String ?? ""
            record.personalHealthInsuranceNumber = ckRecord["personalHealthInsuranceNumber"] as? String ?? ""
            record.personalEmployer = ckRecord["personalEmployer"] as? String ?? ""

            if let boolVal = ckRecord["isPet"] as? Bool {
                record.isPet = boolVal
            } else if let num = ckRecord["isPet"] as? NSNumber {
                record.isPet = num.boolValue
            }

            record.personalName = ckRecord["personalName"] as? String ?? ""
            record.personalAnimalID = ckRecord["personalAnimalID"] as? String ?? ""
            record.ownerName = ckRecord["ownerName"] as? String ?? ""
            record.ownerPhone = ckRecord["ownerPhone"] as? String ?? ""
            record.ownerEmail = ckRecord["ownerEmail"] as? String ?? ""
            record.emergencyName = ckRecord["emergencyName"] as? String ?? ""
            record.emergencyNumber = ckRecord["emergencyNumber"] as? String ?? ""
            record.emergencyEmail = ckRecord["emergencyEmail"] as? String ?? ""

            // Shared records should ALWAYS be marked as cloud-enabled since they exist in CloudKit,
            // regardless of whether the user has enabled global cloud sync for their own records.
            record.isCloudEnabled = true
            record.isSharingEnabled = true
            record.cloudRecordName = ckRecord.recordID.recordName

            if let shareRef = ckRecord.share {
                record.cloudShareRecordName = shareRef.recordID.recordName
            } else {
                record.cloudShareRecordName = share?.recordID.recordName
            }

            if let share {
                record.shareParticipantsSummary = participantsSummary(from: share)
            }

            if existing == nil {
                modelContext.insert(record)
            }

            // Capture the display name for the notification
            importedNames.append(record.displayName)
        }

        do {
            try modelContext.save()
            ShareDebugStore.shared.appendLog("CloudKitSharedImporter: successfully saved \(importedNames.count) record(s)")
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitSharedImporter: FAILED saving import: \(error)")
            // Re-throw to inform callers that the import failed - critical for proper error handling
            throw error
        }

        return importedNames
    }

    private static func participantsSummary(from share: CKShare) -> String {
        let parts: [String] = share.participants.compactMap { p in
            if let email = p.userIdentity.lookupInfo?.emailAddress, !email.isEmpty {
                return email
            }
            return p.userIdentity.userRecordID?.recordName
        }
        return parts.isEmpty ? "Only you" : parts.joined(separator: ", ")
    }
}
