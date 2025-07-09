# 📱 iPhone Testing Setup Guide

This guide shows you how to test your app on a real iPhone using Stripe's sandbox environment.

## 🎯 Two Approaches

### Option 1: Local Network (Quick Setup)
Test on iPhone connected to same Wi-Fi as your computer

### Option 2: Cloud Deployment (Production-Ready)
Deploy to Railway/Render for testing from anywhere

---

## 📱 Option 1: Local Network Setup

### Step 1: Install Stripe Dependency
```bash
npm install stripe
```

### Step 2: Get Your Computer's IP Address

**On Mac:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
# Look for something like: inet 192.168.1.100
```

**On Windows:**
```cmd
ipconfig
# Look for IPv4 Address under your Wi-Fi adapter
```

**On Linux:**
```bash
hostname -I
# Or: ip addr show | grep "inet " | grep -v 127.0.0.1
```

### Step 3: Update Config.swift

Open `Restaurant Demo/Config.swift` and update:

```swift
// 🔧 CHANGE THIS to switch environments
static let currentEnvironment: Environment = .localNetwork

// Update this with YOUR computer's IP address
case .localNetwork:
    return "http://192.168.1.XXX:3001"  // Replace XXX with your IP
```

### Step 4: Set Up Stripe Test Keys

Create a `.env` file in your project root:

```bash
# .env file
STRIPE_SECRET_KEY=sk_test_51...  # Your Stripe test secret key
OPENAI_API_KEY=sk-...           # Your OpenAI key (optional)
```

**Get Stripe Test Keys:**
1. Go to [dashboard.stripe.com](https://dashboard.stripe.com)
2. Make sure "Test data" toggle is ON
3. Go to Developers > API keys
4. Copy your "Secret key" (starts with `sk_test_`)

### Step 5: Start the Server

```bash
node server.js
```

You should see:
```
🚀 Server running on port 3001
💳 Stripe configured: Yes (Real payments)
✅ Ready for real Stripe payments in sandbox mode
```

### Step 6: Test from iPhone

1. **Connect iPhone to same Wi-Fi** as your computer
2. **Build and run** the app on your iPhone (not simulator)
3. **Add items to cart** and proceed to checkout
4. **Use Stripe test cards:**
   - Success: `4242 4242 4242 4242`
   - Decline: `4000 0000 0000 0002`
   - Any future expiry date, any CVC

---

## ☁️ Option 2: Cloud Deployment

### Step 1: Deploy to Railway (Free)

1. **Install Railway CLI:**
   ```bash
   npm install -g @railway/cli
   ```

2. **Login to Railway:**
   ```bash
   railway login
   ```

3. **Initialize project:**
   ```bash
   railway init
   ```

4. **Set environment variables:**
   ```bash
   railway variables set STRIPE_SECRET_KEY=sk_test_51...
   railway variables set OPENAI_API_KEY=sk-...
   ```

5. **Deploy:**
   ```bash
   railway up
   ```

6. **Get your URL:**
   ```bash
   railway status
   # Copy the generated URL (e.g., https://your-app.railway.app)
   ```

### Step 2: Update iOS App Config

Open `Restaurant Demo/Config.swift`:

```swift
// 🔧 CHANGE THIS to switch environments
static let currentEnvironment: Environment = .production

// Update this with your Railway URL
case .production:
    return "https://your-app.railway.app"  // Your actual Railway URL
```

### Step 3: Build and Test

1. **Build for device** (not simulator)
2. **Test from anywhere** with internet connection!

---

## 🧪 Testing with Stripe Sandbox

### Test Credit Cards

| Card Number | Description |
|-------------|-------------|
| `4242 4242 4242 4242` | ✅ Successful payment |
| `4000 0000 0000 0002` | ❌ Card declined |
| `4000 0000 0000 9995` | ⚠️ Insufficient funds |
| `4000 0025 0000 3155` | 🔐 Requires authentication |

**Use any:**
- Future expiry date (e.g., 12/34)
- Any 3-digit CVC (e.g., 123)
- Any postal code (e.g., 12345)

### What Happens During Testing

1. **Add items** to cart
2. **Select tip** amount
3. **Tap "Proceed to Payment"**
4. **Safari opens** with real Stripe checkout
5. **Enter test card** details
6. **Complete payment**
7. **App shows order confirmation** with order number
8. **Tap "View Order"** to see order status

---

## 🛠 Troubleshooting

### iPhone Can't Connect to Server

**Check:**
- iPhone and computer on same Wi-Fi
- Computer firewall allows port 3001
- Server is running (`node server.js`)
- IP address is correct in Config.swift

**Test server connectivity:**
```bash
# From your computer
curl http://YOUR_IP:3001

# Should return: {"status":"Server is running!"...}
```

### Stripe Errors

**"Stripe not configured":**
- Check `.env` file exists
- Verify `STRIPE_SECRET_KEY` is set
- Restart server after adding environment variables

**"No such customer" or similar:**
- Make sure you're using TEST keys (sk_test_...)
- Check Stripe dashboard is in "Test data" mode

### Build Errors

**Missing OrderModels:**
- Check that all Swift files are included in project
- Clean build folder (Cmd+Shift+K)
- Rebuild project

---

## 🎉 Success!

Once set up, you'll have:
- ✅ Real iPhone testing
- ✅ Real Stripe sandbox payments  
- ✅ Proper order creation flow
- ✅ Beautiful order status screens
- ✅ URL scheme handling for payment callbacks

Your app will work exactly like a production app, but with test payments that don't charge real money!