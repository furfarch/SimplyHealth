# CloudKit Integration

Purus Health implements manual CloudKit synchronization to provide per-record opt-in cloud sync and sharing capabilities. This approach gives users full control over which records are synced to iCloud.

## Why Manual CloudKit Integration?

SwiftData offers built-in CloudKit integration, but it operates at the store level, meaning all records are either synced or none are. Purus Health requires per-record control, so it implements manual CloudKit synchronization:

- **Local-First Storage**: SwiftData stores all data locally without CloudKit
- **Per-Record Opt-In**: Users choose which records to sync via `isCloudEnabled` flag
- **Manual Synchronization**: `CloudSyncService` handles syncing opted-in records
- **Sharing Support**: CloudKit shares enable record sharing with other users

## CloudKit Configuration

### Container Setup

**Container ID**: `iCloud.com.purus.health`

```swift
enum AppConfig {
    enum CloudKit {
        static let containerID = "iCloud.com.purus.health"
        static let shareZoneName = "PurusHealthShareZone"
        static let recordType = "MedicalRecord"
    }
}
```

### Databases

Purus Health uses two CloudKit databases:

1. **Private Database** - User's personal records with cloud sync enabled
2. **Shared Database** - Records shared with the user by others

The default zone is NOT used because shares require a custom zone.

### Custom Zone

**Zone Name**: `PurusHealthShareZone`

CloudKit shares cannot exist in the default zone. All shareable records are stored in a custom zone:

```swift
private var shareZoneID: CKRecordZone.ID {
    CKRecordZone.ID(zoneName: "PurusHealthShareZone", ownerName: CKCurrentUserDefaultName)
}
```

## Data Model Mapping

### SwiftData to CloudKit

Since CloudKit doesn't support SwiftData relationships directly, relationships are serialized to JSON strings:

| SwiftData Field | CloudKit Field | Type | Notes |
|----------------|----------------|------|-------|
| `uuid` | `uuid` | STRING | Stable identifier |
| `createdAt` | `createdAt` | DATE_TIME | Creation timestamp |
| `updatedAt` | `updatedAt` | DATE_TIME | Last update timestamp |
| `isPet` | `isPet` | INT64 | 0 = human, 1 = pet |
| `personalGivenName` | `personalGivenName` | STRING | Given name |
| `personalFamilyName` | `personalFamilyName` | STRING | Family name |
| `blood` (relationship) | `bloodEntries` | STRING | JSON array |
| `drugs` (relationship) | `drugEntries` | STRING | JSON array |
| `vaccinations` (relationship) | `vaccinationEntries` | STRING | JSON array |
| ... | ... | ... | All relationships as JSON |

### JSON Serialization Example

```swift
// Serialization (CloudSyncService)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601

let bloodData = try encoder.encode(record.blood)
ckRecord["bloodEntries"] = String(data: bloodData, encoding: .utf8)
```

```json
// Example JSON in CloudKit STRING field
[
  {
    "date": "2024-01-15T10:30:00Z",
    "value": "120/80 mmHg",
    "comment": "Normal blood pressure"
  },
  {
    "date": "2024-02-10T14:15:00Z",
    "value": "118/78 mmHg",
    "comment": "Excellent reading"
  }
]
```

### Deserialization Example

```swift
// Deserialization (CloudKitMedicalRecordFetcher)
if let bloodString = ckRecord["bloodEntries"] as? String,
   let bloodData = bloodString.data(using: .utf8) {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    
    let codableEntries = try decoder.decode([CodableBloodEntry].self, from: bloodData)
    
    // Convert to SwiftData models
    record.blood = codableEntries.map { codable in
        let entry = BloodEntry()
        entry.date = codable.date
        entry.value = codable.value
        entry.comment = codable.comment
        return entry
    }
}
```

## Synchronization Flow

### Enabling Cloud Sync

```
User Action → Toggle isCloudEnabled = true → syncIfNeeded() → Upload to CloudKit
```

