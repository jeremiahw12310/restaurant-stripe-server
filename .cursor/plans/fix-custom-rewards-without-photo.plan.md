---
name: "Fix Custom Rewards Without Photo"
overview: "Fix custom rewards to allow sending without photos, fix storage bucket initialization error, and ensure UI properly handles optional images"
todos:
  - id: fix-bucket-init
    content: "Fix storage bucket initialization with explicit bucket name in backend-deploy/server.js"
  - id: make-image-optional-backend
    content: "Make image optional in backend endpoint - remove req.file requirement and wrap upload logic"
  - id: make-image-optional-frontend-validation
    content: "Remove image requirement from canSend validation in AdminSendRewardsView.swift"
  - id: make-image-optional-frontend-send
    content: "Update sendCustomReward method to handle optional image in multipart form"
  - id: update-ui-label
    content: "Update UI label to show 'Reward Image (Optional)' in AdminSendRewardsView.swift"
isProject: false
---

# Fix Custom Rewards Without Photo Support

## Problems Identified

1. **Storage Bucket Error**: Backend calls `storage.bucket()` without specifying bucket name, causing "Bucket name not specified or invalid" error
2. **Image Required**: Both backend and frontend require images for custom rewards
3. **UI Validation**: Frontend validation prevents sending custom rewards without images

## Root Causes

1. **Backend** (`backend-deploy/server.js` line 7988): `storage.bucket()` called without explicit bucket name
2. **Backend** (`backend-deploy/server.js` line 7945-7947): Endpoint requires `req.file` (image)
3. **Frontend** (`AdminSendRewardsView.swift` line 521): `canSend` validation requires `selectedImage != nil`
4. **Frontend** (`AdminSendRewardsView.swift` line 714): `sendCustomReward` requires image

## Solution

### 1. Fix Storage Bucket Initialization

Specify the bucket name explicitly when calling `storage.bucket()`. Based on the codebase, the bucket name is `dumplinghouseapp.firebasestorage.app`.

**File**: `backend-deploy/server.js` (line 7988)

**Change**:

```javascript
const bucket = storage.bucket('dumplinghouseapp.firebasestorage.app');
```

### 2. Make Image Optional in Backend

Modify the `/admin/rewards/gift/custom` endpoint to:

- Make image optional (remove `req.file` requirement)
- Only upload to storage if image is provided
- Set `imageURL` to `null` if no image

**File**: `backend-deploy/server.js` (lines 7940-8013)

**Changes**:

- Remove `if (!req.file)` validation error
- Wrap image upload logic in `if (req.file)` check
- Set `imageURL: null` when no image provided
- Only clean up `req.file.path` if file exists

### 3. Make Image Optional in Frontend UI

Update the UI to:

- Remove image requirement from validation
- Make image upload optional in UI
- Update send logic to handle missing image

**Files**:

- `AdminSendRewardsView.swift` - Update `canSend` validation (line 521)
- `AdminSendRewardsView.swift` - Update `sendCustomReward` method (line 713)
- `AdminSendRewardsView.swift` - Update UI label to show image as optional (line 236)

## Implementation Details

### Backend Changes

1. **Fix bucket initialization** (line 7988):
   ```javascript
   const bucket = storage.bucket('dumplinghouseapp.firebasestorage.app');
   ```

2. **Make image optional** (lines 7945-8013):

   - Remove the `if (!req.file)` error return
   - Wrap image upload in conditional:
     ```javascript
     let imageURL = null;
     if (req.file) {
       const bucket = storage.bucket('dumplinghouseapp.firebasestorage.app');
       // Upload image logic here
       imageURL = `https://storage.googleapis.com/${bucket.name}/${imageFileName}`;
       // Clean up local file
       fs.unlinkSync(req.file.path);
     }
     ```

   - Update `giftedRewardData` to use `imageURL` (which can be null)
   - Only clean up `req.file.path` if `req.file` exists

### Frontend Changes

1. **Update validation** (`AdminSendRewardsView.swift` line 521):
   ```swift
   // Custom reward
   return !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
          !customDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
   // Remove: selectedImage != nil
   ```

2. **Update send method** (`AdminSendRewardsView.swift` line 713):

   - Remove `guard let image = selectedImage else { return }`
   - Make image data optional in multipart form
   - Only add image to form data if `selectedImage != nil`

3. **Update UI label** (line 236):

   - Change "Reward Image" to "Reward Image (Optional)"

## Testing

After implementation:

1. Send custom reward with image - should work
2. Send custom reward without image - should work
3. Verify storage bucket error is fixed
4. Verify UI allows sending without image
5. Verify admin scanning UI displays custom rewards correctly (with or without images)

## Files to Modify

1. `backend-deploy/server.js` - Fix bucket initialization and make image optional
2. `Restaurant Demo/AdminSendRewardsView.swift` - Make image optional in UI and validation

## Notes

- The bucket name `dumplinghouseapp.firebasestorage.app` is confirmed from `GoogleService-Info.plist`
- Custom rewards without images should display a default icon or placeholder in the UI
- The `GiftedReward` model already supports `imageURL: String?` (optional), so no model changes needed
- Root `server.js` doesn't have this endpoint, so only `backend-deploy/server.js` needs changes