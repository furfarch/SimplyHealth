# Services

Services in Purus Health handle business logic, external integrations, and operations that go beyond basic data management. They provide a clean separation between the UI layer and complex operations.

## Service Architecture

Services are organized into several categories:

```
Services/
├── CloudKit Services       # Cloud synchronization and sharing
├── Export Services        # PDF and data export
├── Platform Services      # Platform-specific implementations
└── Utility Services       # Helper services
```

## CloudKit Services

These services handle all CloudKit-related operations for syncing and sharing medical records.

### CloudSyncService

**Purpose**: Manages synchronization of medical records with CloudKit private database.

```swift
@MainActor
class CloudSyncService {
    static let shared = CloudSyncService()
    
    private let containerID: String
    private let container: CKContainer
    private let privateDB: CKDatabase
    
    init(containerID: String = AppConfig.CloudKit.containerID) {
        self.containerID = containerID
        self.container = CKContainer(identifier: containerID)
        self.privateDB = container.privateCloudDatabase
    }
    
    /// Syncs a record to CloudKit if needed
    func syncIfNeeded(record: MedicalRecord) async throws {
        guard record.isCloudEnabled else { return }
        
        // Upload to CloudKit
        try await uploadRecord(record)
    }
    
    /// Uploads a medical record to CloudKit
    private func uploadRecord(_ record: MedicalRecord) async throws {
        let ckRecord = try await fetchOrCreateCKRecord(for: record)
        try applyMedicalRecord(record, to: ckRecord)
        _ = try await privateDB.save(ckRecord)
    }
    
    /// Applies MedicalRecord data to CKRecord
    func applyMedicalRecord(_ record: MedicalRecord, to ckRecord: CKRecord) throws {
        // Core fields
        ckRecord["uuid"] = record.uuid
        ckRecord["createdAt"] = record.createdAt
        ckRecord["updatedAt"] = record.updatedAt
        ckRecord["isPet"] = record.isPet ? 1 : 0
        
        // Personal fields
        ckRecord["personalGivenName"] = record.personalGivenName
        ckRecord["personalFamilyName"] = record.personalFamilyName
        // ... more fields
        
        // Serialize relationships to JSON
        let bloodData = try JSONEncoder().encode(record.blood)
        ckRecord["bloodEntries"] = String(data: bloodData, encoding: .utf8)
        
        let drugData = try JSONEncoder().encode(record.drugs)
        ckRecord["drugEntries"] = String(data: drugData, encoding: .utf8)
        
        // ... more relationships
    }
}
```

**Key Methods**:
- `syncIfNeeded(record:)` - Main entry point for syncing
- `uploadRecord(_:)` - Uploads to CloudKit
- `applyMedicalRecord(_:to:)` - Serializes SwiftData to CKRecord
- `createShare(for:)` - Creates CloudKit share for a record
- `acceptShare(metadata:)` - Accepts incoming share invitation

**JSON Serialization Pattern**:
```swift
// Encode relationships to JSON
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601

let bloodData = try encoder.encode(record.blood)
ckRecord["bloodEntries"] = String(data: bloodData, encoding: .utf8)
```

### CloudKitMedicalRecordFetcher

**Purpose**: Fetches medical records from CloudKit private database and imports them into SwiftData.

```swift
@MainActor
class CloudKitMedicalRecordFetcher {
    private let containerID: String
    private let container: CKContainer
    private let privateDB: CKDatabase
    private var modelContext: ModelContext?
    
    init(containerIdentifier: String) {
        self.containerID = containerIdentifier
        self.container = CKContainer(identifier: containerIdentifier)
        self.privateDB = container.privateCloudDatabase
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    /// Fetches changes from CloudKit
    func fetchChanges() {
        Task {
            do {
                let changes = try await privateDB.fetchChanges()
                await processChanges(changes)
            } catch {
                ShareDebugStore.shared.appendLog("Fetch failed: \(error)")
            }
        }
    }
    
    /// Imports a CKRecord into SwiftData
    func importToSwiftData(from ckRecord: CKRecord) throws {
        guard let context = modelContext else { return }
        
        // Find existing or create new
        let uuid = ckRecord["uuid"] as? String ?? UUID().uuidString
        let record = findOrCreateRecord(uuid: uuid, in: context)
        
        // Import core fields
        record.uuid = uuid
        record.createdAt = ckRecord["createdAt"] as? Date ?? Date()
        record.updatedAt = ckRecord["updatedAt"] as? Date ?? Date()
        record.isPet = (ckRecord["isPet"] as? Int) == 1
        
        // Import personal fields
        record.personalGivenName = ckRecord["personalGivenName"] as? String ?? ""
        // ... more fields
        
        // Deserialize JSON relationships
        if let bloodString = ckRecord["bloodEntries"] as? String,
           let bloodData = bloodString.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bloodEntries = try decoder.decode([CodableBloodEntry].self, from: bloodData)
            
            // Convert to SwiftData models
            record.blood = bloodEntries.map { codable in
                let entry = BloodEntry()
                entry.date = codable.date
                entry.value = codable.value
                entry.comment = codable.comment
                return entry
            }
        }
        
        try context.save()
    }
}
```