**Code**:
```swift
// In view
Toggle("Enable Cloud Sync", isOn: $record.isCloudEnabled)
    .onChange(of: record.isCloudEnabled) { _, newValue in
        if newValue {
            Task {
                try await CloudSyncService.shared.syncIfNeeded(record: record)
            }
        }
    }
```

### Upload Process

1. **Check if sync needed**: Only sync if `isCloudEnabled` is true
2. **Ensure zone exists**: Create custom zone if it doesn't exist
3. **Fetch or create CKRecord**: Get existing or create new
4. **Apply record data**: Serialize SwiftData → CKRecord
5. **Save to CloudKit**: Upload to private database

```swift
func syncIfNeeded(record: MedicalRecord) async throws {
    guard record.isCloudEnabled else { return }
    
    try await ensureShareZoneExists()
    
    let ckRecord = try await fetchOrCreateCKRecord(for: record)
    try applyMedicalRecord(record, to: ckRecord)
    
    _ = try await database.save(ckRecord)
    
    record.cloudRecordName = ckRecord.recordID.recordName
}
```

### Download Process

1. **Fetch changes**: Query CloudKit for changes
2. **Process records**: For each changed record
3. **Import to SwiftData**: Deserialize CKRecord → SwiftData
4. **Save context**: Persist changes locally

```swift
func fetchChanges() {
    Task {
        let changes = try await privateDB.fetchChanges()
        
        for ckRecord in changes.modified {
            try importToSwiftData(from: ckRecord)
        }
        
        for recordID in changes.deleted {
            deleteLocal(recordID: recordID)
        }
        
        try modelContext?.save()
    }
}
```

### Automatic Sync Triggers

The app syncs automatically in these scenarios:

1. **App Launch**: Fetches changes when app starts
2. **Scene Active**: Syncs when app comes to foreground
3. **Record Update**: Syncs when a cloud-enabled record is modified
4. **Push Notifications**: Responds to CloudKit change notifications

```swift
// In PurusHealthApp.swift
.task {
    if await shouldFetchFromCloud() {
        cloudFetcher.fetchChanges()
    }
}
.onChange(of: scenePhase) { oldPhase, newPhase in
    if newPhase == .active {
        if await shouldFetchFromCloud() {
            cloudFetcher.fetchChanges()
            await syncCloudEnabledRecords()
        }
    }
}
```

## Sharing Implementation

### Creating a Share

```swift
func createShare(for record: MedicalRecord) async throws -> (CKShare, CKRecord) {
    // Ensure zone and root record exist
    try await ensureShareZoneExists()
    let rootRecord = try await fetchOrCreateCKRecord(for: record)
    
    // Create CKShare
    let share = CKShare(rootRecord: rootRecord)
    share[CKShare.SystemFieldKey.title] = record.displayName
    share.publicPermission = .none  // Private share only
    
    // Save share and root record together
    let (records, _) = try await database.modifyRecords(saving: [rootRecord, share], deleting: [])
    
    guard let savedShare = records.first(where: { $0 is CKShare }) as? CKShare,
          let savedRoot = records.first(where: { $0.recordType == medicalRecordType }) else {
        throw CloudSyncError.shareFailed
    }
    
    // Update local record
    record.isSharingEnabled = true
    record.cloudShareRecordName = savedShare.recordID.recordName
    
    return (savedShare, savedRoot)
}
```

### Presenting Share UI

```swift
#if canImport(UIKit)
// iOS
struct CloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        return controller
    }
}
#endif
```

```swift
// In view
.sheet(isPresented: $showShareSheet) {
    if let share = currentShare {
        CloudShareSheet(share: share, container: container)
    }
}
```

### Accepting a Share

1. **Handle URL**: App receives CloudKit share URL
2. **Fetch metadata**: Get share information
3. **Accept share**: Accept the share invitation
4. **Import record**: Fetch and import the shared record

```swift
// In ContentView
.onOpenURL { url in
    guard url.scheme == "https",
          url.host == "www.icloud.com",
          url.pathComponents.contains("share") else { return }
    
    Task {
        try await CloudKitShareAcceptanceService.shared.acceptShare(
            url: url,
            modelContext: modelContext
        )
    }
}
```

