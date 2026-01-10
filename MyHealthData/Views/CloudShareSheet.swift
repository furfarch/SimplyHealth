import SwiftUI
import CloudKit
import UIKit

struct CloudShareSheet: View {
    let record: MedicalRecord

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var shareController: UICloudSharingController?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Share this record using iCloud. You can invite others and manage permissions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await presentShareSheet() }
                    } label: {
                        Text("Share Record")
                    }
                }
            }
            .navigationTitle("Share Record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .background(
                ShareSheetPresenter(controller: $shareController, isPresented: $showShareSheet)
            )
        }
    }

    @MainActor
    private func presentShareSheet() async {
        errorMessage = nil
        do {
            let shareController = try await CloudSyncService.shared.makeCloudSharingController(for: record) { result in
                DispatchQueue.main.async {
                    self.showShareSheet = false
                    switch result {
                    case .success:
                        self.errorMessage = nil // Sharing completed or stopped
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
            self.shareController = shareController
            self.showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var controller: UICloudSharingController?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented, let controller else { return }
        if uiViewController.presentedViewController == nil {
            uiViewController.present(controller, animated: true) {
                isPresented = false
            }
        }
    }
}
