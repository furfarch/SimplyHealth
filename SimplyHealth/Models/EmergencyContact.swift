import Foundation
import SwiftData

@Model
final class EmergencyContact {
    var id: UUID = UUID()
    var name: String = ""
    var phone: String = ""
    var email: String = ""
    var note: String = ""

    var record: MedicalRecord? = nil

    init(id: UUID = UUID(), name: String = "", phone: String = "", email: String = "", note: String = "", record: MedicalRecord? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.note = note
        self.record = record
    }
}
