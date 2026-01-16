import Foundation
import SwiftData

@Model
final class PetYearlyCostEntry {
    var createdAt: Date
    var updatedAt: Date

    // Local stable identifier
    var uuid: String
    var id: String { uuid }

    var title: String
    var date: Date
    var amount: Double?
    var note: String

    // Keep a plain reference to the owning record; the inverse is declared on MedicalRecord.
    var record: MedicalRecord?

    init(
        uuid: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String = "",
        date: Date = Date(),
        amount: Double? = nil,
        note: String = "",
        record: MedicalRecord? = nil
    ) {
        self.uuid = uuid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.date = date
        self.amount = amount
        self.note = note
        self.record = record
    }
}
