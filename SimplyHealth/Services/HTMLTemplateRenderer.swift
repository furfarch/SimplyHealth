import Foundation

enum HTMLTemplateRenderer {
    static func render(recordExport: MedicalRecordExport) -> String {
        func esc(_ s: String) -> String {
            s
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }

        func row(_ cols: [String]) -> String {
            "<tr>" + cols.map { "<td>\(esc($0))</td>" }.joined() + "</tr>"
        }

        func table(headers: [String], rows: [[String]]) -> String {
            let head = "<tr>" + headers.map { "<th>\(esc($0))</th>" }.joined() + "</tr>"
            let body = rows.map { row($0) }.joined(separator: "\n")
            return "<table><thead>\(head)</thead><tbody>\(body)</tbody></table>"
        }

        let p = recordExport.personalinformation
        let pet = recordExport.petinformation
        let eContacts = recordExport.emergencyContacts

        let bloodTable = table(
            headers: ["Blood Date", "Blood Value Name", "Blood Value Comment"],
            rows: recordExport.blood.map { [$0.bloodDate, $0.bloodName, $0.bloodComment] }
        )

        let drugsTable = table(
            headers: ["Medication Date", "Medication Name & Dosage", "Medication Comment (Why, Schedule)"],
            rows: recordExport.drugs.map { [$0.drugDate, $0.drugName, $0.drugComment] }
        )

        let vaccinationsTable = table(
            headers: ["Vaccination Date", "Vaccination Name", "Vaccination Information", "Vaccination Place", "Vaccination Comment"],
            rows: recordExport.vaccinations.map { [$0.vaccinationDate, $0.vaccinationName, $0.vaccinationInfo, $0.vaccinationPlace, $0.vaccinationComment] }
        )

        let allergyTable = table(
            headers: ["Record Date", "Allergy / Intolerance Name", "Allergy / Intolerance Information", "Allergy / Intolerance Comment"],
            rows: recordExport.allergy.map { [$0.allergyDate, $0.allergyName, $0.allergyInformation, $0.allergyComment] }
        )

        let illnessTable = table(
            headers: ["Illness / Incident Date", "Illness / Incident Name", "Illness / Incident Information / Comment"],
            rows: recordExport.illness.map { [$0.illnessDate, $0.illnessName, $0.illnessComment] }
        )

        let medicalDocumentTable = table(
            headers: ["Medical Document Date", "Medical Document Name", "Medical Document Information / Comment / Stored in EPD"],
            rows: recordExport.medicaldocument.map { [$0.medicaldocumentDate, $0.medicaldocumentName, $0.medicaldocumentComment] }
        )

        let medicalHistoryTable = table(
            headers: ["Medical History Date", "Medical History Name", "Medical History Contact", "Medical History Information / Comment"],
            rows: recordExport.medicalhistory.map { [$0.medicalhistoryDate, $0.medicalhistoryName, $0.medicalhistoryContact, $0.medicalhistoryComment] }
        )

        let risksTable = table(
            headers: ["Record Date", "Riskfactor Name", "Riskfactor Description / Information / Comment"],
            rows: recordExport.risks.map { [$0.risksDate, $0.risksName, $0.risksComment] }
        )

        let weightsTable = table(
            headers: ["Date", "Weight (kg)", "Comment"],
            rows: recordExport.weights.map { [$0.weightDate, String(format: "%.1f", $0.weightKg), $0.weightComment] }
        )

        // Personal / Pet HTML
        let personalHTML: String = {
            if recordExport.isPet, let pet = pet {
                return """
    <div class=\"kv\">
      <div class=\"key\">Name</div><div>\(esc(pet.personalName))</div>
      <div class=\"key\">Animal ID (ANIS)</div><div>\(esc(pet.personalAnimalID))</div>
      <div class=\"key\">Owner Name</div><div>\(esc(pet.ownerName))</div>
      <div class=\"key\">Owner Phone</div><div>\(esc(pet.ownerPhone))</div>
      <div class=\"key\">Owner Email</div><div>\(esc(pet.ownerEmail))</div>
    </div>
"""
            } else {
                return """
    <div class=\"kv\">
      <div class=\"key\">Family Name</div><div>\(esc(p.personalFamilyName))</div>
      <div class=\"key\">Given Name</div><div>\(esc(p.personalGivenName))</div>
      <div class=\"key\">Nick Name</div><div>\(esc(p.personalNickName))</div>
      <div class=\"key\">Gender</div><div>\(esc(p.personalGender))</div>
      <div class=\"key\">Birthdate</div><div>\(esc(p.personalBirthdate))</div>
      <div class=\"key\">Social Security / AHV Nummer</div><div>\(esc(p.personalSocialSecurityNumber))</div>
      <div class=\"key\">Address</div><div>\(esc(p.personalAddress))</div>
      <div class=\"key\">Health Insurance</div><div>\(esc(p.personalHealthInsurance))</div>
      <div class=\"key\">Health Insurance Number</div><div>\(esc(p.personalHealthInsuranceNumber))</div>
      <div class=\"key\">Employer</div><div>\(esc(p.personalEmployer))</div>
    </div>
"""
            }
        }()

        // Emergency contacts HTML
        let emergencyHTML: String = {
            if !eContacts.isEmpty {
                var rows: [String] = []
                for c in eContacts {
                    rows.append("<div class=\"key\">Contact</div><div>\(esc(c.name))</div>")
                    rows.append("<div class=\"key\">Phone</div><div>\(esc(c.phone))</div>")
                    rows.append("<div class=\"key\">Email</div><div>\(esc(c.email))</div>")
                    if !c.note.isEmpty { rows.append("<div class=\"key\">Note</div><div>\(esc(c.note))</div>") }
                }
                return rows.joined(separator: "\n")
            } else {
                // Fallback: show nothing
                return ""
            }
        }()

        // Build date for footer (yyyy-MM)
        let buildDate: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM"
            return f.string(from: Date())
        }()

