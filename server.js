require('dotenv').config();
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');
const { OpenAI } = require('openai');

// Initialize Firebase Admin
const admin = require('firebase-admin');

// Check authentication method
if (process.env.FIREBASE_AUTH_TYPE === 'adc') {
  // Use Application Default Credentials
  try {
    admin.initializeApp({
      projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp'
    });
    console.log('✅ Firebase Admin initialized with Application Default Credentials');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin with ADC:', error);
  }
} else if (process.env.FIREBASE_AUTH_TYPE === 'service-account' && process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  // Use service account key
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('✅ Firebase Admin initialized with service account key');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin with service account:', error);
  }
} else if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  // Fallback: Use service account key if available
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('✅ Firebase Admin initialized with service account key (fallback)');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin with service account:', error);
  }
} else {
  console.warn('⚠️ No Firebase authentication method found - Firebase features will not work');
}

const app = express();
const upload = multer({ dest: 'uploads/' });
app.use(cors());
app.use(express.json());

// 🛡️ DIETARY RESTRICTION SAFETY VALIDATION SYSTEM
// This function validates AI-generated combos against user dietary restrictions
// and removes any items that violate those restrictions (Plan B safety net)
function validateDietaryRestrictions(items, dietaryPreferences, allMenuItems) {
  console.log('🛡️ Starting dietary validation for', items.length, 'items');
  console.log('🔍 Dietary preferences:', JSON.stringify(dietaryPreferences));
  
  // Define trigger words for each restriction type
  const restrictions = {
    vegetarian: ['chicken', 'pork', 'beef', 'shrimp', 'crab', 'meat', 'wonton'],
    lactose: ['milk', 'cheese', 'cream', 'dairy', 'biscoff', 'chocolate milk', 'tiramisu'],
    lactoseSubstitutable: ['milk tea', 'latte', 'coffee'], // Items that can use milk substitutes
    noPork: ['pork'],
    peanutAllergy: ['peanut'],
    noSpicy: ['spicy', 'hot', 'chili']
  };
  
  const removedItems = [];
  let milkSubstituteNeeded = false;
  
  // Filter items based on dietary restrictions
  const validatedItems = items.filter(item => {
    const itemNameLower = item.id.toLowerCase();
    
    // Check vegetarian restriction
    if (dietaryPreferences.isVegetarian) {
      for (const word of restrictions.vegetarian) {
        if (itemNameLower.includes(word)) {
          console.log(`🚫 REMOVED: "${item.id}" - contains "${word}" (vegetarian restriction)`);
          removedItems.push(item);
          return false;
        }
      }
    }
    
    // Check lactose intolerance
    if (dietaryPreferences.hasLactoseIntolerance) {
      // Check if item can use milk substitutes
      const canSubstitute = restrictions.lactoseSubstitutable.some(word => 
        itemNameLower.includes(word)
      );
      
      if (canSubstitute) {
        // Item can use substitutes, keep it but flag for note
        milkSubstituteNeeded = true;
        console.log(`✅ KEPT: "${item.id}" - can use milk substitute (oat/almond/coconut milk)`);
      } else {
        // Check if item contains dairy that can't be substituted
        for (const word of restrictions.lactose) {
          if (itemNameLower.includes(word)) {
            console.log(`🚫 REMOVED: "${item.id}" - contains "${word}" (lactose intolerance)`);
            removedItems.push(item);
            return false;
          }
        }
      }
    }
    
    // Check no pork preference
    if (dietaryPreferences.doesntEatPork) {
      for (const word of restrictions.noPork) {
        if (itemNameLower.includes(word)) {
          console.log(`🚫 REMOVED: "${item.id}" - contains "${word}" (doesn't eat pork)`);
          removedItems.push(item);
          return false;
        }
      }
    }
    
    // Check peanut allergy
    if (dietaryPreferences.hasPeanutAllergy) {
      for (const word of restrictions.peanutAllergy) {
        if (itemNameLower.includes(word)) {
          console.log(`🚫 REMOVED: "${item.id}" - contains "${word}" (peanut allergy)`);
          removedItems.push(item);
          return false;
        }
      }
    }
    
    // Check dislikes spicy food
    if (dietaryPreferences.dislikesSpicyFood) {
      for (const word of restrictions.noSpicy) {
        if (itemNameLower.includes(word)) {
          console.log(`🚫 REMOVED: "${item.id}" - contains "${word}" (dislikes spicy food)`);
          removedItems.push(item);
          return false;
        }
      }
    }
    
    // Item passed all checks
    return true;
  });
  
  // Recalculate total price based on validated items
  let totalPrice = 0;
  for (const item of validatedItems) {
    // Find the item in the menu to get accurate price
    const menuItem = allMenuItems.find(mi => mi.id === item.id);
    if (menuItem) {
      totalPrice += parseFloat(menuItem.price) || 0;
    }
  }
  
  // Round to 2 decimal places
  totalPrice = Math.round(totalPrice * 100) / 100;
  
  // Generate milk substitute note if needed
  let milkSubstituteNote = '';
  if (milkSubstituteNeeded && dietaryPreferences.hasLactoseIntolerance) {
    milkSubstituteNote = '(We can make your drink with oat milk, almond milk, or coconut milk instead of regular milk!)';
  }
  
  console.log(`✅ Validation complete: ${validatedItems.length}/${items.length} items passed`);
  if (removedItems.length > 0) {
    console.log(`⚠️ Safety system caught ${removedItems.length} dietary violation(s)`);
  }
  
  return {
    items: validatedItems,
    totalPrice: totalPrice,
    removedCount: removedItems.length,
    removedItems: removedItems,
    wasModified: removedItems.length > 0,
    milkSubstituteNote: milkSubstituteNote
  };
}

