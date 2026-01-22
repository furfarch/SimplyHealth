import SwiftUI
import CloudKit
import SwiftData

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#endif

struct CloudShareSheet: View {
    let record: MedicalRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isBusy = false
    @State private var errorMessage: String?

    #if os(iOS) || targetEnvironment(macCatalyst)
    @State private var showShareSheet = false
    @State private var shareController: UICloudSharingController?
    #else
    @State private var shareURL: URL?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Share this record using iCloud. You can invite others and manage permissions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                #if os(iOS) || targetEnvironment(macCatalyst)
                if let errorMessage {
                    Section("Error") { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await presentShareSheet_iOS() }
                    } label: {
                        if isBusy { ProgressView() } else { Text("Share Record") }
                    }
                }
                .background(
                    ShareSheetPresenter(controller: $shareController, isPresented: $showShareSheet)
                )
                #else
                if let shareURL {
                    Section("Share") {
                        Text(shareURL.absoluteString)
                            .font(.footnote)
                            .textSelection(.enabled)
                        Button("Copy Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(shareURL.absoluteString, forType: .string)
                        }
                    }
                }

                if let errorMessage {
                    Section("Error") { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await createShare_mac() }
                    } label: {
                        if isBusy { ProgressView() } else { Text("Create Share") }
                    }
                }
                #endif
            }
            .navigationTitle("Share Record")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    // MARK: - iOS flow
    #if os(iOS) || targetEnvironment(macCatalyst)
    @MainActor
    private func presentShareSheet_iOS() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let controller = try await CloudSyncService.shared.makeCloudSharingController(for: record) { result in
                DispatchQueue.main.async {
                    self.showShareSheet = false
                    switch result {
                    case .success:
                        self.errorMessage = nil
                        Task { @MainActor in
                            await CloudKitShareParticipantsService.shared.refreshParticipantsSummary(for: record)
                        }
                    case .failure(let err):
                        self.errorMessage = err.localizedDescription
                    }
                }
            }
            shareController = controller
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    struct ShareSheetPresenter: UIViewControllerRepresentable {
        @Binding var controller: UICloudSharingController?
        @Binding var isPresented: Bool
        func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
            guard isPresented, let controller else { return }
            if uiViewController.presentedViewController == nil {
                uiViewController.present(controller, animated: true) { isPresented = false }
            }
        }
    }
    #endif

    // MARK: - macOS fallback
    #if os(macOS)
    @MainActor
    private func createShare_mac() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let share = try await CloudSyncService.shared.createShare(for: record)
            if let url = share.url {
                shareURL = url
            } else {
                errorMessage = "Share created but no URL available. Check iCloud account and container schema."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif
}
