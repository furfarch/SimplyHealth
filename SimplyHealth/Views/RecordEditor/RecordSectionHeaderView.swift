import SwiftUI

struct RecordSectionHeaderView: View {
    let section: RecordSection

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: section.sfSymbol)
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            Text(section.title)
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}
