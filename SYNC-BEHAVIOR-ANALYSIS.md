# CloudKit Sync Behavior Analysis

## Current Code Behavior - Scenario Analysis

### Scenario 1: Set Local on Device A
**What happens:**
- User disables cloud sync on Device A for a record
- `CloudSyncService.disableCloud()` is called (line 240)
- Sets `isCloudEnabled = false`, `isSharingEnabled = false`
- **DELETES the record from CloudKit** (calls `revokeSharingAndDeleteFromCloud()`)
- Clears `cloudRecordName`, `cloudShareRecordName`

**Impact on other devices B and C:**
- **IMMEDIATE**: CloudKit record is deleted
- **NEXT SYNC**: Devices B and C fetch changes → see deletion event
- `CloudKitMedicalRecordFetcher.deleteFromSwiftData()` is called (line 156)
- **PROBLEM**: B and C delete their local copies unconditionally
- **RESULT**: Record disappears from all devices

**Current Bug**: Device A wanted LOCAL-ONLY, but action caused deletion everywhere.

---

### Scenario 2: Local on A, Deleted/Changed on Other Devices

#### Case 2a: Record deleted on Device B
**Current behavior:**
- Device B deletes record → CloudKit record deleted
- Device A syncs → `deleteFromSwiftData()` called
- **PROBLEM**: Device A's local-only record is deleted
- **RESULT**: Data loss on Device A

#### Case 2b: Record changed on Device B
**Current behavior:**
- Device B edits record → CloudKit record updated
- Device A syncs → `importToSwiftData()` called (line 277)
- Line 492: `record.isCloudEnabled = cloudEnabled` (reads UserDefaults)
- If A has global cloud disabled: record stays local but gets updated
- If A has global cloud enabled: record becomes cloud-enabled
- **PROBLEM**: Per-record local setting is lost
- **RESULT**: Local-only intent on A is not preserved

---

### Scenario 3: Local Re-enabled on A to Cloud

**Current behavior:**
- User enables cloud on Device A for the record
- Sets `isCloudEnabled = true`
- `CloudSyncService.syncIfNeeded()` uploads to CloudKit
- Creates new CloudKit record with current data

**Impact on devices B and C:**
- If B and C still have the record (never deleted): conflict!
- Line 287-289: Timestamp comparison `existing.updatedAt > cloudUpdatedAt`
- If A's version is newer: B and C get updated
- If B/C version is newer: A's upload is ignored locally on B/C
- **PROBLEM**: No clear winner, depends on who syncs first

---

### Scenario 4: A and C Set to Local

**Current behavior:**
- Device A sets local → deletes from CloudKit
- Device C sets local → deletes from CloudKit (already deleted)
- Device B (still cloud-enabled) syncs:
  - Sees CloudKit record deleted
  - Deletes local copy
- **RESULT**: All three devices have local copies, but B's was deleted

**Inconsistency**: B lost data it didn't intend to make local-only.

---

## Core Problems Identified

1. **"Set Local" deletes from CloudKit** → affects all devices
2. **No protection for local-only records** during sync
3. **No coordination** between devices about local-only intent
4. **Deletions not tracked** → resurrections occur
5. **Per-record local setting not preserved** during import

---

## Alternative Approaches

### Option A: Persistent Minimal Tombstones (RECOMMENDED ✅)

**Concept**: Keep permanent "skeleton" records in CloudKit with only deletion metadata, no actual data

**The Elegant Solution:**
1. When deleting a record OR setting to local-only:
   - Don't delete from CloudKit entirely
   - Clear ALL data fields (personal info, medical data, relationships)
   - Keep only: `uuid`, `isDeleted=true`, `deletedAt=Date()`, `updatedAt`
   - **Result**: Minimal tombstone record (~100 bytes) persists indefinitely

2. During sync on any device:
   - If `isDeleted=true` and record is cloud-enabled → delete locally
   - If `isDeleted=true` and record is local-only → ignore (keep local copy)

