# Admin Receipt Detail & 48h Images — v1.1 Checklist

Use this to confirm deployment steps and backward compatibility for the Dumpling House app v1.1.

---

## What you need to do

1. **Apply Storage lifecycle (48h delete)**  
   Receipt images are written to `receipt_images/` but are only auto-deleted if you add a lifecycle rule. See [RECEIPT_IMAGES_LIFECYCLE.md](RECEIPT_IMAGES_LIFECYCLE.md).  
   - In Google Cloud Console: Storage → your bucket → Lifecycle → add rule for prefix `receipt_images/`, delete after 2 days.  
   - Or use the gsutil example in that doc.

2. **Confirm Firebase Storage bucket name**  
   The code uses `dumplinghouseapp.firebasestorage.app`. If production uses a different bucket, update it in `backend-deploy/server.js` in:
   - `POST /submit-receipt` (upload)
   - `GET /admin/receipts/:id` (signed URL)
   - `DELETE /admin/receipts/:id` (delete object)

3. **Deploy backend**  
   Deploy `backend-deploy/` to your production environment (e.g. Render) so the new receipt image upload and `GET /admin/receipts/:id` are live.

4. **Ship the iOS app**  
   No extra Xcode steps: the new UI is in the existing `AdminReceiptsView.swift` file. Build and submit as usual.

---

## Backward compatibility (v1.1)

All of the following were checked so **existing production behavior is unchanged**:

| Area | Status |
|------|--------|
| **List receipts** | `GET /admin/receipts` response shape unchanged: `receipts` (id, orderNumber, orderDate, timestamp, userId, userName, userPhone), `nextPageToken`. No new required fields. |
| **Pagination** | Same cursor format and handling; existing clients keep working. |
| **Delete receipt** | `DELETE /admin/receipts/:id` still deletes the receipt and logs the action. Only addition: if the doc has `imageStoragePath`, the Storage object is also deleted. Receipts without that field are unchanged. |
| **Submit receipt (customer flow)** | Points transaction and success response are unchanged. Image upload runs *after* the transaction; if it fails we log and still return success, so customers still get points. |
| **Receipt documents** | New fields are optional: `imageStoragePath`, `imageExpiresAt`, and visibility/tampering flags. Old receipts without them remain valid; list and detail handle missing fields. |
| **Existing app versions** | Old app builds never call `GET /admin/receipts/:id` and don’t tap for detail; list and delete continue to work as before. |
| **Root server.js** | Not modified. If you use it (e.g. with `usedReceipts`), its behavior is unchanged. |

---

## Optional: root server.js

If you run the root [server.js](server.js) in any environment (e.g. dev) and want the same 48h image + detail behavior there, you’d need to mirror the backend-deploy changes (submit-receipt image upload, GET detail, DELETE Storage cleanup). The plan and this checklist focus on **backend-deploy** as production; no change to root server.js is required for v1.1.
