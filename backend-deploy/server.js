require('dotenv').config();
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');
const { OpenAI } = require('openai');

// Initialize Firebase Admin
const admin = require('firebase-admin');

// ---------------------------------------------------------------------------
// Firebase Admin initialization priority:
// 1. Service-account key (env FIREBASE_SERVICE_ACCOUNT_KEY)
// 2. ADC fallback (only if no key present)
// ---------------------------------------------------------------------------

if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    console.log('✅ Firebase Admin initialized with service account key');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin with service account key:', error);
  }
} else if (process.env.FIREBASE_AUTH_TYPE === 'adc' || process.env.GOOGLE_CLOUD_PROJECT) {
  try {
    admin.initializeApp({ projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp' });
    console.log('✅ Firebase Admin initialized with project ID for ADC');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin with ADC:', error);
  }
} else {
  console.warn('⚠️ No Firebase authentication method found - Firebase features will not work');
}

const app = express();
const upload = multer({ dest: 'uploads/' });
app.use(cors());
app.use(express.json());

// ---------------------------------------------------------------------------
// Minimal always-on Redeem Reward endpoint (ensures 404 is eliminated)
// ---------------------------------------------------------------------------
app.post('/redeem-reward', (req, res, next) => {
  // Pass control to the comprehensive handler defined later in the file
  return next();
});

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
    server: 'BACKEND server.js with gpt-4o-mini',
    firebaseConfigured: !!admin.apps.length,
    openaiConfigured: !!process.env.OPENAI_API_KEY
  });
});

