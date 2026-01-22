import SwiftUI

struct RecordViewerSectionDoctors: View {
    let record: MedicalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if record.humanDoctors.isEmpty {
                RecordViewerRow(title: "Doctors", value: "No doctors added")
            } else {
                ForEach(record.humanDoctors.prefix(5).indices, id: \.self) { idx in
                    let doctor = record.humanDoctors[idx]
                    RecordViewerRow(title: "Type", value: doctor.type)
                    RecordViewerRow(title: "Name", value: doctor.name)
                    if !doctor.phone.isEmpty { RecordViewerRow(title: "Phone", value: doctor.phone) }
                    if !doctor.email.isEmpty { RecordViewerRow(title: "Email", value: doctor.email) }
                    if !doctor.address.isEmpty { RecordViewerRow(title: "Address", value: doctor.address) }
                    if !doctor.note.isEmpty { RecordViewerRow(title: "Note", value: doctor.note) }
                    if idx < min(record.humanDoctors.count, 5) - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}
