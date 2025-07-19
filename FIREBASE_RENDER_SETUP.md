# Firebase Configuration for Render Deployment

## Overview
Your Firebase configuration is already set up in your code to use environment variables. You just need to configure the environment variables in Render.

## Current Setup
- ✅ Firebase Admin SDK is configured in your server code
- ✅ Uses `FIREBASE_SERVICE_ACCOUNT_KEY` environment variable
- ✅ Project ID: `dumplinghouseapp`
- ✅ Firebase Functions and Storage are configured

## Authentication Options

### Option 1: Application Default Credentials (Recommended)
If service account key creation is restricted by organization policies, use Application Default Credentials:

1. **Enable Application Default Credentials in Render:**
   - Go to your Render service settings
   - Add environment variable: `GOOGLE_APPLICATION_CREDENTIALS` = `service-account.json`
   - Add environment variable: `FIREBASE_AUTH_TYPE` = `adc`

2. **Update your server code to use ADC:**
   ```javascript
   // In your server.js
   if (process.env.FIREBASE_AUTH_TYPE === 'adc') {
     // Use Application Default Credentials
     admin.initializeApp();
   } else if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
     // Use service account key (existing code)
     const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
     admin.initializeApp({
       credential: admin.credential.cert(serviceAccount)
     });
   }
   ```

### Option 2: Workload Identity Federation (Advanced)
For production environments with strict security policies:

1. **Set up Workload Identity Federation:**
   - Configure OIDC provider in Google Cloud
   - Create Workload Identity Pool
   - Map Render's OIDC tokens to service account

2. **Environment variables needed:**
   ```
   GOOGLE_CLOUD_PROJECT=dumplinghouseapp
   WORKLOAD_IDENTITY_PROVIDER=projects/123456789/locations/global/workloadIdentityPools/my-pool/providers/my-provider
   SERVICE_ACCOUNT_EMAIL=firebase-adminsdk-xxxxx@dumplinghouseapp.iam.gserviceaccount.com
   ```

### Option 3: Request Policy Exception (Contact IT)
If you need service account keys specifically:

1. **Contact your organization's IT/security team**
2. **Request exception for this specific project**
3. **Provide business justification**
4. **Request temporary policy override**

### Option 4: Use Firebase Emulator (Development Only)
For local development without production credentials:

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Start emulators
firebase emulators:start --only firestore,auth
```

## Step-by-Step Setup for Render (Updated)

### Method A: Application Default Credentials

1. **Create a service account (if not already done):**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Navigate to IAM & Admin → Service Accounts
   - Find or create a service account for Firebase Admin

2. **Grant necessary permissions:**
   - Firestore Admin
   - Firebase Admin
   - Storage Admin (if using Firebase Storage)

3. **Configure Render environment variables:**
   ```
   FIREBASE_AUTH_TYPE=adc
   GOOGLE_CLOUD_PROJECT=dumplinghouseapp
   NODE_ENV=production
   ```

### Method B: Service Account Key (If Policy Allows)

1. **Get Your Firebase Service Account Key:**
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Select your project: `dumplinghouseapp`
   - Go to **Project Settings** (gear icon)
   - Go to **Service accounts** tab
   - Click **Generate new private key**
   - Download the JSON file

2. **Configure Environment Variables in Render:**
   - Go to your Render dashboard
   - Select your service: `restaurant-stripe-server`
   - Go to **Environment** tab
   - Add the following environment variable:

   **Key:** `FIREBASE_SERVICE_ACCOUNT_KEY`
   **Value:** Copy the entire contents of the downloaded JSON file

## Updated Server Code

Here's the updated Firebase initialization code that supports both methods:

```javascript
// Initialize Firebase Admin
const admin = require('firebase-admin');

// Check authentication method
if (process.env.FIREBASE_AUTH_TYPE === 'adc') {
  // Use Application Default Credentials
  admin.initializeApp({
    projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp'
  });
  console.log('✅ Firebase Admin initialized with Application Default Credentials');
} else if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  // Use service account key
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('✅ Firebase Admin initialized with service account key');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin:', error);
  }
} else {
  console.warn('⚠️ No Firebase authentication method configured');
}
```

## Troubleshooting Organization Policies

### Common Policy Restrictions:
1. **Service Account Key Creation Disabled**
   - Solution: Use Application Default Credentials
   
2. **External Key Creation Disabled**
   - Solution: Use Workload Identity Federation
   
3. **Project-Level Restrictions**
   - Solution: Contact project owner or organization admin

### Policy Check Commands:
```bash
# Check if you can create service account keys
gcloud iam service-accounts keys list --iam-account=firebase-adminsdk-xxxxx@dumplinghouseapp.iam.gserviceaccount.com

# Check organization policies
gcloud resource-manager org-policies list --project=dumplinghouseapp
```

## Security Best Practices

1. **Use Application Default Credentials when possible**
2. **Rotate credentials regularly**
3. **Limit service account permissions**
4. **Use Workload Identity Federation for production**
5. **Never commit credentials to version control**

## Next Steps

1. **Try Application Default Credentials first** (most secure)
2. **If that doesn't work, contact your IT team** for policy exceptions
3. **Update your server code** to support multiple authentication methods
4. **Test the deployment** with the new configuration

Your Firebase configuration is already properly set up in the code - you just need to work within your organization's security policies! 