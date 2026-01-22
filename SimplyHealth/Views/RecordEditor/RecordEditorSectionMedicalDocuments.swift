import SwiftUI
import SwiftData

struct RecordEditorSectionMedicalDocuments: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section("Relevant Medical Documents") {
            ForEach(record.medicaldocument) { entry in
                MedicalDocumentEntryRowView(entry: entry)
            }
            .onDelete(perform: deleteMedicalDocuments)

            Button("Add Medical Document Entry") { addMedicalDocument() }
        }
    }

    private func addMedicalDocument() {
        withAnimation {
            let entry = MedicalDocumentEntry(date: Date(), record: record)
            record.medicaldocument.append(entry)
            onChange()
        }
    }

    private func deleteMedicalDocuments(offsets: IndexSet) {
        withAnimation {
            for idx in offsets {
                let entry = record.medicaldocument[idx]
                modelContext.delete(entry)
            }
            onChange()
        }
    }
}

struct MedicalDocumentEntryRowView: View {
    @Bindable var entry: MedicalDocumentEntry

    var body: some View {
        VStack(alignment: .leading) {
            DatePicker(
                "Date",
                selection: Binding(get: { entry.date ?? Date() }, set: { entry.date = $0 }),
                displayedComponents: .date
            )
            TextField("Document Title", text: $entry.name)
            TextField("Note", text: $entry.note, axis: .vertical)
                .lineLimit(2...6)
        }
    }
}
