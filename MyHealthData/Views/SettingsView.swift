import SwiftUI
import CloudKit

struct SettingsView: View {
    @State private var accountStatus: CKAccountStatus?
    @State private var accountStatusError: String?

    // Export UI state
    @State private var showExportSheet: Bool = false
    @State private var exportItems: [Any] = []

    private let containerIdentifier = "iCloud.com.furfarch.MyHealthData"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ExportSettingsView()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }

                Section("iCloud") {
                    NavigationLink {
                        CloudRecordSettingsView()
                    } label: {
                        Label("iCloud Sync and Sharing of Records", systemImage: "icloud")
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(accountStatus.map(accountStatusText) ?? "Checking…")
                            .foregroundStyle(.secondary)
                    }

                    if let accountStatusError {
                        Text(accountStatusError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Re-check iCloud Status") {
                        Task { await refreshAccountStatus() }
                    }

                    // Always-available export for TestFlight / Release: copies logs and opens share sheet
                    Button(action: {
                        let export = ShareDebugStore.shared.exportText()
                        // copy to clipboard
                        #if canImport(UIKit)
                        UIPasteboard.general.string = export
                        #elseif canImport(AppKit)
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(export, forType: .string)
                        #endif
                        ShareDebugStore.shared.appendLog("User initiated export from Settings")
                        exportItems = [export]
                        showExportSheet = true
                    }) {
                        Label("Export Share Logs", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                await refreshAccountStatus()
            }
            .sheet(isPresented: $showExportSheet) {
                ActivityViewController(items: exportItems)
            }
        }
    }

    private func refreshAccountStatus() async {
        accountStatusError = nil
        do {
            let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
            accountStatus = status
        } catch {
            accountStatus = nil
            accountStatusError = "iCloud status check failed: \(error.localizedDescription)"
        }
    }

    private func accountStatusText(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "Available"
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "Restricted"
        case .couldNotDetermine:
            return "Could not determine"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        @unknown default:
            return "Unknown"
        }
    }
}

#Preview {
    SettingsView()
}
