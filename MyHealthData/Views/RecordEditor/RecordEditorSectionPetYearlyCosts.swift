import SwiftUI
import SwiftData

struct RecordEditorSectionPetYearlyCosts: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var availableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        let years = Set(record.petYearlyCosts.map { Calendar.current.component(.year, from: $0.date) } + [current])
        return Array(years).sorted(by: >)
    }

    private var filteredIndices: [Int] {
        record.petYearlyCosts.indices
            .filter { Calendar.current.component(.year, from: record.petYearlyCosts[$0].date) == selectedYear }
            .sorted { a, b in record.petYearlyCosts[a].date > record.petYearlyCosts[b].date }
    }

    private var selectedYearTotal: Double {
        record.petYearlyCosts
            .filter { Calendar.current.component(.year, from: $0.date) == selectedYear }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        Section {
            Picker("Year", selection: $selectedYear) {
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }

            HStack {
                Text("Total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedYearTotal, format: .currency(code: Locale.current.currency?.identifier ?? "CHF"))
                    .fontWeight(.semibold)
            }

            if filteredIndices.isEmpty {
                Text("No costs for \(selectedYear).")
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredIndices, id: \.self) { idx in
                TextField(
                    "Title",
                    text: Binding(
                        get: { record.petYearlyCosts[idx].title },
                        set: { record.petYearlyCosts[idx].title = $0; onChange() }
                    )
                )

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
                        "0.00",
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

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        let removed = record.petYearlyCosts.remove(at: idx)
                        modelContext.delete(removed)
                        onChange()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                if idx != filteredIndices.last {
                    Divider()
                }
            }

            Button("Add Cost") {
                let entry = PetYearlyCostEntry(title: "", date: Date(), amount: 0, note: "")
                record.petYearlyCosts.append(entry)
                selectedYear = Calendar.current.component(.year, from: entry.date)
                onChange()
            }
        } header: {
            Label("Costs", systemImage: "eurosign.circle")
        }
        .onAppear {
            selectedYear = Calendar.current.component(.year, from: Date())
        }
    }
}
