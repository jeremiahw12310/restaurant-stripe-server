# Receipt Images: 48-Hour Storage Lifecycle

Receipt scan images are stored in Firebase Storage under the prefix `receipt_images/` for 48 hours so admins can view them in the Admin Receipts detail view. After 48 hours, images should be deleted automatically.

## Option 1: Google Cloud Console (recommended)

1. Open [Google Cloud Console](https://console.cloud.google.com/) and select the project (e.g. `dumplinghouseapp`).
2. Go to **Cloud Storage** → **Buckets** and open the bucket used by the app (e.g. `dumplinghouseapp.firebasestorage.app`).
3. Click the **Lifecycle** tab.
4. Add a rule:
   - **Object conditions**: Prefix = `receipt_images/`
   - **Action**: Delete object
   - **Age**: 2 days

This deletes any object under `receipt_images/` 2 days after its creation time.

## Option 2: gsutil lifecycle configuration

Create a JSON file (e.g. `lifecycle-receipt-images.json`):

```json
{
  "rule": [
    {
      "action": { "type": "Delete" },
      "condition": {
        "age": 2,
        "matchesPrefix": ["receipt_images/"]
      }
    }
  ]
}
```

Apply it (replace BUCKET_NAME with your bucket, e.g. `dumplinghouseapp.firebasestorage.app`):

```bash
gsutil lifecycle set lifecycle-receipt-images.json gs://BUCKET_NAME
```

## Backend behavior

- The backend sets `imageExpiresAt` on the receipt document (Firestore) to 48 hours from scan time. The Admin API uses this to decide whether to return a signed image URL; after 48h it returns `imageExpired: true` and no URL.
- The bucket lifecycle rule above removes the actual file from Storage after 2 days, keeping storage usage bounded even if the backend or Firestore is not queried again.
