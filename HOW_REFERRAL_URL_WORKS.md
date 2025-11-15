# 🔗 How the Referral URL Works

## The Referral URL Format

```
restaurantdemo://referral?code=ABC123
```

**Breaking it down:**
- `restaurantdemo://` - Your app's custom URL scheme (registered in Info.plist)
- `referral` - The host/action type
- `?code=ABC123` - The referral code parameter

## 📱 Complete User Flow

### **Step 1: User A (Referrer) Shares Link**

1. User A opens the Referral page in your app
2. App shows QR code with URL: `restaurantdemo://referral?code=ABC123`
3. User A taps "Invite friends" button
4. iOS Share Sheet opens with the URL
5. User A shares via:
   - **Messages** - Recipient gets tappable link
   - **Email** - Recipient gets clickable link
   - **AirDrop** - Sends link to nearby iPhone
   - **Copy Link** - Copies URL to clipboard

### **Step 2: User B (Recipient) Opens Link**

When User B taps the link on their iPhone:

```
Tap Link: restaurantdemo://referral?code=ABC123
    ↓
iOS asks: "Open in Restaurant Demo?"
    ↓
User B taps "Open"
    ↓
Your App Launches!
```

### **Step 3: App Receives the URL**

**Location:** `Restaurant_DemoApp.swift` → `AppDelegate` → `application(_:open:)`

```swift
func application(_ app: UIApplication, open url: URL, ...) -> Bool {
    // URL received: restaurantdemo://referral?code=ABC123
    
    let host = url.host // "referral"
    let code = url.queryItems // "ABC123"
    
    if host == "referral" {
        // Extract the code
        // Post notification with the code
        NotificationCenter.default.post(
            name: Notification.Name("incomingReferralCode"),
            object: nil,
            userInfo: ["code": "ABC123"]
        )
        return true
    }
}
```

### **Step 4: Code Auto-Fill (Currently Set Up)**

Your app currently has this handler in `ReferralView.swift`:

```swift
init(initialCode: String? = nil) {
    self.initialCode = initialCode
}

.onAppear {
    if let initCode = initialCode, !initCode.isEmpty {
        acceptCode = initCode.uppercased()
        // Auto-submit after 0.2 seconds
        acceptReferral()
    }
}
```

**What needs to happen:**
The notification `"incomingReferralCode"` needs to be caught somewhere (like in AuthFlowViews or ContentView) and passed to ReferralView as `initialCode`.

## 🔄 Current vs Ideal Flow

### **Current State:**
```
1. Recipient taps link
2. App opens to main screen
3. Notification is posted (but nobody is listening)
4. User must manually navigate to Referral page and enter code
```

### **Ideal State (Needs one more piece):**
```
1. Recipient taps link
2. App opens and catches notification
3. App navigates directly to Referral page with code pre-filled
4. Code auto-submits if user is within 24h of signup
```

## ✅ What Works Right Now

1. ✅ **URL Generation** - Server creates `restaurantdemo://referral?code=ABC123`
2. ✅ **URL Sharing** - Share sheet works without sandbox errors
3. ✅ **URL Reception** - App receives and parses the URL correctly
4. ✅ **Notification Posted** - `"incomingReferralCode"` is broadcast
5. ✅ **Auto-Submit Logic** - ReferralView can auto-submit if given a code

## ⚠️ What Needs One More Step

**Missing Listener:** The `"incomingReferralCode"` notification needs a listener that:
1. Catches the notification
2. Navigates to ReferralView
3. Passes the code as `initialCode` parameter

**Would you like me to add this listener?** It would only take 10-15 lines of code.

## 🎯 Use Cases

### **Use Case 1: New User (Perfect)**
```
1. User B taps link → App installed but not signed up
2. App opens → Shows signup flow
3. [With listener] App auto-navigates to Referral page after signup
4. Code auto-fills and submits
5. ✅ Referral linked!
```

### **Use Case 2: Existing User Within 24h**
```
1. User B taps link → Has account (< 24h old)
2. App opens to main screen
3. [With listener] App shows Referral page with code
4. Code auto-fills and submits
5. ✅ Referral linked!
```

