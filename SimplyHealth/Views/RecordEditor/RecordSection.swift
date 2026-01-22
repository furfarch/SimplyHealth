import Foundation

enum RecordSection: String, CaseIterable, Identifiable {
    case personal
    case petVet
    case petCosts
    case doctors
    case emergency
    case weight
    case details
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
        case .petVet: return "Vet"
        case .petCosts: return "Costs"
        case .doctors: return "Doctors"
        case .emergency: return "Emergency"
        case .weight: return "Weight"
        case .details: return "Record Details"
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
        case .petVet: return "stethoscope.circle"
        case .petCosts: return "eurosign.circle"
        case .doctors: return "stethoscope"
        case .emergency: return "cross.case"
        case .weight: return "scalemass"
        case .details: return "info.circle"
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
