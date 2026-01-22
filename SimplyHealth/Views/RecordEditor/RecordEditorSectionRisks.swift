import SwiftUI
import SwiftData

struct RecordEditorSectionRisks: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section("Riskfactors") {
            ForEach(record.risks) { entry in
                RiskEntryRowView(entry: entry)
            }
            .onDelete(perform: deleteRisks)

            Button("Add Risk Factors Entry") { addRisk() }
        }
    }

    private func addRisk() {
        withAnimation {
            let entry = RiskEntry(date: Date(), record: record)
            record.risks.append(entry)
            onChange()
        }
    }

    private func deleteRisks(offsets: IndexSet) {
        withAnimation {
            for idx in offsets {
                let entry = record.risks[idx]
                modelContext.delete(entry)
            }
            onChange()
        }
    }
}

struct RiskEntryRowView: View {
    @Bindable var entry: RiskEntry

    var body: some View {
        VStack(alignment: .leading) {
            DatePicker(
                "Date",
                selection: Binding(get: { entry.date ?? Date() }, set: { entry.date = $0 }),
                displayedComponents: .date
            )
            TextField("Riskfactor Name", text: $entry.name)
            TextField("Description / Information / Comment", text: $entry.descriptionOrComment)
        }
    }
}
