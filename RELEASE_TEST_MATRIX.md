# Release Test Matrix

This checklist is a focused, manual QA matrix for release readiness. It is scoped to
critical flows, compliance, and scale-risk areas.

## Preconditions
- Production backend is deployed (Render) and reachable.
- Firebase deploy completed (rules, indexes, functions).
- Test user accounts available:
  - Regular user (not admin)
  - Admin user (isAdmin == true)
- Push notifications configured (FCM/APNs).
- App version lock env vars set (`MINIMUM_APP_VERSION`, optional `APP_UPDATE_MESSAGE`).

## Full Combo Redemption
1) Full Combo: Single dumpling + Coffee
   - Steps: Redeem Full Combo → select single dumpling → cooking method → Coffee category → select coffee item → topping → redeem.
   - Expected: Redemption succeeds; success display shows dumpling + coffee + topping.

2) Full Combo: Half-and-half + Coffee
   - Steps: Redeem Full Combo → half-and-half selection → choose 2 flavors + method → Coffee category → select coffee item → topping → redeem.
   - Expected: Redemption succeeds; success display shows "Half and Half: X + Y (method) + Coffee (+ topping)".

3) Full Combo: Lemonade vs Soda path
   - Steps: Redeem Full Combo → Lemonade or Soda category → select item → drink type selection → topping → redeem.
   - Expected: Drink type is persisted and shown in success display.

4) Full Combo: Empty tier handling
   - Steps: Temporarily remove items from a drink tier in Firestore.
   - Expected: Empty state appears with a clear message; no crash.

## Notifications Compliance
1) User opt-in toggle
   - Steps: More → Notifications → toggle promotional on/off.
   - Expected: Preference persists after app restart.

2) Admin promotional vs transactional
   - Steps: Send promotional notification and transactional notification from admin UI.
   - Expected: Promotional sends only to opted-in users; transactional sends to all.

3) Audit trail
   - Steps: Check notification history/admin logs.
   - Expected: `isPromotional` recorded; excluded count present for promo sends.

## Auth-Protected Endpoints
1) Signed-out behavior
   - Steps: Sign out → use Chat/Combo/Receipt scan.
   - Expected: App shows sign-in required messaging; no generic error screen.

2) Signed-in behavior
   - Steps: Sign in → use Chat/Combo/Receipt scan.
   - Expected: Requests succeed with Bearer token.

## Reward Redemption Robustness
1) Double-tap protection
   - Steps: Rapidly tap redeem button multiple times.
   - Expected: Only one redemption occurs; no duplicate points deduction.

2) Redemption list sync
   - Steps: Redeem a reward → verify it appears in active redemptions list.
   - Expected: New redemption shows once; no duplicates.

3) Network failure
   - Steps: Disable network during redemption.
   - Expected: Graceful error message; app remains usable.

## App Version Lock
1) Forced update
   - Steps: Set `MINIMUM_APP_VERSION` higher than current build → launch app.
   - Expected: Update required screen appears; button opens App Store URL.

2) Graceful degrade
   - Steps: Disable `/app-version` endpoint temporarily.
   - Expected: App launches normally; no lockout.

## Smoke Checks
1) Menu load and caching
   - Steps: Launch app → menu loads → pull-to-refresh.
   - Expected: Menu displays; refresh works; no crash.

2) Image load/caching
   - Steps: Navigate across menus and reward images.
   - Expected: No missing images; load times acceptable.