**Key Methods**:
- `fetchChanges()` - Fetches changes from CloudKit
- `importToSwiftData(from:)` - Deserializes CKRecord to SwiftData
- `ensurePrivateDBSubscription()` - Sets up CloudKit push notifications

**Deserialization Pattern**:
```swift
// Decode JSON to Codable struct
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

let entries = try decoder.decode([CodableBloodEntry].self, from: data)

// Convert to SwiftData models
record.blood = entries.map { codable in
    let entry = BloodEntry()
    entry.date = codable.date
    entry.value = codable.value
    return entry
}
```

### CloudKitSharedZoneMedicalRecordFetcher

**Purpose**: Fetches medical records shared with the user from CloudKit shared database.

```swift
@MainActor
class CloudKitSharedZoneMedicalRecordFetcher {
    private let containerID: String
    private let container: CKContainer
    private let sharedDB: CKDatabase
    private let modelContext: ModelContext
    
    init(containerIdentifier: String, modelContext: ModelContext) {
        self.containerID = containerIdentifier
        self.container = CKContainer(identifier: containerIdentifier)
        self.sharedDB = container.sharedCloudDatabase
        self.modelContext = modelContext
    }
    
    /// Fetches all shared records across all shared zones
    func fetchAllSharedAcrossZonesAsync() async throws -> [MedicalRecord] {
        // Get all shared zones
        let zones = try await sharedDB.allRecordZones()
        
        var allRecords: [MedicalRecord] = []
        
        for zone in zones {
            let records = try await fetchRecordsInZone(zone)
            allRecords.append(contentsOf: records)
        }
        
        return allRecords
    }
    
    private func fetchRecordsInZone(_ zone: CKRecordZone) async throws -> [MedicalRecord] {
        let query = CKQuery(recordType: AppConfig.CloudKit.recordType, predicate: NSPredicate(value: true))
        
        let (results, _) = try await sharedDB.records(matching: query, inZoneWith: zone.zoneID)
        
        return results.compactMap { result in
            switch result.1 {
            case .success(let ckRecord):
                return try? importSharedRecord(ckRecord)
            case .failure:
                return nil
            }
        }
    }
}
```

**Key Methods**:
- `fetchAllSharedAcrossZonesAsync()` - Fetches all shared records
- `fetchRecordsInZone(_:)` - Fetches records from specific zone
- `importSharedRecord(_:)` - Imports shared CKRecord to SwiftData

### CloudKitShareAcceptanceService

**Purpose**: Handles accepting CloudKit share invitations.

```swift
@MainActor
class CloudKitShareAcceptanceService {
    static let shared = CloudKitShareAcceptanceService()
    
    func acceptShare(url: URL, modelContext: ModelContext) async throws {
        let container = CKContainer(identifier: AppConfig.CloudKit.containerID)
        
        // Fetch share metadata
        let metadata = try await container.shareMetadata(for: url)
        
        // Accept the share
        let acceptedShare = try await container.accept(metadata)
        
        // Fetch the shared record
        let sharedDB = container.sharedCloudDatabase
        let recordID = acceptedShare.rootRecordID
        let ckRecord = try await sharedDB.record(for: recordID)
        
        // Import to SwiftData
        let fetcher = CloudKitMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID)
        fetcher.setModelContext(modelContext)
        try fetcher.importToSwiftData(from: ckRecord)
        
        // Mark as pending for refresh
        UserDefaults.standard.set(true, forKey: "pendingSharedImport")
    }
}
```

**Key Methods**:
- `acceptShare(url:modelContext:)` - Accepts share and imports record

### CloudKitShareParticipantsService

**Purpose**: Manages participants in CloudKit shares.

