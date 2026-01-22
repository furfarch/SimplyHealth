import Foundation

/// Applies Apple file protection to files we create ourselves (e.g. export temp files).
///
/// Notes:
/// - SwiftData's persistent store is managed by the framework; we can't reliably set
///   SQLite file protection attributes directly.
/// - For our own output files, we can enforce protection with NSFileProtection.
enum AppFileProtection {
    static let `default` = FileProtectionType.completeUntilFirstUserAuthentication

    static func apply(to url: URL, protection: FileProtectionType = AppFileProtection.default) throws {
        try FileManager.default.setAttributes([
            .protectionKey: protection
        ], ofItemAtPath: url.path)
    }
}
