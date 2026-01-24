# 🔐 Xcode Cloud Code Signing Fix

## The Problem

Xcode Cloud builds are failing during the archive step, typically due to code signing configuration issues.

## Common Causes

1. **Missing Certificates** - Xcode Cloud needs access to your signing certificates
2. **Provisioning Profile Issues** - Automatic signing might not be configured correctly
3. **Missing Entitlements Files** - Required entitlements files might not be committed
4. **Bundle ID Mismatch** - Bundle ID doesn't match App Store Connect

## Solution: Configure Xcode Cloud Signing

### Step 1: Set Up Signing Certificates in Xcode Cloud

1. **Open Xcode**
2. **Go to Xcode Cloud Settings**
   - Xcode → Settings (or Preferences) → Accounts
   - Select your Apple ID
   - Click "Manage Certificates"
   - Make sure you have certificates installed locally

3. **Configure Xcode Cloud Workflow**
   - In your Xcode project, go to the **Xcode Cloud** tab (or Cloud icon)
   - Select your workflow
   - Go to **"Signing & Capabilities"** section
   - Make sure **"Automatically manage signing"** is enabled
   - Select your **Development Team** (TZ498BT5J7)

### Step 2: Verify Project Settings

1. **Open Your Project in Xcode**
   ```bash
   cd "/Users/jeremiahwiseman/Desktop/Restaurant Demo"
   open "Restaurant Demo.xcodeproj"
   ```

2. **Check Signing Configuration**
   - Select your project in the navigator
   - Select the **"Restaurant Demo"** target
   - Go to **"Signing & Capabilities"** tab
   - Verify:
     - ✅ **"Automatically manage signing"** is checked
     - ✅ **Team** is set to your team (TZ498BT5J7)
     - ✅ **Bundle Identifier** is `bytequack.dumplinghouse`

3. **Check Build Settings**
   - Go to **"Build Settings"** tab
   - Search for "Code Signing"
   - Verify:
     - `CODE_SIGN_STYLE` = `Automatic`
     - `DEVELOPMENT_TEAM` = `TZ498BT5J7`
     - `PRODUCT_BUNDLE_IDENTIFIER` = `bytequack.dumplinghouse`

### Step 3: Commit Entitlements Files

Make sure your entitlements files are committed to git:

```bash
cd "/Users/jeremiahwiseman/Desktop/Restaurant Demo"
git add "Restaurant Demo/Restaurant DemoRelease.entitlements"
git add "Restaurant Demo/Restaurant Demo.entitlements"
git commit -m "Add entitlements files for Xcode Cloud"
git push origin main
```

### Step 4: Verify App Store Connect Setup

1. **Go to App Store Connect**
   - Visit [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   - Make sure your app is created
   - Verify Bundle ID matches: `bytequack.dumplinghouse`

2. **Check Certificates & Profiles**
   - Go to **Certificates, Identifiers & Profiles**
   - Verify your App ID exists
   - Check that provisioning profiles are active

## Alternative: Manual Code Signing Setup

If automatic signing isn't working, you can configure manual signing:

### Option 1: Use Xcode Cloud's Managed Signing

1. **In Xcode Cloud Workflow Settings**
   - Enable **"Use Xcode Cloud managed signing"**
   - This lets Xcode Cloud handle certificates automatically

### Option 2: Export and Import Certificates

1. **Export Your Certificates** (from your local Mac)
   - Keychain Access → My Certificates
   - Export your Apple Development certificate
   - Export your Apple Distribution certificate

2. **Import to Xcode Cloud** (if supported)
   - Or configure Xcode Cloud to use your Apple ID's certificates

## Quick Fix: Update Xcode Cloud Workflow

1. **In Xcode**, go to your Xcode Cloud workflow
2. **Edit the workflow**
3. **Under "Archive" action**, check:
   - ✅ **"Manage Version and Build Number"** is enabled
   - ✅ **"Upload to App Store Connect"** is enabled
   - ✅ **"Automatically manage signing"** is checked

4. **Save and trigger a new build**

## Troubleshooting Specific Errors

### "No signing certificate found"
- Make sure your Apple Developer account is active
- Verify your team ID (TZ498BT5J7) is correct
- Check that certificates are installed in your Apple Developer account

### "Provisioning profile not found"
- Enable "Automatically manage signing" in Xcode
- Make sure your Bundle ID matches App Store Connect
- Verify your team has the right permissions

### "Entitlements file not found"
- Commit your `.entitlements` files to git
- Make sure they're in the correct location
- Verify the paths in Build Settings match

### "Bundle ID mismatch"
- Check Bundle ID in Xcode matches App Store Connect
- Verify it's `bytequack.dumplinghouse` everywhere

## Verify Your Setup

Run these checks:

```bash
# Check if entitlements files exist
ls -la "Restaurant Demo/"*.entitlements

# Check git status
git status

# Verify project file is committed
git ls-files | grep xcodeproj
```

## Next Steps

After fixing signing:

1. **Commit any changes** to your project
2. **Push to GitHub**
3. **Trigger a new Xcode Cloud build**
4. **Monitor the build logs** for any remaining issues

## Still Having Issues?

If you're still seeing errors:

1. **Check the full error log** in Xcode Cloud
   - Look for specific error messages
   - Check which step is failing

2. **Try building locally first**
   - Product → Archive in Xcode
   - If it works locally, the issue is with Xcode Cloud configuration

3. **Contact Apple Support**
   - Xcode Cloud issues can sometimes require Apple's help
   - Provide the full error log
