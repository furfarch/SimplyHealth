//
//  SimplyHealthApp.swift
//  Simply Health
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

@main
struct SimplyHealthApp: App {
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
                }
        }
        .modelContainer(modelContainer)
    }
}