3. When device syncs weeks/months later:
   - Still sees tombstone → properly deletes record
   - No time limit, no race conditions

**Implementation:**
```swift
// When deleting or setting to local
func createTombstone(for record: MedicalRecord) async throws {
    let ckID = zonedRecordID(for: record)
    let ckRecord = CKRecord(recordType: medicalRecordType, recordID: ckID)
    
    // ONLY write deletion metadata (no personal/medical data)
    ckRecord["uuid"] = record.uuid as NSString
    ckRecord["isDeleted"] = 1 as NSNumber
    ckRecord["deletedAt"] = Date() as NSDate
    ckRecord["updatedAt"] = Date() as NSDate
    
    // Save the tombstone
    try await database.save(ckRecord)
    
    ShareDebugStore.shared.appendLog("Created tombstone for uuid=\(record.uuid)")
}

// During import
func importToSwiftData(context: ModelContext) {
    for ckRecord in records {
        // Check for tombstone
        if let isDeleted = ckRecord["isDeleted"] as? NSNumber, isDeleted.boolValue {
            // This is a deletion tombstone
            if let uuid = ckRecord["uuid"] as? String {
                let fetchDescriptor = FetchDescriptor<MedicalRecord>(
                    predicate: #Predicate { $0.uuid == uuid }
                )
                if let existing = (try? context.fetch(fetchDescriptor))?.first {
                    // Only delete if cloud-enabled (protect local records)
                    if existing.isCloudEnabled {
                        context.delete(existing)
                        ShareDebugStore.shared.appendLog("Deleted from tombstone uuid=\(uuid)")
                    } else {
                        ShareDebugStore.shared.appendLog("Protected local record from tombstone uuid=\(uuid)")
                    }
                }
            }
            continue // Don't process further
        }
        
        // Normal import logic...
    }
}
```

**Advantages:**
- ✅ Works for devices that sync weeks/months later
- ✅ Minimal data footprint (no personal/medical data in tombstone)
- ✅ Solves "set local" coordination (tombstone = "deleted on all synced devices")
- ✅ No time-based cleanup complexity
- ✅ No race conditions
- ✅ Simple to implement and maintain
- ✅ Works with existing incremental sync

**Disadvantages:**
- ❌ Tombstones persist indefinitely (but minimal size)
- ❌ Need occasional cleanup for very old tombstones (optional)

**Storage impact:**
- Full record: ~5-50 KB (with all medical data, relationships)
- Tombstone: ~100 bytes (uuid + 3 metadata fields)
- **99% storage reduction** for deleted records

---

### Option B: Time-Limited Tombstones (PREVIOUS APPROACH)

**Concept**: Delete tombstones after 1-24 hours

**Disadvantages:**
- ❌ Devices syncing after time limit miss deletions
- ❌ Requires background cleanup job
- ❌ Doesn't solve occasional sync problem
- **Not recommended** based on user feedback

---

### Option C: LastSeenOnCloud Tracking

**Concept**: Track which CloudKit records we've seen locally

**Disadvantages:**
- ❌ Requires full fetch to detect deletions (not incremental)
- ❌ Doesn't work for new device installs
- ❌ Complex state management
- **Not recommended**

---

## Specific Answers to User Questions

### 1) Set local on A - what happens to B and C?
**Proposed with Persistent Tombstones:**
- A: User taps "Set Local" → Creates tombstone in CloudKit (uuid + isDeleted=true + deletedAt)
- B & C: Sync → See tombstone → Delete their local copies
- **Result**: Record only exists on A (local-only), removed from all synced devices
- **Behavior**: Exactly like "Stop Sharing" - removes from all other devices

### 2) Local on A, deleted/changed on other devices - what happens?
- **Delete on B**: Creates tombstone in CloudKit. A syncs, sees tombstone, but `isCloudEnabled=false` → **PROTECTED**. C deletes.
- **Change on B**: A syncs, sees update, but `isCloudEnabled=false` → Ignores update (local setting preserved).

