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
                    // Best-effort: trigger import of any pending cloud/shared changes on launch
                    cloudFetcher.fetchChanges()
                    
                    // Also fetch shared records on launch
                    Task { @MainActor in
                        await fetchSharedRecordsOnLaunch()
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    // Sync when app becomes active to get latest changes
                    if newPhase == .active {
                        cloudFetcher.fetchChanges()
                        
                        // Also sync cloud-enabled records to push local changes
                        Task { @MainActor in
                            await syncCloudEnabledRecords()
                            await fetchSharedRecordsOnLaunch()
                        }
                    }
                }
        }
        .modelContainer(modelContainer)
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
