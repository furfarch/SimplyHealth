//
//  ContentView.swift
//  Simply Health
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    // Show alert when a share is accepted and imported
    @State private var showShareAcceptedAlert: Bool = false
    @State private var importedName: String = ""

    var body: some View {
        RecordListView()
            .onOpenURL { url in
                // Accept CloudKit share links and import shared records.
                Task { @MainActor in
                    await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
                }
            }
            .task {
                // Check for pending share URL on first appearance
                await checkPendingShareURL()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Check for pending share URL when app becomes active
                if newPhase == .active {
                    Task { @MainActor in
                        await checkPendingShareURL()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NotificationNames.didAcceptShare)) { notif in
                // Show brief alert with the imported record name(s) and ensure shared-zone fetch ran
                if let userInfo = notif.userInfo, let names = userInfo["names"] as? [String], let first = names.first {
                    importedName = first
                } else {
                    importedName = "record"
                }
                showShareAcceptedAlert = true

                // Force model context to refresh
                modelContext.processPendingChanges()

                // Ensure shared-zone fetch runs and imports any related records
                Task { @MainActor in
                    let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID, modelContext: modelContext)
                    do {
                        _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
                        ShareDebugStore.shared.appendLog("ContentView: triggered shared-zone fetch after accept")
                        
                        // Force refresh after fetch completes
                        modelContext.processPendingChanges()
                    } catch {
                        ShareDebugStore.shared.appendLog("ContentView: shared-zone fetch after accept failed: \(error)")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NotificationNames.didChangeSharedRecords)) { _ in
                // Another component requested a UI refresh for shared records - perform a shared-zone fetch
                Task { @MainActor in
                    let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID, modelContext: modelContext)
                    do {
                        _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
                        ShareDebugStore.shared.appendLog("ContentView: triggered shared-zone fetch for DidChangeSharedRecords")
                        
                        // Force refresh after fetch completes
                        modelContext.processPendingChanges()
                    } catch {
                        ShareDebugStore.shared.appendLog("ContentView: DidChangeSharedRecords fetch failed: \(error)")
                    }
                }
            }
            .alert("Imported", isPresented: $showShareAcceptedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(importedName) imported")
            }
    }
    
    @MainActor
    private func checkPendingShareURL() async {
        #if canImport(UIKit)
        // Check if there's a pending share URL from the AppDelegate
        if let pendingURL = PendingShareStore.shared.consume() {
            ShareDebugStore.shared.appendLog("ContentView: processing pending share URL from AppDelegate")
            await CloudKitShareAcceptanceService.shared.acceptShare(from: pendingURL, modelContext: modelContext)
        }
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
