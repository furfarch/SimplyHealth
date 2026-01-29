//
//  PurusHealthApp.swift
//  Purus Health
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

@main
struct PurusHealthApp: App {
    private let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase: ScenePhase

    // Keep a single fetcher instance alive for the app lifetime.
    private let cloudFetcher: CloudKitMedicalRecordFetcher

    init() {
        let schema = Schema([
            MedicalRecord.self,
            BloodEntry.self,
            DrugEntry.self,
            VaccinationEntry.self,
            AllergyEntry.self,
            IllnessEntry.self,
            RiskEntry.self,
            MedicalHistoryEntry.self,
            MedicalDocumentEntry.self,
            EmergencyContact.self,
            WeightEntry.self,
            HumanDoctorEntry.self,
            PetYearlyCostEntry.self
        ])

        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        self.cloudFetcher = CloudKitMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID)

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            // Failed to create persistent ModelContainer — falling back to in-memory container for safety in older/unsupported environments.
            let memoryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            self.modelContainer = try! ModelContainer(for: schema, configurations: [memoryConfig])
        }

        // Ensure the fetcher has the model context so imports can run
        self.cloudFetcher.setModelContext(self.modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.modelContext, modelContainer.mainContext)
                .task {
                    // Only trigger cloud fetch if user has enabled cloud sync or has cloud-enabled records.
                    // This prevents re-importing records that were deleted locally when cloud sync is off.
                    if await shouldFetchFromCloud() {
                        cloudFetcher.fetchChanges()
                    }

                    // Only fetch shared records if there are existing shared records locally.
                    // New shares are handled by the share acceptance flow (onOpenURL).
                    if await hasSharedRecordsLocally() {
                        await fetchSharedRecordsOnLaunch()
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    // Sync when app becomes active to get latest changes
                    if newPhase == .active {
                        Task { @MainActor in
                            // Only sync if user has cloud-enabled records
                            if await shouldFetchFromCloud() {
                                cloudFetcher.fetchChanges()
                                await syncCloudEnabledRecords()
                            }

                            // Only fetch shared records if there are existing shared records locally
                            if await hasSharedRecordsLocally() {
                                await fetchSharedRecordsOnLaunch()
                            }
                        }
                    }
                }
        }
        .modelContainer(modelContainer)
    }
    
    /// Returns true if cloud sync should be performed (user has enabled cloud sync or has cloud-enabled records).
    @MainActor
    private func shouldFetchFromCloud() async -> Bool {
        // Check global cloud setting
        let globalCloudEnabled = UserDefaults.standard.bool(forKey: "cloudEnabled")
        if globalCloudEnabled { return true }

        // Check if any local records are cloud-enabled
        let context = modelContainer.mainContext
        let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.isCloudEnabled == true })
        let count = (try? context.fetchCount(fetchDescriptor)) ?? 0
        return count > 0
    }

    /// Returns true if there are shared records locally that need to be updated.
    @MainActor
    private func hasSharedRecordsLocally() async -> Bool {
        let context = modelContainer.mainContext
        let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.isSharingEnabled == true })
        let count = (try? context.fetchCount(fetchDescriptor)) ?? 0
        return count > 0
    }

    @MainActor
    private func syncCloudEnabledRecords() async {
        let context = modelContainer.mainContext
        let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.isCloudEnabled == true })
        
        guard let records = try? context.fetch(fetchDescriptor) else { return }
        
        for record in records {
            do {
                try await CloudSyncService.shared.syncIfNeeded(record: record)
            } catch {
                // Best-effort: log error but continue syncing other records
                ShareDebugStore.shared.appendLog("PurusHealthApp: failed to sync record \(record.uuid): \(error)")
            }
        }
    }
    
    @MainActor
    private func fetchSharedRecordsOnLaunch() async {
        do {
            let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(
                containerIdentifier: AppConfig.CloudKit.containerID,
                modelContext: modelContainer.mainContext
            )
            _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
        } catch {
            // Best-effort: log but don't fail the app
            ShareDebugStore.shared.appendLog("PurusHealthApp: failed to fetch shared records on launch: \(error)")
        }
    }
}
