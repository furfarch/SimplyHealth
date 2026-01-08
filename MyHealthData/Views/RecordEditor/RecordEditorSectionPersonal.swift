import SwiftUI
import SwiftData

struct RecordEditorSectionPersonal: View {
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        if record.isPet {
            Section {
                // Use existing persisted fields to store pet info to avoid migration issues.
                // personalNickName will serve as pet name.
                TextField("Name", text: $record.personalNickName)
                // Use personalSocialSecurityNumber as Animal ID (ANIS) storage for now.
                TextField("Animal ID (ANIS)", text: $record.personalSocialSecurityNumber)
                // Map owner info onto existing fields to avoid schema changes:
                // owner name -> personalFamilyName
                TextField("Owner Name", text: $record.personalFamilyName)
                // owner phone -> personalHealthInsuranceNumber
                TextField("Owner Phone", text: $record.personalHealthInsuranceNumber)
                // owner email -> emergencyEmail (legacy field)
                TextField("Owner Email", text: $record.emergencyEmail)
            } header: {
                Label("Pet Information", systemImage: "pawprint")
            }
            .onChange(of: record.personalNickName) { _, _ in onChange() }
            .onChange(of: record.personalSocialSecurityNumber) { _, _ in onChange() }
            .onChange(of: record.personalFamilyName) { _, _ in onChange() }
            .onChange(of: record.personalHealthInsuranceNumber) { _, _ in onChange() }
            .onChange(of: record.emergencyEmail) { _, _ in onChange() }
        } else {
            Section {
                TextField("Family Name", text: $record.personalFamilyName)
                TextField("Given Name", text: $record.personalGivenName)
                TextField("Name", text: $record.personalNickName)
                TextField("Gender", text: $record.personalGender)

                DatePicker(
                    "Birthdate",
                    selection: Binding(
                        get: { record.personalBirthdate ?? Date() },
                        set: { record.personalBirthdate = $0 }
                    ),
                    displayedComponents: .date
                )

                TextField("Social Security / ANIS", text: $record.personalSocialSecurityNumber)
                TextField("Address", text: $record.personalAddress, axis: .vertical)
                    .lineLimit(1...4)

                TextField("Health Insurance", text: $record.personalHealthInsurance)
                TextField("Health Insurance Number", text: $record.personalHealthInsuranceNumber)
                TextField("Employer", text: $record.personalEmployer)
            } header: {
                Label("Personal Information", systemImage: "person.text.rectangle")
            }
            .onChange(of: record.personalFamilyName) { _, _ in onChange() }
            .onChange(of: record.personalGivenName) { _, _ in onChange() }
            .onChange(of: record.personalNickName) { _, _ in onChange() }
            .onChange(of: record.personalGender) { _, _ in onChange() }
            .onChange(of: record.personalBirthdate) { _, _ in onChange() }
            .onChange(of: record.personalSocialSecurityNumber) { _, _ in onChange() }
            .onChange(of: record.personalAddress) { _, _ in onChange() }
            .onChange(of: record.personalHealthInsurance) { _, _ in onChange() }
            .onChange(of: record.personalHealthInsuranceNumber) { _, _ in onChange() }
            .onChange(of: record.personalEmployer) { _, _ in onChange() }
        }
    }
}
