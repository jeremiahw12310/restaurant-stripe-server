# Reservation Card, Admin, Reminders, and Auto-Confirm

Plan covering: move Your Reservation card under Just For You above carousel; admin delete (including ongoing); day-of countdown; notification reminders; streamlined admin reservations UI; **auto-confirm parties under 4 after 5 minutes**.

**Important (v1.1):** All changes must be backward-compatible. Existing features, data structures, and user flows must continue to work exactly as in production. New behavior is additive only; no removal or breaking change to current APIs, UI flows, or Firestore usage.

---

## Backward Compatibility (v1.1)

- **APIs:** No changes to existing endpoints (POST/GET/PATCH reservations). New: DELETE and cron endpoints only; existing request/response shapes unchanged.
- **Data:** New optional fields (e.g. reminder flags, `confirmedBy: 'auto'`) are additive; existing docs remain valid. No required schema migration.
- **iOS:** Card move is layout-only. New UI (countdown, Delete button, grouped list) is additive; existing Confirm/Cancel/Call and list behavior unchanged. Existing notification types and parsing (fallback to `.system` for unknown types) unchanged.
- **Admin flows:** Confirm and Cancel keep current behavior; Delete is an additional action. Streamlining is layout and default filter only.
- **Auto-confirm:** Applies only to pending reservations that match the rule; does not alter already confirmed/cancelled or admin-confirmed flow.

---

## 1. Move Your Reservation Card Under Just For You, Above Carousel

**File:** [Restaurant Demo/HomeView.swift](Restaurant Demo/HomeView.swift)

- Remove the "Your Reservation Status Card" block from below Crowd Meter (~lines 312–316).
- Insert it immediately after the "Just For You" header (after `.padding(.bottom, 4)` ~line 265), before the Gifted Reward Banner.
- Order: Just For You → Your Reservation Card (if has reservation) → Gifted Reward Banner → Promo Carousel → …
- Keep `yourReservationAnimated`; trigger it earlier in `startSequentialAnimations()`.

---

## 2. Admin: Delete Reservations (Including Ongoing)

**Backend:** Add `DELETE /reservations/:id` (admin-only). Delete Firestore doc; optionally notify customer (e.g. "Your reservation for [date] at [time] has been removed.").

**iOS AdminReservationsView:** Add `deleteReservation(id:onDone:)`; add Delete button for all statuses with confirmation alert and success feedback.

---

## 3. Day-of Countdown on Your Reservation Card

**YourReservationCard.swift:** Parse `date` + `time` into a `Date`. When `isToday` and reservation time is in the future, show "In Xh Ym" (or "In 45 minutes") and refresh every minute (e.g. `Timer.publish`). When time has passed, show alternate copy or hide countdown.

---

## 4. Notification Reminders

**Backend:** Cron-style endpoint (e.g. `/cron/reservation-reminders` or `/admin/cron/reservation-reminders`) secured by secret or admin. Query reservations with date = tomorrow (day-before reminder) or date = today (day-of reminder); filter by status and reminder-sent flags. Create in-app notification for `userId`; set `reminderDayBeforeSent` / `reminderDayOfSent` (or similar) on the reservation doc. Optionally FCM push.

---

## 5. Streamline Admin Reservations Menu

**AdminReservationsView:** Default filter Pending; optional group-by-date sections; add Delete for all statuses; show only Delete + Call for confirmed/cancelled; keep Confirm/Cancel for pending; optional search by name.

---

## 6. Auto-Confirm Parties Under 4 After 5 Minutes

**Backend:**

- **Trigger:** Same cron/scheduler that runs reservation reminders (or a dedicated cron). Run periodically (e.g. every 5 minutes).
- **Logic:**
  - Query Firestore `reservations` where:
    - `status == 'pending'`
    - `partySize < 4` (or `partySize <= 3`)
    - `createdAt` is older than 5 minutes (e.g. `createdAt <= now - 5 minutes` using Firestore timestamp comparison, or fetch docs and filter in Node).
  - For each such reservation:
    - Update document: `status: 'confirmed'`, `confirmedAt: serverTimestamp()`, `confirmedBy: null` (or a system value like `'auto'` if you want to distinguish).
    - Create an in-app notification for the reservation’s `userId`: e.g. title "Reservation Confirmed", body "Your reservation for [party] on [date] at [time] has been confirmed."
    - Use the same notification shape as the existing PATCH confirm flow (type e.g. `reservation_confirmed`) so the app already handles it.
- **Idempotency:** Only update reservations that are still `pending` at the moment of the update (read-modify-write or transaction) so a concurrent admin confirm doesn’t get overwritten.
- **Deployment:** Expose an endpoint (e.g. `POST /cron/auto-confirm-reservations` or include in `/cron/reservation-reminders`) callable by Render cron (or equivalent) on a schedule (e.g. every 5 minutes). Secure with a shared secret or internal-only URL so only the scheduler can call it.

**iOS:** No change required. Auto-confirmed reservations will appear as confirmed when the user next fetches (GET /reservations/mine or when the card refreshes); existing confirmed state and notifications UI already apply.

---

## Summary

| Item | Where | What |
|------|--------|------|
| Card position | HomeView | Under Just For You, above Gifted Reward Banner and Promo Carousel. |
| Admin delete | Backend + AdminReservationsView | DELETE /reservations/:id; Delete button + confirm for all statuses. |
| Day-of countdown | YourReservationCard | "In Xh Ym" when isToday and time in future; update every minute. |
| Reminders | Backend cron | Day-before and day-of in-app notifications; reminder-sent flags on reservation. |
| Streamline admin | AdminReservationsView | Group by date (optional), Delete, simpler row actions. |
| **Auto-confirm** | **Backend cron** | **Every ~5 min: pending + partySize < 4 + createdAt &gt; 5 min ago → set confirmed, notify customer.** |

**v1.1 constraint:** Implement all items as additive or layout-only; no breaking changes to production behavior or data contracts.