```swift
// CloudKitShareAcceptanceService
func acceptShare(url: URL, modelContext: ModelContext) async throws {
    let container = CKContainer(identifier: AppConfig.CloudKit.containerID)
    
    // Fetch metadata
    let metadata = try await container.shareMetadata(for: url)
    
    // Accept share
    let acceptedShare = try await container.accept(metadata)
    
    // Fetch shared record
    let sharedDB = container.sharedCloudDatabase
    let ckRecord = try await sharedDB.record(for: acceptedShare.rootRecordID)
    
    // Import to local SwiftData
    let fetcher = CloudKitMedicalRecordFetcher(containerIdentifier: containerID)
    fetcher.setModelContext(modelContext)
    try fetcher.importToSwiftData(from: ckRecord)
    
    // Mark record as shared
    if let record = findRecord(uuid: ckRecord["uuid"] as? String) {
        record.isSharingEnabled = true
        record.recordLocation = .shared
    }
}
```

### Fetching Shared Records

```swift
func fetchAllSharedAcrossZonesAsync() async throws -> [MedicalRecord] {
    let sharedDB = container.sharedCloudDatabase
    
    // Get all shared zones
    let zones = try await sharedDB.allRecordZones()
    
    var allRecords: [MedicalRecord] = []
    
    for zone in zones {
        let query = CKQuery(recordType: "MedicalRecord", predicate: NSPredicate(value: true))
        let (results, _) = try await sharedDB.records(matching: query, inZoneWith: zone.zoneID)
        
        for result in results {
            if case .success(let ckRecord) = result.1 {
                let record = try importSharedRecord(ckRecord)
                allRecords.append(record)
            }
        }
    }
    
    return allRecords
}
```

## CloudKit Schema Management

### Schema Definition

CloudKit schemas are defined in `cloudkit-development.cdkb` and must be manually uploaded to CloudKit Dashboard.

**Important Notes**:
- Schemas are NOT auto-created from code
- Development and Production schemas are separate
- New fields must be added to Development first, then deployed to Production
- Attempting to create new types/fields in Production from code will fail

### Adding New Fields

To add a new field to CloudKit:

1. **Add to SwiftData Model**:
```swift
@Model
final class MedicalRecord {
    var newField: String = ""
}
```

2. **Update CloudKit Schema** (`cloudkit-development.cdkb`):
```
FIELD newField STRING;
```