### 3) Local re-enabled on A to cloud - what happens on B and C?
**Proposed**: 
- A: User enables cloud → Uploads full record with latest timestamp
- CloudKit: Overwrites tombstone with full record data
- B & C: Sync → See full record → Create/update their local copies
- **Result**: All devices synchronized with A's version

### 4) What when A and C set to local?
**Proposed**:
- A: Sets local → Creates tombstone
- B: Syncs → Deletes local copy
- C: Sets local → Sees existing tombstone (no-op or updates timestamp)
- **Result**: Only A and C have local copies, B's copy removed

### 5) Device C syncs occasionally (weeks later)
**Question**: How to ensure C gets deletions if it syncs 3 weeks later?

**Answer with Persistent Tombstones:**
- ✅ Tombstone persists indefinitely in CloudKit
- ✅ Device C syncs weeks later → Still sees tombstone → Deletes record
- ✅ No time-based expiration → No missed deletions
- ✅ Minimal storage (~100 bytes per deleted record)

### 6) Setting local should behave like deletion?
**Question**: Should "Set Local" remove from all synced devices like "Stop Sharing"?

**Answer:** YES - This is the proposed behavior!
- "Set Local" = Create tombstone = Remove from all other synced devices
- Only difference from deletion: Device A keeps local copy
- Cleaner semantics: "Local" means "only on this device"
- Tombstone with no content ensures even late-syncing devices see the "removal"

---

## Implementation Plan

### Phase 1: Core Tombstone Infrastructure

#### Step 1.1: Add `isDeleted` to CloudKit Schema
```swift
// In cloudkit-development.cdkb
// Add field: isDeleted (INT64)
```

#### Step 1.2: Create Tombstone Writing Function
```swift
// In CloudSyncService.swift
func createTombstone(for record: MedicalRecord) async throws {
    try await ensureShareZoneExists()
    let ckID = zonedRecordID(for: record)
    let ckRecord = CKRecord(recordType: medicalRecordType, recordID: ckID)
    
    // Minimal data - only deletion metadata
    ckRecord["uuid"] = record.uuid as NSString
    ckRecord["isDeleted"] = 1 as NSNumber
    ckRecord["deletedAt"] = Date() as NSDate
    ckRecord["updatedAt"] = Date() as NSDate
    ckRecord["schemaVersion"] = 1 as NSNumber
    
    _ = try await database.save(ckRecord)
    ShareDebugStore.shared.appendLog("[CloudSyncService] Created tombstone uuid=\(record.uuid)")
}
```

#### Step 1.3: Update Import to Handle Tombstones
```swift
// In CloudKitMedicalRecordFetcher.importToSwiftData()
func importToSwiftData(context: ModelContext) {
    for ckRecord in records {
        guard let uuid = ckRecord["uuid"] as? String else { continue }
        
        // NEW: Check for deletion tombstone
        if let isDeletedNum = ckRecord["isDeleted"] as? NSNumber, isDeletedNum.boolValue {
            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: found tombstone uuid=\(uuid)")
            
            let fetchDescriptor = FetchDescriptor<MedicalRecord>(
                predicate: #Predicate { $0.uuid == uuid }
            )
            
            if let existing = (try? context.fetch(fetchDescriptor))?.first {
                // Protect local-only records from tombstone deletions
                if !existing.isCloudEnabled {
                    ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: protected local-only record from tombstone uuid=\(uuid)")
                    continue
                }
                
                // Cloud-enabled record - respect the deletion
                ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: deleting from tombstone uuid=\(uuid)")
                context.delete(existing)
                SharedImportSuppression.clear(uuid)
            }
            
            continue // Don't import tombstone as data
        }
        
        // Existing import logic continues...
    }
    
    // Save changes
    do {
        try context.save()
        context.processPendingChanges()
        Task { @MainActor in
            NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
        }
    } catch {
        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: failed saving: \(error)")
    }
}
```

### Phase 2: Update Deletion Logic

