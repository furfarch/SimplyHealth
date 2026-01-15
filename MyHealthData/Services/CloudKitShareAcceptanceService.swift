import Foundation
import CloudKit
import SwiftData

/// Accepts a CloudKit share invitation and then triggers a refresh from the Shared database.
@MainActor
final class CloudKitShareAcceptanceService {
    static let shared = CloudKitShareAcceptanceService()

    private let containerIdentifier = "iCloud.com.furfarch.MyHealthData"

    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }

    private init() {}

    func acceptShare(from url: URL, modelContext: ModelContext) async {
        ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: acceptShare url=\(url.absoluteString)")

        do {
            let metadata = try await fetchShareMetadata(for: url)
            try await acceptShareMetadata(metadata)

            ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: accepted share, fetching shared records")
            let sharedFetcher = CloudKitSharedMedicalRecordFetcher(containerIdentifier: containerIdentifier, modelContext: modelContext)
            _ = try await sharedFetcher.fetchAllSharedAsync()
            ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: import from shared database complete")
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: accept failed error=\(error)")
            ShareDebugStore.shared.lastError = error
        }
    }

    private func fetchShareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CKShare.Metadata, Error>) in
            let op = CKFetchShareMetadataOperation(shareURLs: [url])
            var captured: CKShare.Metadata?

            op.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let md):
                    captured = md
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            op.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let md = captured {
                        cont.resume(returning: md)
                    } else {
                        cont.resume(throwing: NSError(domain: "CloudKitShareAcceptanceService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No share metadata returned."]))
                    }
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            self.container.add(op)
        }
    }

    private func acceptShareMetadata(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.qualityOfService = .userInitiated

            op.perShareResultBlock = { md, result in
                switch result {
                case .success(let share):
                    ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: perShare success share=\(share.recordID.recordName) container=\(md.containerIdentifier)")
                case .failure(let err):
                    ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: perShare error=\(err)")
                }
            }

            op.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: ())
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            self.container.add(op)
        }
    }
}
