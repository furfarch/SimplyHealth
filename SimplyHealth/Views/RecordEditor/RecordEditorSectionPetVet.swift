import SwiftUI
import SwiftData

struct RecordEditorSectionPetVet: View {
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section {
            #if canImport(ContactsUI)
            ContactPickerButton(title: "Pick Vet from Contacts") { result in
                apply(contact: result)
                onChange()
            }
            #else
            Text("Picking from Contacts is available on iOS only.")
                .foregroundStyle(.secondary)
            #endif

            TextField("Clinic Name", text: $record.vetClinicName)
            TextField("Contact Name", text: $record.vetContactName)
            TextField("Phone", text: $record.vetPhone)
            TextField("Email", text: $record.vetEmail)
            TextField("Address", text: $record.vetAddress, axis: .vertical)
                .lineLimit(1...3)
            TextField("Note", text: $record.vetNote, axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Label("Veterinarian", systemImage: "stethoscope.circle")
        }
        .onChange(of: record.vetClinicName) { onChange() }
        .onChange(of: record.vetContactName) { onChange() }
        .onChange(of: record.vetPhone) { onChange() }
        .onChange(of: record.vetEmail) { onChange() }
        .onChange(of: record.vetAddress) { onChange() }
        .onChange(of: record.vetNote) { onChange() }
    }

    private func apply(contact: ContactPickerResult) {
        let name = contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            record.vetContactName = name
        }

        if !contact.phone.isEmpty {
            record.vetPhone = contact.phone
        }

        if !contact.email.isEmpty {
            record.vetEmail = contact.email
        }

        let address = contact.postalAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty {
            record.vetAddress = address
        }
    }
}
