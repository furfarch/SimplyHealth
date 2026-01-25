//
//  AppConfig.swift
//  Purus Health
//
//  Created by Chris Furfari on 22.01.2026.
//

import Foundation

/// Central configuration for Purus Health app
enum AppConfig {
    /// CloudKit configuration constants
    enum CloudKit {
        /// CloudKit container identifier
        static let containerID = "iCloud.com.purus.health"

        /// Custom zone name for sharing
        static let shareZoneName = "PurusHealthShareZone"

        /// Record type name for medical records
        static let recordType = "MedicalRecord"
    }

    /// App information
    enum Info {
        /// App display name
        static let appName = "Purus Health"

        /// App bundle identifier
        static let bundleID = "com.purus.health"
    }
}
