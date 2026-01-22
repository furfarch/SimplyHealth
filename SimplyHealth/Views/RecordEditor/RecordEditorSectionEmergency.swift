import SwiftUI
import SwiftData

struct RecordEditorSectionEmergency: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section {
            TextField("Emergency Contact Name", text: $record.emergencyName)
            TextField("Emergency Contact Number", text: $record.emergencyNumber)
            TextField("Emergency Contact Email", text: $record.emergencyEmail)

            ForEach(record.emergencyContacts.indices, id: \.self) { idx in
                HStack {
                    TextField("Name", text: Binding(
                        get: { record.emergencyContacts[idx].name },
                        set: { record.emergencyContacts[idx].name = $0 }
                    ))
                    Spacer()
                    Button(role: .destructive) {
                        let removed = record.emergencyContacts.remove(at: idx)
                        modelContext.delete(removed)
                        onChange()
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                TextField("Phone", text: Binding(
                    get: { record.emergencyContacts[idx].phone },
                    set: { record.emergencyContacts[idx].phone = $0 }
                ))
                TextField("Email", text: Binding(
                    get: { record.emergencyContacts[idx].email },
                    set: { record.emergencyContacts[idx].email = $0 }
                ))
                TextField("Note", text: Binding(
                    get: { record.emergencyContacts[idx].note },
                    set: { record.emergencyContacts[idx].note = $0 }
                ), axis: .vertical)
                    .lineLimit(1...3)
            }

            Button("Add Emergency Contact") {
                let contact = EmergencyContact(record: record)
                record.emergencyContacts.append(contact)
                onChange()
            }
        } header: {
            Label("Emergency Information", systemImage: "cross.case")
        }
        .onChange(of: record.emergencyName) { onChange() }
        .onChange(of: record.emergencyNumber) { onChange() }
        .onChange(of: record.emergencyEmail) { onChange() }
    }
}
