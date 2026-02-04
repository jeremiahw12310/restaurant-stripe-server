# App Store Review — Comprehensive Audit Report

**App:** Dumpling House (Restaurant Demo)  
**Bundle ID:** (from project)  
**Display Name:** Dumpling House  
**iOS Deployment Target:** 17.0  
**Marketing Version:** 1.0  
**App Store ID:** 6758052536 (Config)  

**Review Date:** January 29, 2025  
**Reviewer:** Simulated Apple App Review audit  

---

## Executive Summary

| Verdict | **APPROVE** (with minor recommendations) |
|--------|-----------------------------------------|
| Guideline 4.0 (Design) | ✅ No critical issues |
| Guideline 5.0 (Privacy) | ✅ Compliant |
| Guideline 2.0 (Safety) | ✅ Compliant |
| Guideline 3.0 (Business) | ✅ No IAP; external ordering for physical goods OK |
| Guideline 1.0 (Legal) | ✅ Terms, Privacy, Account Deletion present |

The app is suitable for public release. A small fix was applied (UpdateRequiredView fallback URL). The following sections document the full audit.

---

## 1. Account-Based App Requirements (Guideline 5.1.1)

### 1.1 Sign-in options
- **Finding:** App uses **phone-only** authentication (Firebase Phone Auth). No Google, Facebook, or Apple Sign-In.
- **Guideline 4.8:** Sign in with Apple is required only when using *third-party or social login* (e.g. Facebook, Google, Twitter, etc.). Phone-only auth does **not** trigger this requirement.
- **Status:** ✅ **Compliant.**

### 1.2 Account deletion (Guideline 5.1.1(v))
- **Finding:** Account deletion is supported and reachable from **More → Danger Zone → Delete Account**.
- **Flow:** User must re-authenticate via SMS before deletion. Clear disclosure of what is permanently deleted vs. anonymized (receipt/reward history).
- **Banned users:** Shown `BannedAccountDeletionView` (deletion-only); same re-auth and disclosure.
- **Status:** ✅ **Compliant.**

---

## 2. Privacy & Data Use

### 2.1 Privacy Policy & Terms of Service
- **Finding:** Privacy Policy and Terms are linked in:
  - **Onboarding:** Before sign-up, with explicit “I accept” plus links to both. User cannot send verification code without accepting.
  - **More → Support & Legal:** Privacy Policy and Terms of Service buttons.
- **URLs:** Served from backend (`/privacy.html`, `/terms.html`). Opened in-app via `SFSafariViewController` (SimplifiedSafariView).
- **Status:** ✅ **Compliant.**

### 2.2 Privacy Nutrition Label (PrivacyInfo.xcprivacy)
- **Collected data declared:** Name, Phone Number, User ID, Device ID, Photos/Videos, Purchase History.
- **Purpose:** App Functionality only. **Tracking:** false.
- **APIs:** UserDefaults (CA92.1), File Timestamp (C617.1), Disk Space (E174.1).
- **Status:** ✅ **Compliant.**

### 2.3 Permissions & usage descriptions
- **Camera:** “This app uses the camera to scan receipts and earn loyalty points.” ✅  
- **Microphone:** “We need access to your microphone to capture your voice for chat.” ✅  
- **Photo Library:** “This app accesses your photo library to select profile pictures and receipt images.” (Read only; app does not save images to Photos.) ✅  
- **Speech Recognition:** “We use speech recognition so you can talk to Dumpling Hero hands-free…” ✅  

- **Location:** Not used at runtime. Only static `CLLocationCoordinate2D` for “Open in Maps” / Google Maps. No `CLLocationManager` or location permission. ✅  

### 2.4 Pre-permission flows
- **Camera:** `CameraPrePermissionView` explains use, benefits, and offers “Not now.” ✅  
- **Notifications:** `NotificationPrePermissionView` explains rewards/referrals/account updates, separate **promotional opt-in** toggle, “Not now.” ✅  

### 2.5 Notification compliance
- **In-app controls:** `NotificationSettingsView` — system permission status, **promotional toggle**, link to iOS Settings, “View Notifications.”
- **Promotional opt-in:** Pre-permission view and settings use `promotionalNotificationsEnabled`; backend filters promotional sends accordingly.
- **Status:** ✅ **Compliant** with Apple’s expectations for optional promotional notifications.

---

## 3. Safety & Content

### 3.1 User-generated content / moderation
- **Finding:** Receipt scanning (photos), chatbot (Dumpling Hero), and any community-style features.
- **LLM moderation:** Documented policy and schema (`LLM_MODERATION_PROMPT.md`); violation/borderline handling and audit logging.
- **Status:** ✅ **Reasonable** moderation approach for UGC.

### 3.2 Banned users
- Banned users are blocked from main app and presented only with `BannedAccountDeletionView` (delete account or contact support). No access to core functionality.
- **Status:** ✅ **Appropriate.**

---

## 4. Business & Payments

