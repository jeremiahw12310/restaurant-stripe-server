# Notification System Compliance Review

## Current Implementation Status

### ✅ Compliant Practices
1. **Proper API Usage**: Uses `UNUserNotificationCenter.requestAuthorization` correctly
2. **Permission Timing**: Requests permission after login (not at app launch)
3. **Foreground Handling**: Properly handles notifications when app is in foreground
4. **Token Management**: Removes FCM token on logout

### ⚠️ Potential Compliance Issues

#### 1. Missing In-App Opt-Out Controls
**Issue**: Users can only disable notifications via iOS Settings. Apple prefers in-app controls, especially for promotional notifications.

**Apple Guideline**: Apps should provide in-app settings for notification preferences, particularly for marketing/promotional content.

**Current State**: 
- Admin broadcast notifications are sent to all users
- No way to opt-out of promotional notifications while keeping transactional ones
- Users must go to iOS Settings to disable

**Recommendation**: Add notification settings in the app with:
- Toggle for promotional/admin notifications
- Keep transactional notifications (referrals, rewards) always enabled
- Link to iOS Settings for granular control

#### 2. Promotional Notification Handling
**Issue**: Admin broadcast notifications are promotional/marketing content without explicit opt-in.

**Apple Guideline**: Promotional notifications should be opt-in and users should be able to easily opt-out.

**Current State**:
- Admin can send broadcast notifications to all users
- No distinction between promotional and transactional notifications
- No opt-in mechanism for promotional content

**Recommendation**: 
- Add user preference field: `promotionalNotificationsEnabled` (default: false)
- Only send promotional notifications to users who have opted in
- Always allow transactional notifications (referrals, rewards, system)

#### 3. Permission Request Context
**Issue**: Permission is requested immediately after login, which may not be contextual.

**Apple Guideline**: Request permission when the feature is actually needed, not just when convenient.

**Current State**: Permission requested on first login automatically.

**Recommendation**: 
- Consider requesting permission when user first receives a referral or reward
- Or show a brief explanation before requesting permission
- Make the value proposition clear

## Recommended Implementation

### 1. Add Notification Preferences to User Model

```swift
// In Firestore user document
{
  promotionalNotificationsEnabled: boolean (default: false)
  transactionalNotificationsEnabled: boolean (default: true)
}
```

### 2. Create NotificationSettingsView

Add a new settings screen accessible from MoreView that allows users to:
- Toggle promotional notifications on/off
- View current notification permission status
- Open iOS Settings for granular control
- See what types of notifications they'll receive

### 3. Update Backend Notification Logic

Modify `/admin/notifications/send` endpoint to:
- Check `promotionalNotificationsEnabled` before sending promotional notifications
- Always send transactional notifications regardless of preference
- Respect user preferences when filtering recipients

### 4. Update Permission Request Flow

Consider adding a brief explanation before requesting permission:
- "Stay updated on rewards and friend referrals"
- Request permission when user first earns points or receives a referral

## Priority Actions

1. **High Priority**: Add in-app notification settings with promotional opt-out
2. **Medium Priority**: Update backend to respect promotional notification preferences
3. **Low Priority**: Improve permission request timing/context

## Compliance Checklist

- [x] Uses proper UNUserNotificationCenter API
- [x] Requests permission (not at app launch)
- [x] Handles foreground notifications
- [ ] Provides in-app notification settings
- [ ] Allows opt-out of promotional notifications
- [ ] Distinguishes promotional vs transactional notifications
- [ ] Respects user preferences when sending notifications

## Notes

- The current implementation is mostly compliant but could be improved
- The main risk is admin broadcast notifications without opt-out mechanism
- Adding in-app settings would significantly improve compliance and user experience
- Transactional notifications (referrals, rewards) are generally fine to send without explicit opt-in
