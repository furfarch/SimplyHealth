# Views and UI

Purus Health uses SwiftUI for its user interface, providing a native, declarative, and platform-agnostic UI layer for both iOS and macOS.

## View Architecture

The app follows a hierarchical view structure with clear separation between viewing and editing modes.

```
ContentView (Root)
├── RecordListView (List of all records)
│   ├── RecordRow (Individual record in list)
│   └── RecordViewerView (Detail view)
│       ├── RecordViewerSectionPersonal
│       ├── RecordViewerSectionEntries
│       ├── RecordViewerSectionDoctors
│       ├── RecordViewerSectionEmergency
│       └── ... (other viewer sections)
└── RecordEditorView (Edit/Create record)
    ├── RecordEditorSectionPersonal
    ├── RecordEditorSectionEntries
    ├── RecordEditorSectionDoctors
    ├── RecordEditorSectionEmergency
    └── ... (other editor sections)
```

## Main Views

### ContentView

The root view of the application, providing the main navigation structure.

```swift
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        RecordListView()
            .onOpenURL { url in
                // Handle CloudKit share URLs
            }
    }
}
```

**Responsibilities**:
- Provides SwiftData model context to child views
- Handles CloudKit share URL acceptance
- Sets up the main navigation structure

### RecordListView

Displays a list of all medical records with options to create, edit, and delete records.

```swift
struct RecordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [MedicalRecord]
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    NavigationLink(value: record) {
                        RecordRow(record: record)
                    }
                }
                .onDelete(perform: deleteRecords)
            }
            .navigationTitle("Medical Records")
            .toolbar {
                Button(action: addRecord) {
                    Label("Add Record", systemImage: "plus")
                }
            }
        }
    }
}
```

**Features**:
- Fetches records using `@Query`
- Supports swipe-to-delete
- Navigation to detail and edit views
- Add new record button

### RecordViewerView

Displays a read-only view of a medical record with all its information.

**View Structure**:
```swift
struct RecordViewerView: View {
    let record: MedicalRecord
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                RecordViewerSectionPersonal(record: record)
                RecordViewerSectionEntries(record: record)
                RecordViewerSectionDoctors(record: record)
                RecordViewerSectionEmergency(record: record)
                // ... more sections
            }
            .padding()
        }
        .navigationTitle(record.displayName)
        .toolbar {
            Button("Edit") {
                // Navigate to editor
            }
            Menu("More") {
                Button("Export PDF") { }
                Button("Share") { }
            }
        }
    }
}
```

**Sections**:
- `RecordViewerSectionPersonal` - Personal information
- `RecordViewerSectionEntries` - Medical entries (blood, drugs, vaccinations)
- `RecordViewerSectionDoctors` - Doctor information
- `RecordViewerSectionEmergency` - Emergency contacts
- `RecordViewerSectionPetVet` - Pet veterinarian (for pets)
- `RecordViewerSectionPetYearlyCosts` - Pet costs (for pets)

### RecordEditorView

Provides an interface to create or edit medical records.

```swift
struct RecordEditorView: View {
    @Bindable var record: MedicalRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            RecordEditorSectionPersonal(record: record)
            RecordEditorSectionEntries(record: record)
            RecordEditorSectionDoctors(record: record)
            RecordEditorSectionEmergency(record: record)
            // ... more sections
        }
        .navigationTitle(record.isPet ? "Pet Record" : "Personal Record")
        .toolbar {
            Button("Save") {
                try? modelContext.save()
                dismiss()
            }
        }
    }
}
```

**Features**:
- Uses `@Bindable` for two-way data binding
- Organized into sections for different data types
- Save button commits changes to SwiftData
- Dismiss after save

## View Sections

View sections are reusable components that handle specific parts of the record UI.

### RecordEditorSectionPersonal

Handles personal information fields, adapting based on whether the record is for a human or pet.

