import Foundation
import SwiftData

@Model
final class BloodEntry {
    var date: Date? = nil
    var name: String = ""
    var comment: String = ""

    var record: MedicalRecord? = nil

    init(date: Date? = nil, name: String = "", comment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.comment = comment
        self.record = record
    }
}
