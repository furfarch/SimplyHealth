# Data Models

Purus Health uses SwiftData for local persistence and CloudKit for cloud synchronization. All models are defined using the `@Model` macro and follow consistent patterns for relationships and data management.

## Core Model: MedicalRecord

The `MedicalRecord` is the central entity in the app, representing either a human or pet medical record.

### Model Structure

```swift
@Model
final class MedicalRecord {
    // Timestamps
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // Stable identifier
    var uuid: String = UUID().uuidString
    var id: String { uuid }  // Computed property for Identifiable conformance
    
    // Personal information (human)
    var personalFamilyName: String = ""
    var personalGivenName: String = ""
    var personalNickName: String = ""
    var personalGender: String = ""
    var personalBirthdate: Date? = nil
    var personalSocialSecurityNumber: String = ""
    var personalAddress: String = ""
    var personalHealthInsurance: String = ""
    var personalHealthInsuranceNumber: String = ""
    var personalEmployer: String = ""
    
    // Pet-related fields
    var isPet: Bool = false
    var personalName: String = ""
    var personalAnimalID: String = ""
    var petBreed: String = ""
    var petColor: String = ""
    var ownerName: String = ""
    var ownerPhone: String = ""
    var ownerEmail: String = ""
    
    // Pet veterinarian details
    var vetClinicName: String = ""
    var vetContactName: String = ""
    var vetPhone: String = ""
    var vetEmail: String = ""
    var vetAddress: String = ""
    var vetNote: String = ""
    
    // CloudKit fields
    var isCloudEnabled: Bool = false
    var isSharingEnabled: Bool = false
    var cloudShareRecordName: String? = nil
    var recordLocation: RecordLocation = .local
    
    // Relationships (see below for details)
    @Relationship(deleteRule: .cascade) var blood: [BloodEntry]
    @Relationship(deleteRule: .cascade) var drugs: [DrugEntry]
    @Relationship(deleteRule: .cascade) var vaccinations: [VaccinationEntry]
    // ... and more
}
```

### Key Design Patterns

#### 1. **UUID-Based Identifiers**
- Uses `uuid` field instead of SwiftData's synthesized `id`
- Provides stable identifiers for CloudKit synchronization
- Computed `id` property for `Identifiable` conformance

```swift
var uuid: String = UUID().uuidString
var id: String { uuid }
```

#### 2. **Optional Backing Storage**
For CloudKit compatibility, relationships use optional backing storage:

```swift
@Relationship(deleteRule: .cascade, inverse: \BloodEntry.record)
private var _blood: [BloodEntry]? = nil

var blood: [BloodEntry] {
    get { _blood ?? [] }
    set { _blood = newValue }
}
```

This pattern ensures CloudKit JSON deserialization works correctly even when relationship data is nil.

#### 3. **Shared Fields for Humans and Pets**
To reduce schema complexity, humans and pets share certain fields:

- `personalBirthdate` - Used for both human birthdate and pet date of birth
- `personalGender` - Used for both human gender and pet sex

The `isPet` flag determines how these fields are interpreted and displayed in the UI.

#### 4. **Display Name Computation**

```swift
var displayName: String {
    if isPet {
        return personalName.isEmpty ? "Unnamed Pet" : personalName
    } else {
        let name = [personalGivenName, personalFamilyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "Unnamed Person" : name
    }
}
```

## Entry Models

Entry models represent specific types of medical information. All entries follow a consistent pattern.

### BloodEntry

Represents blood work and lab results.

```swift
@Model
final class BloodEntry {
    var date: Date?
    var value: String = ""
    var comment: String = ""
    
    var record: MedicalRecord?
    
    init(date: Date? = nil, value: String = "", comment: String = "") {
        self.date = date
        self.value = value
        self.comment = comment
    }
}
```

### DrugEntry

Represents medications and prescriptions.

```swift
@Model
final class DrugEntry {
    var date: Date?
    var name: String = ""
    var information: String = ""
    var comment: String = ""
    
    var record: MedicalRecord?
    
    init(date: Date? = nil, name: String = "", information: String = "", comment: String = "") {
        self.date = date
        self.name = name
        self.information = information
        self.comment = comment
    }
}
```

### VaccinationEntry

Represents vaccination records.

```swift
@Model
final class VaccinationEntry {
    var date: Date?
    var name: String = ""
    var information: String = ""
    var place: String = ""
    var comment: String = ""
    
    var record: MedicalRecord?
}
```

### AllergyEntry

Represents allergy information.

```swift
@Model
final class AllergyEntry {
    var information: String = ""
    var comment: String = ""
    
    var record: MedicalRecord?
}
```

### IllnessEntry

Represents medical conditions and illnesses.

```swift
@Model
final class IllnessEntry {
    var information: String = ""
    var comment: String = ""
    
    var record: MedicalRecord?
}
```

### RiskEntry

Represents health risk factors.

```swift
@Model
final class RiskEntry {
    var information: String = ""
    var comment: String = ""
    
    var record: MedicalRecord?
}
```

### MedicalHistoryEntry

Represents medical history events.

```swift
@Model
final class MedicalHistoryEntry {
    var information: String = ""
    var comment: String = ""
    
    var record: MedicalRecord?
}
```

### MedicalDocumentEntry

Represents attached medical documents.

```swift
@Model
final class MedicalDocumentEntry {
    var documentName: String = ""
    var documentType: String = ""
    var documentData: Data?
    var comment: String = ""
    
    var record: MedicalRecord?
}
```

### HumanDoctorEntry

Represents doctor information with timestamps.

