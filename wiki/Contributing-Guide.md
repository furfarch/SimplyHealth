# Contributing Guide

Thank you for your interest in contributing to Purus Health! This guide will help you get started with contributing to the project.

## Code of Conduct

### Be Respectful

- Treat all contributors with respect
- Welcome newcomers and help them get started
- Be patient with questions and discussions
- Accept constructive criticism gracefully

### Be Collaborative

- Share knowledge and help others learn
- Review code thoughtfully and constructively
- Discuss ideas before implementing major changes
- Credit others for their contributions

## Getting Started

### 1. Set Up Development Environment

Follow the [Development Setup](Development-Setup) guide to configure your environment.

### 2. Understand the Architecture

Read the [Architecture Overview](Architecture-Overview) to understand the app's structure.

### 3. Find an Issue

Look for issues labeled:
- `good first issue` - Great for beginners
- `help wanted` - Community help requested
- `bug` - Bug fixes needed
- `enhancement` - New features or improvements

### 4. Discuss Before Major Changes

For significant changes:
1. Open an issue to discuss the change
2. Wait for maintainer feedback
3. Proceed once approach is agreed upon

## Development Workflow

### 1. Fork the Repository

Click "Fork" on GitHub to create your copy.

### 2. Clone Your Fork

```bash
git clone https://github.com/YOUR-USERNAME/Purus.Health.git
cd Purus.Health
```

### 3. Add Upstream Remote

```bash
git remote add upstream https://github.com/furfarch/Purus.Health.git
```

### 4. Create Feature Branch

```bash
git checkout -b feature/your-feature-name
```

**Branch Naming Conventions**:
- `feature/feature-name` - New features
- `bugfix/bug-description` - Bug fixes
- `docs/documentation-update` - Documentation
- `refactor/refactoring-description` - Code refactoring

### 5. Make Changes

Follow the [Coding Standards](#coding-standards) below.

### 6. Test Your Changes

```bash
# Run tests
⌘U in Xcode

# Or command line
xcodebuild test -scheme PurusHealth -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 7. Commit Changes

```bash
git add .
git commit -m "Brief description of changes"
```

See [Commit Message Guidelines](#commit-message-guidelines) below.

### 8. Push to Your Fork

```bash
git push origin feature/your-feature-name
```

### 9. Create Pull Request

1. Go to your fork on GitHub
2. Click "Pull Request"
3. Select your feature branch
4. Fill in PR template
5. Submit PR

## Coding Standards

### Swift Style Guide

Follow Apple's [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

### Naming Conventions

**Variables and Functions**:
```swift
// ✅ Good - camelCase
let personalGivenName: String
func syncIfNeeded(record: MedicalRecord)

// ❌ Bad
let PersonalGivenName: String
let personal_given_name: String
```

**Types**:
```swift
// ✅ Good - PascalCase
class MedicalRecord
struct BloodEntry
enum RecordLocation

// ❌ Bad
class medicalRecord
struct blood_entry
```

**Constants**:
```swift
// ✅ Good
static let containerID = "iCloud.com.purus.health"
let maxRetries = 3

// ❌ Bad
static let CONTAINER_ID = "iCloud.com.purus.health"
```

### Code Organization

**File Structure**:
```swift
// 1. Imports
import SwiftUI
import SwiftData

// 2. Type definition
struct MyView: View {
    // 3. Properties
    @State private var isShowing = false
    let record: MedicalRecord
    
    // 4. Body
    var body: some View {
        // View code
    }
    
    // 5. Helper methods
    private func doSomething() {
        // Logic
    }
}

// 6. Preview
#Preview {
    // Preview code
}
```

### SwiftUI Best Practices

**Use Environment**:
```swift
// ✅ Good
@Environment(\.modelContext) private var modelContext

// ❌ Bad - Don't pass context explicitly unless needed
MyView(context: modelContext)
```

**Binding Pattern**:
```swift
// ✅ Good - Custom binding for optional dates
DatePicker("Date",
    selection: Binding(
        get: { record.date ?? Date() },
        set: { record.date = $0 }
    ))

