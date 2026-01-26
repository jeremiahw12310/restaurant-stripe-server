# Cost Hardening – What You Need To Do

Double-check summary and action items after the cost-hardening implementation.

---

## 1. Deploy Backend (Render)

- **What:** Deploy `backend-deploy/` (Render uses `rootDir: backend-deploy`).
- **How:** Push to your repo and let Render deploy, or trigger a manual deploy.
- **Verify:** `GET https://your-render-url/` returns the health JSON. `POST /chat` without `Authorization: Bearer <token>` returns **401**.

---

## 2. Deploy Firebase (Rules, Indexes, Functions)

```bash
firebase deploy
```

This deploys:

- **Storage rules** (`storage.rules`) – folder-scoped reads, upload limits.
- **Firestore rules** (`firestore.rules`) – unchanged.
- **Firestore indexes** (`firestore.indexes.json`) – **new indexes for `receipts`** were added for duplicate-check queries. Deploy so submit-receipt doesn’t fail with “index required”.
- **Functions** (`functions/`) – referral + menu-sync guards.

---

## 3. Optional Env Vars (Render Dashboard)

You can tune rate limits and caps via environment variables. Set these in **Render → Your Service → Environment** if you want to override defaults:

| Variable | Default | Purpose |
|----------|---------|---------|
| `COMBO_DAILY_LIMIT` | 20 | Max generate-combo calls per user per day |
| `COMBO_UID_PER_MIN` | 6 | Max generate-combo per user per minute |
| `COMBO_IP_PER_MIN` | 20 | Max generate-combo per IP per minute |
| `CHAT_DAILY_LIMIT` | 60 | Max chat messages per user per day |
| `CHAT_UID_PER_MIN` | 12 | Max chat per user per minute |
| `CHAT_IP_PER_MIN` | 30 | Max chat per IP per minute |
| `CHAT_MAX_TOKENS` | 500 | Max tokens per chat response |
| `HERO_DAILY_LIMIT` | 30 | Daily cap for Dumpling Hero endpoints (shared) |
| `HERO_UID_PER_MIN` | 8 | Per-user/min for hero endpoints |
| `HERO_IP_PER_MIN` | 20 | Per-IP/min for hero endpoints |
| `HERO_PREVIEW_DAILY_LIMIT` | 40 | Daily cap for preview-dumpling-hero-comment |
| `ENABLE_CHAT_DEBUG` | (unset) | Set to `true` to re-enable "9327" debug prompt dump |

`OPENAI_API_KEY` is already configured (via Render secret). No change needed unless you rotate it.

---

## 4. Auth Requirements – Confirm These Flows Work

- **Chat:** User must be **signed in**. Chat screen requests an ID token and sends `Authorization: Bearer <token>`. If not signed in, they see “Please sign in to chat with Dumpling Hero.”
- **Combo:** User must be **signed in**. Personalized combo uses the same token.
- **Receipt scan:** Uses **submit-receipt** with Bearer token (already in place). No change.
- **Dumpling Hero (preview, post, comment):** All require **signed-in** user + token.

Manually test: sign out, open Chat, send a message → must get sign-in message, not a generic error.

---

## 5. Admin-Only Endpoints

These now require **admin** auth (Bearer token for a user with `users/{uid}.isAdmin == true`):

- `GET /firestore-menu`
- All other existing admin routes that already used Bearer auth

If you have scripts or an admin UI that call **firestore-menu**, ensure they send `Authorization: Bearer <idToken>` for an admin user.

---

## 6. Local / Test Scripts

- **`test-dumpling-hero-comment.js`** and similar scripts POST to Dumpling Hero endpoints **without** auth. They will get **401** until you add `Authorization: Bearer <token>`.
- **`/analyze-receipt`** (if you use it) now requires auth on the **Render** backend. The **Firebase Functions** `api` export still has an unauthenticated **analyze-receipt** route. If you use that Functions HTTP API for receipts, either add auth there or stop using it in favor of Render’s **submit-receipt**.

---

## 7. Storage Rules – Quick Checks

