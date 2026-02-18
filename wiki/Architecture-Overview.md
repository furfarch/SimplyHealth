# Architecture Overview

Purus Health follows a clean, layered architecture based on Apple's modern app development frameworks: SwiftUI for the presentation layer, SwiftData for persistence, and CloudKit for cloud synchronization.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   SwiftUI Views Layer                    │
│  (RecordListView, RecordEditorView, RecordViewerView)  │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│                    Services Layer                        │
│  (CloudSyncService, ExportService, PDFRenderer, etc.)   │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│                   SwiftData Models                       │
│     (MedicalRecord, BloodEntry, DrugEntry, etc.)        │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│              Persistence & Cloud Storage                 │
│        (SwiftData Local Storage + CloudKit)              │
└─────────────────────────────────────────────────────────┘
```

## Design Principles

### 1. **Separation of Concerns**
- **Models**: Pure data structures with SwiftData persistence
- **Views**: SwiftUI declarative UI components
- **Services**: Business logic, cloud sync, and external integrations

### 2. **Privacy-First Design**
- Local-first storage using SwiftData
- CloudKit integration is opt-in per record
- No third-party analytics or tracking
- Full user control over data sharing

### 3. **Multi-Platform Support**
- Shared codebase for iOS and macOS
- Platform-specific implementations where needed (PDF rendering, contact picker)
- Conditional compilation using `#if canImport(UIKit)`

### 4. **Minimalist Approach**
- Essential features only
- Clean, intuitive interfaces
- Fast data entry and retrieval
- Part of the "Simply Series" philosophy

## Core Components

### 1. Data Layer (Models)

**Primary Model**: `MedicalRecord`
- Central entity representing a person's or pet's medical record
- Contains personal information, medical history, and relationships to various entry types

**Entry Types**:
- `BloodEntry` - Blood work and lab results
- `DrugEntry` - Medications and prescriptions
- `VaccinationEntry` - Vaccination records
- `AllergyEntry` - Allergy information
- `IllnessEntry` - Medical conditions
- `RiskEntry` - Health risk factors
- `MedicalHistoryEntry` - Medical history events
- `MedicalDocumentEntry` - Attached documents
- `WeightEntry` - Weight tracking
- `HumanDoctorEntry` - Doctor information
- `PetYearlyCostEntry` - Pet medical costs
- `EmergencyContact` - Emergency contact information

**Key Patterns**:
- Use of `@Model` macro for SwiftData persistence
- Cascade delete rules for data integrity
- Optional backing storage for CloudKit compatibility
- UUID-based stable identifiers

### 2. View Layer (SwiftUI)

**Main Views**:
- `ContentView` - Root view with navigation
- `RecordListView` - List of all medical records
- `RecordEditorView` - Record editing interface
- `RecordViewerView` - Read-only record display

**View Organization**:
```
Views/
├── RecordEditor/        # Editing sub-views
│   ├── RecordEditorSectionPersonal.swift
│   ├── RecordEditorSectionEntries.swift
│   ├── RecordEditorSectionDoctors.swift
│   └── ...
└── RecordViewer/        # Viewing sub-views
    ├── RecordViewerSectionPersonal.swift
    ├── RecordViewerSectionEntries.swift
    └── ...
```

**View Patterns**:
- Environment-based dependency injection (`@Environment(\.modelContext)`)
- Separate concerns: editing vs. viewing
- Preview providers for development
- Support for both human and pet records

### 3. Service Layer

**CloudKit Services**:
- `CloudSyncService` - Synchronizes records with CloudKit
- `CloudKitMedicalRecordFetcher` - Fetches records from private database
- `CloudKitSharedZoneMedicalRecordFetcher` - Fetches shared records
- `CloudKitShareAcceptanceService` - Handles share acceptance
- `CloudKitShareParticipantsService` - Manages share participants

**Export Services**:
- `ExportService` - Coordinates export operations
- `MedicalRecordExport` - Exports record data
- `PDFRenderer` (protocol) - Platform-agnostic PDF rendering
- `iOSPDFRenderer` - iOS implementation
- `macOSPDFRenderer` - macOS implementation
- `HTMLTemplateRenderer` - Generates HTML for PDF export

