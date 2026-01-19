import Foundation
import SwiftUI
import Combine

/// No-op in-app debug store for release builds. Keeps API but disables disk IO and logging unless DEBUG is set.
@MainActor
final class ShareDebugStore: ObservableObject {
    static let shared = ShareDebugStore()

    @Published var logs: [String] = []
    @Published var lastShareURL: URL? = nil
    @Published var lastError: Error? = nil

    private let maxEntries = 200

    private init() {
        // Intentionally no disk IO in release; logs only populated in DEBUG builds.
    }

    @inline(__always)
    func appendLog(_ text: String) {
        #if DEBUG
        // Keep an in-memory limited buffer for rare inspection during debug builds
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(text)"
        logs.append(line)
        if logs.count > maxEntries {
            logs.removeFirst(logs.count - maxEntries)
        }
        #endif
    }

    func clear() {
        logs.removeAll()
        lastShareURL = nil
        lastError = nil
    }

    func exportText() -> String {
        #if DEBUG
        var parts: [String] = []
        parts.append("Share Debug Export")
        parts.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        if let url = lastShareURL { parts.append("LastShareURL: \(url.absoluteString)") }
        if let err = lastError { parts.append("LastError: \(String(describing: err))") }
        parts.append("\nLogs:\n")
        parts.append(logs.joined(separator: "\n"))
        return parts.joined(separator: "\n")
        #else
        return "Share Debug Export: disabled in Release builds."
        #endif
    }
}
