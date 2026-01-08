import SwiftUI
import SwiftData

struct RecordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MedicalRecord.updatedAt, order: .reverse) private var records: [MedicalRecord]

    @State private var activeRecord: MedicalRecord? = nil
    @State private var showEditor: Bool = false
    @State private var startEditing: Bool = false

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
            }
            .navigationTitle("MyHealthData")
            .toolbar {
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
            .sheet(isPresented: $showEditor) {
                if let record = activeRecord {
                    NavigationStack {
                        RecordEditorView(record: record, startEditing: startEditing)
                    }
                } else {
                    EmptyView()
                }
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
        do { try modelContext.save() } catch { /* intentionally silent */ }

        activeRecord = record
        startEditing = true
        showEditor = true
    }

    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            let record = records[index]
            modelContext.delete(record)
        }
        do { try modelContext.save() } catch { /* intentionally silent */ }
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