        return """
<!DOCTYPE html>
<html>
<head>
  <meta charset=\"utf-8\" />
  <title>Medical Health Record - key Information - EPD Informationen</title>
  <style>
    body { font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 12px; }
    h1 { font-size: 18px; }
    h2 { font-size: 14px; margin-top: 18px; }
    .kv { display: grid; grid-template-columns: 220px 1fr; gap: 6px 12px; }
    .key { font-weight: 600; }
    table { width: 100%; border-collapse: collapse; margin-top: 6px; }
    th, td { border: 1px solid #333; padding: 6px; text-align: left; vertical-align: top; }
    footer { margin-top: 24px; font-size: 11px; color: #666 }
    @page { margin: 24px; }
  </style>
</head>
<body>
  <h1>Medical Health Record - key Information - EPD Informationen</h1>

  <h2>Personal Information</h2>
  \(personalHTML)

  <h2>Emergency Information</h2>
  <div class=\"kv\">
    \(emergencyHTML)
  </div>

  <h2>Blood Values</h2>
  \(bloodTable)

  <h2>Medications</h2>
  \(drugsTable)

  <h2>Vaccinations</h2>
  \(vaccinationsTable)

  <h2>Allergies & Intolerances</h2>
  \(allergyTable)

  <h2>Illnesses & Incidents</h2>
  \(illnessTable)

  <h2>Relevant Medical Documents</h2>
  \(medicalDocumentTable)

  <h2>Relevant Medical History</h2>
  \(medicalHistoryTable)

  <h2>Riskfactors</h2>
  \(risksTable)

  \(recordExport.isPet ? "<h2>Weight</h2>\n  \(weightsTable)" : "")

  <footer>
    Built: \(buildDate) — by furfarch
  </footer>
</body>
</html>
"""
    }
}
