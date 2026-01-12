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

const app = express();
const upload = multer({ dest: 'uploads/' });
app.use(cors());

app.post('/analyze-receipt', upload.single('image'), async (req, res) => {
  try {
    // Initialize OpenAI client only when needed
    const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    const imagePath = req.file.path;
    const imageData = fs.readFileSync(imagePath, { encoding: 'base64' });

    // Compose the prompt
    const prompt = `You are a receipt parser for Dumpling House. Follow these STRICT validation rules:

VALIDATION RULES:
1. If there are NO words stating "Dumpling House" at the top of the receipt, return {"error": "Invalid receipt - must be from Dumpling House"}
2. If there is anything covering up numbers or text on the receipt, return {"error": "Invalid receipt - numbers are covered or obstructed"}
3. For DINE-IN orders: The order number is the BIGGER number inside the black box with white text. IGNORE any smaller numbers below the black box - those are NOT the order number.
4. For PICKUP orders: The order number is typically found near "Pickup" text and may not be in a black box.
5. The order number is ALWAYS next to the words "Walk In", "Dine In", or "Pickup" and found nowhere else
6. If the order number is more than 3 digits, it cannot be the order number - look for a smaller number
7. Order numbers CANNOT be greater than 400 - if you see a number over 400, it's not the order number
8. If the image quality is poor and numbers are blurry, unclear, or hard to read, return {"error": "Poor image quality - please take a clearer photo"}
9. ALWAYS return the date as MM/DD format only (no year, no other format)

EXTRACTION RULES:
- orderNumber: For dine-in orders, find the BIGGER number in the black box with white text (ignore smaller numbers below). For pickup orders, find the number near "Pickup". Must be 3 digits or less and cannot exceed 200.
- orderTotal: The total amount paid (as a number, e.g. 23.45)
- orderDate: The date in MM/DD format only (e.g. "12/25")

IMPORTANT: 
- On dine-in receipts, there may be a smaller number below the black box - this is NOT the order number. The order number is the bigger number inside the black box with white text.
- If you cannot clearly read the numbers due to poor image quality, DO NOT GUESS. Return an error instead.
- Order numbers must be between 1-400. Any number over 400 is invalid.

Respond ONLY as a JSON object: {"orderNumber": "...", "orderTotal": ..., "orderDate": "..."} or {"error": "error message"}
If a field is missing, use null.`;

    // Call OpenAI Vision
    const response = await openai.chat.completions.create({
      model: "gpt-4o-mini",
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
    
    // Check if the response contains an error
    if (data.error) {
      console.log('❌ Receipt validation failed:', data.error);
      return res.status(400).json({ error: data.error });
    }
    
    // Validate that we have the required fields
    if (!data.orderNumber || !data.orderTotal || !data.orderDate) {
      console.log('❌ Missing required fields in receipt data');
      return res.status(400).json({ error: "Could not extract all required fields from receipt" });
    }
    
    // Validate order number format (must be 3 digits or less and not exceed 400)
    const orderNumberStr = data.orderNumber.toString();
    if (orderNumberStr.length > 3) {
      console.log('❌ Order number too long:', orderNumberStr);
      return res.status(400).json({ error: "Invalid order number format" });
    }
    
    const orderNumber = parseInt(data.orderNumber);
    if (isNaN(orderNumber) || orderNumber < 1 || orderNumber > 400) {
      console.log('❌ Order number out of valid range (1-400):', orderNumber);
      return res.status(400).json({ error: "Invalid order number - must be between 1 and 400" });
    }
    
    // Validate date format (must be MM/DD)
    const dateRegex = /^\d{2}\/\d{2}$/;
    if (!dateRegex.test(data.orderDate)) {
      console.log('❌ Invalid date format:', data.orderDate);
      return res.status(400).json({ error: "Invalid date format - must be MM/DD" });
    }
    
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






