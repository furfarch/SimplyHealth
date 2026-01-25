# Purus Health - Copilot Instructions

## Project Overview

Purus Health is a SwiftUI-based iOS/macOS application for managing personal medical records. The app uses SwiftData for local persistence and CloudKit for cloud synchronization and sharing capabilities.

## Technology Stack

- **Language**: Swift 5.0
- **Framework**: SwiftUI
- **Data Persistence**: SwiftData with CloudKit integration
- **Testing**: Swift Testing framework (using `@Test` macro)
- **Platforms**: iOS and macOS

## Architecture

### Data Models

- Use `@Model` macro for SwiftData entities
- All models inherit cascade delete rules via `@Relationship(deleteRule: .cascade)`
- Main entity is `MedicalRecord` with relationships to various entry types (BloodEntry, DrugEntry, VaccinationEntry, etc.)
- Use `uuid` field for stable identifiers (avoid using `id` which conflicts with SwiftData synthesized id)
- Conform to `Identifiable` by providing a computed `id` property that returns `uuid`

### CloudKit Integration

- CloudKit features are opt-in per record via `isCloudEnabled` flag
- Support for sharing records with `isSharingEnabled` and `cloudShareRecordName`
- Use `CloudKitMedicalRecordFetcher` for syncing
- ModelConfiguration uses `cloudKitDatabase: .none` for local storage

### Views and UI

- Follow SwiftUI declarative patterns
- Use `@Environment(\.modelContext)` for data access
- Separate concerns: Views in `Views/`, Models in `Models/`, Services in `Services/`
- Support both human and pet records (check `isPet` flag)

## Coding Standards

### Swift Conventions

- Use Swift's standard naming conventions (camelCase for properties and methods, PascalCase for types)
- Prefer explicit type annotations for clarity in model properties
- Use descriptive property names (e.g., `personalGivenName` instead of `firstName`)
- Mark classes as `final` when inheritance is not intended

### SwiftUI Best Practices

- Use `@MainActor` when required for UI operations
- Leverage SwiftUI property wrappers appropriately (`@State`, `@Binding`, `@Environment`)
- Create preview providers using `#Preview` macro
- For previews, use in-memory model containers: `.modelContainer(for: MedicalRecord.self, inMemory: true)`

### Data Management

- Always use `ModelConfiguration` with `isStoredInMemoryOnly: false` for persistent storage
- Use cascade delete rules to maintain data integrity
- Handle ModelContainer creation errors gracefully with fallback to in-memory storage
- Save context after modifications: `try context.save()`

### Error Handling

- Use Swift's `do-catch` blocks for error-prone operations
- Provide fallback behavior when operations fail (see `SimplyHealthApp.init()` for example)
- Log errors with descriptive messages using print statements with component prefix (e.g., `[PurusHealthApp]`)

## Testing Guidelines

### Test Framework

- Use Swift Testing framework with `@Test` macro (not XCTest)
- Import the module under test with `@testable import SimplyHealth`
- Use `#expect()` assertions instead of XCTAssert
- Mark async tests with `async throws`
- Use `@MainActor` for tests that interact with SwiftData contexts

### Test Structure

- Group related tests in structs
- Use descriptive test names that explain what is being tested
- Clean up test data after tests complete (delete created records)
- For persistence tests, create separate ModelContainer instances to verify data is truly persisted

### Testing Conventions

- Test model properties and computed values
- Test data persistence across container instances
- Verify cascade delete behavior
- Test edge cases (empty strings, nil values, etc.)
- Avoid using predicate APIs/macros in tests; fetch all and filter in-memory for compatibility

## File Organization

```
SimplyHealth/
├── Models/           # SwiftData model definitions
├── Views/            # SwiftUI views
│   └── RecordEditor/ # Sub-views for editing
│   └── RecordViewer/ # Sub-views for viewing
├── Services/         # Business logic and services
└── Assets.xcassets   # Asset catalog
```

## Building and Testing

### Building

- This is an Xcode project (`.xcodeproj`)
- Build using Xcode or `xcodebuild` command-line tools
- Supports both iOS and macOS targets

### Running Tests

- Tests are located in `SimplyHealthTests/`
- Use Swift Testing framework
- Run tests through Xcode Test Navigator or using `xcodebuild test`

## Cloud and Sharing Features

- CloudKit container identifier: `iCloud.com.purus.health`
- Sharing is per-record, not app-wide
- Use `CloudSyncService` for cloud operations
- Track record location status: `.local`, `.iCloud`, or `.shared`

## Important Notes

- Support both human and pet medical records (check `isPet` field)
- Display names differ for humans vs pets (use `displayName` computed property)
- Legacy emergency contact fields exist for backward compatibility
- New emergency contacts use the `EmergencyContact` relationship
- Always use persistent storage unless specifically testing in-memory scenarios
