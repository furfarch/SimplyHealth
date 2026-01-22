import Foundation

/// Small store to hold a pending share URL received before the SwiftUI scene is ready.
final class PendingShareStore {
    static let shared = PendingShareStore()
    private init() {}

    private let queue = DispatchQueue(label: "PendingShareStore")
    private var _pendingURL: URL?

    var pendingURL: URL? {
        get { queue.sync { _pendingURL } }
        set { queue.sync { _pendingURL = newValue } }
    }

    func consume() -> URL? {
        return queue.sync { () -> URL? in
            let u = _pendingURL
            _pendingURL = nil
            return u
        }
    }
}