### 4.1 In-App Purchase
- **Finding:** No StoreKit / IAP. No in-app purchase of digital goods or services.
- **Status:** ✅ **N/A.**

### 4.2 External links — “Order Online”
- **Finding:** “Order Online” links point to external web (e.g. backend `/order`, `dumplinghousetn.kwickmenu.com`). Used for **physical goods** (food ordering).
- **Guideline 3.1.1:** Apps may use payment methods other than IAP for **real-world** goods and services.
- **Status:** ✅ **Compliant.**

### 4.3 Promo carousel links
- **Finding:** Promo slides can open URLs (`destinationType == .url`) via `UIApplication.shared.open`. URLs are admin-defined (Firestore).
- **Recommendation:** Ensure only whitelisted, appropriate URLs (e.g. order, menu, official pages) are configured. No guideline violation found in code.

---

## 5. Legal & Support

### 5.1 Terms of Service
- **Finding:** ToS exists (`public/terms.html`, `backend-deploy/public/terms.html`), covers rewards, receipt rules, 48-hour scan window, etc. Linked and required acceptance at sign-up.
- **Status:** ✅ **Compliant.**

### 5.2 Contact support
- **Finding:** More → “Contact Support” uses `Config.supportEmail` (`support@bytequack.com`) with `mailto:`. Graceful handling if not set.
- **Status:** ✅ **Compliant.**

---

## 6. Technical & Stability

### 6.1 Debug vs release
- **Finding:** `DebugLogger` only logs inside `#if DEBUG`. No production logging of user data.
- **Status:** ✅ **Appropriate.**

### 6.2 Crashes / cache corruption
- **Finding:** Cache emergency cleanup on launch; NSTaggedDate-style crashes addressed via validation and cache clearing (see `NSTAGGEDDATE_CRASH_FIX`). Memory warning handling clears caches.
- **Status:** ✅ **Reasonable** mitigations.

### 6.3 Version / update required
- **Finding:** `AppVersionService` checks minimum version; `UpdateRequiredView` prompts update and opens App Store.
- **URL:** Uses `Config.appStoreID` → `https://apps.apple.com/app/id{id}`. Fallback uses App Store search by bundle ID (no `app/id` + bundle ID).
- **Change made:** UpdateRequiredView fallback was incorrectly using `app/id\(bundleId)`. Simplified to always use `AppVersionService.getAppStoreURL()` (direct link or search). ✅  

---

## 7. Other Guideline Checks

### 7.1 Referrals
- **Finding:** Referral codes and share URLs. No incentive to rate/review the app in exchange for referral benefits.
- **Status:** ✅ **Compliant.**

### 7.2 Review prompts
- **Finding:** No `SKStoreReviewController` / `requestReview` usage.
- **Status:** ✅ **OK.**

### 7.3 Push notifications
- **Finding:** Used for auth (Firebase Phone), FCM, and app features. Proper delegation, token handling, and optional promotional path.
- **Status:** ✅ **Compliant.**

### 7.4 Associated domains / Universal Links
- **Finding:** `applinks:dumplinghouseapp.com`, `applinks:dumplinghouseapp.web.app` for referral URLs. Handled in `AppDelegate`.
- **Status:** ✅ **Consistent** with implementation.

### 7.5 App Check / security
- **Finding:** Firebase App Check with debug (dev) vs production (Attest/DeviceCheck) providers. Production builds use Attest when available.
- **Status:** ✅ **Reasonable** for backend protection.

### 7.6 Forced light mode
- **Finding:** Root `LaunchView` uses `.preferredColorScheme(.light)`.
- **Note:** Design choice. Not a rejection reason; consider documenting if you ever add accessibility-specific review.

---

## 8. Recommendations Before or Soon After Release

1. **Promo slide URLs:** Continue to restrict admin-configured URLs to whitelisted, safe destinations (order, menu, official sites).
2. **Accessibility:** Ensure important flows (auth, account deletion, receipt scan) work well with VoiceOver and Dynamic Type; document if needed for future updates.
3. **Monitoring:** Keep an eye on receipt-scan and moderation error rates post-launch.

---

## 9. Checklist Summary

| Requirement | Status |
|------------|--------|
| Account deletion (5.1.1(v)) | ✅ |
| Privacy Policy & Terms | ✅ |
| Privacy manifest & labels | ✅ |
| Permission strings & pre-prompts | ✅ |
| Notification opt-in/opt-out | ✅ |
| No prohibited IAP use | ✅ |
| External ordering (physical goods) | ✅ |
| Support contact | ✅ |
| Sign in with Apple (when required) | N/A (phone-only) |
| Debug-only logging | ✅ |
| Update-required flow & App Store URL | ✅ (fix applied) |

---

## 10. Final Verdict

**APPROVE for public release.**

The app meets the reviewed App Store Guidelines. The only code change made was correcting the UpdateRequiredView App Store fallback to use `AppVersionService.getAppStoreURL()` only. Address the recommendations above as part of normal iteration and monitoring.
