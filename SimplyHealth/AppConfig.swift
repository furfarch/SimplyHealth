//
//  AppConfig.swift
//  Simply Health
//
//  Created by Chris Furfari on 22.01.2026.
//

import Foundation

/// Central configuration for Simply Health app
enum AppConfig {
    /// CloudKit configuration constants
    enum CloudKit {
        /// CloudKit container identifier
        static let containerID = "iCloud.com.furfarch.SimplyHealth"

        /// Custom zone name for sharing
        static let shareZoneName = "SimplyHealthShareZone"

        /// Record type name for medical records
        static let recordType = "MedicalRecord"
    }

    /// App information
    enum Info {
        /// App display name
        static let appName = "Simply Health"

        /// App bundle identifier
        static let bundleID = "com.furfarch.SimplyHealth"
    }
}
