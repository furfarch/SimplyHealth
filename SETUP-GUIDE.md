# Purus Health - Setup Guide

Complete setup guide for renaming from Purus Health to PurusHealth, including App Store Connect and CloudKit configuration.

---

## ✅ Completed: Code Refactoring

The following have already been completed and pushed to GitHub:

- ✅ Renamed project: `Purus Health.xcodeproj` → `PurusHealth.xcodeproj`
- ✅ Renamed folders: `Purus Health/` → `PurusHealth/`
- ✅ Renamed test folders
- ✅ Updated all Xcode project references
- ✅ Updated CloudKit container ID: `icloud.com.purus.health`
- ✅ Updated bundle identifier: `com.purus.health`
- ✅ Updated README and documentation

---

## 📋 Next Steps Required

### 1. GitHub Repository Rename

**Time Required:** 2 minutes

#### Steps:
1. Go to https://github.com/furfarch/Purus Health
2. Click **Settings** tab
3. Scroll down to **"Repository name"** section
4. Change `Purus Health` to `PurusHealth`
5. Click **"Rename"** button

GitHub automatically:
- ✅ Redirects old URLs to new URL
- ✅ Updates clone URLs
- ✅ Preserves issues, PRs, stars

#### Update Local Git Remote:
```bash
cd /path/to/project
git remote set-url origin https://github.com/furfarch/PurusHealth.git
git remote -v  # Verify the change
```

---

### 2. CloudKit Container Setup

**Time Required:** 10-15 minutes

#### A. Create CloudKit Container

1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Select **Identifiers** in left sidebar
4. Click **CloudKit Containers** from dropdown
5. Click the **+** button
6. Enter identifier: `icloud.com.purus.health`
7. Enter description: "Purus Health - Medical Records App"
8. Click **Continue**, then **Register**

#### B. Verify Container in Xcode

1. Open `PurusHealth.xcodeproj` in Xcode
2. Select the project in navigator
3. Select the **PurusHealth** target
4. Go to **Signing & Capabilities** tab
5. In **iCloud** section:
   - ✅ CloudKit should already be checked
   - Under **Containers**, click **+**
   - Select `icloud.com.purus.health`
   - Or if not listed yet, click **Specify custom container**
   - Enter: `icloud.com.purus.health`

#### C. Configure CloudKit Dashboard (Optional but Recommended)

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
2. Select `icloud.com.purus.health` container
3. Go to **Schema** section
4. The app will create schemas automatically, but you can verify:
   - Record Type: `MedicalRecord`
   - Custom Zone: `PurusHealthShareZone`

---

### 3. App Store Connect Configuration

**Time Required:** 15-20 minutes

#### A. Create New App (or Update Existing)

**If creating a NEW app:**

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **My Apps**
3. Click **+** → **New App**
4. Fill in details:
   - **Platform:** iOS (can add macOS later)
   - **Name:** Purus Health
   - **Primary Language:** English (US)
   - **Bundle ID:** Create new → `com.purus.health`
   - **SKU:** `com.purus.health`
   - **User Access:** Full Access

**If updating EXISTING Purus Health app:**

⚠️ **Important:** You CANNOT change the bundle identifier of an existing app.

**Your options:**
1. **Create a NEW app** with new bundle ID (recommended for major rebrand)
2. **Keep existing app** and just update the display name to "Purus Health"

**To update display name only:**
1. Go to existing app in App Store Connect
2. Go to **App Information**
3. Change **Name** to "Purus Health"
4. Update **Subtitle** if needed
5. Update **Description** to reference "Simply Series"

#### B. Configure App Information

1. In your app, go to **App Information**
2. Update **Privacy Policy URL** (if you have one)
3. Update **App Category**:
   - Primary: Medical
   - Secondary: Health & Fitness (optional)
4. Update **Content Rights**:
   - Check if you have necessary rights

#### C. Add App Version

1. Go to **App Store** tab
2. Click on version (e.g., "1.0 Prepare for Submission")
3. Update metadata:
   - **Name:** Purus Health
   - **Subtitle:** Medical records for humans and pets
   - **Description:** Include "Part of the Simply Series" branding
   - **Keywords:** health, medical, records, tracking, simply
   - **Support URL:** Your support website
   - **Marketing URL:** Optional

#### D. Update Screenshots and Promotional Text

Update your App Store assets to reflect Purus Health branding:
- Update app screenshots
- Update app preview videos (if any)
- Update promotional text
- Mention "Simply Series" in description

---

### 4. Xcode Project Configuration

**Time Required:** 5-10 minutes

#### A. Update Display Name

1. Open `PurusHealth.xcodeproj` in Xcode
2. Select project in navigator
3. Select **PurusHealth** target
4. Go to **Info** tab
5. Find or add key: `Bundle display name`
6. Set value to: `Purus Health`

Or edit directly in `Info.plist`:
```xml
<key>CFBundleDisplayName</key>
<string>Purus Health</string>
```

#### B. Verify Bundle Identifier

1. In **General** tab
2. Verify **Bundle Identifier:** `com.purus.health`
3. This should already be correct from our refactoring

#### C. Update App Icons (If Needed)

