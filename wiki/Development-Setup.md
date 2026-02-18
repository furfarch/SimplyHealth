# Development Setup

This guide will help you set up your development environment for contributing to Purus Health.

## Prerequisites

### Required Software

1. **macOS**: Version 13.0 (Ventura) or later
2. **Xcode**: Latest version (15.0+)
   - Download from Mac App Store or [Apple Developer](https://developer.apple.com/xcode/)
3. **Command Line Tools**: Installed via Xcode
4. **Git**: Installed (comes with Xcode Command Line Tools)

### Apple Developer Account

For CloudKit features and testing:
- **Free Account**: Sufficient for development and testing
- **Paid Account**: Required for App Store distribution

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/furfarch/Purus.Health.git
cd Purus.Health
```

### 2. Open the Project

```bash
open PurusHealth.xcodeproj
```

Alternatively, open Xcode and use File → Open, then select `PurusHealth.xcodeproj`.

### 3. Configure Signing

1. Select the project in the Project Navigator
2. Select the **PurusHealth** target
3. Go to **Signing & Capabilities** tab
4. Select your Team from the dropdown
5. Xcode will automatically manage provisioning profiles

**Bundle Identifier**: If needed, change to a unique identifier (e.g., `com.yourname.purushealth`)

### 4. Select a Destination

Choose your target device:
- **iOS Simulator**: iPhone 15, iPad Pro, etc.
- **My Mac**: For macOS testing
- **Physical Device**: Connect via USB and select from device list

### 5. Build the Project

Press **⌘R** or click the Play button to build and run.

**First Build**: May take a few minutes as Xcode indexes the project and downloads dependencies.

## Project Structure

Understanding the project layout:

```
Purus.Health/
├── PurusHealth/              # Main app source
│   ├── Models/               # SwiftData models
│   ├── Views/                # SwiftUI views
│   │   ├── RecordEditor/     # Editing views
│   │   └── RecordViewer/     # Viewing views
│   ├── Services/             # Business logic
│   ├── Support/              # Helper files
│   ├── Assets.xcassets       # Images and colors
│   ├── PurusHealthApp.swift  # App entry point
│   └── AppConfig.swift       # Configuration
├── PurusHealthTests/         # Unit tests
├── PurusHealthUITests/       # UI tests
├── wiki/                     # Documentation (this wiki)
├── README.md                 # Project readme
├── SETUP-GUIDE.md           # Setup instructions
└── cloudkit-development.cdkb # CloudKit schema
```

## Building the Project

### Clean Build

If you encounter build issues:

1. **Clean Build Folder**: ⌘⇧K (Product → Clean Build Folder)
2. **Delete Derived Data**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```
3. **Rebuild**: ⌘B (Product → Build)

### Build Configuration

The project has two build configurations:

- **Debug**: For development, includes debugging symbols
- **Release**: Optimized for distribution

To change configuration:
1. Product → Scheme → Edit Scheme
2. Select Run
3. Change Build Configuration

## Running Tests

### Unit Tests

```bash
# In Xcode
⌘U  # Run all tests

# Command line
xcodebuild test \
  -scheme PurusHealth \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### UI Tests

UI tests are in `PurusHealthUITests/`:

```bash
# Run specific UI test
xcodebuild test \
  -scheme PurusHealth \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:PurusHealthUITests/UITestSuite
```

### Test Coverage

Enable code coverage:
1. Product → Scheme → Edit Scheme
2. Test → Options → ✓ Code Coverage
3. Run tests (⌘U)
4. View coverage in Report Navigator (⌘9)

## CloudKit Development

### Setting Up CloudKit Container

1. **Create Container** (if not exists):
   - Go to [Apple Developer Portal](https://developer.apple.com)
   - Certificates, Identifiers & Profiles → Identifiers
   - Select CloudKit Containers
   - Click + to create: `iCloud.com.purus.health`

2. **Configure in Xcode**:
   - Select project → PurusHealth target
   - Signing & Capabilities → iCloud
   - Enable CloudKit
   - Add container: `iCloud.com.purus.health`

### CloudKit Dashboard

Access the CloudKit Dashboard:
- URL: https://icloud.developer.apple.com/dashboard/
- Select container: `iCloud.com.purus.health`
- View records, schema, and logs

### Development vs. Production

CloudKit has separate Development and Production environments:

- **Development**: Used automatically in debug builds
- **Production**: Used in App Store builds

**Schema Management**:
1. Create schema in Development
2. Test thoroughly
3. Deploy to Production via CloudKit Dashboard

### CloudKit Schema

The schema is defined in `cloudkit-development.cdkb`:

```
# MedicalRecord type with all fields
RECORD TYPE MedicalRecord (
  uuid          STRING,
  createdAt     DATE_TIME,
  updatedAt     DATE_TIME,
  isPet         INT64,
  # ... more fields
  bloodEntries  STRING,  # JSON array
  drugEntries   STRING,  # JSON array
  # ... more relationships
)
```

**Uploading Schema**:
1. Open CloudKit Dashboard
2. Select Development environment
3. Schema → Import Schema
4. Select `cloudkit-development.cdkb`

## Debugging

### Console Logging

The app uses console logging with component prefixes:

```swift
print("[PurusHealthApp] Launched")
print("[CloudSync] Syncing record \(record.uuid)")
ShareDebugStore.shared.appendLog("Share accepted")
```

**View Logs**:
- Xcode Console: ⌘⇧Y (View → Debug Area → Show Debug Area)
- Filter logs using the search bar

### Breakpoints

Set breakpoints to pause execution:
1. Click line number in code
2. Blue arrow appears
3. Run app in debug mode
4. Inspector shows variables when paused

### LLDB Debugging

When paused at breakpoint:

```lldb
po record                    # Print object
po record.displayName        # Print property
expr record.isPet = true     # Modify value
continue                     # Resume execution
```

### View Hierarchy

Inspect the view hierarchy:
1. Run app in simulator
2. Debug → View Debugging → Capture View Hierarchy
3. Explore 3D view of UI

### Memory Graph

Detect memory leaks:
1. Run app
2. Debug → Memory Graph
3. Look for leaked objects (exclamation marks)

## Common Issues

### Issue: Build Fails with Signing Error

**Solution**: 
1. Select project → Target → Signing & Capabilities
2. Change Team to your Apple Developer account
3. Change Bundle Identifier if needed

### Issue: CloudKit Container Not Found

**Solution**:
1. Verify container ID in `AppConfig.swift` matches Apple Developer Portal
2. Ensure container is added in Xcode Signing & Capabilities
3. Sign in to iCloud on simulator/device

### Issue: SwiftData Not Persisting

**Solution**:
1. Check `ModelConfiguration` uses `isStoredInMemoryOnly: false`
2. Verify models are included in `ModelContainer` schema
3. Ensure `context.save()` is called after changes

### Issue: Simulator iCloud Sign-In

**Solution**:
1. Open Simulator
2. Settings → Sign in to iCloud
3. Use test Apple ID (not production account)
4. Enable iCloud Drive

### Issue: Code Signing Errors on Physical Device

**Solution**:
1. Connect device to Mac
2. Xcode → Window → Devices and Simulators
3. Select device → Trust on both Mac and device
4. Rebuild project

## Development Workflow

### Recommended Workflow

1. **Create Feature Branch**:
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make Changes**: Edit code in Xcode

3. **Test Locally**: Run tests (⌘U)

4. **Commit Changes**:
   ```bash
   git add .
   git commit -m "Add feature: description"
   ```

5. **Push to GitHub**:
   ```bash
   git push origin feature/my-feature
   ```

6. **Create Pull Request**: On GitHub, create PR to main branch

### Code Style

Follow Swift style guidelines:
- Use 4 spaces for indentation
- Follow Apple's [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use meaningful variable names
- Add comments for complex logic

### Git Workflow

- **Main Branch**: Production-ready code
- **Feature Branches**: New features
- **Bugfix Branches**: Bug fixes
- **Release Branches**: Release preparation

### Commit Messages

Write clear commit messages:

```
✅ Good:
"Add blood pressure entry validation"
"Fix crash when deleting shared record"
"Update CloudKit schema with new fields"

❌ Bad:
"Fix bug"
"Update"
"WIP"
```

## Tools and Extensions

### Recommended Xcode Extensions

- **SwiftLint**: Code style enforcement
- **SourceKit-LSP**: Enhanced code completion
- **Copilot**: AI-powered code assistance

### Terminal Commands

Useful commands for development:

```bash
# View git log
git log --oneline --graph

# Check git status
git status

# View changes
git diff

# Reset local changes
git checkout .

# Update from main
git pull origin main

# Clean Xcode derived data
rm -rf ~/Library/Developer/Xcode/DerivedData
```

## Performance Profiling

### Instruments

Use Instruments for performance analysis:
1. Product → Profile (⌘I)
2. Select template:
   - **Time Profiler**: CPU usage
   - **Allocations**: Memory usage
   - **Leaks**: Memory leaks
   - **Network**: Network activity

### Optimization Tips

- Use `@MainActor` for UI operations
- Avoid blocking main thread with heavy computations
- Use lazy loading for large datasets
- Cache expensive computations
- Use `Task` for async operations

## Accessibility Testing

### VoiceOver Testing

Test with VoiceOver on iOS:
1. Settings → Accessibility → VoiceOver → On
2. Navigate app with gestures
3. Verify all UI elements are accessible

### Dynamic Type Testing

Test with different text sizes:
1. Settings → Display & Brightness → Text Size
2. Adjust slider
3. Verify UI adapts correctly

## Localization

While not currently implemented, to add localization:

1. **Add Localizable.strings**:
   ```
   "record_list_title" = "Medical Records";
   "add_record" = "Add Record";
   ```

2. **Use in Code**:
   ```swift
   Text(NSLocalizedString("record_list_title", comment: ""))
   ```

3. **Export Strings**:
   - Editor → Export for Localization

## Next Steps

- Review [Contributing Guide](Contributing-Guide)
- Read [Testing Guide](Testing-Guide)
- Explore [Architecture Overview](Architecture-Overview)
- Study [Data Models](Data-Models)

## Getting Help

If you encounter issues:

1. **Check Documentation**: Review this wiki
2. **Search Issues**: Look for similar issues on GitHub
3. **Ask Questions**: Open a discussion on GitHub
4. **Report Bugs**: Create an issue with details

## Additional Resources

- [Swift Documentation](https://swift.org/documentation/)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [Xcode Documentation](https://developer.apple.com/documentation/xcode)
