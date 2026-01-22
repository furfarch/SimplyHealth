import SwiftUI

struct RecordViewerSectionDetails: View {
    let record: MedicalRecord

    private var createdString: String {
        record.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var updatedString: String {
        record.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordViewerRow(title: "Location", value: record.locationStatus.accessibilityLabel)

            if record.isCloudEnabled {
                RecordViewerRow(title: "Cloud Enabled", value: "Yes")
                RecordViewerRow(title: "Sharing Enabled", value: record.isSharingEnabled ? "Yes" : "No")

                if let shareRecordName = record.cloudShareRecordName, !shareRecordName.isEmpty {
                    RecordViewerRow(title: "Share Record", value: shareRecordName)
                }

                if !record.shareParticipantsSummary.isEmpty {
                    RecordViewerRow(title: "Participants", value: record.shareParticipantsSummary)
                }
            } else {
                RecordViewerRow(title: "Cloud Enabled", value: "No")
            }

            RecordViewerRow(title: "Created", value: createdString)
            RecordViewerRow(title: "Updated", value: updatedString)
        }
    }
}
