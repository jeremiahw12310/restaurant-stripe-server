# Suspicious Activity Triggers - Setup Checklist

## ✅ Implementation Complete

All suspicious activity triggers have been implemented in `backend-deploy/server.js`:

### 1. Receipt Scanning Triggers
- **Repeated Duplicate Submissions**: Flags users with 3+ duplicate receipt attempts within 1 hour
- **Bursty Scan Attempts**: Flags users making 4+ scan attempts per minute (approaching rate limit)

### 2. Referral Triggers  
- **High-Velocity Device Sharing**: Flags when multiple accounts on same device accept 3+ referrals within 24 hours
- **Phone Hash Cluster Abuse**: Flags when a phone number has been referred by 3+ different referrers across account history

### 3. Account Deletion/Recreation Triggers
- **Deletion Tracking**: Records account deletions with phone hash and device fingerprint in `accountDeletions` collection
- **Rapid Recreate Detection**: Flags users with 2+ account deletions within 7 days for same phone number

## ⚠️ Required Actions

### 1. Deploy Firestore Index (REQUIRED)

The new `accountDeletions` collection requires a composite index for the delete/recreate detection queries.

**Action**: Deploy the updated `firestore.indexes.json` file to Firebase:

```bash
firebase deploy --only firestore:indexes
```

Or if using Firebase CLI:
```bash
cd backend-deploy
firebase deploy --only firestore:indexes
```

**Index Details**:
- Collection: `accountDeletions`
- Fields: `phoneHash` (ASCENDING), `deletedAt` (DESCENDING)

**Note**: The index may take a few minutes to build. Queries will work but may be slower until the index is ready.

### 2. Verify Backend Deployment

After deploying the code changes, verify:
- ✅ Server restarts successfully
- ✅ No syntax errors in logs
- ✅ Triggers are creating flags (check `suspiciousFlags` collection)

### 3. Test Triggers (Optional but Recommended)

Test each trigger to ensure they work:

1. **Receipt Duplicate Trigger**: Submit 3 duplicate receipts within 1 hour
2. **Bursty Scan Trigger**: Make 4+ scan attempts in 1 minute
3. **Referral Device Sharing**: Create 3 accounts on same device and accept referrals
4. **Account Recreation**: Delete and recreate account 2+ times within 7 days

### 4. Monitor Admin Dashboard

Check the admin suspicious flags view to confirm new flags appear:
- `/admin/suspicious-flags` endpoint should show all flag types
- New `account_recreation` flag type should be visible
- Filter by `flagType` to see specific trigger types

## 📋 New Collections Created

- **`accountDeletions`**: Stores deletion metadata for recreate detection
  - Fields: `phoneHash`, `deletedAt`, `deletedUserId`, `deviceFingerprint`
  - Index required: `phoneHash` + `deletedAt` (DESC)

## 🔍 Flag Types Added

- `receipt_pattern` (enhanced with new triggers)
- `referral_abuse` (enhanced with new triggers)  
- `account_recreation` (new flag type)

## 🛡️ Apple Policy Compliance

All triggers follow Apple policy requirements:
- ✅ Flag-only enforcement (no automatic bans)
- ✅ Human review required for all actions
- ✅ No user-facing impact (flags are non-blocking)
- ✅ Evidence includes timestamps and context for manual review

## 📝 Notes

- All triggers run asynchronously and won't block user requests
- Flags are deduplicated (similar flags won't create duplicates)
- Admin endpoints already support filtering by the new flag types
- No client-side changes required
