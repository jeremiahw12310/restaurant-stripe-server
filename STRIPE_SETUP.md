# Stripe Setup Guide

## Firebase Functions Setup (Original Approach)

1. Install Firebase CLI:
```bash
npm install -g firebase-tools
```

2. Login to Firebase:
```bash
firebase login
```

3. Initialize Firebase Functions:
```bash
firebase init functions
```

4. Set Stripe secret key in Firebase config:
```bash
firebase functions:config:set stripe.secret="YOUR_STRIPE_SECRET_KEY"
```

5. Deploy functions:
```bash
firebase deploy --only functions
```

## Local Server Setup (Current Approach)

1. Install dependencies:
```bash
npm install express stripe cors
```

2. Set environment variable:
```bash
export STRIPE_SECRET_KEY="your_stripe_secret_key_here"
```

3. Run server:
```bash
node simple-stripe-server.js
```

## Environment Variables

Create a `.env` file in your project root:
```
STRIPE_SECRET_KEY=your_stripe_secret_key_here
```

## Deployment to Render.com

1. Push code to GitHub
2. Connect repository to Render
3. Set environment variables in Render dashboard
4. Deploy

## Prerequisites
- Stripe account (sign up at https://stripe.com)
- Firebase project with Functions enabled

## Step 1: Install Firebase Functions Dependencies

In your `functions` directory, run:
```bash
npm install
```

## Step 2: Set Up Stripe Configuration

1. Get your Stripe secret key from the Stripe Dashboard
2. Set up Firebase Functions configuration:

```bash
firebase functions:config:set stripe.secret="sk_test_your_stripe_secret_key_here"
firebase functions:config:set stripe.webhook_secret="whsec_your_webhook_secret_here"
```

## Step 3: Deploy Firebase Functions

```bash
firebase logout
firebase login
firebase deploy --only functions
```

## Step 4: Set Up Stripe Webhook (Optional but Recommended)

1. In your Stripe Dashboard, go to Webhooks
2. Add endpoint: `https://your-firebase-project.cloudfunctions.net/stripeWebhook`
3. Select events: `checkout.session.completed`, `payment_intent.succeeded`
4. Copy the webhook signing secret and update your Firebase config

## Step 5: Update iOS App URL Scheme

Add URL schemes to your iOS app's Info.plist:
- `restaurantdemo://success`
- `restaurantdemo://cancel`

## Step 6: Test the Integration

1. Add items to cart
2. Press "Proceed to Checkout"
3. Complete payment in Stripe Checkout
4. Verify success flow works

## Troubleshooting

### Common Issues:
1. **Firebase Functions not deployed**: Make sure to run `firebase deploy --only functions`
2. **Stripe key not set**: Verify your Stripe secret key is correctly set in Firebase config
3. **URL scheme not working**: Check that your app's URL schemes are properly configured

### Testing:
- Use Stripe's test card numbers (e.g., 4242 4242 4242 4242)
- Test both success and failure scenarios

## Security Notes

- Never expose your Stripe secret key in client-side code
- Always use Firebase Functions for server-side operations
- Consider adding user authentication before allowing payments
- Implement proper error handling and logging

## Next Steps

1. Add order management system
2. Implement inventory tracking
3. Add email confirmations
4. Set up analytics and reporting 