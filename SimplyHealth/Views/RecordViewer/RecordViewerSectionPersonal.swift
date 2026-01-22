import SwiftUI

struct RecordViewerSectionPersonal: View {
    let record: MedicalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if record.isPet {
                RecordViewerRow(title: "Name", value: record.personalName)
                RecordViewerRow(title: "Animal ID (ANIS)", value: record.personalAnimalID)
                RecordViewerRow(title: "Owner Name", value: record.ownerName)
                RecordViewerRow(title: "Owner Phone", value: record.ownerPhone)
                RecordViewerRow(title: "Owner Email", value: record.ownerEmail)
            } else {
                RecordViewerRow(title: "Family Name", value: record.personalFamilyName)
                RecordViewerRow(title: "Given Name", value: record.personalGivenName)
                RecordViewerRow(title: "Nick Name", value: record.personalNickName)
                RecordViewerRow(title: "Gender", value: record.personalGender)
                RecordViewerDateRow(title: "Birthdate", value: record.personalBirthdate)
                RecordViewerRow(title: "Social Security / AHV Nummer", value: record.personalSocialSecurityNumber)
                RecordViewerRow(title: "Address", value: record.personalAddress)
                RecordViewerRow(title: "Health Insurance", value: record.personalHealthInsurance)
                RecordViewerRow(title: "Health Insurance Number", value: record.personalHealthInsuranceNumber)
                RecordViewerRow(title: "Employer", value: record.personalEmployer)
            }
        }
    }
}
