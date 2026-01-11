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
    @Environment(\.scenePhase) private var scenePhase

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
            WeightEntry.self
        ])

        // Force a purely local store. This avoids Core Data's CloudKit validation rules
        // from preventing the app from launching while the schema is still evolving.
        // (You can re-enable CloudKit later with a dedicated migration pass.)
        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            // LOG THE ERROR so we know why persistent store failed
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
                .task {
                    // On first launch, attempt to pull records from CloudKit into the local store.
                    // This makes per-record sync appear automatic: when a record is uploaded from
                    // another device, this device will import it on foreground/launch.
                    let fetcher = CloudKitMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData")
                    fetcher.setModelContext(self.modelContainer.mainContext)
                    fetcher.fetchAll()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { newPhase, _ in
            if newPhase == .active {
                Task { @MainActor in
                    let fetcher = CloudKitMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData")
                    fetcher.setModelContext(self.modelContainer.mainContext)
                    fetcher.fetchAll()
                }
            }
        }
    }
}
