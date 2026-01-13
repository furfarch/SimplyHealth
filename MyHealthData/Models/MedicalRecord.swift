import Foundation
import SwiftData
import SwiftUI

@Model
final class MedicalRecord {
    var createdAt: Date
    var updatedAt: Date

    // Local stable identifier (avoid using 'id' which conflicts with SwiftData synthesized id)
    var uuid: String
    // Conform to Identifiable for use with SwiftUI APIs that require it.
    var id: String { uuid }

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

    // Pet-related fields
    var isPet: Bool
    var personalName: String
    var personalAnimalID: String
    var ownerName: String
    var ownerPhone: String
    var ownerEmail: String

    // Legacy single emergency contact fields (kept for backward compatibility)
    var emergencyName: String
    var emergencyNumber: String
    var emergencyEmail: String

    // Relationships (existing ones)
    @Relationship(deleteRule: .cascade, inverse: \BloodEntry.record)
    var blood: [BloodEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \DrugEntry.record)
    var drugs: [DrugEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \VaccinationEntry.record)
    var vaccinations: [VaccinationEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \AllergyEntry.record)
    var allergy: [AllergyEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \IllnessEntry.record)
    var illness: [IllnessEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \RiskEntry.record)
    var risks: [RiskEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \MedicalHistoryEntry.record)
    var medicalhistory: [MedicalHistoryEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \MedicalDocumentEntry.record)
    var medicaldocument: [MedicalDocumentEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \WeightEntry.record)
    var weights: [WeightEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.record)
    var emergencyContacts: [EmergencyContact] = []

    // CloudKit integration flags (opt-in per-record)
    var isCloudEnabled: Bool = false
    var cloudRecordName: String? = nil

    /// If non-nil, this record has an associated CKShare stored in the same zone as the root record.
    /// We keep just the recordName so we can fetch/reuse the share later.
    var cloudShareRecordName: String? = nil

    /// Per-record sharing toggle.
    /// When true, we try to ensure a CKShare exists for this record.
    var isSharingEnabled: Bool = false

    /// Optional display string for participants (UI-only, best effort).
    /// For now this may remain empty; we'll populate it later when we add participant fetching.
    var shareParticipantsSummary: String = ""

    enum RecordLocationStatus: Equatable {
        case local
        case iCloud
        case shared

        var systemImageName: String {
            switch self {
            case .local: return "iphone"
            case .iCloud: return "icloud"
            case .shared: return "person.2.circle"
            }
        }

        var color: Color {
            switch self {
            case .local: return .secondary
            case .iCloud: return .blue
            case .shared: return .green
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .local: return "Local record"
            case .iCloud: return "iCloud record"
            case .shared: return "Shared record"
            }
        }
    }

    /// Centralized rule for what the UI should show.
    /// Priority: Shared > iCloud > Local.
    var locationStatus: RecordLocationStatus {
        if isCloudEnabled {
            if isSharingEnabled || cloudShareRecordName != nil {
                return .shared
            }
            return .iCloud
        }
        return .local
    }

    /// Display name for the record following the pattern: "Family Name - Given Name - Name"
    /// For pets: uses personalName
    /// For humans: displays all non-empty fields in order (family, given, name) separated by " - "
    /// Examples: "Smith - John - Johnny", "Smith - John", "Johnny", "Person" (when all empty)
    var displayName: String {
        if isPet {
            let name = personalName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Pet" : name
        } else {
            let family = personalFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let given = personalGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = personalNickName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Build the display name with " - " separator
            let parts = [family, given, name].filter { !$0.isEmpty }
            
            if parts.isEmpty {
                return "Person"
            }
            
            return parts.joined(separator: " - ")
        }
    }
    
    /// Sort key for ordering records
    /// Uses the same pattern as displayName: Family Name, Given Name, Name
    /// Returns lowercase version of displayName for case-insensitive sorting
    var sortKey: String {
        return displayName.lowercased()
    }

    init(
        uuid: String = UUID().uuidString,
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
        isPet: Bool = false,
        personalName: String = "",
        personalAnimalID: String = "",
        ownerName: String = "",
        ownerPhone: String = "",
        ownerEmail: String = "",
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
        emergencyContacts: [EmergencyContact] = [],
        isCloudEnabled: Bool = false,
        cloudRecordName: String? = nil,
        cloudShareRecordName: String? = nil,
        isSharingEnabled: Bool = false,
        shareParticipantsSummary: String = ""
    ) {
        self.uuid = uuid
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

        // pet fields
        self.isPet = isPet
        self.personalName = personalName
        self.personalAnimalID = personalAnimalID
        self.ownerName = ownerName
        self.ownerPhone = ownerPhone
        self.ownerEmail = ownerEmail

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

        self.isCloudEnabled = isCloudEnabled
        self.cloudRecordName = cloudRecordName
        self.cloudShareRecordName = cloudShareRecordName
        self.isSharingEnabled = isSharingEnabled
        self.shareParticipantsSummary = shareParticipantsSummary
    }
}
