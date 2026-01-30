import Foundation
import CloudKit

/// Small store to hold a pending share URL or metadata received before the SwiftUI scene is ready.
final class PendingShareStore {
    static let shared = PendingShareStore()
    private init() {}

    private let queue = DispatchQueue(label: "PendingShareStore")
    private var _pendingURL: URL?
    private var _pendingMetadata: CKShare.Metadata?

    var pendingURL: URL? {
        get { queue.sync { _pendingURL } }
        set { queue.sync { _pendingURL = newValue } }
    }

    var pendingMetadata: CKShare.Metadata? {
        get { queue.sync { _pendingMetadata } }
        set { queue.sync { _pendingMetadata = newValue } }
    }

    func consumeURL() -> URL? {
        return queue.sync { () -> URL? in
            let u = _pendingURL
            _pendingURL = nil
            return u
        }
    }

    func consumeMetadata() -> CKShare.Metadata? {
        return queue.sync { () -> CKShare.Metadata? in
            let m = _pendingMetadata
            _pendingMetadata = nil
            return m
        }
    }

    /// Legacy method - prefer consumeURL() or consumeMetadata()
    func consume() -> URL? {
        return consumeURL()
    }
}
