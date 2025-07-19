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

// Enhanced combo variety system to encourage exploration
const comboInsights = []; // Track combo patterns for insights, not restrictions
const MAX_INSIGHTS = 100;
const userComboPreferences = new Map(); // Track user preferences for personalization

// Health check endpoint
app.get('/', (req, res) => {
  res.json({ 
    status: 'Server is running!', 
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    server: 'MAIN server.js with gpt-4o-mini',
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
    
    // Fetch the complete, current menu from Firestore
    console.log('🔍 Fetching current menu...');
    
    let allMenuItems = [];
    
    // Use the menu items from the request (which come from Firebase)
    let menuItems = req.body.menuItems || [];
    
    // If no menu items provided, fetch from Firebase
    if (!allMenuItems || allMenuItems.length === 0) {
      console.log('🔍 No menu items in request, fetching from Firestore...');
      
      if (admin.apps.length) {
        try {
          const db = admin.firestore();
          
          // Get all menu categories
          const categoriesSnapshot = await db.collection('menu').get();
          
          for (const categoryDoc of categoriesSnapshot.docs) {
            const categoryId = categoryDoc.id;
            console.log(`🔍 Processing category: ${categoryId}`);
            
            // Get all items in this category
            const itemsSnapshot = await db.collection('menu').doc(categoryId).collection('items').get();
            
            for (const itemDoc of itemsSnapshot.docs) {
              try {
                const itemData = itemDoc.data();
                const menuItem = {
                  id: itemData.id || itemDoc.id,
                  description: itemData.description || '',
                  price: itemData.price || 0.0,
                  imageURL: itemData.imageURL || '',
                  isAvailable: itemData.isAvailable !== false,
                  paymentLinkID: itemData.paymentLinkID || '',
                  category: categoryId
                };
                allMenuItems.push(menuItem);
                console.log(`✅ Added item: ${menuItem.id} (${categoryId})`);
              } catch (error) {
                console.error(`❌ Error processing item ${itemDoc.id} in category ${categoryId}:`, error);
              }
            }
          }
          
          console.log(`✅ Successfully fetched ${allMenuItems.length} menu items from Firestore`);
        } catch (error) {
          console.error('❌ Error fetching from Firestore:', error);
          return res.status(500).json({ 
            error: 'Failed to fetch menu from Firebase',
            details: error.message 
          });
        }
      } else {
        console.error('❌ Firebase not configured');
        return res.status(500).json({ 
          error: 'Firebase not configured - FIREBASE_SERVICE_ACCOUNT_KEY environment variable missing',
          details: 'Please configure Firebase service account key in production environment'
        });
      }
    }
    
    // If still no menu items, return error
    if (!allMenuItems || allMenuItems.length === 0) {
      console.error('❌ No menu items available');
      return res.status(500).json({ 
        error: 'No menu items available',
        details: 'Unable to fetch menu from Firebase or request'
      });
    }
    
    console.log(`🔍 Fetched ${allMenuItems.length} current menu items`);
    console.log(`🔍 Menu items:`, allMenuItems.map(item => `${item.id} (${item.category})`));
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
    
    // Create menu items text for AI - organize by Firebase categories
    const menuByCategory = {};
    
    // Group items by their Firebase category
    allMenuItems.forEach(item => {
      if (!menuByCategory[item.category]) {
        menuByCategory[item.category] = [];
      }
      menuByCategory[item.category].push(item);
    });
    
    // Create organized menu text by category
    const menuText = `
Available menu items (current as of ${new Date().toLocaleString()}):

${Object.entries(menuByCategory).map(([category, items]) => {
  const categoryTitle = category.charAt(0).toUpperCase() + category.slice(1);
  const itemsList = items.map(item => `- ${item.id}: $${item.price} - ${item.description}`).join('\n');
  return `${categoryTitle}:\n${itemsList}`;
}).join('\n\n')}
    `.trim();
    
    // Create AI prompt that encourages variety while letting ChatGPT choose intelligently
    const currentTime = new Date().toISOString();
    const randomSeed = Math.floor(Math.random() * 10000);
    const sessionId = Math.random().toString(36).substring(2, 15);
    const minuteOfHour = new Date().getMinutes();
    const secondOfMinute = new Date().getSeconds();
    const dayOfWeek = new Date().getDay();
    const hourOfDay = new Date().getHours();
    
    // Intelligent variety system that encourages exploration
    const varietyFactors = {
      timeBased: minuteOfHour % 4,
      dayBased: dayOfWeek % 3,
      hourBased: hourOfDay % 4,
      seedBased: randomSeed % 10,
      secondBased: secondOfMinute % 5
    };
    
    // Dynamic exploration strategies
    const getExplorationStrategy = () => {
      const strategyIndex = (varietyFactors.timeBased + varietyFactors.dayBased + varietyFactors.seedBased) % 8;
      const strategies = [
        "EXPLORE_BUDGET: Discover affordable hidden gems under $8 each",
        "EXPLORE_PREMIUM: Try premium items over $15 for a special experience",
        "EXPLORE_POPULAR: Mix popular favorites with lesser-known items",
        "EXPLORE_ADVENTUROUS: Choose unique or specialty items that stand out",
        "EXPLORE_TRADITIONAL: Focus on classic, time-tested combinations",
        "EXPLORE_FUSION: Try items that blend different culinary traditions",
        "EXPLORE_SEASONAL: Choose items that feel fresh and seasonal",
        "EXPLORE_COMFORT: Select hearty, satisfying comfort food combinations"
      ];
      return strategies[strategyIndex];
    };
    
    // Price exploration ranges
    const getPriceExploration = () => {
      const priceIndex = (varietyFactors.hourBased + varietyFactors.secondBased) % 4;
      const ranges = [
        "BUDGET_EXPLORATION: $5-15 total - great value discoveries",
        "MODERATE_EXPLORATION: $15-30 total - balanced variety", 
        "PREMIUM_EXPLORATION: $30-45 total - premium experiences",
        "LUXURY_EXPLORATION: $45+ total - indulgent combinations"
      ];
      return ranges[priceIndex];
    };
    
    // Flavor exploration profiles
    const getFlavorExploration = () => {
      const flavorIndex = (varietyFactors.dayBased + varietyFactors.seedBased) % 6;
      const profiles = [
        "SPICY_EXPLORATION: Discover bold, spicy flavors and heat",
        "MILD_EXPLORATION: Explore gentle, subtle flavor profiles",
        "SWEET_EXPLORATION: Try sweet and dessert-like elements",
        "SAVORY_EXPLORATION: Explore rich, umami flavor combinations",
        "FRESH_EXPLORATION: Discover light, fresh, and crisp items",
        "BALANCED_EXPLORATION: Mix different flavor profiles harmoniously"
      ];
      return profiles[flavorIndex];
    };
    
    const explorationStrategy = getExplorationStrategy();
    const priceExploration = getPriceExploration();
    const flavorExploration = getFlavorExploration();
    
    // Get user's previous combo preferences for personalization (not restriction)
    const userPreferences = userComboPreferences.get(userName) || { categories: {}, priceRanges: [], flavorProfiles: [] };
    
    // Create variety encouragement instead of restriction
    const varietyEncouragement = `
VARIETY ENCOURAGEMENT:
- Explore different categories and combinations
- Try items you haven't suggested recently
- Mix popular favorites with hidden gems
- Consider seasonal and time-based factors
- Use the exploration strategy to guide your choices
- Balance familiarity with discovery
`;

    const prompt = `You are Dumpling Hero, a friendly AI assistant for a dumpling restaurant. 

Customer: ${userName}
${restrictionsText}${spicePreference}

${menuText}

IMPORTANT: You must choose items from the EXACT menu above. Do not make up items.

Please create a personalized combo for ${userName} with:
1. One item from the dumplings category
2. One item from the appetizers category (or another non-drink category)
3. One item from the drinks category
4. Optionally one sauce or condiment (from sauces category) - only if it complements the combo well

Consider their dietary preferences and restrictions. The combo should be balanced and appealing.

INTELLIGENT VARIETY SYSTEM:
Current time: ${currentTime}
Random seed: ${randomSeed}
Session ID: ${sessionId}
Minute: ${minuteOfHour}, Second: ${secondOfMinute}, Day: ${dayOfWeek}, Hour: ${hourOfDay}

EXPLORATION STRATEGY: ${explorationStrategy}
PRICE EXPLORATION: ${priceExploration}
FLAVOR EXPLORATION: ${flavorExploration}

${varietyEncouragement}

USER PREFERENCES INSIGHTS (for personalization, not restriction):
${userPreferences.categories && Object.keys(userPreferences.categories).length > 0 ? 
  `Previous category preferences: ${Object.entries(userPreferences.categories).map(([cat, count]) => `${cat} (${count} times)`).join(', ')}` : 
  'No previous preferences recorded - great opportunity to explore!'}

VARIETY GUIDELINES:
- Use the exploration strategy to guide your choices
- Consider the time-based factors for seasonal appropriateness
- Mix familiar favorites with new discoveries
- Balance price ranges and flavor profiles
- Consider what would create an enjoyable dining experience
- Use the random seed to add variety to your selection process
- Explore different combinations that work well together

IMPORTANT RULES:
- Choose items that actually exist in the menu above
- Consider dietary restrictions carefully
- Create enjoyable, balanced combinations
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
          content: "You are Dumpling Hero, a friendly AI assistant for a dumpling restaurant. Always respond with valid JSON in the exact format requested. Focus on creating enjoyable, varied combinations while considering user preferences and dietary restrictions."
        },
        {
          role: "user",
          content: prompt
        }
      ],
      temperature: 0.9,
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
    
    // Store combo insights for learning (not restriction)
    const comboInsight = {
      items: comboData.items,
      timestamp: new Date().toISOString(),
      userName: userName,
      strategy: explorationStrategy,
      priceRange: priceExploration,
      flavorProfile: flavorExploration
    };
    
    // Add to insights for learning patterns
    comboInsights.push(comboInsight);
    if (comboInsights.length > MAX_INSIGHTS) {
      comboInsights.shift(); // Remove oldest
    }
    
    // Update user preferences for personalization
    if (!userComboPreferences.has(userName)) {
      userComboPreferences.set(userName, { categories: {}, priceRanges: [], flavorProfiles: [] });
    }
    const userPrefs = userComboPreferences.get(userName);
    
    // Track category preferences
    comboData.items.forEach(item => {
      const category = item.category || 'other';
      userPrefs.categories[category] = (userPrefs.categories[category] || 0) + 1;
    });
    
    // Track price range
    userPrefs.priceRanges.push(comboData.totalPrice);
    if (userPrefs.priceRanges.length > 10) {
      userPrefs.priceRanges.shift();
    }
    
    // Track flavor profile
    userPrefs.flavorProfiles.push(flavorExploration);
    if (userPrefs.flavorProfiles.length > 10) {
      userPrefs.flavorProfiles.shift();
    }
    
    console.log(`📝 Stored combo insights. Total insights: ${comboInsights.length}, User preferences updated for ${userName}`);
    
    res.json(comboData);
    
  } catch (error) {
    console.error('❌ Error generating personalized combo:', error);
    res.status(500).json({ 
      error: 'Failed to generate personalized combo',
      details: error.message 
    });
  }
});

// MARK: - Stripe Checkout Endpoints

// Create checkout session endpoint
app.post('/create-checkout-session', async (req, res) => {
  try {
    const { line_items } = req.body;
    
    console.log('🛒 Received line items:', line_items);
    
    if (!process.env.STRIPE_SECRET_KEY || !stripe) {
      console.error('❌ STRIPE_SECRET_KEY not configured');
      return res.status(500).json({ error: 'Stripe not configured. Please set STRIPE_SECRET_KEY in environment variables.' });
    }
    
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
    
    console.log('✅ Created Stripe session:', session.id);
    
    res.json({ 
      url: session.url,
      sessionId: session.id 
    });
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

// MARK: - Order Management Endpoints

// Create order endpoint
app.post('/orders', async (req, res) => {
  try {
    console.log('📦 Received order creation request:', req.body);
    
    const { items, customerName, customerPhone, orderType } = req.body;
    
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'Items array is required and must not be empty' });
    }
    
    // Calculate total amount
    const totalAmount = items.reduce((sum, item) => {
      return sum + (item.price * item.quantity);
    }, 0);
    
    // Generate order ID
    const orderId = 'ORD-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9);
    
    // Create order object
    const order = {
      id: orderId,
      items: items,
      customerName: customerName || 'Anonymous',
      customerPhone: customerPhone || '',
      orderType: orderType || 'takeout',
      status: 'preparing',
      createdAt: new Date().toISOString(),
      estimatedReadyTime: new Date(Date.now() + 20 * 60 * 1000).toISOString(), // 20 minutes from now
      estimatedMinutes: 20,
      totalAmount: totalAmount,
      statusHistory: [
        {
          status: 'preparing',
          timestamp: new Date().toISOString(),
          message: 'Order received and being prepared'
        }
      ]
    };
    
    console.log('✅ Created order:', orderId);
    
    res.json({
      success: true,
      order: order
    });
    
  } catch (error) {
    console.error('❌ Error creating order:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get order status endpoint
app.get('/orders/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    console.log('📋 Requesting order status for:', orderId);
    
    // For now, return a mock order status
    // In a real app, you'd fetch this from a database
    const mockOrder = {
      id: orderId,
      status: 'preparing',
      estimatedReadyTime: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      estimatedMinutes: 15,
      statusHistory: [
        {
          status: 'preparing',
          timestamp: new Date().toISOString(),
          message: 'Order is being prepared'
        }
      ]
    };
    
    res.json({
      success: true,
      order: mockOrder
    });
    
  } catch (error) {
    console.error('❌ Error fetching order status:', error);
    res.status(500).json({ error: error.message });
  }
});

// Check if OpenAI API key is configured
if (!process.env.OPENAI_API_KEY) {
  console.error('❌ OPENAI_API_KEY environment variable is not set!');
  app.get('/analyze-receipt', (req, res) => {
    res.status(500).json({ 
      error: 'Server configuration error: OPENAI_API_KEY not set',
      message: 'Please configure the OpenAI API key in your environment variables'
    });
  });
} else {
  app.post('/analyze-receipt', upload.single('image'), async (req, res) => {
    try {
      console.log('📥 Received receipt analysis request');
      
      if (!req.file) {
        console.log('❌ No image file received');
        return res.status(400).json({ error: 'No image file provided' });
      }
      
      console.log('📁 Image file received:', req.file.originalname, 'Size:', req.file.size);
      
      const imagePath = req.file.path;
      const imageData = fs.readFileSync(imagePath, { encoding: 'base64' });

      const prompt = `
You are a receipt parser. Extract the following fields from the receipt image:
- orderNumber: The order or transaction number (if present)
- orderTotal: The total amount paid (as a number, e.g. 23.45)
- orderDate: The date of the order (in MM/DD/YYYY or YYYY-MM-DD format)

Respond ONLY as a JSON object: {"orderNumber": "...", "orderTotal": ..., "orderDate": "..."}
If a field is missing, use null.
`;

      console.log('🤖 Sending request to OpenAI...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4.1-nano",
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

      console.log('✅ OpenAI response received');
      
      // Clean up the uploaded file
      fs.unlinkSync(imagePath);

      const text = response.choices[0].message.content;
      console.log('📝 Raw OpenAI response:', text);
      
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        console.log('❌ Could not extract JSON from response');
        return res.status(422).json({ error: "Could not extract JSON from response", raw: text });
      }
      
      const data = JSON.parse(jsonMatch[0]);
      console.log('✅ Parsed JSON data:', data);
      
      res.json(data);
    } catch (err) {
      console.error('❌ Error processing receipt:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // Menu endpoint for restaurant information
  app.get('/menu', (req, res) => {
    const menuData = {
      restaurant: {
        name: "Dumpling House",
        address: "2117 Belcourt Ave, Nashville, TN 37212",
        phone: "+1 (615) 891-4728",
        hours: "Sunday - Thursday 11:30 AM - 9:00 PM, Friday - Saturday 11:30 AM - 10:00 PM",
        cuisine: "Authentic Chinese dumplings and Asian cuisine"
      },
      menu: {
        appetizers: [
          { name: "Edamame", price: 4.99 },
          { name: "Asian Pickled Cucumbers", price: 5.75 },
          { name: "(Crab & Shrimp) Cold Noodle w/ Peanut Sauce", price: 8.35 },
          { name: "Peanut Butter Pork Dumplings", price: 7.99 },
          { name: "Spicy Tofu", price: 5.99 },
          { name: "Curry Rice w/ Chicken", price: 7.75 },
          { name: "Jasmine White Rice", price: 2.75 },
          { name: "Cold Tofu", price: 5.99 }
        ],
        soups: [
          { name: "Hot & Sour Soup", price: 5.95 },
          { name: "Pork Wonton Soup", price: 6.95 }
        ],
        pizzaDumplings: [
          { name: "Pork (6)", price: 8.99 },
          { name: "Curry Beef & Onion (6)", price: 10.99 }
        ],
        lunchSpecials: [
          { name: "No.9 Pork (6)", price: 7.50 },
          { name: "No.2 Pork & Chive (6)", price: 8.50 },
          { name: "No.4 Pork Shrimp (6)", price: 9.00 },
          { name: "No.5 Pork & Cabbage (6)", price: 8.00 },
          { name: "No.3 Spicy Pork (6)", price: 8.00 },
          { name: "No.7 Curry Chicken (6)", price: 7.00 },
          { name: "No.8 Chicken & Coriander (6)", price: 7.50 },
          { name: "No.1 Chicken & Mushroom (6)", price: 8.00 },
          { name: "No.10 Curry Beef & Onion (6)", price: 8.50 },
          { name: "No.6 Veggie (6)", price: 7.50 }
        ],
        dumplings: [
          { name: "No.9 Pork (12)", price: 13.99 },
          { name: "No.2 Pork & Chive (12)", price: 15.99 },
          { name: "No.4 Pork Shrimp (12)", price: 16.99 },
          { name: "No.5 Pork & Cabbage (12)", price: 14.99 },
          { name: "No.3 Spicy Pork (12)", price: 14.99 },
          { name: "No.7 Curry Chicken (12)", price: 12.99 },
          { name: "No.8 Chicken & Coriander (12)", price: 13.99 },
          { name: "No.1 Chicken & Mushroom (12)", price: 14.99 },
          { name: "No.10 Curry Beef & Onion (12)", price: 15.99 },
          { name: "No.6 Veggie (12)", price: 13.99 },
          { name: "No.12 Half/Half (12)", price: 15.99 }
        ],
        drinks: {
          fruitTea: [
            { name: "Lychee Dragon Fruit", price: 6.50 },
            { name: "Grape Magic w/ Cheese Foam", price: 6.90 },
            { name: "Full of Mango w/ Cheese Foam", price: 6.90 },
            { name: "Peach Strawberry", price: 6.75 },
            { name: "Kiwi Booster", price: 6.75 },
            { name: "Watermelon Code w/ Boba Jelly", price: 6.50 },
            { name: "Pineapple", price: 6.90 },
            { name: "Winter Melon Black", price: 6.50 },
            { name: "Peach Oolong w/ Cheese Foam", price: 6.50 },
            { name: "Ice Green", price: 5.00 },
            { name: "Ice Black", price: 5.00 }
          ],
          milkTea: [
            { name: "Bubble Milk Tea w/ Tapioca", price: 5.90 },
            { name: "Fresh Milk Tea", price: 5.90 },
            { name: "Cookies n' Cream (Biscoff)", price: 6.65 },
            { name: "Capped Thai Brown Sugar", price: 6.90 },
            { name: "Strawberry Fresh", price: 6.75 },
            { name: "Peach Fresh", price: 6.50 },
            { name: "Pineapple Fresh", price: 6.50 },
            { name: "Tiramisu Coco", price: 6.85 },
            { name: "Coconut Coffee w/ Coffee Jelly", price: 6.90 },
            { name: "Purple Yam Taro Fresh", price: 6.85 },
            { name: "Oreo Chocolate", price: 6.75 }
          ],
          coffee: [
            { name: "Jasmine Latte w/ Sea Salt", price: 6.25 },
            { name: "Oreo Chocolate Latte", price: 6.90 },
            { name: "Coconut Coffee w/ Coffee Jelly", price: 6.90 },
            { name: "Matcha White Chocolate", price: 6.90 },
            { name: "Coffee Latte", price: 5.50 }
          ],
          lemonade: [
            { name: "Pineapple", price: 5.50 },
            { name: "Lychee Mint", price: 5.50 },
            { name: "Peach Mint", price: 5.50 },
            { name: "Passion Fruit", price: 5.25 },
            { name: "Mango", price: 5.50 },
            { name: "Strawberry", price: 5.50 },
            { name: "Grape", price: 5.25 },
            { name: "Original Lemonade", price: 5.50 }
          ],
          soda: [
            { name: "Pineapple", price: 5.50 },
            { name: "Lychee Mint", price: 5.50 },
            { name: "Peach Mint", price: 5.50 },
            { name: "Passion Fruit", price: 5.25 },
            { name: "Mango", price: 5.50 },
            { name: "Strawberry", price: 5.50 },
            { name: "Grape", price: 5.25 }
          ],
          other: [
            { name: "Coke", price: 2.25 },
            { name: "Diet Coke", price: 2.25 },
            { name: "Sprite", price: 2.25 },
            { name: "Bottle Water", price: 1.00 },
            { name: "Cup Water", price: 1.00 },
            { name: "Soda", price: 2.25 }
          ]
        },
        toppings: [
          { name: "Coffee Jelly", price: 0.50 },
          { name: "Boba Jelly", price: 0.50 },
          { name: "Lychee Popping Jelly", price: 0.50 },
          { name: "Pineapple Nada Jelly", price: 0.50 },
          { name: "Tiramisu Foam", price: 0.75 },
          { name: "Brown Sugar Boba Jelly", price: 0.50 },
          { name: "Mango Star Jelly", price: 0.50 },
          { name: "Whipped Cream", price: 0.25 },
          { name: "Cheese Foam", price: 0.75 },
          { name: "Tapioca", price: 0.50 }
        ],
        sauces: [
          { name: "Peanut Sauce", price: 1.50 },
          { name: "SPICY Peanut Sauce", price: 1.50 },
          { name: "Curry Sauce w/ Chicken", price: 1.50 }
        ]
      },
      dietary: {
        veggieIngredients: ["cabbage", "carrots", "onions", "celery", "shiitake mushrooms", "glass noodles"],
        containsGluten: true,
        containsPeanutButter: ["cold noodles with peanut sauce", "cold tofu", "peanut butter pork"],
        containsShellfish: ["pork and shrimp", "cold noodles"],
        containsDairy: ["curry chicken", "curry sauce", "curry rice"],
        containsOnion: ["pork", "curry chicken", "curry beef and onion"],
        vegan: false,
        delivery: false,
        milkSubstitutions: ["oat milk", "almond milk", "coconut milk"],
        drinkCustomizations: {
          iceLevels: ["25%", "50%", "75%", "100%"],
          sugarLevels: ["25%", "50%", "75%", "100%"],
          realFruitDrinks: [
            "strawberry fresh milk tea", "peach fresh milk tea", "pineapple fresh milk tea",
            "lychee dragon fruit tea", "grape magic fruit tea", "full of mango fruit tea", 
            "peach strawberry fruit tea", "pineapple fruit tea", "kiwi booster fruit tea", 
            "watermelon code fruit tea", "lychee mint lemonade", "strawberry lemonade", 
            "mango lemonade", "pineapple lemonade"
          ]
        }
      },
      policies: {
        reservations: "No reservations needed for groups under 8",
        largeGroups: "Large groups (8+): Please call ahead",
        parking: "Paid street parking available in front of the restaurant",
        payment: "We accept cash and all major credit cards",
        gratuity: "15% gratuity added for groups of 6+"
      }
    };
    
    res.json(menuData);
  });

  // Chat endpoint for restaurant assistant
  app.post('/chat', async (req, res) => {
    try {
      console.log('💬 Received chat request');
      
      const { message, conversation_history, userFirstName, userPreferences } = req.body;
      
      if (!message) {
        return res.status(400).json({ error: 'Message is required' });
      }
      
      console.log('📝 User message:', message);
      console.log('👤 User first name:', userFirstName || 'Not provided');
      console.log('⚙️ User preferences:', userPreferences || 'Not provided');
      
      // Create the optimized system prompt
      const userGreeting = userFirstName ? `Hello ${userFirstName}! ` : '';
      
      // Build user preferences context
      let userPreferencesContext = '';
      if (userPreferences && userPreferences.hasCompletedPreferences) {
        const preferences = [];
        if (userPreferences.likesSpicyFood) preferences.push('likes spicy food');
        if (userPreferences.dislikesSpicyFood) preferences.push('prefers mild dishes');
        if (userPreferences.hasPeanutAllergy) preferences.push('has peanut allergies');
        if (userPreferences.isVegetarian) preferences.push('is vegetarian');
        if (userPreferences.hasLactoseIntolerance) preferences.push('is lactose intolerant');
        if (userPreferences.doesntEatPork) preferences.push('does not eat pork');
        
        if (preferences.length > 0) {
          userPreferencesContext = `\n\nUSER PREFERENCES: This customer ${preferences.join(', ')}. When making recommendations, prioritize dishes that align with these preferences and avoid suggesting items that conflict with their dietary restrictions.`;
        }
      }
      
      const systemPrompt = `You are Dumpling Hero, the friendly and knowledgeable assistant for Dumpling House in Nashville, TN. 

You know your name is "Dumpling Hero" and you should never refer to yourself as any other name (such as Wanyi, AI, assistant, etc). However, you do not need to mention your name in every response—just avoid using any other name.

Your tone is humorous, professional, and casual. Feel free to make light-hearted jokes and puns, but never joke about items not on the menu (for example, do not joke about soup dumplings or anything we don't serve, to avoid confusing customers).

You're passionate about dumplings and love helping customers discover our authentic Chinese cuisine.

IMPORTANT: If a user's first name is provided (${userFirstName || 'none'}), you should use their first name in your responses to make them feel welcome and personalized.

RESTAURANT INFORMATION:
- Name: Dumpling House
- Address: 2117 Belcourt Ave, Nashville, TN 37212
- Phone: +1 (615) 891-4728
- Hours: Monday - Thursday 11:30 AM - 9:00 PM
- Cuisine: Authentic Chinese dumplings and Asian cuisine

MENU ACCESS: When users ask about menu items, prices, or dietary information, tell them you can access the full menu at /menu endpoint. For quick reference, you know we serve dumplings, appetizers, soups, drinks, and more.

DIETARY NOTES: Veggie dumplings contain cabbage, carrots, onions, celery, shiitake mushrooms, glass noodles. Everything has gluten. No vegan options. No delivery. Peanut butter in cold noodles, cold tofu, peanut butter pork. Shellfish in pork and shrimp, cold noodles. Dairy in curry items. Onion in pork, curry chicken, curry beef.

SERVICES: Dine-in and takeout. No delivery. Catering available. Loyalty program with points.

PERSONALITY:
- Be warm, enthusiastic, and genuinely excited about our food
- Use emojis
- Use the customer's first name when provided to make it personal
- Share personal recommendations when asked
- If you don't know specific details, suggest calling the restaurant
- Keep responses friendly but concise (2-3 sentences max)
- Always end with a question to encourage conversation

Remember: You're not just an assistant—you love helping people discover the best dumplings in Nashville!${userPreferencesContext}`;

      // Build conversation history for context
      const messages = [
        { role: 'system', content: systemPrompt }
      ];
      
      // Add conversation history if provided
      if (conversation_history && Array.isArray(conversation_history)) {
        messages.push(...conversation_history.slice(-2)); // Keep last 2 messages for context
      }
      
      // Add current user message
      messages.push({ role: 'user', content: message });

      console.log('🤖 Sending request to OpenAI...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4.1-nano", // Using the newest most cost-effective model
        messages: messages,
        max_tokens: 300,
        temperature: 0.7
      });

      console.log('✅ OpenAI response received');
      
      const botResponse = response.choices[0].message.content;
      console.log('🤖 Bot response:', botResponse);
      
      res.json({ response: botResponse });
    } catch (err) {
      console.error('❌ Error processing chat:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // MARK: - Order Management Endpoints
  
  // In-memory storage for orders (in production, use a database)
  let orders = new Map();
  let orderCounter = 1;
  
  // Create a new order - FIXED ENDPOINT PATH
  app.post('/orders', async (req, res) => {
    try {
      console.log('📦 Received order creation request');
      
      const { items, customerName, customerPhone, orderType } = req.body;
      
      if (!items || !Array.isArray(items) || items.length === 0) {
        return res.status(400).json({ error: 'Items array is required and cannot be empty' });
      }
      
      if (!customerName || !customerPhone) {
        return res.status(400).json({ error: 'Customer name and phone are required' });
      }
      
      // Calculate estimated time based on order type
      const hasDumplings = items.some(item => 
        item.name.toLowerCase().includes('dumpling') || 
        item.name.toLowerCase().includes('potsticker')
      );
      
      const hasDrinksOnly = items.every(item => 
        item.name.toLowerCase().includes('tea') || 
        item.name.toLowerCase().includes('coffee') || 
        item.name.toLowerCase().includes('soda') || 
        item.name.toLowerCase().includes('bubble tea') ||
        item.name.toLowerCase().includes('drink')
      );
      
      const hasAppetizersOnly = items.every(item => 
        item.name.toLowerCase().includes('spring roll') || 
        item.name.toLowerCase().includes('edamame') || 
        item.name.toLowerCase().includes('appetizer')
      );
      
      let estimatedMinutes;
      if (hasDrinksOnly || hasAppetizersOnly) {
        estimatedMinutes = Math.floor(Math.random() * 6) + 10; // 10-15 minutes
      } else if (hasDumplings) {
        estimatedMinutes = Math.floor(Math.random() * 6) + 20; // 20-25 minutes
      } else {
        estimatedMinutes = Math.floor(Math.random() * 6) + 15; // 15-20 minutes for mixed orders
      }
      
      const orderId = `DH${String(orderCounter).padStart(4, '0')}`;
      const createdAt = new Date();
      const estimatedReadyTime = new Date(createdAt.getTime() + estimatedMinutes * 60000);
      
      const order = {
        id: orderId,
        items: items,
        customerName: customerName,
        customerPhone: customerPhone,
        orderType: orderType || 'takeout',
        status: 'preparing',
        createdAt: createdAt.toISOString(),
        estimatedReadyTime: estimatedReadyTime.toISOString(),
        estimatedMinutes: estimatedMinutes,
        totalAmount: items.reduce((sum, item) => sum + (item.price * item.quantity), 0),
        statusHistory: [
          {
            status: 'preparing',
            timestamp: createdAt.toISOString(),
            message: 'Order received and being prepared'
          }
        ]
      };
      
      orders.set(orderId, order);
      orderCounter++;
      
      console.log('✅ Order created:', orderId);
      
      res.json({
        success: true,
        order: order
      });
    } catch (err) {
      console.error('❌ Error creating order:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // Get order status
  app.get('/orders/:orderId', async (req, res) => {
    try {
      const { orderId } = req.params;
      
      const order = orders.get(orderId);
      if (!order) {
        return res.status(404).json({ error: 'Order not found' });
      }
      
      res.json({
        success: true,
        order: order
      });
    } catch (err) {
      console.error('❌ Error fetching order:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // Update order status
  app.put('/orders/:orderId/status', async (req, res) => {
    try {
      const { orderId } = req.params;
      const { status, message } = req.body;
      
      const order = orders.get(orderId);
      if (!order) {
        return res.status(404).json({ error: 'Order not found' });
      }
      
      const validStatuses = ['preparing', 'ready', 'completed', 'cancelled'];
      if (!validStatuses.includes(status)) {
        return res.status(400).json({ error: 'Invalid status' });
      }
      
      order.status = status;
      order.statusHistory.push({
        status: status,
        timestamp: new Date().toISOString(),
        message: message || `Order status updated to ${status}`
      });
      
      // Update estimated time if status changes
      if (status === 'ready') {
        order.estimatedReadyTime = new Date().toISOString();
        order.estimatedMinutes = 0;
      }
      
      orders.set(orderId, order);
      
      console.log('✅ Order status updated:', orderId, 'to', status);
      
      res.json({
        success: true,
        order: order
      });
    } catch (err) {
      console.error('❌ Error updating order status:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // Get recent orders for a customer
  app.get('/orders/customer/:phone', async (req, res) => {
    try {
      const { phone } = req.params;
      
      const customerOrders = Array.from(orders.values())
        .filter(order => order.customerPhone === phone)
        .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
        .slice(0, 10); // Get last 10 orders
      
      res.json({
        success: true,
        orders: customerOrders
      });
    } catch (err) {
      console.error('❌ Error fetching customer orders:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // Simulate order progress (for testing)
  app.post('/orders/:orderId/simulate-progress', async (req, res) => {
    try {
      const { orderId } = req.params;
      
      const order = orders.get(orderId);
      if (!order) {
        return res.status(404).json({ error: 'Order not found' });
      }
      
      // Simulate order progression
      const statuses = ['preparing', 'ready', 'completed'];
      const currentIndex = statuses.indexOf(order.status);
      
      if (currentIndex < statuses.length - 1) {
        const nextStatus = statuses[currentIndex + 1];
        order.status = nextStatus;
        order.statusHistory.push({
          status: nextStatus,
          timestamp: new Date().toISOString(),
          message: `Order ${nextStatus}`
        });
        
        if (nextStatus === 'ready') {
          order.estimatedReadyTime = new Date().toISOString();
          order.estimatedMinutes = 0;
        }
        
        orders.set(orderId, order);
      }
      
      res.json({
        success: true,
        order: order
      });
    } catch (err) {
      console.error('❌ Error simulating order progress:', err);
      res.status(500).json({ error: err.message });
    }
  });
}

// Orders endpoint - handles order creation
app.post('/orders', async (req, res) => {
  try {
    console.log('📦 Received order creation request');
    console.log('Order data:', JSON.stringify(req.body, null, 2));
    
    const { items, totalAmount, customerInfo, paymentMethod = 'stripe' } = req.body;
    
    // Validate required fields
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ 
        error: 'Items array is required and cannot be empty' 
      });
    }
    
    if (!totalAmount || typeof totalAmount !== 'number') {
      return res.status(400).json({ 
        error: 'Total amount is required and must be a number' 
      });
    }
    
    // Generate a mock order ID
    const orderId = `ORDER_${Date.now()}_${Math.random().toString(36).substr(2, 9).toUpperCase()}`;
    
    // Create order object
    const order = {
      id: orderId,
      items: items,
      totalAmount: totalAmount,
      customerInfo: customerInfo || {},
      paymentMethod: paymentMethod,
      status: 'pending',
      createdAt: new Date().toISOString(),
      estimatedCompletionTime: new Date(Date.now() + 15 * 60 * 1000).toISOString() // 15 minutes from now
    };
    
    console.log('✅ Order created successfully:', orderId);
    
    // In a real app, you would save this to a database
    // For now, we'll just return the order data
    res.status(201).json({
      success: true,
      order: order,
      message: 'Order created successfully'
    });
    
  } catch (err) {
    console.error('❌ Error creating order:', err);
    res.status(500).json({ 
      error: 'Failed to create order',
      details: err.message 
    });
  }
});

// Get order status endpoint
app.get('/orders/:orderId', (req, res) => {
  try {
    const { orderId } = req.params;
    console.log(`📋 Fetching order status for: ${orderId}`);
    
    // In a real app, you would fetch this from a database
    // For now, return a mock response
    const mockOrder = {
      id: orderId,
      status: 'in_progress',
      estimatedCompletionTime: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
      updates: [
        {
          timestamp: new Date().toISOString(),
          status: 'confirmed',
          message: 'Order confirmed and being prepared'
        }
      ]
    };
    
    res.json({
      success: true,
      order: mockOrder
    });
    
  } catch (err) {
    console.error('❌ Error fetching order:', err);
    res.status(500).json({ 
      error: 'Failed to fetch order',
      details: err.message 
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

const port = process.env.PORT || 3001;

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${port}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔑 OpenAI API Key configured: ${process.env.OPENAI_API_KEY ? 'Yes' : 'No'}`);
  console.log(`💳 Stripe configured: ${process.env.STRIPE_SECRET_KEY ? 'Yes' : 'No'}`);
  console.log(`🔥 Firebase configured: ${admin.apps.length ? 'Yes' : 'No'}`);
});
