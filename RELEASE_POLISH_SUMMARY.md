# Release Polish - Summary & Action Items

## ✅ Code Changes Completed

All code changes have been implemented and are ready for testing:

1. **Full Combo Coffee Support** ✅
   - Added Coffee to drink category selection UI
   - Added Coffee tier mapping (`tier_drinks_coffee_450`)
   - Updated code comments to include Coffee

2. **Backend Server Sync** ✅
   - Added `/app-version` endpoint to root `server.js` (matches `backend-deploy/server.js`)
   - Both server files now have promotional notification filtering

3. **Stability Improvements** ✅
   - Replaced `fatalError` in `Config.orderOnlineURL` with safe fallback
   - Replaced `fatalError` in `EnterCodeHostingController.init(coder:)` with graceful nil return
   - Added explicit 401/403 error handling in `RewardRedemptionService`

4. **QA Test Matrix** ✅
   - Created `RELEASE_TEST_MATRIX.md` with comprehensive manual test checklist

## ⚠️ Manual Actions Required Before Release

### 1. Deploy Backend Changes

**If you use root `server.js` (not `backend-deploy/server.js`):**
- The `/app-version` endpoint has been added to root `server.js`
- Deploy this file to your backend hosting (Render/Railway/Heroku)
- Verify: `GET https://your-backend-url/app-version` returns JSON

**If you use `backend-deploy/server.js`:**
- No changes needed - endpoint already exists
- Just ensure it's deployed

### 2. Deploy Firebase (Critical)

Run this command to deploy rules, indexes, and functions:

```bash
firebase deploy
```

This deploys:
- **Firestore rules** - Includes `promotionalNotificationsEnabled` field permission
- **Firestore indexes** - Required for receipt duplicate checks
- **Storage rules** - File upload limits and access controls
- **Functions** - Referral triggers and menu sync guards

**Why critical:** Without deploying Firestore rules, users cannot update their promotional notification preferences (compliance issue).

### 3. Set Environment Variables (Backend)

On your backend hosting platform (Render/Railway/etc.), set:

**Required:**
- `MINIMUM_APP_VERSION=1.0.0` (or your current app version)

**Optional (recommended):**
- `APP_UPDATE_MESSAGE="A new version is available with important updates. Please update to continue."`
- `CURRENT_APP_STORE_VERSION=1.0.0` (your App Store version)
- `FORCE_APP_UPDATE=true` (defaults to true if not set)

**After setting:** Restart your backend server.

### 4. Verify Firestore Tier Configuration

Ensure the Coffee tier has items configured in Firestore:

- Collection: `rewardTierItems`
- Document ID: `tier_drinks_coffee_450`
- Should contain an `eligibleItems` array with coffee drink items

**How to verify:**
1. Open Firebase Console → Firestore
2. Navigate to `rewardTierItems` collection
3. Check if `tier_drinks_coffee_450` document exists
4. Verify it has `eligibleItems` array with coffee items

### 5. Test Full Combo Flow

Before release, manually test:
- [ ] Full Combo → Coffee category → select coffee item → topping → redeem
- [ ] Verify redemption succeeds and displays correctly
- [ ] Test with other drink categories (Fruit Tea, Milk Tea, Lemonade, Soda) to ensure nothing broke

### 6. Run Release Test Matrix

Follow the tests in `RELEASE_TEST_MATRIX.md`:
- Full Combo redemption (all drink types including Coffee)
- Notification compliance (opt-in/opt-out)
- Auth-protected endpoints
- Reward redemption robustness
- App version lock

## 📋 Pre-Release Checklist

Before submitting to App Store:

- [ ] Backend deployed with `/app-version` endpoint
- [ ] Firebase deploy completed (`firebase deploy`)
- [ ] Environment variables set on backend (`MINIMUM_APP_VERSION`, etc.)
- [ ] Firestore tier `tier_drinks_coffee_450` has items configured
- [ ] Full Combo Coffee flow tested manually
- [ ] All tests in `RELEASE_TEST_MATRIX.md` completed
- [ ] Notification compliance tested (promotional vs transactional)
- [ ] App version lock tested (forced update flow)

## 🔍 Verification Steps

**Backend `/app-version` endpoint:**
```bash
curl https://your-backend-url/app-version
```
Expected response:
```json
{
  "minimumRequiredVersion": "1.0.0",
  "currentAppStoreVersion": null,
  "updateMessage": null,
  "forceUpdate": true
}
```

**Firebase rules deployed:**
- Check Firebase Console → Firestore → Rules
- Verify `promotionalNotificationsEnabled` is in allowed user fields

**Coffee tier exists:**
- Check Firebase Console → Firestore → `rewardTierItems` → `tier_drinks_coffee_450`
- Verify `eligibleItems` array has coffee items

## 📝 Notes

- All code changes are backward compatible
- No breaking changes introduced
- Safe fallbacks added for crash-prone code paths
- Error handling improved for better user experience

## 🚨 If Something Breaks

**Coffee not showing in Full Combo:**
- Verify `tier_drinks_coffee_450` exists in Firestore with items
- Check backend logs for tier fetch errors
- Verify tier ID mapping is correct (should be `tier_drinks_coffee_450`)

**App version lock not working:**
- Verify `/app-version` endpoint is deployed and accessible
- Check environment variable `MINIMUM_APP_VERSION` is set
- Verify app is calling correct backend URL

**Notification preferences not saving:**
- Verify Firestore rules are deployed (`firebase deploy --only firestore:rules`)
- Check user document has `promotionalNotificationsEnabled` field permission
