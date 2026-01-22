import SwiftUI
import SwiftData

struct RecordEditorSectionBlood: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        if record.isPet { EmptyView() } else {
        Section("Blood Values") {
            ForEach(record.blood) { entry in
                BloodEntryRowView(entry: entry)
            }
            .onDelete(perform: deleteBlood)

            Button("Add Blood Entry") { addBlood() }
        }
        }
    }

    private func addBlood() {
        withAnimation {
            let entry = BloodEntry(date: Date(), record: record)
            record.blood.append(entry)
            onChange()
        }
    }

    private func deleteBlood(offsets: IndexSet) {
        withAnimation {
            for idx in offsets {
                let entry = record.blood[idx]
                modelContext.delete(entry)
            }
            onChange()
        }
    }
}

struct BloodEntryRowView: View {
    @Bindable var entry: BloodEntry

    var body: some View {
        VStack(alignment: .leading) {
            DatePicker(
                "Date",
                selection: Binding(get: { entry.date ?? Date() }, set: { entry.date = $0 }),
                displayedComponents: .date
            )
            TextField("Value Name", text: $entry.name)
            TextField("Comment", text: $entry.comment)
        }
    }
}
