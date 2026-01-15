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

    // New sections
    case vet
    case doctors
    case petCosts
    case details

    var id: String { rawValue }

    static func sections(for record: MedicalRecord) -> [RecordSection] {
        var sections: [RecordSection] = [
            .personal,
            .emergency,
            .blood,
            .drugs,
            .vaccinations,
            .allergies,
            .illnesses,
            .medicalDocuments,
            .medicalHistory,
            .risks
        ]

        if record.isPet {
            // Pets-only
            sections.insert(.weight, at: 2)
            sections.append(.vet)
            sections.append(.petCosts)
        } else {
            // Humans-only
            sections.append(.doctors)
        }

        sections.append(.details)
        return sections
    }

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
        case .vet: return "Vet"
        case .doctors: return "Doctors"
        case .petCosts: return "Costs"
        case .details: return "Record Details"
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
        case .vet: return "cross.case.circle"
        case .doctors: return "stethoscope.circle"
        case .petCosts: return "eurosign.circle"
        case .details: return "info.circle"
        }
    }
}
