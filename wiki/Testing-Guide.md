# Testing Guide

Purus Health uses the Swift Testing framework (not XCTest) for unit and integration tests. This guide covers testing patterns, best practices, and how to write effective tests for the app.

## Testing Framework

### Swift Testing vs. XCTest

The app uses **Swift Testing** introduced in Swift 5.9+:

```swift
import Testing
@testable import PurusHealth

struct MedicalRecordTests {
    @Test
    func testRecordCreation() async throws {
        // Test code
    }
}
```

**Key Differences from XCTest**:
- Use `@Test` attribute instead of `test` prefix
- Use `#expect()` instead of `XCTAssert()`
- Tests can be in structs instead of classes
- Better async/await support
- More descriptive test names

## Test Organization

### Directory Structure

```
PurusHealthTests/
├── ModelTests/
│   ├── MedicalRecordTests.swift
│   ├── BloodEntryTests.swift
│   └── ...
├── ServiceTests/
│   ├── CloudSyncServiceTests.swift
│   ├── ExportServiceTests.swift
│   └── ...
└── ViewTests/
    └── ... (if needed)
```

### Test Naming Conventions

Use descriptive test names that explain what's being tested:

```swift
@Test
func testMedicalRecordDisplayNameForHuman() async throws {
    // ...
}

@Test
func testMedicalRecordDisplayNameForPet() async throws {
    // ...
}

@Test
func testBloodEntryCascadeDelete() async throws {
    // ...
}
```

## Model Tests

### Setting Up Test Context

Always use in-memory storage for tests:

```swift
@Test
func testModelPersistence() async throws {
    // Create in-memory model container
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: MedicalRecord.self,
        configurations: config
    )
    let context = container.mainContext
    
    // Test code using context
}
```

### Testing Model Creation

```swift
@Test
func testMedicalRecordCreation() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: MedicalRecord.self, configurations: config)
    let context = container.mainContext
    
    let record = MedicalRecord()
    record.personalGivenName = "John"
    record.personalFamilyName = "Doe"
    
    context.insert(record)
    try context.save()
    
    #expect(record.personalGivenName == "John")
    #expect(record.personalFamilyName == "Doe")
    #expect(record.displayName == "John Doe")
}
```

### Testing Relationships

```swift
@Test
func testBloodEntryRelationship() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: MedicalRecord.self, configurations: config)
    let context = container.mainContext
    
    let record = MedicalRecord()
    context.insert(record)
    
    let bloodEntry = BloodEntry(date: Date(), value: "120/80", comment: "Normal")
    record.blood.append(bloodEntry)
    
    try context.save()
    
    #expect(record.blood.count == 1)
    #expect(record.blood.first === bloodEntry)
    #expect(bloodEntry.record === record)
}
```

### Testing Cascade Delete

```swift
@Test
func testCascadeDelete() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: MedicalRecord.self, configurations: config)
    let context = container.mainContext
    
    let record = MedicalRecord()
    context.insert(record)
    
    let bloodEntry = BloodEntry(date: Date(), value: "120/80", comment: "Normal")
    record.blood.append(bloodEntry)
    
    try context.save()
    
    // Delete parent record
    context.delete(record)
    try context.save()
    
    // Verify entry was cascade deleted
    let allBlood = try context.fetch(FetchDescriptor<BloodEntry>())
    #expect(allBlood.isEmpty)
}
```

### Testing Data Persistence

```swift
@Test
func testDataPersistence() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    
    // First container
    let container1 = try ModelContainer(for: MedicalRecord.self, configurations: config)
    let context1 = container1.mainContext
    
    let record = MedicalRecord()
    record.uuid = "test-uuid"
    record.personalGivenName = "Jane"
    
    context1.insert(record)
    try context1.save()
    
    // Second container (simulates app restart with in-memory)
    // Note: In-memory doesn't persist, so this tests the model structure
    let container2 = try ModelContainer(for: MedicalRecord.self, configurations: config)
    let context2 = container2.mainContext
    
    // With in-memory, data won't persist
    // For real persistence testing, use a temporary file URL
}
```

### Testing Pet vs. Human Records

```swift
@Test
func testPetRecord() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: MedicalRecord.self, configurations: config)
    let context = container.mainContext
    
    let petRecord = MedicalRecord()
    petRecord.isPet = true
    petRecord.personalName = "Fluffy"
    petRecord.petBreed = "Persian Cat"
    
    context.insert(petRecord)
    try context.save()
    
    #expect(petRecord.isPet == true)
    #expect(petRecord.displayName == "Fluffy")
    #expect(petRecord.petBreed == "Persian Cat")
}

@Test
func testHumanRecord() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: MedicalRecord.self, configurations: config)
    let context = container.mainContext
    
    let humanRecord = MedicalRecord()
    humanRecord.isPet = false
    humanRecord.personalGivenName = "John"
    humanRecord.personalFamilyName = "Doe"
    
    context.insert(humanRecord)
    try context.save()
    
    #expect(humanRecord.isPet == false)
    #expect(humanRecord.displayName == "John Doe")
}
```

