import SwiftUI
import SwiftData

struct RecordEditorSectionMedicalHistory: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section("Relevant Medical History") {
            ForEach(record.medicalhistory) { entry in
                MedicalHistoryEntryRowView(entry: entry)
            }
            .onDelete(perform: deleteMedicalHistory)

            Button("Add Medical History Entry") { addMedicalHistory() }
        }
    }

    private func addMedicalHistory() {
        withAnimation {
            let entry = MedicalHistoryEntry(date: Date(), record: record)
            record.medicalhistory.append(entry)
            onChange()
        }
    }

    private func deleteMedicalHistory(offsets: IndexSet) {
        withAnimation {
            for idx in offsets {
                let entry = record.medicalhistory[idx]
                modelContext.delete(entry)
            }
            onChange()
        }
    }
}

struct MedicalHistoryEntryRowView: View {
    @Bindable var entry: MedicalHistoryEntry

    var body: some View {
        VStack(alignment: .leading) {
            DatePicker(
                "Date",
                selection: Binding(get: { entry.date ?? Date() }, set: { entry.date = $0 }),
                displayedComponents: .date
            )
            TextField("Medical History Name", text: $entry.name)
            TextField("Contact", text: $entry.contact)
            TextField("Information / Comment", text: $entry.informationOrComment)
        }
    }
}