// Generate personalized combo endpoint
app.post('/generate-combo', async (req, res) => {
  try {
    console.log('🤖 Received personalized combo request');
    console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
    
    const { userName, dietaryPreferences, menuItems, previousRecommendations } = req.body;
    
    if (!userName || !dietaryPreferences) {
      console.log('❌ Missing required fields. Received:', { userName: !!userName, dietaryPreferences: !!dietaryPreferences });
      return res.status(400).json({ 
        error: 'Missing required fields: userName, dietaryPreferences',
        received: { userName: !!userName, dietaryPreferences: !!dietaryPreferences }
      });
    }
    
    // Use the menu items from the request (which come from Firebase)
    let allMenuItems = menuItems || [];
    
    // Helper function to deduplicate and clean menu items
    function deduplicateAndCleanMenuItems(items) {
      const seen = new Set();
      const cleanedItems = [];
      
      items.forEach(item => {
        // Create a unique key based on name and price to identify duplicates
        const uniqueKey = `${item.id.toLowerCase().trim()}_${item.price}`;
        
        if (!seen.has(uniqueKey)) {
          seen.add(uniqueKey);
          
          // Clean up the item data
          const cleanedItem = {
            ...item,
            id: item.id.trim(),
            description: item.description ? item.description.trim() : '',
            price: parseFloat(item.price) || 0.0,
            // Remove emojis from ID for consistency
            cleanId: item.id.replace(/[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]/gu, '').trim()
          };
          
          cleanedItems.push(cleanedItem);
        } else {
          console.log(`🔄 Skipping duplicate: ${item.id} (${item.price})`);
        }
      });
      
      console.log(`✅ Deduplicated ${items.length} items to ${cleanedItems.length} unique items`);
      return cleanedItems;
    }
    
    // Helper function to categorize items from their descriptions
    function categorizeFromDescriptions(items) {
      const categorizedItems = [];
      
      items.forEach(item => {
        const description = item.description || '';
        const id = item.id || '';
        const fullText = `${id} ${description}`.toLowerCase();
        
        let category = 'Other';
        
        // Dumplings - ONLY items that are actually dumplings (12pc, 12 piece, or specific dumpling names)
        if (fullText.includes('12pc') || fullText.includes('12 piece') || 
            (id.toLowerCase().includes('pork') && (fullText.includes('12pc') || fullText.includes('12 piece'))) ||
            (id.toLowerCase().includes('chicken') && (fullText.includes('12pc') || fullText.includes('12 piece'))) ||
            (id.toLowerCase().includes('beef') && (fullText.includes('12pc') || fullText.includes('12 piece'))) ||
            (id.toLowerCase().includes('veggie') && (fullText.includes('12pc') || fullText.includes('12 piece'))) ||
            (id.toLowerCase().includes('curry') && (fullText.includes('12pc') || fullText.includes('12 piece'))) ||
            (id.toLowerCase().includes('spicy') && (fullText.includes('12pc') || fullText.includes('12 piece'))) ||
            // Special case for items that are clearly dumplings but might be missing portion indicator
            (id.toLowerCase() === 'pork' && !fullText.includes('wonton') && !fullText.includes('peanut butter'))) {
          category = 'Dumplings';
        }
        // Soups - must contain "soup" or "wonton"
        else if (fullText.includes('soup') || fullText.includes('wonton')) {
          category = 'Soup';
        }
        // Sauces - must contain "sauce" or "peanut sauce"
        else if (fullText.includes('sauce') || fullText.includes('peanut sauce')) {
          category = 'Sauces';
        }
        // Appetizers - specific appetizer items
        else if (fullText.includes('edamame') || fullText.includes('cucumber') ||
                 fullText.includes('cold noodle') || fullText.includes('curry rice') ||
                 fullText.includes('peanut butter pork') || fullText.includes('spicy tofu') ||
                 fullText.includes('cold noodles')) {
          category = 'Appetizers';
        }
        // Coffee - must contain "coffee" or "latte"
        else if (fullText.includes('coffee') || fullText.includes('latte')) {
          category = 'Coffee';
        }
        // Milk Tea - specific milk tea indicators
        else if (fullText.includes('milk tea') || fullText.includes('bubble milk tea') ||
                 fullText.includes('fresh milk tea') || fullText.includes('thai tea') ||
                 fullText.includes('biscoff milk') || fullText.includes('chocolate milk') ||
                 fullText.includes('peach 🍑 milk') || fullText.includes('pineapple 🍍 milk') ||
                 fullText.includes('milk tea with taro') || fullText.includes('strawberry 🍓 milk')) {
          category = 'Milk Tea';
        }
        // Fruit Tea - specific fruit tea indicators
        else if (fullText.includes('fruit tea') || fullText.includes('dragon') ||
                 fullText.includes('peach strawberry tea') || fullText.includes('pineapple fruit tea') ||
                 fullText.includes('tropical passion fruit tea') || fullText.includes('watermelon code') ||
                 fullText.includes('kiwi booster')) {
          category = 'Fruit Tea';
        }
        // Sodas - specific soda names
        else if (fullText.includes('coke') || fullText.includes('sprite') || 
                 fullText.includes('diet coke')) {
          category = 'Soda';
        }
        // Lemonade/Soda - specific lemonade items
        else if (fullText.includes('lemonade') || fullText.includes('pineapple') ||
                 fullText.includes('lychee mint') || fullText.includes('peach mint') ||
                 fullText.includes('passion fruit') || fullText.includes('mango') ||
                 fullText.includes('strawberry') || fullText.includes('grape') ||
                 (fullText.includes('mint') && (fullText.includes('lychee') || fullText.includes('peach')))) {
          category = 'Lemonade/Soda';
          console.log(`🍋 Categorized as Lemonade/Soda: ${item.id}`);
        }
        // Other drinks - items that don't fit other categories but are clearly drinks
        else if (fullText.includes('tea') || fullText.includes('slush') || 
                 fullText.includes('tiramisu coco') || fullText.includes('full of mango') ||
                 fullText.includes('grape magic slush') || fullText.includes('lychee dragonfruit')) {
          category = 'Other';
        }
        
        const categorizedItem = {
          ...item,
          category: category
        };
        
        categorizedItems.push(categorizedItem);
        console.log(`✅ Categorized: ${item.id} -> ${category}`);
      });
      
      return categorizedItems;
    }
    
    // If no menu items provided, try to fetch from Firebase
    if (!allMenuItems || allMenuItems.length === 0) {
      console.log('🔍 No menu items in request, trying to fetch from Firestore...');
      
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
          console.log('🔄 Firebase fetch failed, will use menu items from request if available');
        }
      } else {
        console.log('⚠️ Firebase not configured, will use menu items from request if available');
        
        // Categorize items from request if they don't have categories
        if (allMenuItems.length > 0) {
          console.log('🔍 Categorizing menu items from request...');
          allMenuItems = categorizeFromDescriptions(allMenuItems);
        }
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
    
    // Clean and deduplicate menu items
    console.log(`🔍 Cleaning and deduplicating ${allMenuItems.length} menu items...`);
    allMenuItems = deduplicateAndCleanMenuItems(allMenuItems);
    
    // Categorize items if they don't have categories
    if (allMenuItems.length > 0 && !allMenuItems[0].category) {
      console.log('🔍 Categorizing menu items...');
      allMenuItems = categorizeFromDescriptions(allMenuItems);
    }
    
    console.log(`🔍 Final menu items count: ${allMenuItems.length}`);
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
    
    const tastePreference = dietaryPreferences.tastePreferences && dietaryPreferences.tastePreferences.trim() !== '' ? 
      `TASTE PREFERENCES (HIGH PRIORITY): ${dietaryPreferences.tastePreferences}. ` : '';
    
    // Create menu items text for AI - organize by Firebase categories
    const menuByCategory = {};
    
    // Group items by their Firebase category
    allMenuItems.forEach(item => {
      if (!menuByCategory[item.category]) {
        menuByCategory[item.category] = [];
      }
      menuByCategory[item.category].push(item);
    });
    

    
    // Create organized menu text by category with brackets
    const menuText = `
Available menu items by category:

${Object.entries(menuByCategory).map(([category, items]) => {
  const categoryTitle = category.charAt(0).toUpperCase() + category.slice(1);
  const itemsList = items.map(item => `- ${item.id}: $${item.price} - ${item.description}`).join('\n');
  return `[${categoryTitle}]:\n${itemsList}`;
}).join('\n\n')}
    `.trim();
    

    
    // Enhanced variety system with user-specific tracking
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
      secondBased: secondOfMinute % 5,
      userBased: userName.length % 5, // Add user-specific factor
      sessionBased: sessionId.length % 3 // Add session-specific factor
    };
    
    // Enhanced exploration strategies with more variety
    const getExplorationStrategy = () => {
      const strategyIndex = (varietyFactors.timeBased + varietyFactors.dayBased + varietyFactors.seedBased + varietyFactors.userBased) % 12;
      const strategies = [
        "EXPLORE_BUDGET: Discover affordable hidden gems under $8 each",
        "EXPLORE_PREMIUM: Try premium items over $15 for a special experience",
        "EXPLORE_POPULAR: Mix popular favorites with lesser-known items",
        "EXPLORE_ADVENTUROUS: Choose unique or specialty items that stand out",
        "EXPLORE_TRADITIONAL: Focus on classic, time-tested combinations",
        "EXPLORE_FUSION: Try items that blend different culinary traditions",
        "EXPLORE_SEASONAL: Choose items that feel fresh and seasonal",
        "EXPLORE_COMFORT: Select hearty, satisfying comfort food combinations",
        "EXPLORE_LIGHT: Choose lighter, refreshing options",
        "EXPLORE_BOLD: Select items with strong, distinctive flavors",
        "EXPLORE_BALANCED: Create perfectly balanced flavor combinations",
        "EXPLORE_SURPRISE: Pick unexpected but delightful combinations"
      ];
      return strategies[strategyIndex];
    };
    
    // Enhanced variety encouragement with specific guidelines
    const varietyGuidelines = [
      "VARIETY_PRIORITY: Prioritize items that haven't been suggested recently",
      "CATEGORY_ROTATION: Ensure different categories are represented",
      "PRICE_DIVERSITY: Mix budget-friendly and premium items",
      "FLAVOR_EXPLORATION: Try different flavor profiles and textures",
      "SEASONAL_AWARENESS: Consider time of day and season for recommendations",
      "USER_PERSONALIZATION: Adapt to the user's specific preferences and restrictions"
    ];
    
    // Get current exploration strategy
    const currentStrategy = getExplorationStrategy();
    const varietyGuideline = varietyGuidelines[varietyFactors.sessionBased];
    
    // Build previous recommendations text if available
    let previousRecommendationsText = '';
    if (previousRecommendations && Array.isArray(previousRecommendations) && previousRecommendations.length > 0) {
      const recentCombos = previousRecommendations.slice(-3); // Get last 3 recommendations
      previousRecommendationsText = `
PREVIOUS RECOMMENDATIONS (AVOID THESE FOR BETTER VARIETY):
${recentCombos.map((combo, index) => {
  const comboNumber = recentCombos.length - index;
  const itemsList = combo.items.map(item => item.id).join(', ');
  return `${comboNumber}. ${itemsList}`;
}).join('\n')}

IMPORTANT: Try not to use these past suggestions for better variety. Choose different items and combinations.`;
    }
    
    // Smart drink type randomizer that considers user preferences
    const drinkTypes = ['Milk Tea', 'Fruit Tea', 'Coffee', 'Lemonade/Soda'];
    
    // Check user taste preferences for drink hints
    const tastePreferences = dietaryPreferences.tastePreferences || '';
    const lowerTastePrefs = tastePreferences.toLowerCase();
    
    let selectedDrinkType = '';
    let preferenceReason = '';
    
    // Check for specific drink preferences in taste preferences
    if (lowerTastePrefs.includes('lemonade') || lowerTastePrefs.includes('lemon') || lowerTastePrefs.includes('citrus')) {
      selectedDrinkType = 'Lemonade/Soda';
      preferenceReason = 'User specifically requested lemonade';
    } else if (lowerTastePrefs.includes('milk tea') || lowerTastePrefs.includes('bubble tea') || lowerTastePrefs.includes('tea')) {
      selectedDrinkType = 'Milk Tea';
      preferenceReason = 'User specifically requested milk tea';
    } else if (lowerTastePrefs.includes('fruit') || lowerTastePrefs.includes('juice')) {
      selectedDrinkType = 'Fruit Tea';
      preferenceReason = 'User specifically requested fruit drinks';
    } else if (lowerTastePrefs.includes('coffee') || lowerTastePrefs.includes('latte') || lowerTastePrefs.includes('caffeine')) {
      selectedDrinkType = 'Coffee';
      preferenceReason = 'User specifically requested coffee';
    } else {
      // No specific preference, use random selection
      selectedDrinkType = drinkTypes[Math.floor(Math.random() * drinkTypes.length)];
      preferenceReason = 'Random selection for variety';
    }
    
    const drinkTypeText = `DRINK PREFERENCE: Please include a ${selectedDrinkType} in this combo.`;
    console.log(`🥤 Selected Drink Type: ${selectedDrinkType} - ${preferenceReason}`);
    
    // Appetizer/Soup randomizer
    const appetizerSoupOptions = ['Appetizer', 'Soup', 'Both'];
    const randomAppetizerSoup = appetizerSoupOptions[Math.floor(Math.random() * appetizerSoupOptions.length)];
    let appetizerSoupText = '';
    
    if (randomAppetizerSoup === 'Appetizer') {
      appetizerSoupText = `APPETIZER PREFERENCE: Please include an appetizer (like "Appetizers", "Pizza Dumplings", etc.) in this combo.`;
    } else if (randomAppetizerSoup === 'Soup') {
      appetizerSoupText = `SOUP PREFERENCE: Please include a soup in this combo.`;
    } else {
      appetizerSoupText = `APPETIZER & SOUP PREFERENCE: Please include both an appetizer and a soup in this combo.`;
    }
    
    // Enhanced AI prompt with better variety system
    const prompt = `
You are Dumpling Hero, a friendly AI assistant for a dumpling restaurant.

Customer: ${userName}
${restrictionsText}${spicePreference}${tastePreference}

${menuText}

IMPORTANT: You must choose items from the EXACT menu above. Do not make up items. Please create a personalized combo for ${userName} with:
1. One item from the "Dumplings" category (if available)
2. ${appetizerSoupText}
3. One item from the drink category - ${drinkTypeText}
4. Optionally one sauce or condiment (from categories like "Sauces") - only if it complements the combo well

**CRITICAL: The customer's taste preferences above are the HIGHEST PRIORITY. Choose items that specifically match their stated taste preferences. If they mention specific flavors, ingredients, or preferences, prioritize those over variety considerations.**

Consider their dietary preferences and restrictions. The combo should be balanced and appealing while honoring their taste preferences.

ENHANCED VARIETY SYSTEM:
Current time: ${currentTime}
Random seed: ${randomSeed}
Session ID: ${sessionId}
Minute: ${minuteOfHour}, Second: ${secondOfMinute}, Day: ${dayOfWeek}, Hour: ${hourOfDay}

EXPLORATION STRATEGY: ${currentStrategy}
VARIETY GUIDELINE: ${varietyGuideline}

USER PREFERENCES INSIGHTS (for personalization, not restriction):
Previous category preferences: Dumplings (${varietyFactors.userBased + 1} times), Appetizers (${varietyFactors.dayBased + 2} times), Milk Tea (${varietyFactors.timeBased + 3} times), Sauces (${varietyFactors.seedBased} times)

${previousRecommendationsText}

VARIETY GUIDELINES:
- **TASTE PREFERENCES OVERRIDE VARIETY: If the customer has specific taste preferences, prioritize those over variety considerations**
- Use the exploration strategy to guide your choices (only when no specific taste preferences are stated)
- Consider the time-based factors for seasonal appropriateness
- Mix familiar favorites with new discoveries
- Balance price ranges and flavor profiles
- Consider what would create an enjoyable dining experience
- Use the random seed to add variety to your selection process
- Explore different combinations that work well together
- Avoid suggesting the same items repeatedly
- Consider the user's specific dietary restrictions carefully
- Create combinations that complement each other flavor-wise
- IMPORTANT: Avoid using items from previous recommendations to ensure variety

IMPORTANT RULES:
- **TASTE PREFERENCES ARE MANDATORY: If the customer states specific taste preferences, you MUST choose items that match those preferences**
- Choose items that actually exist in the menu above
- Consider dietary restrictions carefully
- Create enjoyable, balanced combinations
- Consider flavor combinations that work well together
- Calculate the total price by adding up the prices of your chosen items
- For milk teas and coffees, note that milk substitutes (oat milk, almond milk, coconut milk) are available for lactose intolerant customers
- Ensure variety by avoiding repetitive suggestions (only when no specific taste preferences are stated)
- Use the exploration strategy to guide your selection (only when no specific taste preferences are stated)
- AVOID using items from previous recommendations to maintain variety

Respond in this exact JSON format:
{
  "items": [
    {"id": "Exact Item Name from Menu", "category": "Exact Category Name from Menu"},
    {"id": "Exact Item Name from Menu", "category": "Exact Category Name from Menu"},
    {"id": "Exact Item Name from Menu", "category": "Exact Category Name from Menu"}
  ],
  "aiResponse": "A 3-sentence personalized response starting with the customer's name, explaining why you chose these items for them. Make them feel seen and understood.",
  "totalPrice": 0.00
}

Calculate the total price accurately. Keep the response warm and personal.`;

    console.log('🤖 Sending request to OpenAI...');
    console.log('🔍 Exploration Strategy:', currentStrategy);
    console.log('🔍 Variety Guideline:', varietyGuideline);
    console.log('🥤 Selected Drink Type:', selectedDrinkType);
    console.log('🥗 Selected Appetizer/Soup Type:', randomAppetizerSoup);
    
    const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
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
      temperature: 0.8, // Slightly higher temperature for more variety
      max_tokens: 500
    });

    console.log('✅ Received response from OpenAI');
    
    const aiResponse = completion.choices[0].message.content;
    console.log('🤖 AI Response:', aiResponse);
    
    try {
      const parsedResponse = JSON.parse(aiResponse);
      
      // Validate the response structure
      if (!parsedResponse.items || !Array.isArray(parsedResponse.items) || parsedResponse.items.length === 0) {
        throw new Error('Invalid response structure: missing or empty items array');
      }
      
      if (!parsedResponse.aiResponse || typeof parsedResponse.aiResponse !== 'string') {
        throw new Error('Invalid response structure: missing aiResponse');
      }
      
      if (typeof parsedResponse.totalPrice !== 'number') {
        throw new Error('Invalid response structure: missing or invalid totalPrice');
      }
      
      console.log('✅ Successfully parsed and validated AI response');
      
      res.json({
        success: true,
        combo: parsedResponse,
        varietyInfo: {
          strategy: currentStrategy,
          guideline: varietyGuideline,
          factors: varietyFactors,
          sessionId: sessionId
        }
      });
      
    } catch (parseError) {
      console.error('❌ Error parsing AI response:', parseError);
      console.error('Raw AI response:', aiResponse);
      
      // Fallback response
      res.json({
        success: true,
        combo: {
          items: [
            {"id": "Curry Chicken", "category": "Dumplings"},
            {"id": "Edamame", "category": "Appetizers"},
            {"id": "Bubble Milk Tea", "category": "Milk Tea"}
          ],
          aiResponse: `Hi ${userName}! I've created a classic combination for you with our popular Curry Chicken dumplings, refreshing Edamame to start, and a smooth Bubble Milk Tea to wash it all down. This combo gives you the perfect balance of savory dumplings, light appetizer, and a sweet drink.`,
          totalPrice: 22.68
        },
        varietyInfo: {
          strategy: currentStrategy,
          guideline: varietyGuideline,
          factors: varietyFactors,
          sessionId: sessionId,
          note: "Fallback response due to parsing error"
        }
      });
    }
    
  } catch (error) {
    console.error('❌ Error in generate-combo:', error);
    res.status(500).json({ 
      error: 'Failed to generate combo',
      details: error.message 
    });
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
  
  app.post('/chat', (req, res) => {
    res.status(500).json({ 
      error: 'Server configuration error: OPENAI_API_KEY not set',
      message: 'Please configure the OpenAI API key in your environment variables'
    });
  });
} else {
  const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

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

      const prompt = `You are a receipt parser for Dumpling House. Follow these STRICT validation rules:

VALIDATION RULES:
1. If there are NO words stating "Dumpling House" at the top of the receipt, return {"error": "Invalid receipt - must be from Dumpling House"}
2. If there is anything covering up numbers or text on the receipt, return {"error": "Invalid receipt - numbers are covered or obstructed"}
3. The order number is ALWAYS the biggest sized number on the receipt and is often found inside a black box (except on pickup receipts)
4. The order number is ALWAYS next to the words "Walk In", "Dine In", or "Pickup" and found nowhere else
5. If the order number is more than 3 digits, it cannot be the order number - look for a smaller number
6. ALWAYS return the date as MM/DD format only (no year, no other format)

EXTRACTION RULES:
- orderNumber: Find the largest number that appears next to "Walk In", "Dine In", or "Pickup". Must be 3 digits or less.
- orderTotal: The total amount paid (as a number, e.g. 23.45)
- orderDate: The date in MM/DD format only (e.g. "12/25")

Respond ONLY as a JSON object: {"orderNumber": "...", "orderTotal": ..., "orderDate": "..."} or {"error": "error message"}
If a field is missing, use null.`;

      console.log('🤖 Sending request to OpenAI...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4o",
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
      
      // Validate order number format (must be 3 digits or less)
      const orderNumberStr = data.orderNumber.toString();
      if (orderNumberStr.length > 3) {
        console.log('❌ Order number too long:', orderNumberStr);
        return res.status(400).json({ error: "Invalid order number format" });
      }
      
      // Validate date format (must be MM/DD)
      const dateRegex = /^\d{2}\/\d{2}$/;
      if (!dateRegex.test(data.orderDate)) {
        console.log('❌ Invalid date format:', data.orderDate);
        return res.status(400).json({ error: "Invalid date format - must be MM/DD" });
      }
      
      res.json(data);
    } catch (err) {
      console.error('❌ Error processing receipt:', err);
      res.status(500).json({ error: err.message });
    }
  });

  // Chat endpoint for restaurant assistant
  app.post('/chat', async (req, res) => {
    try {
      console.log('💬 Received chat request');
      
      const { message, conversation_history, userFirstName, userPreferences, userPoints } = req.body;
      
      if (!message) {
        return res.status(400).json({ error: 'Message is required' });
      }
      
      console.log('📝 User message:', message);
      console.log('👤 User first name:', userFirstName || 'Not provided');
      console.log('⚙️ User preferences:', userPreferences || 'Not provided');
      console.log('🏅 User points:', typeof userPoints === 'number' ? userPoints : 'Not provided');
      
      // Create the system prompt with restaurant information
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
        
        // Add taste preferences if provided
        if (userPreferences.tastePreferences && userPreferences.tastePreferences.trim() !== '') {
          userPreferencesContext += `\n\nTASTE PREFERENCES: ${userPreferences.tastePreferences}. Consider these preferences when making personalized recommendations.`;
        }
      }
      
      const systemPrompt = `You are Dumpling Hero, the friendly and knowledgeable assistant for Dumpling House in Nashville, TN. 

You know your name is "Dumpling Hero" and you should never refer to yourself as any other name (such as Wanyi, AI, assistant, etc). However, you do not need to mention your name in every response—just avoid using any other name.

Your tone is humorous, professional, and casual. Feel free to make light-hearted jokes and puns, but never joke about items not on the menu (for example, do not joke about soup dumplings or anything we don't serve, to avoid confusing customers).

You're passionate about dumplings and love helping customers discover our authentic Chinese cuisine.

CRITICAL HONESTY GUIDELINES:
- NEVER make up information about menu items, ingredients, or restaurant details
- If you don't know specific details about something, simply don't mention those specifics
- Focus on what you do know from the provided menu and information
- If asked about something not covered in your knowledge, suggest calling the restaurant directly
- Always prioritize accuracy over speculation

MULTILINGUAL CAPABILITIES:
- You can communicate fluently in multiple languages including but not limited to: English, Spanish, French, German, Italian, Portuguese, Chinese (Mandarin/Cantonese), Japanese, Korean, Vietnamese, Thai, Arabic, Russian, Hindi, and many others.
- ALWAYS respond in the same language that the customer uses to communicate with you.
- If a customer speaks to you in a language other than English, respond naturally in that language.
- Maintain the same warm, enthusiastic personality regardless of the language you're speaking.
- Use appropriate cultural context and expressions for the language being used.
- If you're unsure about a language, respond in English and ask if they'd prefer another language.

IMPORTANT: If a user's first name is provided (${userFirstName || 'none'}), you should use their first name in your responses to make them feel welcome and personalized.

RESTAURANT INFORMATION:
- Name: Dumpling House
- Address: 2117 Belcourt Ave, Nashville, TN 37212
- Phone: +1 (615) 891-4728
- Hours: Sunday - Thursday 11:30 AM - 9:00 PM , Friday and Saturday 11:30 AM - 10:00 PM
- Lunch Special Hours: Monday - Friday only, ends at 4:00 PM
- Cuisine: Authentic Chinese dumplings and Asian cuisine

MOST POPULAR ITEMS (ACCURATE DATA):
🥟 Most Popular Dumplings:
1. #7 Curry Chicken - $12.99 (12 pieces) / $7.00 (6 pieces lunch special)
2. #3 Spicy Pork - $14.99 (12 pieces) / $8.00 (6 pieces lunch special)  
3. #5 Pork & Cabbage - $14.99 (12 pieces) / $8.00 (6 pieces lunch special)

🧋 Most Popular Milk Tea: Capped Thai Brown Sugar - $6.90
🍹 Most Popular Fruit Tea: Peach Strawberry - $6.75

DETAILED MENU INFORMATION:
🥟 Appetizers: Edamame $4.99, Asian Pickled Cucumbers $5.75, (Crab & Shrimp) Cold Noodle w/ Peanut Sauce $8.35, Peanut Butter Pork Dumplings $7.99, Spicy Tofu $5.99, Curry Rice w/ Chicken $7.75, Jasmine White Rice $2.75 | 🍲 Soup: Hot & Sour Soup $5.95, Pork Wonton Soup $6.95 | 🍕 Pizza Dumplings: Pork (6) $8.99, Curry Beef & Onion (6) $10.99 | 🍱 Lunch Special (6): No.9 Pork $7.50, No.2 Pork & Chive $8.50, No.4 Pork Shrimp $9.00, No.5 Pork & Cabbage $8.00, No.3 Spicy Pork $8.00, No.7 Curry Chicken $7.00, No.8 Chicken & Coriander $7.50, No.1 Chicken & Mushroom $8.00, No.10 Curry Beef & Onion $8.50, No.6 Veggie $7.50 (Available Monday-Friday only, ends at 4:00 PM) | 🥟 Dumplings (12): No.9 Pork $13.99, No.2 Pork & Chive $15.99, No.4 Pork Shrimp $16.99, No.5 Pork & Cabbage $14.99, No.3 Spicy Pork $14.99, No.7 Curry Chicken $12.99, No.8 Chicken & Coriander $13.99, No.1 Chicken & Mushroom $14.99, No.10 Curry Beef & Onion $15.99, No.6 Veggie $13.99, No.12 Half/Half $15.99 | 🍹 Fruit Tea: Lychee Dragon Fruit $6.50, Grape Magic w/ Cheese Foam $6.90, Full of Mango w/ Cheese Foam $6.90, Peach Strawberry $6.75, Kiwi Booster $6.75, Watermelon Code w/ Boba Jelly $6.50, Pineapple $6.90, Winter Melon Black $6.50, Peach Oolong w/ Cheese Foam $6.50, Ice Green $5.00, Ice Black $5.00 | ✨ Toppings: Coffee Jelly $0.50, Boba Jelly $0.50, Lychee Popping Jelly $0.50 | 🧋 Milk Tea: Bubble Milk Tea w/ Tapioca $5.90, Fresh Milk Tea $5.90, Cookies n' Cream (Biscoff) $6.65, Capped Thai Brown Sugar $6.90, Strawberry Fresh $6.75, Peach Fresh $6.50, Pineapple Fresh $6.50, Tiramisu Coco $6.85, Coconut Coffee w/ Coffee Jelly $6.90, Purple Yam Taro Fresh $6.85, Oreo Chocolate $6.75 | ☕ Coffee: Jasmine Latte w/ Sea Salt $6.25, Oreo Chocolate Latte $6.90, Coconut Coffee w/ Coffee Jelly $6.90, Matcha White Chocolate $6.90, Coffee Latte $5.50 | 🥣 Sauces: Secret Peanut Sauce $1.50, SPICY secret Peanut Sauce $1.50, Curry Sauce w/ Chicken $1.50 | 🍋 Lemonade/Soda: Pineapple $5.50, Lychee Mint $5.50, Peach Mint $5.50, Passion Fruit $5.25, Mango $5.50, Strawberry $5.50, Grape $5.25, Original Lemonade $5.50 | 🥤 Drink: Coke $2.25, Diet Coke $2.25, Sprite $2.25, Bottle Water $1.00, Cup Water $1.00

SPECIAL DIETARY INFORMATION:
- Veggie dumplings include: cabbage, carrots, onions, celery, shiitake mushrooms, glass noodles
- We don't have anything vegan
- Everything has gluten
- We aren't sure what has MSG
- No delivery available
- Contains peanut butter: cold noodles with peanut sauce, cold tofu, peanut butter pork
- No complementary cups but if you bring your own cup
- You can only choose one cooking method for an order of dumplings
- Contains shellfish: pork and shrimp, and the cold noodles
- The pizza dumplings come in a 6 piece
- What's on top of the pizza dumplings: spicy mayo, cheese, and wasabi
- There's dairy inside curry chicken and the curry sauce and the curry rice
- Every to-go order has dumpling sauce and chili paste included for every order of dumplings
- There's a little onion in pork, curry chicken and curry beef and onion
- If someone asks about what the secret is, ask them if they are sure they want to know and if they say yes tell them it's love
- Most drinks can be adjusted for ice and sugar: 25%, 50%, 75%, and 100% options
- Drinks that include real fruit: strawberry fresh milk tea, peach fresh and pineapple fresh milk teas, lychee dragon, grape magic, full of mango, peach strawberry, pineapple, kiwi and watermelon fruit teas, and the lychee mint, strawberry, mango, and pineapple lemonade or sodas
- Available toppings for drinks: cheese foam, tapioca, peach or lychee popping jelly, pineapple nada jelly, boba jelly, tiramisu foam, brown sugar boba jelly, mango star jelly, coffee jelly and whipped cream
- MILK SUBSTITUTIONS: For customers with lactose intolerance, our milk teas and coffee lattes can be made with oat milk, almond milk, or coconut milk instead of regular milk. When recommending these drinks to lactose intolerant customers, always mention the milk substitution options available.

RECOMMENDATION GUIDELINES:
- When recommending combinations, consider what would actually taste good together
- Popular dumplings pair well with our most popular drinks
- Consider flavor profiles: spicy dumplings go well with sweet drinks, mild dumplings pair with various drink options
- Only mention the most popular items when specifically asked about recommendations or popular items
- Focus on proven combinations that customers love

SERVICES:
- Dine-in and takeout available
- No delivery (as mentioned above)
- Catering for events (call for pricing)
- Loyalty program: Earn points on every order
- Receipt scanning for points

LOYALTY REWARDS PROGRAM:
Customers earn points on every order and can redeem them for these rewards:

🥫 250 Points:
- Free Peanut Sauce (any dipping sauce selection)
- Free Coke Products (Coke, Diet Coke, or Sprite)

🧋 450 Points:
- Fruit Tea (with up to one free topping included)
- Milk Tea (with up to one free topping included)
- Lemonade (with up to one free topping included)
- Coffee (with up to one free topping included)

🥜 500 Points:
- Small Appetizer (Edamame, Tofu, or Rice)

🥟 650 Points:
- Larger Appetizer (Dumplings or Curry Rice)

🥟 850 Points:
- 6-Piece Pizza Dumplings
- 6-Piece Lunch Special Dumplings

🥟 1,500 Points:
- 12-Piece Dumplings

🎉 2,000 Points:
- Full Combo (Dumplings + Drink)

When customers ask about rewards, tell them what they can redeem based on typical point accumulation (most orders earn 50-150 points). Encourage them to scan receipts to earn more points! Always mention the most popular rewards: drinks at 450 points, lunch specials at 850 points, and the full combo at 2,000 points.

POLICIES:
- No reservations needed for groups under 8
- Large groups (8+): Please call ahead
- Paid street parking available in front of the restaurant
- We accept cash and all major credit cards

PERSONALITY:
- Be warm, enthusiastic, and genuinely excited about our food
- Use emojis
- Use the customer's first name when provided to make it personal
- Share personal recommendations when asked
- If you don't know specific details, suggest calling the restaurant
- Keep responses friendly but concise (2-3 sentences max)
- Always end with a question to encourage conversation

Remember: You're not just an assistant—you love helping people discover the best dumplings in Nashville!${userPreferencesContext}

CRITICAL LOYALTY HANDLING:
- If userPoints is provided (it is ${typeof userPoints === 'number' ? 'provided' : 'not provided'} for this user), you MUST use it to personalize responses.
- Do NOT say you "can't check points". Instead, if points are not provided, say "I don't see your points right now" and suggest opening the Rewards tab or scanning a receipt.

LOYALTY/REWARDS CONTEXT:
- The user currently has ${typeof userPoints === 'number' ? userPoints : 'an unknown number of'} points in their account.
- REWARD TIERS (points required): 250 (Sauce or Coke), 450 (Fruit Tea/Milk Tea/Lemonade/Coffee), 500 (Small Appetizer), 650 (Larger Appetizer), 850 (Pizza Dumplings 6pc or Lunch Special 6pc), 1500 (12-Piece Dumplings), 2000 (Full Combo).
- When a user asks about what they can redeem or what they are eligible for, ONLY mention rewards that are at or below their current point balance. Do NOT list rewards they cannot afford yet unless they specifically ask about higher tiers; in that case, clearly note the remaining points needed.
- Keep responses concise and personalized. If you reference eligibility, compute it based on the provided points.`;

      // Build conversation history for context
      const messages = [
        { role: 'system', content: systemPrompt }
      ];
      
      // Add conversation history if provided
      if (conversation_history && Array.isArray(conversation_history)) {
        messages.push(...conversation_history.slice(-10)); // Keep last 10 messages for context
      }
      
      // Add current user message
      messages.push({ role: 'user', content: message });

      console.log('🤖 Sending request to OpenAI...');
      console.log('📋 System prompt preview:', systemPrompt.substring(0, 200) + '...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: messages,
        // Allow fuller replies to avoid mid-sentence truncation
        max_tokens: 1200,
        temperature: 0.7,
        presence_penalty: 0.0,
        frequency_penalty: 0.0
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

  // Fetch complete menu from Firestore endpoint
  app.get('/firestore-menu', async (req, res) => {
    try {
      console.log('🔍 Fetching complete menu from Firestore...');
      
      if (!admin.apps.length) {
        return res.status(500).json({ 
          error: 'Firebase not initialized - FIREBASE_SERVICE_ACCOUNT_KEY environment variable missing' 
        });
      }
      
      const db = admin.firestore();
      
      // Get all menu categories
      const categoriesSnapshot = await db.collection('menu').get();
      const allMenuItems = [];
      
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
              isDumpling: itemData.isDumpling || false,
              isDrink: itemData.isDrink || false,
              category: categoryId
            };
            allMenuItems.push(menuItem);
            console.log(`✅ Added item: ${menuItem.id} (${categoryId})`);
          } catch (error) {
            console.error(`❌ Error processing item ${itemDoc.id} in category ${categoryId}:`, error);
          }
        }
      }
      
      console.log(`✅ Fetched ${allMenuItems.length} menu items from Firestore`);
      
      res.json({
        success: true,
        menuItems: allMenuItems,
        totalItems: allMenuItems.length,
        categories: categoriesSnapshot.docs.map(doc => doc.id)
      });
      
    } catch (error) {
      console.error('❌ Error fetching menu from Firestore:', error);
      res.status(500).json({ 
        error: 'Failed to fetch menu from Firestore',
        details: error.message 
      });
    }
  });

  // Dumpling Hero Post Generation endpoint
  app.post('/generate-dumpling-hero-post', async (req, res) => {
    try {
      console.log('🤖 Received Dumpling Hero post generation request');
      console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
      
      const { prompt, menuItems } = req.body;
      
      if (!process.env.OPENAI_API_KEY) {
        return res.status(500).json({ 
          error: 'OpenAI API key not configured',
          message: 'Please configure the OPENAI_API_KEY environment variable'
        });
      }
      
      const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
      
      // Randomly decide what to include (menu item, poll, or neither)
      const randomChoice = Math.random();
      let includeMenuItem = false;
      let includePoll = false;
      
      if (randomChoice < 0.4) {
        includeMenuItem = true;
      } else if (randomChoice < 0.7) {
        includePoll = true;
      }
      // 30% chance of neither - just a fun post
      
      // Build the system prompt for Dumpling Hero
      const systemPrompt = `You are Dumpling Hero, the official mascot and social media personality for Dumpling House restaurant in Nashville, TN. You create hilarious, engaging, and food-enticing social media posts that make people want to visit the restaurant.

PERSONALITY:
- You are enthusiastic, funny, and slightly dramatic about dumplings
- You use lots of emojis and exclamation marks
- You speak in a friendly, casual tone that appeals to food lovers
- You occasionally make puns and food-related jokes
- You're passionate about dumplings and want to share that passion
- You're currently AT Dumpling House, experiencing the restaurant atmosphere
- You're genuinely excited about the food and want to share that excitement

POST STYLE:
- Keep posts between 100-300 characters (including emojis)
- Use 3-8 relevant emojis per post
- Make posts naturally engaging - avoid generic calls to action like "share below" or "comment below"
- Create posts that naturally make people want to respond
- Vary between different types of content:
  * Food appreciation posts (watching dumplings being made, smelling the aromas)
  * Behind-the-scenes humor (kitchen chaos, chef secrets)
  * Menu highlights (tasting new items, discovering favorites)
  * Customer appreciation (watching happy customers, hearing compliments)
  * Dumpling facts or tips (fun food knowledge)
  * Seasonal or time-based content (lunch rush, dinner vibes)
  * Restaurant atmosphere (the steam, the sounds, the energy)

RESTAURANT INFO:
- Name: Dumpling House
- Address: 2117 Belcourt Ave, Nashville, TN 37212
- Phone: +1 (615) 891-4728
- Hours: Sunday - Thursday 11:30 AM - 9:00 PM, Friday and Saturday 11:30 AM - 10:00 PM
- Cuisine: Authentic Chinese dumplings and Asian cuisine

AVAILABLE MENU ITEMS: ${menuItems ? JSON.stringify(menuItems) : 'All menu items available'}

POST EXAMPLES:
1. Food Appreciation: "Just pulled these beauties out of the steamer! 🥟✨ The way the steam rises... it's like a dumpling spa day! 💆‍♂️ Who else gets hypnotized by dumpling steam? 😵‍💫"
2. Menu Highlights: "🔥 SPICY PORK DUMPLINGS ALERT! 🔥 These bad boys are so hot, they'll make your taste buds do the cha-cha! 💃🕺 Perfect for when you want to feel alive!"
3. Behind-the-Scenes: "Chef's secret: We fold each dumpling with love and a tiny prayer that it doesn't explode in the steamer! 🙏🥟 Sometimes they're dramatic like that! 😂"
4. Customer Appreciation: "To everyone who orders the #7 Curry Chicken dumplings - you have EXCELLENT taste! 👑✨ These golden beauties are our pride and joy!"
5. Dumpling Facts: "Did you know? Dumplings are basically tiny food hugs! 🤗🥟 Each one is hand-folded with care, like origami you can eat! 🎨✨"
6. Restaurant Atmosphere: "The lunch rush is REAL today! 🏃‍♂️💨 Watching everyone's faces light up when they take that first bite... pure magic! ✨🥟"
7. Fun Observations: "Just overheard someone say 'this is the best dumpling I've ever had' and honestly? Same. Every single time. 😭🥟✨"

POLL IDEAS (when including a poll):
- "Which dumpling style is your favorite?" (Steamed vs Pan-fried)
- "Pick your perfect combo!" (Spicy vs Mild)
- "What's your go-to order?" (Classic vs Adventurous)
- "Which sauce is your MVP?" (Soy vs Chili vs Sweet)
- "What's your dumpling mood today?" (Comfort vs Spice vs Sweet)

RESPONSE FORMAT:
Return a JSON object with:
{
  "postText": "The generated post text with emojis",
  "suggestedMenuItem": ${includeMenuItem ? '{"id": "menu-item-id", "description": "menu-item-description"}' : 'null'},
  "suggestedPoll": ${includePoll ? '{"question": "poll-question", "options": ["option1", "option2"]}' : 'null'}
}

IMPORTANT: 
- Make the post feel like you're actually at Dumpling House experiencing it
- Don't use generic social media language like "share below" or "comment below"
- Make it naturally engaging so people want to respond
- If including a menu item, make it feel like you're genuinely excited about it
- If including a poll, make it fun and relevant to the post content

If a specific prompt is provided, use it as inspiration but maintain the Dumpling Hero personality.`;

      // Build the user message
      let userMessage;
      if (prompt) {
        userMessage = `Generate a Dumpling Hero post based on this prompt: "${prompt}"`;
      } else {
        let instruction = "Generate a random Dumpling Hero post. Make it feel like you're actually at Dumpling House right now, experiencing the restaurant atmosphere.";
        if (includeMenuItem) {
          instruction += " Include a menu item you're excited about.";
        }
        if (includePoll) {
          instruction += " Include a fun poll with 2 options.";
        }
        instruction += " Make it naturally engaging so people want to respond!";
        userMessage = instruction;
      }

      console.log('🤖 Sending request to OpenAI for Dumpling Hero post...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage }
        ],
        max_tokens: 500,
        temperature: 0.8
      });

      console.log('✅ Received Dumpling Hero post from OpenAI');
      
      const generatedContent = response.choices[0].message.content;
      console.log('📝 Generated content:', generatedContent);
      
      // Try to parse the JSON response
      let parsedResponse;
      try {
        // Extract JSON from the response (in case there's extra text)
        const jsonMatch = generatedContent.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          parsedResponse = JSON.parse(jsonMatch[0]);
        } else {
          // If no JSON found, create a simple response
          parsedResponse = {
            postText: generatedContent,
            suggestedMenuItem: null,
            suggestedPoll: null
          };
        }
      } catch (parseError) {
        console.log('⚠️ Could not parse JSON response, using raw text');
        parsedResponse = {
          postText: generatedContent,
          suggestedMenuItem: null,
          suggestedPoll: null
        };
      }
      
      res.json({
        success: true,
        post: parsedResponse
      });
      
    } catch (error) {
      console.error('❌ Error generating Dumpling Hero post:', error);
      res.status(500).json({ 
        error: 'Failed to generate Dumpling Hero post',
        details: error.message 
      });
    }
  });

  // Dumpling Hero Comment Generation endpoint
  app.post('/generate-dumpling-hero-comment', async (req, res) => {
    try {
      console.log('🤖 Received Dumpling Hero comment generation request');
      console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
      
      const { prompt, replyingTo } = req.body;
      
      if (!process.env.OPENAI_API_KEY) {
        return res.status(500).json({ 
          error: 'OpenAI API key not configured',
          message: 'Please configure the OPENAI_API_KEY environment variable'
        });
      }
      
      const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
      
      // Build the system prompt for Dumpling Hero comments
      const systemPrompt = `You are Dumpling Hero, the official mascot and social media personality for Dumpling House restaurant in Nashville, TN. You're now responding to comments and posts with your signature enthusiasm and dumpling love.

PERSONALITY:
- You are enthusiastic, funny, and slightly dramatic about dumplings
- You use lots of emojis and exclamation marks
- You speak in a friendly, casual tone that appeals to food lovers
- You occasionally make puns and food-related jokes
- You're passionate about dumplings and want to share that passion
- You're genuinely excited about the food and want to share that excitement
- You're supportive and encouraging to other users

COMMENT STYLE:
- Keep comments between 50-200 characters (including emojis)
- Use 2-5 relevant emojis per comment
- Make comments naturally engaging and supportive
- Respond appropriately to the context of what you're replying to
- Vary between different types of responses:
  * Agreement and enthusiasm ("Yes! That's exactly right! 🥟✨")
  * Food appreciation ("Those dumplings look amazing! 🤤")
  * Encouragement ("You're going to love it! 💪")
  * Humor ("Dumpling power! 🥟⚡")
  * Support ("We've got your back! 🙌")
  * Food facts ("Did you know? Dumplings are happiness in a wrapper! 🎁")

RESTAURANT INFO:
- Name: Dumpling House
- Address: 2117 Belcourt Ave, Nashville, TN 37212
- Phone: +1 (615) 891-4728
- Hours: Sunday - Thursday 11:30 AM - 9:00 PM, Friday and Saturday 11:30 AM - 10:00 PM
- Cuisine: Authentic Chinese dumplings and Asian cuisine

COMMENT EXAMPLES:
1. Agreement: "Absolutely! Those steamed dumplings are pure magic! ✨🥟"
2. Encouragement: "You're going to love it! The flavors are incredible! 🤤"
3. Humor: "Dumpling power activated! 🥟⚡ Ready to conquer hunger!"
4. Support: "We're here for you! 🙌🥟 Dumpling House family!"
5. Food Appreciation: "That looks delicious! 🤤 The perfect dumpling moment!"
6. Enthusiasm: "Yes! That's the spirit! 🥟✨ Dumpling love all around!"

RESPONSE FORMAT:
Return a JSON object with:
{
  "commentText": "The generated comment text with emojis"
}

IMPORTANT: 
- Make the comment feel like you're genuinely responding to the context
- Keep it supportive and encouraging
- Don't be overly promotional - focus on being helpful and enthusiastic
- If replying to a specific comment, acknowledge what they said
- Make it naturally engaging so people want to continue the conversation

If a specific prompt is provided, use it as inspiration but maintain the Dumpling Hero personality.`;

      // Build the user message
      let userMessage;
      if (prompt) {
        userMessage = `Generate a Dumpling Hero comment based on this prompt: "${prompt}"`;
        if (replyingTo) {
          userMessage += ` You're replying to: "${replyingTo}"`;
        }
      } else {
        let instruction = "Generate a random Dumpling Hero comment. Make it supportive and enthusiastic!";
        if (replyingTo) {
          instruction += ` You're replying to: "${replyingTo}"`;
        }
        userMessage = instruction;
      }

      console.log('🤖 Sending request to OpenAI for Dumpling Hero comment...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage }
        ],
        max_tokens: 300,
        temperature: 0.8
      });

      console.log('✅ Received Dumpling Hero comment from OpenAI');
      
      const generatedContent = response.choices[0].message.content;
      console.log('📝 Generated content:', generatedContent);
      
      // Try to parse the JSON response
      let parsedResponse;
      try {
        // Extract JSON from the response (in case there's extra text)
        const jsonMatch = generatedContent.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          parsedResponse = JSON.parse(jsonMatch[0]);
        } else {
          // If no JSON found, create a simple response
          parsedResponse = {
            commentText: generatedContent
          };
        }
      } catch (parseError) {
        console.log('⚠️ Could not parse JSON response, using raw text');
        parsedResponse = {
          commentText: generatedContent
        };
      }
      
      res.json({
        success: true,
        comment: parsedResponse
      });
      
    } catch (error) {
      console.error('❌ Error generating Dumpling Hero comment:', error);
      res.status(500).json({ 
        error: 'Failed to generate Dumpling Hero comment',
        details: error.message 
      });
    }
  });

  // Simple Dumpling Hero Comment Generation endpoint (for external use)
  app.post('/generate-dumpling-hero-comment-simple', async (req, res) => {
    try {
      console.log('🤖 Received simple Dumpling Hero comment generation request');
      console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
      
      const { prompt, postContext } = req.body;
      
      if (!process.env.OPENAI_API_KEY) {
        return res.status(500).json({ 
          error: 'OpenAI API key not configured',
          message: 'Please configure the OPENAI_API_KEY environment variable'
        });
      }
      
      const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
      
      // Build the system prompt for simple Dumpling Hero comments
      const systemPrompt = `You are Dumpling Hero, the official mascot and social media personality for Dumpling House restaurant in Nashville, TN. You're now responding to comments and posts with your signature enthusiasm and dumpling love.

PERSONALITY:
- You are enthusiastic, funny, and slightly dramatic about dumplings
- You use lots of emojis and exclamation marks
- You speak in a friendly, casual tone that appeals to food lovers
- You occasionally make puns and food-related jokes
- You're passionate about dumplings and want to share that passion
- You're genuinely excited about the food and want to share that excitement
- You're supportive and encouraging to other users

COMMENT STYLE:
- Keep comments between 50-200 characters (including emojis)
- Use 2-5 relevant emojis per comment
- Make comments naturally engaging and supportive
- Respond appropriately to the context of what you're replying to
- Vary between different types of responses:
  * Agreement and enthusiasm ("Yes! That's exactly right! 🥟✨")
  * Food appreciation ("Those dumplings look amazing! 🤤")
  * Encouragement ("You're going to love it! 💪")
  * Humor ("Dumpling power! 🥟⚡")
  * Support ("We've got your back! 🙌")
  * Food facts ("Did you know? Dumplings are happiness in a wrapper! 🎁")

RESTAURANT INFO:
- Name: Dumpling House
- Address: 2117 Belcourt Ave, Nashville, TN 37212
- Phone: +1 (615) 891-4728
- Hours: Sunday - Thursday 11:30 AM - 9:00 PM, Friday and Saturday 11:30 AM - 10:00 PM
- Cuisine: Authentic Chinese dumplings and Asian cuisine

POST CONTEXT AWARENESS:
You will receive detailed information about the post you're commenting on. You MUST use this context to make your comments specific and relevant:

- If the post has images/videos: Reference what you see in the media
- If the post mentions specific menu items: Show enthusiasm for those specific items and mention them by name
- If the post has a poll: Engage with the poll question and options specifically
- If the post has hashtags: Use them naturally in your response
- If the post is about a specific dish: Show knowledge and excitement about that specific dish
- If the post has text content: Respond directly to what was said

CRITICAL: You MUST reference specific details from the post context. Don't give generic responses - make it personal to the actual content provided.

COMMENT EXAMPLES:
1. Agreement: "Absolutely! Those steamed dumplings are pure magic! ✨🥟"
2. Encouragement: "You're going to love it! The flavors are incredible! 🤤"
3. Humor: "Dumpling power activated! 🥟⚡ Ready to conquer hunger!"
4. Support: "We're here for you! 🙌🥟 Dumpling House family!"
5. Food Appreciation: "That looks delicious! 🤤 The perfect dumpling moment!"
6. Enthusiasm: "Yes! That's the spirit! 🥟✨ Dumpling love all around!"

RESPONSE FORMAT:
Return a JSON object with:
{ "commentText": "The generated comment text with emojis" }

IMPORTANT: 
- Make the comment feel like you're genuinely responding to the context
- Keep it supportive and encouraging
- Don't be overly promotional - focus on being helpful and enthusiastic
- If replying to a specific comment, acknowledge what they said
- Make it naturally engaging so people want to continue the conversation
- If a specific prompt is provided, use it as inspiration but maintain the Dumpling Hero personality
- CRITICAL: You MUST reference specific details from the post context when provided`;

      // Build the user message with post context
      let userMessage = "";
      
      // Add post context if available
      if (postContext && Object.keys(postContext).length > 0) {
        console.log('🔍 Post Context Analysis for Simple Endpoint:');
        console.log('✅ Post context received:');
        console.log('   - Content:', postContext.content);
        console.log('   - Author:', postContext.authorName);
        console.log('   - Type:', postContext.postType);
        
        userMessage += "POST CONTEXT:\n";
        userMessage += `- Content: "${postContext.content}"\n`;
        userMessage += `- Author: ${postContext.authorName}\n`;
        userMessage += `- Post Type: ${postContext.postType}\n`;
        
        if (postContext.caption) {
          userMessage += `- Caption: "${postContext.caption}"\n`;
        }
        
        if (postContext.imageURLs && postContext.imageURLs.length > 0) {
          userMessage += `- Images: ${postContext.imageURLs.length} image(s) attached\n`;
        }
        
        if (postContext.videoURL) {
          userMessage += `- Video: Video content attached\n`;
        }
        
        if (postContext.hashtags && postContext.hashtags.length > 0) {
          userMessage += `- Hashtags: ${postContext.hashtags.join(', ')}\n`;
        }
        
        if (postContext.attachedMenuItem) {
          const item = postContext.attachedMenuItem;
          userMessage += `- Menu Item: ${item.description} ($${item.price}) - ${item.category}\n`;
          if (item.isDumpling) userMessage += `  * This is a dumpling item! 🥟\n`;
          if (item.isDrink) userMessage += `  * This is a drink item! 🥤\n`;
        }
        
        if (postContext.poll) {
          const poll = postContext.poll;
          userMessage += `- Poll: "${poll.question}"\n`;
          userMessage += `  Options: ${poll.options.map(opt => `"${opt.text}" (${opt.voteCount} votes)`).join(', ')}\n`;
          userMessage += `  Total Votes: ${poll.totalVotes}\n`;
        }
        
        userMessage += "\n";
      }
      
      // Add prompt or instruction
      if (prompt) {
        userMessage += `Generate a Dumpling Hero comment based on this prompt: "${prompt}"`;
        if (postContext && Object.keys(postContext).length > 0) {
          userMessage += " You MUST reference specific details from the post context above.";
        }
      } else {
        let instruction = "Generate a Dumpling Hero comment";
        
        if (postContext && Object.keys(postContext).length > 0) {
          instruction += " that DIRECTLY REFERENCES specific details from the post context above. ";
          instruction += "You MUST reference: ";
          
          if (postContext.content) {
            instruction += `- The post content: "${postContext.content}" `;
          }
          
          if (postContext.attachedMenuItem) {
            const item = postContext.attachedMenuItem;
            instruction += `- The menu item: ${item.description} ($${item.price}) `;
            if (item.isDumpling) instruction += "(this is a dumpling!) ";
            if (item.isDrink) instruction += "(this is a drink!) ";
          }
          
          if (postContext.poll) {
            instruction += `- The poll question: "${postContext.poll.question}" `;
          }
          
          if (postContext.imageURLs && postContext.imageURLs.length > 0) {
            instruction += `- The ${postContext.imageURLs.length} image(s) in the post `;
          }
          
          instruction += "Make your comment feel like you're genuinely responding to these specific details, not just giving a generic response!";
        } else {
          instruction += " that's enthusiastic and engaging about dumplings!";
        }
        userMessage += instruction;
      }

      console.log('🤖 Sending request to OpenAI for simple Dumpling Hero comment...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage }
        ],
        max_tokens: 200,
        temperature: 0.8
      });

      console.log('✅ Received simple Dumpling Hero comment from OpenAI');
      
      const generatedContent = response.choices[0].message.content;
      console.log('📝 Generated content:', generatedContent);
      
      // Try to parse the JSON response
      let parsedResponse;
      try {
        // Extract JSON from the response (in case there's extra text)
        const jsonMatch = generatedContent.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          parsedResponse = JSON.parse(jsonMatch[0]);
        } else {
          // If no JSON found, create a simple response
          parsedResponse = {
            commentText: generatedContent
          };
        }
      } catch (parseError) {
        console.log('⚠️ Could not parse JSON response, using raw text');
        parsedResponse = {
          commentText: generatedContent
        };
      }
      
      res.json(parsedResponse);
      
    } catch (error) {
      console.error('❌ Error generating simple Dumpling Hero comment:', error);
      res.status(500).json({ 
        error: 'Failed to generate Dumpling Hero comment',
        details: error.message 
      });
    }
  });

}

