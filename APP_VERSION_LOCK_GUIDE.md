# App Version Lock Implementation Guide

This guide explains how to use the app version lock feature that forces users to update the app when a new version is required.

## Overview

The app version lock system:
1. Checks the minimum required version from the backend on app launch
2. Compares it with the current app version
3. Shows an update screen if the app version is too old
4. Prevents users from using the app until they update

## How It Works

### 1. Backend Endpoint

The backend provides a `/app-version` endpoint that returns:
- `minimumRequiredVersion`: The minimum app version required (e.g., "1.1.0")
- `currentAppStoreVersion`: (Optional) Current version available on App Store
- `updateMessage`: (Optional) Custom message to display to users
- `forceUpdate`: Whether to force the update (defaults to true)

### 2. App-Side Check

On app launch (`LaunchView`):
- Calls `AppVersionService.shared.checkVersionRequirement()`
- Compares current version with minimum required version
- Shows `UpdateRequiredView` if update is required
- Allows app to continue if version check fails (graceful degradation)

### 3. Version Comparison

Versions are compared using semantic versioning (major.minor.patch):
- "1.0.0" < "1.1.0" → Update required
- "1.1.0" = "1.1.0" → No update required
- "1.2.0" > "1.1.0" → No update required

## Configuration

### Backend Configuration (Environment Variables)

Set these environment variables on your backend server (Render, Railway, etc.):

```bash
# Minimum required app version (required)
MINIMUM_APP_VERSION=1.1.0

# Current App Store version (optional, for display)
CURRENT_APP_STORE_VERSION=1.2.0

# Custom update message (optional)
APP_UPDATE_MESSAGE="New features and security improvements are available. Please update to continue."

# Force update flag (optional, defaults to true)
# Set to "false" to disable forced updates
FORCE_APP_UPDATE=true
```

### App Store URL Configuration

To ensure the "Update Now" button opens the correct App Store page:

1. **Find your App Store ID:**
   - Go to App Store Connect
   - Find your app
   - The App Store ID is in the URL: `https://apps.apple.com/app/id[YOUR_APP_STORE_ID]`

2. **Update AppVersionService.swift:**
   - Option A: Add App Store ID to `Config.swift` and use it in `getAppStoreURL()`
   - Option B: Hardcode the App Store ID in `AppVersionService.swift`:
     ```swift
     let appStoreID = "1234567890" // Your App Store ID
     return URL(string: "https://apps.apple.com/app/id\(appStoreID)")
     ```

## Usage Examples

### Example 1: Force Update for Critical Security Fix

**Backend:**
```bash
MINIMUM_APP_VERSION=1.1.0
APP_UPDATE_MESSAGE="A critical security update is available. Please update immediately."
FORCE_APP_UPDATE=true
```

**Result:** Users on version 1.0.0 or lower will see the update screen and cannot use the app until they update.

### Example 2: Optional Update (Informational Only)

**Backend:**
```bash
MINIMUM_APP_VERSION=1.0.0
APP_UPDATE_MESSAGE="Version 1.2.0 is now available with new features!"
FORCE_APP_UPDATE=false
```

**Result:** Users can continue using the app, but will see update notifications (if you implement that separately).

### Example 3: Gradual Rollout

**Backend:**
```bash
# Week 1: Allow all versions
MINIMUM_APP_VERSION=1.0.0

# Week 2: Require 1.1.0+
MINIMUM_APP_VERSION=1.1.0

# Week 3: Require 1.2.0+
MINIMUM_APP_VERSION=1.2.0
```

## Testing

### Test Update Required Screen

1. Set `MINIMUM_APP_VERSION` to a version higher than your current app version
2. Launch the app
3. You should see the `UpdateRequiredView` screen
4. Tap "Update Now" to verify it opens the App Store

### Test Version Check Failure (Graceful Degradation)

1. Temporarily disable the `/app-version` endpoint or set a wrong URL
2. Launch the app
3. The app should continue normally (check logs for warning message)

### Test Version Comparison

The version comparison logic handles:
- `"1.0.0"` vs `"1.1.0"` → Update required ✅
- `"1.1.0"` vs `"1.1.0"` → No update ✅
- `"1.2.0"` vs `"1.1.0"` → No update ✅
- `"2.0.0"` vs `"1.9.9"` → No update ✅

## Important Notes

1. **Graceful Degradation:** If the version check fails (network error, endpoint down, etc.), the app will continue normally. This prevents network issues from locking users out.

2. **Version Format:** Use semantic versioning (major.minor.patch). Examples: "1.0.0", "1.1.0", "2.0.0"

3. **App Store ID:** Make sure to configure the App Store ID so the "Update Now" button works correctly.

4. **Testing:** Always test with a version higher than your current version before deploying to production.

5. **Rollback:** If you need to rollback, simply set `MINIMUM_APP_VERSION` back to a lower version or set `FORCE_APP_UPDATE=false`.

## Files Modified

- `Restaurant Demo/AppVersionService.swift` - Version checking service
- `Restaurant Demo/UpdateRequiredView.swift` - Update required UI
- `Restaurant Demo/LaunchView.swift` - Integrated version check on launch
- `backend-deploy/server.js` - Added `/app-version` endpoint

## Troubleshooting

### Update screen doesn't appear
- Check that `MINIMUM_APP_VERSION` is set correctly
- Verify the version format matches semantic versioning
- Check app logs for version check messages

### "Update Now" button doesn't work
- Verify App Store ID is configured correctly
- Check that the app is published on the App Store
- Test the App Store URL manually in a browser

### App is locked even after updating
- Check that the app version in Info.plist matches what's on the App Store
- Verify `CFBundleShortVersionString` is set correctly
- Check backend logs to see what version is being compared
