import Foundation

/// Centralized notification names used throughout the app
enum NotificationNames {
    /// Posted after records are successfully imported from CloudKit
    static let didImportRecords = Notification.Name("MyHealthData.DidImportRecords")
    
    /// Posted after a share is accepted and imported
    static let didAcceptShare = Notification.Name("MyHealthData.DidAcceptShare")
    
    /// Posted when shared records need to be refreshed
    static let didChangeSharedRecords = Notification.Name("MyHealthData.DidChangeSharedRecords")

    /// Posted when a share URL is received (pending) — used to notify the UI to accept/import it
    static let pendingShareReceived = Notification.Name("MyHealthData.PendingShareReceived")
}