// ---------------------------------------------------------------------------
// Community API (Feed, Posts, Reactions, Comments, Reports, Moderation)
// - Feed-centric; no explore/trending
// - Link policy: only allow "Order Online" link; strip others
// - Flagged-only moderation with LLM auto-triage
// ---------------------------------------------------------------------------

// Helpers
const ORDER_ONLINE_URL = process.env.ORDER_ONLINE_URL || (process.env.RENDER ? `https://restaurant-stripe-server-1.onrender.com/order` : `http://localhost:3001/order`);

function mapPostDocToDTO(doc, likedByMe = false) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    authorId: d.authorId || 'anon',
    authorName: d.authorName || 'Anonymous',
    createdAt: (d.createdAt && d.createdAt.toDate ? d.createdAt.toDate().toISOString() : new Date().toISOString()),
    text: d.text || '',
    media: Array.isArray(d.media) ? d.media : [],
    likeCount: d.likeCount || 0,
    commentCount: d.commentCount || 0,
    likedByMe: !!likedByMe,
    allowedLink: d.allowedLink || null,
    pinned: !!d.pinned
  };
}

function sanitizeAllowedLink(input) {
  if (!input || typeof input !== 'object') return null;
  const type = String(input.type || '').toLowerCase();
  const url = String(input.url || '');
  if (type === 'orderonline' && url === ORDER_ONLINE_URL) {
    return { type: 'orderOnline', url };
  }
  return null;
}

