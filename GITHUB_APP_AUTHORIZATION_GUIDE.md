# 🔐 GitHub App Authorization Guide

## What You're Seeing

When adding Firebase SDK dependencies in Xcode, you'll see a prompt asking you to authorize access to Google's GitHub repositories. This is **normal and safe**.

## Why This Happens

- Firebase SDKs are hosted on Google's GitHub organization
- Xcode needs permission to download these dependencies
- GitHub requires explicit authorization for organization repositories

## What To Do

### Option 1: If You Own the GitHub Account/Organization

1. **Click "Install" or "Authorize"**
   - This will take you to GitHub's authorization page

2. **Select the Repositories**
   - ✅ `google/GoogleDataTransport`
   - ✅ `google/promises`
   - ✅ `google/GoogleUtilities`
   - ✅ `google/gtm-session-fetcher`

3. **Click "Install" or "Authorize"**
   - Grant the requested permissions

4. **Return to Xcode**
   - The dependencies should now download automatically

### Option 2: If You're Not the Owner

1. **Click "Request"**
   - This sends a request to the organization owner

2. **Wait for Approval**
   - The owner will receive an email notification
   - They need to approve the request

3. **Once Approved**
   - Return to Xcode
   - The dependencies will download

## Alternative: Skip This Step

If you're having trouble with the GitHub authorization, you can:

### Use CocoaPods Instead

1. **Install CocoaPods** (if not already installed):
   ```bash
   sudo gem install cocoapods
   ```

2. **Create a Podfile** in your project root:
   ```ruby
   platform :ios, '15.0'
   use_frameworks!

   target 'Restaurant Demo' do
     pod 'Firebase/Firestore'
     pod 'Firebase/Auth'
     # Add other Firebase pods as needed
   end
   ```

3. **Install dependencies**:
   ```bash
   pod install
   ```

4. **Open the workspace** (not the project):
   ```bash
   open "Restaurant Demo.xcworkspace"
   ```

### Or Use Firebase's Official Distribution

Firebase also provides pre-built frameworks, but Swift Package Manager is the recommended approach.

## Is This Safe?

✅ **Yes, this is safe!**
- You're only granting read access to public repositories
- These are official Google/Firebase repositories
- No write access is granted
- This is a standard part of using Firebase SDK

## Troubleshooting

### "I Don't See 'google' in the List"

This can happen for several reasons. Try these solutions:

#### Solution 1: Make Sure You're Logged Into GitHub
1. **Open GitHub in your browser**: Go to [github.com](https://github.com)
2. **Sign in** with your GitHub account
3. **Return to Xcode** and try again

#### Solution 2: Search for "google"
- Look for a **search box** on the authorization page
- Type "google" to search for the organization
- It might be listed differently or you might need to search

#### Solution 3: Check What Page You're On
- You should be on a page that says "Install GitHub App" or "Authorize GitHub App"
- Look for a list of organizations or a search box
- If you see your personal account, click on it to see organizations

#### Solution 4: Try Direct Authorization URL
1. **Copy this URL** and open it in your browser:
   ```
   https://github.com/settings/installations
   ```
2. **Look for pending installations** or click "Configure" on any existing apps
3. **Find the Xcode/GitHub App** and authorize it

#### Solution 5: Skip This Entirely (Easiest Option)
If you're having trouble, **you can skip the GitHub authorization** and add Firebase directly:

1. **In Xcode**, go to: **File → Add Package Dependencies...**
2. **Enter this URL**:
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```
3. **Click "Add Package"**
4. **Select the Firebase products** you need (Firestore, Auth, etc.)
5. **Click "Add Package"**

This bypasses the GitHub App authorization entirely!

### "Installation Failed"
- Check your internet connection
- Make sure you're logged into GitHub in your browser
- Try again after a few minutes

### "Request Pending"
- Contact your organization owner
- They need to approve the request in GitHub settings

### Still Having Issues?
- **Use the direct package URL method** (Solution 5 above) - this is the easiest!
- Try using CocoaPods instead (see above)
- Or contact Firebase support

## What Repositories Are These?

- **GoogleDataTransport**: Internal Firebase dependency
- **promises**: Google's Promise library
- **GoogleUtilities**: Shared utility functions
- **gtm-session-fetcher**: HTTP session management

All of these are **required** for Firebase to work properly in your iOS app.
