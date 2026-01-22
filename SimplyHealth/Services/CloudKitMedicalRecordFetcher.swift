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
    private let recordType = AppConfig.CloudKit.recordType
    private var modelContext: ModelContext?

    // Keep in sync with CloudSyncService.shareZoneName
    private let shareZoneName = AppConfig.CloudKit.shareZoneName
    private var shareZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: shareZoneName, ownerName: CKCurrentUserDefaultName)
    }

    // Persist the server change token so we can fetch incremental changes.
    private let changeTokenDefaultsKey = "CloudKitMedicalRecordFetcher.shareZoneChangeToken"

    init(containerIdentifier: String = "iCloud.com.furfarch.MyHealthData", modelContext: ModelContext? = nil) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Incremental sync (preferred)

    /// Fetch incremental changes (edits + deletions) from the custom share zone and merge them into SwiftData.
    /// This works WITHOUT push notifications. Call it on:
    /// - user taps Sync
    /// - pull to refresh
    /// - app becomes active
    func fetchChanges() {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        let previousToken = loadChangeToken()
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: previousToken)

        let op = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [shareZoneID],
            configurationsByRecordZoneID: [shareZoneID: configuration]
        )

        var changed: [CKRecord] = []
        var deleted: [CKRecord.ID] = []

        op.recordWasChangedBlock = { (_: CKRecord.ID, result: Result<CKRecord, Error>) in
            switch result {
            case .success(let rec):
                changed.append(rec)
            case .failure(let err):
                ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: recordWasChangedBlock error: \(err)")
            }
        }

        op.recordWithIDWasDeletedBlock = { (recordID: CKRecord.ID, _: String) in
            deleted.append(recordID)
        }

        op.recordZoneChangeTokensUpdatedBlock = { [weak self] zoneID, token, _ in
            guard zoneID == self?.shareZoneID else { return }
            self?.saveChangeToken(token)
        }

        op.recordZoneFetchResultBlock = { [weak self] zoneID, result in
            guard zoneID == self?.shareZoneID else { return }
            switch result {
            case .success(let info):
                self?.saveChangeToken(info.serverChangeToken)
                if info.moreComing {
                    ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: moreComing=true for zone=\(zoneID.zoneName)")
                }
            case .failure(let err):
                ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: zone fetch failed zone=\(zoneID.zoneName) error=\(err)")
            }
        }

        op.fetchRecordZoneChangesResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                switch result {
                case .success:
                    self.applyZoneChanges(changed: changed, deleted: deleted)
                case .failure(let err):
                    // Token expired: clear and retry with full fetch.
                    if let ck = err as? CKError, ck.code == .changeTokenExpired {
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: change token expired; clearing and falling back to full fetch")
                        self.clearChangeToken()
                        self.fetchAll()
                        return
                    }
                    // Zone not found: treat as empty cloud.
                    if let ck = err as? CKError, ck.code == .zoneNotFound {
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: zone not found (\(self.shareZoneName)), treating as empty cloud state")
                        self.records = []
                        return
                    }

                    self.error = err
                    ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: fetchChanges error: \(err)")
                }
            }
        }

        database.add(op)
    }

    private func applyZoneChanges(changed: [CKRecord], deleted: [CKRecord.ID]) {
        guard let context = modelContext else {
            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: no modelContext set; skipping import")
            return
        }

        if !deleted.isEmpty {
            deleteFromSwiftData(recordIDs: deleted, context: context)
        }

        if !changed.isEmpty {
            self.records = changed
            importToSwiftData(context: context)
        }
    }

    private func deleteFromSwiftData(recordIDs: [CKRecord.ID], context: ModelContext) {
        for recordID in recordIDs {
            let recordName = recordID.recordName
            let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate {
                $0.cloudRecordName == recordName || $0.uuid == recordName
            })

            if let existing = (try? context.fetch(fetchDescriptor))?.first {
                context.delete(existing)
            }
        }

        do {
            try context.save()
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: failed saving deletions: \(error)")
        }
    }

    // MARK: - Full fetch (fallback)

    func fetchAll() {
        isLoading = true
        error = nil
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.zoneID = shareZoneID
        var fetched: [CKRecord] = []
        operation.recordMatchedBlock = { (_, result) in
            switch result {
            case .success(let rec):
                fetched.append(rec)
            case .failure(let err):
                ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: recordMatchedBlock error: \(err)")
            }
        }

        operation.queryResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success:
                    self?.records = fetched
                    if let context = self?.modelContext {
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: performing sync/merge of \(fetched.count) records into local store")
                        self?.importToSwiftData(context: context)
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: sync/merge complete for \(fetched.count) records")
                    }
                case .failure(let err):
                    if let ck = err as? CKError, ck.code == .zoneNotFound {
                        let zoneName = self?.shareZoneName ?? ""
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: zone not found (\(zoneName)), treating as empty cloud state")
                        self?.records = []
                        return
                    }
                    self?.error = err
                    ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: queryResultBlock error: \(err)")
                }
            }
        }
        database.add(operation)
    }

    /// Async API: fetch all records and import them into local SwiftData; returns number of fetched records.
    func fetchAllAsync() async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            isLoading = true
            error = nil
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let op = CKQueryOperation(query: query)
            op.zoneID = shareZoneID
            var fetched: [CKRecord] = []

            op.recordMatchedBlock = { (_, result) in
                switch result {
                case .success(let rec): fetched.append(rec)
                case .failure(let err): ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: recordMatchedBlock error: \(err)")
                }
            }

            op.queryResultBlock = { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    switch result {
                    case .success:
                        self?.records = fetched
                        if let context = self?.modelContext {
                            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: (async) performing sync/merge of \(fetched.count) records into local store")
                            self?.importToSwiftData(context: context)
                            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: (async) sync/merge complete for \(fetched.count) records")
                        }
                        continuation.resume(returning: fetched.count)
                    case .failure(let err):
                        if let ck = err as? CKError, ck.code == .zoneNotFound {
                            let zoneName = self?.shareZoneName ?? ""
                            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: (async) zone not found (\(zoneName)), treating as empty cloud state")
                            self?.records = []
                            continuation.resume(returning: 0)
                            return
                        }
                        self?.error = err
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: (async) queryResultBlock error: \(err)")
                        continuation.resume(throwing: err)
                    }
                }
            }

            database.add(op)
        }
    }

    // MARK: - Import

    /// Import fetched CKRecords into the local SwiftData store as MedicalRecord objects.
    func importToSwiftData(context: ModelContext) {
        for ckRecord in records {
            guard let uuid = ckRecord["uuid"] as? String else { continue }

            let cloudUpdatedAt = (ckRecord["updatedAt"] as? Date) ?? Date.distantPast

            let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.uuid == uuid })
            let existing = (try? context.fetch(fetchDescriptor))?.first

            // Prevent stale cloud copies from overwriting newer local edits.
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

            // Respect global iCloud toggle. Importing should not auto-enable cloud for the user.
            let cloudEnabled = UserDefaults.standard.bool(forKey: "cloudEnabled")
            record.isCloudEnabled = cloudEnabled
            record.cloudRecordName = ckRecord.recordID.recordName

            if existing == nil {
                context.insert(record)
            }
        }

        do {
            try context.save()
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: failed saving import: \(error)")
        }
    }

    // MARK: - Change token persistence

    private func saveChangeToken(_ token: CKServerChangeToken?) {
        guard let token else { return }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: changeTokenDefaultsKey)
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: failed to persist change token: \(error)")
        }
    }

    private func loadChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenDefaultsKey) else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: failed to unarchive change token: \(error)")
            return nil
        }
    }

    private func clearChangeToken() {
        UserDefaults.standard.removeObject(forKey: changeTokenDefaultsKey)
    }
}