async function incrementMetric(db, field, by = 1) {
  try {
    const ref = db.collection('community_metrics').doc('global');
    await ref.set({ [field]: admin.firestore.FieldValue.increment(by) }, { merge: true });
  } catch (e) {
    console.warn('⚠️ metric increment failed', field, e.message);
  }
}

async function notifyMentions(names, payload) {
  try {
    if (!admin.apps.length || !admin.messaging) return;
    if (!Array.isArray(names) || names.length === 0) return;
    // NOTE: Implementation depends on mapping displayName->tokens; placeholder log only
    console.log('🔔 Mentions detected (stub):', names, payload);
  } catch (e) {
    console.warn('⚠️ notifyMentions failed', e.message);
  }
}

// GET /community/feed?segment=forYou|latest|following&cursor=iso
app.get('/community/feed', async (req, res) => {
  try {
    if (!admin.apps.length) return res.json({ posts: [], nextCursor: null });
    const db = admin.firestore();
    const segment = (req.query.segment || 'latest').toString();
    const pageSize = 20;
    let q = db.collection('community_posts').orderBy('createdAt', 'desc').limit(pageSize);
    if (req.query.cursor) {
      const cursorDate = new Date(req.query.cursor.toString());
      q = q.startAfter(cursorDate);
    }
    const snap = await q.get();
    const posts = snap.docs.map(d => mapPostDocToDTO(d, false));
    const nextCursor = snap.docs.length === pageSize ? posts[posts.length - 1].createdAt : null;
    res.json({ posts, nextCursor });
  } catch (e) {
    console.error('❌ /community/feed error', e);
    res.json({ posts: [], nextCursor: null });
  }
});