## Service Tests

### Testing CloudSyncService

```swift
@MainActor
struct CloudSyncServiceTests {
    @Test
    func testSyncSkipsNonCloudEnabledRecords() async throws {
        let record = MedicalRecord()
        record.isCloudEnabled = false
        
        // Should not throw, should just skip
        try await CloudSyncService.shared.syncIfNeeded(record: record)
        
        // Verify no CloudKit operations occurred
        #expect(record.cloudRecordName == nil)
    }
}
```

### Testing ExportService

```swift
@MainActor
struct ExportServiceTests {
    @Test
    func testJSONExport() async throws {
        let record = MedicalRecord()
        record.personalGivenName = "John"
        record.personalFamilyName = "Doe"
        
        let jsonData = try ExportService.shared.exportRecordToJSON(record)
        
        #expect(!jsonData.isEmpty)
        
        // Verify JSON structure
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        #expect(json?["personalGivenName"] as? String == "John")
        #expect(json?["personalFamilyName"] as? String == "Doe")
    }
}
```

### Testing HTMLTemplateRenderer

```swift
struct HTMLTemplateRendererTests {
    @Test
    func testHTMLGeneration() async throws {
        let record = MedicalRecord()
        record.personalGivenName = "John"
        record.personalFamilyName = "Doe"
        
        let html = try HTMLTemplateRenderer.shared.render(record: record)
        
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("John Doe"))
        #expect(html.contains("<html>"))
        #expect(html.contains("</html>"))
    }
}
```

## Testing Best Practices

### 1. **Use In-Memory Storage**

Always use in-memory storage for tests to ensure isolation:

```swift
let config = ModelConfiguration(isStoredInMemoryOnly: true)
```

### 2. **Clean Up After Tests**

Delete test records after tests complete:

```swift
@Test
func testExample() async throws {
    let context = // ... create context
    
    let record = MedicalRecord()
    context.insert(record)
    try context.save()
    
    // Test operations
    
    // Clean up
    context.delete(record)
    try context.save()
}
```

### 3. **Test Edge Cases**

Always test edge cases and boundary conditions:

```swift
@Test
func testDisplayNameWithEmptyFields() async throws {
    let record = MedicalRecord()
    record.personalGivenName = ""
    record.personalFamilyName = ""
    
    #expect(record.displayName == "Unnamed Person")
}

@Test
func testDisplayNameWithOnlyGivenName() async throws {
    let record = MedicalRecord()
    record.personalGivenName = "John"
    record.personalFamilyName = ""
    
    #expect(record.displayName == "John")
}
```

### 4. **Use @MainActor When Needed**

Mark tests that interact with SwiftData contexts as `@MainActor`:

```swift
@MainActor
struct ModelTests {
    @Test
    func testModelOperation() async throws {
        let context = // ... ModelContext
        // Test code
    }
}
```

### 5. **Avoid Predicate Macros in Tests**

For compatibility, fetch all records and filter in-memory rather than using predicate macros:

```swift
// ✅ Good - Compatible approach
let allRecords = try context.fetch(FetchDescriptor<MedicalRecord>())
let cloudEnabled = allRecords.filter { $0.isCloudEnabled }

// ❌ Avoid in tests - May have compatibility issues
let descriptor = FetchDescriptor<MedicalRecord>(
    predicate: #Predicate { $0.isCloudEnabled == true }
)
```

### 6. **Test Async Operations**

Use `async throws` for async tests:

```swift
@Test
func testAsyncOperation() async throws {
    let result = await someAsyncFunction()
    #expect(result != nil)
}
```

## Assertion Patterns

### Basic Assertions

```swift
#expect(value == expected)
#expect(value != unexpected)
#expect(value > 0)
#expect(value < 100)
#expect(array.count == 5)
#expect(!array.isEmpty)
```

### Optional Assertions

```swift
#expect(optionalValue != nil)
#expect(optionalValue?.property == "expected")

// Unwrap and test
if let value = optionalValue {
    #expect(value.property == "expected")
}
```

### Collection Assertions

```swift
#expect(array.count == 3)
#expect(array.isEmpty)
#expect(array.contains(item))
#expect(array.first == expectedFirst)
#expect(array.last == expectedLast)
```

### Boolean Assertions

```swift
#expect(condition)
#expect(!condition)
#expect(record.isPet == true)
#expect(record.isCloudEnabled == false)
```

## Running Tests

### In Xcode

1. Open Test Navigator (⌘6)
2. Click play button next to test or test suite
3. Or press ⌘U to run all tests

### Command Line

