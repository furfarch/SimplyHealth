import SwiftUI
import CloudKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accountStatusText: String? = nil

    private var platformName: String {
        #if targetEnvironment(macCatalyst)
        return "Mac Catalyst"
        #elseif os(macOS)
        return "macOS (native)"
        #else
        return "iOS"
        #endif
    }

    private var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (build \(b))"
    }

    private func mapAccountStatus(_ s: CKAccountStatus) -> String {
        switch s {
        case .available: return "Available"
        case .noAccount: return "No iCloud account"
        case .restricted: return "Restricted"
        case .couldNotDetermine: return "Could not determine"
        case .temporarilyUnavailable: return "Temporarily unavailable"
        @unknown default: return "Unknown"
        }
    }

    private func refreshICloudStatus() async {
        do {
            let status = try await CKContainer(identifier: AppConfig.CloudKit.containerID).accountStatus()
            accountStatusText = mapAccountStatus(status)
        } catch {
            accountStatusText = "Check failed: \(error.localizedDescription)"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("MyHealthData")
                    .font(.title)
                    .bold()
                Text("Build: 2026-01, by furfarch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Data & Privacy\nThis app lets you store health and medical information securely on your device. By default, all data remains stored locally.\n\nYou can optionally enable cloud synchronization to access your data across multiple devices or share it with other people. When cloud sync is enabled, your data is transferred to and stored on Apple iCloud servers and protected using Apple’s standard encryption.\n\nPlease note that if you choose to export your data and store it externally, the exported files are not encrypted.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                // Runtime diagnostics (visible in About so TestFlight / user can report)
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    Text("Runtime info")
                        .font(.headline)
                    Text("Platform: \(platformName)")
                    Text("Mode: \(buildConfiguration)")
                    Text("Version: \(appVersion)")
                    Text("Bundle: \(Bundle.main.bundleIdentifier ?? "?")")
                    if let acct = accountStatusText {
                        Text("iCloud: \(acct)")
                    } else {
                        Text("iCloud: checking…")
                            .task { await refreshICloudStatus() }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("About")
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        #endif
    }
}

#Preview {
    AboutView()
}