If your app icons still show "Purus Health" branding:
1. Design new icons with "Purus Health" or just "SH" logo
2. Replace in `Assets.xcassets/AppIcon.appiconset/`
3. Use all required sizes (1024x1024 for App Store)

---

### 5. Testing Before Release

#### A. Test Local Storage
```bash
# Clean build folder
⌘+Shift+K

# Clean derived data
⌘+Option+Shift+K

# Build and run
⌘+R
```

**Test:**
- ✅ Create a medical record
- ✅ Edit and save
- ✅ Delete record
- ✅ App restarts with data persisted
- ✅ PDF export works

#### B. Test CloudKit (After Container Setup)

**Enable cloud sync on a test record:**
1. Create a medical record
2. Toggle "Enable Cloud Sync"
3. Check Settings → iCloud Status shows "Available"
4. Wait for sync to complete
5. Check CloudKit Dashboard for record

**Test sharing:**
1. Enable sharing on a record
2. Tap "Share" button
3. Send invite to test account
4. Accept invite on another device
5. Verify record appears

#### C. Test Multi-Platform

**On macOS:**
1. Open `PurusHealth.xcodeproj`
2. Select "My Mac" destination
3. Build and run (⌘+R)
4. Verify UI renders correctly
5. Test all features work

---

### 6. Update Documentation

Update any remaining documentation:

#### A. Update .github/copilot-instructions.md

Search for any remaining "Purus Health" references and update to "PurusHealth"

#### B. Create CHANGELOG.md

Document the rebrand:

```markdown
# Changelog

## [2.0.0] - 2026-01-22
### Changed
- **BREAKING:** Rebranded from Purus Health to Purus Health
- Now part of the Simply Series family of apps
- Updated CloudKit container ID
- Updated bundle identifier
- All references updated throughout codebase
```

---

## 📊 Configuration Summary

| Item | Old Value | New Value | Status |
|------|-----------|-----------|--------|
| **Project Name** | Purus Health.xcodeproj | PurusHealth.xcodeproj | ✅ Complete |
| **Bundle ID** | com.furfarch.Purus Health | com.purus.health | ✅ Complete |
| **CloudKit Container** | iCloud.com.furfarch.Purus Health | icloud.com.purus.health | ⏳ Create |
| **Display Name** | Purus Health | Purus Health | ⏳ Update |
| **GitHub Repo** | furfarch/Purus Health | furfarch/PurusHealth | ⏳ Rename |
| **App Store** | Purus Health | Purus Health | ⏳ Update |

---

## 🚨 Important Notes

### Data Migration Warning

⚠️ **Users will NOT automatically migrate data** when changing bundle identifiers.

**If you're updating an existing app:**
- Changing bundle ID = NEW app to App Store
- Users need to export/import their data manually
- Consider providing migration instructions

**Recommended approach:**
1. Release as a NEW app ("Purus Health")
2. Keep old app ("Purus Health") available for download
3. Provide export from old app → import to new app

### CloudKit Data

⚠️ **Existing CloudKit data is in the OLD container**

**Your options:**
1. **Start fresh** - New container, users start clean (recommended for rebrand)
2. **Migrate data** - Complex, requires custom migration script
3. **Keep old container** temporarily while migrating

**Recommendation:** Start with fresh container, let users opt-in to new sync.

---

## ✅ Checklist

Use this checklist to track your progress:

### Code (Complete)
- [x] Rename Xcode project
- [x] Rename folders and files
- [x] Update bundle identifier
- [x] Update CloudKit container references
- [x] Update documentation
- [x] Commit and push to GitHub

### External Services (To Do)
- [ ] Rename GitHub repository
- [ ] Update local git remote
- [ ] Create CloudKit container in Apple Developer Portal
- [ ] Configure CloudKit in Xcode
- [ ] Create or update app in App Store Connect
- [ ] Update app metadata and screenshots
- [ ] Update bundle display name
- [ ] Update app icons (if needed)

### Testing
- [ ] Test local storage
- [ ] Test CloudKit sync
- [ ] Test sharing features
- [ ] Test on iOS
- [ ] Test on macOS
- [ ] Test PDF export
- [ ] Clean build and test

### Release
- [ ] Create changelog
- [ ] Update support documentation
- [ ] Prepare App Store submission
- [ ] Submit for review

---

## 🆘 Troubleshooting

### "CloudKit container not found"
**Solution:** Make sure container is created in Developer Portal and added in Xcode Signing & Capabilities

### "Bundle identifier already exists"
**Solution:** If updating existing app, you cannot change bundle ID. Either:
- Create new app with new bundle ID
- Or keep old bundle ID and just update display name

### "Data not syncing"
**Solution:**
1. Check iCloud account is signed in
2. Verify container ID matches in code and Developer Portal
3. Check CloudKit Dashboard for errors
4. Verify entitlements are correct

### Git remote update not working
**Solution:**
```bash
git remote remove origin
git remote add origin https://github.com/furfarch/PurusHealth.git
```

---

## 📞 Need Help?

If you encounter issues:
1. Check Xcode build logs for errors
2. Check CloudKit Dashboard for sync issues
3. Verify entitlements match Developer Portal
4. Clean build folder and derived data
5. Restart Xcode

---

**Last Updated:** 2026-01-22
**Status:** Code refactoring complete, external services pending
