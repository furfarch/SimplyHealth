import Foundation
import SwiftUI
import Combine

/// Small in-app debug store for CloudKit sharing operations.
@MainActor
final class ShareDebugStore: ObservableObject {
    static let shared = ShareDebugStore()

    @Published var logs: [String] = []
    @Published var lastShareURL: URL? = nil
    @Published var lastError: Error? = nil

    private init() {}

    func appendLog(_ text: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        logs.append("[\(ts)] \(text)")
        // keep recent 200 entries
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
    }

    func clear() {
        logs.removeAll()
        lastShareURL = nil
        lastError = nil
    }

    func exportText() -> String {
        var parts: [String] = []
        parts.append("Share Debug Export")
        parts.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        if let url = lastShareURL {
            parts.append("LastShareURL: \(url.absoluteString)")
        }
        if let err = lastError {
            parts.append("LastError: \(String(describing: err))")
        }
        parts.append("\nLogs:\n")
        parts.append(logs.joined(separator: "\n"))
        return parts.joined(separator: "\n")
    }
}
