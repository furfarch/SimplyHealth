import SwiftUI
import SwiftData

struct RecordEditorSectionPersonal: View {
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        if record.isPet {
            Section {
                // Use dedicated pet fields in the model
                TextField("Name", text: $record.personalName)
                TextField("Animal ID (ANIS)", text: $record.personalAnimalID)
                TextField("Owner Name", text: $record.ownerName)
                TextField("Owner Phone", text: $record.ownerPhone)
                TextField("Owner Email", text: $record.ownerEmail)
            } header: {
                Label("Pet Information", systemImage: "pawprint")
            }
            .onChange(of: record.personalName) { onChange() }
            .onChange(of: record.personalAnimalID) { onChange() }
            .onChange(of: record.ownerName) { onChange() }
            .onChange(of: record.ownerPhone) { onChange() }
            .onChange(of: record.ownerEmail) { onChange() }
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
            .onChange(of: record.personalFamilyName) { onChange() }
            .onChange(of: record.personalGivenName) { onChange() }
            .onChange(of: record.personalNickName) { onChange() }
            .onChange(of: record.personalGender) { onChange() }
            .onChange(of: record.personalBirthdate) { onChange() }
            .onChange(of: record.personalSocialSecurityNumber) { onChange() }
            .onChange(of: record.personalAddress) { onChange() }
            .onChange(of: record.personalHealthInsurance) { onChange() }
            .onChange(of: record.personalHealthInsuranceNumber) { onChange() }
            .onChange(of: record.personalEmployer) { onChange() }
        }
    }
}
