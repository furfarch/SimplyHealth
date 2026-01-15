//
//  ContentView.swift
//  MyHealthData
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        RecordListView()
            .onOpenURL { url in
                // Accept CloudKit share links and import shared records.
                Task { @MainActor in
                    await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
                }
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
