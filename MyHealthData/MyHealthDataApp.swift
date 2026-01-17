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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.modelContext, modelContainer.mainContext)
                .task(id: UUID()) {
                    // On launch, attempt a best-effort fetch of incremental changes and shared records.
                    // Do not crash the app on CloudKit failures — just log them.
                    cloudFetcher.fetchChanges()

                    // Also fetch shared records across shared zones so accepted shares appear.
                    Task {
                        let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData", modelContext: modelContainer.mainContext)
                        do {
                            _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
                        } catch {
                            ShareDebugStore.shared.appendLog("MyHealthDataApp: initial shared fetch failed: \(error)")
                        }
                    }
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { newPhase, _ in
            if newPhase == .active {
                // Reattach context (in case of container recreation in fallback) and trigger fetch
                cloudFetcher.setModelContext(modelContainer.mainContext)
                cloudFetcher.fetchChanges()

                Task {
                    let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData", modelContext: modelContainer.mainContext)
                    do {
                        _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
                    } catch {
                        ShareDebugStore.shared.appendLog("MyHealthDataApp: active shared fetch failed: \(error)")
                    }
                }
            }
        }
    }
}
