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

## Alternative Approaches (No Tombstones)

### Option A: LastSeenOnCloud Tracking (RECOMMENDED)

**Concept**: Track which CloudKit records we've seen, detect unexpected disappearances

**Implementation**:
```swift
// Track UUIDs of records we've seen in CloudKit
private let lastSeenCloudRecordsKey = "LastSeenCloudRecords"

func trackCloudRecords(uuids: [String]) {
    UserDefaults.standard.set(uuids, forKey: lastSeenCloudRecordsKey)
}

func wasSeenInCloud(uuid: String) -> Bool {
    let seen = UserDefaults.standard.array(forKey: lastSeenCloudRecordsKey) as? [String] ?? []
    return seen.contains(uuid)
}
```

**During sync:**
1. Fetch all current CloudKit records
2. Compare to "last seen" list
3. Records in "last seen" but not in CloudKit → deleted by another device
4. Check if local record is cloud-enabled:
   - If YES → delete locally (deletion sync)
   - If NO → keep locally (protected)

**Advantages:**
- ✅ No tombstones
- ✅ Simple state tracking
- ✅ Protects local-only records
- ✅ Detects deletions

**Disadvantages:**
- ❌ Requires full fetch to detect deletions (not incremental)
- ❌ First sync after app install sees nothing → treats all as "new"

---

### Option B: Local-Only Flag in CloudKit (SIMPLE)

**Concept**: Don't delete from CloudKit when setting to local-only

**Changes:**
1. Add `isLocalOnlyOnSomeDevice` boolean field to CloudKit
2. When user sets local on Device A:
   - Set local flag `isCloudEnabled = false`
   - Write to CloudKit: `isLocalOnlyOnSomeDevice = true`
   - Do NOT delete from CloudKit
3. During import on Device B:
   - See `isLocalOnlyOnSomeDevice = true`
   - Respect it: keep cloud copy but show indicator
4. When user deletes on Device B:
   - Delete from CloudKit normally
5. Device A syncs:
   - Sees deletion, but `isCloudEnabled = false`
   - Protected from deletion

**Advantages:**
- ✅ No tombstones
- ✅ Simple boolean field
- ✅ All devices see the "local-only" intent
- ✅ Deletions work normally

**Disadvantages:**
- ❌ CloudKit still stores record even if "local-only" on all devices
- ❌ Requires schema change
- ❌ Coordination complexity

---

### Option C: Deletion Timestamp (MINIMAL TOMBSTONE)

**Concept**: Use a simple deletion timestamp instead of boolean tombstone

**Implementation:**
```swift
// In CloudKit schema
deletedAt: Date? // Only set when deleted

// When deleting
ckRecord["deletedAt"] = Date()
ckRecord["updatedAt"] = Date()
// Save, then delete after 1 second
Task {
    try await Task.sleep(nanoseconds: 1_000_000_000)
    try await database.deleteRecord(withID: ckID)
}

// During import
if let deletedAt = ckRecord["deletedAt"] as? Date {
    // Record was deleted
    if record.isCloudEnabled {
        context.delete(record) // Sync deletion
    }
    // Don't re-import
    continue
}
```

**Advantages:**
- ✅ Minimal tombstone (just timestamp)
- ✅ Auto-cleanup (delete after 1 second)
- ✅ Works with incremental sync
- ✅ Protects local records

**Disadvantages:**
- ❌ Still uses tombstones (user concern)
- ❌ Race condition window (1 second)

---

### Option D: CloudKit Zones as "Local-Only Barrier" (RADICAL)

**Concept**: Use separate CloudKit zones for cloud vs local-only tracking

**Not recommended** - too complex and doesn't align with CloudKit design.

---

## Recommended Solution: Hybrid Approach

Combine **Option A** (LastSeenOnCloud) with **Option C** (Minimal Tombstone):

1. **Track last seen records** for deletion detection
2. **Use deletedAt timestamp** for immediate propagation
3. **Auto-cleanup tombstones** after 24 hours (via background job)
4. **Protect local records** during deletion sync

**Key behaviors:**
- Set local on A → Writes to CloudKit, marks as "local on some device"
- Delete on B → Sets deletedAt, deletes after 24h
- A syncs → Sees deletedAt but is protected (isCloudEnabled=false)
- Re-enable on A → Uploads normally

**Tombstone cleanup:**
- deletedAt older than 24 hours → permanent deletion
- Gives all devices time to sync
- No long-lived tombstones

---

## Specific Answers to User Questions

### 1) Set local on A - what happens to B and C?
**Proposed**: A writes `isCloudEnabled=false` locally, marks in CloudKit `localOnSomeDevice=true`. B and C see flag, show indicator, but keep their cloud copies active.

### 2) Local on A, deleted/changed on other devices - what happens?
- **Delete on B**: Sets deletedAt in CloudKit. A syncs, sees deletedAt, but protected (isCloudEnabled=false). B and C delete.
- **Change on B**: A syncs, sees change, but respects local `isCloudEnabled=false` setting. Doesn't auto-enable cloud.

### 3) Local re-enabled on A to cloud - what happens on B and C?
**Proposed**: A uploads with latest timestamp. B and C see newer version during sync, update their copies. All in sync.

### 4) What when A and C set to local?
**Proposed**: A and C both local. B keeps cloud copy. If B deletes, A and C protected. If B changes, A and C don't auto-sync (local setting preserved).

---

## Next Steps

1. Implement local record protection (fix immediate bug)
2. Add LastSeenOnCloud tracking
3. Add minimal deletedAt tombstone (24h cleanup)
4. Test all scenarios
5. Document behavior in wiki

