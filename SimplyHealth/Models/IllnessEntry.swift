import Foundation
import SwiftData

@Model
final class IllnessEntry {
    var date: Date? = nil
    var name: String = ""
    var informationOrComment: String = ""

    var record: MedicalRecord? = nil

    init(date: Date? = nil, name: String = "", informationOrComment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.informationOrComment = informationOrComment
        self.record = record
    }
}
