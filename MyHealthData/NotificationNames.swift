import Foundation

/// Centralized notification names used throughout the app
enum NotificationNames {
    /// Posted after records are successfully imported from CloudKit
    static let didImportRecords = Notification.Name("MyHealthData.DidImportRecords")
    
    /// Posted after a share is accepted and imported
    static let didAcceptShare = Notification.Name("MyHealthData.DidAcceptShare")
    
    /// Posted when shared records need to be refreshed
    static let didChangeSharedRecords = Notification.Name("MyHealthData.DidChangeSharedRecords")
}