```swift
struct RecordEditorSectionPersonal: View {
    @Bindable var record: MedicalRecord
    
    var body: some View {
        Section("Personal Information") {
            if record.isPet {
                TextField("Name", text: $record.personalName)
                TextField("Animal ID", text: $record.personalAnimalID)
                TextField("Breed", text: $record.petBreed)
                TextField("Color", text: $record.petColor)
                
                DatePicker("Date of Birth",
                          selection: Binding(
                              get: { record.personalBirthdate ?? Date() },
                              set: { record.personalBirthdate = $0 }
                          ),
                          displayedComponents: .date)
                
                Picker("Sex", selection: $record.personalGender) {
                    Text("Not specified").tag("")
                    Text("Male").tag("Male")
                    Text("Female").tag("Female")
                    Text("N/A").tag("N/A")
                }
            } else {
                TextField("Given Name", text: $record.personalGivenName)
                TextField("Family Name", text: $record.personalFamilyName)
                TextField("Nickname", text: $record.personalNickName)
                
                DatePicker("Birthdate",
                          selection: Binding(
                              get: { record.personalBirthdate ?? Date() },
                              set: { record.personalBirthdate = $0 }
                          ),
                          displayedComponents: .date)
                
                Picker("Gender", selection: $record.personalGender) {
                    Text("Not specified").tag("")
                    Text("Male").tag("Male")
                    Text("Female").tag("Female")
                    Text("N/A").tag("N/A")
                }
                
                TextField("Address", text: $record.personalAddress)
                TextField("Health Insurance", text: $record.personalHealthInsurance)
                // ... more fields
            }
        }
    }
}
```

**Key Patterns**:
- Conditional rendering based on `record.isPet`
- `@Bindable` for two-way binding to model properties
- DatePicker pattern for optional dates using custom Binding
- Picker for enumerated values (gender/sex)

### RecordEditorSectionEntries

Manages lists of medical entries (blood, drugs, vaccinations, allergies, etc.).

```swift
struct RecordEditorSectionEntries: View {
    @Bindable var record: MedicalRecord
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        // Blood Entries
        Section("Blood Work") {
            ForEach(record.blood) { entry in
                BloodEntryRow(entry: entry)
            }
            .onDelete { indices in
                deleteBloodEntries(at: indices)
            }
            
            Button("Add Blood Entry") {
                addBloodEntry()
            }
        }
        
        // Drug Entries
        Section("Medications") {
            ForEach(record.drugs) { entry in
                DrugEntryRow(entry: entry)
            }
            .onDelete { indices in
                deleteDrugEntries(at: indices)
            }
            
            Button("Add Medication") {
                addDrugEntry()
            }
        }
        
        // ... similar sections for other entry types
    }
    
    private func addBloodEntry() {
        let entry = BloodEntry()
        record.blood.append(entry)
    }
    
    private func deleteBloodEntries(at indices: IndexSet) {
        for index in indices {
            let entry = record.blood[index]
            modelContext.delete(entry)
        }
    }
}
```

**Key Patterns**:
- `ForEach` with `onDelete` for swipe-to-delete
- Add button creates new entries and appends to relationship array
- Delete operations use `modelContext.delete()`

### RecordViewerSectionPersonal

Read-only display of personal information.

```swift
struct RecordViewerSectionPersonal: View {
    let record: MedicalRecord
    
    var body: some View {
        Section("Personal Information") {
            if record.isPet {
                RecordViewerRow(label: "Name", value: record.personalName)
                RecordViewerRow(label: "Animal ID", value: record.personalAnimalID)
                RecordViewerRow(label: "Breed", value: record.petBreed)
                // ... more fields
            } else {
                RecordViewerRow(label: "Name", value: record.displayName)
                RecordViewerRow(label: "Birthdate", value: formatDate(record.personalBirthdate))
                RecordViewerRow(label: "Gender", value: record.personalGender)
                // ... more fields
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Not set" }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }
}
```

**Key Patterns**:
- Uses helper view `RecordViewerRow` for consistent formatting
- Conditional rendering based on `record.isPet`
- Date formatting for display

### RecordViewerRow

A reusable row component for displaying label-value pairs.

```swift
struct RecordViewerRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "Not set" : value)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
}
```

## Supporting Views

### CloudRecordSettingsView

Manages CloudKit settings for a record.

```swift
struct CloudRecordSettingsView: View {
    @Bindable var record: MedicalRecord
    
    var body: some View {
        Form {
            Section("Cloud Sync") {
                Toggle("Enable Cloud Sync", isOn: $record.isCloudEnabled)
                
                if record.isCloudEnabled {
                    Toggle("Enable Sharing", isOn: $record.isSharingEnabled)
                    
                    if record.isSharingEnabled {
                        Button("Share Record") {
                            // Show share sheet
                        }
                    }
                }
            }
            
            Section("Status") {
                RecordViewerRow(label: "Location", value: record.recordLocation.description)
                RecordViewerRow(label: "Cloud Record", value: record.cloudShareRecordName ?? "None")
            }
        }
    }
}
```

### ExportSettingsView

Provides options for exporting records.

