import Foundation
import CloudKit
import SwiftData

/// Fetches MedicalRecord records from the CloudKit Shared database by iterating record zones.
///
/// Why this exists
/// Shared records live in *shared record zones* (often one zone per share). A plain query against
/// `sharedCloudDatabase` without supplying `zoneID` can miss results or behave inconsistently.
@MainActor
final class CloudKitSharedZoneMedicalRecordFetcher {
    private let container: CKContainer
    private let database: CKDatabase
    private var modelContext: ModelContext?

    // Keep in sync with the owner's record type.
    private let recordType = AppConfig.CloudKit.recordType

    init(containerIdentifier: String = AppConfig.CloudKit.containerID, modelContext: ModelContext? = nil) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.sharedCloudDatabase
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// Fetch shared records across all shared record zones and merge them into SwiftData.
    /// Returns the number of fetched records.
    func fetchAllSharedAcrossZonesAsync() async throws -> Int {
        let zones = try await fetchAllRecordZones()
        guard !zones.isEmpty else { return 0 }

        var totalFetched = 0
        for zone in zones {
            totalFetched += try await fetchAllShared(in: zone.zoneID)
        }
        return totalFetched
    }

    // MARK: - Zones

    private func fetchAllRecordZones() async throws -> [CKRecordZone] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecordZone], Error>) in
            database.fetchAllRecordZones { zones, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: zones ?? [])
            }
        }
    }

    // MARK: - Query

    private func fetchAllShared(in zoneID: CKRecordZone.ID) async throws -> Int {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let op = CKQueryOperation(query: query)
        op.zoneID = zoneID

        var fetched: [CKRecord] = []
        op.recordMatchedBlock = { _, result in
            if case .success(let rec) = result { fetched.append(rec) }
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            op.queryResultBlock = { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        guard let self else { cont.resume(returning: 0); return }
                        self.importToSwiftData(records: fetched)
                        cont.resume(returning: fetched.count)
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
            }
            database.add(op)
        }
    }

    // MARK: - Import

    private func importToSwiftData(records: [CKRecord]) {
        guard let context = modelContext else {
            ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: no modelContext set; skipping import")
            return
        }

        for ckRecord in records {
            guard let uuid = ckRecord["uuid"] as? String else { continue }

            let cloudUpdatedAt = (ckRecord["updatedAt"] as? Date) ?? Date.distantPast

            let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.uuid == uuid })
            let existing = (try? context.fetch(fetchDescriptor))?.first

            if let existing, existing.updatedAt > cloudUpdatedAt {
                ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: skipping stale cloud record uuid=\(uuid) (local=\(existing.updatedAt), cloud=\(cloudUpdatedAt))")
                continue
            }

            let record = existing ?? MedicalRecord(uuid: uuid)
            
            if existing != nil {
                ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: updating existing record uuid=\(uuid)")
            } else {
                ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: creating new record uuid=\(uuid)")
            }

            record.createdAt = ckRecord["createdAt"] as? Date ?? record.createdAt
            record.updatedAt = cloudUpdatedAt

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

            // Shared records should always be marked as shared.
            record.isSharingEnabled = true
            record.cloudRecordName = ckRecord.recordID.recordName

            if let shareRef = ckRecord.share {
                record.cloudShareRecordName = shareRef.recordID.recordName
            }

            // Do NOT stomp a user's per-record cloud syncing preference. Shared visibility is independent.
            // (locationStatus uses cloudShareRecordName/isSharingEnabled to show the shared badge.)

            if existing == nil {
                context.insert(record)
            }
        }

        // Process pending changes before saving to ensure all modifications are tracked
        context.processPendingChanges()

        do {
            try context.save()
            ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: successfully saved \(records.count) record(s)")
            
            // Post notification to trigger UI refresh (ensure on MainActor for thread safety)
            Task { @MainActor in
                NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
            }
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: failed saving import: \(error)")
        }
    }
}
