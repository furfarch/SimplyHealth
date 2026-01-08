 import Foundation

enum RecordSection: String, CaseIterable, Identifiable {
    case personal
    case emergency
    case weight
    case blood
    case drugs
    case vaccinations
    case allergies
    case illnesses
    case medicalDocuments
    case medicalHistory
    case risks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "Personal"
        case .emergency: return "Emergency"
        case .weight: return "Weight"
        case .blood: return "Blood"
        case .drugs: return "Medications"
        case .vaccinations: return "Vaccinations"
        case .allergies: return "Allergies"
        case .illnesses: return "Illnesses"
        case .medicalDocuments: return "Documents"
        case .medicalHistory: return "History"
        case .risks: return "Risks"
        }
    }

    var sfSymbol: String {
        switch self {
        case .personal: return "person.text.rectangle"
        case .emergency: return "cross.case"
        case .weight: return "scalemass"
        case .blood: return "drop"
        case .drugs: return "pills"
        case .vaccinations: return "syringe"
        case .allergies: return "allergens"
        case .illnesses: return "stethoscope"
        case .medicalDocuments: return "doc.text"
        case .medicalHistory: return "clock.arrow.circlepath"
        case .risks: return "exclamationmark.triangle"
        }
    }
}
