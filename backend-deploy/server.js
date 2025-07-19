require('dotenv').config();
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');
const { OpenAI } = require('openai');

// Initialize Stripe only if API key is available
let stripe = null;
if (process.env.STRIPE_SECRET_KEY) {
  stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
}

// Updated for Render deployment with latest OpenAI model
// ROOT SERVER.JS - USING GPT-4O MODEL
const app = express();
const upload = multer({ dest: 'uploads/' });
app.use(cors());
app.use(express.json());

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// Initialize Firebase Admin
const admin = require('firebase-admin');

// Check if Firebase credentials are available
if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('✅ Firebase Admin initialized successfully');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin:', error);
  }
} else {
  console.warn('⚠️ FIREBASE_SERVICE_ACCOUNT_KEY not found - Firebase features will not work');
}

// Health check endpoint
app.get('/', (req, res) => {
  res.json({ 
    status: 'Server is running!', 
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    server: 'DEPLOYED server.js with gpt-4o-mini',
    stripeConfigured: !!process.env.STRIPE_SECRET_KEY,
    firebaseConfigured: !!admin.apps.length,
    openaiConfigured: !!process.env.OPENAI_API_KEY
  });
});

// Generate personalized combo endpoint
app.post('/generate-combo', async (req, res) => {
  try {
    console.log('🤖 Received personalized combo request');
    console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
    
    const { userName, dietaryPreferences } = req.body;
    
    if (!userName || !dietaryPreferences) {
      console.log('❌ Missing required fields. Received:', { userName: !!userName, dietaryPreferences: !!dietaryPreferences });
      return res.status(400).json({ 
        error: 'Missing required fields: userName, dietaryPreferences',
        received: { userName: !!userName, dietaryPreferences: !!dietaryPreferences }
      });
    }
    
    // Use fallback static menu data since this is the deployed version
    console.log('🔍 Using fallback static menu data...');
    const allMenuItems = [
      // Dumplings
      { id: "No.9 Pork (12)", price: 13.99, description: "Classic pork dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      { id: "No.2 Pork & Chive (12)", price: 15.99, description: "Pork and chive dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      { id: "No.4 Pork Shrimp (12)", price: 16.99, description: "Pork and shrimp dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      { id: "No.5 Pork & Cabbage (12)", price: 14.99, description: "Pork and cabbage dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      { id: "No.3 Spicy Pork (12)", price: 14.99, description: "Spicy pork dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      { id: "No.7 Curry Chicken (12)", price: 12.99, description: "Curry chicken dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      { id: "No.8 Chicken & Coriander (12)", price: 13.99, description: "Chicken and coriander dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      { id: "No.1 Chicken & Mushroom (12)", price: 14.99, description: "Chicken and mushroom dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      { id: "No.10 Curry Beef & Onion (12)", price: 15.99, description: "Curry beef and onion dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      { id: "No.6 Veggie (12)", price: 13.99, description: "Vegetable dumplings", isDumpling: true, isDrink: false, category: "dumplings" },
      
      // Appetizers
      { id: "Edamame", price: 4.99, description: "Steamed soybeans", isDumpling: false, isDrink: false, category: "appetizers" },
      { id: "Asian Pickled Cucumbers", price: 5.75, description: "Pickled cucumbers", isDumpling: false, isDrink: false, category: "appetizers" },
      { id: "(Crab & Shrimp) Cold Noodle w/ Peanut Sauce", price: 8.35, description: "Cold noodles with peanut sauce", isDumpling: false, isDrink: false, category: "appetizers" },
      { id: "Peanut Butter Pork Dumplings", price: 7.99, description: "Peanut butter pork dumplings", isDumpling: false, isDrink: false, category: "appetizers" },
      { id: "Spicy Tofu", price: 5.99, description: "Spicy tofu", isDumpling: false, isDrink: false, category: "appetizers" },
      { id: "Curry Rice w/ Chicken", price: 7.75, description: "Curry rice with chicken", isDumpling: false, isDrink: false, category: "appetizers" },
      { id: "Jasmine White Rice", price: 2.75, description: "Jasmine white rice", isDumpling: false, isDrink: false, category: "appetizers" },
      { id: "Cold Tofu", price: 5.99, description: "Cold tofu", isDumpling: false, isDrink: false, category: "appetizers" },
      
      // Soups
      { id: "Hot & Sour Soup", price: 5.95, description: "Hot and sour soup", isDumpling: false, isDrink: false, category: "soups" },
      { id: "Pork Wonton Soup", price: 6.95, description: "Pork wonton soup", isDumpling: false, isDrink: false, category: "soups" },
      
      // Drinks
      { id: "Bubble Milk Tea w/ Tapioca", price: 5.90, description: "Bubble milk tea with tapioca", isDumpling: false, isDrink: true, category: "drinks" },
      { id: "Fresh Milk Tea", price: 5.90, description: "Fresh milk tea", isDumpling: false, isDrink: true, category: "drinks" },
      { id: "Capped Thai Brown Sugar", price: 6.90, description: "Capped Thai brown sugar milk tea", isDumpling: false, isDrink: true, category: "drinks" },
      { id: "Strawberry Fresh", price: 6.75, description: "Strawberry fresh milk tea", isDumpling: false, isDrink: true, category: "drinks" },
      { id: "Peach Fresh", price: 6.50, description: "Peach fresh milk tea", isDumpling: false, isDrink: true, category: "drinks" },
      { id: "Lychee Dragon Fruit", price: 6.50, description: "Lychee dragon fruit tea", isDumpling: false, isDrink: true, category: "drinks" },
      { id: "Peach Strawberry", price: 6.75, description: "Peach strawberry fruit tea", isDumpling: false, isDrink: true, category: "drinks" },
      { id: "Coffee Latte", price: 5.50, description: "Coffee latte", isDumpling: false, isDrink: true, category: "drinks" },
      { id: "Coke", price: 2.25, description: "Coca Cola", isDumpling: false, isDrink: true, category: "drinks" },
      { id: "Bottle Water", price: 1.00, description: "Bottle water", isDumpling: false, isDrink: true, category: "drinks" },
      
      // Sauces
      { id: "Peanut Sauce", price: 1.50, description: "Peanut sauce", isDumpling: false, isDrink: false, category: "sauces" },
      { id: "SPICY Peanut Sauce", price: 1.50, description: "Spicy peanut sauce", isDumpling: false, isDrink: false, category: "sauces" },
      { id: "Curry Sauce w/ Chicken", price: 1.50, description: "Curry sauce with chicken", isDumpling: false, isDrink: false, category: "sauces" }
    ];
    
    console.log(`🔍 Fetched ${allMenuItems.length} current menu items`);
    console.log(`🔍 Menu items:`, allMenuItems.map(item => `${item.id} (${item.isDumpling ? 'dumpling' : item.isDrink ? 'drink' : 'other'})`));
    console.log(`🔍 Dietary preferences:`, dietaryPreferences);
    
    // Create dietary restrictions string
    const restrictions = [];
    if (dietaryPreferences.hasPeanutAllergy) restrictions.push('peanut allergy');
    if (dietaryPreferences.isVegetarian) restrictions.push('vegetarian');
    if (dietaryPreferences.hasLactoseIntolerance) restrictions.push('lactose intolerant');
    if (dietaryPreferences.doesntEatPork) restrictions.push('no pork');
    if (dietaryPreferences.dislikesSpicyFood) restrictions.push('no spicy food');
    
    const restrictionsText = restrictions.length > 0 ? 
      `Dietary restrictions: ${restrictions.join(', ')}. ` : '';
    
    const spicePreference = dietaryPreferences.likesSpicyFood ? 
      'The customer enjoys spicy food. ' : '';
    
    // Create menu items text for AI - send the FULL current menu
    const menuText = `
Available menu items (current as of ${new Date().toLocaleString()}):

${allMenuItems.map(item => `- ${item.id}: $${item.price} - ${item.description} ${item.isDumpling ? '(dumpling)' : item.isDrink ? '(drink)' : ''}`).join('\n')}
    `.trim();
    
    // Create AI prompt that lets ChatGPT actually choose the items
    const prompt = `You are Dumpling Hero, a friendly AI assistant for a dumpling restaurant. 

Customer: ${userName}
${restrictionsText}${spicePreference}

${menuText}

IMPORTANT: You must choose items from the EXACT menu above. Do not make up items.

Please create a personalized combo for ${userName} with:
1. One dumpling option (choose from items marked as dumplings above)
2. One appetizer or side dish (choose from non-dumpling, non-drink items above)  
3. One drink (choose from items marked as drinks above)
4. Optionally one sauce or condiment (choose from items that seem like sauces/dips above) - only if it complements the combo well

Consider their dietary preferences and restrictions. The combo should be balanced and appealing.

IMPORTANT RULES:
- Choose items that actually exist in the menu above
- Consider dietary restrictions carefully
- Create variety - don't always choose the same items
- Consider flavor combinations that work well together
- Calculate the total price by adding up the prices of your chosen items
- For milk teas and coffees, note that milk substitutes (oat milk, almond milk, coconut milk) are available for lactose intolerant customers

Respond in this exact JSON format:
{
  "items": [
    {"id": "Exact Item Name from Menu", "category": "dumplings"},
    {"id": "Exact Item Name from Menu", "category": "appetizers"},
    {"id": "Exact Item Name from Menu", "category": "drinks"}
  ],
  "aiResponse": "A 3-sentence personalized response starting with the customer's name, explaining why you chose these items for them. Make them feel seen and understood.",
  "totalPrice": 0.00
}

Calculate the total price accurately. Keep the response warm and personal.`;
    
    console.log('🤖 Sending request to OpenAI...');
    
    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: "You are Dumpling Hero, a friendly AI assistant for a dumpling restaurant. Always respond with valid JSON in the exact format requested."
        },
        {
          role: "user",
          content: prompt
        }
      ],
      temperature: 0.7,
      max_tokens: 500
    });
    
    const aiResponse = completion.choices[0].message.content;
    console.log('🤖 AI Response:', aiResponse);
    
    // Parse AI response
    let comboData;
    try {
      comboData = JSON.parse(aiResponse);
    } catch (parseError) {
      console.error('❌ Failed to parse AI response:', parseError);
      return res.status(500).json({ 
        error: 'Failed to parse AI response',
        aiResponse: aiResponse 
      });
    }
    
    // Validate response structure
    if (!comboData.items || !comboData.aiResponse || typeof comboData.totalPrice !== 'number') {
      return res.status(500).json({ 
        error: 'Invalid AI response structure',
        aiResponse: aiResponse 
      });
    }
    
    console.log('✅ Generated personalized combo successfully');
    
    res.json(comboData);
    
  } catch (error) {
    console.error('❌ Error generating personalized combo:', error);
    res.status(500).json({ 
      error: 'Failed to generate personalized combo',
      details: error.message 
    });
  }
});

// Stripe checkout session endpoint
app.post('/create-checkout-session', async (req, res) => {
  try {
    if (!stripe) {
      return res.status(500).json({ 
        error: 'Stripe not configured - STRIPE_SECRET_KEY environment variable missing' 
      });
    }

    const { line_items } = req.body;
    console.log('🛒 Creating Stripe checkout session');
    console.log('Line items:', line_items);
    
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: line_items,
      mode: 'payment',
      success_url: 'restaurantdemo://success',
      cancel_url: 'restaurantdemo://cancel',
    });

    console.log('✅ Stripe session created:', session.id);
    res.json({ url: session.url });
    
  } catch (error) {
    console.error('❌ Error creating checkout session:', error);
    res.status(500).json({ error: error.message });
  }
});

// Success page that auto-redirects to app
app.get('/success', (req, res) => {
  const sessionId = req.query.session_id;
  console.log('🎉 Payment success for session:', sessionId);
  
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

const port = process.env.PORT || 3001;

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${port}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔑 OpenAI API Key configured: ${process.env.OPENAI_API_KEY ? 'Yes' : 'No'}`);
  console.log(`💳 Stripe configured: ${process.env.STRIPE_SECRET_KEY ? 'Yes' : 'No'}`);
  console.log(`🔥 Firebase configured: ${admin.apps.length ? 'Yes' : 'No'}`);
});
