# Stripe Production Setup Guide

## 🚀 Making Your App Work Anywhere

### Step 1: Get Stripe Production Keys

1. **Go to [Stripe Dashboard](https://dashboard.stripe.com/)**
2. **Switch to Live Mode** (toggle in top right)
3. **Get your Live Keys:**
   - Go to Developers > API Keys
   - Copy your **Publishable Key** (starts with `pk_live_`)
   - Copy your **Secret Key** (starts with `sk_live_`)

### Step 2: Set Up Render Environment Variables

1. **Go to [Render Dashboard](https://dashboard.render.com/)**
2. **Find your `restaurant-stripe-server` service**
3. **Go to Environment tab**
4. **Add these environment variables:**

```
STRIPE_SECRET_KEY=sk_live_your_live_secret_key_here
OPENAI_API_KEY=your_openai_api_key_here
NODE_ENV=production
```

### Step 3: Update iOS App for Production

1. **Open `Restaurant Demo/Config.swift`**
2. **Change line 9 to:**
   ```swift
   static let currentEnvironment: Environment = .production
   ```

### Step 4: Deploy and Test

1. **Push your code to GitHub**
2. **Render will automatically deploy**
3. **Test the app on any iPhone!**

## 🔧 Alternative: Use Stripe Test Mode (Recommended for Development)

If you want to test without real money:

1. **Stay in Test Mode** in Stripe Dashboard
2. **Use test keys** (start with `pk_test_` and `sk_test_`)
3. **Use test card numbers:**
   - `4242 4242 4242 4242` (Visa)
   - `4000 0000 0000 0002` (Declined)
   - Expiry: Any future date
   - CVC: Any 3 digits

## 📱 Testing on Any iPhone

Once deployed:

1. **Build your iOS app** in Xcode
2. **Archive and distribute** via TestFlight or Ad Hoc
3. **Install on any iPhone**
4. **The app will work anywhere in the world!**

## 🌍 Production URLs

Your app will use:
- **Backend:** `https://restaurant-stripe-server.onrender.com`
- **Stripe Checkout:** Live Stripe checkout
- **Success/Cancel:** Auto-redirects to your app

## 🔒 Security Notes

- ✅ Stripe handles all payment security
- ✅ No credit card data stored on your server
- ✅ HTTPS enforced in production
- ✅ Environment variables keep keys secure

## 🚨 Important

- **Never commit API keys** to Git
- **Use environment variables** for all secrets
- **Test thoroughly** before going live
- **Monitor Stripe dashboard** for transactions 