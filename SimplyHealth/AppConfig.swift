//
//  AppConfig.swift
//  Purus Health
//
//  Created by Chris Furfari on 22.01.2026.
//

import Foundation

/// Central configuration for Purus Health app
/// Properties marked nonisolated(unsafe) to allow access from any actor context
enum AppConfig {
    /// CloudKit configuration constants
    enum CloudKit {
        /// CloudKit container identifier
        nonisolated(unsafe) static let containerID = "iCloud.com.purus.health"

        /// Custom zone name for sharing
        nonisolated(unsafe) static let shareZoneName = "PurusHealthShareZone"

        /// Record type name for medical records
        nonisolated(unsafe) static let recordType = "MedicalRecord"
    }

    /// App information
    enum Info {
        /// App display name
        nonisolated(unsafe) static let appName = "Purus Health"

        /// App bundle identifier
        nonisolated(unsafe) static let bundleID = "com.purus.health"
    }
}
