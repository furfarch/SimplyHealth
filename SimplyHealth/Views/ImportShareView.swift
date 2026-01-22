import SwiftUI
import SwiftData

struct ImportShareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var urlString: String = ""
    @State private var isImporting: Bool = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste a CloudKit share link (https://www.icloud.com/share/...) and tap Import.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Share URL", text: $urlString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disableAutocorrection(true)
                    #if canImport(UIKit)
                    .autocapitalization(.none)
                    #endif

                if let status = statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button(action: importAction) {
                        if isImporting { ProgressView() } else { Text("Import") }
                    }
                    .disabled(isImporting || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(minWidth: 480)
            .navigationTitle("Import Share URL")
        }
    }

    private func importAction() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "Invalid URL"
            return
        }

        isImporting = true
        statusMessage = "Importing…"

        Task { @MainActor in
            await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
            statusMessage = "Import complete"
            isImporting = false
            // Keep the sheet open so user can see message; they can close manually.
        }
    }
}

#Preview {
    ImportShareView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
