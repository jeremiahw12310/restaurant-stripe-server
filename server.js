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

// =============================================================================
// Basic in-memory rate limiting (per process)
// =============================================================================

function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.length > 0) {
    return forwarded.split(',')[0].trim();
  }
  return req.ip || req.connection?.remoteAddress || 'unknown';
}

function createInMemoryRateLimiter({ keyFn, windowMs, max, errorCode }) {
  const hits = new Map();

  return function rateLimiter(req, res, next) {
    const key = keyFn(req);
    if (!key) return next();

    const now = Date.now();
    const entry = hits.get(key);
    if (!entry || now > entry.resetAt) {
      hits.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }

    entry.count += 1;
    if (entry.count > max) {
      return res.status(429).json({
        errorCode: errorCode || 'RATE_LIMITED',
        error: 'Too many requests',
        retryAfterMs: Math.max(0, entry.resetAt - now)
      });
    }

    return next();
  };
}

const aiPerUserLimiter = createInMemoryRateLimiter({
  keyFn: (req) => req.auth?.uid,
  windowMs: 60 * 1000,
  max: 60,
  errorCode: 'AI_RATE_LIMITED'
});

const aiPerIpLimiter = createInMemoryRateLimiter({
  keyFn: (req) => getClientIp(req),
  windowMs: 60 * 1000,
  max: 30,
  errorCode: 'AI_RATE_LIMITED'
});

const analyzeReceiptLimiter = createInMemoryRateLimiter({
  keyFn: (req) => getClientIp(req),
  windowMs: 60 * 1000,
  max: 10,
  errorCode: 'RECEIPT_RATE_LIMITED'
});

const submitReceiptLimiter = createInMemoryRateLimiter({
  keyFn: (req) => getClientIp(req),
  windowMs: 60 * 1000,
  max: 10,
  errorCode: 'RECEIPT_RATE_LIMITED'
});

// Referral endpoints (moderate brute-force protection)
const referralPerUserLimiter = createInMemoryRateLimiter({
  keyFn: (req) => req.auth?.uid,
  windowMs: 60 * 1000,
  max: 5,
  errorCode: 'REFERRAL_RATE_LIMITED'
});

const referralPerIpLimiter = createInMemoryRateLimiter({
  keyFn: (req) => getClientIp(req),
  windowMs: 60 * 1000,
  max: 10,
  errorCode: 'REFERRAL_RATE_LIMITED'
});

// Banned number helpers (hash doc IDs to reduce enumeration)
function normalizePhoneForBannedNumbers(phone) {
  const digits = (phone || '').toString().replace(/\D/g, '');
  if (!digits || digits.length < 10) return null;
  const last10 = digits.slice(-10);
  return `+1${last10}`;
}

function hashBannedNumbersDocId(normalizedPhone) {
  const crypto = require('crypto');
  const value = (normalizedPhone || '').toString();
  if (!value) return null;
  return crypto.createHash('sha256').update(value).digest('hex');
}

// =============================================================================
// Auth helpers (cost protection / parity with deployed backend)
// =============================================================================

function getBearerToken(req) {
  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) return null;
  return authHeader.substring('Bearer '.length).trim() || null;
}

async function requireFirebaseAuth(req, res, next) {
  try {
    const token = getBearerToken(req);
    if (!token) {
      return res.status(401).json({ errorCode: 'UNAUTHENTICATED', error: 'Missing or invalid Authorization header' });
    }
    const decoded = await admin.auth().verifyIdToken(token);
    req.auth = { uid: decoded.uid, decoded };
    return next();
  } catch (e) {
    return res.status(401).json({ errorCode: 'UNAUTHENTICATED', error: 'Invalid auth token' });
  }
}

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
// Referral System Endpoints
// ---------------------------------------------------------------------------