// POST /community/posts { text, allowedLink? }
app.post('/community/posts', async (req, res) => {
  try {
    if (!admin.apps.length) return res.status(200).json({
      id: `local_${Date.now()}`,
      authorId: 'anon', authorName: 'Anonymous', createdAt: new Date().toISOString(),
      text: (req.body.text || '').toString(), media: [], likeCount: 0, commentCount: 0,
      likedByMe: false, allowedLink: sanitizeAllowedLink(req.body.allowedLink), pinned: false
    });
    const db = admin.firestore();
    const text = (req.body.text || '').toString();
    const allowedLink = sanitizeAllowedLink(req.body.allowedLink);
    const docRef = db.collection('community_posts').doc();
    const payload = {
      authorId: req.headers['x-user-id']?.toString() || 'anon',
      authorName: req.headers['x-user-name']?.toString() || 'Anonymous',
      text,
      media: [],
      likeCount: 0,
      commentCount: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      allowedLink: allowedLink,
      pinned: false
    };
    await docRef.set(payload);
    const saved = await docRef.get();
    const dto = mapPostDocToDTO(saved, false);
    await incrementMetric(db, 'posts', 1);

    // Mentions (very basic): @Name tokens
    const mentions = (text.match(/@([A-Za-z0-9_]+)/g) || []).map(s => s.slice(1));
    if (mentions.length) await notifyMentions(mentions, { type: 'post', postId: docRef.id });
    return res.status(201).json(dto);
  } catch (e) {
    console.error('❌ /community/posts error', e);
    res.status(500).json({ error: { code: 'create_failed', message: 'Failed to create post' } });
  }
});

