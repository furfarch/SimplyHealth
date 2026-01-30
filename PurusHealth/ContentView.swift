//
//  ContentView.swift
//  Purus Health
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData
import CloudKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    // Show alert when a share is accepted and imported
    @State private var showShareAcceptedAlert: Bool = false
    @State private var importedName: String = ""

    // Show alert when share acceptance fails
    @State private var showShareErrorAlert: Bool = false
    @State private var shareErrorMessage: String = ""

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
                await checkPendingShare()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Check for pending share URL when app becomes active
                if newPhase == .active {
                    Task { @MainActor in
                        await checkPendingShare()
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
                        
                        // Post notification to ensure UI refreshes
                        NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
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
            .onReceive(NotificationCenter.default.publisher(for: NotificationNames.shareAcceptanceFailed)) { notif in
                // Show error alert when share acceptance fails
                if let userInfo = notif.userInfo, let errorMsg = userInfo["error"] as? String {
                    shareErrorMessage = errorMsg
                } else {
                    shareErrorMessage = "An unknown error occurred while accepting the share."
                }
                showShareErrorAlert = true
            }
            .alert("Share Failed", isPresented: $showShareErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shareErrorMessage)
            }
            .onReceive(NotificationCenter.default.publisher(for: NotificationNames.pendingShareReceived)) { notif in
                // Process share immediately when received from SceneDelegate/AppDelegate
                // This handles the case where onOpenURL doesn't fire due to custom SceneDelegate
                guard let userInfo = notif.userInfo else { return }

                // Prefer metadata (more efficient - skips URL fetch)
                if let metadata = userInfo["metadata"] as? CKShare.Metadata {
                    ShareDebugStore.shared.appendLog("ContentView: received pendingShareReceived with metadata")
                    Task { @MainActor in
                        await CloudKitShareAcceptanceService.shared.acceptShare(from: metadata, modelContext: modelContext)
                    }
                    return
                }

                // Fall back to URL
                if let url = userInfo["url"] as? URL {
                    ShareDebugStore.shared.appendLog("ContentView: received pendingShareReceived notification for URL: \(url)")
                    Task { @MainActor in
                        await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
                    }
                }
            }
    }
    
    @MainActor
    private func checkPendingShare() async {
        #if canImport(UIKit)
        // Check for pending share metadata first (more efficient)
        if let metadata = PendingShareStore.shared.consumeMetadata() {
            ShareDebugStore.shared.appendLog("ContentView: processing pending share metadata from AppDelegate")
            await CloudKitShareAcceptanceService.shared.acceptShare(from: metadata, modelContext: modelContext)
            return
        }

        // Fall back to pending URL
        if let pendingURL = PendingShareStore.shared.consumeURL() {
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
