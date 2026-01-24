# Suspicious Behavior Flagging System - Setup Checklist

## ✅ Implementation Complete

All code has been implemented. Here's what you need to do:

## 1. Add New Swift Files to Xcode Project

You need to add these 3 new files to your Xcode project:

### Files to Add:
1. **`Restaurant Demo/DeviceFingerprint.swift`**
2. **`Restaurant Demo/AdminSuspiciousFlagsViewModel.swift`**
3. **`Restaurant Demo/AdminSuspiciousFlagsView.swift`**

### How to Add:
1. Open `Restaurant Demo.xcodeproj` in Xcode
2. In Project Navigator, right-click the **"Restaurant Demo"** folder (blue icon)
3. Select **"Add Files to 'Restaurant Demo'..."**
4. Select all 3 files listed above
5. Make sure:
   - ✅ **"Copy items if needed"** is checked (if files aren't already in folder)
   - ✅ **"Create groups"** is checked
   - ✅ **Target: "Restaurant Demo"** is checked
6. Click **"Add"**

## 2. Deploy Firestore Security Rules

The Firestore rules have been updated in `firestore.rules`. Deploy them:

```bash
firebase deploy --only firestore:rules
```

Or use Firebase Console:
1. Go to [Firebase Console](https://console.firebase.google.com/project/dumplinghouseapp/firestore/rules)
2. Copy the rules from `firestore.rules`
3. Paste and click **"Publish"**

## 3. Deploy Backend Changes

The backend server has been updated. Deploy it:

```bash
cd backend-deploy
# Follow your normal deployment process
# (e.g., git push, Render auto-deploy, etc.)
```

**Important:** Make sure the backend server restarts to load the new code.

## 4. Test the System

### Test Device Fingerprinting:
1. Submit a receipt from the app
2. Check backend logs - should see device fingerprint being recorded
3. Create a second account from the same device
4. Check admin panel - should see a "device_reuse" flag

### Test Receipt Detection:
1. Submit 4+ receipts within 24 hours
2. Check admin panel - should see a "receipt_velocity" flag

### Test Referral Detection:
1. Accept a referral code
2. Quickly reach 50 points (within 1 hour)
3. Check admin panel - should see a "referral_abuse" flag

### Test Admin UI:
1. As an admin, go to "More" tab
2. You should see "Suspicious Activity" menu item
3. Tap it to see the flags list
4. Tap a flag to see details and take action

## 5. Verify Backend Endpoints

Test these endpoints (as admin):

```bash
# List flags
curl -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  https://your-backend-url.com/admin/suspicious-flags

# Get user risk score
curl -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  https://your-backend-url.com/admin/user-risk-score/USER_ID
```

## 6. Monitor for Issues

After deployment, monitor:

1. **Backend Logs:**
   - Look for errors related to `SuspiciousBehaviorService`
   - Check for device fingerprint recording errors
   - Verify flags are being created

2. **Firestore Collections:**
   - Check `suspiciousFlags` collection - should see flags appearing
   - Check `userRiskScores` collection - should see scores being calculated
   - Check `deviceFingerprints` collection - should see fingerprints being stored

3. **iOS App:**
   - Build and run - should compile without errors
   - Admin menu should show "Suspicious Activity"
   - Flags list should load and display

## 7. Known Issues / Notes

### Device Fingerprint Unused Import
- ✅ **FIXED:** Removed unused `CryptoKit` import from `DeviceFingerprint.swift`

### Evidence Display
- Evidence is displayed as JSON string in the detail view
- This is intentional for now - can be enhanced later with better parsing

### Risk Score Calculation
- Risk scores are calculated automatically when flags are created
- Scores update when flags are reviewed
- Watch status is set automatically based on score thresholds

## 8. Optional Enhancements

Consider adding later:
- Badge count on "Suspicious Activity" menu item (showing pending flags)
- Push notifications for admins when critical flags are created
- Export flags to CSV for analysis
- More detailed evidence parsing in the detail view

## Summary

**What's Done:**
- ✅ Backend detection service implemented
- ✅ Admin API endpoints created
- ✅ Receipt detection integrated
- ✅ Referral detection integrated
- ✅ Device fingerprinting implemented
- ✅ Admin UI views created
- ✅ Firestore rules updated
- ✅ Risk scoring implemented

**What You Need to Do:**
1. Add 3 Swift files to Xcode project
2. Deploy Firestore rules
3. Deploy backend changes
4. Test the system
5. Monitor for issues

Everything should work once the files are added to Xcode and the backend/rules are deployed!
