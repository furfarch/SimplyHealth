import SwiftUI
import SwiftData

struct RecordEditorSectionDoctors: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    private var sortedIndices: [Int] {
        record.humanDoctors.indices.sorted { a, b in
            record.humanDoctors[a].type.localizedCaseInsensitiveCompare(record.humanDoctors[b].type) == .orderedAscending
        }
    }

    var body: some View {
        Section {
            if record.humanDoctors.isEmpty {
                Text("Add up to 5 doctors (type + contact details).")
                    .foregroundStyle(.secondary)
            }

            ForEach(sortedIndices, id: \.self) { idx in
                VStack(alignment: .leading, spacing: 12) {
                    ContactPickerButton(title: "Pick from Contacts") { contact in
                        record.humanDoctors[idx].name = contact.displayName
                        record.humanDoctors[idx].phone = contact.phone
                        record.humanDoctors[idx].email = contact.email
                        record.humanDoctors[idx].address = contact.postalAddress
                        onChange()
                    }

                    HStack {
                        TextField(
                            "Type (e.g., GP)",
                            text: Binding(
                                get: { record.humanDoctors[idx].type },
                                set: { record.humanDoctors[idx].type = $0; onChange() }
                            )
                        )

                        Spacer()

                        Button(role: .destructive) {
                            let removed = record.humanDoctors.remove(at: idx)
                            modelContext.delete(removed)
                            onChange()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    TextField(
                        "Name",
                        text: Binding(
                            get: { record.humanDoctors[idx].name },
                            set: { record.humanDoctors[idx].name = $0; onChange() }
                        )
                    )

                    TextField(
                        "Phone",
                        text: Binding(
                            get: { record.humanDoctors[idx].phone },
                            set: { record.humanDoctors[idx].phone = $0; onChange() }
                        )
                    )

                    TextField(
                        "Email",
                        text: Binding(
                            get: { record.humanDoctors[idx].email },
                            set: { record.humanDoctors[idx].email = $0; onChange() }
                        )
                    )

                    TextField(
                        "Address",
                        text: Binding(
                            get: { record.humanDoctors[idx].address },
                            set: { record.humanDoctors[idx].address = $0; onChange() }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(1...3)

                    TextField(
                        "Note",
                        text: Binding(
                            get: { record.humanDoctors[idx].note },
                            set: { record.humanDoctors[idx].note = $0; onChange() }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                }
                .padding(.vertical, 4)

                if idx != sortedIndices.last {
                    Divider()
                }
            }

            Button("Add Doctor") {
                guard record.humanDoctors.count < 5 else { return }
                let doctor = HumanDoctorEntry(record: record)
                record.humanDoctors.append(doctor)
                onChange()
            }
            .disabled(record.humanDoctors.count >= 5)
        } header: {
            Label("Doctors", systemImage: "stethoscope")
        }
    }
}
