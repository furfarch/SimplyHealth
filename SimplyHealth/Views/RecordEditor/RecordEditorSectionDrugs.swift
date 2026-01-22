import SwiftUI
import SwiftData

struct RecordEditorSectionDrugs: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section("Medications") {
            ForEach(record.drugs) { entry in
                DrugEntryRowView(entry: entry)
            }
            .onDelete(perform: deleteDrugs)

            Button("Add Drug Entry") { addDrug() }
        }
    }

    private func addDrug() {
        withAnimation {
            let entry = DrugEntry(date: Date(), record: record)
            record.drugs.append(entry)
            onChange()
        }
    }

    private func deleteDrugs(offsets: IndexSet) {
        withAnimation {
            for idx in offsets {
                let entry = record.drugs[idx]
                modelContext.delete(entry)
            }
            onChange()
        }
    }
}

struct DrugEntryRowView: View {
    @Bindable var entry: DrugEntry

    var body: some View {
        VStack(alignment: .leading) {
            DatePicker(
                "Date",
                selection: Binding(get: { entry.date ?? Date() }, set: { entry.date = $0 }),
                displayedComponents: .date
            )
            TextField("Medication Name & Dosage", text: $entry.nameAndDosage)
            TextField("Comment (Why, Schedule)", text: $entry.comment)
        }
    }
}
