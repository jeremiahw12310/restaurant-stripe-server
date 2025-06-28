// This is your new secure backend.

// Import necessary tools
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');
const { OpenAI } = require('openai');
require('dotenv').config();

// Initialize the Firebase Admin SDK
admin.initializeApp();

// Get your Stripe secret key (we'll set this in the next step)
const stripe = require("stripe")(functions.config().stripe.secret);

const app = express();
const upload = multer({ dest: 'uploads/' });
app.use(cors());

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

/**
 * Creates a Stripe Payment Intent.
 * This function is called by your iOS app to securely start a payment process.
 */
exports.createPaymentIntent = functions.https.onCall(async (data, context) => {
  // Ensure the user is authenticated with Firebase Auth if you want extra security
  // if (!context.auth) {
  //   throw new functions.https.HttpsError(
  //     "unauthenticated",
  //     "You must be logged in to make a payment."
  //   );
  // }

  // Get the total amount from the data sent by the app
  const amount = data.amount;

  try {
    // In a real app, you might find or create a Stripe customer ID
    // associated with the Firebase user ID (context.auth.uid).
    // For now, we'll create a new temporary customer for each transaction.
    const customer = await stripe.customers.create();
    const ephemeralKey = await stripe.ephemeralKeys.create({
      customer: customer.id,
    }, {
      apiVersion: "2024-04-10", // Use a recent Stripe API version
    });

    // Create a Payment Intent with the order amount and currency
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount,
      currency: "usd",
      customer: customer.id,
      automatic_payment_methods: {
        enabled: true,
      },
    });

    // Send the necessary keys back to the app
    return {
      paymentIntent: paymentIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customer: customer.id,
    };
  } catch (error) {
    console.error("Stripe Error:", error);
    throw new functions.https.HttpsError("internal", "Unable to create payment intent");
  }
});

/**
 * Creates a Stripe Checkout Session.
 * This function is called by your iOS app to create a web-based checkout session.
 */
exports.createCheckoutSession = functions.https.onCall(async (data, context) => {
  // Ensure the user is authenticated with Firebase Auth if you want extra security
  // if (!context.auth) {
  //   throw new functions.https.HttpsError(
  //     "unauthenticated",
  //     "You must be logged in to make a payment."
  //   );
  // }

  const { lineItems, successUrl, cancelUrl } = data;

  try {
    // Create a Checkout Session
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: lineItems,
      mode: 'payment',
      success_url: successUrl || 'https://your-app.com/success',
      cancel_url: cancelUrl || 'https://your-app.com/cancel',
      automatic_tax: { enabled: true },
    });

    return {
      url: session.url,
      sessionId: session.id,
    };
  } catch (error) {
    console.error("Stripe Checkout Error:", error);
    throw new functions.https.HttpsError("internal", "Unable to create checkout session");
  }
});

/**
 * Webhook to handle successful payments
 */
exports.stripeWebhook = functions.https.onRequest(async (req, res) => {
  const sig = req.headers['stripe-signature'];
  const endpointSecret = functions.config().stripe.webhook_secret;

  let event;

  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret);
  } catch (err) {
    console.error('Webhook signature verification failed:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  // Handle the event
  switch (event.type) {
    case 'checkout.session.completed':
      const session = event.data.object;
      console.log('Payment successful for session:', session.id);
      // Here you would typically:
      // 1. Update your database to mark the order as paid
      // 2. Send confirmation emails
      // 3. Update inventory
      break;
    case 'payment_intent.succeeded':
      const paymentIntent = event.data.object;
      console.log('Payment intent succeeded:', paymentIntent.id);
      break;
    default:
      console.log(`Unhandled event type ${event.type}`);
  }

  res.json({ received: true });
});

app.post('/analyze-receipt', upload.single('image'), async (req, res) => {
  try {
    const imagePath = req.file.path;
    const imageData = fs.readFileSync(imagePath, { encoding: 'base64' });

    // Compose the prompt
    const prompt = `
You are a receipt parser. Extract the following fields from the receipt image:
- orderNumber: The order or transaction number (if present)
- orderTotal: The total amount paid (as a number, e.g. 23.45)
- orderDate: The date of the order (in MM/DD/YYYY or YYYY-MM-DD format)

Respond ONLY as a JSON object: {"orderNumber": "...", "orderTotal": ..., "orderDate": "..."}
If a field is missing, use null.
`;

    // Call OpenAI Vision
    const response = await openai.chat.completions.create({
      model: "gpt-4-vision-preview", // or "gpt-4o"
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageData}` } }
          ]
        }
      ],
      max_tokens: 300
    });

    fs.unlinkSync(imagePath);

    // Extract JSON from the response
    const text = response.choices[0].message.content;
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      return res.status(422).json({ error: "Could not extract JSON from response", raw: text });
    }
    const data = JSON.parse(jsonMatch[0]);
    // TODO: Check for duplicate orderNumber in your DB here if you want

    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3001, () => console.log('Server running on port 3001'));

