import Foundation

/// Centralized notification names used throughout the app
enum NotificationNames {
    /// Posted after records are successfully imported from CloudKit
    static let didImportRecords = Notification.Name("PurusHealth.DidImportRecords")

    /// Posted after a share is accepted and imported
    static let didAcceptShare = Notification.Name("PurusHealth.DidAcceptShare")

    /// Posted when shared records need to be refreshed
    static let didChangeSharedRecords = Notification.Name("PurusHealth.DidChangeSharedRecords")

    /// Posted when a share URL is received (pending) — used to notify the UI to accept/import it
    static let pendingShareReceived = Notification.Name("PurusHealth.PendingShareReceived")
}
