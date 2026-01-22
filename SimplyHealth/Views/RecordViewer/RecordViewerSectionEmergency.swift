import SwiftUI

struct RecordViewerSectionEmergency: View {
    let record: MedicalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let contacts = record.emergencyContacts

            if !contacts.isEmpty {
                ForEach(contacts, id: \.self) { contact in
                    RecordViewerRow(title: "Contact", value: contact.name)
                    if !contact.phone.isEmpty { RecordViewerRow(title: "Phone", value: contact.phone) }
                    if !contact.email.isEmpty { RecordViewerRow(title: "Email", value: contact.email) }
                    if !contact.note.isEmpty { RecordViewerRow(title: "Note", value: contact.note) }
                    Divider()
                }
            } else {
                RecordViewerRow(title: "Emergency Contact Name", value: record.emergencyName)
                RecordViewerRow(title: "Emergency Contact Number", value: record.emergencyNumber)
                RecordViewerRow(title: "Emergency Contact Email", value: record.emergencyEmail)
            }
        }
    }
}
