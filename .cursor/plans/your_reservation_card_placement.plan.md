# Your Reservation Card: Placement and Visibility

## Problem

- User made a reservation but does not see the "Your Reservation" card.
- Card should appear **under "Just For You"** on Home and remain visible **until the day after the reservation** (or until it’s cancelled).

## Current Behavior

1. **Placement**  
   The card is currently below **Crowd Meter** and above the "Reserve A Table" card (around line 311 in `HomeView.swift`). That’s far down the page, so it’s easy to miss and not where the user expects it.

2. **Visibility window**  
   Backend `GET /reservations/mine` returns only reservations with `date >= today` (YYYY-MM-DD). So:
   - Card is hidden for past dates (correct).
   - Requirement: show the card on the **reservation day** and on the **day after** the reservation, then hide. So we must include reservations where the date is **yesterday** as well (so “day after” still shows the card).

3. **Why the card might not show at all**  
   - Backend not deployed or old backend without `GET /reservations/mine` → request fails, `reservation` stays `nil`.  
   - Firestore composite index missing for `reservations` (`userId` + `date` + `orderBy date`) → backend can return 500, client gets no data.  
   - Card is just far down the list (Crowd Meter, etc.) so it’s not seen.

---

## Plan

### 1. Move the card under "Just For You"

**File:** [Restaurant Demo/HomeView.swift](Restaurant Demo/HomeView.swift)

- **Remove** the "Your Reservation Status Card" block from its current position (below Crowd Meter, ~lines 311–315).
- **Insert** the same block **immediately after** the "Just For You" header block (after the `HStack` that contains "Just For You," and the name, and the padding — i.e. after the `.padding(.bottom, 4)`), and **before** the "Gifted Reward Banner" section.
- Resulting order: **Unified Greeting + Points** → **Just For You** (header) → **Your Reservation Card** (if `reservationVM.reservation != nil`) → **Gifted Reward Banner** (if any) → **Promo Carousel** → … rest unchanged.
- Keep the same animation binding (`yourReservationAnimated`) and trigger that animation in the same place in `startSequentialAnimations()` so the card still animates in when it appears.

### 2. Show card until the day after the reservation

**Backend (both `server.js` and `backend-deploy/server.js`):**

- In `GET /reservations/mine`, change the date filter from “today and future” to “yesterday, today, and future”:
  - Compute `yesterdayStr` in YYYY-MM-DD (e.g. `new Date()` minus 1 day, then format).
  - Use `where('date', '>=', yesterdayStr)` instead of `where('date', '>=', todayStr)`.
- Keep existing filters: `userId == caller`, non-cancelled, same response shape.
- Effect: reservation for date D shows on D and D+1, then disappears from the list (and card hides) from D+2 onward.

**Optional (if Firestore index errors are an issue):**  
If the composite index for `userId` + `date` + `orderBy('date')` is not present and cannot be added quickly, consider querying by `userId` only and filtering in server memory for `date >= yesterdayStr` and `status !== 'cancelled'`, then sorting by date. That avoids a composite index but may be less efficient with many reservations per user.

### 3. No other changes required

- **ReservationCard** (“Reserve A Table”) stays where it is (below Crowd Meter).
- **reservationVM.load()** on `setupView` and on reservation sheet `onDismiss` stays as is so the card updates when the user returns to Home or after making a new reservation.
- Backend response shape and iOS model stay the same; only the date threshold and Home layout change.

---

## Summary

| What | Where | Change |
|------|--------|--------|
| Card position | HomeView | Move from below Crowd Meter to directly under "Just For You" (before Gifted Reward Banner). |
| Visibility window | Backend GET /reservations/mine | Return reservations with `date >= yesterday` (and not cancelled) so the card shows on reservation day and the day after. |
| Animation | HomeView | Keep `yourReservationAnimated`; ensure it’s still set in the same animation sequence (may need to run slightly earlier now that the card is higher on the page). |

After this, the "Your Reservation" card will appear in the intended place under "Just For You" and will remain visible until the day after the reservation (or until it’s cancelled).