// Create or get referral code
app.post('/referrals/create', requireFirebaseAuth, referralPerUserLimiter, referralPerIpLimiter, async (req, res) => {
  try {
    const uid = req.auth.uid;

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
      referralCode = await generateUniqueReferralCode(db);
      await userRef.update({ referralCode });
    }

    // Use custom URL scheme to avoid sandbox extension errors
    // For users who already have the app installed
    const directUrl = `restaurantdemo://referral?code=${referralCode}`;
    
    // Web redirect URL for users who don't have the app yet
    // Host this page on your domain or use a service like Firebase Hosting
    const webUrl = `https://dumplinghouseapp.web.app/refer?code=${referralCode}`;
    
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
app.post('/referrals/accept', requireFirebaseAuth, referralPerUserLimiter, referralPerIpLimiter, async (req, res) => {
  try {
    const uid = req.auth.uid;

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
app.get('/referrals/mine', requireFirebaseAuth, async (req, res) => {
  try {
    const uid = req.auth.uid;

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
function generateReferralCode(length = 6) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed ambiguous chars
  let code = '';
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

// Generate a referral code that is not currently used by any user.
async function generateUniqueReferralCode(db, length = 6, maxAttempts = 50) {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const candidate = generateReferralCode(length);
    const snap = await db.collection('users')
      .where('referralCode', '==', candidate)
      .limit(1)
      .get();
    if (snap.empty) {
      return candidate;
    }
  }
  throw new Error('Unable to generate unique referral code');
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

// App version check endpoint (public, no auth required)
// Returns the minimum required app version to force updates
app.get('/app-version', (req, res) => {
  try {
    // Get minimum required version from environment variable or use default
    // Format: "1.0.0" (major.minor.patch)
    const minimumRequiredVersion = process.env.MINIMUM_APP_VERSION || '1.0.0';
    
    // Optional: Get current App Store version (if you want to display it)
    const currentAppStoreVersion = process.env.CURRENT_APP_STORE_VERSION || null;
    
    // Optional: Custom update message
    const updateMessage = process.env.APP_UPDATE_MESSAGE || null;
    
    // Force update flag (set to false to allow graceful degradation)
    const forceUpdate = process.env.FORCE_APP_UPDATE !== 'false'; // Defaults to true
    
    res.json({
      minimumRequiredVersion,
      currentAppStoreVersion,
      updateMessage,
      forceUpdate
    });
  } catch (error) {
    console.error('❌ Error in /app-version endpoint:', error);
    // Return a safe default that won't lock users out
    res.json({
      minimumRequiredVersion: '0.0.0',
      currentAppStoreVersion: null,
      updateMessage: null,
      forceUpdate: false
    });
  }
});

// Generate personalized combo endpoint
app.post('/generate-combo', requireFirebaseAuth, aiPerUserLimiter, aiPerIpLimiter, async (req, res) => {
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

  // Standardized error response helper for observability + consistent client UX
  function sendError(res, httpStatus, errorCode, message, extra = {}) {
    return res.status(httpStatus).json({ errorCode, error: message, ...extra });
  }

  app.post('/analyze-receipt', analyzeReceiptLimiter, upload.single('image'), async (req, res) => {
    try {
      console.log('📥 Received receipt analysis request');
      
      if (!req.file) {
        console.log('❌ No image file received');
        return sendError(res, 400, "NO_IMAGE", "No image file provided");
      }
      
      console.log('📁 Image file received:', req.file.originalname, 'Size:', req.file.size);
      
      const imagePath = req.file.path;
      const imageData = fs.readFileSync(imagePath, { encoding: 'base64' });
      const db = admin.firestore();

      const prompt = `You are a receipt parser for Dumpling House. Follow these STRICT validation rules:

VALIDATION RULES:
1. If there are NO words stating "Dumpling House" at the top of the receipt, return {"error": "Invalid receipt - must be from Dumpling House"}
2. If there is anything covering up numbers or text on the receipt, and it affects the ORDER NUMBER, TOTAL, DATE, or TIME, treat this as tampering and do NOT accept the receipt.
3. TAMPERING DETECTION: Look for signs of obvious tampering or manipulation, especially on the ORDER NUMBER, TOTAL, DATE, or TIME:
   - If numbers appear to be digitally altered, edited, or photoshopped, return {"error": "Receipt appears to be tampered with - digital manipulation detected"}
   - If you can see evidence this is a photo of a screen/monitor (pixel patterns, screen glare, moiré effect), return {"error": "Invalid - please scan the original physical receipt, not a photo of a screen"}
   - If you can see this is a photo of another photo (edges of another photo visible, photo paper texture), return {"error": "Invalid - please scan the original receipt, not a photo of a photo"}
   - If numbers appear to be written over, crossed out, scribbled on, whited-out, or manually changed on the ORDER NUMBER, TOTAL, DATE, or TIME, return {"error": "Receipt appears to be tampered with - numbers have been altered"}
   - IMPORTANT: Employee checkmarks, circles, or handwritten notes on items are NORMAL and ALLOWED ONLY if they do NOT cover the digits of the ORDER NUMBER, TOTAL, DATE, or TIME. If any marking crosses through or obscures the digits of these key fields, treat it as tampering.
   - If the receipt looks artificially brightened or enhanced to hide alterations, return {"error": "Receipt appears to be digitally modified"}
4. CRITICAL LOCATION: The order number is ALWAYS directly underneath the word "Nashville" on the receipt. Look for "Nashville" and find the number immediately below it.
5. For DINE-IN orders: The order number is the BIGGER number inside the black box with white text, located directly under "Nashville". IGNORE any smaller numbers below the black box - those are NOT the order number.
6. For PICKUP orders: The order number is found directly underneath the word "Nashville" and may not be in a black box.
7. The order number is NEVER found further down on the receipt - it's always in the top section under "Nashville"
8. PAID ONLINE RECEIPTS (NO BLACK BOX): On the rare chance that there is NO black box at all for the order number anywhere in the top section under "Nashville", look to see if you can find that the receipt indicates it was paid online. This may appear as:
   - "paid online"
   - "customer paid online"
   - "new customer paid online"
   - or the words "paid" and "online" close together (even if split across lines).
   - If you do NOT see the words "paid online" anywhere on the receipt, you MUST NOT guess the order number from anywhere else. In this case, return {"error": "No valid order number found in black box under Nashville"}.
   - If you DO see "paid online" on the receipt, the ONLY valid order number is the number in bold font that appears immediately next to the label "Order:" on the ticket. You MUST:
     * Read the number that is in bold font right next to "Order:".
     * Treat this as the order number ONLY if it is clearly readable, not tampered with, and within the valid range (see below).
     * NOT use any other numbers anywhere else on the receipt as the order number.
   - If "paid online" is present but there is no clear bold number right next to "Order:", or that number is unclear, obscured, or tampered with, you MUST return {"error": "No valid order number found next to 'Order:' for paid online receipt"} and NOT guess from anywhere else.
9. If the order number is more than 3 digits, it cannot be the order number - look for a smaller number
10. Order numbers CANNOT be greater than 400 - if you see a number over 400, it's not the order number and should be ignored completely
10. CRITICAL: If the receipt is faded, blurry, hard to read, or if ANY numbers in the ORDER NUMBER, TOTAL, DATE, or TIME are unclear or difficult to see, return {"error": "Receipt is too faded or unclear - please take a clearer photo"} - DO NOT attempt to guess or estimate any numbers
11. If the image quality is poor and numbers (especially the ORDER NUMBER, TOTAL, DATE, or TIME) are blurry, unclear, or hard to read, return {"error": "Poor image quality - please take a clearer photo"}
12. ALWAYS return the date as MM/DD format only (no year, no other format). If the receipt prints the date with a hyphen (MM-DD), convert it to MM/DD in your output.
13. CRITICAL: You MUST double-check all extracted information before returning it. Verify that the order number, total, and date are accurate and match what you see on the receipt. This is essential for preventing system abuse and maintaining data integrity.

EXTRACTION RULES:
- orderNumber: CRITICAL - Find the number INSIDE the black box with white text that is located directly underneath the word "Nashville" on the receipt. This black box is the ONLY valid source for the order number when a black box is present. On receipts where there is no such black box at all, you MUST follow the paid-online rules described above: only use the bold number immediately next to "Order:" on receipts that clearly say "paid online", and otherwise return an appropriate error without guessing from anywhere else on the receipt.
- orderTotal: The total amount paid (as a number, e.g. 23.45)
- orderDate: The date in MM/DD format only (e.g. "12/25")
- orderTime: The time in HH:MM format only (e.g. "14:30"). This is always located to the right of the date on the receipt.

VISIBILITY & TAMPERING FLAGS:
- You MUST also return the following boolean flags describing the visibility and tampering status of each key field:
  - totalVisibleAndClear: true if the TOTAL digits are fully visible, unobscured, and clearly readable. false if any part of the total is blurred, cropped, covered, scribbled on, crossed out, or otherwise unclear.
  - orderNumberVisibleAndClear: true if the ORDER NUMBER digits are fully visible, unobscured, and clearly readable. false if any part is blurred, cropped, covered, scribbled on, crossed out, or otherwise unclear.
  - dateVisibleAndClear: true if the DATE digits are fully visible, unobscured, and clearly readable. false if any part is blurred, cropped, covered, scribbled on, crossed out, or otherwise unclear.
  - timeVisibleAndClear: true if the TIME digits are fully visible, unobscured, and clearly readable. false if any part is blurred, cropped, covered, scribbled on, crossed out, or otherwise unclear.
- You MUST also return:
  - keyFieldsTampered: true if you see ANY evidence of scribbles, crossings-out, overwriting, white-out, or manual changes on the ORDER NUMBER, TOTAL, DATE, or TIME. Otherwise false.
  - tamperingReason: a short string explaining the tampering if keyFieldsTampered is true (for example: "date is scribbled over", "order number crossed out and rewritten", or "heavy marker drawn over total").
  - orderNumberInBlackBox: true if and only if the orderNumber you returned was read from INSIDE the black box directly under "Nashville". If there is no black box or no number inside it, set this to false.
  - orderNumberDirectlyUnderNashville: true if and only if the orderNumber you returned was read from the number immediately under the word "Nashville" in the top section (pickup receipts may not show a black box). If you did NOT use that number, set this to false.
  - paidOnlineReceipt: true if and only if the receipt clearly contains the words "paid online" and you are using the paid-online fallback path (bold number next to "Order:") described above. Otherwise false.
  - orderNumberFromPaidOnlineSection: true if and only if the orderNumber you returned was read from the bold number immediately next to the label "Order:" on a paid-online receipt. Otherwise false.

IMPORTANT: 
- CRITICAL LOCATION: The only valid order number is the number inside the black box with white text directly underneath the word "Nashville" on the receipt. Do not use any other number anywhere else on the receipt as the order number.
- TIME LOCATION: The time is ALWAYS located to the right of the date on the receipt and must be in HH:MM format.
- If you cannot clearly read the numbers due to poor image quality, DO NOT GUESS. Return an error instead.
- If the receipt is faded, blurry, or any numbers are unclear, DO NOT ATTEMPT TO READ THEM. Return an error immediately.
- Order numbers must be between 1-400. Any number over 400 is completely invalid and should not be returned at all.
- If the only numbers you see are over 400, return {"error": "No valid order number found - order numbers must be under 400"}
- DOUBLE-CHECK REQUIREMENT: Before returning any data, carefully review the extracted order number, total, date, and time to ensure they are accurate and match the receipt. Also carefully review whether any part of these fields is obscured or tampered with, and set the visibility/tampering flags accordingly. This verification step is crucial for preventing fraud and maintaining system integrity.
- SAFETY FIRST: It's better to reject a receipt and ask for a clearer photo than to guess and return incorrect information. If you are not highly confident about any of the key fields, treat the receipt as invalid and return an error message instead of guessing.

Respond ONLY as a JSON object with this exact shape:
{"orderNumber": "...", "orderTotal": ..., "orderDate": "...", "orderTime": "...", "totalVisibleAndClear": true/false, "orderNumberVisibleAndClear": true/false, "dateVisibleAndClear": true/false, "timeVisibleAndClear": true/false, "keyFieldsTampered": true/false, "tamperingReason": "...", "orderNumberInBlackBox": true/false, "orderNumberDirectlyUnderNashville": true/false, "paidOnlineReceipt": true/false, "orderNumberFromPaidOnlineSection": true/false} 
or {"error": "error message"}.
If a field is missing, use null.`;

      console.log('🤖 Sending request to OpenAI for FIRST validation...');
      console.log('📊 API Call 1 - Starting at:', new Date().toISOString());
      
      // First OpenAI call
      const response1 = await openai.chat.completions.create({
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
        max_tokens: 500,
        temperature: 0.1
      });

      console.log('✅ First OpenAI response received');
      console.log('📊 API Call 1 - Completed at:', new Date().toISOString());
      
      console.log('🤖 Sending request to OpenAI for SECOND validation...');
      console.log('📊 API Call 2 - Starting at:', new Date().toISOString());
      
      // Second OpenAI call
      const response2 = await openai.chat.completions.create({
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
        return sendError(res, 422, "AI_JSON_EXTRACT_FAILED", "Could not extract JSON from first response", { raw: text1 });
      }
      
      const data1 = JSON.parse(jsonMatch1[0]);
      console.log('✅ Parsed JSON data 1:', data1);
      
      // Parse second response
      const text2 = response2.choices[0].message.content;
      console.log('📝 Raw OpenAI response 2:', text2);
      
      const jsonMatch2 = text2.match(/\{[\s\S]*\}/);
      if (!jsonMatch2) {
        console.log('❌ Could not extract JSON from second response');
        return sendError(res, 422, "AI_JSON_EXTRACT_FAILED", "Could not extract JSON from second response", { raw: text2 });
      }
      
      const data2 = JSON.parse(jsonMatch2[0]);
      console.log('✅ Parsed JSON data 2:', data2);
      
      // Check if either response contains an error
      if (data1.error) {
        console.log('❌ First validation failed:', data1.error);
        return sendError(res, 400, "AI_VALIDATION_FAILED", data1.error);
      }
      
      if (data2.error) {
        console.log('❌ Second validation failed:', data2.error);
        return sendError(res, 400, "AI_VALIDATION_FAILED", data2.error);
      }

      // Normalize both responses BEFORE comparing to reduce false mismatches
      // (e.g., "12-21" vs "12/21", whitespace, numeric string formatting).
      const normalizeOrderDate = (v) => {
        if (typeof v !== 'string') return v;
        const s = v.trim().replace(/-/g, '/');
        // If it's MM/DD already, keep; otherwise return as-is (later validation will reject).
        return s;
      };
      const normalizeOrderTime = (v) => (typeof v === 'string' ? v.trim() : v);
      const normalizeOrderNumber = (v) => {
        if (v === null || v === undefined) return v;
        const s = String(v).trim();
        // preserve string form but remove leading zeros consistently (e.g., "058" -> "58")
        if (/^\d+$/.test(s)) return String(parseInt(s, 10));
        return s;
      };
      const normalizeMoney = (v) => {
        if (v === null || v === undefined) return v;
        const n = typeof v === 'number' ? v : parseFloat(String(v).trim());
        if (Number.isNaN(n)) return v;
        // Round to cents to avoid representation mismatch (e.g., 56.6 vs 56.60 vs 56.6000001)
        return Math.round(n * 100) / 100;
      };
      const normalizeParsedReceipt = (d) => ({
        // carry through the rest untouched
        ...d,
        // then override the canonical fields with normalized values
        orderNumber: normalizeOrderNumber(d.orderNumber),
        orderTotal: normalizeMoney(d.orderTotal),
        tipAmount: normalizeMoney(d.tipAmount),
        orderDate: normalizeOrderDate(d.orderDate),
        orderTime: normalizeOrderTime(d.orderTime),
      });

      const norm1 = normalizeParsedReceipt(data1);
      const norm2 = normalizeParsedReceipt(data2);
      
      // Compare the two responses
      console.log('🔍 COMPARING TWO VALIDATIONS:');
      console.log('   Response 1 - Order Number:', norm1.orderNumber, 'Total:', norm1.orderTotal, 'Date:', norm1.orderDate, 'Time:', norm1.orderTime);
      console.log('   Response 2 - Order Number:', norm2.orderNumber, 'Total:', norm2.orderTotal, 'Date:', norm2.orderDate, 'Time:', norm2.orderTime);
      
      // Check if responses match
      const responsesMatch = 
        norm1.orderNumber === norm2.orderNumber &&
        norm1.orderTotal === norm2.orderTotal &&
        norm1.tipAmount === norm2.tipAmount &&
        norm1.tipLineVisible === norm2.tipLineVisible &&
        norm1.orderDate === norm2.orderDate &&
        norm1.orderTime === norm2.orderTime;
      
      console.log('🔍 COMPARISON DETAILS:');
      console.log('   Order Number Match:', norm1.orderNumber === norm2.orderNumber, `(${norm1.orderNumber} vs ${norm2.orderNumber})`);
      console.log('   Order Total Match:', norm1.orderTotal === norm2.orderTotal, `(${norm1.orderTotal} vs ${norm2.orderTotal})`);
      console.log('   Order Date Match:', norm1.orderDate === norm2.orderDate, `(${norm1.orderDate} vs ${norm2.orderDate})`);
      console.log('   Order Time Match:', norm1.orderTime === norm2.orderTime, `(${norm1.orderTime} vs ${norm2.orderTime})`);
      console.log('   Overall Match:', responsesMatch);
      
      if (!responsesMatch) {
        console.log('❌ VALIDATION MISMATCH - Responses do not match');
        console.log('   This indicates unclear or ambiguous receipt data');
        return sendError(
          res,
          400,
          "DOUBLE_PARSE_MISMATCH",
          "Receipt data is unclear - the two validations returned different results. Please take a clearer photo of the receipt."
        );
      }
      
      console.log('✅ VALIDATION MATCH - Both responses are identical');
      
      // Use the validated data (both are the same)
      const data = norm1;

      // Normalize date formatting to MM/DD (accept MM-DD from model/receipt)
      if (typeof data.orderDate === 'string') {
        data.orderDate = data.orderDate.trim().replace(/-/g, '/');
      }
      
      // Validate that we have the required fields
      if (!data.orderNumber || !data.orderTotal || !data.orderDate || !data.orderTime) {
        console.log('❌ Missing required fields in receipt data');
        return sendError(res, 400, "MISSING_FIELDS", "Could not extract all required fields from receipt");
      }

      // Validate visibility and tampering flags for key fields
      const totalVisibleAndClear = data.totalVisibleAndClear;
      const orderNumberVisibleAndClear = data.orderNumberVisibleAndClear;
      const dateVisibleAndClear = data.dateVisibleAndClear;
      const timeVisibleAndClear = data.timeVisibleAndClear;
      const keyFieldsTampered = data.keyFieldsTampered;
      const tamperingReason = data.tamperingReason;
      const orderNumberInBlackBox = data.orderNumberInBlackBox;
      const orderNumberDirectlyUnderNashville = data.orderNumberDirectlyUnderNashville;
      const paidOnlineReceipt = data.paidOnlineReceipt;
      const orderNumberFromPaidOnlineSection = data.orderNumberFromPaidOnlineSection;

      // Determine whether the order number came from a valid source:
      //  - Either from the black box under "Nashville"
      //  - Or, directly underneath "Nashville" on pickup receipts with no black box
      //  - Or, on a paid-online receipt with no black box, from the bold number next to "Order:"
      const orderNumberSourceIsValid =
        orderNumberInBlackBox === true ||
        orderNumberDirectlyUnderNashville === true ||
        orderNumberFromPaidOnlineSection === true;

      // If any of the visibility flags are explicitly false, keyFieldsTampered is true,
      // or the order number did not come from a valid, allowed source, reject the receipt
      if (
        totalVisibleAndClear === false ||
        orderNumberVisibleAndClear === false ||
        dateVisibleAndClear === false ||
        timeVisibleAndClear === false ||
        keyFieldsTampered === true ||
        !orderNumberSourceIsValid
      ) {
        console.log('❌ Receipt rejected due to obscured/tampered key fields or invalid order number source', {
          totalVisibleAndClear,
          orderNumberVisibleAndClear,
          dateVisibleAndClear,
          timeVisibleAndClear,
          keyFieldsTampered,
          tamperingReason,
          orderNumberInBlackBox,
          paidOnlineReceipt,
          orderNumberFromPaidOnlineSection
        });

        // If the only issue is the order number source (no valid source used) and there is no tampering,
        // surface a specific error depending on whether this was a paid-online receipt or not.
        if (!orderNumberSourceIsValid && keyFieldsTampered !== true) {
          if (paidOnlineReceipt === true) {
            return sendError(res, 400, "ORDER_NUMBER_SOURCE_INVALID", "No valid order number found next to 'Order:' for paid online receipt");
          }
          return sendError(res, 400, "ORDER_NUMBER_SOURCE_INVALID", "No valid order number found under Nashville");
        }

        const msg = tamperingReason && typeof tamperingReason === 'string' && tamperingReason.trim().length > 0
            ? `Receipt invalid - ${tamperingReason}`
          : "Receipt invalid - key information is obscured or appears tampered with";
        return sendError(res, 400, "KEY_FIELDS_INVALID", msg, { tamperingReason: tamperingReason || null });
      }
      
      // Validate order number format (must be 3 digits or less and not exceed 400)
      const orderNumberStr = data.orderNumber.toString();
      console.log('🔍 Validating order number:', orderNumberStr);
      
      if (orderNumberStr.length > 3) {
        console.log('❌ Order number too long:', orderNumberStr);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number format - must be 3 digits or less");
      }
      
      const orderNumber = parseInt(data.orderNumber);
      console.log('🔍 Parsed order number:', orderNumber);
      
      if (isNaN(orderNumber)) {
        console.log('❌ Order number is not a valid number:', data.orderNumber);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be a valid number");
      }
      
      if (orderNumber < 1) {
        console.log('❌ Order number too small:', orderNumber);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be at least 1");
      }
      
      if (orderNumber > 400) {
        console.log('❌ Order number too large (over 400):', orderNumber);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be 400 or less");
      }
      
      console.log('✅ Order number validation passed:', orderNumber);
      
      // Validate date format (must be MM/DD; accept MM-DD but normalized above)
      const dateRegex = /^\d{2}\/\d{2}$/;
      if (!dateRegex.test(data.orderDate)) {
        console.log('❌ Invalid date format:', data.orderDate);
        return sendError(res, 400, "DATE_FORMAT_INVALID", "Invalid date format - must be MM/DD (or MM-DD on receipt)");
      }
      
      // Validate time format (must be HH:MM)
      const timeRegex = /^\d{2}:\d{2}$/;
      if (!timeRegex.test(data.orderTime)) {
        console.log('❌ Invalid time format:', data.orderTime);
        return sendError(res, 400, "TIME_FORMAT_INVALID", "Invalid time format - must be HH:MM");
      }
      
      // Validate time is reasonable (00:00 to 23:59)
      const [hours, minutes] = data.orderTime.split(':').map(Number);
      if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
        console.log('❌ Invalid time values:', data.orderTime);
        return sendError(res, 400, "TIME_FORMAT_INVALID", "Invalid time - must be between 00:00 and 23:59");
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
        return sendError(res, 400, "TOTAL_INVALID", "Invalid order total - must be a reasonable amount between $1 and $500");
      }
      
      // Validate date is reasonable (cannot be in the future and not too far in the past)
      const [month, day] = data.orderDate.split('/').map(Number);
      const currentDate = new Date();
      const [h, m] = data.orderTime.split(':').map(Number);

      // Admin-only override for testing old receipts:
      // If the caller has explicitly enabled old-receipt testing on their user profile,
      // we relax the 48-hour window check (for this user only) but still enforce all other validations.
      //
      // NOTE: We key primarily off `oldReceiptTestingEnabled` because it is admin-controlled in Firestore
      // (and the Admin SDK bypasses rules anyway). This avoids false negatives if `isAdmin` is missing/stale.
      let allowOldReceiptForAdmin = false;
      try {
        const authHeader = req.headers.authorization || '';
        const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
        if (token) {
          const decoded = await admin.auth().verifyIdToken(token);
          const uid = decoded.uid;
          const userDoc = await admin.firestore().collection('users').doc(uid).get();
          if (userDoc.exists) {
            const userData = userDoc.data() || {};
            if (userData.oldReceiptTestingEnabled === true) {
              allowOldReceiptForAdmin = true;
              console.log('⚠️ Old-receipt test mode active for user:', uid, 'daysDiff:', daysDiff, 'isAdmin:', userData.isAdmin === true);
            }
          }
        }
      } catch (err) {
        console.warn('⚠️ Failed to evaluate admin old-receipt test override:', err.message || err);
      }

      // Build a year-safe receipt DateTime:
      // - First assume current year
      // - If that looks "far future" but the previous year lands within ~48h, treat as year-boundary scan
      const receiptDateThisYear = new Date(currentDate.getFullYear(), month - 1, day, h, m, 0, 0);
      const receiptDatePrevYear = new Date(currentDate.getFullYear() - 1, month - 1, day, h, m, 0, 0);

      const hoursDiffThisYear = (currentDate - receiptDateThisYear) / (1000 * 60 * 60);
      const hoursDiffPrevYear = (currentDate - receiptDatePrevYear) / (1000 * 60 * 60);

      // If the receipt appears to be in the future this year:
      // - If old-receipt testing is enabled, interpret it as last year (receipts omit year)
      // - Else allow only the special-case where last year lands within 48h (New Year boundary)
      let receiptDate = receiptDateThisYear;
      let hoursDiff = hoursDiffThisYear;
      if (hoursDiffThisYear < 0) {
        if (allowOldReceiptForAdmin) {
          receiptDate = receiptDatePrevYear;
          hoursDiff = hoursDiffPrevYear;
          console.log('⚠️ Old-receipt test mode: treating future-date receipt as previous year:', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiff);
        } else if (hoursDiffPrevYear >= 0 && hoursDiffPrevYear <= 48) {
          receiptDate = receiptDatePrevYear;
          hoursDiff = hoursDiffPrevYear;
          console.log('🗓️ Year-boundary adjustment applied for receipt date:', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiff);
        } else {
          console.log('❌ Receipt date appears to be in the future:', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiffThisYear);
          return sendError(res, 400, "FUTURE_DATE", "Invalid receipt date - receipt appears to be dated in the future");
        }
      }

      // Keep daysDiff for existing logs (derived from hours for consistency)
      const daysDiff = hoursDiff / 24;

      if (hoursDiff > 48 && !allowOldReceiptForAdmin) {
        console.log('❌ Receipt date too old:', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiff);
        return sendError(res, 400, "EXPIRED_48H", "Receipt expired - receipts must be scanned within 48 hours of purchase");
      }
      
      console.log('✅ All validations passed - data integrity confirmed');
      
      // DUPLICATE DETECTION SYSTEM
      console.log('🔍 CHECKING FOR DUPLICATE RECEIPTS...');
      
      try {
        // Query Firestore for existing receipts with matching criteria
        const receiptsRef = db.collection('receipts');
        
        // Check for duplicates: if ANY 2 of the 3 fields match (orderNumber, date, time),
        // OR if date, time, and total ALL match (strong duplicate signal)
        //
        // NOTE: Older data may have stored `orderNumber` as a number, while newer code uses a string.
        // To avoid missing duplicates across that migration, we check both variants when possible.
        const orderNumberStrForDup = String(data.orderNumber);
        const orderNumberNumForDup = parseInt(orderNumberStrForDup, 10);
        const orderNumberVariants = [orderNumberStrForDup];
        if (!isNaN(orderNumberNumForDup)) orderNumberVariants.push(orderNumberNumForDup);

        const duplicateQueries = [
          // Same date AND time
          receiptsRef.where('orderDate', '==', data.orderDate).where('orderTime', '==', data.orderTime),
          // Same date, time, AND total (even if order number differs)
          receiptsRef.where('orderDate', '==', data.orderDate).where('orderTime', '==', data.orderTime).where('orderTotal', '==', orderTotal)
        ];

        for (const variant of orderNumberVariants) {
          // Same order number AND date
          duplicateQueries.push(
            receiptsRef.where('orderNumber', '==', variant).where('orderDate', '==', data.orderDate)
          );
          // Same order number AND time
          duplicateQueries.push(
            receiptsRef.where('orderNumber', '==', variant).where('orderTime', '==', data.orderTime)
          );
        }
        
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
          return sendError(
            res,
            409,
            "DUPLICATE_RECEIPT",
            "Receipt already submitted - this receipt has already been processed and points will not be awarded",
            { duplicate: true }
          );
        }
        
        console.log('✅ No duplicates found - receipt is unique');

        // Persist this validated receipt so future scans can be checked reliably
        try {
          await receiptsRef.add({
            orderNumber: String(data.orderNumber),
            orderDate: data.orderDate,
            orderTime: data.orderTime,
            orderTotal: orderTotal,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
          });
          console.log('💾 Saved receipt to receipts collection for future duplicate checks');
        } catch (saveError) {
          console.log('❌ Error saving receipt record:', saveError.message);
          // For safety, do NOT award points if we cannot persist the receipt
          return sendError(res, 500, "SERVER_SAVE_FAILED", "Server error while saving receipt - please try again with a clear photo");
        }
        
      } catch (duplicateError) {
        console.log('❌ Error checking for duplicates:', duplicateError.message);
        // For safety, do NOT award points if we cannot verify duplicates
        return sendError(res, 500, "SERVER_DUPLICATE_CHECK_FAILED", "Server error while verifying receipt uniqueness - please try again with a clear photo");
      }
      
      res.json(data);
    } catch (err) {
      console.error('❌ Error processing receipt:', err);
      return sendError(res, 500, "SERVER_ERROR", err.message || "Server error");
    }
  });

  // Receipt submit endpoint (server-authoritative points awarding)
  // This endpoint validates the receipt and awards points atomically on the server.
  // It does NOT rely on the client to update points, improving integrity.
  app.post('/submit-receipt', requireFirebaseAuth, submitReceiptLimiter, upload.single('image'), async (req, res) => {
    try {
      console.log('📥 Received receipt SUBMISSION request');

      const uid = req.auth.uid;

      if (!req.file) {
        console.log('❌ No image file received');
        return sendError(res, 400, "NO_IMAGE", "No image file provided");
      }

      console.log('📁 Image file received:', req.file.originalname, 'Size:', req.file.size);

      const imagePath = req.file.path;
      const imageData = fs.readFileSync(imagePath, { encoding: 'base64' });
      const db = admin.firestore();

      // Reuse the same strict prompt as /analyze-receipt (kept in sync).
      const prompt = `You are a receipt parser for Dumpling House. Follow these STRICT validation rules:

VALIDATION RULES:
1. If there are NO words stating "Dumpling House" at the top of the receipt, return {"error": "Invalid receipt - must be from Dumpling House"}
2. If there is anything covering up numbers or text on the receipt, and it affects the ORDER NUMBER, TOTAL, DATE, or TIME, treat this as tampering and do NOT accept the receipt.
3. TAMPERING DETECTION: Look for signs of obvious tampering or manipulation, especially on the ORDER NUMBER, TOTAL, DATE, or TIME:
   - If numbers appear to be digitally altered, edited, or photoshopped, return {"error": "Receipt appears to be tampered with - digital manipulation detected"}
   - If you can see evidence this is a photo of a screen/monitor (pixel patterns, screen glare, moiré effect), return {"error": "Invalid - please scan the original physical receipt, not a photo of a screen"}
   - If you can see this is a photo of another photo (edges of another photo visible, photo paper texture), return {"error": "Invalid - please scan the original receipt, not a photo of a photo"}
   - If numbers appear to be written over, crossed out, scribbled on, whited-out, or manually changed on the ORDER NUMBER, TOTAL, DATE, or TIME, return {"error": "Receipt appears to be tampered with - numbers have been altered"}
   - IMPORTANT: Employee checkmarks, circles, or handwritten notes on items are NORMAL and ALLOWED ONLY if they do NOT cover the digits of the ORDER NUMBER, TOTAL, DATE, or TIME. If any marking crosses through or obscures the digits of these key fields, treat it as tampering.
   - If the receipt looks artificially brightened or enhanced to hide alterations, return {"error": "Receipt appears to be digitally modified"}
4. CRITICAL LOCATION: The order number is ALWAYS directly underneath the word "Nashville" on the receipt. Look for "Nashville" and find the number immediately below it.
5. For DINE-IN orders: The order number is the BIGGER number inside the black box with white text, located directly under "Nashville". IGNORE any smaller numbers below the black box - those are NOT the order number.
6. For PICKUP orders: The order number is found directly underneath the word "Nashville" and may not be in a black box.
7. The order number is NEVER found further down on the receipt - it's always in the top section under "Nashville"
8. PAID ONLINE RECEIPTS (NO BLACK BOX): On the rare chance that there is NO black box at all for the order number anywhere in the top section under "Nashville", look to see if you can find that the receipt indicates it was paid online. This may appear as:
   - "paid online"
   - "customer paid online"
   - "new customer paid online"
   - or the words "paid" and "online" close together (even if split across lines).
   - If you do NOT see the words "paid online" anywhere on the receipt, you MUST NOT guess the order number from anywhere else. In this case, return {"error": "No valid order number found under Nashville"}.
   - If you DO see "paid online" on the receipt, the ONLY valid order number is the number in bold font that appears immediately next to the label "Order:" on the ticket. You MUST:
     * Read the number that is in bold font right next to "Order:".
     * Treat this as the order number ONLY if it is clearly readable, not tampered with, and within the valid range (see below).
     * NOT use any other numbers anywhere else on the receipt as the order number.
   - If "paid online" is present but there is no clear bold number right next to "Order:", or that number is unclear, obscured, or tampered with, you MUST return {"error": "No valid order number found next to 'Order:' for paid online receipt"} and NOT guess from anywhere else on the receipt.
9. If the order number is more than 3 digits, it cannot be the order number - look for a smaller number
10. Order numbers CANNOT be greater than 400 - if you see a number over 400, it's not the order number and should be ignored completely
10. CRITICAL: If the receipt is faded, blurry, hard to read, or if ANY numbers in the ORDER NUMBER, TOTAL, DATE, or TIME are unclear or difficult to see, return {"error": "Receipt is too faded or unclear - please take a clearer photo"} - DO NOT attempt to guess or estimate any numbers
11. If the image quality is poor and numbers (especially the ORDER NUMBER, TOTAL, DATE, or TIME) are blurry, unclear, or hard to read, return {"error": "Poor image quality - please take a clearer photo"}
12. ALWAYS return the date as MM/DD format only (no year, no other format). If the receipt prints the date with a hyphen (MM-DD), convert it to MM/DD in your output.
13. CRITICAL: You MUST double-check all extracted information before returning it. Verify that the order number, total, and date are accurate and match what you see on the receipt. This is essential for preventing system abuse and maintaining data integrity.

EXTRACTION RULES:
- orderNumber: CRITICAL - Find the number INSIDE the black box with white text that is located directly underneath the word "Nashville" on the receipt. This black box is the ONLY valid source for the order number when a black box is present. On pickup receipts, the order number may be directly under "Nashville" without a black box. On receipts where there is no such black box at all, you MUST follow the paid-online rules described above: only use the bold number immediately next to "Order:" on receipts that clearly say "paid online", and otherwise return an appropriate error without guessing from anywhere else on the receipt.
- orderTotal: The total amount paid (as a number, e.g. 23.45)
- tipAmount: The TIP/GRATUITY amount as a number (e.g. 4.81) or null if not visible.
- tipLineVisible: true only if the Tip/Gratuity line (label + digits) is clearly visible. Otherwise false.
- orderDate: The date in MM/DD format only (e.g. "12/25")
- orderTime: The time in HH:MM format only (e.g. "14:30"). This is always located to the right of the date on the receipt.

VISIBILITY & TAMPERING FLAGS:
- You MUST also return the following boolean flags describing the visibility and tampering status of each key field:
  - totalVisibleAndClear: true if the TOTAL digits are fully visible, unobscured, and clearly readable. false if any part of the total is blurred, cropped, covered, scribbled on, crossed out, or otherwise unclear.
  - orderNumberVisibleAndClear: true if the ORDER NUMBER digits are fully visible, unobscured, and clearly readable. false if any part is blurred, cropped, covered, scribbled on, crossed out, or otherwise unclear.
  - dateVisibleAndClear: true if the DATE digits are fully visible, unobscured, and clearly readable. false if any part is blurred, cropped, covered, scribbled on, crossed out, or otherwise unclear.
  - timeVisibleAndClear: true if the TIME digits are fully visible, unobscured, and clearly readable. false if any part is blurred, cropped, covered, scribbled on, crossed out, or otherwise unclear.
- You MUST also return:
  - keyFieldsTampered: true if you see ANY evidence of scribbles, crossings-out, overwriting, white-out, or manual changes on the ORDER NUMBER, TOTAL, DATE, or TIME. Otherwise false.
  - tamperingReason: a short string explaining the tampering if keyFieldsTampered is true (for example: "date is scribbled over", "order number crossed out and rewritten", or "heavy marker drawn over total").
  - orderNumberInBlackBox: true if and only if the orderNumber you returned was read from INSIDE the black box directly under "Nashville". If there is no black box or no number inside it, set this to false.
  - orderNumberDirectlyUnderNashville: true if and only if the orderNumber you returned was read from the number immediately under the word "Nashville" in the top section (pickup receipts may not show a black box). If you did NOT use that number, set this to false.
  - paidOnlineReceipt: true if and only if the receipt clearly contains the words "paid online" and you are using the paid-online fallback path (bold number next to "Order:") described above. Otherwise false.
  - orderNumberFromPaidOnlineSection: true if and only if the orderNumber you returned was read from the bold number immediately next to the label "Order:" on a paid-online receipt. Otherwise false.

IMPORTANT: 
- CRITICAL LOCATION: The only valid order number is the number inside the black box with white text directly underneath the word "Nashville" on the receipt, OR (for pickup) the number directly underneath "Nashville", OR (paid online fallback) the bold number next to "Order:".
- TIME LOCATION: The time is ALWAYS located to the right of the date on the receipt and must be in HH:MM format.
- If you cannot clearly read the numbers due to poor image quality, DO NOT GUESS. Return an error instead.
- If the receipt is faded, blurry, or any numbers are unclear, DO NOT ATTEMPT TO READ THEM. Return an error immediately.
- Order numbers must be between 1-400. Any number over 400 is completely invalid and should not be returned at all.
- If the only numbers you see are over 400, return {"error": "No valid order number found - order numbers must be under 400"}
- DOUBLE-CHECK REQUIREMENT: Before returning any data, carefully review the extracted order number, total, date, and time to ensure they are accurate and match the receipt. Also carefully review whether any part of these fields is obscured or tampered with, and set the visibility/tampering flags accordingly. This verification step is crucial for preventing fraud and maintaining system integrity.
- SAFETY FIRST: It's better to reject a receipt and ask for a clearer photo than to guess and return incorrect information. If you are not highly confident about any of the key fields, treat the receipt as invalid and return an error message instead of guessing.

Respond ONLY as a JSON object with this exact shape:
{"orderNumber": "...", "orderTotal": ..., "tipAmount": ..., "tipLineVisible": true/false, "orderDate": "...", "orderTime": "...", "totalVisibleAndClear": true/false, "orderNumberVisibleAndClear": true/false, "dateVisibleAndClear": true/false, "timeVisibleAndClear": true/false, "keyFieldsTampered": true/false, "tamperingReason": "...", "orderNumberInBlackBox": true/false, "orderNumberDirectlyUnderNashville": true/false, "paidOnlineReceipt": true/false, "orderNumberFromPaidOnlineSection": true/false} 
or {"error": "error message"}.
If a field is missing, use null.`;

      console.log('🤖 Sending request to OpenAI for FIRST validation (submit-receipt)...');
      const response1 = await openai.chat.completions.create({
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
        max_tokens: 500,
        temperature: 0.1
      });

      console.log('🤖 Sending request to OpenAI for SECOND validation (submit-receipt)...');
      const response2 = await openai.chat.completions.create({
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
        max_tokens: 500,
        temperature: 0.1
      });

      // Clean up the uploaded file
      fs.unlinkSync(imagePath);

      const extractJson = (text) => {
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (!jsonMatch) return null;
        return JSON.parse(jsonMatch[0]);
      };

      const text1 = response1.choices[0].message.content;
      const text2 = response2.choices[0].message.content;
      const data1 = extractJson(text1);
      const data2 = extractJson(text2);
      if (!data1) return sendError(res, 422, "AI_JSON_EXTRACT_FAILED", "Could not extract JSON from first response", { raw: text1 });
      if (!data2) return sendError(res, 422, "AI_JSON_EXTRACT_FAILED", "Could not extract JSON from second response", { raw: text2 });

      if (data1.error) return sendError(res, 400, "AI_VALIDATION_FAILED", data1.error);
      if (data2.error) return sendError(res, 400, "AI_VALIDATION_FAILED", data2.error);

      // Normalize before comparing
      const normalizeOrderDate = (v) => (typeof v === 'string' ? v.trim().replace(/-/g, '/') : v);
      const normalizeOrderTime = (v) => (typeof v === 'string' ? v.trim() : v);
      const normalizeOrderNumber = (v) => {
        if (v === null || v === undefined) return v;
        const s = String(v).trim();
        if (/^\d+$/.test(s)) return String(parseInt(s, 10));
        return s;
      };
      const normalizeMoney = (v) => {
        if (v === null || v === undefined) return v;
        const n = typeof v === 'number' ? v : parseFloat(String(v).trim());
        if (Number.isNaN(n)) return v;
        return Math.round(n * 100) / 100;
      };
      const normalizeParsedReceipt = (d) => ({
        ...d,
        orderNumber: normalizeOrderNumber(d.orderNumber),
        orderTotal: normalizeMoney(d.orderTotal),
        tipAmount: normalizeMoney(d.tipAmount),
        orderDate: normalizeOrderDate(d.orderDate),
        orderTime: normalizeOrderTime(d.orderTime),
      });
      const norm1 = normalizeParsedReceipt(data1);
      const norm2 = normalizeParsedReceipt(data2);

      const responsesMatch =
        norm1.orderNumber === norm2.orderNumber &&
        norm1.orderTotal === norm2.orderTotal &&
        norm1.tipAmount === norm2.tipAmount &&
        norm1.tipLineVisible === norm2.tipLineVisible &&
        norm1.orderDate === norm2.orderDate &&
        norm1.orderTime === norm2.orderTime;

      if (!responsesMatch) {
        return sendError(
          res,
          400,
          "DOUBLE_PARSE_MISMATCH",
          "Receipt data is unclear - the two validations returned different results. Please take a clearer photo of the receipt."
        );
      }

      const data = norm1;

      // Validate required fields
      if (!data.orderNumber || !data.orderTotal || !data.orderDate || !data.orderTime) {
        return sendError(res, 400, "MISSING_FIELDS", "Could not extract all required fields from receipt");
      }

      // Normalize date formatting to MM/DD (accept MM-DD from model/receipt)
      if (typeof data.orderDate === 'string') {
        data.orderDate = data.orderDate.trim().replace(/-/g, '/');
      }

      // Validate visibility and tampering flags for key fields
      const totalVisibleAndClear = data.totalVisibleAndClear;
      const orderNumberVisibleAndClear = data.orderNumberVisibleAndClear;
      const dateVisibleAndClear = data.dateVisibleAndClear;
      const timeVisibleAndClear = data.timeVisibleAndClear;
      const keyFieldsTampered = data.keyFieldsTampered;
      const tamperingReason = data.tamperingReason;
      const orderNumberInBlackBox = data.orderNumberInBlackBox;
      const orderNumberDirectlyUnderNashville = data.orderNumberDirectlyUnderNashville;
      const paidOnlineReceipt = data.paidOnlineReceipt;
      const orderNumberFromPaidOnlineSection = data.orderNumberFromPaidOnlineSection;

      const orderNumberSourceIsValid =
        orderNumberInBlackBox === true ||
        orderNumberDirectlyUnderNashville === true ||
        orderNumberFromPaidOnlineSection === true;

      if (
        totalVisibleAndClear === false ||
        orderNumberVisibleAndClear === false ||
        dateVisibleAndClear === false ||
        timeVisibleAndClear === false ||
        keyFieldsTampered === true ||
        !orderNumberSourceIsValid
      ) {
        if (!orderNumberSourceIsValid && keyFieldsTampered !== true) {
          if (paidOnlineReceipt === true) {
            return sendError(res, 400, "ORDER_NUMBER_SOURCE_INVALID", "No valid order number found next to 'Order:' for paid online receipt");
          }
          return sendError(res, 400, "ORDER_NUMBER_SOURCE_INVALID", "No valid order number found under Nashville");
        }
        const msg = tamperingReason && typeof tamperingReason === 'string' && tamperingReason.trim().length > 0
          ? `Receipt invalid - ${tamperingReason}`
          : "Receipt invalid - key information is obscured or appears tampered with";
        return sendError(res, 400, "KEY_FIELDS_INVALID", msg, { tamperingReason: tamperingReason || null });
      }

      // Validate order number format (must be 3 digits or less and not exceed 400)
      const orderNumberStr = data.orderNumber.toString();
      if (orderNumberStr.length > 3) {
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number format - must be 3 digits or less");
      }
      const orderNumber = parseInt(data.orderNumber);
      if (isNaN(orderNumber)) return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be a valid number");
      if (orderNumber < 1) return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be at least 1");
      if (orderNumber > 400) return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be 400 or less");

      // Validate date/time formats
      const dateRegex = /^\d{2}\/\d{2}$/;
      if (!dateRegex.test(data.orderDate)) {
        return sendError(res, 400, "DATE_FORMAT_INVALID", "Invalid date format - must be MM/DD (or MM-DD on receipt)");
      }
      const timeRegex = /^\d{2}:\d{2}$/;
      if (!timeRegex.test(data.orderTime)) {
        return sendError(res, 400, "TIME_FORMAT_INVALID", "Invalid time format - must be HH:MM");
      }
      const [hours, minutes] = data.orderTime.split(':').map(Number);
      if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
        return sendError(res, 400, "TIME_FORMAT_INVALID", "Invalid time - must be between 00:00 and 23:59");
      }

      // Validate order total
      const orderTotal = parseFloat(data.orderTotal);
      if (isNaN(orderTotal) || orderTotal < 1 || orderTotal > 500) {
        return sendError(res, 400, "TOTAL_INVALID", "Invalid order total - must be a reasonable amount between $1 and $500");
      }

      // 48-hour expiration logic (same as analyze endpoint, with admin override)
      const [month, day] = data.orderDate.split('/').map(Number);
      const currentDate = new Date();
      const [h, m] = data.orderTime.split(':').map(Number);

      const receiptDateThisYear = new Date(currentDate.getFullYear(), month - 1, day, h, m, 0, 0);
      const receiptDatePrevYear = new Date(currentDate.getFullYear() - 1, month - 1, day, h, m, 0, 0);
      const hoursDiffThisYear = (currentDate - receiptDateThisYear) / (1000 * 60 * 60);
      const hoursDiffPrevYear = (currentDate - receiptDatePrevYear) / (1000 * 60 * 60);

      let receiptDate = receiptDateThisYear;
      let hoursDiff = hoursDiffThisYear;
      if (hoursDiffThisYear < 0) {
        if (hoursDiffPrevYear >= 0 && hoursDiffPrevYear <= 48) {
          receiptDate = receiptDatePrevYear;
          hoursDiff = hoursDiffPrevYear;
          console.log('🗓️ Year-boundary adjustment applied (submit-receipt):', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiff);
        } else {
          return sendError(res, 400, "FUTURE_DATE", "Invalid receipt date - receipt appears to be dated in the future");
        }
      }

      const daysDiff = hoursDiff / 24;
      let allowOldReceiptForAdmin = false;
      try {
        const userDoc = await db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          const userData = userDoc.data() || {};
          if (userData.oldReceiptTestingEnabled === true) {
            allowOldReceiptForAdmin = true;
            console.log('⚠️ Old-receipt test mode active (submit-receipt):', uid, 'daysDiff:', daysDiff, 'isAdmin:', userData.isAdmin === true);
          }
        }
      } catch (err) {
        console.warn('⚠️ Failed to evaluate admin old-receipt test override (submit-receipt):', err.message || err);
      }
      if (hoursDiff > 48 && !allowOldReceiptForAdmin) {
        return sendError(res, 400, "EXPIRED_48H", "Receipt expired - receipts must be scanned within 48 hours of purchase");
      }

      // Award points atomically with server-side duplicate prevention
      const pointsAwarded = Math.floor(orderTotal * 5);
      const userRef = db.collection('users').doc(uid);
      const receiptsRef = db.collection('receipts');
      const pointsTxId = `receipt_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      let newPointsBalance = null;
      let newLifetimePoints = null;
      let savedReceiptId = null;

      try {
        await db.runTransaction(async (tx) => {
          // Duplicate detection (same logic as analyze endpoint)
          // Support legacy orderNumber type (string vs number) for duplicate detection
          const orderNumberStrForDup = String(data.orderNumber);
          const orderNumberNumForDup = parseInt(orderNumberStrForDup, 10);
          const orderNumberVariants = [orderNumberStrForDup];
          if (!isNaN(orderNumberNumForDup)) orderNumberVariants.push(orderNumberNumForDup);

          const duplicateQueries = [
            receiptsRef.where('orderDate', '==', data.orderDate).where('orderTime', '==', data.orderTime),
            receiptsRef.where('orderDate', '==', data.orderDate).where('orderTime', '==', data.orderTime).where('orderTotal', '==', orderTotal)
          ];
          for (const variant of orderNumberVariants) {
            duplicateQueries.push(
              receiptsRef.where('orderNumber', '==', variant).where('orderDate', '==', data.orderDate)
            );
            duplicateQueries.push(
              receiptsRef.where('orderNumber', '==', variant).where('orderTime', '==', data.orderTime)
            );
          }
          for (const q of duplicateQueries) {
            const snap = await tx.get(q);
            if (!snap.empty) {
              const err = new Error("DUPLICATE_RECEIPT");
              err.code = "DUPLICATE_RECEIPT";
              throw err;
            }
          }

          const userDoc = await tx.get(userRef);
          if (!userDoc.exists) {
            const err = new Error("USER_NOT_FOUND");
            err.code = "USER_NOT_FOUND";
            throw err;
          }
          const userData = userDoc.data() || {};
          const currentPoints = userData.points || 0;
          const currentLifetime = (typeof userData.lifetimePoints === 'number')
            ? userData.lifetimePoints
            : currentPoints;
          newPointsBalance = currentPoints + pointsAwarded;
          newLifetimePoints = currentLifetime + pointsAwarded;

          // Update user points
          tx.update(userRef, {
            points: newPointsBalance,
            lifetimePoints: newLifetimePoints
          });

          // Save receipt record (for future duplicate checks + auditing)
          const receiptDocRef = receiptsRef.doc();
          savedReceiptId = receiptDocRef.id;
          tx.set(receiptDocRef, {
            orderNumber: String(data.orderNumber),
            orderDate: data.orderDate,
            orderTime: data.orderTime,
            orderTotal: orderTotal,
            userId: uid,
            pointsAwarded,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
          });

          // Save points transaction
          tx.set(db.collection('pointsTransactions').doc(pointsTxId), {
            userId: uid,
            type: 'receipt_scan',
            amount: pointsAwarded,
            description: `Receipt Scan - $${orderTotal.toFixed(2)}`,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            metadata: {
              orderNumber: String(data.orderNumber),
              orderDate: data.orderDate,
              orderTime: data.orderTime,
              orderTotal: orderTotal
            }
          });
        });
      } catch (e) {
        if (e && e.code === "DUPLICATE_RECEIPT") {
          return sendError(
            res,
            409,
            "DUPLICATE_RECEIPT",
            "Receipt already submitted - this receipt has already been processed and points will not be awarded",
            { duplicate: true }
          );
        }
        if (e && e.code === "USER_NOT_FOUND") {
          return sendError(res, 404, "USER_NOT_FOUND", "User not found");
        }
        console.error('❌ submit-receipt transaction failed:', e);
        return sendError(res, 500, "SERVER_AWARD_FAILED", "Server error while awarding points - please try again");
      }

      return res.json({
        success: true,
        receipt: {
          orderNumber: String(data.orderNumber),
          orderTotal: orderTotal,
          orderDate: data.orderDate,
          orderTime: data.orderTime,
          receiptId: savedReceiptId
        },
        pointsAwarded,
        newPointsBalance,
        newLifetimePoints
      });
    } catch (err) {
      console.error('❌ Error processing submit-receipt:', err);
      return sendError(res, 500, "SERVER_ERROR", err.message || "Server error");
    }
  });

  // Welcome points claim (server-authoritative)
  // Prevents clients from directly incrementing their own points in Firestore.
  app.post('/welcome/claim', requireFirebaseAuth, async (req, res) => {
    try {
      const uid = req.auth.uid;

      const db = admin.firestore();
      const userRef = db.collection('users').doc(uid);
      const txId = `welcome_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const welcomePoints = 5;

      let newPointsBalance = null;
      let newLifetimePoints = null;
      let alreadyClaimed = false;

      await db.runTransaction(async (tx) => {
        const userDoc = await tx.get(userRef);
        if (!userDoc.exists) {
          const err = new Error("USER_NOT_FOUND");
          err.code = "USER_NOT_FOUND";
          throw err;
        }
        const userData = userDoc.data() || {};
        if (userData.hasReceivedWelcomePoints === true) {
          alreadyClaimed = true;
          return;
        }

        const currentPoints = userData.points || 0;
        const currentLifetime = (typeof userData.lifetimePoints === 'number') ? userData.lifetimePoints : currentPoints;
        newPointsBalance = currentPoints + welcomePoints;
        newLifetimePoints = currentLifetime + welcomePoints;

        tx.update(userRef, {
          points: newPointsBalance,
          lifetimePoints: newLifetimePoints,
          hasReceivedWelcomePoints: true,
          isNewUser: false
        });

        tx.set(db.collection('pointsTransactions').doc(txId), {
          userId: uid,
          type: 'welcome',
          amount: welcomePoints,
          description: 'Welcome bonus points for new account',
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });
      });

      if (alreadyClaimed) {
        return res.status(200).json({ success: true, alreadyClaimed: true });
      }

      return res.json({
        success: true,
        alreadyClaimed: false,
        pointsAwarded: welcomePoints,
        newPointsBalance,
        newLifetimePoints
      });
    } catch (err) {
      if (err && err.code === "USER_NOT_FOUND") return sendError(res, 404, "USER_NOT_FOUND", "User not found");
      console.error('❌ Error in /welcome/claim:', err);
      return sendError(res, 500, "SERVER_ERROR", "Failed to claim welcome points");
    }
  });

  // Chat endpoint for restaurant assistant
  app.post('/chat', requireFirebaseAuth, aiPerUserLimiter, aiPerIpLimiter, async (req, res) => {
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
- REWARD TIERS: 250 (Sauce), 450 (Tea/Lemonade/Coffee), 500 (Small Appetizer), 650 (Large Appetizer), 850 (Pizza Dumplings/Lunch Special 6pc), 1500 (12pc Dumplings), 2000 (Full Combo).
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
- REWARD TIERS: 250 (Sauce), 450 (Tea/Lemonade/Coffee), 500 (Small Appetizer), 650 (Large Appetizer), 850 (Pizza Dumplings/Lunch Special 6pc), 1500 (12pc Dumplings), 2000 (Full Combo).
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
  app.post('/generate-dumpling-hero-post', requireFirebaseAuth, aiPerUserLimiter, aiPerIpLimiter, async (req, res) => {
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
  app.post('/generate-dumpling-hero-comment', requireFirebaseAuth, aiPerUserLimiter, aiPerIpLimiter, async (req, res) => {
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
  app.post('/preview-dumpling-hero-comment', requireFirebaseAuth, async (req, res) => {
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
  app.post('/generate-dumpling-hero-comment-simple', requireFirebaseAuth, aiPerUserLimiter, aiPerIpLimiter, async (req, res) => {
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

  // ---------------------------------------------------------------------------
  // Reward Tier Items - Fetch eligible items for a reward tier
  // ---------------------------------------------------------------------------
  
  app.get('/reward-tier-items/:pointsRequired', async (req, res) => {
    try {
      const pointsRequired = parseInt(req.params.pointsRequired, 10);
      
      if (isNaN(pointsRequired) || pointsRequired <= 0) {
        return res.status(400).json({ error: 'Invalid pointsRequired parameter' });
      }
      
      console.log(`🎁 Fetching eligible items for ${pointsRequired} point tier`);
      
      const db = admin.firestore();
      
      // Query rewardTierItems collection for this points tier
      const snapshot = await db.collection('rewardTierItems')
        .where('pointsRequired', '==', pointsRequired)
        .limit(1)
        .get();
      
      if (snapshot.empty) {
        console.log(`📭 No configured items for ${pointsRequired} point tier`);
        return res.json({
          pointsRequired,
          tierName: null,
          eligibleItems: []
        });
      }
      
      const tierDoc = snapshot.docs[0];
      const tierData = tierDoc.data();
      
      console.log(`✅ Found ${(tierData.eligibleItems || []).length} eligible items for tier`);
      
      res.json({
        pointsRequired: tierData.pointsRequired,
        tierName: tierData.tierName || null,
        eligibleItems: tierData.eligibleItems || []
      });
      
    } catch (error) {
      console.error('❌ Error fetching reward tier items:', error);
      res.status(500).json({ 
        error: 'Failed to fetch reward tier items',
        details: error.message 
      });
    }
  });

  // Fetch eligible items for a reward tier by tier ID
  app.get('/reward-tier-items/by-id/:tierId', async (req, res) => {
    try {
      const { tierId } = req.params;
      if (!tierId) {
        return res.status(400).json({ error: 'tierId is required' });
      }
      
      console.log(`🎁 Fetching eligible items for tier ${tierId}`);
      
      const db = admin.firestore();
      const tierDoc = await db.collection('rewardTierItems').doc(tierId).get();
      
      if (!tierDoc.exists) {
        console.log(`📭 No configured items for tier ${tierId}`);
        return res.json({
          tierId,
          pointsRequired: null,
          tierName: null,
          eligibleItems: []
        });
      }
      
      const tierData = tierDoc.data();
      console.log(`✅ Found ${(tierData.eligibleItems || []).length} eligible items for tier`);
      
      res.json({
        tierId,
        pointsRequired: tierData.pointsRequired || null,
        tierName: tierData.tierName || null,
        eligibleItems: tierData.eligibleItems || []
      });
      
    } catch (error) {
      console.error('❌ Error fetching reward tier items by ID:', error);
      res.status(500).json({ 
        error: 'Failed to fetch reward tier items',
        details: error.message 
      });
    }
  });

  // Redeem reward endpoint
  app.post('/redeem-reward', requireFirebaseAuth, async (req, res) => {
    let pointsRequiredNumber = null;
    try {
      console.log('🎁 Received reward redemption request');
      console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
      
      const { 
        userId: requestedUserId, 
        rewardTitle, 
        rewardDescription, 
        pointsRequired, 
        rewardCategory,
        idempotencyKey,
        selectedItemId,      // Optional selected item ID
        selectedItemName,    // Optional selected item name
        selectedToppingId,   // NEW: Optional topping ID (for drink rewards)
        selectedToppingName, // NEW: Optional topping name (for drink rewards)
        selectedItemId2,     // NEW: Optional second item ID (for half-and-half)
        selectedItemName2,   // NEW: Optional second item name (for half-and-half)
        cookingMethod,       // NEW: Optional cooking method (for dumpling rewards)
        drinkType,           // NEW: Optional drink type (Lemonade or Soda)
        selectedDrinkItemId, // NEW: Optional drink item ID (for Full Combo)
        selectedDrinkItemName, // NEW: Optional drink item name (for Full Combo)
        iceLevel,            // Optional ice level (Normal, 75%, 50%, 25%, No Ice)
        sugarLevel           // Optional sugar level (Normal, 75%, 50%, 25%, No Sugar)
      } = req.body;
      
      const userId = req.auth.uid;
      if (requestedUserId && requestedUserId !== userId) {
        return res.status(403).json({ error: 'User mismatch for reward redemption' });
      }
      
      pointsRequiredNumber = Number(pointsRequired);
      if (!rewardTitle || !pointsRequiredNumber) {
        console.log('❌ Missing required fields for reward redemption');
        return res.status(400).json({ 
          error: 'Missing required fields: rewardTitle, pointsRequired',
          received: { rewardTitle: !!rewardTitle, pointsRequired: !!pointsRequiredNumber }
        });
      }
      
      if (!Number.isInteger(pointsRequiredNumber) || pointsRequiredNumber <= 0) {
        return res.status(400).json({ error: 'Invalid pointsRequired value' });
      }
      
      const db = admin.firestore();
      
      const redemptionResult = await db.runTransaction(async (transaction) => {
        const userRef = db.collection('users').doc(userId);
        const redeemedRewardsRef = db.collection('redeemedRewards');
        const pointsTransactionsRef = db.collection('pointsTransactions');
        
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
          const error = new Error('USER_NOT_FOUND');
          error.code = 'USER_NOT_FOUND';
          throw error;
        }
        
        const userData = userDoc.data() || {};
        const currentPoints = userData.points || 0;
        
        if (idempotencyKey) {
          const existingQuery = redeemedRewardsRef
            .where('userId', '==', userId)
            .where('idempotencyKey', '==', idempotencyKey)
            .limit(1);
          const existingSnapshot = await transaction.get(existingQuery);
          if (!existingSnapshot.empty) {
            return {
              existingReward: existingSnapshot.docs[0].data(),
              currentPoints
            };
          }
        }
        
        console.log(`👤 User ${userId} has ${currentPoints} points, needs ${pointsRequiredNumber} for reward`);
        
        if (currentPoints < pointsRequiredNumber) {
          const error = new Error('INSUFFICIENT_POINTS');
          error.code = 'INSUFFICIENT_POINTS';
          error.currentPoints = currentPoints;
          throw error;
        }
        
        const redemptionCode = Math.floor(10000000 + Math.random() * 90000000).toString();
        console.log(`🔢 Generated redemption code: ${redemptionCode}`);
        
        const newPointsBalance = currentPoints - pointsRequiredNumber;
        
        const redeemedRewardRef = redeemedRewardsRef.doc();
        const redeemedReward = {
          id: redeemedRewardRef.id,
          userId: userId,
          rewardTitle: rewardTitle,
          rewardDescription: rewardDescription || '',
          rewardCategory: rewardCategory || 'General',
          pointsRequired: pointsRequiredNumber,
          redemptionCode: redemptionCode,
          redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: new Date(Date.now() + 15 * 60 * 1000),
          isExpired: false,
          isUsed: false,
          pointsBalanceAfter: newPointsBalance,
          ...(idempotencyKey && { idempotencyKey }),
          ...(selectedItemId && { selectedItemId }),
          ...(selectedItemName && { selectedItemName }),
          ...(selectedToppingId && { selectedToppingId }),
          ...(selectedToppingName && { selectedToppingName }),
          ...(selectedItemId2 && { selectedItemId2 }),
          ...(selectedItemName2 && { selectedItemName2 }),
          ...(cookingMethod && { cookingMethod }),
          ...(drinkType && { drinkType }),
          ...(selectedDrinkItemId && { selectedDrinkItemId }),
          ...(selectedDrinkItemName && { selectedDrinkItemName }),
          ...(iceLevel && { iceLevel }),
          ...(sugarLevel && { sugarLevel })
        };
        
        let transactionDescription = `Redeemed: ${rewardTitle}`;
        if (selectedItemName) {
          transactionDescription = `Redeemed: ${selectedItemName}`;
          if (selectedToppingName) {
            transactionDescription += ` with ${selectedToppingName}`;
          }
          if (selectedItemName2) {
            transactionDescription = `Redeemed: Half and Half: ${selectedItemName} + ${selectedItemName2}`;
            if (cookingMethod) {
              transactionDescription += ` (${cookingMethod})`;
            }
          }
        }
        
        const transactionRef = pointsTransactionsRef.doc();
        const pointsTransaction = {
          id: transactionRef.id,
          userId: userId,
          type: 'reward_redemption',
          amount: -pointsRequiredNumber,
          description: transactionDescription,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isEarned: false,
          redemptionCode: redemptionCode,
          rewardTitle: rewardTitle,
          redeemedRewardId: redeemedRewardRef.id,
          ...(idempotencyKey && { idempotencyKey }),
          ...(selectedItemName && { selectedItemName }),
          ...(selectedToppingName && { selectedToppingName }),
          ...(selectedItemName2 && { selectedItemName2 }),
          ...(cookingMethod && { cookingMethod })
        };
        
        transaction.update(userRef, { points: newPointsBalance });
        transaction.set(redeemedRewardRef, redeemedReward);
        transaction.set(transactionRef, pointsTransaction);
        
        return {
          redemptionCode,
          newPointsBalance,
          pointsDeducted: pointsRequiredNumber,
          rewardTitle,
          selectedItemName: selectedItemName || null,
          selectedToppingName: selectedToppingName || null,
          selectedItemName2: selectedItemName2 || null,
          cookingMethod: cookingMethod || null,
          drinkType: drinkType || null,
          selectedDrinkItemId: selectedDrinkItemId || null,
          selectedDrinkItemName: selectedDrinkItemName || null,
          iceLevel: iceLevel || null,
          sugarLevel: sugarLevel || null,
          expiresAt: redeemedReward.expiresAt
        };
      });
      
      const existingExpiresAt = redemptionResult.existingReward?.expiresAt?.toDate
        ? redemptionResult.existingReward.expiresAt.toDate()
        : redemptionResult.existingReward?.expiresAt;
      
      const responseData = redemptionResult.existingReward
        ? {
            success: true,
            redemptionCode: redemptionResult.existingReward.redemptionCode,
            newPointsBalance: redemptionResult.currentPoints,
            pointsDeducted: redemptionResult.existingReward.pointsRequired,
            rewardTitle: redemptionResult.existingReward.rewardTitle,
            selectedItemName: redemptionResult.existingReward.selectedItemName || null,
            selectedToppingName: redemptionResult.existingReward.selectedToppingName || null,
            selectedItemName2: redemptionResult.existingReward.selectedItemName2 || null,
            cookingMethod: redemptionResult.existingReward.cookingMethod || null,
            drinkType: redemptionResult.existingReward.drinkType || null,
            selectedDrinkItemId: redemptionResult.existingReward.selectedDrinkItemId || null,
            selectedDrinkItemName: redemptionResult.existingReward.selectedDrinkItemName || null,
            iceLevel: redemptionResult.existingReward.iceLevel || null,
            sugarLevel: redemptionResult.existingReward.sugarLevel || null,
            expiresAt: existingExpiresAt,
            message: 'Reward redeemed successfully! Show the code to your cashier.'
          }
        : {
            success: true,
            redemptionCode: redemptionResult.redemptionCode,
            newPointsBalance: redemptionResult.newPointsBalance,
            pointsDeducted: redemptionResult.pointsDeducted,
            rewardTitle: redemptionResult.rewardTitle,
            selectedItemName: redemptionResult.selectedItemName,
            selectedToppingName: redemptionResult.selectedToppingName,
            selectedItemName2: redemptionResult.selectedItemName2,
            cookingMethod: redemptionResult.cookingMethod,
            drinkType: redemptionResult.drinkType,
            selectedDrinkItemId: redemptionResult.selectedDrinkItemId,
            selectedDrinkItemName: redemptionResult.selectedDrinkItemName,
            iceLevel: redemptionResult.iceLevel,
            sugarLevel: redemptionResult.sugarLevel,
            expiresAt: redemptionResult.expiresAt,
            message: 'Reward redeemed successfully! Show the code to your cashier.'
          };
      
      console.log(`✅ Reward redeemed successfully!`);
      console.log(`🔢 Redemption code: ${responseData.redemptionCode}`);
      console.log(`💰 Points deducted: ${responseData.pointsDeducted}`);
      console.log(`💳 New balance: ${responseData.newPointsBalance}`);
      
      res.json(responseData);
      
    } catch (error) {
      console.error('❌ Error redeeming reward:', error);
      if (error.code === 'INSUFFICIENT_POINTS') {
        return res.status(400).json({
          error: 'Insufficient points for redemption',
          currentPoints: error.currentPoints,
          pointsRequired: pointsRequiredNumber,
          pointsNeeded: pointsRequiredNumber - error.currentPoints
        });
      }
      
      if (error.code === 'USER_NOT_FOUND') {
        return res.status(404).json({ error: 'User not found' });
      }
      
      res.status(500).json({
        error: 'Failed to redeem reward',
        details: error.message
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Admin-only Receipts Management Endpoints
  // ---------------------------------------------------------------------------

  // Helper to verify Firebase Auth token and ensure the caller is an admin user
  async function requireAdmin(req, res) {
    try {
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
      if (!token) {
        res.status(401).json({ error: 'Missing or invalid Authorization header' });
        return null;
      }

      const decoded = await admin.auth().verifyIdToken(token);
      const uid = decoded.uid;

      const db = admin.firestore();
      const userDoc = await db.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        res.status(403).json({ error: 'User record not found for admin check' });
        return null;
      }

      const userData = userDoc.data() || {};
      if (userData.isAdmin !== true) {
        res.status(403).json({ error: 'Admin privileges required' });
        return null;
      }

      return { uid, userData };
    } catch (err) {
      console.error('❌ Admin auth check failed:', err);
      res.status(401).json({ error: 'Failed to verify admin credentials' });
      return null;
    }
  }

  // Helper to verify Firebase Auth token and ensure the caller is an admin OR employee user
  async function requireStaff(req, res) {
    try {
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
      if (!token) {
        res.status(401).json({ error: 'Missing or invalid Authorization header' });
        return null;
      }

      const decoded = await admin.auth().verifyIdToken(token);
      const uid = decoded.uid;

      const db = admin.firestore();
      const userDoc = await db.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        res.status(403).json({ error: 'User record not found for staff check' });
        return null;
      }

      const userData = userDoc.data() || {};
      if (userData.isAdmin !== true && userData.isEmployee !== true) {
        res.status(403).json({ error: 'Staff privileges required' });
        return null;
      }

      return { uid, userData };
    } catch (err) {
      console.error('❌ Staff auth check failed:', err);
      res.status(401).json({ error: 'Failed to verify staff credentials' });
      return null;
    }
  }

  // Helper to verify Firebase Auth token for any signed-in user
  async function requireUser(req, res) {
    try {
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
      if (!token) {
        res.status(401).json({ error: 'Missing or invalid Authorization header' });
        return null;
      }

      const decoded = await admin.auth().verifyIdToken(token);
      return { uid: decoded.uid, decoded };
    } catch (err) {
      console.error('❌ User auth check failed:', err);
      res.status(401).json({ error: 'Failed to verify credentials' });
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Authenticated User Endpoints
  // ---------------------------------------------------------------------------
  /**
   * POST /me/fcmToken
   *
   * Authenticated user endpoint. Stores (or clears) the caller's FCM token
   * server-side using Admin SDK (bypasses client Firestore issues).
   *
   * Body:
   * - { fcmToken: string } to set token
   * - { fcmToken: null } to clear token
   */
  app.post('/me/fcmToken', requireFirebaseAuth, async (req, res) => {
    try {
      const uid = req.auth.uid;

      const { fcmToken } = req.body || {};
      const db = admin.firestore();
      const userRef = db.collection('users').doc(uid);

      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        return res.status(404).json({ error: 'User record not found' });
      }

      if (fcmToken === null) {
        await userRef.set({
          hasFcmToken: false,
          fcmToken: admin.firestore.FieldValue.delete(),
          fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        return res.json({ ok: true, hasFcmToken: false });
      }

      if (typeof fcmToken !== 'string' || fcmToken.trim().length === 0) {
        return res.status(400).json({ error: 'fcmToken must be a non-empty string or null' });
      }

      const trimmedToken = fcmToken.trim();
      await userRef.set({
        hasFcmToken: true,
        fcmToken: trimmedToken,
        fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

      return res.json({ ok: true, hasFcmToken: true });
    } catch (error) {
      console.error('❌ Error in /me/fcmToken:', error);
      return res.status(500).json({ error: 'Failed to store FCM token' });
    }
  });

  // ---------------------------------------------------------------------------
  // Admin-only Users Listing (server-side paging + search)
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Admin-only Debug Endpoints (Firebase wiring + push targeting visibility)
  // ---------------------------------------------------------------------------
  /**
   * GET /admin/debug/firebase
   *
   * Admin-only. Returns non-secret information about which Firebase project
   * this server instance is connected to.
   */
  app.get('/admin/debug/firebase', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const appInstance = admin.app();
      const options = appInstance?.options || {};

      // Best-effort project id derivation without exposing secrets.
      let derivedProjectId = options.projectId || process.env.GOOGLE_CLOUD_PROJECT || null;
      if (!derivedProjectId && process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
        try {
          const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
          if (sa && typeof sa.project_id === 'string') derivedProjectId = sa.project_id;
        } catch (_) {
          // ignore parse errors
        }
      }

      return res.json({
        ok: true,
        firebase: {
          appName: appInstance?.name || null,
          optionsProjectId: options.projectId || null,
          derivedProjectId
        },
        env: {
          FIREBASE_AUTH_TYPE: process.env.FIREBASE_AUTH_TYPE || null,
          GOOGLE_CLOUD_PROJECT: process.env.GOOGLE_CLOUD_PROJECT || null,
          NODE_ENV: process.env.NODE_ENV || null
        }
      });
    } catch (error) {
      console.error('❌ Error in /admin/debug/firebase:', error);
      return res.status(500).json({ error: 'Failed to fetch Firebase debug info' });
    }
  });

  /**
   * GET /admin/debug/pushTargets
   *
   * Admin-only. Summarizes how many users are marked as having FCM tokens,
   * and samples a few documents to confirm fields exist (never returns tokens).
   */
  app.get('/admin/debug/pushTargets', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();
      const pageSize = 500;
      const sampleSize = Math.min(parseInt(req.query.sampleSize, 10) || 10, 25);

      let lastDoc = null;
      let hasFcmTokenTrueCount = 0;
      let excludedAdminCount = 0;
      let missingFcmTokenCount = 0;
      const samples = [];

      while (true) {
        let query = db.collection('users')
          .where('hasFcmToken', '==', true)
          .limit(pageSize);

        if (lastDoc) query = query.startAfter(lastDoc);

        const page = await query.get();
        if (!page || page.empty) break;

        for (const doc of page.docs) {
          hasFcmTokenTrueCount += 1;
          const data = doc.data() || {};

          if (data.isAdmin === true) excludedAdminCount += 1;

          const fcmToken = data.fcmToken;
          const isValidToken = (typeof fcmToken === 'string' && fcmToken.length > 0);
          if (!isValidToken) missingFcmTokenCount += 1;

          if (samples.length < sampleSize) {
            samples.push({
              id: doc.id,
              isAdmin: data.isAdmin === true,
              hasFcmToken: data.hasFcmToken === true,
              fcmTokenLength: isValidToken ? fcmToken.length : 0,
              hasFcmTokenUpdatedAt: !!data.fcmTokenUpdatedAt
            });
          }
        }

        lastDoc = page.docs[page.docs.length - 1];
        if (page.docs.length < pageSize) break;
      }

      return res.json({
        ok: true,
        counts: {
          hasFcmTokenTrueCount,
          excludedAdminCount,
          missingFcmTokenCount
        },
        samples
      });
    } catch (error) {
      console.error('❌ Error in /admin/debug/pushTargets:', error);
      return res.status(500).json({ error: 'Failed to fetch push target debug info' });
    }
  });

  /**
   * GET /admin/users
   *
   * Query params:
   * - limit: number (default 50, max 200)
   * - cursor: string (doc id to start after)
   * - q: string (search query across firstName/email/phone; server-side scan)
   *
   * NOTE: Do NOT return fcmToken to clients.
   */
  app.get('/admin/users', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();
      const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
      const cursor = (req.query.cursor || '').toString().trim();
      const q = (req.query.q || '').toString().trim().toLowerCase();

      const mapUser = (doc) => {
        const data = doc.data() || {};
        // Check both accountCreatedDate and createdAt for backward compatibility
        const created = data.accountCreatedDate || data.createdAt;
        const createdDate = created && typeof created.toDate === 'function' ? created.toDate() : null;

        return {
          id: doc.id,
          firstName: data.firstName || 'Unknown',
          email: data.email || 'No email',
          phone: data.phone || '',
          points: typeof data.points === 'number' ? data.points : 0,
          lifetimePoints: typeof data.lifetimePoints === 'number' ? data.lifetimePoints : 0,
          avatarEmoji: data.avatarEmoji || '👤',
          avatarColor: data.avatarColor || data.avatarColorName || 'gray',
          profilePhotoURL: data.profilePhotoURL || null,
          isVerified: data.isVerified === true,
          isAdmin: data.isAdmin === true,
          isEmployee: data.isEmployee === true,
          accountCreatedDate: createdDate ? createdDate.toISOString() : null,
          hasFcmToken: data.hasFcmToken === true
        };
      };

      // Fast path: no search query -> simple pagination
      if (!q) {
        let query = db.collection('users')
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(limit);

        if (cursor) {
          query = query.startAfter(cursor);
        }

        const snap = await query.get();
        const docs = snap.docs || [];
        const users = docs.map(mapUser);
        const nextCursor = docs.length > 0 ? docs[docs.length - 1].id : null;

        return res.json({
          users,
          nextCursor,
          hasMore: docs.length === limit
        });
      }

      // Search path: scan in pages, filter server-side, return matches (up to limit)
      const scanPageSize = 500;
      const matches = [];
      let scanCursor = cursor || null;
      let reachedEnd = false;
      let lastScannedId = null;

      while (matches.length < limit && !reachedEnd) {
        let query = db.collection('users')
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(scanPageSize);

        if (scanCursor) {
          query = query.startAfter(scanCursor);
        }

        const page = await query.get();
        if (!page || page.empty) {
          reachedEnd = true;
          break;
        }

        for (const doc of page.docs) {
          lastScannedId = doc.id;
          const data = doc.data() || {};

          const firstName = (data.firstName || '').toString().toLowerCase();
          const email = (data.email || '').toString().toLowerCase();
          const phone = (data.phone || '').toString().toLowerCase();

          if (firstName.includes(q) || email.includes(q) || phone.includes(q)) {
            matches.push(mapUser(doc));
            if (matches.length >= limit) break;
          }
        }

        // Prepare for next scan page
        scanCursor = lastScannedId;
        if (page.docs.length < scanPageSize) {
          reachedEnd = true;
        }
      }

      return res.json({
        users: matches,
        nextCursor: lastScannedId,
        hasMore: !reachedEnd
      });
    } catch (error) {
      console.error('❌ Error listing admin users:', error);
      res.status(500).json({ error: 'Failed to list users' });
    }
  });

  /**
   * POST /admin/users/update
   *
   * Updates a user's account fields and logs an admin audit action.
   * Body:
   * - userId: string (required)
   * - points: number (required, non-negative integer)
   * - phone: string (optional)
   * - isAdmin: bool (optional)
   * - isVerified: bool (optional)
   */
  app.post('/admin/users/update', async (req, res) => {
    try {
      console.log('📥 Received admin user update request');
      console.log('📦 Request body:', JSON.stringify(req.body, null, 2));
      
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) {
        console.log('❌ Admin authentication failed');
        return; // requireAdmin already sent the response
      }

      console.log('✅ Admin authenticated:', adminContext.uid);

      const {
        userId,
        points,
        phone,
        isAdmin: isAdminFlag,
        isVerified: isVerifiedFlag
      } = req.body || {};

      if (!userId || typeof userId !== 'string') {
        console.log('❌ Missing or invalid userId');
        return res.status(400).json({ 
          errorCode: 'INVALID_REQUEST',
          error: 'userId is required and must be a string' 
        });
      }

      const pointsInt = Number(points);
      if (!Number.isInteger(pointsInt) || pointsInt < 0) {
        console.log('❌ Invalid points value:', points);
        return res.status(400).json({ 
          errorCode: 'INVALID_REQUEST',
          error: 'points must be a non-negative integer' 
        });
      }

      console.log(`🔄 Updating user ${userId}: points=${pointsInt}, isAdmin=${isAdminFlag}, isVerified=${isVerifiedFlag}`);

      const db = admin.firestore();
      const result = await db.runTransaction(async (transaction) => {
        const userRef = db.collection('users').doc(userId);
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
          const error = new Error('USER_NOT_FOUND');
          error.code = 'USER_NOT_FOUND';
          throw error;
        }

        const userData = userDoc.data() || {};
        const currentPoints = typeof userData.points === 'number' ? userData.points : 0;
        const currentLifetime = typeof userData.lifetimePoints === 'number'
          ? userData.lifetimePoints
          : currentPoints;
        const delta = pointsInt - currentPoints;
        const newLifetimePoints = delta > 0 ? currentLifetime + delta : currentLifetime;

        // Handle boolean flags - explicitly set to false if undefined/null
        const updateData = {
          points: pointsInt,
          lifetimePoints: newLifetimePoints,
          isAdmin: isAdminFlag === true,
          isVerified: isVerifiedFlag === true,
          phone: typeof phone === 'string' ? phone : (userData.phone || '')
        };

        console.log('📝 Update data:', JSON.stringify(updateData, null, 2));

        transaction.update(userRef, updateData);

        if (delta !== 0) {
          const transactionRef = db.collection('pointsTransactions').doc();
          transaction.set(transactionRef, {
            id: transactionRef.id,
            userId,
            type: 'admin_adjustment',
            amount: delta,
            description: 'Points adjusted by admin',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            isEarned: delta > 0,
            performedBy: adminContext.uid,
            metadata: {
              previousPoints: currentPoints,
              newPoints: pointsInt
            }
          });
        }

        const actionRef = db.collection('adminActions').doc();
        transaction.set(actionRef, {
          action: 'admin_user_update',
          targetUserId: userId,
          performedBy: adminContext.uid,
          changes: {
            points: pointsInt,
            phone: typeof phone === 'string' ? phone : (userData.phone || ''),
            isAdmin: isAdminFlag === true,
            isVerified: isVerifiedFlag === true
          },
          previousPoints: currentPoints,
          delta,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        return {
          userId,
          points: pointsInt,
          lifetimePoints: newLifetimePoints,
          phone: updateData.phone,
          isAdmin: updateData.isAdmin,
          isVerified: updateData.isVerified,
          previousPoints: currentPoints,
          delta
        };
      });

      console.log('✅ User update successful:', JSON.stringify(result, null, 2));
      return res.json({ success: true, ...result });
    } catch (error) {
      console.error('❌ Error updating admin user:', error);
      console.error('❌ Error stack:', error.stack);
      
      if (error.code === 'USER_NOT_FOUND') {
        return res.status(404).json({ 
          errorCode: 'USER_NOT_FOUND',
          error: `User with ID '${req.body?.userId || 'unknown'}' not found` 
        });
      }
      
      // Check for Firestore permission errors
      if (error.code === 7 || error.message?.includes('permission') || error.message?.includes('PERMISSION_DENIED')) {
        return res.status(403).json({ 
          errorCode: 'PERMISSION_DENIED',
          error: 'Firestore permission denied. Check that the service account has proper permissions.' 
        });
      }
      
      return res.status(500).json({ 
        errorCode: 'INTERNAL_ERROR',
        error: `Failed to update user: ${error.message || 'Unknown error'}`,
        details: process.env.NODE_ENV === 'development' ? error.stack : undefined
      });
    }
  });

  /**
   * POST /admin/users/cleanup-orphans
   *
   * Finds and deletes orphaned Firestore user documents (documents without
   * corresponding Firebase Auth accounts). This helps clean up duplicates
   * that occur when accounts are deleted and recreated.
   *
   * Returns:
   * - deletedCount: number of orphaned documents deleted
   * - checkedCount: total number of documents checked
   */
  app.post('/admin/users/cleanup-orphans', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();
      const auth = admin.auth();
      
      console.log('🧹 Starting orphaned accounts cleanup...');
      
      let checkedCount = 0;
      let deletedCount = 0;
      let lastDoc = null;
      const pageSize = 500;
      const orphanedUIDs = [];
      
      // Scan through all user documents in batches
      while (true) {
        let query = db.collection('users')
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(pageSize);
        
        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }
        
        const snapshot = await query.get();
        if (snapshot.empty) {
          break;
        }
        
        // Check each document for orphaned status
        for (const doc of snapshot.docs) {
          checkedCount++;
          const uid = doc.id;
          
          try {
            // Check if Firebase Auth account exists for this UID
            await auth.getUser(uid);
            // If getUser succeeds, the account exists - not orphaned
          } catch (error) {
            // If getUser fails with user-not-found, it's an orphaned document
            if (error.code === 'auth/user-not-found') {
              orphanedUIDs.push(uid);
              console.log(`🔍 Found orphaned account: ${uid}`);
            } else {
              // Other errors (permissions, etc.) - log but don't treat as orphaned
              console.warn(`⚠️ Error checking user ${uid}: ${error.code}`);
            }
          }
        }
        
        lastDoc = snapshot.docs[snapshot.docs.length - 1];
        
        // If we got fewer docs than pageSize, we've reached the end
        if (snapshot.docs.length < pageSize) {
          break;
        }
      }
      
      // Delete orphaned documents in batches (Firestore batch limit is 500)
      const batchSize = 450; // Leave some headroom
      for (let i = 0; i < orphanedUIDs.length; i += batchSize) {
        const batch = db.batch();
        const batchUIDs = orphanedUIDs.slice(i, i + batchSize);
        
        for (const uid of batchUIDs) {
          batch.delete(db.collection('users').doc(uid));
        }
        
        try {
          await batch.commit();
          deletedCount += batchUIDs.length;
          console.log(`✅ Deleted batch of ${batchUIDs.length} orphaned accounts`);
        } catch (error) {
          console.error(`❌ Error deleting batch: ${error.message}`);
        }
      }
      
      console.log(`✅ Cleanup complete: Deleted ${deletedCount} orphaned accounts out of ${checkedCount} checked`);
      
      return res.json({
        deletedCount,
        checkedCount,
        message: `Cleaned up ${deletedCount} orphaned account(s) out of ${checkedCount} checked`
      });
    } catch (error) {
      console.error('❌ Error in /admin/users/cleanup-orphans:', error);
      res.status(500).json({ error: 'Failed to cleanup orphaned accounts' });
    }
  });

  // ---------------------------------------------------------------------------
  // Admin-only Rewards Validation / Consumption (QR scanning)
  // ---------------------------------------------------------------------------

  function parseFirestoreDate(value) {
    if (!value) return null;
    if (value instanceof Date) return value;
    if (typeof value.toDate === 'function') return value.toDate(); // Firestore Timestamp
    return null;
  }

  function pickBestRedeemedRewardDoc(snapshot) {
    if (!snapshot || snapshot.empty) return null;
    // Prefer the newest redeemedAt when possible; otherwise just take the first.
    let bestDoc = snapshot.docs[0];
    let bestRedeemedAt = parseFirestoreDate(bestDoc.get('redeemedAt')) || new Date(0);
    for (const doc of snapshot.docs) {
      const redeemedAt = parseFirestoreDate(doc.get('redeemedAt')) || new Date(0);
      if (redeemedAt > bestRedeemedAt) {
        bestRedeemedAt = redeemedAt;
        bestDoc = doc;
      }
    }
    return bestDoc;
  }

  function rewardStatusFromData(data) {
    const expiresAt = parseFirestoreDate(data.expiresAt);
    const isExpired = data.isExpired === true || (expiresAt ? expiresAt <= new Date() : false);
    const isUsed = data.isUsed === true;

    if (isUsed) return 'already_used';
    if (isExpired) return 'expired';
    return 'ok';
  }

  // Validate a reward code (no mutation; used to show confirmation UI)
  app.post('/admin/rewards/validate', async (req, res) => {
    try {
      const staffContext = await requireStaff(req, res);
      if (!staffContext) return;

      const redemptionCode = (req.body?.redemptionCode || '').toString().trim();
      if (!/^\d{8}$/.test(redemptionCode)) {
        return res.status(400).json({ error: 'Invalid redemptionCode. Expected 8 digits.' });
      }

      const db = admin.firestore();
      const snapshot = await db
        .collection('redeemedRewards')
        .where('redemptionCode', '==', redemptionCode)
        .limit(10)
        .get();

      const bestDoc = pickBestRedeemedRewardDoc(snapshot);
      if (!bestDoc) {
        return res.json({ status: 'not_found' });
      }

      const data = bestDoc.data() || {};
      const expiresAt = parseFirestoreDate(data.expiresAt);
      const redeemedAt = parseFirestoreDate(data.redeemedAt);

      return res.json({
        status: rewardStatusFromData(data),
        reward: {
          id: bestDoc.id,
          userId: data.userId || null,
          rewardTitle: data.rewardTitle || null,
          rewardDescription: data.rewardDescription || null,
          rewardCategory: data.rewardCategory || null,
          pointsRequired: typeof data.pointsRequired === 'number' ? data.pointsRequired : null,
          redemptionCode: data.redemptionCode || null,
          redeemedAt: redeemedAt ? redeemedAt.toISOString() : null,
          expiresAt: expiresAt ? expiresAt.toISOString() : null,
          isUsed: data.isUsed === true,
          isExpired: data.isExpired === true || (expiresAt ? expiresAt <= new Date() : false),
          selectedItemId: data.selectedItemId || null,
          selectedItemName: data.selectedItemName || null,
          selectedToppingId: data.selectedToppingId || null,    // NEW: For drink rewards
          selectedToppingName: data.selectedToppingName || null, // NEW: For drink rewards
          selectedItemId2: data.selectedItemId2 || null,        // NEW: For half-and-half
          selectedItemName2: data.selectedItemName2 || null,    // NEW: For half-and-half
          cookingMethod: data.cookingMethod || null,            // NEW: For dumpling rewards
          drinkType: data.drinkType || null,                     // NEW: For Lemonade/Soda rewards
          selectedDrinkItemId: data.selectedDrinkItemId || null, // NEW: For Full Combo
          selectedDrinkItemName: data.selectedDrinkItemName || null // NEW: For Full Combo
        }
      });
    } catch (error) {
      console.error('❌ Error validating reward code:', error);
      return res.status(500).json({ error: 'Failed to validate reward code' });
    }
  });

  // Consume a reward code (atomic: re-check + mark used)
  app.post('/admin/rewards/consume', async (req, res) => {
    try {
      const staffContext = await requireStaff(req, res);
      if (!staffContext) return;

      const redemptionCode = (req.body?.redemptionCode || '').toString().trim();
      if (!/^\d{8}$/.test(redemptionCode)) {
        return res.status(400).json({ error: 'Invalid redemptionCode. Expected 8 digits.' });
      }

      const db = admin.firestore();
      // Find candidate doc (outside transaction); transaction will re-check before mutation.
      const snapshot = await db
        .collection('redeemedRewards')
        .where('redemptionCode', '==', redemptionCode)
        .limit(10)
        .get();

      const bestDoc = pickBestRedeemedRewardDoc(snapshot);
      if (!bestDoc) {
        return res.json({ status: 'not_found' });
      }

      const rewardRef = bestDoc.ref;
      const staffUid = staffContext.uid;
      const staffEmail = staffContext.userData?.email || null;
      const staffRole = staffContext.userData?.isAdmin === true ? 'admin' : 'employee';

      const result = await db.runTransaction(async (tx) => {
        const doc = await tx.get(rewardRef);
        if (!doc.exists) {
          return { status: 'not_found' };
        }

        const data = doc.data() || {};
        const expiresAt = parseFirestoreDate(data.expiresAt);
        const redeemedAt = parseFirestoreDate(data.redeemedAt);
        const status = rewardStatusFromData(data);

        if (status === 'already_used') {
          return {
            status,
            reward: {
              id: doc.id,
              userId: data.userId || null,
              rewardTitle: data.rewardTitle || null,
              rewardCategory: data.rewardCategory || null,
              pointsRequired: typeof data.pointsRequired === 'number' ? data.pointsRequired : null,
              redemptionCode: data.redemptionCode || null,
              redeemedAt: redeemedAt ? redeemedAt.toISOString() : null,
              expiresAt: expiresAt ? expiresAt.toISOString() : null,
              isUsed: true,
              isExpired: data.isExpired === true || (expiresAt ? expiresAt <= new Date() : false),
              selectedItemId: data.selectedItemId || null,
              selectedItemName: data.selectedItemName || null,
              selectedToppingId: data.selectedToppingId || null,
              selectedToppingName: data.selectedToppingName || null,
              selectedItemId2: data.selectedItemId2 || null,
              selectedItemName2: data.selectedItemName2 || null,
              cookingMethod: data.cookingMethod || null,
              drinkType: data.drinkType || null,
              selectedDrinkItemId: data.selectedDrinkItemId || null,
              selectedDrinkItemName: data.selectedDrinkItemName || null
            }
          };
        }

        if (status === 'expired') {
          // Mark as expired so it won’t show up in future active queries.
          tx.update(rewardRef, { isExpired: true });
          return {
            status,
            reward: {
              id: doc.id,
              userId: data.userId || null,
              rewardTitle: data.rewardTitle || null,
              rewardCategory: data.rewardCategory || null,
              pointsRequired: typeof data.pointsRequired === 'number' ? data.pointsRequired : null,
              redemptionCode: data.redemptionCode || null,
              redeemedAt: redeemedAt ? redeemedAt.toISOString() : null,
              expiresAt: expiresAt ? expiresAt.toISOString() : null,
              isUsed: false,
              isExpired: true,
              selectedItemId: data.selectedItemId || null,
              selectedItemName: data.selectedItemName || null,
              selectedToppingId: data.selectedToppingId || null,
              selectedToppingName: data.selectedToppingName || null,
              selectedItemId2: data.selectedItemId2 || null,
              selectedItemName2: data.selectedItemName2 || null,
              cookingMethod: data.cookingMethod || null,
              drinkType: data.drinkType || null,
              selectedDrinkItemId: data.selectedDrinkItemId || null,
              selectedDrinkItemName: data.selectedDrinkItemName || null
            }
          };
        }

        // OK -> consume
        tx.update(rewardRef, {
          isUsed: true,
          usedAt: admin.firestore.FieldValue.serverTimestamp(),
          // Back-compat (old field names)
          usedByAdminUid: staffUid,
          ...(staffEmail ? { usedByAdminEmail: staffEmail } : {}),
          // New, clearer fields
          usedByStaffUid: staffUid,
          usedByStaffRole: staffRole,
          ...(staffEmail ? { usedByStaffEmail: staffEmail } : {})
        });

        return {
          status: 'ok',
          reward: {
            id: doc.id,
            userId: data.userId || null,
            rewardTitle: data.rewardTitle || null,
            rewardDescription: data.rewardDescription || null,
            rewardCategory: data.rewardCategory || null,
            pointsRequired: typeof data.pointsRequired === 'number' ? data.pointsRequired : null,
            redemptionCode: data.redemptionCode || null,
            redeemedAt: redeemedAt ? redeemedAt.toISOString() : null,
            expiresAt: expiresAt ? expiresAt.toISOString() : null,
            isUsed: true,
            isExpired: false,
            selectedItemId: data.selectedItemId || null,
            selectedItemName: data.selectedItemName || null,
            selectedToppingId: data.selectedToppingId || null,
            selectedToppingName: data.selectedToppingName || null,
            selectedItemId2: data.selectedItemId2 || null,
            selectedItemName2: data.selectedItemName2 || null,
            cookingMethod: data.cookingMethod || null,
            drinkType: data.drinkType || null,
            selectedDrinkItemId: data.selectedDrinkItemId || null,
            selectedDrinkItemName: data.selectedDrinkItemName || null
          }
        };
      });

      return res.json(result);
    } catch (error) {
      console.error('❌ Error consuming reward code:', error);
      return res.status(500).json({ error: 'Failed to consume reward code' });
    }
  });

  // ---------------------------------------------------------------------------
  // Admin Reward Tier Item Management
  // ---------------------------------------------------------------------------

  // Get all reward tiers with their eligible items
  app.get('/admin/reward-tiers', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();
      const snapshot = await db.collection('rewardTierItems')
        .orderBy('pointsRequired', 'asc')
        .get();

      const tiers = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));

      console.log(`📋 Fetched ${tiers.length} reward tiers`);
      res.json({ tiers });

    } catch (error) {
      console.error('❌ Error fetching reward tiers:', error);
      res.status(500).json({ error: 'Failed to fetch reward tiers' });
    }
  });

  // Create or update a reward tier with eligible items
  app.post('/admin/reward-tiers/items', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { pointsRequired, tierName, eligibleItems } = req.body;

      if (!pointsRequired || typeof pointsRequired !== 'number' || pointsRequired <= 0) {
        return res.status(400).json({ error: 'Invalid pointsRequired. Must be a positive number.' });
      }

      if (!Array.isArray(eligibleItems)) {
        return res.status(400).json({ error: 'eligibleItems must be an array.' });
      }

      // Validate eligible items structure
      for (const item of eligibleItems) {
        if (!item.itemId || !item.itemName) {
          return res.status(400).json({ error: 'Each eligible item must have itemId and itemName.' });
        }
      }

      const db = admin.firestore();

      // Check if tier already exists
      const existingSnapshot = await db.collection('rewardTierItems')
        .where('pointsRequired', '==', pointsRequired)
        .limit(1)
        .get();

      const tierData = {
        pointsRequired,
        tierName: tierName || `${pointsRequired} Points Tier`,
        eligibleItems: eligibleItems.map(item => ({
          itemId: item.itemId,
          itemName: item.itemName,
          categoryId: item.categoryId || null,
          imageURL: item.imageURL || null
        })),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: adminContext.uid
      };

      let docId;
      if (!existingSnapshot.empty) {
        // Update existing tier
        docId = existingSnapshot.docs[0].id;
        await db.collection('rewardTierItems').doc(docId).update(tierData);
        console.log(`✏️ Updated reward tier ${pointsRequired} with ${eligibleItems.length} items`);
      } else {
        // Create new tier
        docId = `tier_${pointsRequired}`;
        tierData.createdAt = admin.firestore.FieldValue.serverTimestamp();
        await db.collection('rewardTierItems').doc(docId).set(tierData);
        console.log(`➕ Created reward tier ${pointsRequired} with ${eligibleItems.length} items`);
      }

      res.json({
        success: true,
        tierId: docId,
        pointsRequired,
        itemCount: eligibleItems.length,
        message: existingSnapshot.empty ? 'Reward tier created' : 'Reward tier updated'
      });

    } catch (error) {
      console.error('❌ Error saving reward tier items:', error);
      res.status(500).json({ error: 'Failed to save reward tier items' });
    }
  });

  // Add a single item to a reward tier
  app.post('/admin/reward-tiers/:tierId/add-item', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { tierId } = req.params;
      const { tierName, pointsRequired, itemId, itemName, categoryId, imageURL } = req.body;

      if (!tierId) {
        return res.status(400).json({ error: 'tierId is required' });
      }

      if (!itemId || !itemName) {
        return res.status(400).json({ error: 'itemId and itemName are required' });
      }

      const db = admin.firestore();

      const newItem = {
        itemId,
        itemName,
        categoryId: categoryId || null,
        imageURL: imageURL || null
      };

      const tierRef = db.collection('rewardTierItems').doc(tierId);
      const tierDoc = await tierRef.get();

      if (!tierDoc.exists) {
        if (!pointsRequired || typeof pointsRequired !== 'number' || pointsRequired <= 0) {
          return res.status(400).json({ error: 'pointsRequired is required to create a new tier' });
        }
        // Create new tier with this item
        await tierRef.set({
          pointsRequired,
          tierName: tierName || `${pointsRequired} Points Tier`,
          eligibleItems: [newItem],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: adminContext.uid
        });
        console.log(`➕ Created tier ${tierId} with item: ${itemName}`);
      } else {
        // Add to existing tier (avoid duplicates)
        const tierData = tierDoc.data();
        const existingItems = tierData.eligibleItems || [];
        
        // Check if item already exists
        if (existingItems.some(item => item.itemId === itemId)) {
          return res.status(400).json({ error: 'Item already exists in this tier' });
        }

        await tierRef.update({
          eligibleItems: admin.firestore.FieldValue.arrayUnion(newItem),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: adminContext.uid
        });
        console.log(`➕ Added item ${itemName} to tier ${tierId}`);
      }

      res.json({
        success: true,
        tierId,
        pointsRequired: pointsRequired || null,
        itemAdded: itemName,
        message: 'Item added to reward tier'
      });

    } catch (error) {
      console.error('❌ Error adding item to reward tier:', error);
      res.status(500).json({ error: 'Failed to add item to reward tier' });
    }
  });

  // Remove an item from a reward tier
  app.delete('/admin/reward-tiers/:tierId/remove-item/:itemId', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { tierId, itemId } = req.params;

      if (!itemId) {
        return res.status(400).json({ error: 'itemId is required' });
      }

      const db = admin.firestore();

      const tierRef = db.collection('rewardTierItems').doc(tierId);
      const tierDoc = await tierRef.get();

      if (!tierDoc.exists) {
        return res.status(404).json({ error: 'Reward tier not found' });
      }

      const tierData = tierDoc.data();
      const existingItems = tierData.eligibleItems || [];
      
      const itemToRemove = existingItems.find(item => item.itemId === itemId);
      if (!itemToRemove) {
        return res.status(404).json({ error: 'Item not found in this tier' });
      }

      await tierRef.update({
        eligibleItems: admin.firestore.FieldValue.arrayRemove(itemToRemove),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: adminContext.uid
      });

      console.log(`🗑️ Removed item ${itemId} from tier ${tierId}`);

      res.json({
        success: true,
        tierId,
        itemRemoved: itemId,
        message: 'Item removed from reward tier'
      });

    } catch (error) {
      console.error('❌ Error removing item from reward tier:', error);
      res.status(500).json({ error: 'Failed to remove item from reward tier' });
    }
  });

  // List scanned receipts for Admin Office
  app.get('/admin/receipts', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();

      // Basic pagination: limit + optional startAfter timestamp
      const pageSize = Math.min(parseInt(req.query.limit, 10) || 50, 200);
      const startAfterTs = req.query.startAfter ? new Date(req.query.startAfter) : null;

      let query = db.collection('usedReceipts')
        .orderBy('timestamp', 'desc')
        .limit(pageSize);

      if (startAfterTs && !isNaN(startAfterTs.getTime())) {
        query = query.startAfter(startAfterTs);
      }

      const snapshot = await query.get();

      const receipts = [];
      const userIds = new Set();

      snapshot.forEach(doc => {
        const data = doc.data() || {};
        if (data.userId) {
          userIds.add(data.userId);
        }
      });

      // Fetch basic user info for all involved users
      const usersMap = {};
      if (userIds.size > 0) {
        const userIdArray = Array.from(userIds);
        const userPromises = userIdArray.map(async userId => {
          try {
            const userDoc = await db.collection('users').doc(userId).get();
            if (userDoc.exists) {
              usersMap[userId] = userDoc.data() || {};
            }
          } catch (err) {
            console.warn('⚠️ Failed to load user for receipt list:', userId, err.message || err);
          }
        });
        await Promise.all(userPromises);
      }

      snapshot.forEach(doc => {
        const data = doc.data() || {};
        const userInfo = data.userId ? (usersMap[data.userId] || {}) : {};

        receipts.push({
          id: doc.id,
          orderNumber: data.orderNumber || null,
          orderDate: data.orderDate || null,
          timestamp: data.timestamp ? data.timestamp.toDate().toISOString() : null,
          userId: data.userId || null,
          userName: userInfo.firstName || userInfo.name || null,
          userPhone: userInfo.phone || null
        });
      });

      const lastDoc = snapshot.docs[snapshot.docs.length - 1];
      const nextPageToken = lastDoc && lastDoc.get('timestamp')
        ? lastDoc.get('timestamp').toDate().toISOString()
        : null;

      res.json({
        receipts,
        nextPageToken
      });
    } catch (error) {
      console.error('❌ Error listing admin receipts:', error);
      res.status(500).json({ error: 'Failed to load receipts for admin' });
    }
  });

  // Delete a scanned receipt so it can be rescanned
  app.delete('/admin/receipts/:id', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();
      const receiptId = req.params.id;

      const usedReceiptRef = db.collection('usedReceipts').doc(receiptId);
      const usedReceiptDoc = await usedReceiptRef.get();

      if (!usedReceiptDoc.exists) {
        return res.status(404).json({ error: 'Receipt not found' });
      }

      const usedData = usedReceiptDoc.data() || {};
      const { orderNumber, orderDate, userId } = usedData;

      if (!orderNumber || !orderDate) {
        console.warn('⚠️ Used receipt missing orderNumber or orderDate; deleting usedReceipts doc only');
      }

      const batch = db.batch();

      // Always delete the usedReceipts entry
      batch.delete(usedReceiptRef);

      // Also delete any backend receipts that match this orderNumber + orderDate
      if (orderNumber && orderDate) {
        try {
          const receiptsRef = db.collection('receipts');
          const receiptsSnapshot = await receiptsRef
            .where('orderNumber', '==', orderNumber)
            .where('orderDate', '==', orderDate)
            .get();

          receiptsSnapshot.forEach(doc => {
            batch.delete(doc.ref);
          });
        } catch (matchErr) {
          console.warn('⚠️ Failed to query matching receipts for deletion:', matchErr.message || matchErr);
        }
      }

      // Log admin action for audit
      const actionRef = db.collection('adminActions').doc();
      batch.set(actionRef, {
        type: 'deleteReceipt',
        performedBy: adminContext.uid,
        receiptDocId: receiptId,
        orderNumber: orderNumber || null,
        orderDate: orderDate || null,
        userId: userId || null,
        reason: req.body && req.body.reason ? String(req.body.reason).slice(0, 500) : null,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });

      await batch.commit();

      console.log('🗑️ Admin deleted receipt and related records:', {
        receiptId,
        orderNumber,
        orderDate,
        userId,
        adminId: adminContext.uid
      });

      res.json({ success: true });
    } catch (error) {
      console.error('❌ Error deleting admin receipt:', error);
      res.status(500).json({ error: 'Failed to delete receipt for admin' });
    }
  });

  // ---------------------------------------------------------------------------
  // Admin Notifications - Send Push & In-App Notifications to Customers
  // ---------------------------------------------------------------------------

  /**
   * POST /admin/notifications/send
   * 
   * Send push notifications to all customers or specific users.
   * 
   * Request body:
   * {
   *   title: string (required) - Notification title
   *   body: string (required) - Notification message body
   *   targetType: 'all' | 'individual' (required) - Target audience
   *   userIds: string[] (required if targetType is 'individual') - Specific user IDs
   * }
   * 
   * Response:
   * {
   *   success: true,
   *   successCount: number,
   *   failureCount: number,
   *   notificationId: string
   * }
   */
  app.post('/admin/notifications/send', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { title, body, targetType, userIds, includeAdmins, isPromotional } = req.body;

      // Validate required fields
      if (!title || typeof title !== 'string' || title.trim().length === 0) {
        return res.status(400).json({ error: 'Notification title is required' });
      }

      if (!body || typeof body !== 'string' || body.trim().length === 0) {
        return res.status(400).json({ error: 'Notification body is required' });
      }

      if (!targetType || !['all', 'individual'].includes(targetType)) {
        return res.status(400).json({ error: 'targetType must be "all" or "individual"' });
      }

      if (targetType === 'individual') {
        if (!Array.isArray(userIds) || userIds.length === 0) {
          return res.status(400).json({ error: 'userIds array is required for individual targeting' });
        }
      }

      // Parse includeAdmins (optional, defaults to false for backward compatibility)
      const shouldIncludeAdmins = includeAdmins === true;
      
      // Parse isPromotional (optional, defaults to true for backward compatibility - admin notifications are promotional by default)
      // If not provided, assume promotional to maintain compliance (opt-in required)
      const isPromotionalNotification = isPromotional !== false;

      const db = admin.firestore();
      const trimmedTitle = title.trim();
      const trimmedBody = body.trim();

      const recipientDescription = targetType === 'all' 
        ? (shouldIncludeAdmins ? 'all users (including admins)' : 'all users')
        : `${userIds.length} users`;
      const notificationTypeDescription = isPromotionalNotification ? 'promotional' : 'transactional';
      console.log(`📨 Admin ${adminContext.uid} sending ${notificationTypeDescription} notification: "${trimmedTitle}" to ${recipientDescription}`);

      // Fetch FCM tokens based on target type
      let usersSnapshot;
      if (targetType === 'all') {
        // Get all users with FCM tokens (excluding admins)
        const pageSize = 500;
        let lastDoc = null;
        const allDocs = [];

        while (true) {
          let query = db.collection('users')
            .where('hasFcmToken', '==', true)
            .limit(pageSize);

          if (lastDoc) {
            query = query.startAfter(lastDoc);
          }

          const pageSnapshot = await query.get();
          if (pageSnapshot.empty) {
            break;
          }

          allDocs.push(...pageSnapshot.docs);
          lastDoc = pageSnapshot.docs[pageSnapshot.docs.length - 1];

          if (pageSnapshot.docs.length < pageSize) {
            break;
          }
        }

        usersSnapshot = { docs: allDocs, empty: allDocs.length === 0 };
      } else {
        // Get specific users
        // Firestore 'in' queries are limited to 30 items, so we batch if needed
        const batchSize = 30;
        const userBatches = [];
        for (let i = 0; i < userIds.length; i += batchSize) {
          userBatches.push(userIds.slice(i, i + batchSize));
        }

        const allDocs = [];
        for (const batch of userBatches) {
          const batchSnapshot = await db.collection('users')
            .where(admin.firestore.FieldPath.documentId(), 'in', batch)
            .get();
          allDocs.push(...batchSnapshot.docs);
        }
        usersSnapshot = { docs: allDocs, empty: allDocs.length === 0 };
      }

      // Filter to users with valid FCM tokens (conditionally exclude admins for broadcast)
      // Also filter by promotional preference if this is a promotional notification
      const tokensToSend = [];
      const targetUserIdsForLog = [];
      let excludedAdminCount = 0;
      let missingFcmTokenCount = 0;
      let excludedPromotionalOptOutCount = 0;

      for (const doc of usersSnapshot.docs) {
        const userData = doc.data() || {};
        
        // Skip admin users for broadcast unless includeAdmins is true
        if (targetType === 'all' && userData.isAdmin === true && !shouldIncludeAdmins) {
          excludedAdminCount += 1;
          continue;
        }

        // For promotional notifications, only send to users who have opted in
        // Default to false if field doesn't exist (opt-in by default for compliance)
        if (isPromotionalNotification) {
          const hasOptedIn = userData.promotionalNotificationsEnabled === true;
          if (!hasOptedIn) {
            excludedPromotionalOptOutCount += 1;
            continue;
          }
        }

        const fcmToken = userData.fcmToken;
        if (fcmToken && typeof fcmToken === 'string' && fcmToken.length > 0) {
          tokensToSend.push(fcmToken);
          targetUserIdsForLog.push(doc.id);
        } else {
          missingFcmTokenCount += 1;
        }
      }

      if (tokensToSend.length === 0) {
        console.log('⚠️ No valid FCM tokens found for notification');
        const diagnostics = (targetType === 'all')
          ? {
              targetType,
              matchedHasFcmTokenCount: usersSnapshot.docs.length,
              excludedAdminCount,
              excludedPromotionalOptOutCount: isPromotionalNotification ? excludedPromotionalOptOutCount : undefined,
              missingFcmTokenCount
            }
          : {
              targetType,
              requestedCount: Array.isArray(userIds) ? userIds.length : 0,
              foundUserDocsCount: usersSnapshot.docs.length,
              excludedPromotionalOptOutCount: isPromotionalNotification ? excludedPromotionalOptOutCount : undefined,
              missingFcmTokenCount
            };

        const hint = (targetType === 'all' && usersSnapshot.docs.length === 0)
          ? 'No users matched hasFcmToken==true. Ensure devices store tokens (e.g. POST /me/fcmToken) and that the backend and client are using the same Firebase project.'
          : 'Ensure targeted users have a non-empty fcmToken stored on their user document.';

        return res.status(400).json({
          error: 'No users with push notifications enabled found',
          successCount: 0,
          failureCount: 0,
          diagnostics,
          hint
        });
      }

      console.log(`📱 Sending to ${tokensToSend.length} devices...`);

      // Send push notifications via FCM
      let successCount = 0;
      let failureCount = 0;

      // FCM sendEachForMulticast is limited to 500 tokens per call
      const fcmBatchSize = 500;
      for (let i = 0; i < tokensToSend.length; i += fcmBatchSize) {
        const batchTokens = tokensToSend.slice(i, i + fcmBatchSize);
        
        const message = {
          notification: {
            title: trimmedTitle,
            body: trimmedBody
          },
          data: {
            type: targetType === 'all' ? 'admin_broadcast' : 'admin_individual',
            timestamp: new Date().toISOString()
          },
          tokens: batchTokens
        };

        try {
          const response = await admin.messaging().sendEachForMulticast(message);
          successCount += response.successCount;
          failureCount += response.failureCount;

          // Log any failures for debugging
          if (response.failureCount > 0) {
            response.responses.forEach((resp, idx) => {
              if (!resp.success) {
                console.warn(`❌ FCM send failed for token ${idx}: ${resp.error?.code || 'unknown'}`);
              }
            });
          }
        } catch (fcmError) {
          console.error('❌ FCM batch send error:', fcmError);
          failureCount += batchTokens.length;
        }
      }

      // Log the sent notification for admin audit
      const sentNotifRef = db.collection('sentNotifications').doc();
      await sentNotifRef.set({
        title: trimmedTitle,
        body: trimmedBody,
        targetType,
        targetUserIds: targetType === 'individual' ? userIds : null,
        includeAdmins: shouldIncludeAdmins,
        isPromotional: isPromotionalNotification,
        sentBy: adminContext.uid,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        successCount,
        failureCount,
        totalTargeted: tokensToSend.length,
        excludedPromotionalOptOutCount: isPromotionalNotification ? excludedPromotionalOptOutCount : undefined
      });

      // Create in-app notifications for each target user (batch in chunks)
      const notificationType = targetType === 'all' ? 'admin_broadcast' : 'admin_individual';
      const batchSize = 450;

      for (let i = 0; i < targetUserIdsForLog.length; i += batchSize) {
        const batch = db.batch();
        const batchIds = targetUserIdsForLog.slice(i, i + batchSize);

        for (const userId of batchIds) {
          const notifRef = db.collection('notifications').doc();
          batch.set(notifRef, {
            userId,
            title: trimmedTitle,
            body: trimmedBody,
            type: notificationType,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
          });
        }

        await batch.commit();
      }

      console.log(`✅ Notification sent: ${successCount} success, ${failureCount} failed`);

      res.json({
        success: true,
        successCount,
        failureCount,
        notificationId: sentNotifRef.id,
        totalTargeted: tokensToSend.length
      });

    } catch (error) {
      console.error('❌ Error sending admin notification:', error);
      res.status(500).json({ error: 'Failed to send notification' });
    }
  });

  /**
   * GET /admin/notifications/history
   * 
   * Get history of sent notifications (for admin audit).
   */
  app.get('/admin/notifications/history', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();
      const limit = Math.min(parseInt(req.query.limit, 10) || 20, 100);

      const snapshot = await db.collection('sentNotifications')
        .orderBy('sentAt', 'desc')
        .limit(limit)
        .get();

      const notifications = snapshot.docs.map(doc => {
        const data = doc.data();
        return {
          id: doc.id,
          title: data.title,
          body: data.body,
          targetType: data.targetType,
          targetUserIds: data.targetUserIds,
          sentBy: data.sentBy,
          sentAt: data.sentAt?.toDate()?.toISOString() || null,
          successCount: data.successCount || 0,
          failureCount: data.failureCount || 0,
          totalTargeted: data.totalTargeted || 0
        };
      });

      res.json({ notifications });

    } catch (error) {
      console.error('❌ Error fetching notification history:', error);
      res.status(500).json({ error: 'Failed to fetch notification history' });
    }
  });

  /**
   * GET /admin/stats
   * 
   * Get aggregated statistics for admin overview dashboard.
   * Returns counts of users, receipts, rewards, and points.
   * 
   * Response:
   * {
   *   totalUsers: number,
   *   newUsersToday: number,
   *   newUsersThisWeek: number,
   *   totalReceipts: number,
   *   receiptsToday: number,
   *   receiptsThisWeek: number,
   *   totalRewardsRedeemed: number,
   *   rewardsRedeemedToday: number,
   *   totalPointsDistributed: number
   * }
   */
  
  // Cache for admin stats to reduce Firestore reads (2 minute TTL)
  const adminStatsCache = {
    data: null,
    timestamp: null,
    ttl: 2 * 60 * 1000 // 2 minutes in milliseconds
  };
  
  app.get('/admin/stats', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      // Check cache first
      const cacheNow = Date.now();
      if (adminStatsCache.data && adminStatsCache.timestamp && 
          (cacheNow - adminStatsCache.timestamp) < adminStatsCache.ttl) {
        console.log('📊 Admin stats served from cache');
        return res.json(adminStatsCache.data);
      }

      const db = admin.firestore();
      
      // Calculate date boundaries
      const now = new Date();
      const todayStart = new Date(now);
      todayStart.setHours(0, 0, 0, 0);
      
      const weekAgo = new Date(now);
      weekAgo.setDate(weekAgo.getDate() - 7);
      weekAgo.setHours(0, 0, 0, 0);

      // Run all queries in parallel for efficiency
      // Note: Using .get() and .size instead of .count().get() for compatibility
      const [
        usersSnapshot,
        usersTodaySnapshot,
        usersWeekSnapshot,
        receiptsSnapshot,
        receiptsTodaySnapshot,
        receiptsWeekSnapshot,
        rewardsSnapshot,
        rewardsTodaySnapshot,
        pointsSnapshot
      ] = await Promise.all([
        // Total users count
        db.collection('users').get(),
        
        // New users today (check both accountCreatedDate and createdAt for compatibility)
        db.collection('users')
          .where('accountCreatedDate', '>=', todayStart)
          .get(),
        
        // New users this week
        db.collection('users')
          .where('accountCreatedDate', '>=', weekAgo)
          .get(),
        
        // Total receipts scanned
        db.collection('usedReceipts').get(),
        
        // Receipts scanned today
        db.collection('usedReceipts')
          .where('timestamp', '>=', todayStart)
          .get(),
        
        // Receipts scanned this week
        db.collection('usedReceipts')
          .where('timestamp', '>=', weekAgo)
          .get(),
        
        // Total rewards redeemed (isUsed = true)
        db.collection('redeemedRewards')
          .where('isUsed', '==', true)
          .get(),
        
        // Rewards redeemed today
        db.collection('redeemedRewards')
          .where('isUsed', '==', true)
          .where('usedAt', '>=', todayStart)
          .get(),
        
        // Get aggregate points from users collection
        db.collection('users').select('lifetimePoints').get()
      ]);

      // Calculate total points distributed from all users' lifetime points
      let totalPointsDistributed = 0;
      pointsSnapshot.forEach(doc => {
        const data = doc.data();
        if (typeof data.lifetimePoints === 'number') {
          totalPointsDistributed += data.lifetimePoints;
        }
      });

      const stats = {
        totalUsers: usersSnapshot.size || 0,
        newUsersToday: usersTodaySnapshot.size || 0,
        newUsersThisWeek: usersWeekSnapshot.size || 0,
        totalReceipts: receiptsSnapshot.size || 0,
        receiptsToday: receiptsTodaySnapshot.size || 0,
        receiptsThisWeek: receiptsWeekSnapshot.size || 0,
        totalRewardsRedeemed: rewardsSnapshot.size || 0,
        rewardsRedeemedToday: rewardsTodaySnapshot.size || 0,
        totalPointsDistributed
      };

      // Update cache
      adminStatsCache.data = stats;
      adminStatsCache.timestamp = cacheNow;

      console.log('📊 Admin stats fetched and cached:', stats);
      res.json(stats);

    } catch (error) {
      console.error('❌ Error fetching admin stats:', error);
      res.status(500).json({ error: 'Failed to fetch admin statistics' });
    }
  });

  /**
   * GET /check-ban-status
   * 
   * Public endpoint to check if a phone number is banned.
   * Called by iOS before sending SMS verification code.
   * 
   * Query params:
   * - phone: normalized phone number (e.g., "+15551234567")
   * 
   * Response:
   * {
   *   isBanned: boolean
   * }
   */
  app.get('/check-ban-status', async (req, res) => {
    try {
      const phone = req.query.phone;
      if (!phone || typeof phone !== 'string') {
        return res.status(400).json({ error: 'Phone number is required' });
      }

      // Normalize phone number to match iOS format: +1XXXXXXXXXX (12 characters)
      // iOS sends: +1 + 10 digits = 12 characters
      let normalizedPhone = phone.trim();
      
      // Remove all non-digit characters except leading +
      const digits = normalizedPhone.replace(/[^\d]/g, '');
      
      // If it starts with +1, keep it; if it starts with 1, add +; if 10 digits, add +1
      if (normalizedPhone.startsWith('+1') && digits.length === 11) {
        // Already has +1 prefix with 11 digits (1 + 10)
        normalizedPhone = normalizedPhone.substring(0, 12); // Ensure exactly 12 chars
      } else if (normalizedPhone.startsWith('+') && digits.length === 11) {
        // Has + but missing 1, add it
        normalizedPhone = '+1' + digits.substring(1);
      } else if (digits.length === 11 && digits.startsWith('1')) {
        // 11 digits starting with 1, add +
        normalizedPhone = '+' + digits;
      } else if (digits.length === 10) {
        // 10 digits, add +1
        normalizedPhone = '+1' + digits;
      } else {
        // Try to fix: if it has + but wrong format, try to normalize
        if (normalizedPhone.startsWith('+')) {
          normalizedPhone = '+' + digits;
        } else {
          normalizedPhone = '+1' + digits;
        }
      }

      // Ensure it's exactly 12 characters: +1XXXXXXXXXX
      if (normalizedPhone.length !== 12 || !normalizedPhone.startsWith('+1')) {
        console.warn(`⚠️ Phone normalization warning: ${phone} -> ${normalizedPhone} (expected +1XXXXXXXXXX)`);
        // Try one more time with just digits
        if (digits.length >= 10) {
          const last10 = digits.slice(-10); // Take last 10 digits
          normalizedPhone = '+1' + last10;
        }
      }

      const db = admin.firestore();
      
      // Check bannedNumbers collection (prefer hashed doc IDs; fall back to legacy)
      let isBanned = false;
      const hashedId = hashBannedNumbersDocId(normalizedPhone);
      if (hashedId) {
        const hashedDoc = await db.collection('bannedNumbers').doc(hashedId).get();
        isBanned = hashedDoc.exists;
      }
      if (!isBanned) {
        const bannedDoc = await db.collection('bannedNumbers').doc(normalizedPhone).get();
        isBanned = bannedDoc.exists;
      }
      if (!isBanned) {
        const digitsOnly = normalizedPhone.replace('+', '');
        const altBannedDoc = await db.collection('bannedNumbers').doc(digitsOnly).get();
        isBanned = altBannedDoc.exists;
      }

      res.json({ isBanned });
    } catch (error) {
      console.error('❌ Error checking ban status:', error);
      res.status(500).json({ error: 'Failed to check ban status' });
    }
  });

  /**
   * POST /admin/ban-user
   * 
   * Ban a user by their user ID. Adds their phone number to bannedNumbers
   * and marks the user account as banned.
   * 
   * Body:
   * {
   *   userId: string,
   *   reason?: string
   * }
   * 
   * Response:
   * {
   *   success: true,
   *   phone: string
   * }
   */
  app.post('/admin/ban-user', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { userId, reason } = req.body;
      if (!userId || typeof userId !== 'string') {
        return res.status(400).json({ error: 'userId is required' });
      }

      const db = admin.firestore();
      
      // Get user document
      const userDoc = await db.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return res.status(404).json({ error: 'User not found' });
      }

      const userData = userDoc.data();
      const phone = userData.phone;
      
      if (!phone || typeof phone !== 'string') {
        return res.status(400).json({ error: 'User does not have a phone number' });
      }

      const normalizedPhone = normalizePhoneForBannedNumbers(phone);
      if (!normalizedPhone) {
        return res.status(400).json({ error: 'Invalid phone number format' });
      }
      const bannedDocId = hashBannedNumbersDocId(normalizedPhone);
      if (!bannedDocId) {
        return res.status(500).json({ error: 'Failed to compute ban hash' });
      }

      // Check if already banned
      const bannedDoc = await db.collection('bannedNumbers').doc(bannedDocId).get();
      if (bannedDoc.exists) {
        return res.status(400).json({ error: 'This phone number is already banned' });
      }

      // Add to bannedNumbers collection
      const bannedData = {
        phone: normalizedPhone,
        bannedAt: admin.firestore.FieldValue.serverTimestamp(),
        bannedByUserId: adminContext.uid,
        bannedByEmail: adminContext.email || '',
        originalUserId: userId,
        originalUserName: userData.firstName || 'Unknown',
        reason: reason || null
      };

      await db.collection('bannedNumbers').doc(bannedDocId).set(bannedData);

      // Best-effort cleanup of legacy doc IDs (migration)
      const digitsOnlyLegacy = normalizedPhone.replace('+', '');
      await Promise.all([
        db.collection('bannedNumbers').doc(normalizedPhone).delete().catch(() => {}),
        db.collection('bannedNumbers').doc(digitsOnlyLegacy).delete().catch(() => {})
      ]);

      // Mark user as banned
      await db.collection('users').doc(userId).update({
        isBanned: true
      });

      console.log(`🚫 User ${userId} (${normalizedPhone}) banned by ${adminContext.email}`);
      res.json({ success: true, phone: normalizedPhone });
    } catch (error) {
      console.error('❌ Error banning user:', error);
      res.status(500).json({ error: 'Failed to ban user' });
    }
  });

  /**
   * POST /admin/unban-number
   * 
   * Unban a phone number. Removes from bannedNumbers and updates
   * user account if originalUserId exists.
   * 
   * Body:
   * {
   *   phone: string
   * }
   * 
   * Response:
   * {
   *   success: true
   * }
   */
  app.post('/admin/unban-number', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { phone } = req.body;
      if (!phone || typeof phone !== 'string') {
        return res.status(400).json({ error: 'Phone number is required' });
      }

      const normalizedPhone = normalizePhoneForBannedNumbers(phone) || (phone.startsWith('+') ? phone : `+${phone}`);
      const digitsOnlyLegacy = normalizedPhone.replace('+', '');
      const bannedDocId = hashBannedNumbersDocId(normalizedPhone);

      const db = admin.firestore();
      
      // Get banned number document (hashed first, then legacy)
      let bannedDoc = null;
      if (bannedDocId) {
        const snap = await db.collection('bannedNumbers').doc(bannedDocId).get();
        if (snap.exists) bannedDoc = snap;
      }
      if (!bannedDoc) {
        const snap = await db.collection('bannedNumbers').doc(normalizedPhone).get();
        if (snap.exists) bannedDoc = snap;
      }
      if (!bannedDoc) {
        const snap = await db.collection('bannedNumbers').doc(digitsOnlyLegacy).get();
        if (snap.exists) bannedDoc = snap;
      }
      if (!bannedDoc) return res.status(404).json({ error: 'Phone number is not banned' });

      const bannedData = bannedDoc.data();
      const originalUserId = bannedData?.originalUserId;

      // Remove from bannedNumbers (hashed + legacy best-effort)
      await Promise.all([
        bannedDocId ? db.collection('bannedNumbers').doc(bannedDocId).delete().catch(() => {}) : Promise.resolve(),
        db.collection('bannedNumbers').doc(normalizedPhone).delete().catch(() => {}),
        db.collection('bannedNumbers').doc(digitsOnlyLegacy).delete().catch(() => {})
      ]);

      // If there's an original user ID, unban their account
      if (originalUserId) {
        const userDoc = await db.collection('users').doc(originalUserId).get();
        if (userDoc.exists) {
          await db.collection('users').doc(originalUserId).update({
            isBanned: false
          });
        }
      }

      console.log(`✅ Phone number ${normalizedPhone} unbanned by ${adminContext.email}`);
      res.json({ success: true });
    } catch (error) {
      console.error('❌ Error unbanning number:', error);
      res.status(500).json({ error: 'Failed to unban number' });
    }
  });

  /**
   * GET /admin/banned-numbers
   * 
   * Get paginated list of banned phone numbers with metadata.
   * 
   * Query params:
   * - limit: number of items per page (default: 50)
   * - startAfter: document ID for pagination cursor (optional)
   * 
   * Response:
   * {
   *   bannedNumbers: [
   *     {
   *       phone: string,
   *       bannedAt: string (ISO timestamp),
   *       bannedByEmail: string,
   *       originalUserId: string | null,
   *       originalUserName: string | null,
   *       reason: string | null
   *     }
   *   ],
   *   hasMore: boolean,
   *   nextCursor: string | null
   * }
   */
  app.get('/admin/banned-numbers', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const limit = Math.min(parseInt(req.query.limit) || 50, 100);
      const startAfter = req.query.startAfter;

      const db = admin.firestore();
      let query = db.collection('bannedNumbers')
        .orderBy('bannedAt', 'desc')
        .limit(limit);

      if (startAfter) {
        const startAfterDoc = await db.collection('bannedNumbers').doc(startAfter).get();
        if (startAfterDoc.exists) {
          query = query.startAfter(startAfterDoc);
        }
      }

      const bannedDocs = await query.get();
      const hasMore = bannedDocs.size === limit;

      const bannedNumbers = bannedDocs.docs.map(doc => {
        const data = doc.data();
        return {
          phone: data.phone || doc.id,
          bannedAt: data.bannedAt?.toDate?.().toISOString() || null,
          bannedByEmail: data.bannedByEmail || 'Unknown',
          originalUserId: data.originalUserId || null,
          originalUserName: data.originalUserName || null,
          reason: data.reason || null
        };
      });

      const result = {
        bannedNumbers,
        hasMore,
        nextCursor: hasMore && bannedDocs.size > 0 ? bannedDocs.docs[bannedDocs.size - 1].id : null
      };

      console.log(`📋 Fetched ${bannedNumbers.length} banned numbers (hasMore: ${hasMore})`);
      res.json(result);
    } catch (error) {
      console.error('❌ Error fetching banned numbers:', error);
      res.status(500).json({ error: 'Failed to fetch banned numbers' });
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
