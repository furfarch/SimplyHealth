import Foundation
import CloudKit
import SwiftData
import Combine

@MainActor
/// Fetches MedicalRecord records from CloudKit (private database by default).
class CloudKitMedicalRecordFetcher: ObservableObject {
    @Published var records: [CKRecord] = []
    @Published var error: Error?
    @Published var isLoading: Bool = false

    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "MedicalRecord"
    private var modelContext: ModelContext?

    init(containerIdentifier: String = "iCloud.com.furfarch.MyHealthData", modelContext: ModelContext? = nil) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func fetchAll() {
        isLoading = true
        error = nil
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        var fetched: [CKRecord] = []
        operation.recordFetchedBlock = { record in
            fetched.append(record)
        }
        operation.queryCompletionBlock = { [weak self] _, err in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let err = err {
                    self?.error = err
                } else {
                    self?.records = fetched
                    // Automatic import to SwiftData for true sync
                    if let context = self?.modelContext {
                        self?.importToSwiftData(context: context)
                    }
                }
            }
        }
        database.add(operation)
    }

    /// Import fetched CKRecords into the local SwiftData store as MedicalRecord objects.
    func importToSwiftData(context: ModelContext) {
        // Build set of UUIDs present in CloudKit
        let cloudUUIDs: Set<String> = Set(records.compactMap { $0["uuid"] as? String })

        for ckRecord in records {
            guard let uuid = ckRecord["uuid"] as? String else { continue }
            // Try to find an existing record by uuid
            let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.uuid == uuid })
            let existing = (try? context.fetch(fetchDescriptor))?.first
            let record = existing ?? MedicalRecord(uuid: uuid)
            // Map fields
            record.createdAt = ckRecord["createdAt"] as? Date ?? Date()
            record.updatedAt = ckRecord["updatedAt"] as? Date ?? Date()
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
            // 'isPet' in your model may be Bool or Int; try Bool then Number
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
            record.isCloudEnabled = true
            record.cloudRecordName = ckRecord.recordID.recordName
            if existing == nil {
                context.insert(record)
            }
        }

        // Handle remote deletions: for local records that are marked cloud-enabled but their uuid is missing in CloudKit,
        // clear cloud flags so they remain local-only (safer than automatic deletion).
        do {
            let cloudEnabledFetch = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.isCloudEnabled == true })
            let localCloudRecords = try context.fetch(cloudEnabledFetch)
            for local in localCloudRecords {
                if !cloudUUIDs.contains(local.uuid) {
                    // remote deleted — keep local data but disable cloud sync for this record
                    local.isCloudEnabled = false
                    local.cloudRecordName = nil
                }
            }
            try context.save()
        } catch {
            print("Failed to reconcile remote deletions: \(error)")
        }
    }
}
