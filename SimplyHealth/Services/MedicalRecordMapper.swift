import Foundation

enum MedicalRecordMapper {
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    static func toExport(record: MedicalRecord) -> MedicalRecordExport {
        let petInfo: MedicalRecordExport.PetInformation? = record.isPet ? .init(
            personalName: record.personalName,
            personalAnimalID: record.personalAnimalID,
            ownerName: record.ownerName,
            ownerPhone: record.ownerPhone,
            ownerEmail: record.ownerEmail
        ) : nil

        // Map emergency contacts; if none exist but legacy fields exist, create a single contact
        var emergencyContacts: [MedicalRecordExport.EmergencyContact] = []
        if !record.emergencyContacts.isEmpty {
            emergencyContacts = record.emergencyContacts.map { c in
                .init(name: c.name, phone: c.phone, email: c.email, note: c.note)
            }
        } else if !record.emergencyName.isEmpty || !record.emergencyNumber.isEmpty || !record.emergencyEmail.isEmpty {
            emergencyContacts = [.init(name: record.emergencyName, phone: record.emergencyNumber, email: record.emergencyEmail, note: "")]
        }

        return MedicalRecordExport(
            isPet: record.isPet,
            personalinformation: .init(
                personalFamilyName: record.personalFamilyName,
                personalGivenName: record.personalGivenName,
                personalNickName: record.personalNickName,
                personalGender: record.personalGender,
                personalBirthdate: record.personalBirthdate.map { iso8601.string(from: $0) } ?? "",
                personalSocialSecurityNumber: record.personalSocialSecurityNumber,
                personalAddress: record.personalAddress,
                personalHealthInsurance: record.personalHealthInsurance,
                personalHealthInsuranceNumber: record.personalHealthInsuranceNumber,
                personalEmployer: record.personalEmployer
            ),
            petinformation: petInfo,
            emergencyContacts: emergencyContacts,
            blood: record.blood.map {
                .init(
                    bloodDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    bloodName: $0.name,
                    bloodComment: $0.comment
                )
            },
            drugs: record.drugs.map {
                .init(
                    drugDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    drugName: $0.nameAndDosage,
                    drugComment: $0.comment
                )
            },
            vaccinations: record.vaccinations.map {
                .init(
                    vaccinationDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    vaccinationName: $0.name,
                    vaccinationInfo: $0.information,
                    vaccinationPlace: $0.place,
                    vaccinationComment: $0.comment
                )
            },
            allergy: record.allergy.map {
                .init(
                    allergyDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    allergyName: $0.name,
                    allergyInformation: $0.information,
                    allergyComment: $0.comment
                )
            },
            illness: record.illness.map {
                .init(
                    illnessDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    illnessName: $0.name,
                    illnessComment: $0.informationOrComment
                )
            },
            risks: record.risks.map {
                .init(
                    risksDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    risksName: $0.name,
                    risksComment: $0.descriptionOrComment
                )
            },
            medicalhistory: record.medicalhistory.map {
                .init(
                    medicalhistoryDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    medicalhistoryName: $0.name,
                    medicalhistoryContact: $0.contact,
                    medicalhistoryComment: $0.informationOrComment
                )
            },
            medicaldocument: record.medicaldocument.map {
                .init(
                    medicaldocumentDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    medicaldocumentName: $0.name,
                    medicaldocumentComment: $0.note
                )
            },
            // Only include weights for pets. Humans receive an empty weights array.
            weights: record.isPet ? record.weights.map {
                .init(
                    weightDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    weightKg: $0.weightKg ?? 0,
                    weightComment: $0.comment
                )
            } : []
        )
    }
}