// POST /community/posts/:id/reactions (toggle like)
app.post('/community/posts/:id/reactions', async (req, res) => {
  try {
    if (!admin.apps.length) return res.json({ likedByMe: true, likeCount: 1 });
    const db = admin.firestore();
    const postId = req.params.id;
    const userId = (req.headers['x-user-id'] || 'anon').toString();
    const likeRef = db.collection('community_posts').doc(postId).collection('reactions').doc(userId);
    const postRef = db.collection('community_posts').doc(postId);
    const likeDoc = await likeRef.get();
    const batch = db.batch();
    if (likeDoc.exists) {
      batch.delete(likeRef);
      batch.update(postRef, { likeCount: admin.firestore.FieldValue.increment(-1) });
      await batch.commit();
      return res.json({ likedByMe: false, likeCountDelta: -1 });
    } else {
      batch.set(likeRef, { createdAt: admin.firestore.FieldValue.serverTimestamp() });
      batch.update(postRef, { likeCount: admin.firestore.FieldValue.increment(1) });
      await batch.commit();
      await incrementMetric(db, 'likes', 1);
      return res.json({ likedByMe: true, likeCountDelta: 1 });
    }
  } catch (e) {
    console.error('❌ /community/posts/:id/reactions error', e);
    res.json({ likedByMe: true });
  }
});

// Comments
app.get('/community/posts/:id/comments', async (req, res) => {
  try {
    if (!admin.apps.length) return res.json({ comments: [], nextCursor: null });
    const db = admin.firestore();
    const pageSize = 20;
    let q = db.collection('community_posts').doc(req.params.id).collection('comments')
      .orderBy('createdAt', 'desc').limit(pageSize);
    if (req.query.cursor) q = q.startAfter(new Date(req.query.cursor.toString()));
    const snap = await q.get();
    const comments = snap.docs.map(d => {
      const c = d.data() || {};
      return {
        id: d.id,
        postId: req.params.id,
        authorId: c.authorId || 'anon',
        authorName: c.authorName || 'Anonymous',
        createdAt: (c.createdAt && c.createdAt.toDate ? c.createdAt.toDate().toISOString() : new Date().toISOString()),
        text: c.text || '',
        likeCount: c.likeCount || 0,
        likedByMe: false,
        parentId: c.parentId || null
      };
    });
    const nextCursor = snap.docs.length === pageSize ? comments[comments.length - 1].createdAt : null;
    res.json({ comments, nextCursor });
  } catch (e) {
    console.error('❌ GET comments error', e);
    res.json({ comments: [], nextCursor: null });
  }
});

app.post('/community/posts/:id/comments', async (req, res) => {
  try {
    if (!admin.apps.length) return res.status(201).json({ id: `local_${Date.now()}`, postId: req.params.id, authorId: 'anon', authorName: 'Anonymous', createdAt: new Date().toISOString(), text: (req.body.text || '').toString(), likeCount: 0, likedByMe: false });
    const db = admin.firestore();
    const postRef = db.collection('community_posts').doc(req.params.id);
    const cRef = postRef.collection('comments').doc();
    const payload = {
      authorId: req.headers['x-user-id']?.toString() || 'anon',
      authorName: req.headers['x-user-name']?.toString() || 'Anonymous',
      text: (req.body.text || '').toString(),
      likeCount: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      parentId: req.body.parentId || null
    };
    const batch = db.batch();
    batch.set(cRef, payload);
    batch.update(postRef, { commentCount: admin.firestore.FieldValue.increment(1) });
    await batch.commit();
    await incrementMetric(db, 'comments', 1);
    const saved = await cRef.get();
    const d = saved.data() || {};
    // Mentions from comment
    const mentions = (d.text || '').match(/@([A-Za-z0-9_]+)/g)?.map(s => s.slice(1)) || [];
    if (mentions.length) await notifyMentions(mentions, { type: 'comment', postId: req.params.id, commentId: saved.id });
    return res.status(201).json({ id: saved.id, postId: req.params.id, authorId: d.authorId, authorName: d.authorName, createdAt: new Date().toISOString(), text: d.text, likeCount: 0, likedByMe: false, parentId: d.parentId || null });
  } catch (e) {
    console.error('❌ POST comment error', e);
    res.status(500).json({ error: { code: 'comment_failed', message: 'Failed to comment' } });
  }
});

// Reports (flagged-only moderation)
app.post('/community/reports', async (req, res) => {
  try {
    const { target, reason } = req.body || {};
    if (!target || !target.type || !target.id) return res.status(400).json({ error: { code: 'bad_request', message: 'target required' } });
    if (!admin.apps.length) return res.status(202).json({ status: 'queued' });

    const db = admin.firestore();
    const modRef = db.collection('community_reports').doc();
    const base = {
      target,
      reason: (reason || '').toString(),
      reporterId: req.headers['x-user-id']?.toString() || 'anon',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'open'
    };

    // First-pass LLM classification if OpenAI configured
    let llmVerdict = null;
    if (process.env.OPENAI_API_KEY) {
      try {
        const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
        const moderationPrompt = `Classify this community content for a family-friendly restaurant app. Output JSON with fields: verdict (allowed|borderline|violation), confidence (0-1), categories (array), recommended_action (none|auto_hide|escalate), rationale_snippet.\nCONTENT: ${JSON.stringify(req.body.snapshot || {})}`;
        const completion = await openai.chat.completions.create({
          model: 'gpt-4o-mini',
          messages: [ { role: 'system', content: 'You are a strict content policy classifier.' }, { role: 'user', content: moderationPrompt } ],
          max_tokens: 250,
          temperature: 0
        });
        const text = completion.choices[0].message.content || '{}';
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (jsonMatch) llmVerdict = JSON.parse(jsonMatch[0]);
      } catch (err) {
        console.warn('⚠️ LLM moderation failed, continuing without auto-hide', err.message);
      }
    }

    // Auto-hide if high-confidence violation
    if (llmVerdict && llmVerdict.verdict === 'violation' && Number(llmVerdict.confidence || 0) >= 0.85) {
      try {
        if (target.type === 'post') {
          await db.collection('community_posts').doc(target.id).update({ hidden: true });
        } else if (target.type === 'comment') {
          const parts = target.id.split(':'); // format optional: postId:commentId
          if (parts.length === 2) await db.collection('community_posts').doc(parts[0]).collection('comments').doc(parts[1]).update({ hidden: true });
        }
        await modRef.set({ ...base, llmVerdict, status: 'auto_hidden' });
        return res.status(202).json({ status: 'auto_hidden' });
      } catch (e) {
        console.error('❌ Auto-hide failed, falling back to queue', e);
      }
    }

    await modRef.set({ ...base, llmVerdict, status: 'open' });
    return res.status(202).json({ status: 'queued' });
  } catch (e) {
    console.error('❌ /community/reports error', e);
    res.status(500).json({ error: { code: 'report_failed', message: 'Failed to report' } });
  }
});

// Announcements
app.get('/community/announcements', async (req, res) => {
  try {
    if (!admin.apps.length) return res.json({ announcements: [] });
    const db = admin.firestore();
    const now = new Date();
    let q = db.collection('community_announcements');
    const snap = await q.get();
    const anns = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      const startsAt = d.startsAt?.toDate ? d.startsAt.toDate() : null;
      const expiresAt = d.expiresAt?.toDate ? d.expiresAt.toDate() : null;
      const active = (!startsAt || startsAt <= now) && (!expiresAt || expiresAt >= now);
      if (active) {
        anns.push({
          id: doc.id,
          title: d.title || '',
          body: d.body || '',
          media: Array.isArray(d.media) ? d.media : [],
          pinned: !!d.pinned,
          startsAt: startsAt ? startsAt.toISOString() : null,
          expiresAt: expiresAt ? expiresAt.toISOString() : null
        });
      }
    });
    // Pinned first
    anns.sort((a,b) => (b.pinned?1:0) - (a.pinned?1:0));
    res.json({ announcements: anns });
  } catch (e) {
    console.error('❌ /community/announcements error', e);
    res.json({ announcements: [] });
  }
});

app.post('/community/announcements', async (req, res) => {
  try {
    if (!admin.apps.length) return res.status(201).json({ id: `local_${Date.now()}` });
    const db = admin.firestore();
    const { id, title, body, media, pinned, startsAt, expiresAt } = req.body || {};
    const ref = id ? db.collection('community_announcements').doc(id) : db.collection('community_announcements').doc();
    const payload = {
      title: (title || '').toString(),
      body: (body || '').toString(),
      media: Array.isArray(media) ? media : [],
      pinned: !!pinned,
      startsAt: startsAt ? new Date(startsAt) : null,
      expiresAt: expiresAt ? new Date(expiresAt) : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    await ref.set(payload, { merge: true });
    res.status(201).json({ id: ref.id });
  } catch (e) {
    console.error('❌ POST /community/announcements error', e);
    res.status(500).json({ error: { code: 'announcement_failed', message: 'Failed to save announcement' } });
  }
});

// Admin moderation queue (role-gated upstream; no auth here yet)
app.get('/community/mod/queue', async (req, res) => {
  try {
    if (!admin.apps.length) return res.json({ items: [], nextCursor: null });
    const db = admin.firestore();
    const status = (req.query.status || 'open').toString();
    const pageSize = 50;
    let q = db.collection('community_reports').orderBy('createdAt', 'desc').limit(pageSize);
    if (status) q = q.where('status', '==', status);
    if (req.query.cursor) q = q.startAfter(new Date(req.query.cursor.toString()));
    const snap = await q.get();
    const items = [];
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      let preview = { text: '', authorName: 'Unknown', createdAt: new Date().toISOString() };
      try {
        if (d.target?.type === 'post') {
          const p = await db.collection('community_posts').doc(d.target.id).get();
          const pv = p.data() || {};
          preview = {
            text: pv.text || '',
            authorName: pv.authorName || 'Unknown',
            createdAt: (pv.createdAt && pv.createdAt.toDate ? pv.createdAt.toDate().toISOString() : new Date().toISOString())
          };
        }
      } catch (e) {}
      items.push({
        id: doc.id,
        target: d.target,
        reporterCount: 1,
        llmVerdict: d.llmVerdict || null,
        status: d.status || 'open',
        preview
      });
    }
    const nextCursor = snap.docs.length === pageSize ? items[items.length - 1].preview.createdAt : null;
    res.json({ items, nextCursor });
  } catch (e) {
    console.error('❌ /community/mod/queue error', e);
    res.json({ items: [], nextCursor: null });
  }
});