### **Use Case 3: Existing User After 24h**
```
1. User B taps link → Has account (> 24h old)
2. App opens to main screen
3. [With listener] App shows Referral page
4. Message: "Referral code entry not available after 24h"
5. ❌ Referral cannot be linked (by design)
```

## 🔐 Security

The URL scheme is **safe** because:
- ✅ Only your app can respond to `restaurantdemo://` URLs
- ✅ Other apps cannot intercept these links
- ✅ The code is validated server-side before accepting
- ✅ Backend checks:
  - User hasn't already used a referral
  - Account is < 24h old
  - Code exists and is valid
  - Not trying to refer themselves

## 📊 Backend Validation Flow

When code is submitted:

```javascript
POST /referrals/accept
{
  "code": "ABC123",
  "deviceId": "unique-device-id"
}

Backend checks:
✓ User is authenticated
✓ User hasn't used a referral already
✓ Account is < 24 hours old
✓ Code exists in database
✓ Code doesn't belong to same user
✓ Device ID matches (prevents sharing)

If all pass → Link referral → Return success
If any fail → Return specific error message
```

## 🎨 What User Sees

### **Sender Side:**
```
┌─────────────────────────┐
│  Give 50, Get 50        │
│                         │
│  [Large QR Code]        │
│                         │
│  Your code: ABC123      │
│                         │
│  ┌─────────────────────┐│
│  │ 📤 Invite Friends   ││  ← Taps this
│  └─────────────────────┘│
│                         │
│  New connections: 0     │
└─────────────────────────┘

Share sheet opens:
- Messages
- Email
- AirDrop
- Copy Link

Link shared: restaurantdemo://referral?code=ABC123
```

### **Receiver Side (With Listener Added):**
```
Recipient taps link in Messages
         ↓
┌─────────────────────────┐
│  "Open in Restaurant    │
│   Demo?"                │
│                         │
│  [Cancel]  [Open]       │  ← Taps Open
└─────────────────────────┘
         ↓
App launches and navigates to:
┌─────────────────────────┐
│  Give 50, Get 50        │
│                         │
│  Have a code?           │
│                         │
│  ┌─────────────────────┐│
│  │ ABC123  ✓          ││  ← Auto-filled!
│  └─────────────────────┘│
│                         │
│  "Linking..."           │  ← Auto-submitting
│                         │
│  ✅ Linked!             │  ← Success!
└─────────────────────────┘
```

## 🔧 Technical Details

### **URL Components:**
```swift
let url = URL(string: "restaurantdemo://referral?code=ABC123")!

url.scheme      // "restaurantdemo"
url.host        // "referral"
url.query       // "code=ABC123"

URLComponents(url: url).queryItems?
    .first(where: { $0.name == "code" })?
    .value  // "ABC123"
```

### **Registration in Info.plist:**
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>restaurantdemo</string>  ← Your scheme
        </array>
    </dict>
</array>
```

### **QR Code Generation:**
The QR code is a visual representation of the URL string. When scanned:
1. Camera app reads: `restaurantdemo://referral?code=ABC123`
2. iOS recognizes your app's scheme
3. Offers to open in your app
4. Same flow as tapping a link!

## 💡 Summary

**What the URL does:**
1. 🔗 **Links** - Creates a shareable deep link to your app
2. 📱 **Opens** - Opens your app when tapped (if installed)
3. 🎯 **Routes** - Can trigger specific actions in your app
4. 🎁 **Rewards** - Connects referrer and referee for point rewards

**Current status:**
- ✅ URL generation and sharing works perfectly
- ✅ URL reception and parsing works
- ⚠️ Needs listener to auto-navigate to Referral page (optional but recommended)

**Would you like me to add the missing notification listener to complete the flow?**

---

**The URL is working!** Your app can now share referral codes without sandbox errors, and recipients can open the app via the link. The only optional enhancement is auto-navigating to the Referral page when the link is tapped.


