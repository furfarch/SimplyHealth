import SwiftUI
import SwiftData

struct RecordEditorSectionIllnesses: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section("Illnesses & Incidents") {
            ForEach(record.illness) { entry in
                IllnessEntryRowView(entry: entry)
            }
            .onDelete(perform: deleteIllness)

            Button("Add Illness / Incident Entry") { addIllness() }
        }
    }

    private func addIllness() {
        withAnimation {
            let entry = IllnessEntry(date: Date(), record: record)
            record.illness.append(entry)
            onChange()
        }
    }

    private func deleteIllness(offsets: IndexSet) {
        withAnimation {
            for idx in offsets {
                let entry = record.illness[idx]
                modelContext.delete(entry)
            }
            onChange()
        }
    }
}

struct IllnessEntryRowView: View {
    @Bindable var entry: IllnessEntry

    var body: some View {
        VStack(alignment: .leading) {
            DatePicker(
                "Date",
                selection: Binding(get: { entry.date ?? Date() }, set: { entry.date = $0 }),
                displayedComponents: .date
            )
            TextField("Illness / Incident Name", text: $entry.name)
            TextField("Information / Comment", text: $entry.informationOrComment)
        }
    }
}