```swift
struct ExportSettingsView: View {
    @Bindable var record: MedicalRecord
    @State private var exportFormat: ExportFormat = .pdf
    
    enum ExportFormat {
        case pdf, json
    }
    
    var body: some View {
        Form {
            Section("Export Format") {
                Picker("Format", selection: $exportFormat) {
                    Text("PDF").tag(ExportFormat.pdf)
                    Text("JSON").tag(ExportFormat.json)
                }
            }
            
            Section {
                Button("Export") {
                    performExport()
                }
            }
        }
    }
    
    private func performExport() {
        // Call ExportService
    }
}
```

### SettingsView

App-wide settings view.

```swift
struct SettingsView: View {
    @AppStorage("cloudEnabled") private var cloudEnabled = false
    
    var body: some View {
        Form {
            Section("Cloud Sync") {
                Toggle("Enable Cloud Sync Globally", isOn: $cloudEnabled)
            }
            
            Section("About") {
                NavigationLink("About Purus Health") {
                    AboutView()
                }
            }
        }
        .navigationTitle("Settings")
    }
}
```

## UI Patterns

### 1. **Environment-Based Dependency Injection**

Use `@Environment` to access SwiftData context:

```swift
@Environment(\.modelContext) private var modelContext
```

### 2. **Two-Way Data Binding**

Use `@Bindable` for model binding in SwiftUI:

```swift
struct EditorView: View {
    @Bindable var record: MedicalRecord
    
    var body: some View {
        TextField("Name", text: $record.personalGivenName)
    }
}
```

### 3. **Optional Date Binding**

Pattern for DatePicker with optional dates:

```swift
DatePicker("Date",
          selection: Binding(
              get: { record.personalBirthdate ?? Date() },
              set: { record.personalBirthdate = $0 }
          ),
          displayedComponents: .date)
```

### 4. **List Management**

Pattern for managing lists with add/delete:

```swift
ForEach(record.blood) { entry in
    EntryRow(entry: entry)
}
.onDelete { indices in
    for index in indices {
        let entry = record.blood[index]
        modelContext.delete(entry)
    }
}

Button("Add Entry") {
    let entry = BloodEntry()
    record.blood.append(entry)
}
```

### 5. **Conditional UI**

Show different UI based on record type:

```swift
if record.isPet {
    // Pet-specific UI
} else {
    // Human-specific UI
}
```

## Platform-Specific Views

### iOS-Specific

```swift
#if canImport(UIKit)
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
```

### macOS-Specific

```swift
#if canImport(AppKit)
// macOS-specific implementations
#endif
```

## Preview Providers

All views should include preview providers for development:

```swift
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: MedicalRecord.self, configurations: [config])
    
    let record = MedicalRecord()
    record.personalGivenName = "John"
    record.personalFamilyName = "Doe"
    container.mainContext.insert(record)
    
    return RecordViewerView(record: record)
        .modelContainer(container)
}
```

**Key Points**:
- Use in-memory model container
- Create sample data
- Provide model container to preview

## Accessibility

### VoiceOver Support

SwiftUI provides automatic VoiceOver support, but you can enhance it:

```swift
TextField("Name", text: $record.personalGivenName)
    .accessibilityLabel("Person's given name")
    .accessibilityHint("Enter the first name of the person")
```

### Dynamic Type

Support Dynamic Type automatically by using system fonts:

```swift
Text("Name")
    .font(.headline)  // Automatically scales with user's font size preference
```

## Best Practices

### 1. **Component Reusability**
Break down complex views into smaller, reusable components:

```swift
// ✅ Good
RecordViewerRow(label: "Name", value: record.displayName)

// ❌ Avoid
HStack {
    Text("Name")
    Spacer()
    Text(record.displayName)
}
```

### 2. **Separation of Concerns**
Keep view logic separate from business logic:

```swift
// ✅ Good - Business logic in service
Button("Export") {
    ExportService.shared.exportRecord(record)
}

// ❌ Avoid - Business logic in view
Button("Export") {
    // 50 lines of export logic here
}
```

### 3. **Consistent Spacing**
Use consistent spacing throughout the app:

```swift
VStack(spacing: 20) {
    // Content
}
.padding()
```

### 4. **Error Handling in Views**
Show user-friendly error messages:

```swift
@State private var errorMessage: String?
@State private var showError = false

// In view
.alert("Error", isPresented: $showError) {
    Button("OK") { }
} message: {
    Text(errorMessage ?? "An unknown error occurred")
}
```

## Next Steps

- Understand [Services](Services)
- Explore [CloudKit Integration](CloudKit-Integration)
- Learn about [Testing Guide](Testing-Guide)