```swift
class CloudKitShareParticipantsService {
    func fetchParticipants(for share: CKShare) async throws -> [CKShare.Participant] {
        return share.participants
    }
    
    func removeParticipant(_ participant: CKShare.Participant, from share: CKShare) async throws {
        let container = CKContainer(identifier: AppConfig.CloudKit.containerID)
        let privateDB = container.privateCloudDatabase
        
        share.participants.removeAll { $0 === participant }
        _ = try await privateDB.save(share)
    }
}
```

## Export Services

These services handle exporting medical records to various formats.

### ExportService

**Purpose**: Coordinates export operations and provides export functionality.

```swift
@MainActor
class ExportService {
    static let shared = ExportService()
    
    func exportRecordToPDF(_ record: MedicalRecord) async throws -> URL {
        // Generate HTML
        let html = try HTMLTemplateRenderer.shared.render(record: record)
        
        // Render PDF
        #if canImport(UIKit)
        let pdfRenderer = iOSPDFRenderer()
        #else
        let pdfRenderer = macOSPDFRenderer()
        #endif
        
        let pdfData = try await pdfRenderer.render(html: html)
        
        // Save to file
        let fileURL = temporaryPDFURL(for: record)
        try pdfData.write(to: fileURL)
        
        return fileURL
    }
    
    func exportRecordToJSON(_ record: MedicalRecord) throws -> Data {
        let mapper = MedicalRecordMapper()
        let exportable = mapper.toExportable(record)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        return try encoder.encode(exportable)
    }
    
    private func temporaryPDFURL(for record: MedicalRecord) -> URL {
        let fileName = "\(record.displayName) - Medical Record.pdf"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
    }
}
```

**Key Methods**:
- `exportRecordToPDF(_:)` - Exports record as PDF
- `exportRecordToJSON(_:)` - Exports record as JSON
- `shareRecord(_:)` - Shares record via system share sheet

### HTMLTemplateRenderer

**Purpose**: Generates HTML from medical records for PDF export.

```swift
class HTMLTemplateRenderer {
    static let shared = HTMLTemplateRenderer()
    
    func render(record: MedicalRecord) throws -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>\(record.displayName) - Medical Record</title>
            <style>
                body { font-family: -apple-system, sans-serif; margin: 20px; }
                h1 { color: #007AFF; }
                h2 { color: #333; border-bottom: 1px solid #ccc; }
                .section { margin: 20px 0; }
                .entry { margin: 10px 0; padding: 10px; background: #f9f9f9; }
                .label { font-weight: bold; }
            </style>
        </head>
        <body>
        """
        
        // Add personal information
        html += renderPersonalSection(record)
        
        // Add entries
        html += renderEntriesSection(record)
        
        // Add emergency contacts
        html += renderEmergencySection(record)
        
        html += """
        </body>
        </html>
        """
        
        return html
    }
    
    private func renderPersonalSection(_ record: MedicalRecord) -> String {
        // Generate HTML for personal information
        return "<div class='section'>...</div>"
    }
    
    private func renderEntriesSection(_ record: MedicalRecord) -> String {
        // Generate HTML for medical entries
        return "<div class='section'>...</div>"
    }
}
```

### PDFRenderer Protocol

**Purpose**: Platform-agnostic PDF rendering interface.

```swift
protocol PDFRenderer {
    func render(html: String) async throws -> Data
}
```

### iOSPDFRenderer

**Purpose**: iOS-specific PDF rendering implementation.

```swift
#if canImport(UIKit)
import UIKit
import WebKit

class iOSPDFRenderer: PDFRenderer {
    func render(html: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let webView = WKWebView()
            
            webView.loadHTMLString(html, baseURL: nil)
            
            // Wait for load
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let renderer = UIPrintPageRenderer()
                let printFormatter = webView.viewPrintFormatter()
                renderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)
                
                let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
                renderer.setValue(pageRect, forKey: "paperRect")
                renderer.setValue(pageRect, forKey: "printableRect")
                
                let pdfData = NSMutableData()
                UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
                
                for page in 0..<renderer.numberOfPages {
                    UIGraphicsBeginPDFPage()
                    renderer.drawPage(at: page, in: pageRect)
                }
                
                UIGraphicsEndPDFContext()
                
                continuation.resume(returning: pdfData as Data)
            }
        }
    }
}
#endif
```

### macOSPDFRenderer

**Purpose**: macOS-specific PDF rendering implementation.

