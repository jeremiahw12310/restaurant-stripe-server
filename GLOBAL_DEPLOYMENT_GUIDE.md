# 🌍 Global iPhone Deployment Guide

## 🚀 Make Your App Work on Any iPhone Anywhere

### Quick Setup (5 minutes)

1. **Get Stripe Keys** (2 minutes)
   - Go to [Stripe Dashboard](https://dashboard.stripe.com/)
   - Copy your **Secret Key** (starts with `sk_test_` or `sk_live_`)

2. **Set Up Render** (2 minutes)
   - Go to [Render Dashboard](https://dashboard.render.com/)
   - Find your `restaurant-stripe-server` service
   - Add environment variable: `STRIPE_SECRET_KEY=your_key_here`

3. **Deploy** (1 minute)
   ```bash
   ./deploy-production.sh
   ```

### ✅ What's Already Done

- ✅ iOS app configured for production
- ✅ Render deployment setup ready
- ✅ Stripe integration working
- ✅ Order status flow implemented
- ✅ Heart burst animations working

### 📱 Testing on Any iPhone

Once deployed:

1. **Build in Xcode:**
   - Product → Archive
   - Distribute App → Ad Hoc or TestFlight

2. **Install on iPhone:**
   - Via TestFlight (recommended)
   - Via Ad Hoc distribution
   - Works on any iPhone anywhere!

### 🌐 Production URLs

Your app will use:
- **Backend:** `https://restaurant-stripe-server.onrender.com`
- **Stripe:** Live checkout (or test mode)
- **Success/Cancel:** Auto-redirects to app

### 🔧 Environment Variables Needed

In Render dashboard, add:
```
STRIPE_SECRET_KEY=sk_test_your_key_here
OPENAI_API_KEY=your_openai_key_here
NODE_ENV=production
```

### 🎯 Test Cards (if using test mode)

- **Success:** `4242 4242 4242 4242`
- **Decline:** `4000 0000 0000 0002`
- **Expiry:** Any future date
- **CVC:** Any 3 digits

### 🚨 Important Notes

- ✅ No credit card data stored on your server
- ✅ Stripe handles all payment security
- ✅ HTTPS enforced in production
- ✅ Works globally once deployed

### 🎉 Result

After deployment, your app will:
- ✅ Work on any iPhone anywhere
- ✅ Process real payments (or test payments)
- ✅ Show order status with animations
- ✅ Handle Stripe checkout seamlessly
- ✅ Work without your computer running

### 🔄 Switching Back to Local

To test locally again:
```swift
// In Config.swift, change line 9 to:
static let currentEnvironment: Environment = .local
```

---

**🎯 Goal Achieved:** Your app now works on any iPhone anywhere in the world! 