import SwiftUI
import SwiftData

struct RecordEditorSectionVaccinations: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section("Vaccinations") {
            ForEach(record.vaccinations) { entry in
                VaccinationEntryRowView(entry: entry)
            }
            .onDelete(perform: deleteVaccinations)

            Button("Add Vaccination Entry") { addVaccination() }
        }
    }

    private func addVaccination() {
        withAnimation {
            let entry = VaccinationEntry(date: Date(), record: record)
            record.vaccinations.append(entry)
            onChange()
        }
    }

    private func deleteVaccinations(offsets: IndexSet) {
        withAnimation {
            for idx in offsets {
                let entry = record.vaccinations[idx]
                modelContext.delete(entry)
            }
            onChange()
        }
    }
}

struct VaccinationEntryRowView: View {
    @Bindable var entry: VaccinationEntry

    var body: some View {
        VStack(alignment: .leading) {
            DatePicker(
                "Date",
                selection: Binding(get: { entry.date ?? Date() }, set: { entry.date = $0 }),
                displayedComponents: .date
            )
            TextField("Vaccination Name", text: $entry.name)
            TextField("Information", text: $entry.information)
            TextField("Place", text: $entry.place)
            TextField("Comment", text: $entry.comment)
        }
    }
}