// ---------------------------------------------------------------------------
// Minimal always-on Redeem Reward endpoint
// ---------------------------------------------------------------------------
app.post('/redeem-reward', (req, res) => {
  console.log('🎁 [Minimal] redeem-reward hit');
  res.status(501).json({
    error: 'Redeem reward logic temporarily unavailable on this instance',
    message: 'Endpoint registered successfully; full implementation pending.'
  });
});

// ---------------------------------------------------------------------------
// Referral System Endpoints
// ---------------------------------------------------------------------------

// Create or get referral code
app.post('/referrals/create', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const db = admin.firestore();
    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    const userData = userDoc.data();
    let referralCode = userData.referralCode;

    // Generate code if doesn't exist
    if (!referralCode) {
      referralCode = generateReferralCode();
      await userRef.update({ referralCode });
    }

    // Use custom URL scheme to avoid sandbox extension errors
    // For users who already have the app installed
    const directUrl = `restaurantdemo://referral?code=${referralCode}`;
    
    // Web redirect URL for users who don't have the app yet
    // Host this page on your domain or use a service like Firebase Hosting
    const webUrl = `https://dumplinghouseapp.com/refer?code=${referralCode}`;
    
    res.json({
      code: referralCode,
      shareUrl: directUrl, // Use direct link for now (works for installed app)
      webUrl: webUrl, // Optional: Use this for QR codes to support non-installed users
      directUrl: directUrl // Direct deep link
    });
  } catch (error) {
    console.error('Error creating referral code:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Accept referral code
app.post('/referrals/accept', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const { code } = req.body;
    if (!code) {
      return res.status(400).json({ error: 'Missing code' });
    }

    const db = admin.firestore();
    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    const userData = userDoc.data();

    // Check if user already used a referral
    if (userData.referredBy) {
      return res.status(400).json({ error: 'already_used_referral' });
    }

    // Find referrer by code
    const referrerQuery = await db.collection('users').where('referralCode', '==', code.toUpperCase()).limit(1).get();
    
    if (referrerQuery.empty) {
      return res.status(404).json({ error: 'invalid_code' });
    }

    const referrerDoc = referrerQuery.docs[0];
    const referrerId = referrerDoc.id;

    // Can't refer yourself
    if (referrerId === uid) {
      return res.status(400).json({ error: 'cannot_refer_self' });
    }

    // Create referral document
    const referralRef = await db.collection('referrals').add({
      referrerUserId: referrerId,
      referredUserId: uid,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Update user with referredBy
    await userRef.update({
      referredBy: referrerId,
      referralId: referralRef.id
    });

    res.json({
      success: true,
      referrerUserId: referrerId,
      referralId: referralRef.id
    });
  } catch (error) {
    console.error('Error accepting referral:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get user's referral connections
app.get('/referrals/mine', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    const db = admin.firestore();
    
    // Get outbound (people I referred)
    const outboundSnap = await db.collection('referrals').where('referrerUserId', '==', uid).get();
    const outbound = [];
    
    for (const doc of outboundSnap.docs) {
      const data = doc.data();
      const referredUserDoc = await db.collection('users').doc(data.referredUserId).get();
      const referredUserData = referredUserDoc.data() || {};
      
      outbound.push({
        referralId: doc.id,
        referredName: referredUserData.firstName || 'Friend',
        status: data.status || 'pending',
        pointsTowards50: referredUserData.totalPoints || 0
      });
    }

    // Get inbound (who referred me)
    const inboundSnap = await db.collection('referrals').where('referredUserId', '==', uid).limit(1).get();
    let inbound = null;
    
    if (!inboundSnap.empty) {
      const doc = inboundSnap.docs[0];
      const data = doc.data();
      const referrerDoc = await db.collection('users').doc(data.referrerUserId).get();
      const referrerData = referrerDoc.data() || {};
      
      inbound = {
        referralId: doc.id,
        referrerName: referrerData.firstName || 'Friend',
        status: data.status || 'pending',
        pointsTowards50: 0
      };
    }

    res.json({
      outbound,
      inbound
    });
  } catch (error) {
    console.error('Error fetching referrals:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Helper function to generate referral codes
function generateReferralCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed ambiguous chars
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
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
      
      // 🛡️ PLAN B: Dietary Restriction Safety Validation System
      console.log('🛡️ Running dietary restriction safety validation...');
      const validationResult = validateDietaryRestrictions(
        parsedResponse.items, 
        dietaryPreferences, 
        allMenuItems
      );
      
      // Update the combo with validated items
      parsedResponse.items = validationResult.items;
      parsedResponse.totalPrice = validationResult.totalPrice;
      
      // Add warning if items were removed
      if (validationResult.wasModified) {
        console.log(`⚠️ AI DIETARY VIOLATION CAUGHT: Removed ${validationResult.removedCount} item(s)`);
        console.log(`   Removed items: ${validationResult.removedItems.map(item => item.id).join(', ')}`);
      }
      
      // Add milk substitute note if applicable
      if (validationResult.milkSubstituteNote) {
        parsedResponse.aiResponse += ' ' + validationResult.milkSubstituteNote;
      }
      
      res.json({
        success: true,
        combo: parsedResponse,
        varietyInfo: {
          strategy: currentStrategy,
          guideline: varietyGuideline,
          factors: varietyFactors,
          sessionId: sessionId
        },
        safetyInfo: {
          validationApplied: true,
          itemsRemoved: validationResult.removedCount,
          wasModified: validationResult.wasModified
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
3. CRITICAL LOCATION: The order number is ALWAYS directly underneath the word "Nashville" on the receipt. Look for "Nashville" and find the number immediately below it.
4. For DINE-IN orders: The order number is the BIGGER number inside the black box with white text, located directly under "Nashville". IGNORE any smaller numbers below the black box - those are NOT the order number.
5. For PICKUP orders: The order number is found directly underneath the word "Nashville" and may not be in a black box.
6. The order number is NEVER found further down on the receipt - it's always in the top section under "Nashville"
7. If the order number is more than 3 digits, it cannot be the order number - look for a smaller number
8. Order numbers CANNOT be greater than 400 - if you see a number over 400, it's not the order number and should be ignored completely
9. CRITICAL: If the receipt is faded, blurry, hard to read, or if ANY numbers are unclear or difficult to see, return {"error": "Receipt is too faded or unclear - please take a clearer photo"} - DO NOT attempt to guess or estimate any numbers
10. If the image quality is poor and numbers are blurry, unclear, or hard to read, return {"error": "Poor image quality - please take a clearer photo"}
11. ALWAYS return the date as MM/DD format only (no year, no other format)
12. CRITICAL: You MUST double-check all extracted information before returning it. Verify that the order number, total, and date are accurate and match what you see on the receipt. This is essential for preventing system abuse and maintaining data integrity.

EXTRACTION RULES:
- orderNumber: CRITICAL - Find the number directly underneath the word "Nashville" on the receipt. For dine-in orders, this is the BIGGER number in the black box with white text (ignore smaller numbers below). For pickup orders, this is the number directly under "Nashville". Must be 3 digits or less and cannot exceed 400. If no valid order number under 400 is found, return {"error": "No valid order number found - order numbers must be under 400"}
- orderTotal: The total amount paid (as a number, e.g. 23.45)
- orderDate: The date in MM/DD format only (e.g. "12/25")
- orderTime: The time in HH:MM format only (e.g. "14:30"). This is always located to the right of the date on the receipt.

IMPORTANT: 
- CRITICAL LOCATION: The order number is ALWAYS directly underneath the word "Nashville" on the receipt. Do not look for numbers further down on the receipt.
- On dine-in receipts, there may be a smaller number below the black box - this is NOT the order number. The order number is the bigger number inside the black box with white text, located directly under "Nashville".
- TIME LOCATION: The time is ALWAYS located to the right of the date on the receipt and must be in HH:MM format.
- If you cannot clearly read the numbers due to poor image quality, DO NOT GUESS. Return an error instead.
- If the receipt is faded, blurry, or any numbers are unclear, DO NOT ATTEMPT TO READ THEM. Return an error immediately.
- Order numbers must be between 1-400. Any number over 400 is completely invalid and should not be returned at all.
- If the only numbers you see are over 400, return {"error": "No valid order number found - order numbers must be under 400"}
- DOUBLE-CHECK REQUIREMENT: Before returning any data, carefully review the extracted order number, total, date, and time to ensure they are accurate and match the receipt. This verification step is crucial for preventing fraud and maintaining system integrity.
- SAFETY FIRST: It's better to reject a receipt and ask for a clearer photo than to guess and return incorrect information.

Respond ONLY as a JSON object: {"orderNumber": "...", "orderTotal": ..., "orderDate": "...", "orderTime": "..."} or {"error": "error message"}
If a field is missing, use null.`;

      console.log('🤖 Sending request to OpenAI for FIRST validation...');
      console.log('📊 API Call 1 - Starting at:', new Date().toISOString());
      
      // First OpenAI call
      const response1 = await openai.chat.completions.create({
        model: "gpt-4-vision-preview",
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageData}` } }
            ]
          }
        ],
        max_tokens: 500,
        temperature: 0.1
      });

      console.log('✅ First OpenAI response received');
      console.log('📊 API Call 1 - Completed at:', new Date().toISOString());
      
      console.log('🤖 Sending request to OpenAI for SECOND validation...');
      console.log('📊 API Call 2 - Starting at:', new Date().toISOString());
      
      // Second OpenAI call
      const response2 = await openai.chat.completions.create({
        model: "gpt-4-vision-preview",
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageData}` } }
            ]
          }
        ],
        max_tokens: 500,
        temperature: 0.1
      });

      console.log('✅ Second OpenAI response received');
      console.log('📊 API Call 2 - Completed at:', new Date().toISOString());
      
      // Clean up the uploaded file
      fs.unlinkSync(imagePath);

      // Parse first response
      const text1 = response1.choices[0].message.content;
      console.log('📝 Raw OpenAI response 1:', text1);
      
      const jsonMatch1 = text1.match(/\{[\s\S]*\}/);
      if (!jsonMatch1) {
        console.log('❌ Could not extract JSON from first response');
        return res.status(422).json({ error: "Could not extract JSON from first response", raw: text1 });
      }
      
      const data1 = JSON.parse(jsonMatch1[0]);
      console.log('✅ Parsed JSON data 1:', data1);
      
      // Parse second response
      const text2 = response2.choices[0].message.content;
      console.log('📝 Raw OpenAI response 2:', text2);
      
      const jsonMatch2 = text2.match(/\{[\s\S]*\}/);
      if (!jsonMatch2) {
        console.log('❌ Could not extract JSON from second response');
        return res.status(422).json({ error: "Could not extract JSON from second response", raw: text2 });
      }
      
      const data2 = JSON.parse(jsonMatch2[0]);
      console.log('✅ Parsed JSON data 2:', data2);
      
      // Check if either response contains an error
      if (data1.error) {
        console.log('❌ First validation failed:', data1.error);
        return res.status(400).json({ error: data1.error });
      }
      
      if (data2.error) {
        console.log('❌ Second validation failed:', data2.error);
        return res.status(400).json({ error: data2.error });
      }
      
      // Compare the two responses
      console.log('🔍 COMPARING TWO VALIDATIONS:');
      console.log('   Response 1 - Order Number:', data1.orderNumber, 'Total:', data1.orderTotal, 'Date:', data1.orderDate, 'Time:', data1.orderTime);
      console.log('   Response 2 - Order Number:', data2.orderNumber, 'Total:', data2.orderTotal, 'Date:', data2.orderDate, 'Time:', data2.orderTime);
      
      // Check if responses match
      const responsesMatch = 
        data1.orderNumber === data2.orderNumber &&
        data1.orderTotal === data2.orderTotal &&
        data1.orderDate === data2.orderDate &&
        data1.orderTime === data2.orderTime;
      
      console.log('🔍 COMPARISON DETAILS:');
      console.log('   Order Number Match:', data1.orderNumber === data2.orderNumber, `(${data1.orderNumber} vs ${data2.orderNumber})`);
      console.log('   Order Total Match:', data1.orderTotal === data2.orderTotal, `(${data1.orderTotal} vs ${data2.orderTotal})`);
      console.log('   Order Date Match:', data1.orderDate === data2.orderDate, `(${data1.orderDate} vs ${data2.orderDate})`);
      console.log('   Order Time Match:', data1.orderTime === data2.orderTime, `(${data1.orderTime} vs ${data2.orderTime})`);
      console.log('   Overall Match:', responsesMatch);
      
      if (!responsesMatch) {
        console.log('❌ VALIDATION MISMATCH - Responses do not match');
        console.log('   This indicates unclear or ambiguous receipt data');
        return res.status(400).json({ 
          error: "Receipt data is unclear - the two validations returned different results. Please take a clearer photo of the receipt." 
        });
      }
      
      console.log('✅ VALIDATION MATCH - Both responses are identical');
      
      // Use the validated data (both are the same)
      const data = data1;
      
      // Validate that we have the required fields
      if (!data.orderNumber || !data.orderTotal || !data.orderDate || !data.orderTime) {
        console.log('❌ Missing required fields in receipt data');
        return res.status(400).json({ error: "Could not extract all required fields from receipt" });
      }
      
      // Validate order number format (must be 3 digits or less and not exceed 200)
      const orderNumberStr = data.orderNumber.toString();
      console.log('🔍 Validating order number:', orderNumberStr);
      
      if (orderNumberStr.length > 3) {
        console.log('❌ Order number too long:', orderNumberStr);
        return res.status(400).json({ error: "Invalid order number format - must be 3 digits or less" });
      }
      
      const orderNumber = parseInt(data.orderNumber);
      console.log('🔍 Parsed order number:', orderNumber);
      
      if (isNaN(orderNumber)) {
        console.log('❌ Order number is not a valid number:', data.orderNumber);
        return res.status(400).json({ error: "Invalid order number - must be a valid number" });
      }
      
      if (orderNumber < 1) {
        console.log('❌ Order number too small:', orderNumber);
        return res.status(400).json({ error: "Invalid order number - must be at least 1" });
      }
      
      if (orderNumber > 200) {
        console.log('❌ Order number too large (over 200):', orderNumber);
        return res.status(400).json({ error: "Invalid order number - must be 200 or less" });
      }
      
      console.log('✅ Order number validation passed:', orderNumber);
      
      // Validate date format (must be MM/DD)
      const dateRegex = /^\d{2}\/\d{2}$/;
      if (!dateRegex.test(data.orderDate)) {
        console.log('❌ Invalid date format:', data.orderDate);
        return res.status(400).json({ error: "Invalid date format - must be MM/DD" });
      }
      
      // Validate time format (must be HH:MM)
      const timeRegex = /^\d{2}:\d{2}$/;
      if (!timeRegex.test(data.orderTime)) {
        console.log('❌ Invalid time format:', data.orderTime);
        return res.status(400).json({ error: "Invalid time format - must be HH:MM" });
      }
      
      // Validate time is reasonable (00:00 to 23:59)
      const [hours, minutes] = data.orderTime.split(':').map(Number);
      if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
        console.log('❌ Invalid time values:', data.orderTime);
        return res.status(400).json({ error: "Invalid time - must be between 00:00 and 23:59" });
      }
      
      console.log('✅ Time validation passed:', data.orderTime);
      
      // Additional server-side validation to double-check extracted data
      console.log('🔍 DOUBLE-CHECKING EXTRACTED DATA:');
      console.log('   Order Number:', data.orderNumber);
      console.log('   Order Total:', data.orderTotal);
      console.log('   Order Date:', data.orderDate);
      console.log('   Order Time:', data.orderTime);
      
      // Validate order total is a reasonable amount (between $1 and $500)
      const orderTotal = parseFloat(data.orderTotal);
      if (isNaN(orderTotal) || orderTotal < 1 || orderTotal > 500) {
        console.log('❌ Order total validation failed:', data.orderTotal);
        return res.status(400).json({ error: "Invalid order total - must be a reasonable amount between $1 and $500" });
      }
      
      // Validate date is reasonable (not in the future and not too far in the past)
      const [month, day] = data.orderDate.split('/').map(Number);
      const currentDate = new Date();
      const receiptDate = new Date(currentDate.getFullYear(), month - 1, day);
      
      // Check if date is in the future (adjust year if needed)
      if (receiptDate > currentDate) {
        receiptDate.setFullYear(currentDate.getFullYear() - 1);
      }
      
      const daysDiff = Math.abs((currentDate - receiptDate) / (1000 * 60 * 60 * 24));
      if (daysDiff > 30) {
        console.log('❌ Receipt date too old:', data.orderDate);
        return res.status(400).json({ error: "Receipt date is too old - must be within the last 30 days" });
      }
      
      console.log('✅ All validations passed - data integrity confirmed');
      
      // DUPLICATE DETECTION SYSTEM
      console.log('🔍 CHECKING FOR DUPLICATE RECEIPTS...');
      
      try {
        // Query Firestore for existing receipts with matching criteria
        const receiptsRef = db.collection('receipts');
        
        // Check for duplicates: if ANY 2 of the 3 fields match (orderNumber, date, time)
        const duplicateQueries = [
          // Same order number AND date
          receiptsRef.where('orderNumber', '==', data.orderNumber).where('orderDate', '==', data.orderDate),
          // Same order number AND time  
          receiptsRef.where('orderNumber', '==', data.orderNumber).where('orderTime', '==', data.orderTime),
          // Same date AND time
          receiptsRef.where('orderDate', '==', data.orderDate).where('orderTime', '==', data.orderTime)
        ];
        
        let duplicateFound = false;
        
        for (const query of duplicateQueries) {
          const snapshot = await query.get();
          if (!snapshot.empty) {
            console.log('❌ DUPLICATE RECEIPT DETECTED');
            console.log('   Matching criteria found in existing receipt');
            duplicateFound = true;
            break;
          }
        }
        
        if (duplicateFound) {
          return res.status(409).json({ 
            error: "Receipt already submitted - this receipt has already been processed and points will not be awarded",
            duplicate: true
          });
        }
        
        console.log('✅ No duplicates found - receipt is unique');
        
      } catch (duplicateError) {
        console.log('⚠️ Error checking for duplicates:', duplicateError.message);
        // Continue processing even if duplicate check fails
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
      
      // Debug mode: Return full prompt information when user sends "9327"
      if (message === "9327") {
        console.log('🔍 Debug mode activated - returning full prompt information');
        
        // Build user preferences context for the debug output
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

You know your name is "Dumpling Hero" and you should never refer to yourself as any other name (such as AI, assistant, etc). However, you do not need to mention your name in every response—just avoid using any other name.

Your tone is humorous, professional, and casual. Feel free to make light-hearted jokes and puns, but never joke about items not on the menu (for example, do not joke about soup dumplings or anything we don't serve, to avoid confusing customers).

You're passionate about dumplings and love helping customers discover our authentic Chinese cuisine.

CRITICAL HONESTY GUIDELINES:
- NEVER make up information about menu items, ingredients, or restaurant details
- If you don't know specific details about something, simply don't mention those specifics
- Focus on what you do know from the provided menu and information
- If asked about something not covered in your knowledge, suggest calling the restaurant directly
- Always prioritize accuracy over speculation

MULTILINGUAL CAPABILITIES:
- You can communicate fluently in many languages. ALWAYS respond in the same language the customer uses, maintaining your warm personality and using culturally appropriate expressions.
- If unsure about a language, respond in English and ask if they'd prefer another language.

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

🥟 APPETIZERS:
- Edamame $4.99
- Asian Pickled Cucumbers $5.75
- (Crab & Shrimp) Cold Noodle w/ Peanut Sauce $8.35
- Peanut Butter Pork Dumplings $7.99
- Spicy Tofu $5.99
- Curry Rice w/ Chicken $7.75
- Jasmine White Rice $2.75

🍲 SOUP:
- Hot & Sour Soup $5.95
- Pork Wonton Soup $6.95
- Shrimp Wonton Soup $8.95

🍕 PIZZA DUMPLINGS (6 pieces):
- Pork $8.99
- Curry Beef & Onion $10.99

🍱 LUNCH SPECIAL (6 pieces - Monday-Friday only, ends at 4:00 PM):
- No.9 Pork $7.50
- No.2 Pork & Chive $8.50
- No.4 Pork Shrimp $9.00
- No.5 Pork & Cabbage $8.00
- No.3 Spicy Pork $8.00
- No.7 Curry Chicken $7.00
- No.8 Chicken & Coriander $7.50
- No.1 Chicken & Mushroom $8.00
- No.10 Curry Beef & Onion $8.50
- No.6 Veggie $7.50

🥟 DUMPLINGS (12 pieces):
- No.9 Pork $13.99
- No.2 Pork & Chive $15.99
- No.4 Pork Shrimp $16.99
- No.5 Pork & Cabbage $14.99
- No.3 Spicy Pork $14.99
- No.7 Curry Chicken $12.99
- No.8 Chicken & Coriander $13.99
- No.1 Chicken & Mushroom $14.99
- No.10 Curry Beef & Onion $15.99
- No.6 Veggie $13.99
- No.12 Half/Half $15.99

🧋 MILK TEA:
- Bubble Milk Tea w/ Tapioca $5.90
- Fresh Milk Tea $5.90
- Cookies n' Cream (Biscoff) $6.65
- Cream Brulee Cake $7.50
- Capped Thai Brown Sugar $6.90
- Strawberry Cake $6.75
- Strawberry Fresh $6.75
- Peach Fresh $6.50
- Pineapple Fresh $6.50
- Tiramisu Coco $6.85
- Coconut Coffee w/ Coffee Jelly $6.90
- Purple Yam Taro Fresh $6.85
- Oreo Chocolate $6.75

🍹 FRUIT TEA:
- Lychee Dragon Fruit $6.50
- Lychee Dragon Slush $7.50
- Grape Magic w/ Cheese Foam $6.90
- Full of Mango w/ Cheese Foam $6.90
- Peach Strawberry $6.75
- Kiwi Booster $6.75
- Tropical Passion Fruit Tea $6.75
- Pineapple $6.90
- Winter Melon Black $6.50
- Osmanthus Oolong w/ Cheese Foam $6.25
- Peach Oolong w/ Cheese Foam $6.25
- Ice Green $5.00
- Ice Black $5.00

☕ COFFEE:
- Jasmine Latte w/ Sea Salt $6.25
- Oreo Chocolate Latte $6.90
- Coconut Coffee w/ Coffee Jelly $6.90
- Matcha White Chocolate $6.90
- Coffee Latte $5.50

✨ DRINK TOPPINGS (add to any drink):
- Tapioca $0.75
- Whipped Cream $1.50
- Tiramisu Foam $1.25
- Cheese Foam $1.25
- Coffee Jelly $0.50
- Boba Jelly $0.50
- Lychee, Peach, Blue Lemon or Strawberry Popping Jelly $0.50
- Pineapple Nata Jelly $0.50
- Mango Star Jelly $0.50

🍋 LEMONADE OR SODA:
- Pineapple $5.50
- Lychee Mint $5.50
- Peach Mint $5.50
- Passion Fruit $5.25
- Mango $5.50
- Strawberry $5.50
- Grape $5.25
- Original Lemonade $5.50

🥣 SAUCES:
- Secret Peanut Sauce $1.50
- SPICY Secret Peanut Sauce $1.50
- Curry Sauce w/ Chicken $1.50

🥤 BEVERAGES:
- Coke $2.25
- Diet Coke $2.25
- Sprite $2.25
- Bottle Water $1.00
- Cup Water $1.00

SPECIAL DIETARY INFORMATION:
- Veggie dumplings include: cabbage, carrots, onions, celery, shiitake mushrooms, glass noodles
- We don't have anything vegan
- Everything has gluten
- We aren't sure what has MSG
- No delivery available
- Contains peanut butter: cold noodles with peanut sauce, cold tofu, peanut butter pork
- No complementary cups, but if you bring your own cup we can fill it with water
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
- MILK SUBSTITUTIONS: For customers with lactose intolerance, our milk teas and coffee lattes can be made with oat milk, almond milk, or coconut milk instead of regular milk. When recommending these drinks to lactose intolerant customers, always mention the milk substitution options available.

RECOMMENDATION GUIDELINES:
- Pair items that taste good together (spicy dumplings with sweet drinks, etc.). Focus on proven combinations customers love.
- Only mention "most popular" items when specifically asked about recommendations or popular items.

SERVICES:
- Dine-in and takeout available
- No delivery available
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
- Keep responses concise (2-3 sentences max) and end with a question to encourage conversation

Remember: You're not just an assistant—you love helping people discover the best dumplings in Nashville!${userPreferencesContext}

LOYALTY/REWARDS CONTEXT:
- User has ${typeof userPoints === 'number' ? userPoints : 'an unknown number of'} points. If points provided (${typeof userPoints === 'number' ? 'YES' : 'NO'}), personalize responses. If not provided, say "I don't see your points right now" and suggest opening Rewards tab or scanning receipt.
- REWARD TIERS: 250 (Sauce/Coke), 450 (Tea/Lemonade/Coffee), 500 (Small Appetizer), 650 (Large Appetizer), 850 (Pizza Dumplings/Lunch Special 6pc), 1500 (12pc Dumplings), 2000 (Full Combo).
- CRITICAL: If under 250 points, do NOT say they can redeem anything. Tell them they need 250+ points and how many more they need.
- Only mention rewards at or below their point balance. Don't list unaffordable rewards unless specifically asked about higher tiers.`;
        
        // Format debug information as readable text
        const debugResponse = {
          response: `🔍 DEBUG MODE ACTIVATED

=== SYSTEM PROMPT ===
${systemPrompt}

=== USER CONTEXT ===
First Name: ${userFirstName || 'Not provided'}
Points: ${typeof userPoints === 'number' ? userPoints : 'Not provided'}
Preferences Completed: ${userPreferences?.hasCompletedPreferences || false}
${userPreferences?.hasCompletedPreferences ? `
Dietary Restrictions:
- Likes Spicy: ${userPreferences.likesSpicyFood || false}
- Dislikes Spicy: ${userPreferences.dislikesSpicyFood || false}
- Peanut Allergy: ${userPreferences.hasPeanutAllergy || false}
- Vegetarian: ${userPreferences.isVegetarian || false}
- Lactose Intolerant: ${userPreferences.hasLactoseIntolerance || false}
- Doesn't Eat Pork: ${userPreferences.doesntEatPork || false}
${userPreferences.tastePreferences ? `- Taste Preferences: ${userPreferences.tastePreferences}` : ''}
` : ''}

=== CONVERSATION HISTORY ===
${conversation_history && conversation_history.length > 0 
  ? conversation_history.map((msg, i) => `[${i + 1}] ${msg.role.toUpperCase()}: ${msg.content.substring(0, 100)}${msg.content.length > 100 ? '...' : ''}`).join('\n')
  : 'No conversation history'}

Total Messages: ${conversation_history ? conversation_history.length : 0}`
        };
        
        return res.json(debugResponse);
      }
      
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

You know your name is "Dumpling Hero" and you should never refer to yourself as any other name (such as AI, assistant, etc). However, you do not need to mention your name in every response—just avoid using any other name.

Your tone is humorous, professional, and casual. Feel free to make light-hearted jokes and puns, but never joke about items not on the menu (for example, do not joke about soup dumplings or anything we don't serve, to avoid confusing customers).

You're passionate about dumplings and love helping customers discover our authentic Chinese cuisine.

CRITICAL HONESTY GUIDELINES:
- NEVER make up information about menu items, ingredients, or restaurant details
- If you don't know specific details about something, simply don't mention those specifics
- Focus on what you do know from the provided menu and information
- If asked about something not covered in your knowledge, suggest calling the restaurant directly
- Always prioritize accuracy over speculation

MULTILINGUAL CAPABILITIES:
- You can communicate fluently in many languages. ALWAYS respond in the same language the customer uses, maintaining your warm personality and using culturally appropriate expressions.
- If unsure about a language, respond in English and ask if they'd prefer another language.

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

🥟 APPETIZERS:
- Edamame $4.99
- Asian Pickled Cucumbers $5.75
- (Crab & Shrimp) Cold Noodle w/ Peanut Sauce $8.35
- Peanut Butter Pork Dumplings $7.99
- Spicy Tofu $5.99
- Curry Rice w/ Chicken $7.75
- Jasmine White Rice $2.75

🍲 SOUP:
- Hot & Sour Soup $5.95
- Pork Wonton Soup $6.95
- Shrimp Wonton Soup $8.95

🍕 PIZZA DUMPLINGS (6 pieces):
- Pork $8.99
- Curry Beef & Onion $10.99

🍱 LUNCH SPECIAL (6 pieces - Monday-Friday only, ends at 4:00 PM):
- No.9 Pork $7.50
- No.2 Pork & Chive $8.50
- No.4 Pork Shrimp $9.00
- No.5 Pork & Cabbage $8.00
- No.3 Spicy Pork $8.00
- No.7 Curry Chicken $7.00
- No.8 Chicken & Coriander $7.50
- No.1 Chicken & Mushroom $8.00
- No.10 Curry Beef & Onion $8.50
- No.6 Veggie $7.50

🥟 DUMPLINGS (12 pieces):
- No.9 Pork $13.99
- No.2 Pork & Chive $15.99
- No.4 Pork Shrimp $16.99
- No.5 Pork & Cabbage $14.99
- No.3 Spicy Pork $14.99
- No.7 Curry Chicken $12.99
- No.8 Chicken & Coriander $13.99
- No.1 Chicken & Mushroom $14.99
- No.10 Curry Beef & Onion $15.99
- No.6 Veggie $13.99
- No.12 Half/Half $15.99

🧋 MILK TEA:
- Bubble Milk Tea w/ Tapioca $5.90
- Fresh Milk Tea $5.90
- Cookies n' Cream (Biscoff) $6.65
- Cream Brulee Cake $7.50
- Capped Thai Brown Sugar $6.90
- Strawberry Cake $6.75
- Strawberry Fresh $6.75
- Peach Fresh $6.50
- Pineapple Fresh $6.50
- Tiramisu Coco $6.85
- Coconut Coffee w/ Coffee Jelly $6.90
- Purple Yam Taro Fresh $6.85
- Oreo Chocolate $6.75

🍹 FRUIT TEA:
- Lychee Dragon Fruit $6.50
- Lychee Dragon Slush $7.50
- Grape Magic w/ Cheese Foam $6.90
- Full of Mango w/ Cheese Foam $6.90
- Peach Strawberry $6.75
- Kiwi Booster $6.75
- Tropical Passion Fruit Tea $6.75
- Pineapple $6.90
- Winter Melon Black $6.50
- Osmanthus Oolong w/ Cheese Foam $6.25
- Peach Oolong w/ Cheese Foam $6.25
- Ice Green $5.00
- Ice Black $5.00

☕ COFFEE:
- Jasmine Latte w/ Sea Salt $6.25
- Oreo Chocolate Latte $6.90
- Coconut Coffee w/ Coffee Jelly $6.90
- Matcha White Chocolate $6.90
- Coffee Latte $5.50

✨ DRINK TOPPINGS (add to any drink):
- Tapioca $0.75
- Whipped Cream $1.50
- Tiramisu Foam $1.25
- Cheese Foam $1.25
- Coffee Jelly $0.50
- Boba Jelly $0.50
- Lychee, Peach, Blue Lemon or Strawberry Popping Jelly $0.50
- Pineapple Nata Jelly $0.50
- Mango Star Jelly $0.50

🍋 LEMONADE OR SODA:
- Pineapple $5.50
- Lychee Mint $5.50
- Peach Mint $5.50
- Passion Fruit $5.25
- Mango $5.50
- Strawberry $5.50
- Grape $5.25
- Original Lemonade $5.50

🥣 SAUCES:
- Secret Peanut Sauce $1.50
- SPICY Secret Peanut Sauce $1.50
- Curry Sauce w/ Chicken $1.50

🥤 BEVERAGES:
- Coke $2.25
- Diet Coke $2.25
- Sprite $2.25
- Bottle Water $1.00
- Cup Water $1.00

SPECIAL DIETARY INFORMATION:
- Veggie dumplings include: cabbage, carrots, onions, celery, shiitake mushrooms, glass noodles
- We don't have anything vegan
- Everything has gluten
- We aren't sure what has MSG
- No delivery available
- Contains peanut butter: cold noodles with peanut sauce, cold tofu, peanut butter pork
- No complementary cups, but if you bring your own cup we can fill it with water
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
- MILK SUBSTITUTIONS: For customers with lactose intolerance, our milk teas and coffee lattes can be made with oat milk, almond milk, or coconut milk instead of regular milk. When recommending these drinks to lactose intolerant customers, always mention the milk substitution options available.

RECOMMENDATION GUIDELINES:
- Pair items that taste good together (spicy dumplings with sweet drinks, etc.). Focus on proven combinations customers love.
- Only mention "most popular" items when specifically asked about recommendations or popular items.

SERVICES:
- Dine-in and takeout available
- No delivery available
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
- Keep responses concise (2-3 sentences max) and end with a question to encourage conversation

Remember: You're not just an assistant—you love helping people discover the best dumplings in Nashville!${userPreferencesContext}

LOYALTY/REWARDS CONTEXT:
- User has ${typeof userPoints === 'number' ? userPoints : 'an unknown number of'} points. If points provided (${typeof userPoints === 'number' ? 'YES' : 'NO'}), personalize responses. If not provided, say "I don't see your points right now" and suggest opening Rewards tab or scanning receipt.
- REWARD TIERS: 250 (Sauce/Coke), 450 (Tea/Lemonade/Coffee), 500 (Small Appetizer), 650 (Large Appetizer), 850 (Pizza Dumplings/Lunch Special 6pc), 1500 (12pc Dumplings), 2000 (Full Combo).
- CRITICAL: If under 250 points, do NOT say they can redeem anything. Tell them they need 250+ points and how many more they need.
- Only mention rewards at or below their point balance. Don't list unaffordable rewards unless specifically asked about higher tiers.`;

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
        max_tokens: 1200,
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
      
      const { prompt, replyingTo, postContext } = req.body;
      
      // Debug logging for post context
      console.log('🔍 Post Context Analysis:');
      if (postContext && Object.keys(postContext).length > 0) {
        console.log('✅ Post context received:');
        console.log('   - Content:', postContext.content);
        console.log('   - Author:', postContext.authorName);
        console.log('   - Type:', postContext.postType);
        console.log('   - Images:', postContext.imageURLs?.length || 0);
        console.log('   - Has Menu Item:', !!postContext.attachedMenuItem);
        console.log('   - Has Poll:', !!postContext.poll);
        if (postContext.attachedMenuItem) {
          console.log('   - Menu Item:', postContext.attachedMenuItem.description);
        }
        if (postContext.poll) {
          console.log('   - Poll Question:', postContext.poll.question);
        }
      } else {
        console.log('❌ No post context received or empty context');
      }
      
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
{
  "commentText": "The generated comment text with emojis"
}

IMPORTANT: 
- Make the comment feel like you're genuinely responding to the context
- Keep it supportive and encouraging
- Don't be overly promotional - focus on being helpful and enthusiastic
- If replying to a specific comment, acknowledge what they said
- Make it naturally engaging so people want to continue the conversation
- Reference specific details from the post context when relevant

If a specific prompt is provided, use it as inspiration but maintain the Dumpling Hero personality.`;

      // Build the user message with post context
      let userMessage = "";
      
      // Add post context if available
      if (postContext && Object.keys(postContext).length > 0) {
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
        if (replyingTo) {
          userMessage += ` You're replying to: "${replyingTo}"`;
        }
      } else {
        let instruction = "Generate a Dumpling Hero comment that DIRECTLY REFERENCES specific details from the post context above. ";
        
        // Add specific instructions based on what's available
        if (postContext && Object.keys(postContext).length > 0) {
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
        }
        
        if (replyingTo) {
          instruction += ` You're replying to: "${replyingTo}"`;
        }
        userMessage += instruction;
      }

      console.log('🤖 Sending request to OpenAI for Dumpling Hero comment...');
      console.log('📤 Final user message being sent to OpenAI:');
      console.log('---START OF MESSAGE---');
      console.log(userMessage);
      console.log('---END OF MESSAGE---');
      
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

  // Dumpling Hero Comment Preview endpoint (for preview before posting)
  app.post('/preview-dumpling-hero-comment', async (req, res) => {
    try {
      console.log('🤖 Received Dumpling Hero comment preview request');
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
4. Support: "We've got your back! 🙌🥟 Dumpling House family!"
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
        console.log('🔍 Post Context Analysis for Preview Endpoint:');
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
        if (postContext && Object.keys(postContext).length > 0) {
          // When we have post context but no prompt, create a specific instruction
          userMessage += "Generate a Dumpling Hero comment that DIRECTLY REFERENCES the post context above. ";
          userMessage += "You MUST reference: ";
          
          if (postContext.content) {
            userMessage += `- The post content: "${postContext.content}" `;
          }
          
          if (postContext.caption) {
            userMessage += `- The caption: "${postContext.caption}" `;
          }
          
          if (postContext.videoURL) {
            userMessage += `- The video content `;
          }
          
          if (postContext.attachedMenuItem) {
            const item = postContext.attachedMenuItem;
            userMessage += `- The menu item: ${item.description} ($${item.price}) `;
            if (item.isDumpling) userMessage += "(this is a dumpling!) ";
            if (item.isDrink) userMessage += "(this is a drink!) ";
          }
          
          if (postContext.poll) {
            userMessage += `- The poll question: "${postContext.poll.question}" `;
          }
          
          if (postContext.imageURLs && postContext.imageURLs.length > 0) {
            userMessage += `- The ${postContext.imageURLs.length} image(s) in the post `;
          }
          
          userMessage += "Make your comment feel like you're genuinely responding to these specific details, not just giving a generic response!";
        } else {
          userMessage += "Generate a random Dumpling Hero comment. Make it supportive and enthusiastic!";
        }
      }

      console.log('🤖 Sending request to OpenAI for Dumpling Hero comment preview...');
      console.log('📝 User message being sent to ChatGPT:');
      console.log(userMessage);
      
      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage }
        ],
        max_tokens: 200,
        temperature: 0.8
      });

      console.log('✅ Received Dumpling Hero comment preview from OpenAI');
      
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
      console.error('❌ Error generating Dumpling Hero comment preview:', error);
      res.status(500).json({ 
        error: 'Failed to generate Dumpling Hero comment preview',
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
        if (postContext && Object.keys(postContext).length > 0) {
          // When we have post context but no prompt, create a specific instruction
          userMessage += "Generate a Dumpling Hero comment that DIRECTLY REFERENCES the post context above. ";
          userMessage += "You MUST reference: ";
          
          if (postContext.content) {
            userMessage += `- The post content: "${postContext.content}" `;
          }
          
          if (postContext.caption) {
            userMessage += `- The caption: "${postContext.caption}" `;
          }
          
          if (postContext.videoURL) {
            userMessage += `- The video content `;
          }
          
          if (postContext.attachedMenuItem) {
            const item = postContext.attachedMenuItem;
            userMessage += `- The menu item: ${item.description} ($${item.price}) `;
            if (item.isDumpling) userMessage += "(this is a dumpling!) ";
            if (item.isDrink) userMessage += "(this is a drink!) ";
          }
          
          if (postContext.poll) {
            userMessage += `- The poll question: "${postContext.poll.question}" `;
          }
          
          if (postContext.imageURLs && postContext.imageURLs.length > 0) {
            userMessage += `- The ${postContext.imageURLs.length} image(s) in the post `;
          }
          
          userMessage += "Make your comment feel like you're genuinely responding to these specific details, not just giving a generic response!";
        } else {
          userMessage += "Generate a random Dumpling Hero comment. Make it supportive and enthusiastic!";
        }
      }

      console.log('🤖 Sending request to OpenAI for simple Dumpling Hero comment...');
      console.log('📝 User message being sent to ChatGPT:');
      console.log(userMessage);
      
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

  // Redeem reward endpoint
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
}

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
