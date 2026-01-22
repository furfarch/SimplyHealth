import SwiftUI

struct RecordViewerSectionPetYearlyCosts: View {
    let record: MedicalRecord

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var years: [Int] {
        let yearsSet = Set(record.petYearlyCosts.map { $0.year } + [currentYear])
        return Array(yearsSet).sorted(by: >)
    }

    private func entries(for year: Int) -> [PetYearlyCostEntry] {
        record.petYearlyCosts.filter { $0.year == year }.sorted { $0.date < $1.date }
    }

    private func total(for year: Int) -> Double {
        entries(for: year).reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(years, id: \.self) { year in
                DisclosureGroup {
                    let items = entries(for: year)
                    if items.isEmpty {
                        Text("No transactions for \(year).")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(items, id: \.uuid) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.category.isEmpty ? "Transaction" : entry.category)
                                        .font(.headline)
                                    Text(entry.date, format: .dateTime.day().month().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing) {
                                    Text(entry.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                        .fontWeight(.semibold)
                                    if !entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(entry.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                } label: {
                    HStack {
                        Text(String(year))
                            .font(.headline)
                        Spacer()
                        Text(total(for: year), format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal)
                Divider()
            }
        }
    }
}
