//
//  MyHealthDataApp.swift
//  MyHealthData
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

@main
struct MyHealthDataApp: App {
    private let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase: ScenePhase

    #if canImport(UIKit)
    // Register AppDelegate to capture incoming URLs/user activities before SwiftUI scene is ready
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    // Keep a single fetcher instance alive for the app lifetime.
    private let cloudFetcher: CloudKitMedicalRecordFetcher
    private let sharedFetcher: CloudKitSharedZoneMedicalRecordFetcher

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

        self.cloudFetcher = CloudKitMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData")

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            print("[MyHealthDataApp] Failed to create persistent ModelContainer: \(error)")
            let memoryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            self.modelContainer = try! ModelContainer(for: schema, configurations: [memoryConfig])
        }

        // Ensure the fetchers have the model context so imports can run
        self.cloudFetcher.setModelContext(self.modelContainer.mainContext)
        self.sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(
            containerIdentifier: "iCloud.com.furfarch.MyHealthData",
            modelContext: self.modelContainer.mainContext
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.modelContext, modelContainer.mainContext)
                .task {
                    // Best-effort: trigger import of any pending cloud/shared changes on launch
                    // cloudFetcher.fetchChanges() is fire-and-forget for private CloudKit database
                    // fetchSharedRecords() fetches and imports from shared CloudKit database
                    cloudFetcher.fetchChanges()
                    await fetchSharedRecords()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Fetch cloud changes when app becomes active to ensure we get updates
            if newPhase == .active {
                Task { @MainActor in
                    // Start both fetchers to update from private and shared CloudKit databases
                    // cloudFetcher.fetchChanges() is fire-and-forget, starts async operation
                    // fetchSharedRecords() is awaited to ensure shared records are current
                    cloudFetcher.fetchChanges()
                    await fetchSharedRecords()
                }
            }
        }
    }
    
    @MainActor
    private func fetchSharedRecords() async {
        // Fetch shared records from CloudKit shared database
        do {
            let count = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
            if count > 0 {
                ShareDebugStore.shared.appendLog("MyHealthDataApp: fetched \(count) shared records on activation")
                
                // Force the model context to process any pending changes and refresh
                modelContainer.mainContext.processPendingChanges()
                
                // Post notification to ensure UI refreshes
                NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
            }
        } catch {
            ShareDebugStore.shared.appendLog("MyHealthDataApp: shared fetch failed: \(error)")
        }
    }
}
