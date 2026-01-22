import SwiftUI

struct RecordViewerRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)

            Text(value.isEmpty ? "—" : value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .padding(.vertical, 6)
        .padding(.horizontal)
    }
}

struct RecordViewerDateRow: View {
    let title: String
    let value: Date?

    var body: some View {
        RecordViewerRow(
            title: title,
            value: value.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
        )
    }
}
