const express = require('express');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
const cors = require('cors');
const admin = require('firebase-admin');

// Initialize Firebase Admin using Application Default Credentials (ADC)
try {
  admin.initializeApp({
    projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp'
  });
  console.log('✅ Firebase Admin initialized with ADC in Stripe server');
} catch (firebaseInitError) {
  console.error('❌ Failed to initialize Firebase Admin in Stripe server:', firebaseInitError);
}

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Create checkout session endpoint
app.post('/create-checkout-session', async (req, res) => {
  try {
    const { line_items } = req.body;
    
    console.log('Received line items:', line_items);
    
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: line_items,
      mode: 'payment',
      success_url: 'https://restaurant-stripe-server-1.onrender.com/success?session_id={CHECKOUT_SESSION_ID}',
      cancel_url: 'https://restaurant-stripe-server-1.onrender.com/cancel',
      metadata: {
        source: 'ios_app'
      }
    });
    
    console.log('Created session:', session.id);
    
    res.json({ 
      url: session.url,
      sessionId: session.id 
    });
  } catch (error) {
    console.error('Error creating checkout session:', error);
    res.status(500).json({ error: error.message });
  }
});

// Success page that auto-redirects to app
app.get('/success', (req, res) => {
  const sessionId = req.query.session_id;
  console.log('Payment success for session:', sessionId);
  
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>Payment Successful</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 40px; }
            .success { color: #28a745; font-size: 24px; margin-bottom: 20px; }
            .button { background: #007AFF; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; display: inline-block; margin: 10px; }
            .auto-redirect { color: #666; font-size: 14px; margin-top: 20px; }
        </style>
    </head>
    <body>
        <div class="success">✅ Payment Successful!</div>
        <p>Your order has been placed successfully.</p>
        <a href="restaurantdemo://success" class="button">Return to App</a>
        <div class="auto-redirect">Redirecting to app in 2 seconds...</div>
        <script>
            setTimeout(function() {
                window.location.href = 'restaurantdemo://success';
            }, 2000);
        </script>
    </body>
    </html>
  `);
});

// Cancel page
app.get('/cancel', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>Payment Cancelled</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 40px; }
            .cancel { color: #dc3545; font-size: 24px; margin-bottom: 20px; }
            .button { background: #007AFF; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; display: inline-block; margin: 10px; }
        </style>
    </head>
    <body>
        <div class="cancel">❌ Payment Cancelled</div>
        <p>Your payment was cancelled.</p>
        <a href="restaurantdemo://cancel" class="button">Return to App</a>
    </body>
    </html>
  `);
});

// Simple order creation endpoint
app.post('/orders/orders', async (req, res) => {
  try {
    const { items, customerName, customerPhone, orderType } = req.body;
    
    console.log('Creating order:', { items, customerName, customerPhone, orderType });
    
    // Generate a simple order ID
    const orderId = 'order_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
    
    // Create order object
    const order = {
      id: orderId,
      items: items,
      customerName: customerName,
      customerPhone: customerPhone,
      orderType: orderType,
      status: 'pending',
      createdAt: new Date().toISOString(),
      total: items.reduce((sum, item) => sum + (item.price * item.quantity), 0)
    };
    
    console.log('Created order:', orderId);
    
    res.json({
      success: true,
      order: order
    });
  } catch (error) {
    console.error('Error creating order:', error);
    res.status(500).json({ error: error.message });
  }
});

app.post('/redeem-reward', async (req, res) => {
  try {
    console.log('🎁 [Stripe Server] Redeem reward request received');
    console.log('📥 Body:', req.body);

    const { userId, rewardTitle, rewardDescription, pointsRequired, rewardCategory } = req.body;

    if (!userId || !rewardTitle || !pointsRequired) {
      return res.status(400).json({
        error: 'Missing required fields: userId, rewardTitle, pointsRequired'
      });
    }

    if (!admin.apps.length) {
      console.error('⚠️ Firebase not initialized – cannot redeem reward');
      return res.status(500).json({ error: 'Firebase not configured' });
    }

    const db = admin.firestore();

    // Fetch current points
    const userRef = db.collection('users').doc(userId);
    const userSnap = await userRef.get();

    if (!userSnap.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    const userData = userSnap.data();
    const currentPoints = userData.points || 0;

    if (currentPoints < pointsRequired) {
      return res.status(400).json({
        error: 'Insufficient points for redemption',
        currentPoints,
        pointsRequired,
        pointsNeeded: pointsRequired - currentPoints
      });
    }

    // Generate 8-digit redemption code
    const redemptionCode = Math.floor(10000000 + Math.random() * 90000000).toString();

    const newBalance = currentPoints - pointsRequired;

    const redeemedReward = {
      id: `reward_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      userId,
      rewardTitle,
      rewardDescription: rewardDescription || '',
      rewardCategory: rewardCategory || 'General',
      pointsRequired,
      redemptionCode,
      redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + 15 * 60 * 1000), // 15 min expiry
      isExpired: false,
      isUsed: false
    };

    const pointsTransaction = {
      id: `deduction_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      userId,
      type: 'reward_redemption',
      amount: -pointsRequired,
      description: `Redeemed: ${rewardTitle}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isEarned: false,
      redemptionCode,
      rewardTitle
    };

    // Firestore batch
    const batch = db.batch();
    batch.update(userRef, { points: newBalance });
    batch.set(db.collection('redeemedRewards').doc(redeemedReward.id), redeemedReward);
    batch.set(db.collection('pointsTransactions').doc(pointsTransaction.id), pointsTransaction);

    await batch.commit();

    console.log('✅ Reward redeemed successfully via Stripe server');

    res.json({
      success: true,
      redemptionCode,
      newPointsBalance: newBalance,
      pointsDeducted: pointsRequired,
      rewardTitle,
      expiresAt: redeemedReward.expiresAt,
      message: 'Reward redeemed successfully! Show the code to your cashier.'
    });
  } catch (err) {
    console.error('❌ Error redeeming reward in Stripe server:', err);
    res.status(500).json({ error: 'Failed to redeem reward', details: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`🚀 Stripe server running on port ${PORT}`);
}); 