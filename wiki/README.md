# Wiki Documentation

This directory contains comprehensive documentation for the Purus Health application. The wiki covers architecture, data models, views, services, CloudKit integration, testing, and contribution guidelines.

## Wiki Pages

1. **[Home](Home.md)** - Wiki home page with overview and navigation
2. **[Architecture Overview](Architecture-Overview.md)** - High-level architecture and design patterns
3. **[Data Models](Data-Models.md)** - SwiftData models and relationships
4. **[Views and UI](Views-and-UI.md)** - SwiftUI views and UI patterns
5. **[Services](Services.md)** - Business logic and service layer
6. **[CloudKit Integration](CloudKit-Integration.md)** - Cloud sync and sharing implementation
7. **[Testing Guide](Testing-Guide.md)** - Testing patterns and guidelines
8. **[Development Setup](Development-Setup.md)** - Setting up the development environment
9. **[Contributing Guide](Contributing-Guide.md)** - How to contribute to the project

## Publishing to GitHub Wiki

GitHub Wiki is a separate git repository. To publish these pages to the GitHub Wiki:

### Method 1: Manual Copy-Paste

1. Go to the [GitHub Wiki](https://github.com/furfarch/Purus.Health/wiki)
2. Click "New Page" for each wiki page
3. Set the page title (e.g., "Home", "Architecture Overview")
4. Copy the content from the corresponding `.md` file
5. Click "Save Page"

### Method 2: Clone and Push to Wiki Repository

The GitHub Wiki has its own git repository:

```bash
# Clone the wiki repository
git clone https://github.com/furfarch/Purus.Health.wiki.git

# Copy wiki files
cp wiki/*.md Purus.Health.wiki/

# Commit and push
cd Purus.Health.wiki
git add .
git commit -m "Add comprehensive wiki documentation"
git push origin master
```

### Method 3: Automated Script

Use this script to sync wiki files:

```bash
#!/bin/bash

# Navigate to repository root
cd "$(dirname "$0")/.."

# Clone wiki if not exists
if [ ! -d "../Purus.Health.wiki" ]; then
    git clone https://github.com/furfarch/Purus.Health.wiki.git ../Purus.Health.wiki
fi

# Copy wiki files
cp wiki/*.md ../Purus.Health.wiki/

# Commit and push
cd ../Purus.Health.wiki
git add .
git commit -m "Update wiki documentation"
git push origin master

echo "Wiki updated successfully!"
```

Save as `scripts/sync-wiki.sh` and run:

```bash
chmod +x scripts/sync-wiki.sh
./scripts/sync-wiki.sh
```

## Wiki File Naming

GitHub Wiki uses the following naming conventions:

- **Home.md** → Home page (automatically recognized)
- **Architecture-Overview.md** → "Architecture Overview" page
- **Data-Models.md** → "Data Models" page
- Spaces in page titles are represented by hyphens in file names

## Wiki Links

Internal wiki links use the format `[Link Text](Page-Name)`:

```markdown
[Architecture Overview](Architecture-Overview)
[Data Models](Data-Models)
```

GitHub automatically converts these to proper wiki links.

## Updating the Wiki

When updating wiki documentation:

1. **Edit locally**: Make changes to `.md` files in the `wiki/` directory
2. **Commit changes**: Commit to the main repository
3. **Sync to wiki**: Use one of the methods above to publish to GitHub Wiki
4. **Keep in sync**: Ensure both repositories stay synchronized

## Wiki Structure

The wiki follows this structure:

```
Getting Started
├── Development Setup
└── Building and Running

Architecture
├── Architecture Overview
├── Data Models
├── Views and UI
└── Services

Advanced Topics
├── CloudKit Integration
├── Testing Guide
└── Contributing Guide
```

## Maintenance

### Keeping Documentation Up to Date

- Update wiki when making significant code changes
- Review documentation during PR reviews
- Ensure code examples match current implementation
- Update screenshots when UI changes

### Documentation Review Checklist

- [ ] Accurate code examples
- [ ] Current architecture diagrams
- [ ] Valid links (internal and external)
- [ ] Consistent formatting
- [ ] Clear explanations
- [ ] No outdated information

## Contributing to Documentation

To improve documentation:

1. Edit the appropriate `.md` file in `wiki/` directory
2. Follow markdown best practices
3. Include code examples where helpful
4. Test internal links
5. Submit PR with documentation changes
6. Sync to GitHub Wiki after merge

## Markdown Style Guide

### Headers

```markdown
# Main Title (H1)
## Section (H2)
### Subsection (H3)
```

### Code Blocks

````markdown
```swift
// Swift code
func example() {
    print("Hello")
}
```
````

### Lists

```markdown
- Unordered item
- Another item

1. Ordered item
2. Another item
```

### Links

```markdown
[Internal Wiki Link](Page-Name)
[External Link](https://example.com)
[Anchor Link](#section-name)
```

### Tables

```markdown
| Column 1 | Column 2 |
|----------|----------|
| Value 1  | Value 2  |
```

### Admonitions

Use bold for emphasis:

```markdown
**Important**: Critical information
**Note**: Additional context
**Warning**: Caution required
```

## Screenshots and Images

For images in the wiki:

1. **Upload to repository**: Add to `wiki/images/` directory
2. **Reference in markdown**: `![Alt text](images/screenshot.png)`
3. **Alternative**: Use GitHub issue attachments for images

## Wiki Benefits

Having wiki documentation in the repository:

- ✅ Version controlled
- ✅ PR reviews for documentation
- ✅ CI/CD integration possible
- ✅ Local editing and preview
- ✅ Offline access
- ✅ Searchable in repository

## Additional Resources

- [GitHub Wiki Documentation](https://docs.github.com/en/communities/documenting-your-project-with-wikis)
- [Markdown Guide](https://www.markdownguide.org/)
- [Swift Documentation](https://swift.org/documentation/)

## Questions?

If you have questions about the wiki:

1. Check existing documentation
2. Open a GitHub Issue
3. Start a Discussion
4. Contact maintainers

---

**Last Updated**: 2024-02-17
**Maintainers**: Purus Health Team
