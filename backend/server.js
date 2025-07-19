require('dotenv').config();
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');
const { OpenAI } = require('openai');

// Initialize Firebase Admin SDK
let admin;
try {
  admin = require('firebase-admin');
  
  // Check if Firebase service account key is provided
  if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('✅ Firebase Admin SDK initialized successfully');
  } else {
    console.log('⚠️ FIREBASE_SERVICE_ACCOUNT_KEY not found, Firebase features will be disabled');
  }
} catch (error) {
  console.error('❌ Failed to initialize Firebase Admin SDK:', error.message);
  admin = { apps: [] }; // Fallback to prevent errors
}

const app = express();
const upload = multer({ dest: 'uploads/' });
app.use(cors());
app.use(express.json());

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

      const prompt = `\nYou are a receipt parser. Extract the following fields from the receipt image:\n- orderNumber: Look for the largest number on the receipt that appears as white text inside a black container/box. This is typically located under \"Nashville, TN\" and next to \"Walk In\". This is the order number.\n- orderTotal: The total amount paid (as a number, e.g. 23.45)\n- orderDate: The date of the order (in MM/DD/YYYY or YYYY-MM-DD format)\n\nRespond ONLY as a JSON object: {\"orderNumber\": \"...\", \"orderTotal\": ..., \"orderDate\": \"...\"}\nIf a field is missing, use null.\n`;

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
      
      const { message, conversation_history, userFirstName, userPreferences } = req.body;
      
      if (!message) {
        return res.status(400).json({ error: 'Message is required' });
      }
      
      console.log('📝 User message:', message);
      console.log('👤 User first name:', userFirstName || 'Not provided');
      console.log('⚙️ User preferences:', userPreferences || 'Not provided');
      
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

Remember: You're not just an assistant—you love helping people discover the best dumplings in Nashville!${userPreferencesContext}`;

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
        model: "gpt-4.1-mini", // UPGRADED: Changed from nano to mini for better performance
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

  // Generate personalized combo endpoint
  app.post('/generate-combo', async (req, res) => {
    try {
      console.log('🤖 Received personalized combo request');
      
      const { userName, dietaryPreferences, menuItems } = req.body;
      
      if (!userName || !dietaryPreferences || !menuItems) {
        return res.status(400).json({ 
          error: 'Missing required fields: userName, dietaryPreferences, menuItems' 
        });
      }
      
      // Try to fetch from Firebase first, fall back to menu items from request
      let allMenuItems = [];
      
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
          
          console.log(`✅ Successfully fetched ${allMenuItems.length} menu items from Firestore with proper categories`);
        } catch (error) {
          console.error('❌ Error fetching from Firestore:', error);
          console.log('🔄 Falling back to menu items from request...');
          allMenuItems = menuItems || [];
        }
      } else {
        console.log('⚠️ Firebase not configured, using menu items from request');
        allMenuItems = menuItems || [];
        
        // Categorize items from request if they don't have categories
        if (allMenuItems.length > 0) {
          console.log('🔍 Categorizing menu items from request...');
          allMenuItems = categorizeFromDescriptions(allMenuItems);
        }
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
      
      // If still no menu items, return error
      if (!allMenuItems || allMenuItems.length === 0) {
        console.error('❌ No menu items available');
        return res.status(500).json({ 
          error: 'No menu items available',
          details: 'Unable to fetch menu from Firebase or request'
        });
      }
      

      
      // Send the FULL menu to ChatGPT - no filtering, let ChatGPT decide
      console.log('🔍 DEBUG: All menu items received:', allMenuItems.length);
      console.log('🔍 DEBUG: All menu items:', allMenuItems.map(item => `${item.id} (${item.category || 'uncategorized'})`));
      console.log('🔍 DEBUG: Dietary preferences:', dietaryPreferences);
      
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
      
      // Group menu items by their Firebase categories
      const menuByCategory = {};
      allMenuItems.forEach(item => {
        const category = item.category || 'Other';
        if (!menuByCategory[category]) {
          menuByCategory[category] = [];
        }
        menuByCategory[category].push(item);
      });
      
      // Create menu items text for AI organized by categories with brackets
      const menuText = `
Available menu items by category:

${Object.entries(menuByCategory).map(([category, items]) => 
  `[${category}]:\n${items.map(item => `- ${item.id}: $${item.price} - ${item.description}`).join('\n')}`
).join('\n\n')}
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
1. One item from the "Dumplings" category (if available)
2. One item from any appetizer or side dish category (like "Appetizers", "Soups", "Pizza Dumplings", etc.)
3. One item from any drink category (like "Fruit Tea", "Milk Tea", "Coffee", "Lemonade/Soda", "Drink")
4. Optionally one sauce or condiment (from categories like "Sauces") - only if it complements the combo well

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
    {"id": "Exact Item Name from Menu", "category": "Exact Category Name from Menu"},
    {"id": "Exact Item Name from Menu", "category": "Exact Category Name from Menu"},
    {"id": "Exact Item Name from Menu", "category": "Exact Category Name from Menu"}
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
      
      // Parse AI response - handle both pure JSON and markdown-wrapped JSON
      let comboData;
      try {
        // First try to parse as pure JSON
        comboData = JSON.parse(aiResponse);
      } catch (parseError) {
        console.log('🔄 First parse attempt failed, trying to extract JSON from markdown...');
        
        // Try to extract JSON from markdown code blocks
        const jsonMatch = aiResponse.match(/```(?:json)?\s*(\{[\s\S]*?\})\s*```/);
        if (jsonMatch) {
          try {
            comboData = JSON.parse(jsonMatch[1]);
            console.log('✅ Successfully extracted JSON from markdown code block');
          } catch (markdownParseError) {
            console.error('❌ Failed to parse JSON from markdown:', markdownParseError);
            return res.status(500).json({ 
              error: 'Failed to parse AI response from markdown',
              aiResponse: aiResponse 
            });
          }
        } else {
          console.error('❌ Failed to parse AI response - no valid JSON found:', parseError);
          return res.status(500).json({ 
            error: 'Failed to parse AI response - no valid JSON found',
            aiResponse: aiResponse 
          });
        }
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
}

// Force production environment
process.env.NODE_ENV = 'production';

const port = process.env.PORT || 3001;

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${port}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔑 OpenAI API Key configured: ${process.env.OPENAI_API_KEY ? 'Yes' : 'No'}`);
});
