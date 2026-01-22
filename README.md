# Simply Health

**Part of the Simply Series** - Minimalist apps focused on one tracking task at a time.

A SwiftUI-based iOS and macOS application for managing personal medical records with CloudKit integration for cloud synchronization and sharing.

## Overview

Simply Health helps you keep track of your medical information and that of your pets in one secure, private application. All data is stored locally on your device using SwiftData, with optional CloudKit synchronization for backup and sharing across devices.

## Features

- 📱 **Multi-Platform Support**: Native apps for iOS (iPhone & iPad) and macOS
- 🔒 **Privacy-First**: All data stored locally on your device
- ☁️ **Optional Cloud Sync**: CloudKit integration for backup and synchronization
- 🤝 **Sharing**: Share medical records with family members or healthcare providers
- 👥 **Support for Humans and Pets**: Manage medical records for all family members
- 📊 **Comprehensive Record Types**:
  - Blood work and lab results
  - Medications and prescriptions
  - Vaccinations
  - Allergies
  - Medical history
  - Doctor visits
  - Weight tracking
  - Medical documents
  - Emergency contacts

## Requirements

- **iOS**: 26.2 or later
- **macOS**: 26.2 or later
- **Xcode**: Latest version with Swift 5.0 support
- **Development Tools**: Swift, SwiftUI, SwiftData

## Technology Stack

- **Language**: Swift 5.0
- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData
- **Cloud Services**: CloudKit (optional)
- **Testing**: Swift Testing framework

## Getting Started

### Prerequisites

1. Xcode installed on your Mac
2. An Apple Developer account (for CloudKit features)
3. iOS 26.2+ device/simulator or macOS 26.2+ system

### Building the Project

1. Clone the repository:
   ```bash
   git clone https://github.com/furfarch/SimplyHealth.git
   cd SimplyHealth
   ```

2. Open the project in Xcode:
   ```bash
   open SimplyHealth.xcodeproj
   ```

3. Select your target device (iOS Simulator, iPad Simulator, or My Mac)

4. Build and run the project (⌘R)

### Running Tests

Tests use the Swift Testing framework. To run tests:

1. In Xcode, open the Test Navigator (⌘6)
2. Click the play button next to "SimplyHealthTests"
3. Or use the keyboard shortcut (⌘U)

## Project Structure

```
SimplyHealth/
├── SimplyHealth/
│   ├── Models/              # SwiftData model definitions
│   ├── Views/               # SwiftUI views
│   │   ├── RecordEditor/    # Record editing views
│   │   └── RecordViewer/    # Record viewing views
│   ├── Services/            # Business logic and services
│   ├── AppConfig.swift      # Centralized configuration
│   └── Assets.xcassets      # Asset catalog
├── SimplyHealthTests/       # Unit tests
└── SimplyHealthUITests/     # UI tests
```

## CloudKit Integration

CloudKit features are opt-in per record:

- **Container ID**: `iCloud.com.furfarch.SimplyHealth`
- **Features**:
  - Private database for personal records
  - Shared database for records shared with others
  - Real-time synchronization across devices
  - Participant management for shared records

To enable CloudKit for a record:
1. Toggle "Enable Cloud Sync" in the record settings
2. Optionally enable sharing to share with others

## Architecture

### Data Models

- Built with SwiftData `@Model` macro
- Cascade delete rules for data integrity
- Support for relationships between entities
- Stable identifiers using `uuid` fields

### Views

- Declarative SwiftUI patterns
- Environment-based dependency injection
- Separate concerns for editing and viewing
- Preview providers for development

### Services

- CloudKit synchronization services
- PDF export functionality
- Contact management
- Share management

## Simply Series Apps

Simply Health is part of a family of minimalist tracking apps:

- **Simply Drive** - Vehicle tracking, drive logs, and maintenance checklists
- **Simply Health** - Medical records and health tracking for humans and pets
- **Simply Train** - Workout and training tracker (coming soon)

Each app in the Simply Series follows the same design principles:
- Minimalist approach with essential features only
- Fast data entry and retrieval
- Clean, intuitive interfaces
- Focused scope - one problem solved comprehensively
- Consistent architecture across all apps

## Contributing

This is a personal project, but suggestions and feedback are welcome. Please open an issue to discuss potential changes.

## Privacy & Security

- All data is stored locally on your device by default
- CloudKit integration is optional and user-controlled
- No third-party analytics or tracking
- Full control over data sharing
- iOS hardware encryption protects your data

## License

[Add your license information here]

## Support

For issues, questions, or feature requests, please open an issue on GitHub.

## Acknowledgments

Built with SwiftUI and SwiftData, leveraging Apple's modern app development frameworks.