```swift
@Model
final class HumanDoctorEntry {
    var uuid: String = UUID().uuidString
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    var date: Date?
    var name: String = ""
    var specialty: String = ""
    var contactName: String = ""
    var phone: String = ""
    var email: String = ""
    var address: String = ""
    var comment: String = ""
    
    var record: MedicalRecord?
}
```

### WeightEntry

Represents weight tracking with timestamps.

```swift
@Model
final class WeightEntry {
    var uuid: String = UUID().uuidString
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    var date: Date?
    var weight: Double = 0.0
    var unit: String = "kg"  // "kg" or "lbs"
    var comment: String = ""
    
    var record: MedicalRecord?
}
```

### PetYearlyCostEntry

Represents annual pet medical costs with timestamps.

```swift
@Model
final class PetYearlyCostEntry {
    var uuid: String = UUID().uuidString
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    var year: Int = 0
    var cost: Double = 0.0
    var currency: String = "USD"
    var comment: String = ""
    
    var record: MedicalRecord?
}
```

### EmergencyContact

Represents emergency contact information.

```swift
@Model
final class EmergencyContact {
    var name: String = ""
    var phone: String = ""
    var email: String = ""
    var relationship: String = ""
    
    var record: MedicalRecord?
}
```

## Relationship Patterns

### One-to-Many Relationships

All entry models have a many-to-one relationship with `MedicalRecord`:

```swift
// In MedicalRecord
@Relationship(deleteRule: .cascade, inverse: \BloodEntry.record)
var blood: [BloodEntry]

// In BloodEntry
var record: MedicalRecord?
```

### Cascade Delete

All relationships use `.cascade` delete rule to maintain data integrity. When a `MedicalRecord` is deleted, all associated entries are automatically deleted.

```swift
@Relationship(deleteRule: .cascade)
```

## CloudKit Compatibility

### JSON Serialization

SwiftData relationships cannot be directly stored in CloudKit. Instead, the app serializes relationships to JSON strings:

```swift
// Serialization (in CloudSyncService)
let bloodData = try JSONEncoder().encode(record.blood)
ckRecord["bloodEntries"] = String(data: bloodData, encoding: .utf8)

// Deserialization (in CloudKitMedicalRecordFetcher)
if let bloodString = ckRecord["bloodEntries"] as? String,
   let bloodData = bloodString.data(using: .utf8) {
    let bloodEntries = try JSONDecoder().decode([BloodEntry].self, from: bloodData)
    record.blood = bloodEntries
}
```

### Codable Models

For CloudKit operations, there are corresponding Codable structs in `CloudKitCodableModels.swift`:

```swift
struct CodableBloodEntry: Codable {
    var date: Date?
    var value: String
    var comment: String
}
```

These are used as intermediaries during JSON serialization/deserialization.

## Model Container Configuration

### Persistent Storage

The app uses persistent storage by default:

```swift
let localConfig = ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .none  // CloudKit is handled separately
)

let modelContainer = try ModelContainer(for: schema, configurations: [localConfig])
```

Note: `cloudKitDatabase: .none` is used because CloudKit sync is implemented manually via services, not through SwiftData's automatic CloudKit integration.

### In-Memory Storage (Testing)

For tests, use in-memory storage:

```swift
let memoryConfig = ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: true,
    cloudKitDatabase: .none
)
```

## Schema Evolution

When adding new fields to models:

1. **Add to SwiftData Model**: Update the `@Model` class
2. **Add to CloudKit Schema**: Update `cloudkit-development.cdkb`
3. **Update Serialization**: Add to `CloudSyncService.applyMedicalRecord()`
4. **Update Deserialization**: Add to `CloudKitMedicalRecordFetcher.importToSwiftData()`
5. **Update Codable Models**: Add to `CloudKitCodableModels.swift` if needed

See [CloudKit Integration](CloudKit-Integration#adding-new-fields) for detailed instructions.

## Best Practices

### 1. **Always Provide Default Values**
All properties should have default values for CloudKit compatibility:

```swift
var name: String = ""  // ✅ Good
var name: String       // ❌ Bad - may cause issues with CloudKit
```

### 2. **Use Optional Dates When Appropriate**
Dates that might not be set should be optional:

```swift
var date: Date? = nil  // ✅ Good for optional dates
var createdAt: Date = Date()  // ✅ Good for required timestamps
```

### 3. **Provide Initializers for Entry Models**
Entry models should have initializers for easy creation:

```swift
init(date: Date? = nil, name: String = "", information: String = "") {
    self.date = date
    self.name = name
    self.information = information
}
```

### 4. **Back-Reference to Parent**
All entry models should have a reference back to their parent `MedicalRecord`:

```swift
var record: MedicalRecord?
```

This enables the inverse relationship and cascade delete.

## Testing Models

### Creating Test Records

```swift
@Test
func testModelCreation() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: MedicalRecord.self, configurations: config)
    let context = container.mainContext
    
    let record = MedicalRecord()
    record.personalGivenName = "John"
    record.personalFamilyName = "Doe"
    
    context.insert(record)
    try context.save()
    
    #expect(record.displayName == "John Doe")
}
```

### Testing Relationships

```swift
@Test
func testRelationships() async throws {
    let context = // ... create context
    
    let record = MedicalRecord()
    context.insert(record)
    
    let blood = BloodEntry(date: Date(), value: "120/80", comment: "Normal")
    record.blood.append(blood)
    
    try context.save()
    
    #expect(record.blood.count == 1)
    #expect(blood.record === record)
}
```

## Next Steps

- Learn about [Views and UI](Views-and-UI)
- Understand [Services](Services)
- Explore [CloudKit Integration](CloudKit-Integration)
