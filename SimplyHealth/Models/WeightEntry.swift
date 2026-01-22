import Foundation
import SwiftData

@Model
final class WeightEntry {
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Local stable identifier
    var uuid: String = UUID().uuidString
    var id: String { uuid }

    var date: Date? = nil
    var weightKg: Double? = nil
    var comment: String = ""

    var record: MedicalRecord? = nil

    init(
        uuid: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        date: Date? = nil,
        weightKg: Double? = nil,
        comment: String = "",
        record: MedicalRecord? = nil
    ) {
        self.uuid = uuid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.weightKg = weightKg
        self.comment = comment
        self.record = record
    }
}
