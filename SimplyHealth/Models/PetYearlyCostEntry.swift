import Foundation
import SwiftData

@Model
final class PetYearlyCostEntry {
    var createdAt: Date
    var updatedAt: Date

    // Local stable identifier
    var uuid: String
    var id: String { uuid }

    // Transaction date and derived year
    var date: Date
    var year: Int

    var category: String
    var amount: Double
    var note: String

    // Inverse is declared on MedicalRecord.petYearlyCosts.
    var record: MedicalRecord?

    init(
        uuid: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        date: Date = Date(),
        year: Int? = nil,
        category: String = "",
        amount: Double = 0,
        note: String = "",
        record: MedicalRecord? = nil
    ) {
        self.uuid = uuid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        // If year is provided use it, otherwise derive from date
        self.year = year ?? Calendar.current.component(.year, from: date)
        self.category = category
        self.amount = amount
        self.note = note
        self.record = record
    }
}
