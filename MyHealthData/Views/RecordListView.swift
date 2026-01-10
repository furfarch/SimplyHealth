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
                if records.isEmpty {
                    VStack(alignment: .center) {
                        Text("No records yet")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(records, id: \.createdAt) { record in
                        Button(action: {
                            activeRecord = record
                            startEditing = false
                            showEditor = true
                        }) {
                            HStack {
                                Image(systemName: record.isPet ? "cat" : "person")
                                VStack(alignment: .leading) {
                                    Text(displayName(for: record)).font(.headline)
                                    Text(record.updatedAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteRecords)
                }

                // CloudKit section
                Section(header: Text("CloudKit Records")) {
                    if cloudKitFetcher.isLoading {
                        ProgressView("Loading from iCloud...")
                    } else if let error = cloudKitFetcher.error {
                        Text("CloudKit error: \(error.localizedDescription)")
                            .foregroundStyle(.red)
                    } else if cloudKitFetcher.records.isEmpty {
                        Text("No records in iCloud")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(cloudKitFetcher.records, id: \.recordID) { ckRecord in
                            VStack(alignment: .leading) {
                                Text(ckRecord["personalFamilyName"] as? String ?? "(No Name)")
                                    .font(.headline)
                                Text("Updated: \(ckRecord["updatedAt"] as? Date ?? Date())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Import All to Local Records") {
                            cloudKitFetcher.importToSwiftData(context: modelContext)
                        }
                    }
                    Button("Reload from iCloud") {
                        cloudKitFetcher.fetchAll()
                    }
                }
            }
            .navigationTitle("MyHealthData")
            .toolbar {
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
        for index in offsets {
            let record = records[index]
            modelContext.delete(record)
        }
        Task { @MainActor in
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
}

#Preview {
    RecordListView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