- **Profile photos:** Must be **image/jpeg**, &lt; 5 MB. Path: `profile_photos/{uid}.jpg`. Only owner can read/write.
- **Promo slides / category icons / menu images:** Admin-only write, size/type limits. Public read unchanged.
- **Community posts:** Any signed-in user can **create** (image/video, &lt; 25 MB). **Update/delete** only by admin. If you later allow users to delete their own posts, you’ll need owner-scoped paths (e.g. `community_posts/{uid}/{file}`) and rule updates.
- **Legacy root images** (`Subject.png`, `wontonsoup-2.png`, `eda.png`, `coke.png`, `peanut.png`): Still public read. Anything else at root is denied.

---

## 8. Menu – Realtime vs One-Time Fetch

- **Customers:** One-time fetch + cache-first. Pull-to-refresh triggers a fresh fetch. When **admin editing mode** is active, pull-to-refresh does **not** run a one-time fetch (realtime listeners are used instead).
- **Admins:** Realtime listeners only when **admin editing mode** is enabled (e.g. menu editor screen). Disabling that mode clears listeners and caches current data.

---

## 9. Firebase Functions

- **Referral trigger** runs only when `points` **changed** and the change is relevant to progress/award. Unrelated writes (e.g. FCM token, profile) no longer trigger it.
- **Menu sync trigger** skips no-op writes (before/after data identical).

---

## 10. Feature Integrity (Double-Check)

Verified during review; one **fix** was applied:

- **Menu admin image upload:** One menu item image upload path used `putData(_, metadata: nil)`. Storage rules require `contentType` (isImage). That upload would have been **rejected** after deploying storage rules. **Fixed:** `MenuAdminDashboard` now sets `StorageMetadata()` with `contentType = "image/jpeg"` for that flow.
- **Rewards limit(10):** The active redemption listener uses `.limit(to: 10)`. Users with **more than 10** active (unused, unexpired) redemptions only see the 10 most recent. Uncommon; acceptable trade-off for cost. No change.
- **Referral trigger:** Skips only when points unchanged or when both before/after ≥ 50 (no cross, no progress update). Never skips a valid 50-point cross or progress update. ✅
- **Receipt duplicate checks:** `limit(1)` is sufficient to detect any duplicate; we never miss one. ✅
- **Auth’d endpoints:** Chat, combo, submit-receipt, preview-dumpling-hero, Dumpling Hero post/comment all send Bearer token from the app. firestore-menu / hero post/comment are not called from iOS; only scripts/admin. ✅
- **Storage:** Profile photos (owner-only read), promo/category/menu (admin writes, public read), legacy root images allowlist – all match app usage. ✅

---

## 11. Optional UX Tweaks

- **401 from server** (e.g. expired token): Chat/combo currently show "Sorry, I'm having trouble...". "Please sign in" only appears when there's no signed-in user (token fetch fails). If you want 401 to also show "Please sign in", you’d need to check `HTTPURLResponse.statusCode` before decoding and map 401 accordingly.

---

## 12. If Something Breaks

- **“Index required” on submit-receipt:** Run `firebase deploy` so the new `receipts` (and `redeemedRewards`) indexes are created.
- **401 on chat/combo:** User not signed in or token missing/expired. Ensure Client sends `Authorization: Bearer <idToken>` and that the user is logged in.
- **403 on firestore-menu:** Caller is not an admin. Use an admin user’s ID token.
- **Storage upload rejected:** Check file size, type, and path (e.g. profile_photos `{uid}.jpg`, menu_images allowed types). See **Storage rules** above.

---

## Summary

1. Deploy **Render** (backend-deploy).
2. Run **`firebase deploy`** (rules, indexes, functions).
3. Optionally set **env vars** for rate limits and caps.
4. Manually test **chat** and **combo** with signed-in vs signed-out users.
5. Update any **scripts** or **admin tools** that call protected endpoints to send a Bearer token.
6. If you use **Functions** `api` for **analyze-receipt**, add auth or switch to Render **submit-receipt** only.
