# Multiple Rewards Fix – Double-Check & Your Checklist

## What Was Verified

- **ViewModel**: `activeRedemptions` array, no `.limit(to: 1)`, listener processes all docs, refunds all expired sequentially, `handleActiveRedemptionExpired` removes one and refunds.
- **UI**: Home, UnifiedRewardsScreen, RewardsView use `ForEach(activeRedemptions)` and `sheet(item:)` for tap-to-detail; each countdown uses `handleActiveRedemptionExpired` on expire.
- **Redemption flow**: RewardsComponents and GiftedRewardCard append to `activeRedemptions` and `successDataByCode` on claim.
- **Points sync**: Refunds update `rewardsVM.userPoints`. Backend updates `users/{uid}.points`. `UserViewModel` listens to that doc, so Home points update when the listener fires (may lag slightly).
- **Backend**: `/refund-expired-reward` updates user points and marks `pointsRefunded`; app sets `isExpired` on the reward doc after refund when the **listener** detects expiry.

---

## What You Should Do

### 1. Manual testing (required)

- **Multiple countdowns**: Claim 2–3 rewards. Confirm each has its own countdown on Home, Rewards tab, and unified rewards screen.
- **Tap to open**: Tap each countdown and confirm the correct reward (code, title) opens in the detail sheet.
- **Multiple expirations**: Claim 2+ rewards, let all expire (or use 15‑minute window). Confirm:
  - Each triggers a refund.
  - Points return to the correct total (same as before any claims).
  - You see refund notification(s); if several expire close together, the last one may overwrite the message.

### 2. Firestore composite index (if you see an error)

The active-redemptions query uses:

- `userId` (==)
- `isUsed` (==)
- `isExpired` (==)
- `orderBy("redeemedAt", "desc")`

There is **no** `redeemedRewards` index in `firestore.indexes.json`. If you get a Firestore error asking for a composite index:

1. Use the link in the error to create it in the Firebase Console, or  
2. Add an index in `firestore.indexes.json` for `redeemedRewards` with those fields and run `firebase deploy --only firestore:indexes`.

If the app runs without that error, you can skip this.

### 3. Optional improvements (later)

- **Refund message for multiple**: When several rewards expire, we show one notification per refund. You could later aggregate (e.g. “1,200 pts refunded – 3 rewards expired”).
- **Mark expired from app when timer fires**: Today we only set `isExpired` when the **listener** sees an expired doc. The countdown timer triggers refund but doesn’t touch Firestore. The listener eventually marks it. If you want to avoid that extra listener path, you could also update `isExpired` from the app when the timer fires (you’d need the reward doc ref, e.g. from `rewardId`).

---

## No Backend or Config Changes Required

- Backend already supports per-reward refunds and updates user points.
- No env or config updates needed for this fix.

---

## If Something Breaks

- **“Points not fully restored”**: Ensure each expired reward is actually refunded (check backend logs for refund calls and `pointsRefunded`). Verify `UserViewModel`’s Firestore listener is running so `userVM.points` updates after refunds.
- **“Only one countdown”**: Confirm the Firestore query has no `.limit(to: 1)` and that `activeRedemptions` is used in the UI (not `activeRedemption`).
- **Firestore `updateData`**: We use `try? await doc.reference.updateData(["isExpired": true])`. If you hit a runtime error there, switch to the callback-based `updateData(_:completion:)` and call it from within the same `Task` (e.g. using `withCheckedContinuation`).
