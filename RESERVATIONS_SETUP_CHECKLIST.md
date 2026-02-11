# Reservations Feature – What You Need To Do

## 1. Deploy Firestore indexes (required before reservations work in production)

The new `reservations` queries need composite indexes. Deploy them from the **project root** (where `firestore.indexes.json` lives):

```bash
firebase deploy --only firestore:indexes
```

If you use a Firebase project alias (e.g. `production`), run:

```bash
firebase use production   # or your alias
firebase deploy --only firestore:indexes
```

Until this is done, **GET /reservations** (admin list) may fail in production with a “missing index” error. The Firebase Console will also show a link to create the index when the first query runs.

---

## 2. Deploy Firestore rules (recommended)

The `reservations` collection is now explicitly denied for client access (server-only). Deploy rules from the project root:

```bash
firebase deploy --only firestore:rules
```

---

## 3. Deploy the backend (if you use Render / backend-deploy)

Reservation routes were added to **both**:

- Root `server.js` (local / dev)
- **backend-deploy/server.js** (used by Render per `render.yaml`)

If you deploy to Render from this repo, push your branch and let Render auto-deploy, or trigger a deploy from the Render dashboard. No extra config is needed; the new routes are in `backend-deploy`.

---

## 4. No app/config changes required

- **Config.swift** already points the app at your backend via `Config.backendURL`; reservations use that.
- No new environment variables.
- No change to how admins are defined; the backend uses existing `users/{uid}.isAdmin === true` to notify admins.

---

## 5. Quick verification

1. **Customer flow**: Open the app → Home → tap “Reserve a Table” → fill form → submit. You should see “Reservation requested” and admins should get an in-app notification.
2. **Admin flow**: As an admin, open the app → Notifications (or More → Notifications). You should see a “Reservations” section with the new reservation and **Confirm** / **Call** buttons. Confirm should mark it confirmed; Call should open the phone dialer.
3. **Backend**: If something fails, check server logs for `✅ Reservation … created` or `❌ Error creating reservation` (and the same for list/patch).

---

## Summary

| Step | Action |
|------|--------|
| 1 | Run `firebase deploy --only firestore:indexes` from project root |
| 2 | Run `firebase deploy --only firestore:rules` from project root |
| 3 | Deploy backend (e.g. push to trigger Render deploy) |
| 4 | Test: customer reserves → admin sees notification → Confirm / Call |

Nothing else is required for the feature to work end-to-end.

---

## If you got 404 when creating a reservation

The app was hitting the backend but **POST /reservations** returned 404. That means the running server didn’t have the reservation routes yet (old deploy).

1. **Redeploy the backend** (push to trigger Render, or Manual Deploy in the Render dashboard).
2. **Confirm the new code is live:**
   ```bash
   curl -s https://restaurant-stripe-server-1.onrender.com/reservations/ok
   ```
   You should see `{"ok":true,"reservations":true}`. If you still get 404, wait for the deploy to finish and try again.
3. Retry creating a reservation from the app.
