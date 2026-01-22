import SwiftUI
import SwiftData

struct RecordEditorSectionAllergies: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        if record.isPet { EmptyView() } else {
        Section("Allergies & Intolerances") {
            ForEach(record.allergy) { entry in
                AllergyEntryRowView(entry: entry)
            }
            .onDelete(perform: deleteAllergy)

            Button("Add Allergy / Intolerance Entry") { addAllergy() }
        }
        }
    }

    private func addAllergy() {
        withAnimation {
            let entry = AllergyEntry(date: Date(), record: record)
            record.allergy.append(entry)
            onChange()
        }
    }

    private func deleteAllergy(offsets: IndexSet) {
        withAnimation {
            for idx in offsets {
                let entry = record.allergy[idx]
                modelContext.delete(entry)
            }
            onChange()
        }
    }
}

struct AllergyEntryRowView: View {
    @Bindable var entry: AllergyEntry

    var body: some View {
        VStack(alignment: .leading) {
            DatePicker(
                "Date",
                selection: Binding(get: { entry.date ?? Date() }, set: { entry.date = $0 }),
                displayedComponents: .date
            )
            TextField("Allergy / Intolerance Name", text: $entry.name)
            TextField("Information", text: $entry.information)
            TextField("Comment", text: $entry.comment)
        }
    }
}
