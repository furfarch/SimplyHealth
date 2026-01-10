import Foundation
import CloudKit
import SwiftData

/// Fetches MedicalRecord records from CloudKit (private database by default).
class CloudKitMedicalRecordFetcher: ObservableObject {
    @Published var records: [CKRecord] = []
    @Published var error: Error?
    @Published var isLoading: Bool = false

    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "MedicalRecord"

    init(containerIdentifier: String = "iCloud.com.furfarch.MyHealthData") {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
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
                }
            }
        }
        database.add(operation)
    }
}

extension CloudKitMedicalRecordFetcher {
    /// Import fetched CKRecords into the local SwiftData store as MedicalRecord objects.
    func importToSwiftData(context: ModelContext) {
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
            record.isPet = ckRecord["isPet"] as? Bool ?? false
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
        try? context.save()
    }
}
