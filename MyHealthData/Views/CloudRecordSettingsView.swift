import SwiftUI
import SwiftData

struct CloudRecordSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("cloudEnabled") private var cloudEnabled: Bool = false

    @Query(sort: \MedicalRecord.updatedAt, order: .reverse) private var records: [MedicalRecord]

    @State private var syncingRecordID: String?
    @State private var errorMessage: String?

    @State private var sharingRecord: MedicalRecord?
    @State private var pendingShareRecord: MedicalRecord?
    @State private var showShareConfirm: Bool = false

    var body: some View {
        Form {
            Section("Cloud") {
                Toggle("Enable iCloud Sync (per-record opt-in)", isOn: $cloudEnabled)

                Text("When enabled, you can choose which records are synced to iCloud and which are shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Records") {
                if records.isEmpty {
                    Text("No records yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records) { record in
                        recordRow(for: record)
                    }
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("iCloud")
        .confirmationDialog(
            "Create Share?",
            isPresented: $showShareConfirm,
            titleVisibility: .visible
        ) {
            Button("Create Share") {
                sharingRecord = pendingShareRecord
                pendingShareRecord = nil
            }
            Button("Cancel", role: .cancel) {
                // If user cancels, also revert the toggle.
                pendingShareRecord?.isSharingEnabled = false
                pendingShareRecord = nil
            }
        } message: {
            Text("This will create a CloudKit share link for this record.")
        }
        .sheet(item: $sharingRecord, onDismiss: {
            sharingRecord = nil
        }) { record in
            CloudShareSheet(record: record)
        }
    }

    @ViewBuilder
    private func recordRow(for record: MedicalRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(record.displayName)
                    .font(.headline)
                Spacer()
                Image(systemName: record.isCloudEnabled ? (record.isSharingEnabled ? "person.2.circle" : "icloud") : "iphone")
                    .foregroundStyle(record.isCloudEnabled ? (record.isSharingEnabled ? .green : .blue) : .secondary)
            }

            Toggle("Sync", isOn: Binding(
                get: { record.isCloudEnabled },
                set: { newValue in
                    if newValue {
                        record.isCloudEnabled = true

                        // Immediately attempt to sync the record to CloudKit so enabling feels instantaneous.
                        Task { @MainActor in
                            do {
                                try? modelContext.save()
                                try await CloudSyncService.shared.syncIfNeeded(record: record)
                                try? modelContext.save()
                            } catch {
                                // Surface a user-visible error message
                                errorMessage = "Cloud sync failed: \(error.localizedDescription)"
                            }
                        }
                    } else {
                        // OFF means: remove this record from iCloud.
                        CloudSyncService.shared.disableCloud(for: record)
                    }

                    record.updatedAt = Date()
                    try? modelContext.save()
                }
            ))
            .disabled(!cloudEnabled)

            HStack {
                Button {
                    Task { await syncNow(record) }
                } label: {
                    if syncingRecordID == record.id {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Syncing…")
                        }
                    } else {
                        Text("Sync Now")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!cloudEnabled || !record.isCloudEnabled || syncingRecordID == record.id)

                Spacer()
            }

            Toggle("Sharing", isOn: Binding(
                get: { record.isSharingEnabled },
                set: { newValue in
                    // Sharing requires sync.
                    if newValue {
                        guard cloudEnabled, record.isCloudEnabled else {
                            record.isSharingEnabled = false
                            return
                        }
                        // Ask for confirmation + present share UI.
                        record.isSharingEnabled = true
                        pendingShareRecord = record
                        showShareConfirm = true

                        Task { @MainActor in
                            await CloudKitShareParticipantsService.shared.refreshParticipantsSummary(for: record)
                            try? modelContext.save()
                        }
                    } else {
                        // MVP: local-only toggle. Unsharing CloudKit records can be added later.
                        record.isSharingEnabled = false
                        record.shareParticipantsSummary = ""
                    }

                    record.updatedAt = Date()
                    try? modelContext.save()
                }
            ))
            .disabled(!cloudEnabled || !record.isCloudEnabled)

            if record.isSharingEnabled {
                Text(record.shareParticipantsSummary.isEmpty ? "Shared with: (not loaded yet)" : "Shared with: \(record.shareParticipantsSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !cloudEnabled {
                Text("Enable iCloud Sync above to manage per-record syncing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @MainActor
    private func syncNow(_ record: MedicalRecord) async {
        errorMessage = nil
        syncingRecordID = record.id
        defer { syncingRecordID = nil }

        do {
            try modelContext.save()
            try await CloudSyncService.shared.syncIfNeeded(record: record)
            try modelContext.save()
        } catch {
            errorMessage = "Cloud sync failed: \(error.localizedDescription)"
        }
    }


}

#Preview {
    NavigationStack {
        CloudRecordSettingsView()
    }
    .modelContainer(for: MedicalRecord.self, inMemory: true)
}
