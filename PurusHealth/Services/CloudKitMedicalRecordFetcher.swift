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
    // Must match CloudSyncService.medicalRecordType
    private let recordType = "MedicalRecord"
    private var modelContext: ModelContext?

    // Keep in sync with CloudSyncService.shareZoneName
    private let shareZoneName = AppConfig.CloudKit.shareZoneName
    private var shareZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: shareZoneName, ownerName: CKCurrentUserDefaultName)
    }

    // Persist the server change token so we can fetch incremental changes.
    private let changeTokenDefaultsKey = "CloudKitMedicalRecordFetcher.shareZoneChangeToken"
    
    private let privateDBSubscriptionID = "MedicalRecordPrivateZoneChanges"

    init(containerIdentifier: String? = nil, modelContext: ModelContext? = nil) {
        let resolvedIdentifier = containerIdentifier ?? AppConfig.CloudKit.containerID
        self.container = CKContainer(identifier: resolvedIdentifier)
        self.database = container.privateCloudDatabase
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func ensurePrivateDBSubscription() async {
        do {
            let sub = CKDatabaseSubscription(subscriptionID: privateDBSubscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            sub.notificationInfo = info
            try await database.save(sub)
            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: ensured private DB subscription")
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: failed to ensure private DB subscription: \(error)")
        }
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
                // Clear suppression on confirmed cloud deletion
                SharedImportSuppression.clear(existing.uuid)
            }
        }

        do {
            try context.save()
            // Nudge UI to refresh immediately after deletions
            context.processPendingChanges()
            Task { @MainActor in
                NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
            }
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
            record.petBreed = ckRecord["petBreed"] as? String ?? ""
            record.petColor = ckRecord["petColor"] as? String ?? ""
            record.ownerName = ckRecord["ownerName"] as? String ?? ""
            record.ownerPhone = ckRecord["ownerPhone"] as? String ?? ""
            record.ownerEmail = ckRecord["ownerEmail"] as? String ?? ""
            
            // Veterinary fields
            record.vetClinicName = ckRecord["vetClinicName"] as? String ?? ""
            record.vetContactName = ckRecord["vetContactName"] as? String ?? ""
            record.vetPhone = ckRecord["vetPhone"] as? String ?? ""
            record.vetEmail = ckRecord["vetEmail"] as? String ?? ""
            record.vetAddress = ckRecord["vetAddress"] as? String ?? ""
            record.vetNote = ckRecord["vetNote"] as? String ?? ""
            
            record.emergencyName = ckRecord["emergencyName"] as? String ?? ""
            record.emergencyNumber = ckRecord["emergencyNumber"] as? String ?? ""
            record.emergencyEmail = ckRecord["emergencyEmail"] as? String ?? ""

            // Deserialize relationship arrays from JSON
            // Blood entries
            if let bloodString = ckRecord["bloodEntries"] as? String,
               let bloodData = bloodString.data(using: .utf8),
               let codableBlood = try? JSONDecoder().decode([CodableBloodEntry].self, from: bloodData) {
                // Clear existing entries
                for entry in record.blood {
                    context.delete(entry)
                }
                record.blood = codableBlood.map { codable in
                    BloodEntry(date: codable.date.map { Date(timeIntervalSince1970: $0) }, name: codable.name, comment: codable.comment, record: record)
                }
            }
            
            // Drug entries
            if let drugsString = ckRecord["drugEntries"] as? String,
               let drugsData = drugsString.data(using: .utf8),
               let codableDrugs = try? JSONDecoder().decode([CodableDrugEntry].self, from: drugsData) {
                for entry in record.drugs {
                    context.delete(entry)
                }
                record.drugs = codableDrugs.map { codable in
                    DrugEntry(date: codable.date.map { Date(timeIntervalSince1970: $0) }, nameAndDosage: codable.nameAndDosage, comment: codable.comment, record: record)
                }
            }
            
            // Vaccination entries
            if let vaccinationsString = ckRecord["vaccinationEntries"] as? String,
               let vaccinationsData = vaccinationsString.data(using: .utf8),
               let codableVaccinations = try? JSONDecoder().decode([CodableVaccinationEntry].self, from: vaccinationsData) {
                for entry in record.vaccinations {
                    context.delete(entry)
                }
                record.vaccinations = codableVaccinations.map { codable in
                    VaccinationEntry(date: codable.date.map { Date(timeIntervalSince1970: $0) }, name: codable.name, information: codable.information, place: codable.place, comment: codable.comment, record: record)
                }
            }
            
            // Allergy entries
            if let allergyString = ckRecord["allergyEntries"] as? String,
               let allergyData = allergyString.data(using: .utf8),
               let codableAllergy = try? JSONDecoder().decode([CodableAllergyEntry].self, from: allergyData) {
                for entry in record.allergy {
                    context.delete(entry)
                }
                record.allergy = codableAllergy.map { codable in
                    AllergyEntry(date: codable.date.map { Date(timeIntervalSince1970: $0) }, name: codable.name, information: codable.information, comment: codable.comment, record: record)
                }
            }
            
            // Illness entries
            if let illnessString = ckRecord["illnessEntries"] as? String,
               let illnessData = illnessString.data(using: .utf8),
               let codableIllness = try? JSONDecoder().decode([CodableIllnessEntry].self, from: illnessData) {
                for entry in record.illness {
                    context.delete(entry)
                }
                record.illness = codableIllness.map { codable in
                    IllnessEntry(date: codable.date.map { Date(timeIntervalSince1970: $0) }, name: codable.name, informationOrComment: codable.informationOrComment, record: record)
                }
            }
            
            // Risk entries
            if let risksString = ckRecord["riskEntries"] as? String,
               let risksData = risksString.data(using: .utf8),
               let codableRisks = try? JSONDecoder().decode([CodableRiskEntry].self, from: risksData) {
                for entry in record.risks {
                    context.delete(entry)
                }
                record.risks = codableRisks.map { codable in
                    RiskEntry(date: codable.date.map { Date(timeIntervalSince1970: $0) }, name: codable.name, descriptionOrComment: codable.descriptionOrComment, record: record)
                }
            }
            
            // Medical history entries
            if let historyString = ckRecord["medicalHistoryEntries"] as? String,
               let historyData = historyString.data(using: .utf8),
               let codableHistory = try? JSONDecoder().decode([CodableMedicalHistoryEntry].self, from: historyData) {
                for entry in record.medicalhistory {
                    context.delete(entry)
                }
                record.medicalhistory = codableHistory.map { codable in
                    MedicalHistoryEntry(date: codable.date.map { Date(timeIntervalSince1970: $0) }, name: codable.name, contact: codable.contact, informationOrComment: codable.informationOrComment, record: record)
                }
            }
            
            // Medical document entries
            if let documentString = ckRecord["medicalDocumentEntries"] as? String,
               let documentData = documentString.data(using: .utf8),
               let codableDocuments = try? JSONDecoder().decode([CodableMedicalDocumentEntry].self, from: documentData) {
                for entry in record.medicaldocument {
                    context.delete(entry)
                }
                record.medicaldocument = codableDocuments.map { codable in
                    MedicalDocumentEntry(date: codable.date.map { Date(timeIntervalSince1970: $0) }, name: codable.name, note: codable.note, record: record)
                }
            }
            
            // Human doctor entries
            if let doctorsString = ckRecord["humanDoctorEntries"] as? String,
               let doctorsData = doctorsString.data(using: .utf8),
               let codableDoctors = try? JSONDecoder().decode([CodableHumanDoctorEntry].self, from: doctorsData) {
                for entry in record.humanDoctors {
                    context.delete(entry)
                }
                record.humanDoctors = codableDoctors.map { codable in
                    HumanDoctorEntry(uuid: codable.uuid, createdAt: Date(timeIntervalSince1970: codable.createdAt), updatedAt: Date(timeIntervalSince1970: codable.updatedAt), type: codable.type, name: codable.name, phone: codable.phone, email: codable.email, address: codable.address, note: codable.note, record: record)
                }
            }
            
            // Weight entries
            if let weightsString = ckRecord["weightEntries"] as? String,
               let weightsData = weightsString.data(using: .utf8),
               let codableWeights = try? JSONDecoder().decode([CodableWeightEntry].self, from: weightsData) {
                for entry in record.weights {
                    context.delete(entry)
                }
                record.weights = codableWeights.map { codable in
                    WeightEntry(uuid: codable.uuid, createdAt: Date(timeIntervalSince1970: codable.createdAt), updatedAt: Date(timeIntervalSince1970: codable.updatedAt), date: codable.date.map { Date(timeIntervalSince1970: $0) }, weightKg: codable.weightKg, comment: codable.comment, record: record)
                }
            }
            
            // Pet yearly cost entries
            if let petCostsString = ckRecord["petYearlyCostEntries"] as? String,
               let petCostsData = petCostsString.data(using: .utf8),
               let codablePetCosts = try? JSONDecoder().decode([CodablePetYearlyCostEntry].self, from: petCostsData) {
                for entry in record.petYearlyCosts {
                    context.delete(entry)
                }
                record.petYearlyCosts = codablePetCosts.map { codable in
                    PetYearlyCostEntry(uuid: codable.uuid, createdAt: Date(timeIntervalSince1970: codable.createdAt), updatedAt: Date(timeIntervalSince1970: codable.updatedAt), date: Date(timeIntervalSince1970: codable.date), year: codable.year, category: codable.category, amount: codable.amount, note: codable.note, record: record)
                }
            }
            
            // Emergency contacts
            if let emergencyContactsString = ckRecord["emergencyContactEntries"] as? String,
               let emergencyContactsData = emergencyContactsString.data(using: .utf8),
               let codableEmergencyContacts = try? JSONDecoder().decode([CodableEmergencyContact].self, from: emergencyContactsData) {
                for entry in record.emergencyContacts {
                    context.delete(entry)
                }
                record.emergencyContacts = codableEmergencyContacts.map { codable in
                    EmergencyContact(id: UUID(uuidString: codable.id) ?? UUID(), name: codable.name, phone: codable.phone, email: codable.email, note: codable.note, record: record)
                }
            }

            // Map private DB share reference to local sharing flags for owner’s other devices
            if let shareRef = ckRecord.share {
                record.isSharingEnabled = true
                record.cloudShareRecordName = shareRef.recordID.recordName
            }

            // Read isSharingEnabled mirrored as Int64 (0/1) from CloudKit if present
            if let num = ckRecord["isSharingEnabled"] as? NSNumber {
                record.isSharingEnabled = (num.int64Value != 0)
            }

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
            // Nudge UI to refresh immediately after imports
            context.processPendingChanges()
            Task { @MainActor in
                NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
            }
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

@MainActor
func ensureSharedDBSubscription(containerIdentifier: String) async {
    let container = CKContainer(identifier: containerIdentifier)
    let sharedDB = container.sharedCloudDatabase
    let subID = "MedicalRecordSharedDBChanges"
    do {
        let sub = CKDatabaseSubscription(subscriptionID: subID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        sub.notificationInfo = info
        try await sharedDB.save(sub)
        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: ensured shared DB subscription")
    } catch {
        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: failed to ensure shared DB subscription: \(error)")
    }
}
