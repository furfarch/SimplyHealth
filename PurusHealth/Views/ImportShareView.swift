import SwiftUI
import SwiftData

struct ImportShareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var urlString: String = ""
    @State private var isImporting: Bool = false
    @State private var statusMessage: String?
    @State private var progress: Double? = nil

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
                        if isImporting {
                            HStack(spacing: 8) {
                                ProgressView(value: progress)
                                Text("Importing…")
                            }
                        } else {
                            Text("Import")
                        }
                    }
                    .disabled(isImporting || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(minWidth: 480)
            .navigationTitle("Import Share URL")
            .overlay(alignment: .bottom) {
                if isImporting {
                    HStack(spacing: 8) {
                        if let p = progress {
                            ProgressView(value: p)
                                .frame(width: 80)
                        } else {
                            ProgressView()
                        }
                        Text(statusMessage ?? "Importing shared record…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
                    .accessibilityLabel("Importing shared record")
                }
            }
        }
    }

    private func importAction() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "Invalid URL"
            return
        }

        isImporting = true
        progress = nil
        statusMessage = "Starting…"

        Task { @MainActor in
            // Accept the share and then fetch shared zones to materialize data
            await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
            statusMessage = "Fetching shared data…"
            do {
                let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID, modelContext: modelContext)
                _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
                statusMessage = "Import complete"
            } catch {
                statusMessage = "Import failed: \(error.localizedDescription)"
            }
            isImporting = false
        }
    }
}

#Preview {
    ImportShareView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
