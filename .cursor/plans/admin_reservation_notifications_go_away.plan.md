# Admin Reservation Notifications: Make Them Go Away

## Problem

Reservation notifications for admins ("New reservation" with type `reservation_new`) never go away. They can be marked as read when the admin opens the Notifications center (or when they confirm from the card), but they remain in the list. Admins want these notifications to disappear once the reservation has been acted on (confirmed, cancelled, or deleted).

## Current behavior

- **POST /reservations** creates one notification per admin (userId, type `reservation_new`, reservationId, title/body). Each admin sees one "New reservation" notification.
- **NotificationsCenterView** shows them in a "Reservations" section; opening the center calls `markAllNotificationsAsRead()` so they appear read and the badge clears.
- **ReservationNotificationCard** has Confirm/Call; on confirm success the app calls `markNotificationAsRead(notificationId)` so that one notification is marked read locally and in Firestore.
- Notifications are never removed: they stay in the list (read or unread) until the user has no way to clear them.

## Approach: Remove notifications when the reservation is acted on (backend)

When an admin **confirms**, **cancels**, or **deletes** a reservation, remove all "New reservation" notifications that reference that reservation so they disappear for every admin.

- **Backend** (both [backend-deploy/server.js](backend-deploy/server.js) and [server.js](server.js)):
  - In **PATCH /reservations/:id** (admin confirm/cancel): after successfully updating the reservation doc, query `notifications` where `reservationId == id` and `type == 'reservation_new'`, and delete those documents (batch delete if many).
  - In **DELETE /reservations/:id**: after successfully deleting the reservation doc, same: query notifications where `reservationId == id` and `type == 'reservation_new'`, and delete them.
- **Firestore:** Notifications are in collection `notifications` with fields `reservationId`, `type`. Use Admin SDK; no rule change needed (server bypasses rules).
- **iOS:** No change required. The app’s existing Firestore listener for the user’s notifications will receive the removal and the list will update; the notification will disappear from the UI.

## Implementation details

1. **Query:** `db.collection('notifications').where('reservationId', '==', id).where('type', '==', 'reservation_new').get()`.
2. **Composite index:** Firestore may require a composite index on `notifications` for `reservationId` and `type`. If the query fails with "index required", add the index (Firestore error message usually includes a link) or do two queries (e.g. by reservationId only, then filter by type in code) to avoid an index.
3. **Delete:** Loop and `batch.delete(doc.ref)` (batches of 500), or delete in a single batch if count is small.
4. **Placement:** Run this after the reservation update/delete succeeds, before sending the customer notification (so the order is: update/delete reservation, clear admin reservation_new notifications, then create customer notification if applicable).

## Summary

| Where | What |
|-------|------|
| Backend PATCH /reservations/:id | After updating reservation, query and delete all notification docs with that reservationId and type reservation_new. |
| Backend DELETE /reservations/:id | After deleting reservation, same: query and delete those notification docs. |
| iOS | No change; listener will remove items from the list when docs are deleted. |

## Backward compatibility

- Additive: only deletes notification documents that match the reservation. Existing behavior (mark as read, confirm from card) unchanged.
- If the query fails (e.g. missing index), log the error and do not block the reservation update/delete; notifications would remain until a later fix (e.g. add index or filter in code).