3. **Upload to CloudKit Dashboard**:
   - Open [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
   - Select container: `iCloud.com.purus.health`
   - Upload schema from `cloudkit-development.cdkb`

4. **Add Serialization** (`CloudSyncService.applyMedicalRecord`):
```swift
ckRecord["newField"] = record.newField
```

5. **Add Deserialization** (`CloudKitMedicalRecordFetcher.importToSwiftData`):
```swift
record.newField = ckRecord["newField"] as? String ?? ""
```

6. **Deploy to Production**:
   - In CloudKit Dashboard, deploy Development schema to Production

## Push Notifications

### Subscription Setup

The app subscribes to CloudKit changes for real-time sync:

```swift
func ensurePrivateDBSubscription() async {
    let subscriptionID = "medical-records-changes"
    
    let subscription = CKQuerySubscription(
        recordType: "MedicalRecord",
        predicate: NSPredicate(value: true),
        subscriptionID: subscriptionID,
        options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
    )
    
    let notificationInfo = CKSubscription.NotificationInfo()
    notificationInfo.shouldSendContentAvailable = true
    subscription.notificationInfo = notificationInfo
    
    do {
        _ = try await database.save(subscription)
    } catch {
        // Subscription already exists or other error
        ShareDebugStore.shared.appendLog("Subscription setup: \(error)")
    }
}
```

### Handling Push Notifications

```swift
// In AppDelegate
func application(_ application: UIApplication,
                didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    
    if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
        // Trigger fetch
        CloudKitMedicalRecordFetcher.shared.fetchChanges()
        completionHandler(.newData)
    } else {
        completionHandler(.noData)
    }
}
```

## Record Location Status

Records have a `recordLocation` field indicating where they're stored:

```swift
enum RecordLocation: String, Codable {
    case local     // Only stored locally
    case iCloud    // Synced to user's private CloudKit
    case shared    // Shared by another user
}
```

**Usage**:
```swift
// Display location badge in UI
Text(record.recordLocation.description)
    .badge(record.recordLocation.badgeColor)
```

## Error Handling

### CloudKit Errors

Common CloudKit errors and handling:

```swift
do {
    try await syncRecord(record)
} catch let error as CKError {
    switch error.code {
    case .notAuthenticated:
        // User not signed into iCloud
        showAlert("Please sign in to iCloud")
        
    case .networkFailure, .networkUnavailable:
        // Network issue, retry later
        scheduleRetry()
        
    case .quotaExceeded:
        // User's iCloud storage is full
        showAlert("iCloud storage full")
        
    case .zoneNotFound:
        // Zone was deleted, recreate
        try await ensureShareZoneExists()
        
    default:
        ShareDebugStore.shared.appendLog("CloudKit error: \(error)")
    }
}
```

### Graceful Degradation

The app continues to work even if CloudKit fails:

```swift
func syncIfNeeded(record: MedicalRecord) async throws {
    guard record.isCloudEnabled else { return }
    
    do {
        try await uploadRecord(record)
    } catch {
        // Log error but don't crash
        ShareDebugStore.shared.appendLog("Sync failed: \(error)")
        // Record remains local, will retry later
    }
}
```

## Testing CloudKit Features

### Development Environment

Use CloudKit Development environment for testing:

```swift
let container = CKContainer(identifier: AppConfig.CloudKit.containerID)
// Automatically uses Development environment in debug builds
```

### CloudKit Dashboard

Access the CloudKit Dashboard for debugging:
- [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
- View/edit records
- Check schema
- Monitor usage
- Review error logs

### Debug Logs

Use `ShareDebugStore` to collect logs:

```swift
ShareDebugStore.shared.appendLog("Sync started for \(record.uuid)")

// View logs in DiagnosticsView
struct DiagnosticsView: View {
    @ObservedObject var debugStore = ShareDebugStore.shared
    
    var body: some View {
        List(debugStore.logs, id: \.self) { log in
            Text(log).font(.system(.caption, design: .monospaced))
        }
    }
}
```

## Best Practices

### 1. **Always Check isCloudEnabled**
```swift
guard record.isCloudEnabled else { return }
```

### 2. **Use Custom Zones for Shares**
Never use the default zone for shareable records.

### 3. **Handle JSON Serialization Errors**
```swift
do {
    let data = try JSONEncoder().encode(entries)
    ckRecord["entries"] = String(data: data, encoding: .utf8)
} catch {
    ShareDebugStore.shared.appendLog("Serialization failed: \(error)")
    // Fallback: save empty array
    ckRecord["entries"] = "[]"
}
```

### 4. **Implement Retry Logic**
Network operations should retry on failure:

```swift
var retries = 0
let maxRetries = 3

while retries < maxRetries {
    do {
        try await uploadRecord(record)
        break
    } catch {
        retries += 1
        if retries < maxRetries {
            try await Task.sleep(nanoseconds: UInt64(retries) * 1_000_000_000)
        } else {
            throw error
        }
    }
}
```

### 5. **Batch Operations**
Use batch operations when possible:

```swift
let records = [record1, record2, record3]
let ckRecords = records.map { convertToCKRecord($0) }
let (saved, _) = try await database.modifyRecords(saving: ckRecords, deleting: [])
```

## Security Considerations

### 1. **Private by Default**
All records start in private database with no sharing.

### 2. **Explicit Sharing**
Users must explicitly enable sharing per record.

### 3. **Share Permissions**
```swift
share.publicPermission = .none  // No public access
// Participants are added individually
```

### 4. **Data Encryption**
CloudKit encrypts all data in transit and at rest.

### 5. **User Authentication**
CloudKit uses iCloud authentication, no passwords stored in app.

## Next Steps

- Learn about [Testing Guide](Testing-Guide)
- Review [Contributing Guide](Contributing-Guide)
- Explore [Development Setup](Development-Setup)