**Other Services**:
- `ContactPicker` - Platform-specific contact selection
- `AppFileProtection` - File system security
- `ShareDebugStore` - Debugging utilities for sharing

## Data Flow

### Local Data Operations

1. **Create Record**:
   ```
   User Input → RecordEditorView → ModelContext.insert() → SwiftData Storage
   ```

2. **Read Records**:
   ```
   SwiftData Storage → FetchDescriptor → ModelContext.fetch() → RecordListView
   ```

3. **Update Record**:
   ```
   User Input → RecordEditorView → Model Property Update → ModelContext.save()
   ```

4. **Delete Record**:
   ```
   User Action → ModelContext.delete() → Cascade Delete Related Entries
   ```

### Cloud Sync Operations

1. **Enable Cloud Sync**:
   ```
   User Toggles → isCloudEnabled = true → CloudSyncService.syncIfNeeded()
   ```

2. **Upload to CloudKit**:
   ```
   Local Record → CloudSyncService.applyMedicalRecord() → CKRecord → CloudKit
   ```

3. **Download from CloudKit**:
   ```
   CloudKit → CloudKitMedicalRecordFetcher → importToSwiftData() → Local Record
   ```

4. **Share Record**:
   ```
   User Action → CKShare Creation → CloudShareSheet → Share URL → Recipient
   ```

### JSON Serialization for CloudKit

Since CloudKit doesn't support direct relationship storage like SwiftData, the app serializes relationship arrays to JSON:

```swift
// Example: Serializing vaccinations to CloudKit
let vaccinationData = try JSONEncoder().encode(record.vaccinations)
ckRecord["vaccinationEntries"] = String(data: vaccinationData, encoding: .utf8)
```

This allows complex relationships to be stored in CloudKit STRING fields while maintaining SwiftData relationships locally.

## State Management

### SwiftData Context
- Main context provided via `@Environment(\.modelContext)`
- Background contexts for CloudKit operations
- Automatic change tracking and persistence

### UserDefaults
- `cloudEnabled` - Global cloud sync preference
- `pendingSharedImport` - Flag for pending share acceptance
- Service-specific settings

### CloudKit State
- `isCloudEnabled` - Per-record cloud sync flag
- `isSharingEnabled` - Per-record sharing flag
- `cloudShareRecordName` - Share identifier
- `recordLocation` - Record location status (.local, .iCloud, .shared)

## Threading Model

### Main Thread (@MainActor)
- All SwiftUI view updates
- SwiftData context operations (main context)
- User interactions

### Background Threads
- CloudKit operations
- PDF generation
- JSON serialization/deserialization
- Network requests

**Pattern**:
```swift
Task {
    // Background work
    let data = await fetchFromCloudKit()
    
    await MainActor.run {
        // Update UI on main thread
        updateView(with: data)
    }
}
```

## Error Handling

### Graceful Degradation
- If persistent storage fails, fall back to in-memory storage
- If CloudKit sync fails, continue with local operations
- Best-effort sync with error logging

### Error Logging
- `ShareDebugStore` for debugging share operations
- Console logging with component prefixes (e.g., `[PurusHealthApp]`)
- Non-blocking error handling to prevent app crashes

## Security and Privacy

### Data Protection
- iOS hardware encryption for local storage
- File protection attributes via `AppFileProtection`
- No third-party data sharing

### CloudKit Security
- User authentication via iCloud
- Private database for personal records
- Shared database with participant management
- User-controlled sharing permissions

## Configuration

### AppConfig
Central configuration file for app-wide constants:

```swift
enum AppConfig {
    enum CloudKit {
        static let containerID = "iCloud.com.purus.health"
        static let shareZoneName = "PurusHealthShareZone"
        static let recordType = "MedicalRecord"
    }
    
    enum Info {
        static let appName = "Purus Health"
        static let bundleID = "com.purus.health"
    }
}
```

## Next Steps

- Learn more about [Data Models](Data-Models)
- Explore [Views and UI](Views-and-UI)
- Understand [Services](Services)
- Deep dive into [CloudKit Integration](CloudKit-Integration)
