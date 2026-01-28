import Foundation
import SwiftData
import SwiftUI

@Model
final class MedicalRecord {
    // timestamps with defaults for CloudKit compatibility
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Local stable identifier (avoid using 'id' which conflicts with SwiftData synthesized id)
    var uuid: String = UUID().uuidString
    // Conform to Identifiable for use with SwiftUI APIs that require it.
    var id: String { uuid }

    // Personal Information (human)
    var personalFamilyName: String = ""
    var personalGivenName: String = ""
    var personalNickName: String = ""
    var personalGender: String = ""
    var personalBirthdate: Date? = nil
    var personalSocialSecurityNumber: String = ""
    var personalAddress: String = ""
    var personalHealthInsurance: String = ""
    var personalHealthInsuranceNumber: String = ""
    var personalEmployer: String = ""

    // Pet-related fields
    var isPet: Bool = false
    var personalName: String = ""
    var personalAnimalID: String = ""
    var ownerName: String = ""
    var ownerPhone: String = ""
    var ownerEmail: String = ""

    // Pet veterinarian details
    var vetClinicName: String = ""
    var vetContactName: String = ""
    var vetPhone: String = ""
    var vetEmail: String = ""
    var vetAddress: String = ""
    var vetNote: String = ""

    // Legacy single emergency contact fields (kept for backward compatibility)
    var emergencyName: String = ""
    var emergencyNumber: String = ""
    var emergencyEmail: String = ""

    // Relationships (use optional backing storage for CloudKit compatibility)
    @Relationship(deleteRule: .cascade, inverse: \BloodEntry.record)
    private var _blood: [BloodEntry]? = nil
    var blood: [BloodEntry] {
        get { _blood ?? [] }
        set { _blood = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \DrugEntry.record)
    private var _drugs: [DrugEntry]? = nil
    var drugs: [DrugEntry] {
        get { _drugs ?? [] }
        set { _drugs = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \VaccinationEntry.record)
    private var _vaccinations: [VaccinationEntry]? = nil
    var vaccinations: [VaccinationEntry] {
        get { _vaccinations ?? [] }
        set { _vaccinations = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \AllergyEntry.record)
    private var _allergy: [AllergyEntry]? = nil
    var allergy: [AllergyEntry] {
        get { _allergy ?? [] }
        set { _allergy = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \IllnessEntry.record)
    private var _illness: [IllnessEntry]? = nil
    var illness: [IllnessEntry] {
        get { _illness ?? [] }
        set { _illness = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \RiskEntry.record)
    private var _risks: [RiskEntry]? = nil
    var risks: [RiskEntry] {
        get { _risks ?? [] }
        set { _risks = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \MedicalHistoryEntry.record)
    private var _medicalhistory: [MedicalHistoryEntry]? = nil
    var medicalhistory: [MedicalHistoryEntry] {
        get { _medicalhistory ?? [] }
        set { _medicalhistory = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \MedicalDocumentEntry.record)
    private var _medicaldocument: [MedicalDocumentEntry]? = nil
    var medicaldocument: [MedicalDocumentEntry] {
        get { _medicaldocument ?? [] }
        set { _medicaldocument = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \WeightEntry.record)
    private var _weights: [WeightEntry]? = nil
    var weights: [WeightEntry] {
        get { _weights ?? [] }
        set { _weights = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.record)
    private var _emergencyContacts: [EmergencyContact]? = nil
    var emergencyContacts: [EmergencyContact] {
        get { _emergencyContacts ?? [] }
        set { _emergencyContacts = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \HumanDoctorEntry.record)
    private var _humanDoctors: [HumanDoctorEntry]? = nil
    var humanDoctors: [HumanDoctorEntry] {
        get { _humanDoctors ?? [] }
        set { _humanDoctors = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \PetYearlyCostEntry.record)
    private var _petYearlyCosts: [PetYearlyCostEntry]? = nil
    var petYearlyCosts: [PetYearlyCostEntry] {
        get { _petYearlyCosts ?? [] }
        set { _petYearlyCosts = newValue }
    }

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
    /// Note: Shared records should show as shared even if isCloudEnabled is false,
    /// because recipients of a share may not have cloud sync enabled for their own records.
    var locationStatus: RecordLocationStatus {
        // Check sharing status first - a shared record should always show as shared
        // regardless of the local isCloudEnabled flag
        if isSharingEnabled || cloudShareRecordName != nil {
            return .shared
        }
        if isCloudEnabled {
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
    /// Humans first, then Pets, both alphabetically sorted by displayName
    /// Uses "0-" prefix for humans and "1-" prefix for pets to ensure correct ordering
    var sortKey: String {
        let prefix = isPet ? "1-" : "0-"
        return prefix + displayName.lowercased()
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
        vetClinicName: String = "",
        vetContactName: String = "",
        vetPhone: String = "",
        vetEmail: String = "",
        vetAddress: String = "",
        vetNote: String = "",
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
        humanDoctors: [HumanDoctorEntry] = [],
        petYearlyCosts: [PetYearlyCostEntry] = [],
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

        self.vetClinicName = vetClinicName
        self.vetContactName = vetContactName
        self.vetPhone = vetPhone
        self.vetEmail = vetEmail
        self.vetAddress = vetAddress
        self.vetNote = vetNote

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
        self.humanDoctors = humanDoctors
        self.petYearlyCosts = petYearlyCosts

        self.isCloudEnabled = isCloudEnabled
        self.cloudRecordName = cloudRecordName
        self.cloudShareRecordName = cloudShareRecordName
        self.isSharingEnabled = isSharingEnabled
        self.shareParticipantsSummary = shareParticipantsSummary
    }
}
