import Foundation
import CloudKit
import Combine

/// Fetches MedicalRecord records from CloudKit (private database by default).
@MainActor
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
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                fetched.append(record)
            case .failure(let err):
                print("CloudKit fetch error for recordID \(recordID): \(err)")
            }
        }
        operation.queryResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success:
                    self?.records = fetched
                case .failure(let err):
                    self?.error = err
                }
            }
        }
        database.add(operation)
    }
}
