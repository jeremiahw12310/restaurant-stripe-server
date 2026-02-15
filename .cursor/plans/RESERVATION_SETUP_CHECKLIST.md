# Reservation Features – What You Need To Do

After deploying the latest code, do the following so everything works.

---

## 1. Backend (Render or your host)

- **Deploy** the updated backend so it includes:
  - `DELETE /reservations/:id`
  - `POST /cron/reservation-reminders`

- **Set `CRON_SECRET`** in your backend environment (e.g. Render → Environment):
  - Pick a long random string (e.g. from a password generator).
  - If this is not set, the reminders endpoint always returns 401 and no reminders are sent.

---

## 2. Schedule the reminders cron

- **Call the reminders endpoint on a schedule** (e.g. every hour):
  - URL: `POST https://<your-backend>/cron/reservation-reminders`
  - Header: `X-Cron-Secret: <value of CRON_SECRET>`
  - Or: `Authorization: Bearer <value of CRON_SECRET>`

- **Ways to run it:**
  - **Render:** Cron Job that runs `curl -X POST -H "X-Cron-Secret: $CRON_SECRET" https://your-service.onrender.com/cron/reservation-reminders` (or use a small script that sets the header from an env var).
  - **Other:** Use any cron/scheduler (GitHub Actions, AWS EventBridge, etc.) to send the same POST with the secret header.

- **Suggested schedule:** Every hour (e.g. at :00). The handler only sends each reminder once (it sets `reminderDayBeforeSent` / `reminderDayOfSent` on the reservation).

---

## 3. Firestore

- **No new indexes are required.**  
  GET /reservations/mine uses a single-field query on `userId`.  
  The cron uses single-field equality on `date`.  
  Existing indexes are enough.

- **New fields are optional.**  
  Reservations can have `reminderDayBeforeSent` and `reminderDayOfSent` (boolean). Old documents without these fields still work; the code treats “missing” as “not sent”.

---

## 4. iOS app

- **No extra setup.**  
  The app already uses your backend URL. After the backend is deployed with DELETE and the cron endpoint, the new reservation card placement, countdown, admin delete, and grouped admin list work without any app config changes.

---

## 5. Quick verification

| What | How to check |
|------|------------------|
| Card position | Open Home; when you have a reservation, the gold “Your Reservation” card is under “Just For You,” above the carousel. |
| Countdown | On the day of the reservation, the card shows “In Xh Ym” or “In X minutes” and updates over time. |
| Admin delete | As admin, open Reservations, tap Delete on any reservation, confirm; it disappears and the customer can get the “Reservation Removed” notification. |
| Admin groups | Reservations list is grouped by date with “Today,” “Tomorrow,” or the full date. |
| Reminders | After setting CRON_SECRET and scheduling the cron, create a reservation for tomorrow (or today) and wait for the next cron run; the user should get the in-app reminder. |

---

## Summary

1. Deploy backend and set **CRON_SECRET**.
2. Schedule **POST /cron/reservation-reminders** (e.g. hourly) with the secret in a header.
3. No Firestore index or schema migration required.
4. No iOS config changes required beyond using the new build.
