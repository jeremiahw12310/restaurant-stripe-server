# App Version Lock - Setup Checklist ✅

## ⚠️ ACTION REQUIRED: You Need to Do These Steps

### 1. Add New Swift Files to Xcode Project ⚠️ **REQUIRED**

You need to add these 2 new files to your Xcode project:

**Files to Add:**
1. `Restaurant Demo/AppVersionService.swift`
2. `Restaurant Demo/UpdateRequiredView.swift`

**How to Add:**
1. Open `Restaurant Demo.xcodeproj` in Xcode
2. In Project Navigator (left sidebar), right-click the **"Restaurant Demo"** folder (blue icon)
3. Select **"Add Files to 'Restaurant Demo'..."**
4. Navigate to and select both files:
   - `AppVersionService.swift`
   - `UpdateRequiredView.swift`
5. Make sure these options are checked:
   - ✅ **"Copy items if needed"** (if files aren't already in the folder)
   - ✅ **"Create groups"**
   - ✅ **Target: "Restaurant Demo"** is checked
6. Click **"Add"**

**Verify:**
- Build the project (Cmd+B) - should build without errors
- Both files should appear in Project Navigator under "Restaurant Demo"

---

### 2. Configure Backend Environment Variables ⚠️ **REQUIRED**

Set these environment variables on your backend server (Render, Railway, etc.):

**Required:**
```bash
MINIMUM_APP_VERSION=1.0.0
```
*(Set this to your current app version or higher to test)*

**Optional (but recommended):**
```bash
# Custom message shown to users
APP_UPDATE_MESSAGE="A new version is available with important updates. Please update to continue."

# Current version on App Store (for display)
CURRENT_APP_STORE_VERSION=1.0.0

# Force update flag (defaults to true if not set)
FORCE_APP_UPDATE=true
```

**Where to Set:**
- **Render:** Dashboard → Your Service → Environment → Add Environment Variable
- **Railway:** Project → Variables → Add Variable
- **Heroku:** Settings → Config Vars → Reveal Config Vars → Add

**Important:** After setting environment variables, restart your backend server.

---

### 3. Configure App Store ID (Optional but Recommended) ⚠️ **RECOMMENDED**

To ensure the "Update Now" button opens the correct App Store page:

**Find Your App Store ID:**
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app
3. Look at the URL: `https://apps.apple.com/app/id[YOUR_APP_STORE_ID]`
4. Or check App Information → General Information → Apple ID

**Update the Code:**
1. Open `Restaurant Demo/AppVersionService.swift`
2. Find the `getAppStoreURL()` function (around line 107)
3. Replace the search fallback with your App Store ID:

```swift
func getAppStoreURL() -> URL? {
    // Replace with your actual App Store ID
    let appStoreID = "1234567890" // YOUR APP STORE ID HERE
    
    return URL(string: "https://apps.apple.com/app/id\(appStoreID)")
}
```

**OR** add it to `Config.swift` (better approach):

Add to `Config.swift`:
```swift
extension Config {
    static let appStoreID: String? = "1234567890" // Your App Store ID
}
```

Then update `AppVersionService.swift`:
```swift
func getAppStoreURL() -> URL? {
    if let appStoreID = Config.appStoreID {
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }
    // Fallback to search
    if let bundleId = Bundle.main.bundleIdentifier {
        let encodedBundleId = bundleId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleId
        return URL(string: "https://apps.apple.com/search?term=\(encodedBundleId)")
    }
    return nil
}
```

---

### 4. Test the Implementation ⚠️ **REQUIRED BEFORE DEPLOYING**

**Test 1: Version Check Works**
1. Set `MINIMUM_APP_VERSION=999.0.0` (higher than your current version)
2. Deploy backend changes
3. Launch the app
4. **Expected:** You should see the "Update Required" screen
5. **Verify:** Current and required versions are displayed correctly

**Test 2: Update Button Works**
1. On the "Update Required" screen, tap "Update Now"
2. **Expected:** App Store should open (or search for your app)
3. **If it doesn't work:** Configure App Store ID (Step 3 above)

**Test 3: Version Check Passes**
1. Set `MINIMUM_APP_VERSION=1.0.0` (lower than or equal to your current version)
2. Deploy backend changes
3. Launch the app
4. **Expected:** App should launch normally, no update screen

**Test 4: Graceful Degradation**
1. Temporarily disable `/app-version` endpoint (or set wrong URL)
2. Launch the app
3. **Expected:** App should continue normally (check logs for warning)

---

### 5. Deploy Backend Changes ⚠️ **REQUIRED**

The backend endpoint has been added to `backend-deploy/server.js`. Deploy it:

**If using Git:**
```bash
cd backend-deploy
git add server.js
git commit -m "Add app version check endpoint"
git push
```

**If using Render/Railway:**
- Changes should auto-deploy if connected to Git
- Or manually trigger a deploy

**Verify Deployment:**
1. Visit: `https://restaurant-stripe-server-1.onrender.com/app-version`
2. **Expected:** JSON response with version info:
   ```json
   {
     "minimumRequiredVersion": "1.0.0",
     "currentAppStoreVersion": null,
     "updateMessage": null,
     "forceUpdate": true
   }
   ```

---

## ✅ Verification Checklist

Before considering this complete, verify:

- [ ] Both Swift files added to Xcode project
- [ ] Project builds without errors (Cmd+B)
- [ ] Backend environment variable `MINIMUM_APP_VERSION` is set
- [ ] Backend endpoint `/app-version` returns JSON response
- [ ] App Store ID configured (or at least tested that search works)
- [ ] Tested with version higher than current → shows update screen ✅
- [ ] Tested with version lower/equal to current → app launches normally ✅
- [ ] "Update Now" button opens App Store ✅
- [ ] Tested graceful degradation (endpoint down) → app continues ✅

---

## 🐛 Troubleshooting

### Build Errors

**Error: "Cannot find 'Config' in scope"**
- Make sure `AppVersionService.swift` is in the same target as `Config.swift`
- Clean build folder: Product → Clean Build Folder (Cmd+Shift+K)
- Rebuild: Product → Build (Cmd+B)

**Error: "Cannot find 'DebugLogger' in scope"**
- Same as above - verify file is in correct target
- Clean and rebuild

### Update Screen Doesn't Appear

- Check backend logs - is `/app-version` endpoint being called?
- Verify `MINIMUM_APP_VERSION` is set correctly
- Check app version in Info.plist matches what you expect
- Look for version check logs in Xcode console

### "Update Now" Button Doesn't Work

- Configure App Store ID (Step 3)
- Test the URL manually in Safari: `https://apps.apple.com/app/id[YOUR_ID]`
- Verify app is published on App Store

### App Locked Even After Updating

- Check `CFBundleShortVersionString` in Info.plist matches App Store version
- Verify version comparison logic (should be semantic versioning)
- Check backend `MINIMUM_APP_VERSION` value

---

## 📝 Current App Version

To find your current app version:
1. Open Xcode → Select project → General tab
2. Look at **Version** field (e.g., "1.0.0")
3. Or check `Restaurant-Demo-Info.plist` → `CFBundleShortVersionString`

**Current version in project:** Check `MARKETING_VERSION` in `project.pbxproj` (line 530 shows `1.0`)

---

## 🚀 Ready to Use

Once all steps are complete:
1. Set `MINIMUM_APP_VERSION` to your current version (or higher)
2. Deploy backend
3. Deploy app update
4. When you want to force an update, increase `MINIMUM_APP_VERSION` on backend
5. Users will be prompted to update on next app launch

---

## 📚 Additional Documentation

See `APP_VERSION_LOCK_GUIDE.md` for detailed usage instructions and examples.
