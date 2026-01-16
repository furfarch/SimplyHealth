import SwiftUI
import SwiftData

struct RecordEditorSectionPetYearlyCosts: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    private var sortedIndices: [Int] {
        record.petYearlyCosts.indices.sorted { a, b in
            record.petYearlyCosts[a].date > record.petYearlyCosts[b].date
        }
    }

    var body: some View {
        Section {
            if record.petYearlyCosts.isEmpty {
                Text("Track pet costs by date and see the yearly total.")
                    .foregroundStyle(.secondary)
            }

            ForEach(sortedIndices, id: \.self) { idx in
                HStack {
                    TextField(
                        "Title (e.g., Vet Check Up)",
                        text: Binding(
                            get: { record.petYearlyCosts[idx].title },
                            set: { record.petYearlyCosts[idx].title = $0; onChange() }
                        )
                    )

                    Spacer()

                    Button(role: .destructive) {
                        let removed = record.petYearlyCosts.remove(at: idx)
                        modelContext.delete(removed)
                        onChange()
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { record.petYearlyCosts[idx].date },
                        set: { record.petYearlyCosts[idx].date = $0; onChange() }
                    ),
                    displayedComponents: [.date]
                )

                HStack {
                    Text("Amount")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField(
                        "",
                        value: Binding(
                            get: { record.petYearlyCosts[idx].amount },
                            set: { record.petYearlyCosts[idx].amount = $0; onChange() }
                        ),
                        format: .number
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }

                TextField(
                    "Note",
                    text: Binding(
                        get: { record.petYearlyCosts[idx].note },
                        set: { record.petYearlyCosts[idx].note = $0; onChange() }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...3)
            }

            Button("Add Cost") {
                let entry = PetYearlyCostEntry(record: record)
                record.petYearlyCosts.append(entry)
                onChange()
            }
        } header: {
            Label("Costs", systemImage: "eurosign.circle")
        }
    }
}
