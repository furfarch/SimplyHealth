import Foundation

struct MedicalRecordExport: Codable {
    var exportVersion: Int = 1

    var isPet: Bool
    var personalinformation: PersonalInformation
    var petinformation: PetInformation?
    var emergencyContacts: [EmergencyContact]

    var blood: [Blood]
    var drugs: [Drug]
    var vaccinations: [Vaccination]
    var allergy: [Allergy]
    var illness: [Illness]
    var risks: [Risk]
    var medicalhistory: [MedicalHistory]
    var medicaldocument: [MedicalDocument]
    var weights: [Weight]

    struct PersonalInformation: Codable {
        var personalFamilyName: String
        var personalGivenName: String
        var personalNickName: String
        var personalGender: String
        var personalBirthdate: String
        var personalSocialSecurityNumber: String
        var personalAddress: String
        var personalHealthInsurance: String
        var personalHealthInsuranceNumber: String
        var personalEmployer: String
    }

    struct EmergencyContact: Codable {
        var name: String
        var phone: String
        var email: String
        var note: String
    }

    struct Blood: Codable {
        var bloodDate: String
        var bloodName: String
        var bloodComment: String
    }

    struct Drug: Codable {
        var drugDate: String
        var drugName: String
        var drugComment: String
    }

    struct Vaccination: Codable {
        var vaccinationDate: String
        var vaccinationName: String
        var vaccinationInfo: String
        var vaccinationPlace: String
        var vaccinationComment: String
    }

    struct Allergy: Codable {
        var allergyDate: String
        var allergyName: String
        var allergyInformation: String
        var allergyComment: String
    }

    struct Illness: Codable {
        var illnessDate: String
        var illnessName: String
        var illnessComment: String
    }

    struct Risk: Codable {
        var risksDate: String
        var risksName: String
        var risksComment: String
    }

    struct MedicalHistory: Codable {
        var medicalhistoryDate: String
        var medicalhistoryName: String
        var medicalhistoryContact: String
        var medicalhistoryComment: String
    }

    struct MedicalDocument: Codable {
        var medicaldocumentDate: String
        var medicaldocumentName: String
        var medicaldocumentComment: String
    }

    struct PetInformation: Codable {
        var personalName: String
        var personalAnimalID: String
        var ownerName: String
        var ownerPhone: String
        var ownerEmail: String
    }

    struct Weight: Codable {
        var weightDate: String
        var weightKg: Double
        var weightComment: String
    }
}
