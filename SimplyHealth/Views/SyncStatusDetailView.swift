import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SyncStatusDetailView: View, Identifiable {
    var id: String { record.id }
    var record: MedicalRecord

    @ObservedObject private var debug = ShareDebugStore.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isSyncing: Bool = false
    @State private var actionMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Summary") {
                    HStack {
                        Text("Record")
                        Spacer()
                        Text(record.displayName)
                    }
                    HStack {
                        Text("Cloud Enabled")
                        Spacer()
                        Text(record.isCloudEnabled ? "Yes" : "No")
                    }
                    HStack {
                        Text("Sharing Enabled")
                        Spacer()
                        Text(record.isSharingEnabled ? "Yes" : "No")
                    }
                }

                Section("Cloud IDs") {
                    HStack {
                        Text("Cloud Record")
                        Spacer()
                        Text(record.cloudRecordName ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Share Record")
                        Spacer()
                        Text(record.cloudShareRecordName ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Actions") {
                    Button(action: { Task { await performSync() } }) {
                        HStack {
                            if isSyncing { ProgressView().scaleEffect(0.75) }
                            Text(isSyncing ? "Syncing…" : "Sync Now")
                        }
                    }
                    .disabled(isSyncing || !record.isCloudEnabled)

                    Button("Copy Share Logs to Clipboard") {
                        let exportLines = filteredLogs()
                        let export = exportLines.joined(separator: "\n")
                        copyToClipboard(export)
                        ShareDebugStore.shared.appendLog("User copied filtered share logs from SyncStatusDetailView for record=\(record.uuid)")
                        actionMessage = "Copied \(exportLines.count) log lines"
                    }

                    if let msg = actionMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Share Debug Log") {
                    let logs = filteredLogs()
                    if logs.isEmpty {
                        Text("No logs for this record yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(logs, id: \.self) { line in
                                    Text(line)
                                        .font(.caption2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 120, maxHeight: 300)
                    }
                }
            }
            .navigationTitle("Sync Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func filteredLogs() -> [String] {
        debug.logs.filter { $0.contains(record.uuid) }
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
    }

    @MainActor
    private func performSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        actionMessage = nil
        ShareDebugStore.shared.appendLog("SyncStatusDetailView: user initiated sync for record=\(record.uuid)")
        do {
            try await CloudSyncService.shared.syncIfNeeded(record: record)
            try modelContext.save()
            actionMessage = "Sync succeeded"
            ShareDebugStore.shared.appendLog("SyncStatusDetailView: sync succeeded for record=\(record.uuid)")
        } catch {
            actionMessage = "Sync failed: \(error.localizedDescription)"
            ShareDebugStore.shared.appendLog("SyncStatusDetailView: sync failed for record=\(record.uuid) error=\(error)")
        }
        isSyncing = false
    }


}
