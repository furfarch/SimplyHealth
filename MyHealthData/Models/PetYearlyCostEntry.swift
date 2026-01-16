import Foundation
import SwiftData

@Model
final class PetYearlyCostEntry {
    var createdAt: Date
    var updatedAt: Date

    // Local stable identifier
    var uuid: String
    var id: String { uuid }

    /// e.g. "Vet Check Up", "Food", "Insurance"
    var title: String

    /// Date of the expense
    var date: Date

    /// Amount paid for this entry
    var amount: Double

    var note: String

    // Intentionally no inverse relationship back to MedicalRecord.
    // The owning relationship lives on MedicalRecord.petYearlyCosts with cascade delete.

    init(
        uuid: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String = "",
        date: Date = Date(),
        amount: Double = 0,
        note: String = ""
    ) {
        self.uuid = uuid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.date = date
        self.amount = amount
        self.note = note
    }
}