```bash
# Run all tests
xcodebuild test -scheme PurusHealth -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test
xcodebuild test -scheme PurusHealth -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PurusHealthTests/MedicalRecordTests
```

### Continuous Integration

Tests should run on CI for every commit:

```yaml
# Example GitHub Actions workflow
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run tests
        run: |
          xcodebuild test \
            -scheme PurusHealth \
            -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Test Coverage

### Viewing Coverage

1. In Xcode, enable code coverage:
   - Product → Scheme → Edit Scheme
   - Test → Options → Code Coverage ✓
2. Run tests (⌘U)
3. View coverage in Report Navigator (⌘9)

### Coverage Goals

Aim for high coverage on:
- **Models**: 90%+ (core data structures)
- **Services**: 80%+ (business logic)
- **Views**: 50%+ (UI logic is harder to test)

## Mocking and Stubbing

### Mocking CloudKit

For CloudKit tests, use mock containers:

```swift
protocol CloudKitContainerProtocol {
    func save(_ record: CKRecord) async throws -> CKRecord
}

class MockCloudKitContainer: CloudKitContainerProtocol {
    var savedRecords: [CKRecord] = []
    
    func save(_ record: CKRecord) async throws -> CKRecord {
        savedRecords.append(record)
        return record
    }
}
```

### Stubbing Services

Create stub implementations for testing:

```swift
class StubExportService: ExportServiceProtocol {
    var exportCalled = false
    var returnData: Data?
    
    func exportRecordToJSON(_ record: MedicalRecord) throws -> Data {
        exportCalled = true
        return returnData ?? Data()
    }
}
```

## Testing CloudKit Integration

### Testing Serialization

```swift
@Test
func testJSONSerialization() async throws {
    let record = MedicalRecord()
    
    let bloodEntry = BloodEntry(date: Date(), value: "120/80", comment: "Normal")
    record.blood.append(bloodEntry)
    
    // Serialize
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(record.blood)
    let jsonString = String(data: data, encoding: .utf8)
    
    #expect(jsonString != nil)
    #expect(jsonString!.contains("120/80"))
    
    // Deserialize
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode([BloodEntry].self, from: data)
    
    #expect(decoded.count == 1)
    #expect(decoded.first?.value == "120/80")
}
```

## Performance Tests

### Measuring Performance

```swift
@Test
func testLargeDatasetPerformance() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: MedicalRecord.self, configurations: config)
    let context = container.mainContext
    
    // Create large dataset
    let start = Date()
    
    for i in 0..<1000 {
        let record = MedicalRecord()
        record.personalGivenName = "Person \(i)"
        context.insert(record)
    }
    
    try context.save()
    
    let elapsed = Date().timeIntervalSince(start)
    print("Created 1000 records in \(elapsed) seconds")
    
    #expect(elapsed < 5.0)  // Should complete in under 5 seconds
}
```

## Debugging Tests

### Print Debugging

```swift
@Test
func testDebugExample() async throws {
    let record = MedicalRecord()
    print("Record UUID: \(record.uuid)")
    print("Display name: \(record.displayName)")
    
    // Test assertions
}
```

### Breakpoints

Set breakpoints in test code to inspect state:
1. Click line number in Xcode to set breakpoint
2. Run test in debug mode
3. Inspect variables when breakpoint hits

### Test Logs

View test logs in Xcode:
1. Run tests
2. Open Report Navigator (⌘9)
3. Select test run
4. View logs and console output

## Common Testing Pitfalls

### 1. **Shared State**

❌ **Bad**: Tests share state
```swift
let sharedRecord = MedicalRecord()  // Outside test

@Test
func test1() {
    sharedRecord.personalGivenName = "John"
    // ...
}

@Test
func test2() {
    // Assumes sharedRecord state from test1
}
```

✅ **Good**: Each test creates its own state
```swift
@Test
func test1() {
    let record = MedicalRecord()
    record.personalGivenName = "John"
    // ...
}

@Test
func test2() {
    let record = MedicalRecord()
    // Independent test
}
```

### 2. **Testing Implementation Details**

❌ **Bad**: Testing private implementation
```swift
@Test
func testInternalCacheStructure() {
    // Testing internal cache implementation
}
```

✅ **Good**: Testing public behavior
```swift
@Test
func testRecordRetrievalPerformance() {
    // Testing observable behavior
}
```

### 3. **Flaky Tests**

❌ **Bad**: Tests depend on timing or external factors
```swift
@Test
func testFlaky() async throws {
    Task {
        // Some async operation
    }
    // Immediately check result without waiting
}
```

✅ **Good**: Proper async/await usage
```swift
@Test
func testStable() async throws {
    let result = await someAsyncOperation()
    #expect(result != nil)
}
```

## Next Steps

- Review [Contributing Guide](Contributing-Guide)
- Set up [Development Environment](Development-Setup)
- Explore [Architecture Overview](Architecture-Overview)
