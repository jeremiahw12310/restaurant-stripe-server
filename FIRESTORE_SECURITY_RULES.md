# Firestore Security Rules Documentation

## Overview

This document explains the Firestore security rules implemented for the Restaurant Demo app. These rules protect your data while allowing the app to function properly.

## Security Rules Summary

The rules have been deployed to your Firebase project and will take effect immediately. They replace the Test Mode configuration that was allowing unrestricted access.

## Collections and Access Rules

### 1. Users Collection (`/users/{userId}`)
- **Read Access**: Users can read their own profile, admins can read all user profiles
- **Write Access**: Users can update their own profile, admins can update any profile
- **Purpose**: Stores user information including admin status

### 2. Crowd Meter Collection (`/crowdMeter/{document}`)
- **Read Access**: Public (anyone can read crowd levels)
- **Write Access**: Admin only (only authenticated admins can update crowd levels)
- **Purpose**: Stores real-time crowd level data for different hours and days

### 3. Menu Collection (`/menu/{categoryId}`)
- **Read Access**: Public (anyone can read menu categories)
- **Write Access**: Admin only (only authenticated admins can modify menu categories)
- **Purpose**: Stores menu category information

### 4. Menu Items Subcollection (`/menu/{categoryId}/items/{itemId}`)
- **Read Access**: Public (anyone can read menu items)
- **Write Access**: Admin only (only authenticated admins can modify menu items)
- **Purpose**: Stores individual menu item details

## Helper Functions

The rules use these helper functions to determine access:

### `isAuthenticated()`
- Returns `true` if the user is logged in
- Used to ensure only authenticated users can perform certain operations

### `isAdmin()`
- Returns `true` if the user is authenticated AND has admin status in their user document
- Used to restrict admin-only operations

### `isOwner(userId)`
- Returns `true` if the authenticated user is accessing their own data
- Used to allow users to manage their own profiles

## Security Features

1. **Authentication Required**: Most write operations require user authentication
2. **Admin-Only Operations**: Sensitive operations (menu management, crowd updates) require admin privileges
3. **Public Read Access**: Menu and crowd data are publicly readable for app functionality
4. **User Data Protection**: Users can only access their own profile data
5. **Deny by Default**: Any collection not explicitly allowed is denied access

## Testing the Rules

You can test these rules using the Firebase Console:

1. Go to [Firebase Console](https://console.firebase.google.com/project/dumplinghouseapp/firestore/rules)
2. Use the Rules Playground to test different scenarios
3. Verify that:
   - Anonymous users can read menu and crowd data
   - Only admins can write to menu and crowd collections
   - Users can only access their own profile data

## Important Notes

1. **Admin Setup**: Ensure at least one user has admin privileges by setting `isAdmin: true` in their user document
2. **App Functionality**: The rules are designed to maintain all current app functionality while adding security
3. **Monitoring**: Monitor the Firebase Console for any rule violations or access issues
4. **Updates**: If you add new collections, update the security rules accordingly

## Emergency Access

If you need to temporarily disable security rules (not recommended):

1. Go to Firebase Console → Firestore → Rules
2. Temporarily set rules to allow all access:
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} {
         allow read, write: if true;
       }
     }
   }
   ```
3. **IMPORTANT**: Re-enable proper security rules immediately after troubleshooting

## Compliance

These rules ensure:
- ✅ Data is protected from unauthorized access
- ✅ App functionality is maintained
- ✅ Admin operations are properly secured
- ✅ User privacy is respected
- ✅ Firebase security best practices are followed

## Support

If you encounter any issues with the security rules:
1. Check the Firebase Console for error messages
2. Verify user authentication status
3. Confirm admin privileges are properly set
4. Test rules in the Rules Playground 