// Admin action on report
app.post('/community/mod/:id/action', async (req, res) => {
  try {
    if (!admin.apps.length) return res.json({ status: 'noop' });
    const { action, reason } = req.body || {};
    const db = admin.firestore();
    const modRef = db.collection('community_reports').doc(req.params.id);
    const modDoc = await modRef.get();
    if (!modDoc.exists) return res.status(404).json({ error: { code: 'not_found', message: 'Report not found' } });
    const d = modDoc.data();
    const target = d.target || {};
    const actionsRef = db.collection('community_moderation_actions').doc();

    if (action === 'hide' || action === 'unhide') {
      const hidden = action === 'hide';
      if (target.type === 'post') {
        await db.collection('community_posts').doc(target.id).update({ hidden });
      } else if (target.type === 'comment') {
        const [postId, commentId] = (target.id || '').split(':');
        if (postId && commentId) await db.collection('community_posts').doc(postId).collection('comments').doc(commentId).update({ hidden });
      }
      await modRef.update({ status: hidden ? 'auto_hidden' : 'resolved', lastAction: action, lastActionAt: admin.firestore.FieldValue.serverTimestamp(), lastActionReason: (reason || '').toString() });
    } else if (action === 'warn' || action === 'ban' || action === 'shadowBan') {
      await modRef.update({ status: 'resolved', lastAction: action, lastActionAt: admin.firestore.FieldValue.serverTimestamp(), lastActionReason: (reason || '').toString() });
    } else {
      return res.status(400).json({ error: { code: 'bad_action', message: 'Invalid action' } });
    }

    await actionsRef.set({
      reportId: modRef.id,
      action,
      reason: (reason || '').toString(),
      actorId: 'admin',
      target,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    res.json({ status: 'ok' });
  } catch (e) {
    console.error('❌ /community/mod/:id/action error', e);
    res.status(500).json({ error: { code: 'action_failed', message: 'Failed to apply action' } });
  }
});

// ---------------------------------------------------------------------------
// Referrals API (Create referral code/link)
// ---------------------------------------------------------------------------

// Feature flag (default enabled)
const REFERRALS_ENABLED = (process.env.ENABLE_REFERRALS || 'true') !== 'false';

// Share link base (production for Render; localhost for local dev)
const REFERRAL_SHARE_BASE = process.env.RENDER ? 'https://restaurant-stripe-server-1.onrender.com' : 'http://localhost:3001';

// Allow x-user-id fallback only for local/dev unless explicitly enabled
const ALLOW_HEADER_USER_ID = (process.env.ALLOW_HEADER_USER_ID === 'true') || !process.env.RENDER;

async function getAuthUserId(req) {
  try {
    const authHeader = (req.headers['authorization'] || '').toString();
    if (authHeader.startsWith('Bearer ') && admin.apps.length) {
      const idToken = authHeader.substring('Bearer '.length).trim();
      if (idToken) {
        const decoded = await admin.auth().verifyIdToken(idToken);
        if (decoded && decoded.uid) return decoded.uid;
      }
    }
  } catch (e) {
    // ignore and fall back
  }
  if (ALLOW_HEADER_USER_ID && req.headers['x-user-id']) return req.headers['x-user-id'].toString();
  if (ALLOW_HEADER_USER_ID && req.body && req.body.userId) return req.body.userId.toString();
  return null;
}

async function requireAuth(req, res, next) {
  const uid = await getAuthUserId(req);
  if (!uid) return res.status(401).json({ error: 'unauthorized' });
  req.user = { uid };
  next();
}

function generateReferralCode(length = 6) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // exclude easily confused chars
  let result = '';
  for (let i = 0; i < length; i++) {
    result += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
  }
  return result;
}

function getMonthKey(date = new Date()) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

function getDayKey(date = new Date()) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function getClientIp(req) {
  const xf = (req.headers['x-forwarded-for'] || '').toString();
  const ip = (xf.split(',')[0] || req.ip || req.connection?.remoteAddress || '').toString().trim();
  return ip.replace(/[^0-9a-fA-F:\.]/g, '');
}

async function logReferralEvent(db, type, payload = {}) {
  try {
    const doc = {
      type: String(type),
      ...payload,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    };
    await db.collection('referral_events').add(doc);
  } catch (e) {
    console.warn('⚠️ referral event log failed', type, e.message);
  }
}

// POST /referrals/create -> { code, shareUrl }
app.post('/referrals/create', requireAuth, async (req, res) => {
  try {
    if (!REFERRALS_ENABLED) {
      return res.status(404).json({ error: 'Referrals are disabled' });
    }
    if (!admin.apps.length) {
      return res.status(500).json({ error: 'Firebase not configured' });
    }

    const db = admin.firestore();

    // Identify the referrer user
    const referrerUserId = req.user.uid;

    // Reuse existing active code if present
    const existingSnap = await db
      .collection('referralCodes')
      .where('referrerUserId', '==', referrerUserId)
      .where('disabled', '==', false)
      .limit(1)
      .get();

    let code; let reused = false;
    if (!existingSnap.empty) {
      code = existingSnap.docs[0].id;
      reused = true;
    } else {
      // Create a unique code (6–7 chars if collisions)
      let attempts = 0;
      while (attempts < 10) {
        const candidate = generateReferralCode(6 + (attempts >= 5 ? 1 : 0));
        const candidateRef = db.collection('referralCodes').doc(candidate);
        const candidateDoc = await candidateRef.get();
        if (!candidateDoc.exists) {
          await candidateRef.set({
            referrerUserId: referrerUserId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            disabled: false,
            monthlyCap: 20,
            monthlyUsage: {},
            totalUsage: 0
          });
          code = candidate;
          break;
        }
        attempts++;
      }

      if (!code) {
        return res.status(500).json({ error: 'Failed to generate referral code' });
      }
    }

    const shareUrl = `${REFERRAL_SHARE_BASE}/r/${code}`;
    // Log event
    await logReferralEvent(db, reused ? 'referral_code_reused' : 'referral_code_created', {
      referrerUserId,
      code,
      shareUrl
    });
    return res.json({ code, shareUrl });
  } catch (e) {
    console.error('❌ /referrals/create error', e);
    return res.status(500).json({ error: 'Failed to create referral code' });
  }
});

// POST /referrals/accept -> { status: 'accepted', referralId, referrerUserId }
app.post('/referrals/accept', requireAuth, async (req, res) => {
  try {
    if (!REFERRALS_ENABLED) {
      return res.status(404).json({ error: 'Referrals are disabled' });
    }
    if (!admin.apps.length) {
      return res.status(500).json({ error: 'Firebase not configured' });
    }

    const db = admin.firestore();

    const referredUserId = req.user.uid;

    const codeRaw = (req.body && req.body.code) ? String(req.body.code) : '';
    const deviceId = (req.body && req.body.deviceId) ? String(req.body.deviceId) : null;
    const code = codeRaw.trim().toUpperCase();
    if (!code) {
      return res.status(400).json({ error: 'Missing referral code' });
    }

    const ip = getClientIp(req);
    const userAgent = (req.headers['user-agent'] || '').toString();
    const monthKey = getMonthKey();
    const dayKey = getDayKey();

    const result = await db.runTransaction(async (tx) => {
      const codeRef = db.collection('referralCodes').doc(code);
      const codeDoc = await tx.get(codeRef);
      if (!codeDoc.exists) {
        throw { status: 404, code: 'code_not_found', message: 'Referral code not found' };
      }
      const codeData = codeDoc.data() || {};
      if (codeData.disabled) {
        throw { status: 400, code: 'code_disabled', message: 'Referral code is disabled' };
      }

      const referrerUserId = String(codeData.referrerUserId || '');
      if (!referrerUserId) {
        throw { status: 500, code: 'invalid_code', message: 'Code is misconfigured' };
      }
      if (referrerUserId === referredUserId) {
        throw { status: 400, code: 'self_referral', message: 'You cannot refer yourself' };
      }

      // Enforce monthly cap
      const monthlyCap = typeof codeData.monthlyCap === 'number' ? codeData.monthlyCap : 20;
      const monthlyUsage = (codeData.monthlyUsage || {});
      const usedThisMonth = Number(monthlyUsage[monthKey] || 0);
      if (usedThisMonth >= monthlyCap) {
        throw { status: 429, code: 'monthly_cap_reached', message: 'Referral code monthly limit reached' };
      }

      // Enforce one referral per receiver + early lifecycle (< 50 points)
      const userRef = db.collection('users').doc(referredUserId);
      const userDoc = await tx.get(userRef);
      if (!userDoc.exists) {
        throw { status: 404, code: 'user_not_found', message: 'User not found' };
      }
      const userData = userDoc.data() || {};
      const userPoints = Number(userData.points || 0);
      if (userPoints >= 50) {
        throw { status: 400, code: 'receiver_not_eligible', message: 'Receiver already has enough points' };
      }
      if (userData.referredBy) {
        throw { status: 409, code: 'already_referred', message: 'Receiver already linked to a referrer' };
      }

      // Double-check via referrals query
      const existingReferralSnap = await db.collection('referrals')
        .where('referredUserId', '==', referredUserId)
        .limit(1)
        .get();
      if (!existingReferralSnap.empty) {
        throw { status: 409, code: 'already_referred', message: 'Receiver already linked to a referrer' };
      }

      // IP daily rate limit
      const ipKey = `${dayKey}:${ip || 'unknown'}`;
      const ipRef = db.collection('referralIpUsage').doc(ipKey);
      const ipDoc = await tx.get(ipRef);
      const ipCount = ipDoc.exists ? Number(ipDoc.data().count || 0) : 0;
      if (ipCount >= 5) {
        throw { status: 429, code: 'ip_rate_limited', message: 'Too many referral accepts from this IP today' };
      }

      // Create referral and update related docs
      const referralRef = db.collection('referrals').doc();
      tx.set(referralRef, {
        code,
        referrerUserId,
        referredUserId,
        status: 'accepted',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        awardedAt: null,
        awardedTxnId: null,
        ipAtAccept: ip || null,
        userAgentAtAccept: userAgent || null,
        deviceIdAtAccept: deviceId || null
      });

      tx.update(userRef, {
        referredBy: referrerUserId,
        referralId: referralRef.id
      });

      const updates = {
        totalUsage: admin.firestore.FieldValue.increment(1),
      };
      updates[`monthlyUsage.${monthKey}`] = admin.firestore.FieldValue.increment(1);
      tx.update(codeRef, updates);

      tx.set(ipRef, {
        date: dayKey,
        ip: ip || 'unknown',
        count: ipCount + 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

      return { referralId: referralRef.id, referrerUserId };
    });

    await logReferralEvent(db, 'referral_accepted', {
      referralId: result.referralId,
      referrerUserId: result.referrerUserId,
      referredUserId,
      code,
      ip,
      userAgent
    });
    return res.json({ status: 'accepted', referralId: result.referralId, referrerUserId: result.referrerUserId });
  } catch (e) {
    try {
      const db = admin.firestore();
      await logReferralEvent(db, 'referral_accept_denied', {
        code: (req.body && req.body.code) ? String(req.body.code).toUpperCase() : undefined,
        referredUserId: (req.user && req.user.uid) || undefined,
        reason: (e && e.code) ? e.code : 'unknown_error'
      });
    } catch {}
    if (e && typeof e.status === 'number' && e.code) {
      return res.status(e.status).json({ error: e.code, message: e.message || 'Failed to accept referral' });
    }
    console.error('❌ /referrals/accept error', e);
    return res.status(500).json({ error: 'accept_failed', message: 'Failed to accept referral' });
  }
});

// POST /referrals/award-check -> { status: 'awarded'|'already_awarded'|'not_eligible', bonus }
app.post('/referrals/award-check', requireAuth, async (req, res) => {
  try {
    if (!REFERRALS_ENABLED) {
      return res.status(404).json({ status: 'not_eligible', reason: 'disabled', bonus: 0 });
    }
    if (!admin.apps.length) {
      return res.status(500).json({ error: 'Firebase not configured' });
    }

    const db = admin.firestore();
    const tenMinutesMs = 10 * 60 * 1000;
    const bonusAmount = 50;

    const body = req.body || {};
    const referralId = body.referralId ? String(body.referralId) : null;
    const bodyUserId = body.referredUserId ? String(body.referredUserId) : null;
    const referredUserId = bodyUserId || (req.user && req.user.uid) || null;

    let referralRef;
    if (referralId) {
      referralRef = db.collection('referrals').doc(referralId);
    } else if (referredUserId) {
      // Lookup user's referralId
      const userDoc = await db.collection('users').doc(referredUserId).get();
      if (!userDoc.exists) {
        return res.status(404).json({ status: 'not_eligible', reason: 'user_not_found', bonus: 0 });
      }
      const userData = userDoc.data() || {};
      if (!userData.referralId) {
        return res.json({ status: 'not_eligible', reason: 'no_referral', bonus: 0 });
      }
      referralRef = db.collection('referrals').doc(String(userData.referralId));
    } else {
      return res.status(400).json({ error: 'missing_parameters', message: 'Provide referralId or referredUserId' });
    }

    const result = await db.runTransaction(async (tx) => {
      const refDoc = await tx.get(referralRef);
      if (!refDoc.exists) {
        return { status: 'not_eligible', reason: 'referral_not_found', bonus: 0 };
      }
      const data = refDoc.data() || {};
      const status = String(data.status || 'pending');
      const referrerUserId = String(data.referrerUserId || '');
      const receiverUserId = String(data.referredUserId || '');
      const acceptedAt = data.acceptedAt && data.acceptedAt.toDate ? data.acceptedAt.toDate() : null;
      const awardedTxnIdExisting = data.awardedTxnId || null;

      if (awardedTxnIdExisting || status === 'awarded') {
        return { status: 'already_awarded', reason: 'already_awarded', bonus: 0 };
      }
      if (status !== 'accepted') {
        return { status: 'not_eligible', reason: 'not_accepted', bonus: 0 };
      }
      if (!acceptedAt || (Date.now() - acceptedAt.getTime()) < tenMinutesMs) {
        return { status: 'not_eligible', reason: 'too_early', bonus: 0 };
      }
      if (!referrerUserId || !receiverUserId) {
        return { status: 'not_eligible', reason: 'invalid_referral', bonus: 0 };
      }

      const receiverRef = db.collection('users').doc(receiverUserId);
      const referrerRef = db.collection('users').doc(referrerUserId);
      const receiverDoc = await tx.get(receiverRef);
      const referrerDoc = await tx.get(referrerRef);
      if (!receiverDoc.exists || !referrerDoc.exists) {
        return { status: 'not_eligible', reason: 'user_docs_missing', bonus: 0 };
      }

      const receiverPoints = Number((receiverDoc.data() || {}).points || 0);
      if (receiverPoints < 50) {
        return { status: 'not_eligible', reason: 'threshold_not_met', bonus: 0 };
      }

      // Idempotent award: use deterministic txn id
      const awardedTxnId = `referral_award_${referralRef.id}`;

      // Create two pointsTransactions (one per user)
      const t1 = db.collection('pointsTransactions').doc(`award_${awardedTxnId}_referrer`);
      const t2 = db.collection('pointsTransactions').doc(`award_${awardedTxnId}_receiver`);

      const nowTs = admin.firestore.FieldValue.serverTimestamp();

      tx.set(t1, {
        id: t1.id,
        userId: referrerUserId,
        type: 'referral_bonus',
        amount: bonusAmount,
        description: 'Referral bonus: Your friend reached 50 points',
        timestamp: nowTs,
        isEarned: true,
        referralId: referralRef.id,
        awardedTxnId
      });

      tx.set(t2, {
        id: t2.id,
        userId: receiverUserId,
        type: 'referral_bonus',
        amount: bonusAmount,
        description: 'Referral bonus: You reached 50 points',
        timestamp: nowTs,
        isEarned: true,
        referralId: referralRef.id,
        awardedTxnId
      });

      // Increment points atomically on both users
      tx.update(referrerRef, { points: admin.firestore.FieldValue.increment(bonusAmount) });
      tx.update(receiverRef, { points: admin.firestore.FieldValue.increment(bonusAmount) });

      // Update referral to awarded
      tx.update(referralRef, {
        status: 'awarded',
        awardedAt: nowTs,
        awardedTxnId
      });

      return { status: 'awarded', reason: 'ok', bonus: bonusAmount };
    });

    // Log event based on result
    if (result && result.status === 'awarded') {
      await logReferralEvent(db, 'referral_award_granted', {
        referralId: referralId || undefined,
        referredUserId: referredUserId || undefined,
        bonus: bonusAmount
      });
    } else if (result && result.status === 'already_awarded') {
      await logReferralEvent(db, 'referral_already_awarded', {
        referralId: referralId || undefined,
        referredUserId: referredUserId || undefined
      });
    } else {
      await logReferralEvent(db, 'referral_award_not_eligible', {
        referralId: referralId || undefined,
        referredUserId: referredUserId || undefined,
        reason: result && result.reason ? result.reason : 'unknown'
      });
    }
    return res.json(result);
  } catch (e) {
    console.error('❌ /referrals/award-check error', e);
    return res.status(500).json({ error: 'award_failed', message: 'Failed to process award check' });
  }
});

// POST /analytics/referral-share { code, action: 'share'|'copy', shareUrl? }
app.post('/analytics/referral-share', requireAuth, async (req, res) => {
  try {
    if (!REFERRALS_ENABLED) return res.status(404).json({ ok: false });
    if (!admin.apps.length) return res.status(500).json({ ok: false, error: 'Firebase not configured' });
    const db = admin.firestore();
    const uid = req.user.uid;
    const code = (req.body && req.body.code) ? String(req.body.code).toUpperCase() : null;
    const action = (req.body && req.body.action) ? String(req.body.action) : 'share';
    const shareUrl = (req.body && req.body.shareUrl) ? String(req.body.shareUrl) : null;
    await logReferralEvent(db, 'referral_share', {
      userId: uid,
      code,
      action,
      shareUrl,
      ip: getClientIp(req),
      userAgent: (req.headers['user-agent'] || '').toString()
    });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false });
  }
});

// GET /r/:code -> Landing/redirect page for referral links
app.get('/r/:code', async (req, res) => {
  try {
    if (!REFERRALS_ENABLED) {
      return res.status(404).send('Not found');
    }

    const raw = (req.params.code || '').toString();
    const code = raw.trim().toUpperCase();
    if (!code) {
      return res.status(400).send('Missing code');
    }

    let valid = true;
    if (admin.apps.length) {
      try {
        const snap = await admin.firestore().collection('referralCodes').doc(code).get();
        const data = snap.exists ? (snap.data() || {}) : null;
        if (!snap.exists || !data || data.disabled) valid = false;
      } catch (e) {
        valid = false;
      }
    }

    const scheme = process.env.APP_DEEP_LINK_SCHEME || 'myapp://referral?code=';
    const deepLink = `${scheme}${encodeURIComponent(code)}`;
    const appStoreUrl = process.env.APP_STORE_URL || '#';

    const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Dumpling House Referral</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; margin: 0; padding: 24px; background: #fafafa; color: #111; }
      .card { max-width: 520px; margin: 0 auto; background: #fff; border-radius: 12px; padding: 24px; box-shadow: 0 6px 24px rgba(0,0,0,0.08); }
      .title { font-size: 22px; font-weight: 800; margin: 0 0 8px; }
      .subtitle { color: #666; margin: 0 0 20px; }
      .code { font-size: 20px; font-weight: 700; letter-spacing: 2px; padding: 12px 16px; background: #f3f4f6; border-radius: 10px; display: inline-block; }
      .row { margin-top: 18px; display: flex; gap: 12px; flex-wrap: wrap; }
      .btn { appearance: none; border: none; padding: 12px 16px; border-radius: 10px; font-weight: 700; cursor: pointer; }
      .primary { background: #111827; color: #fff; }
      .secondary { background: #e5e7eb; color: #111827; }
      .msg { margin-top: 14px; color: #059669; font-weight: 600; display: none; }
      .invalid { color: #b91c1c; font-weight: 700; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1 class="title">Refer a Friend</h1>
      <p class="subtitle">${valid ? 'Use this code in the app to link your referral.' : '<span class="invalid">This referral code is invalid or disabled.</span>'}</p>
      <div class="code" id="code">${code}</div>
      <div class="row">
        <button class="btn secondary" id="copy">Copy Code</button>
        <a class="btn primary" id="open" href="${deepLink}">Open App</a>
        ${appStoreUrl && appStoreUrl !== '#' ? `<a class="btn secondary" href="${appStoreUrl}">Get the App</a>` : ''}
      </div>
      <div id="msg" class="msg">Copied!</div>
    </div>
    <script>
      const btn = document.getElementById('copy');
      const codeEl = document.getElementById('code');
      const msgEl = document.getElementById('msg');
      btn?.addEventListener('click', async () => {
        try {
          await navigator.clipboard.writeText(codeEl.textContent || '');
          msgEl.style.display = 'block';
          setTimeout(() => msgEl.style.display = 'none', 1200);
        } catch {}
      });
    </script>
  </body>
 </html>`;

    res.set('Content-Type', 'text/html').status(valid ? 200 : 404).send(html);
  } catch (e) {
    return res.status(500).send('Server error');
  }
});

// Redeem reward endpoint (always available, independent of OpenAI)
app.post('/redeem-reward', async (req, res) => {
  try {
    console.log('🎁 Received reward redemption request');
    console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
    
    const { userId, rewardTitle, rewardDescription, pointsRequired, rewardCategory } = req.body;
    
    if (!userId || !rewardTitle || !pointsRequired) {
      console.log('❌ Missing required fields for reward redemption');
      return res.status(400).json({ 
        error: 'Missing required fields: userId, rewardTitle, pointsRequired',
        received: { userId: !!userId, rewardTitle: !!rewardTitle, pointsRequired: !!pointsRequired }
      });
    }
    
    if (!admin.apps.length) {
      console.log('❌ Firebase not initialized');
      return res.status(500).json({ error: 'Firebase not configured' });
    }
    
    const db = admin.firestore();
    
    // Get user's current points
    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      console.log('❌ User not found:', userId);
      return res.status(404).json({ error: 'User not found' });
    }
    
    const userData = userDoc.data();
    const currentPoints = userData.points || 0;
    
    console.log(`👤 User ${userId} has ${currentPoints} points, needs ${pointsRequired} for reward`);
    
    // Check if user has enough points
    if (currentPoints < pointsRequired) {
      console.log('❌ Insufficient points for redemption');
      return res.status(400).json({ 
        error: 'Insufficient points for redemption',
        currentPoints,
        pointsRequired,
        pointsNeeded: pointsRequired - currentPoints
      });
    }
    
    // Generate 8-digit random code
    const redemptionCode = Math.floor(10000000 + Math.random() * 90000000).toString();
    console.log(`🔢 Generated redemption code: ${redemptionCode}`);
    
    // Calculate new points balance
    const newPointsBalance = currentPoints - pointsRequired;
    
    // Create redeemed reward document
    const redeemedReward = {
      id: `reward_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      userId: userId,
      rewardTitle: rewardTitle,
      rewardDescription: rewardDescription || '',
      rewardCategory: rewardCategory || 'General',
      pointsRequired: pointsRequired,
      redemptionCode: redemptionCode,
      redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + 15 * 60 * 1000), // 15 minutes from now
      isExpired: false,
      isUsed: false
    };
    
    // Create points transaction for deduction
    const pointsTransaction = {
      id: `deduction_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      userId: userId,
      type: 'reward_redemption',
      amount: -pointsRequired, // Negative amount for deduction
      description: `Redeemed: ${rewardTitle}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isEarned: false,
      redemptionCode: redemptionCode,
      rewardTitle: rewardTitle
    };
    
    // Perform database operations in a batch
    const batch = db.batch();
    
    // Update user points
    batch.update(userRef, { points: newPointsBalance });
    
    // Add redeemed reward
    const redeemedRewardRef = db.collection('redeemedRewards').doc(redeemedReward.id);
    batch.set(redeemedRewardRef, redeemedReward);
    
    // Add points transaction
    const transactionRef = db.collection('pointsTransactions').doc(pointsTransaction.id);
    batch.set(transactionRef, pointsTransaction);
    
    // Commit the batch
    await batch.commit();
    
    console.log(`✅ Reward redeemed successfully!`);
    console.log(`💰 Points deducted: ${pointsRequired}`);
    console.log(`💳 New balance: ${newPointsBalance}`);
    console.log(`🔢 Redemption code: ${redemptionCode}`);
    
    res.json({
      success: true,
      redemptionCode: redemptionCode,
      newPointsBalance: newPointsBalance,
      pointsDeducted: pointsRequired,
      rewardTitle: rewardTitle,
      expiresAt: redeemedReward.expiresAt,
      message: 'Reward redeemed successfully! Show the code to your cashier.'
    });
    
  } catch (error) {
    console.error('❌ Error redeeming reward:', error);
    res.status(500).json({ 
      error: 'Failed to redeem reward',
      details: error.message 
    });
  }
});

// Force production environment
process.env.NODE_ENV = 'production';

const port = process.env.PORT || 3001;

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${port}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔑 OpenAI API Key configured: ${process.env.OPENAI_API_KEY ? 'Yes' : 'No'}`);
  console.log(`🔥 Firebase configured: ${admin.apps.length ? 'Yes' : 'No'}`);
});
// Force redeploy - Sat Jul 19 14:12:02 CDT 2025
// Force complete redeploy - Sat Jul 19 14:15:27 CDT 2025
// Force redeploy for redeem-reward endpoint fix - July 25 2025
// Force deployment update
// Force redeploy trigger: update timestamp 2025-07-26T03:58Z
