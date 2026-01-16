import SwiftUI

struct RecordViewerSectionPetYearlyCosts: View {
    let record: MedicalRecord

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var yearPickerYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        let years = Set(record.petYearlyCosts.map { Calendar.current.component(.year, from: $0.date) } + [current])
        return Array(years).sorted(by: >)
    }

    private var entriesForSelectedYear: [PetYearlyCostEntry] {
        record.petYearlyCosts
            .filter { Calendar.current.component(.year, from: $0.date) == selectedYear }
            .sorted { $0.date > $1.date }
    }

    private var selectedYearTotal: Double {
        entriesForSelectedYear.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Year")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Year", selection: $selectedYear) {
                    ForEach(yearPickerYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            HStack {
                Text("Total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedYearTotal, format: .currency(code: Locale.current.currency?.identifier ?? "CHF"))
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)

            Divider()

            if entriesForSelectedYear.isEmpty {
                Text("No costs for \(selectedYear).")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            } else {
                RecordViewerSectionEntries(
                    title: "Costs",
                    columns: ["Title", "Date", "Amount", "Note"],
                    rows: entriesForSelectedYear.map { entry in
                        [
                            entry.title,
                            entry.date.formatted(date: .abbreviated, time: .omitted),
                            String(format: "%.2f", entry.amount),
                            entry.note
                        ]
                    }
                )
            }
        }
        .onAppear {
            selectedYear = Calendar.current.component(.year, from: Date())
        }
    }
}
