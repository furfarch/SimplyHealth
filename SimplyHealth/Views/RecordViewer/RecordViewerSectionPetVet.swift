import SwiftUI

struct RecordViewerSectionPetVet: View {
    let record: MedicalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordViewerRow(title: "Clinic", value: record.vetClinicName)
            RecordViewerRow(title: "Contact", value: record.vetContactName)
            RecordViewerRow(title: "Phone", value: record.vetPhone)
            RecordViewerRow(title: "Email", value: record.vetEmail)
            RecordViewerRow(title: "Address", value: record.vetAddress)
            RecordViewerRow(title: "Note", value: record.vetNote)
        }
    }
}
