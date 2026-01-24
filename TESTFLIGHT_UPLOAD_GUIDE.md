# 📱 TestFlight Upload Guide

Complete step-by-step guide to upload your iOS app to TestFlight for beta testing.

## ✅ Prerequisites

Before you start, make sure you have:

1. **Apple Developer Account** ($99/year)
   - Sign up at [developer.apple.com](https://developer.apple.com)
   - Enroll in the Apple Developer Program

2. **App Store Connect Access**
   - Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   - Sign in with your Apple Developer account

3. **Xcode Installed**
   - Latest version from Mac App Store or [developer.apple.com](https://developer.apple.com/xcode/)

---

## 🚀 Step-by-Step Process

### Step 1: Set Up Your App in App Store Connect

1. **Log in to App Store Connect**
   - Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   - Click **"My Apps"**

2. **Create a New App** (if you haven't already)
   - Click the **"+"** button → **"New App"**
   - Fill in:
     - **Platform:** iOS
     - **Name:** Your app name (e.g., "Restaurant Demo")
     - **Primary Language:** English (or your preferred language)
     - **Bundle ID:** Select your bundle ID (e.g., `bytequack.dumplinghouse`)
     - **SKU:** Create your own unique identifier (see SKU details below)
   - Click **"Create"**

   **About SKU (Stock Keeping Unit):**
   - **You create this yourself** - it's not something you get from Apple
   - It's an internal identifier for your own tracking (users never see it)
   - Must be unique within your Apple Developer account
   - Can be any combination of letters, numbers, hyphens, and underscores
   - Examples: `restaurant-demo-001`, `dumplinghouse-v1`, `myapp-ios-2024`
   - Tip: Use something descriptive like `appname-platform-version` format

3. **Note Your Bundle ID**
   - You'll need this to match it in Xcode

---

### Step 2: Configure Your Xcode Project

1. **Open Your Project in Xcode**
   ```bash
   cd "/Users/jeremiahwiseman/Desktop/Restaurant Demo"
   open "Restaurant Demo.xcodeproj"  # or .xcworkspace if using CocoaPods
   ```

2. **Select Your Project Target**
   - Click on your project name in the left sidebar
   - Select the **"Restaurant Demo"** target
   - Go to the **"Signing & Capabilities"** tab

3. **Configure Signing**
   - ✅ Check **"Automatically manage signing"**
   - Select your **Team** (your Apple Developer account)
   - Verify the **Bundle Identifier** matches App Store Connect (e.g., `bytequack.dumplinghouse`)

4. **Set Version and Build Number**
   - Go to the **"General"** tab
   - **Version:** e.g., `1.0.0` (this is the user-facing version)
   - **Build:** e.g., `1` (increment this for each upload)

---

### Step 3: Build an Archive

1. **Select "Any iOS Device" or "Generic iOS Device"**
   - In the device selector at the top of Xcode, choose **"Any iOS Device"** (not a simulator)

2. **Create Archive**
   - Go to **Product** → **Archive**
   - Wait for the build to complete (this may take a few minutes)

3. **Organizer Window Opens**
   - After archiving, the Organizer window should open automatically
   - If not: **Window** → **Organizer** → Select your archive

---

### Step 4: Upload to App Store Connect

1. **In the Organizer Window**
   - Select your latest archive
   - Click **"Distribute App"**

2. **Choose Distribution Method**
   - Select **"App Store Connect"**
   - Click **"Next"**

3. **Choose Distribution Options**
   - Select **"Upload"** (not "Export")
   - Click **"Next"**

4. **Select Distribution Options**
   - ✅ **"Upload your app's symbols"** (recommended for crash reports)
   - ✅ **"Manage Version and Build Number"** (if you want Xcode to handle it)
   - Click **"Next"**

5. **Review and Upload**
   - Review the summary
   - Click **"Upload"**
   - Wait for the upload to complete (this may take 5-15 minutes)

---

### Step 5: Process Build in App Store Connect

1. **Wait for Processing**
   - Go back to App Store Connect
   - Navigate to your app → **"TestFlight"** tab
   - You'll see your build appear with status **"Processing"**
   - This usually takes 10-30 minutes

2. **Build Becomes Available**
   - Once processing completes, status changes to **"Ready to Submit"** or **"Ready to Test"**

---

### Step 6: Set Up TestFlight Testing

1. **Add Test Information** (First time only)
   - In TestFlight tab, fill in:
     - **What to Test:** Brief description of what testers should focus on
     - **Feedback Email:** Your email for tester feedback

2. **Add Internal Testers** (Optional)
   - Go to **"Internal Testing"** section
   - Click **"+"** to add testers
   - Add email addresses of team members (up to 100)
   - They'll receive an email invitation

3. **Add External Testers** (Optional)
   - Go to **"External Testing"** section
   - Click **"+"** to create a new group
   - Add your build to the group
   - Add testers (up to 10,000 for external testing)
   - **Note:** External testing requires App Review (usually 24-48 hours)

---

### Step 7: Testers Install Your App

1. **Testers Receive Email**
   - They'll get an email invitation to test your app

2. **Testers Install TestFlight**
   - Download **TestFlight** app from App Store (if they don't have it)

3. **Testers Accept Invitation**
   - Open the email on their iPhone
   - Tap **"Start Testing"** or **"View in TestFlight"**
   - Or open TestFlight app and tap **"Accept"**

4. **Testers Install Your App**
   - In TestFlight, they'll see your app
   - Tap **"Install"** to download and install

---

## 🔧 Troubleshooting

### "No accounts with App Store Connect access"
- Make sure you're signed in to Xcode with your Apple ID
- Go to **Xcode** → **Preferences** → **Accounts**
- Click **"+"** to add your Apple ID
- Make sure your account has the **"App Manager"** or **"Admin"** role

### "Bundle ID doesn't match"
- Check that your Bundle ID in Xcode matches the one in App Store Connect
- Go to **Signing & Capabilities** tab to verify

### "Invalid Bundle"
- Make sure you selected **"Any iOS Device"** before archiving (not a simulator)
- Clean build folder: **Product** → **Clean Build Folder** (Shift+Cmd+K)
- Try archiving again

### "Upload Failed"
- Check your internet connection
- Make sure you have enough disk space
- Try uploading again (sometimes it's a temporary issue)

### Build Stuck in "Processing"
- This is normal, can take up to 30 minutes
- If it's been over an hour, check App Store Connect status page
- Sometimes you need to wait or try uploading a new build

### "Missing Compliance"
- After first upload, you may need to answer export compliance questions
- Go to App Store Connect → Your App → **App Information**
- Answer the encryption compliance questions

---

## 📋 Quick Checklist

Before uploading, make sure:

- [ ] Apple Developer account is active
- [ ] App is created in App Store Connect
- [ ] Bundle ID matches in Xcode and App Store Connect
- [ ] Signing is configured correctly in Xcode
- [ ] Version and Build numbers are set
- [ ] Selected "Any iOS Device" before archiving
- [ ] Archive was created successfully
- [ ] Upload completed without errors

---

## 🎯 Tips

1. **Increment Build Number** for each upload (even if version stays the same)

2. **Test Locally First** - Make sure your app works on a real device before uploading

3. **Use Internal Testing** for quick iterations (no review needed)

4. **External Testing** requires App Review but allows up to 10,000 testers

5. **TestFlight Builds Expire** after 90 days - upload new builds regularly

6. **Version Numbers** follow semantic versioning: `MAJOR.MINOR.PATCH` (e.g., 1.0.0)

---

## 📚 Additional Resources

- [Apple's TestFlight Guide](https://developer.apple.com/testflight/)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [Xcode Help](https://help.apple.com/xcode/)

---

## 🎉 Success!

Once your build is processed and testers are added, they can install and test your app through TestFlight. You'll be able to see crash reports, tester feedback, and usage analytics in App Store Connect!