#### Step 2.1: Modify `deleteSyncRecord` to Create Tombstone
```swift
// In CloudSyncService.deleteSyncRecord()
func deleteSyncRecord(forLocalRecord record: MedicalRecord) async throws {
    // Create tombstone instead of deleting entirely
    try await createTombstone(for: record)
    
    // Best-effort: delete share if exists
    if let shareRecordName = record.cloudShareRecordName {
        let shareID = CKRecord.ID(recordName: shareRecordName, zoneID: shareZoneID)
        do {
            _ = try await database.deleteRecord(withID: shareID)
            ShareDebugStore.shared.appendLog("[CloudSyncService] Deleted share uuid=\(record.uuid)")
        } catch {
            ShareDebugStore.shared.appendLog("[CloudSyncService] Failed deleting share: \(error)")
        }
        record.cloudShareRecordName = nil
    }
    
    // Clear local CloudKit identifiers
    record.cloudRecordName = nil
    record.isSharingEnabled = false
    record.isCloudEnabled = false
    record.updatedAt = Date()
}
```

#### Step 2.2: Protect Local Records in deleteFromSwiftData
```swift
// In CloudKitMedicalRecordFetcher.deleteFromSwiftData()
private func deleteFromSwiftData(recordIDs: [CKRecord.ID], context: ModelContext) {
    for recordID in recordIDs {
        let recordName = recordID.recordName
        let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate {
            $0.cloudRecordName == recordName || $0.uuid == recordName
        })
        
        if let existing = (try? context.fetch(fetchDescriptor))?.first {
            // NEW: Protect local-only records from cloud deletions
            if !existing.isCloudEnabled {
                ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: protecting local-only record uuid=\(existing.uuid)")
                continue
            }
            
            context.delete(existing)
            SharedImportSuppression.clear(existing.uuid)
        }
    }
    
    // Existing save logic...
}
```

### Phase 3: Update "Set Local" Behavior

#### Step 3.1: Modify `disableCloud` to Create Tombstone
```swift
// In CloudSyncService.disableCloud()
func disableCloud(for record: MedicalRecord) {
    // Turn off local flags immediately
    record.isCloudEnabled = false
    record.isSharingEnabled = false
    
    // Create tombstone in CloudKit (removes from other synced devices)
    Task {
        do {
            try await createTombstone(for: record)
            ShareDebugStore.shared.appendLog("disableCloud: created tombstone uuid=\(record.uuid)")
        } catch {
            ShareDebugStore.shared.appendLog("disableCloud: tombstone creation failed uuid=\(record.uuid) error=\(error)")
        }
        
        // Clear CloudKit identifiers
        record.cloudRecordName = nil
        record.cloudShareRecordName = nil
        record.shareParticipantsSummary = ""
        record.updatedAt = Date()
    }
}
```

### Phase 4: Handle Re-enabling Cloud

#### Step 4.1: Overwrite Tombstone with Full Data
```swift
// In CloudSyncService.syncIfNeeded()
// Existing logic already handles this:
// - Fetches existing CKRecord (tombstone if present)
// - Calls applyMedicalRecord() which writes all fields
// - Saves, overwriting the tombstone with full data
// NO CHANGES NEEDED - current code already works!
```

### Phase 5: Testing

#### Test Cases:
1. ✅ Delete record on Device A → Verify tombstone created
2. ✅ Device B syncs → Verify B deletes record
3. ✅ Device C syncs 3 weeks later → Verify C deletes record
4. ✅ Set local on Device A → Verify tombstone created, B and C delete
5. ✅ Local record on A, B deletes → Verify A keeps local copy
6. ✅ Re-enable cloud on A → Verify tombstone overwritten with full data
7. ✅ B and C see full record restored

### Phase 6: Schema Update

#### Update CloudKit Schema:
1. Add `isDeleted` field (INT64) to cloudkit-development.cdkb
2. Add `deletedAt` field (DATE) to cloudkit-development.cdkb  
3. Upload schema to CloudKit Dashboard (Development)
4. Test in Development environment
5. Deploy to Production when stable

