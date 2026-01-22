import Foundation
import SwiftData

@Model
final class HumanDoctorEntry {
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var uuid: String = UUID().uuidString
    var id: String { uuid }

    /// e.g. "GP", "Dentist", "Cardiologist"
    var type: String = ""

    /// Doctor's name
    var name: String = ""

    var phone: String = ""
    var email: String = ""
    var address: String = ""
    var note: String = ""

    var record: MedicalRecord? = nil

    init(
        uuid: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        type: String = "",
        name: String = "",
        phone: String = "",
        email: String = "",
        address: String = "",
        note: String = "",
        record: MedicalRecord? = nil
    ) {
        self.uuid = uuid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.type = type
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.note = note
        self.record = record
    }
}
