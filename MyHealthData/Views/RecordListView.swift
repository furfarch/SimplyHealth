import SwiftUI
import SwiftData

struct RecordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MedicalRecord.updatedAt, order: .reverse) private var records: [MedicalRecord]

    @State private var activeRecord: MedicalRecord? = nil
    @State private var showEditor: Bool = false
    @State private var startEditing: Bool = false
    @State private var showAbout: Bool = false
    @State private var showSettings: Bool = false
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                listContent
            }
            .refreshable {
                await refreshFromCloud()
            }
            .navigationTitle("MyHealthData")
            .toolbar {
                #if os(iOS) || targetEnvironment(macCatalyst)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button {
                            addRecord(isPet: false)
                        } label: {
                            Label("Human", systemImage: "person")
                        }

                        Button {
                            addRecord(isPet: true)
                        } label: {
                            Label("Pet", systemImage: "cat")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #else
                // macOS: use automatic placements so toolbar items render in the mac toolbar
                ToolbarItem(placement: .automatic) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }

                ToolbarItem {
                    Menu {
                        Button {
                            addRecord(isPet: false)
                        } label: {
                            Label("Human", systemImage: "person")
                        }

                        Button {
                            addRecord(isPet: true)
                        } label: {
                            Label("Pet", systemImage: "cat")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #endif
            }
            .sheet(item: $activeRecord, onDismiss: { activeRecord = nil }) { record in
                NavigationStack {
                    RecordEditorView(record: record, startEditing: startEditing)
                }
            }
            .sheet(isPresented: $showAbout) { AboutView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("Save Error", isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "Unknown error")
            }
        }
    }

    private func addRecord(isPet: Bool) {
        let record = MedicalRecord()
        record.isPet = isPet
        record.updatedAt = Date()
        if isPet {
            record.personalName = ""
        } else {
            record.personalNickName = ""
        }

        modelContext.insert(record)
        // Persist immediately so the query observes the change.
        Task { @MainActor in
            do { try modelContext.save() }
            catch { saveErrorMessage = "Save failed: \(error.localizedDescription)" }
        }

        activeRecord = record
        startEditing = true
        showEditor = true
    }

    private func deleteRecords(at offsets: IndexSet) {
        Task { @MainActor in
            // delete in reverse index order
            for index in offsets.sorted(by: >) {
                let record = records[index]
                if record.isCloudEnabled {
                    do {
                        try await CloudSyncService.shared.deleteCloudRecord(for: record)
                    } catch {
                        // record cloud delete failed; surface error but continue with local deletion
                        saveErrorMessage = "Cloud delete failed: \(error.localizedDescription)"
                    }
                }
                modelContext.delete(record)
            }
            do { try modelContext.save() }
            catch { saveErrorMessage = "Delete failed: \(error.localizedDescription)" }
        }
    }

    private func displayName(for record: MedicalRecord) -> String {
        if record.isPet {
            let name = record.personalName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
            return "Pet"
        } else {
            let family = record.personalFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let given = record.personalGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
            let nick = record.personalNickName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nick.isEmpty { return nick }
            if family.isEmpty && given.isEmpty { return "Person" }
            return [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if records.isEmpty {
            Text("No records yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ForEach(records, id: \.persistentModelID) { record in
                NavigationLink {
                    RecordEditorView(record: record, startEditing: false)
                } label: {
                    HStack {
                        Image(systemName: record.isPet ? "cat" : "person")

                        VStack(alignment: .leading) {
                            Text(displayName(for: record)).font(.headline)
                            Text(record.updatedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: record.locationStatus.systemImageName)
                            .foregroundStyle(record.locationStatus.color)
                            .accessibilityLabel(record.locationStatus.accessibilityLabel)
                            .accessibilityIdentifier("recordLocationStatusIcon")
                    }
                }
            }
            .onDelete(perform: deleteRecords)
        }
    }

    @MainActor
    private func refreshFromCloud() async {
        // Pull incremental changes (including deletions) so this works without app relaunch.
        let fetcher = CloudKitMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData", modelContext: modelContext)
        fetcher.fetchChanges()
    }
}

#Preview {
    RecordListView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
