// This is your new secure backend.

// Import necessary tools
const admin = require("firebase-admin");
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');
const { OpenAI } = require('openai');
if (process.env.NODE_ENV !== 'production') {
  require('dotenv').config();
}
const { onCall, onRequest } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");

// Initialize the Firebase Admin SDK
admin.initializeApp();

// Get your Stripe secret key (we'll set this in the next step)
const stripe = require("stripe")(process.env.STRIPE_SECRET_KEY);

const app = express();
const upload = multer({ dest: 'uploads/' });
app.use(cors());

/**
 * Creates a Stripe Payment Intent.
 * This function is called by your iOS app to securely start a payment process.
 */
exports.createPaymentIntent = onCall(async (data, context) => {
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
exports.createCheckoutSession = onCall(async (data, context) => {
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

app.post('/analyze-receipt', upload.single('image'), async (req, res) => {
  try {
    // Initialize OpenAI client only when needed
    const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
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

/**
 * Firestore trigger to sync menu items array on parent document
 */
exports.syncMenuItemsArray = onDocumentWritten(
  'menu/{categoryId}/items/{itemId}',
  async (event) => {
    const admin = require('firebase-admin');
    const categoryId = event.params.categoryId;
    const categoryRef = admin.firestore().collection('menu').doc(categoryId);
    const itemsCollection = categoryRef.collection('items');
    try {
      console.log(`[syncMenuItemsArray] Triggered for category: ${categoryId}`);
      const snapshot = await itemsCollection.get();
      const itemsArray = [];
      snapshot.forEach(doc => {
        itemsArray.push(doc.data());
      });
      console.log(`[syncMenuItemsArray] Found ${itemsArray.length} items for category ${categoryId}`);
      await categoryRef.update({ items: itemsArray });
      console.log(`[syncMenuItemsArray] Updated items array for category ${categoryId}`);
    } catch (error) {
      console.error(`[syncMenuItemsArray] Error for category ${categoryId}:`, error);
    }
    return null;
  }
);

exports.api = onRequest(app);

