import SwiftUI
import SwiftData

struct RecordEditorSectionPetYearlyCosts: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    private var entries: [PetYearlyCostEntry] { Array(record.petYearlyCosts) }

    @State private var amountCache: [String: String] = [:]

    private func parseAmount(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Normalize whitespace
        var s = trimmed.replacingOccurrences(of: "\u{00A0}", with: "")
        s = s.replacingOccurrences(of: " ", with: "")

        // Count separators
        let dotCount = s.filter { $0 == "." }.count
        let commaCount = s.filter { $0 == "," }.count

        func digitsCountAfter(_ idx: String.Index) -> Int {
            let suffix = s[s.index(after: idx)...]
            return suffix.filter { $0.isWholeNumber }.count
        }

        // If both separators present, assume the rightmost separator is decimal separator
        if dotCount > 0 && commaCount > 0 {
            // Determine rightmost separator
            if let lastDot = s.lastIndex(of: "."), let lastComma = s.lastIndex(of: ",") {
                let decimalChar: Character = (lastDot > lastComma) ? "." : ","
                let groupingChar: Character = (decimalChar == ".") ? "," : "."
                // remove grouping chars
                s.removeAll { $0 == groupingChar }
                // replace decimalChar with '.' for Double parsing
                s = s.replacingOccurrences(of: String(decimalChar), with: ".")
                return Double(s)
            }
        }

        // Only one of dot/comma present
        if dotCount + commaCount == 1 {
            let sep: Character = dotCount == 1 ? "." : ","
            if let sepIndex = s.firstIndex(of: sep) {
                let digitsAfter = digitsCountAfter(sepIndex)
                // If digits after separator look like decimal (1 or 2 digits), treat as decimal
                if digitsAfter >= 1 && digitsAfter <= 2 {
                    let normalized = s.replacingOccurrences(of: String(sep), with: ".")
                    return Double(normalized)
                }
                // If digitsAfter == 3 it's likely a grouping separator (e.g., 1.000)
                if digitsAfter == 3 {
                    let work = s.replacingOccurrences(of: String(sep), with: "")
                    return Double(work)
                }
                // Fallback: if digits after 0 treat as grouping, else decimal
                if digitsAfter == 0 {
                    let work = s.replacingOccurrences(of: String(sep), with: "")
                    return Double(work)
                }
                // Other cases: treat as decimal
                let normalized = s.replacingOccurrences(of: String(sep), with: ".")
                return Double(normalized)
            }
        }

        // No separators -> treat as whole number
        if let i = Int(s) {
            return Double(i)
        }

        // Last resort
        return Double(s)
    }

    var body: some View {
        Section {
            if record.petYearlyCosts.isEmpty {
                Text("Track recurring yearly pet costs (e.g., insurance, food, vet).")
                    .foregroundStyle(.secondary)
            }

            // Iterate a snapshot of entries so UI rows remain stable when appending/removing
            ForEach(entries, id: \.uuid) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        // Category editable
                        TextField("Category", text: Binding(get: {
                            entry.category
                        }, set: { new in
                            entry.category = new
                            record.updatedAt = Date()
                            onChange()
                        }))
                        .font(.headline)

                        Spacer()

                        Button(role: .destructive) {
                            if let index = record.petYearlyCosts.firstIndex(where: { $0.uuid == entry.uuid }) {
                                let removed = record.petYearlyCosts.remove(at: index)
                                modelContext.delete(removed)
                                amountCache[entry.uuid] = nil
                                onChange()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    HStack(spacing: 12) {
                        // Date editable
                        DatePicker("Date", selection: Binding(get: {
                            entry.date
                        }, set: { new in
                            entry.date = new
                            // Keep year in sync by default
                            entry.year = Calendar.current.component(.year, from: new)
                            record.updatedAt = Date()
                            onChange()
                        }), displayedComponents: .date)
                        .labelsHidden()
                        .frame(minWidth: 120)

                        // Amount editable as string cache so the field can be empty and not reformat mid-edit
                        let amtBinding = Binding<String>(get: {
                            if let cached = amountCache[entry.uuid] { return cached }
                            // initialize cache from model value
                            if entry.amount == 0 { return "" }
                            if floor(entry.amount) == entry.amount { return String(format: "%.0f", entry.amount) }
                            return String(format: "%.2f", entry.amount)
                        }, set: { new in
                            amountCache[entry.uuid] = new
                            if let parsed = parseAmount(new) {
                                entry.amount = parsed
                            } else {
                                entry.amount = 0
                            }
                            record.updatedAt = Date()
                            onChange()
                        })

                        TextField("Amount", text: amtBinding)
                        #if canImport(UIKit)
                        .keyboardType(.decimalPad)
                        #endif
                        .frame(minWidth: 120)

                        Spacer()
                    }

                    HStack {
                        TextField("Year", value: Binding(get: {
                            entry.year
                        }, set: { new in
                            entry.year = new
                            record.updatedAt = Date()
                            onChange()
                        }), format: .number)
                        .frame(width: 100)

                        TextField("Note", text: Binding(get: {
                            entry.note
                        }, set: { new in
                            entry.note = new
                            record.updatedAt = Date()
                            onChange()
                        }))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .onAppear {
                    // Ensure cache is initialized once
                    if amountCache[entry.uuid] == nil {
                        if entry.amount == 0 {
                            amountCache[entry.uuid] = ""
                        } else if floor(entry.amount) == entry.amount {
                            amountCache[entry.uuid] = String(format: "%.0f", entry.amount)
                        } else {
                            amountCache[entry.uuid] = String(format: "%.2f", entry.amount)
                        }
                    }
                }
            }

            Button("Add Transaction") {
                let entry = PetYearlyCostEntry(record: record)
                // default date today -> year derived
                record.petYearlyCosts.append(entry)
                onChange()
            }
        } header: {
            Label("Yearly Costs", systemImage: "eurosign.circle")
        }
    }
}