// ❌ Bad - Force unwrapping
DatePicker("Date", selection: $record.date!)
```

**State Management**:
```swift
// ✅ Good - Appropriate property wrappers
@State private var showSheet = false
@Bindable var record: MedicalRecord
@Environment(\.modelContext) private var modelContext

// ❌ Bad - Wrong property wrapper usage
@State var record: MedicalRecord  // Should be @Bindable
```

### SwiftData Best Practices

**Model Definition**:
```swift
// ✅ Good - Provide defaults
@Model
final class MedicalRecord {
    var name: String = ""
    var date: Date?  // Optional when appropriate
    
    init(name: String = "") {
        self.name = name
    }
}

// ❌ Bad - No defaults
@Model
final class MedicalRecord {
    var name: String
    var date: Date
}
```

**Relationships**:
```swift
// ✅ Good - Cascade delete
@Relationship(deleteRule: .cascade, inverse: \BloodEntry.record)
var blood: [BloodEntry]

// ❌ Bad - No delete rule specified
@Relationship
var blood: [BloodEntry]
```

### Error Handling

**Do-Catch Blocks**:
```swift
// ✅ Good - Specific error handling
do {
    try context.save()
} catch {
    ShareDebugStore.shared.appendLog("Save failed: \(error)")
    // Handle gracefully
}

// ❌ Bad - Silent failures
try? context.save()
```

**Async Error Handling**:
```swift
// ✅ Good
func syncRecord() async throws {
    do {
        try await uploadToCloudKit()
    } catch {
        ShareDebugStore.shared.appendLog("Sync failed: \(error)")
        throw error
    }
}

// ❌ Bad - Swallowing errors
func syncRecord() async {
    try? await uploadToCloudKit()
}
```

### Comments

**When to Comment**:
```swift
// ✅ Good - Complex logic explanation
/// Migrates legacy default-zone records to custom share zone.
/// Required because CloudKit shares cannot exist in default zone.
private func migrateRootRecordToShareZoneIfNeeded(record: MedicalRecord) async throws {
    // Implementation
}

// ✅ Good - Non-obvious behavior
// CloudKit records are fetched with 1 second delay to allow server-side URL population
try await Task.sleep(nanoseconds: shareURLPopulationDelay)

// ❌ Bad - Obvious comment
// Set name to "John"
record.name = "John"
```

**Documentation Comments**:
```swift
/// Synchronizes a medical record to CloudKit if cloud sync is enabled.
///
/// - Parameter record: The medical record to sync
/// - Throws: CloudKit errors if sync fails
/// - Note: Records with `isCloudEnabled = false` are skipped
func syncIfNeeded(record: MedicalRecord) async throws {
    // Implementation
}
```

## Testing Requirements

### All Changes Must Include Tests

**New Features**:
```swift
@Test
func testNewFeature() async throws {
    // Test your new feature
}
```

**Bug Fixes**:
```swift
@Test
func testBugFix() async throws {
    // Test that demonstrates the bug is fixed
}
```

### Test Coverage

Maintain test coverage:
- **Models**: 90%+ coverage
- **Services**: 80%+ coverage
- **Views**: 50%+ coverage (where feasible)

### Testing Checklist

- [ ] Unit tests for new/modified code
- [ ] Tests pass locally (⌘U)
- [ ] Edge cases covered
- [ ] Error cases tested
- [ ] No failing tests introduced

## Commit Message Guidelines

### Format

```
<type>: <subject>

<body>

<footer>
```

### Type

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples

**Good Commit Messages**:
```
feat: Add weight tracking entry model

Implements WeightEntry model with date, weight, unit, and comment fields.
Includes SwiftData model definition and CloudKit serialization support.

Closes #42
```

```
fix: Resolve crash when deleting shared record

The app crashed when attempting to delete a record that was shared
with other users. Fixed by checking sharing status before deletion.

Fixes #38
```

```
docs: Update CloudKit integration guide

