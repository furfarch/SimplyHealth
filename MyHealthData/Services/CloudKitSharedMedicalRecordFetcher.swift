import Foundation
import CloudKit
import SwiftData

/// Fetches MedicalRecord records from the CloudKit Shared database and merges them into local SwiftData.
@MainActor
final class CloudKitSharedMedicalRecordFetcher {
    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "MedicalRecord"
    private var modelContext: ModelContext?

    init(containerIdentifier: String = "iCloud.com.furfarch.MyHealthData", modelContext: ModelContext? = nil) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.sharedCloudDatabase
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func fetchAllSharedAsync() async throws -> Int {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let op = CKQueryOperation(query: query)

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

    private func importToSwiftData(records: [CKRecord]) {
        guard let context = modelContext else {
            ShareDebugStore.shared.appendLog("CloudKitSharedMedicalRecordFetcher: no modelContext set; skipping import")
            return
        }

        for ckRecord in records {
            guard let uuid = ckRecord["uuid"] as? String else { continue }

            let cloudUpdatedAt = (ckRecord["updatedAt"] as? Date) ?? Date.distantPast

            let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.uuid == uuid })
            let existing = (try? context.fetch(fetchDescriptor))?.first

            if let existing, existing.updatedAt > cloudUpdatedAt {
                continue
            }

            let record = existing ?? MedicalRecord(uuid: uuid)

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

            // Mark as shared/imported
            record.isCloudEnabled = true
            record.cloudRecordName = ckRecord.recordID.recordName

            if existing == nil {
                context.insert(record)
            }
        }

        do {
            try context.save()
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitSharedMedicalRecordFetcher: failed saving import: \(error)")
        }
    }
}
