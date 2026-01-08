import Foundation
import SwiftData

@Model
final class MedicalRecord {
    var createdAt: Date
    var updatedAt: Date

    // Personal Information (human)
    var personalFamilyName: String
    var personalGivenName: String
    var personalNickName: String
    var personalGender: String
    var personalBirthdate: Date?
    var personalSocialSecurityNumber: String
    var personalAddress: String
    var personalHealthInsurance: String
    var personalHealthInsuranceNumber: String
    var personalEmployer: String

    // Legacy single emergency contact fields (kept for backward compatibility)
    var emergencyName: String
    var emergencyNumber: String
    var emergencyEmail: String

    // Relationships (existing ones)
    @Relationship(deleteRule: .cascade, inverse: \BloodEntry.record)
    var blood: [BloodEntry]

    @Relationship(deleteRule: .cascade, inverse: \DrugEntry.record)
    var drugs: [DrugEntry]

    @Relationship(deleteRule: .cascade, inverse: \VaccinationEntry.record)
    var vaccinations: [VaccinationEntry]

    @Relationship(deleteRule: .cascade, inverse: \AllergyEntry.record)
    var allergy: [AllergyEntry]

    @Relationship(deleteRule: .cascade, inverse: \IllnessEntry.record)
    var illness: [IllnessEntry]

    @Relationship(deleteRule: .cascade, inverse: \RiskEntry.record)
    var risks: [RiskEntry]

    @Relationship(deleteRule: .cascade, inverse: \MedicalHistoryEntry.record)
    var medicalhistory: [MedicalHistoryEntry]

    @Relationship(deleteRule: .cascade, inverse: \MedicalDocumentEntry.record)
    var medicaldocument: [MedicalDocumentEntry]

    @Relationship(deleteRule: .cascade, inverse: \WeightEntry.record)
    var weights: [WeightEntry]

    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.record)
    var emergencyContacts: [EmergencyContact]

    init(
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        personalFamilyName: String = "",
        personalGivenName: String = "",
        personalNickName: String = "",
        personalGender: String = "",
        personalBirthdate: Date? = nil,
        personalSocialSecurityNumber: String = "",
        personalAddress: String = "",
        personalHealthInsurance: String = "",
        personalHealthInsuranceNumber: String = "",
        personalEmployer: String = "",
        emergencyName: String = "",
        emergencyNumber: String = "",
        emergencyEmail: String = "",
        blood: [BloodEntry] = [],
        drugs: [DrugEntry] = [],
        vaccinations: [VaccinationEntry] = [],
        allergy: [AllergyEntry] = [],
        illness: [IllnessEntry] = [],
        risks: [RiskEntry] = [],
        medicalhistory: [MedicalHistoryEntry] = [],
        medicaldocument: [MedicalDocumentEntry] = [],
        weights: [WeightEntry] = [],
        emergencyContacts: [EmergencyContact] = []
    ) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt

        self.personalFamilyName = personalFamilyName
        self.personalGivenName = personalGivenName
        self.personalNickName = personalNickName
        self.personalGender = personalGender
        self.personalBirthdate = personalBirthdate
        self.personalSocialSecurityNumber = personalSocialSecurityNumber
        self.personalAddress = personalAddress
        self.personalHealthInsurance = personalHealthInsurance
        self.personalHealthInsuranceNumber = personalHealthInsuranceNumber
        self.personalEmployer = personalEmployer

        self.emergencyName = emergencyName
        self.emergencyNumber = emergencyNumber
        self.emergencyEmail = emergencyEmail

        self.blood = blood
        self.drugs = drugs
        self.vaccinations = vaccinations
        self.allergy = allergy
        self.illness = illness
        self.risks = risks
        self.medicalhistory = medicalhistory
        self.medicaldocument = medicaldocument
        self.weights = weights
        self.emergencyContacts = emergencyContacts
    }

    // Pet-related accessors (computed) — map to existing persisted fields so no schema change is required.
    var isPet: Bool {
        get { personalEmployer == "IS_PET" }
        set { personalEmployer = newValue ? "IS_PET" : "" }
    }

    var personalName: String {
        get { personalNickName }
        set { personalNickName = newValue }
    }

    var personalAnimalID: String {
        get { personalSocialSecurityNumber }
        set { personalSocialSecurityNumber = newValue }
    }

    var ownerName: String {
        get { personalFamilyName }
        set { personalFamilyName = newValue }
    }

    var ownerPhone: String {
        get { personalHealthInsuranceNumber }
        set { personalHealthInsuranceNumber = newValue }
    }

    var ownerEmail: String {
        get { emergencyEmail }
        set { emergencyEmail = newValue }
    }
}