```swift
#if canImport(AppKit)
import AppKit
import WebKit

class macOSPDFRenderer: PDFRenderer {
    func render(html: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let webView = WKWebView()
            
            webView.loadHTMLString(html, baseURL: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let printInfo = NSPrintInfo.shared
                printInfo.paperSize = NSSize(width: 595, height: 842) // A4
                
                let printOp = webView.printOperation(with: printInfo)
                
                guard let pdfData = printOp.pdfPanel.data else {
                    continuation.resume(throwing: NSError(domain: "PDFError", code: 1))
                    return
                }
                
                continuation.resume(returning: pdfData)
            }
        }
    }
}
#endif
```

### MedicalRecordMapper

**Purpose**: Maps between SwiftData models and exportable/importable formats.

```swift
class MedicalRecordMapper {
    func toExportable(_ record: MedicalRecord) -> ExportableMedicalRecord {
        return ExportableMedicalRecord(
            uuid: record.uuid,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            isPet: record.isPet,
            personalGivenName: record.personalGivenName,
            personalFamilyName: record.personalFamilyName,
            // ... all fields
            blood: record.blood.map { toExportable($0) },
            drugs: record.drugs.map { toExportable($0) }
            // ... all relationships
        )
    }
    
    func fromExportable(_ exportable: ExportableMedicalRecord) -> MedicalRecord {
        let record = MedicalRecord()
        record.uuid = exportable.uuid
        record.createdAt = exportable.createdAt
        // ... map all fields
        return record
    }
}
```

## Utility Services

### ContactPicker

**Purpose**: Platform-specific contact selection.

```swift
#if canImport(UIKit)
import Contacts
import ContactsUI

class ContactPicker: NSObject, CNContactPickerDelegate {
    var onContactSelected: ((CNContact) -> Void)?
    
    func presentPicker(from viewController: UIViewController) {
        let picker = CNContactPickerViewController()
        picker.delegate = self
        viewController.present(picker, animated: true)
    }
    
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        onContactSelected?(contact)
    }
}
#endif
```

### AppFileProtection

**Purpose**: Manages file system security and protection levels.

```swift
class AppFileProtection {
    static func setProtectionLevel(for url: URL, level: FileProtectionType = .complete) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: level],
            ofItemAtPath: url.path
        )
    }
}
```

### ShareDebugStore

**Purpose**: Collects debug logs for CloudKit sharing operations.

```swift
@MainActor
class ShareDebugStore: ObservableObject {
    static let shared = ShareDebugStore()
    
    @Published private(set) var logs: [String] = []
    
    func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
        print("[ShareDebug] \(message)")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
}
```

## Service Patterns

### 1. **Singleton Pattern**

Most services use the singleton pattern for global access:

```swift
class CloudSyncService {
    static let shared = CloudSyncService()
    
    private init() {
        // Private initializer
    }
}
```

### 2. **Dependency Injection**

Some services accept dependencies in the initializer:

```swift
class CloudKitSharedZoneMedicalRecordFetcher {
    init(containerIdentifier: String, modelContext: ModelContext) {
        // Inject dependencies
    }
}
```

### 3. **Async/Await**

All asynchronous operations use modern Swift concurrency:

```swift
func syncIfNeeded(record: MedicalRecord) async throws {
    // Async operation
}
```

### 4. **Error Handling**

Services use throwing functions and handle errors gracefully:

```swift
func exportRecord(_ record: MedicalRecord) throws -> Data {
    do {
        return try generatePDF(record)
    } catch {
        ShareDebugStore.shared.appendLog("Export failed: \(error)")
        throw error
    }
}
```

## Best Practices

### 1. **Use @MainActor for UI-Related Services**

Services that interact with SwiftData contexts or UI should be marked `@MainActor`:

```swift
@MainActor
class CloudSyncService {
    // ...
}
```

### 2. **Separate Platform-Specific Code**

Use conditional compilation for platform-specific implementations:

```swift
#if canImport(UIKit)
// iOS implementation
#else
// macOS implementation
#endif
```

### 3. **Log Important Operations**

Use `ShareDebugStore` or console logging for debugging:

```swift
ShareDebugStore.shared.appendLog("Sync completed for record \(record.uuid)")
```

### 4. **Handle Nil Context Gracefully**

Always check for nil contexts before operations:

```swift
guard let context = modelContext else {
    ShareDebugStore.shared.appendLog("No model context available")
    return
}
```

## Next Steps

- Explore [CloudKit Integration](CloudKit-Integration) in detail
- Learn about [Testing Guide](Testing-Guide)
- Review [Contributing Guide](Contributing-Guide)