Added section on handling push notifications and improved
error handling examples.
```

**Bad Commit Messages**:
```
update code
fix bug
changes
WIP
```

### Commit Size

- Keep commits focused and atomic
- One logical change per commit
- Easier to review and revert if needed

## Pull Request Guidelines

### PR Title

Use same format as commit messages:
```
feat: Add PDF export functionality
fix: Resolve CloudKit sync race condition
docs: Update testing guide with async examples
```

### PR Description

Include:

1. **What**: What changes were made
2. **Why**: Why these changes are needed
3. **How**: How the changes work
4. **Testing**: How you tested the changes
5. **Screenshots**: For UI changes
6. **Related Issues**: Link to related issues

**Template**:
```markdown
## Description
Brief description of changes.

## Motivation
Why are these changes needed?

## Changes
- List of changes made
- With details

## Testing
- [ ] Unit tests added/updated
- [ ] Manual testing performed
- [ ] Edge cases covered

## Screenshots (if applicable)
[Add screenshots for UI changes]

## Related Issues
Closes #42
```

### PR Checklist

Before submitting:

- [ ] Code follows style guidelines
- [ ] Tests added/updated
- [ ] All tests pass
- [ ] Documentation updated
- [ ] No merge conflicts
- [ ] Commit messages are clear
- [ ] PR description is complete

## Code Review Process

### Submitting Code for Review

1. Create PR with complete description
2. Ensure CI checks pass
3. Request review from maintainers
4. Address review feedback
5. Update PR as needed

### Reviewing Code

When reviewing PRs:

**Be Constructive**:
```
✅ "Consider using a guard statement here for early return"
❌ "This is wrong"
```

**Ask Questions**:
```
✅ "Why did you choose this approach over X?"
❌ "This doesn't make sense"
```

**Suggest Alternatives**:
```
✅ "Have you considered using map instead of a for loop?"
```

**Approve or Request Changes**:
- Approve if code looks good
- Request changes if issues need addressing
- Comment if you have questions

### Addressing Feedback

1. Read all feedback carefully
2. Ask for clarification if needed
3. Make requested changes
4. Respond to comments
5. Push updated code
6. Request re-review

## Documentation

### Updating Documentation

When changing functionality:

1. Update relevant wiki pages
2. Update inline code comments
3. Update README if applicable
4. Add examples for new features

### Writing Documentation

- Be clear and concise
- Include code examples
- Explain "why" not just "what"
- Use proper markdown formatting

## Special Considerations

### CloudKit Changes

When modifying CloudKit integration:

1. **Test Locally First**: Use Development environment
2. **Update Schema**: Modify `cloudkit-development.cdkb`
3. **Test Migration**: Ensure existing data migrates correctly
4. **Document Changes**: Update CloudKit Integration wiki page

### Data Model Changes

When changing SwiftData models:

1. **Consider Migration**: How will existing data migrate?
2. **Test Thoroughly**: Test with existing data
3. **Update Tests**: Add tests for new/changed fields
4. **CloudKit Sync**: Update serialization/deserialization

### Breaking Changes

Avoid breaking changes if possible. If necessary:

1. Discuss in issue first
2. Document migration path
3. Update version number
4. Add migration code
5. Update documentation

## Security

### Reporting Security Issues

**Do NOT** open public issues for security vulnerabilities.

Instead:
1. Email security concerns to maintainers
2. Provide detailed description
3. Wait for acknowledgment
4. Coordinate disclosure timing

### Security Best Practices

- Never commit secrets or API keys
- Use environment variables for sensitive data
- Follow iOS security guidelines
- Validate all user input
- Use secure network communication

## Getting Help

### Resources

- **Documentation**: Read the wiki
- **Issues**: Search existing issues
- **Discussions**: Ask questions in Discussions
- **Code**: Review existing code for examples

### Community

- Be patient and respectful
- Help others when you can
- Share knowledge and learnings
- Participate in discussions

## Recognition

Contributors are recognized:
- In release notes
- In CONTRIBUTORS file (if exists)
- Through GitHub contributions graph

Thank you for contributing to Purus Health! 🎉

## Next Steps

- Review [Development Setup](Development-Setup)
- Read [Testing Guide](Testing-Guide)
- Study [Architecture Overview](Architecture-Overview)
- Start with a `good first issue`
