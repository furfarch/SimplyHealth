import SwiftUI
import SwiftData

struct ExportSettingsView: View {
    @Query(sort: \MedicalRecord.updatedAt, order: .reverse) private var records: [MedicalRecord]

    @State private var exportRecord: MedicalRecord?

    var body: some View {
        List {
            Section {
                Text("Exports are created per record and are not encrypted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Records") {
                if records.isEmpty {
                    Text("No records yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records) { record in
                        Button {
                            exportRecord = record
                        } label: {
                            Text(record.displayName)
                        }
                    }
                }
            }
        }
        .navigationTitle("Export")
        .sheet(item: $exportRecord, onDismiss: { exportRecord = nil }) { record in
            ExportRecordSheet(record: record)
        }
    }


}

#Preview {
    NavigationStack {
        ExportSettingsView()
    }
    .modelContainer(for: MedicalRecord.self, inMemory: true)
}
