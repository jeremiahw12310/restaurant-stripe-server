require('dotenv').config();
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const helmet = require('helmet');
const fs = require('fs');
const { randomUUID } = require('crypto');
const pino = require('pino');
const pinoHttp = require('pino-http');
const rateLimit = require('express-rate-limit');
const { RedisStore } = require('rate-limit-redis');
const Redis = require('ioredis');
const { OpenAI } = require('openai');
const { DateTime } = require('luxon');

// Initialize structured logger early so all initialization code can use it
const logger = pino({
  level: process.env.LOG_LEVEL || (process.env.NODE_ENV === 'production' ? 'info' : 'debug')
});

// Initialize Sentry (error tracking) - only if DSN is configured
let Sentry = null;
if (process.env.SENTRY_DSN) {
  try {
    Sentry = require('@sentry/node');
    const { nodeProfilingIntegration } = require('@sentry/profiling-node');
    
    Sentry.init({
      dsn: process.env.SENTRY_DSN,
      environment: process.env.NODE_ENV || 'development',
      tracesSampleRate: process.env.NODE_ENV === 'production' ? 0.1 : 1.0,
      profilesSampleRate: process.env.NODE_ENV === 'production' ? 0.1 : 1.0,
      integrations: [
        nodeProfilingIntegration(),
      ],
      release: process.env.SENTRY_RELEASE || undefined,
    });
    logger.info('✅ Sentry initialized for error tracking');
  } catch (error) {
    logger.warn('⚠️ Failed to initialize Sentry:', error.message);
    Sentry = null;
  }
} else {
  logger.info('ℹ️ Sentry not configured (SENTRY_DSN not set)');
}

// Input validation schemas and middleware
const { validate, chatSchema, comboSchema, referralAcceptSchema, adminUserUpdateSchema, redeemRewardSchema, dumplingHeroPostSchema, dumplingHeroCommentSchema, dumplingHeroCommentPreviewSchema } = require('./validation');

// OpenAI timeout helper - wraps API calls with 30-second timeout to prevent hanging requests
const OPENAI_TIMEOUT_MS = 30000;

async function openaiWithTimeout(openaiInstance, createOptions) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);
  
  try {
    const response = await openaiInstance.chat.completions.create(createOptions, { signal: controller.signal });
    clearTimeout(timeoutId);
    return response;
  } catch (error) {
    clearTimeout(timeoutId);
    if (error.name === 'AbortError') {
      throw new Error('OpenAI request timed out after 30 seconds');
    }
    throw error;
  }
}

// Initialize Firebase Admin
const admin = require('firebase-admin');

let firebaseInitialized = false;

// Simple Firebase initialization - use service account key if present
if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    
    // Log only project identifier (safe to expose)
    logger.info('🔍 Service Account loaded for project:', serviceAccount.project_id);
    
    const credential = admin.credential.cert(serviceAccount);
    admin.initializeApp({ credential });
    firebaseInitialized = true;
    logger.info('✅ Firebase Admin initialized with service account key');
    
    // Test if credential can generate access token
    credential.getAccessToken().then(token => {
      logger.info('✅ Service account can generate access tokens');
    }).catch(err => {
      logger.error('❌ Service account CANNOT generate access tokens:', err.message);
    });
  } catch (error) {
    logger.error('❌ Error initializing Firebase Admin with service account key:', error);
  }
} else if (process.env.FIREBASE_AUTH_TYPE === 'adc' || process.env.GOOGLE_CLOUD_PROJECT) {
  try {
    admin.initializeApp({ projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp' });
    firebaseInitialized = true;
    logger.info('✅ Firebase Admin initialized with project ID for ADC');
  } catch (error) {
    logger.error('❌ Error initializing Firebase Admin with ADC:', error);
  }
} else {
  logger.warn('⚠️ No Firebase authentication method found - Firebase features will not work');
}

const path = require('path');
const fsPromises = require('fs').promises;

const app = express();
const upload = multer({ dest: 'uploads/', limits: { fileSize: 10 * 1024 * 1024 } });

app.use(pinoHttp({
  logger,
  genReqId: (req) => {
    const existing = req.headers['x-request-id'];
    if (Array.isArray(existing) && existing.length > 0) return existing[0];
    if (typeof existing === 'string' && existing.trim()) return existing;
    return randomUUID();
  }
}));
app.use((req, res, next) => {
  if (req.id) res.setHeader('X-Request-Id', req.id);
  next();
});

// Sentry request tracing middleware (if Sentry is configured)
if (Sentry) {
  app.use(Sentry.Handlers.requestHandler());
  app.use(Sentry.Handlers.tracingHandler());
}

const redisUrl = process.env.REDIS_URL;
let redisClient = null;
let redisConnected = false;

// Redis connection with retry logic
if (redisUrl) {
  redisClient = new Redis(redisUrl, { 
    enableAutoPipelining: true,
    retryStrategy: (times) => {
      const delay = Math.min(times * 50, 2000);
      return delay;
    },
    maxRetriesPerRequest: 3
  });
  
  redisClient.on('connect', () => {
    redisConnected = true;
    logger.info('✅ Redis connected');
  });
  
  redisClient.on('ready', () => {
    redisConnected = true;
  });
  
  redisClient.on('error', (err) => {
    redisConnected = false;
    logError(err, null, { service: 'redis', operation: 'connection' });
  });
  
  redisClient.on('close', () => {
    redisConnected = false;
    logger.warn('⚠️ Redis connection closed');
  });
  
  redisClient.on('reconnecting', () => {
    logger.info('🔄 Redis reconnecting...');
  });
} else {
  logger.info('ℹ️ Redis not configured (REDIS_URL not set) - using in-memory rate limiting');
}

// Redis health check function
async function checkRedisHealth() {
  if (!redisClient) {
    return { status: 'not_configured', connected: false };
  }
  
  try {
    const result = await Promise.race([
      redisClient.ping(),
      new Promise((_, reject) => setTimeout(() => reject(new Error('Redis ping timeout')), 1000))
    ]);
    return { status: 'connected', connected: true, response: result };
  } catch (error) {
    return { status: 'disconnected', connected: false, error: error.message };
  }
}

// Firebase health check function
async function checkFirebaseHealth() {
  if (!admin.apps.length) {
    return { status: 'not_initialized', connected: false };
  }
  
  try {
    const db = admin.firestore();
    // Simple read operation to test connectivity
    const testRef = db.collection('_health').doc('test');
    await Promise.race([
      testRef.get(),
      new Promise((_, reject) => setTimeout(() => reject(new Error('Firestore timeout')), 2000))
    ]);
    return { status: 'connected', connected: true };
  } catch (error) {
    // Don't fail health check if collection doesn't exist - that's expected
    if (error.code === 7 || error.message.includes('timeout')) {
      return { status: 'timeout', connected: false, error: error.message };
    }
    return { status: 'connected', connected: true }; // Assume connected if we can reach Firestore
  }
}

function validateEnvironment() {
  const missing = [];
  const recommended = [];
  const warnings = [];
  
  // Required environment variables
  if (!process.env.OPENAI_API_KEY) missing.push('OPENAI_API_KEY');
  if (!firebaseInitialized && !admin.apps.length) missing.push('FIREBASE_AUTH');

  // Recommended environment variables
  if (!process.env.REDIS_URL) {
    recommended.push('REDIS_URL');
    warnings.push('⚠️  Redis not configured - rate limiting will use in-memory storage (not scalable across instances)');
  }
  if (!process.env.SENTRY_DSN) {
    recommended.push('SENTRY_DSN');
    warnings.push('⚠️  Sentry not configured - errors will not be tracked in external service');
  }
  if (!process.env.ALLOWED_ORIGINS) {
    warnings.push('ℹ️  ALLOWED_ORIGINS not set - using default origins');
  }

  // Log warnings for recommended variables
  if (warnings.length > 0) {
    warnings.forEach(warning => logger.warn(warning));
  }

  // Log recommended variables
  if (recommended.length > 0 && process.env.NODE_ENV === 'production') {
    logger.warn(`💡 Recommended environment variables not set: ${recommended.join(', ')}`);
    logger.warn('   See documentation for setup instructions');
  }

  // Exit if required variables are missing
  if (missing.length > 0) {
    const message = `❌ Missing required configuration: ${missing.join(', ')}`;
    if (process.env.NODE_ENV === 'production') {
      logger.error(message);
      process.exit(1);
    }
    logger.warn(message);
  }
}

// Structured error logging helper
function logError(error, req = null, context = {}) {
  const errorContext = {
    ...context,
    requestId: req?.id || null,
    userId: req?.auth?.uid || null,
    endpoint: req?.path || req?.url || null,
    method: req?.method || null,
    errorMessage: error?.message || String(error),
    errorStack: error?.stack || null,
  };

  // Log with Pino
  logger.error({ err: error, ...errorContext }, 'Error occurred');

  // Send to Sentry if configured
  if (Sentry) {
    Sentry.withScope((scope) => {
      if (errorContext.requestId) {
        scope.setTag('requestId', errorContext.requestId);
      }
      if (errorContext.userId) {
        scope.setUser({ id: errorContext.userId });
      }
      if (errorContext.endpoint) {
        scope.setTag('endpoint', errorContext.endpoint);
      }
      if (errorContext.method) {
        scope.setTag('method', errorContext.method);
      }
      Object.keys(context).forEach(key => {
        scope.setContext(key, context[key]);
      });
      Sentry.captureException(error);
    });
  }
}

// Security headers - protect against common web vulnerabilities
app.use(helmet({
  contentSecurityPolicy: false, // Disable CSP for API server (responses are JSON, not HTML)
  crossOriginEmbedderPolicy: false // Allow embedding from mobile apps
}));

// CORS configuration - restrict to allowed origins
const allowedOrigins = process.env.ALLOWED_ORIGINS 
  ? process.env.ALLOWED_ORIGINS.split(',') 
  : ['https://dumplinghouseapp.com', 'https://dumplinghouseapp.web.app'];
app.use(cors({
  origin: function(origin, callback) {
    // Allow requests with no origin (mobile apps, Postman, etc.)
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    // In production, be strict; in dev, allow localhost
    if (process.env.NODE_ENV !== 'production' && origin.includes('localhost')) {
      return callback(null, true);
    }
    return callback(new Error('Not allowed by CORS'), false);
  },
  credentials: true
}));

// Body size limits to prevent DoS (1MB for JSON/forms, file uploads handled separately by multer)
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// Serve static files from public folder (privacy policy, terms, refer.html, etc.)
app.use(express.static(path.join(__dirname, 'public')));

// Metrics tracking (must be before routes)
let metrics = {
  requests: 0,
  errors: 0,
  rateLimitHits: 0,
  startTime: Date.now()
};

// Middleware to track metrics
app.use((req, res, next) => {
  metrics.requests++;
  const originalSend = res.send;
  res.send = function(data) {
    if (res.statusCode >= 400) {
      metrics.errors++;
    }
    return originalSend.call(this, data);
  };
  next();
});

// =============================================================================
// Auth + rate limiting helpers (cost protection)
// =============================================================================

function getClientIp(req) {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.trim()) return xf.split(',')[0].trim();
  return req.ip || null;
}

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
    logError(e, req, { operation: 'firebase_auth' });
    return res.status(401).json({ errorCode: 'UNAUTHENTICATED', error: 'Invalid auth token' });
  }
}

async function requireAdminAuth(req, res, next) {
  try {
    const token = getBearerToken(req);
    if (!token) {
      return res.status(401).json({ errorCode: 'UNAUTHENTICATED', error: 'Missing or invalid Authorization header' });
    }
    const decoded = await admin.auth().verifyIdToken(token);
    const uid = decoded.uid;
    const db = admin.firestore();
    const userDoc = await db.collection('users').doc(uid).get();
    const isAdmin = userDoc.exists && userDoc.data()?.isAdmin === true;
    if (!isAdmin) {
      return res.status(403).json({ errorCode: 'FORBIDDEN', error: 'Admin privileges required' });
    }
    req.auth = { uid, decoded, isAdmin: true };
    return next();
  } catch (e) {
    logError(e, req, { operation: 'admin_auth' });
    return res.status(401).json({ errorCode: 'UNAUTHENTICATED', error: 'Invalid auth token' });
  }
}

function normalizeRateLimitOptions({ windowMs, max }) {
  const m = typeof max === 'number' && max > 0 ? max : parseInt(String(max || ''), 10);
  const w = typeof windowMs === 'number' && windowMs > 0 ? windowMs : 60_000;
  return { m, w };
}

// Global registry for all in-memory rate limiter buckets (for periodic cleanup)
const rateLimiterBuckets = [];
const MAX_BUCKETS_PER_LIMITER = 10000; // Hard limit to prevent unbounded growth

function createInMemoryRateLimiter({ keyFn, windowMs, max, errorCode }) {
  const buckets = new Map(); // key -> { count, resetAt }
  const { m, w } = normalizeRateLimitOptions({ windowMs, max });
  let lastCleanupAt = 0;
  
  // Register this limiter's buckets for global cleanup
  rateLimiterBuckets.push({ buckets, windowMs: w });

  return function rateLimitMiddleware(req, res, next) {
    if (!m || m <= 0) return next();
    const key = keyFn(req);
    if (!key) return next();
    const now = Date.now();

    // Periodic cleanup of stale entries (per-limiter)
    if (now - lastCleanupAt > w) {
      for (const [bucketKey, bucket] of buckets.entries()) {
        if (!bucket || bucket.resetAt <= now) {
          buckets.delete(bucketKey);
        }
      }
      lastCleanupAt = now;
    }
    
    // Hard limit: if too many unique keys, evict oldest entries
    if (buckets.size >= MAX_BUCKETS_PER_LIMITER) {
      // Evict 10% of oldest entries to make room
      const toEvict = Math.ceil(MAX_BUCKETS_PER_LIMITER * 0.1);
      const entries = Array.from(buckets.entries());
      entries.sort((a, b) => (a[1]?.resetAt || 0) - (b[1]?.resetAt || 0));
      for (let i = 0; i < toEvict && i < entries.length; i++) {
        buckets.delete(entries[i][0]);
      }
      logger.warn(`⚠️ Rate limiter bucket limit reached, evicted ${toEvict} oldest entries`);
    }

    const existing = buckets.get(key);
    if (!existing || existing.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + w });
      return next();
    }

    existing.count += 1;
    if (existing.count > m) {
      metrics.rateLimitHits++;
      const retryAfterSeconds = Math.max(1, Math.ceil((existing.resetAt - now) / 1000));
      res.set('Retry-After', String(retryAfterSeconds));
      return res.status(429).json({
        errorCode: errorCode || 'RATE_LIMITED',
        error: `You're doing this too quickly. Please wait ${retryAfterSeconds} second${retryAfterSeconds === 1 ? '' : 's'}.`,
        retryAfterSeconds
      });
    }

    return next();
  };
}

// Periodic cleanup of all rate limiter buckets (runs every 60 seconds)
setInterval(() => {
  const now = Date.now();
  let totalCleaned = 0;
  for (const { buckets } of rateLimiterBuckets) {
    for (const [key, bucket] of buckets.entries()) {
      if (!bucket || bucket.resetAt <= now) {
        buckets.delete(key);
        totalCleaned++;
      }
    }
  }
  if (totalCleaned > 0) {
    logger.info(`🧹 Periodic cleanup: removed ${totalCleaned} expired rate limit entries`);
  }
}, 60_000);

function createRateLimiter({ keyFn, windowMs, max, errorCode }) {
  const { m, w } = normalizeRateLimitOptions({ windowMs, max });
  if (!m || m <= 0) {
    return function rateLimitDisabled(req, res, next) {
      return next();
    };
  }
  if (!redisClient) {
    return createInMemoryRateLimiter({ keyFn, windowMs: w, max: m, errorCode });
  }

  return rateLimit({
    windowMs: w,
    max: m,
    skip: (req) => {
      const key = keyFn(req);
      if (!key) return true;
      req.rateLimitKey = key;
      return false;
    },
    keyGenerator: (req) => req.rateLimitKey || keyFn(req),
    standardHeaders: true,
    legacyHeaders: false,
    store: new RedisStore({
      sendCommand: (...args) => redisClient.call(...args)
    }),
    handler: (req, res) => {
      metrics.rateLimitHits++;
      const resetTime = req.rateLimit?.resetTime;
      const retryAfterSeconds = resetTime
        ? Math.max(1, Math.ceil((resetTime.getTime() - Date.now()) / 1000))
        : undefined;
      if (retryAfterSeconds) res.set('Retry-After', String(retryAfterSeconds));
      return res.status(429).json({
        errorCode: errorCode || 'RATE_LIMITED',
        error: retryAfterSeconds 
          ? `You're doing this too quickly. Please wait ${retryAfterSeconds} second${retryAfterSeconds === 1 ? '' : 's'}.`
          : 'You\'re doing this too quickly. Please wait a moment.',
        retryAfterSeconds
      });
    }
  });
}

async function enforceDailyQuota({ db, uid, endpointKey, limit }) {
  const lim = typeof limit === 'number' ? limit : parseInt(String(limit || ''), 10);
  if (!lim || lim <= 0) return { allowed: true };

  const dayKey = DateTime.utc().toFormat('yyyy-LL-dd');
  const ref = db.collection('apiDailyCounters').doc(`${endpointKey}_${uid}_${dayKey}`);

  let allowed = true;
  let count = 0;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    count = snap.exists ? (snap.data()?.count || 0) : 0;
    if (count >= lim) {
      allowed = false;
      return;
    }
    tx.set(ref, { count: count + 1, endpoint: endpointKey, dayKey, uid }, { merge: true });
    count = count + 1;
  });

  return { allowed, count, limit: lim, dayKey };
}

// 🛡️ DIETARY RESTRICTION SAFETY VALIDATION SYSTEM
// This function validates AI-generated combos against user dietary restrictions
// and removes any items that violate those restrictions (Plan B safety net)
function validateDietaryRestrictions(items, dietaryPreferences, allMenuItems) {
  logger.info('🛡️ Starting dietary validation for', items.length, 'items');
  logger.info('🔍 Dietary preferences:', JSON.stringify(dietaryPreferences));
  
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
          logger.info(`🚫 REMOVED: "${item.id}" - contains "${word}" (vegetarian restriction)`);
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
        logger.info(`✅ KEPT: "${item.id}" - can use milk substitute (oat/almond/coconut milk)`);
      } else {
        // Check if item contains dairy that can't be substituted
        for (const word of restrictions.lactose) {
          if (itemNameLower.includes(word)) {
            logger.info(`🚫 REMOVED: "${item.id}" - contains "${word}" (lactose intolerance)`);
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
          logger.info(`🚫 REMOVED: "${item.id}" - contains "${word}" (doesn't eat pork)`);
          removedItems.push(item);
          return false;
        }
      }
    }
    
    // Check peanut allergy
    if (dietaryPreferences.hasPeanutAllergy) {
      for (const word of restrictions.peanutAllergy) {
        if (itemNameLower.includes(word)) {
          logger.info(`🚫 REMOVED: "${item.id}" - contains "${word}" (peanut allergy)`);
          removedItems.push(item);
          return false;
        }
      }
    }
    
    // Check dislikes spicy food
    if (dietaryPreferences.dislikesSpicyFood) {
      for (const word of restrictions.noSpicy) {
        if (itemNameLower.includes(word)) {
          logger.info(`🚫 REMOVED: "${item.id}" - contains "${word}" (dislikes spicy food)`);
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
  
  logger.info(`✅ Validation complete: ${validatedItems.length}/${items.length} items passed`);
  if (removedItems.length > 0) {
    logger.info(`⚠️ Safety system caught ${removedItems.length} dietary violation(s)`);
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

// Hard cap on referrals per user (admins exempt)
const MAX_REFERRALS_PER_USER = 10;

// Referral endpoint rate limiting (moderate brute-force protection)
const referralPerUserLimiter = createRateLimiter({
  keyFn: (req) => req.auth?.uid,
  windowMs: 60_000,
  max: 5,
  errorCode: 'REFERRAL_RATE_LIMITED'
});

const referralPerIpLimiter = createRateLimiter({
  keyFn: (req) => getClientIp(req),
  windowMs: 60_000,
  max: 10,
  errorCode: 'REFERRAL_RATE_LIMITED'
});

// General rate limiter for authenticated endpoints without specific limiters
// 60 requests per minute per user is reasonable for general API access
const generalPerUserLimiter = createRateLimiter({
  keyFn: (req) => req.auth?.uid,
  windowMs: 60_000,
  max: 60,
  errorCode: 'RATE_LIMITED'
});

const generalPerIpLimiter = createRateLimiter({
  keyFn: (req) => getClientIp(req),
  windowMs: 60_000,
  max: 120,
  errorCode: 'RATE_LIMITED'
});

// Create or get referral code
app.post('/referrals/create', requireFirebaseAuth, referralPerUserLimiter, referralPerIpLimiter, async (req, res) => {
  try {
    // Check if Firebase is initialized
    if (!admin.apps.length) {
      logger.error('❌ Firebase not initialized');
      return res.status(503).json({ error: 'Firebase not configured' });
    }
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
    logger.error('Error creating referral code:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Accept referral code
app.post('/referrals/accept', requireFirebaseAuth, referralPerUserLimiter, referralPerIpLimiter, validate(referralAcceptSchema), async (req, res) => {
  try {
    const uid = req.auth.uid;

    const { code } = req.body;
    // Validation middleware ensures code exists and is properly formatted

    const db = admin.firestore();
    const ipAddress = req.ip || req.headers['x-forwarded-for'] || null;
    
    // Extract device fingerprint if provided
    let deviceInfo = null;
    const fingerprintHeader = req.headers['x-device-fingerprint'];
    if (fingerprintHeader) {
      try {
        deviceInfo = JSON.parse(fingerprintHeader);
      } catch (e) {
        logger.warn('⚠️ Failed to parse device fingerprint:', e);
      }
    }
    
    // Record device fingerprint for multi-account detection (async, don't block)
    if (deviceInfo) {
      const service = new SuspiciousBehaviorService(db);
      service.recordDeviceFingerprint(uid, deviceInfo, ipAddress).catch(err => {
        logger.error('❌ Error recording device fingerprint (non-blocking):', err);
      });
    }
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
    const referrerData = referrerDoc.data() || {};

    const referrerFirstName =
      (typeof referrerData.firstName === 'string' && referrerData.firstName.trim().length > 0)
        ? referrerData.firstName.trim()
        : (typeof referrerData.name === 'string' && referrerData.name.trim().length > 0)
          ? referrerData.name.trim().split(' ')[0]
          : 'Friend';

    const referredFirstName =
      (typeof userData.firstName === 'string' && userData.firstName.trim().length > 0)
        ? userData.firstName.trim()
        : (typeof userData.name === 'string' && userData.name.trim().length > 0)
          ? userData.name.trim().split(' ')[0]
          : 'Friend';

    // Can't refer yourself
    if (referrerId === uid) {
      return res.status(400).json({ error: 'cannot_refer_self' });
    }

    // Check for duplicate referral using phone hashes (persists across account deletions)
    const referrerPhoneHash = hashPhoneNumber(referrerData.phone);
    const referredPhoneHash = hashPhoneNumber(userData.phone);
    
    if (referrerPhoneHash && referredPhoneHash) {
      const pairId = `${referrerPhoneHash}_${referredPhoneHash}`;
      const pairDoc = await db.collection('referralPairs').doc(pairId).get();
      
      if (pairDoc.exists) {
        logger.info(`🚫 Referral blocked - phone pair already exists: ${pairId.substring(0, 16)}...`);
        return res.status(400).json({ 
          error: 'referral_already_used',
          message: 'This referral relationship has already been used previously'
        });
      }
    }

    // Check referral cap (admins exempt)
    // 1) Per-account cap: current user's referral count
    // 2) Lifetime cap: phone hash has referred 10+ people across all accounts (survives account deletion)
    const referrerIsAdmin = referrerData.isAdmin === true;
    if (!referrerIsAdmin) {
      // Per-account cap
      const referrerReferralsSnap = await db.collection('referrals')
        .where('referrerUserId', '==', referrerId)
        .get();
      
      if (referrerReferralsSnap.size >= MAX_REFERRALS_PER_USER) {
        logger.info(`⚠️ Referral cap reached for user ${referrerId}: ${referrerReferralsSnap.size} referrals`);
        return res.status(400).json({ 
          error: 'referral_cap_reached',
          message: `Maximum referral limit reached (${MAX_REFERRALS_PER_USER} referrals)`
        });
      }

      // Lifetime cap: this phone has referred 10+ people total (blocks delete-and-refer-again abuse)
      if (referrerPhoneHash) {
        const referrerHashDoc = await db.collection('abusePreventionHashes').doc(referrerPhoneHash).get();
        const referredHashes = referrerHashDoc.exists ? (referrerHashDoc.data().referredHashes || []) : [];
        if (referredHashes.length >= MAX_REFERRALS_PER_USER) {
          logger.info(`⚠️ Lifetime referral cap reached for referrer phone hash: ${referredHashes.length} referrals`);
          return res.status(400).json({ 
            error: 'referral_cap_reached',
            message: `Maximum referral limit reached (${MAX_REFERRALS_PER_USER} referrals)`
          });
        }
      }
    }

    // Create referral document
    // Set initial pointsTowards50 based on current user points (clamped to 0-50)
    const currentUserPoints = userData.points || 0;
    const initialPointsTowards50 = Math.max(0, Math.min(50, currentUserPoints));
    
    const referralRef = await db.collection('referrals').add({
      referrerUserId: referrerId,
      referredUserId: uid,
      // Denormalized names so clients can display without cross-user reads (blocked by Firestore rules)
      referrerFirstName,
      referredFirstName,
      status: 'pending',
      pointsTowards50: initialPointsTowards50, // Set initial progress
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Update user with referredBy
    await userRef.update({
      referredBy: referrerId,
      referralId: referralRef.id
    });

    // Record the referral pair for abuse prevention (persists across account deletions)
    if (referrerPhoneHash && referredPhoneHash) {
      const pairId = `${referrerPhoneHash}_${referredPhoneHash}`;
      await db.collection('referralPairs').doc(pairId).set({
        referrerPhoneHash,
        referredPhoneHash,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        bonusAwarded: false
      });
      
      // Update abuse prevention hashes to track referral relationships
      const referrerHashRef = db.collection('abusePreventionHashes').doc(referrerPhoneHash);
      const referredHashRef = db.collection('abusePreventionHashes').doc(referredPhoneHash);
      
      await Promise.all([
        referrerHashRef.set({
          phoneHash: referrerPhoneHash,
          referredHashes: admin.firestore.FieldValue.arrayUnion(referredPhoneHash),
          lastAccountCreatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true }),
        referredHashRef.set({
          phoneHash: referredPhoneHash,
          referredByHashes: admin.firestore.FieldValue.arrayUnion(referrerPhoneHash),
          lastAccountCreatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true })
      ]);
      
      logger.info(`✅ Referral pair recorded: ${pairId.substring(0, 16)}...`);
    }

    // Check if user already has enough points for immediate award
    if (currentUserPoints >= 50) {
      logger.info(`✅ User ${uid} already has ${currentUserPoints} points, awarding referral bonus immediately`);
      // Award points immediately using the shared helper function
      const awardResult = await awardReferralPoints(db, referralRef.id, referrerId, uid);
      if (awardResult.success) {
        logger.info(`🎉 Referral ${referralRef.id} awarded immediately! Referrer: +${awardResult.referrerNewPoints !== null ? 50 : 0}, Referred: +50`);
      } else {
        logger.warn(`⚠️ Failed to award referral immediately: ${awardResult.error}`);
        // Don't fail the accept request - the award-check endpoint will handle it later
      }
    }

    // Check for suspicious referral patterns (async, don't block response)
    try {
      const service = new SuspiciousBehaviorService(db);
      await service.checkReferralPatterns(uid, {
        referrerId,
        referralId: referralRef.id
      });
      // Also check for new account bonus pattern
      await service.checkNewAccountBonusPattern(uid);
      
      // Flag high-velocity referral accepts from shared device fingerprints or phone-hash clusters
      if (deviceInfo) {
        const fingerprintHash = service.createDeviceFingerprint(deviceInfo);
        const fingerprintDoc = await db.collection('deviceFingerprints').doc(fingerprintHash).get();
        
        if (fingerprintDoc.exists) {
          const fingerprintData = fingerprintDoc.data();
          const associatedUserIds = fingerprintData.associatedUserIds || [];
          
          // Check if multiple accounts on this device have accepted referrals recently
          const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
          let referralCountOnDevice = 0;
          
          for (const deviceUserId of associatedUserIds) {
            const deviceUserReferrals = await db.collection('referrals')
              .where('referredUserId', '==', deviceUserId)
              .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(oneDayAgo))
              .get();
            referralCountOnDevice += deviceUserReferrals.size;
          }
          
          if (referralCountOnDevice >= 3) {
            await service.flagSuspiciousBehavior(uid, {
              flagType: 'referral_abuse',
              severity: 'high',
              description: `High-velocity referral accepts from shared device: ${referralCountOnDevice} referrals accepted by ${associatedUserIds.length} account(s) on same device in last 24 hours`,
              evidence: {
                fingerprintHash,
                accountsOnDevice: associatedUserIds.length,
                referralCountOnDevice,
                timeWindow: '24 hours',
                deviceInfo
              }
            });
          }
        }
      }
      
      // Check for phone hash cluster abuse
      if (referredPhoneHash) {
        const phoneHashDoc = await db.collection('abusePreventionHashes').doc(referredPhoneHash).get();
        if (phoneHashDoc.exists) {
          const phoneHashData = phoneHashDoc.data();
          const referredByHashes = phoneHashData.referredByHashes || [];
          
          // Check if this phone hash has been referred by multiple different phone hashes recently
          if (referredByHashes.length >= 3) {
            const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
            const recentReferrals = await db.collection('referrals')
              .where('referredUserId', '==', uid)
              .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(oneDayAgo))
              .get();
            
            if (recentReferrals.size > 0) {
              await service.flagSuspiciousBehavior(uid, {
                flagType: 'referral_abuse',
                severity: 'medium',
                description: `Phone hash cluster: This phone number has been referred by ${referredByHashes.length} different referrers across account history`,
                evidence: {
                  phoneHash: referredPhoneHash,
                  referredByCount: referredByHashes.length,
                  recentReferrals: recentReferrals.size,
                  timeWindow: '24 hours'
                }
              });
            }
          }
        }
      }
    } catch (detectionError) {
      logger.error('❌ Error in referral pattern detection (non-blocking):', detectionError);
    }

    res.json({
      success: true,
      referrerUserId: referrerId,
      referralId: referralRef.id,
      referrerFirstName,
      referredFirstName
    });
  } catch (error) {
    logger.error('Error accepting referral:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get user's referral connections
app.get('/referrals/mine', requireFirebaseAuth, generalPerUserLimiter, generalPerIpLimiter, async (req, res) => {
  try {
    const uid = req.auth.uid;

    const db = admin.firestore();
    
    // Get outbound (people I referred)
    const outboundSnap = await db.collection('referrals').where('referrerUserId', '==', uid).get();
    const outbound = [];
    
    for (const doc of outboundSnap.docs) {
      const data = doc.data();
      // Use denormalized name from referral doc (avoids cross-user reads)
      const referredName = data.referredFirstName || 'Friend';
      // Read pointsTowards50 from referral doc (maintained by Cloud Function)
      const pointsTowards50 = typeof data.pointsTowards50 === 'number' 
        ? Math.max(0, Math.min(50, data.pointsTowards50))
        : 0;
      
      outbound.push({
        referralId: doc.id,
        referredName: referredName,
        status: data.status || 'pending',
        pointsTowards50: pointsTowards50
      });
    }

    // Get inbound (who referred me)
    const inboundSnap = await db.collection('referrals').where('referredUserId', '==', uid).limit(1).get();
    let inbound = null;
    
    if (!inboundSnap.empty) {
      const doc = inboundSnap.docs[0];
      const data = doc.data();
      // Use denormalized name from referral doc (avoids cross-user reads)
      const referrerName = data.referrerFirstName || 'Friend';
      // Read pointsTowards50 from referral doc (maintained by Cloud Function)
      // For inbound, this represents the current user's own progress
      const pointsTowards50 = typeof data.pointsTowards50 === 'number' 
        ? Math.max(0, Math.min(50, data.pointsTowards50))
        : 0;
      
      inbound = {
        referralId: doc.id,
        referrerName: referrerName,
        status: data.status || 'pending',
        pointsTowards50: pointsTowards50
      };
    }

    res.json({
      outbound,
      inbound
    });
  } catch (error) {
    logger.error('Error fetching referrals:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---------------------------------------------------------------------------
// Referral Award System - Push Notification Helper
// ---------------------------------------------------------------------------

/**
 * Send a push notification to a single FCM token.
 * Returns { success: boolean, error?: string }
 */
async function sendPushNotificationToToken(fcmToken, title, body, data = {}) {
  if (!fcmToken || typeof fcmToken !== 'string' || fcmToken.length === 0) {
    return { success: false, error: 'Invalid or missing FCM token' };
  }

  try {
    // Use Firebase Admin SDK messaging method (handles auth automatically)
    const message = {
      token: fcmToken,
      notification: {
        title: title,
        body: body
      },
      data: {
        ...data,
        timestamp: new Date().toISOString()
      }
    };

    const response = await admin.messaging().send(message);
    logger.info(`✅ FCM push sent successfully:`, response);
    return { success: true };
  } catch (error) {
    logger.warn(`❌ FCM push failed:`, error.message || error);
    return { success: false, error: error.message || 'Unknown error' };
  }
}

// ---------------------------------------------------------------------------
// Referral Award Check Endpoint
// ---------------------------------------------------------------------------

/**
 * Helper function to award referral points to both referrer and referred user.
 * This is used by both /referrals/award-check and /referrals/accept endpoints.
 * 
 * @param {Firestore} db - Firestore database instance
 * @param {string} referralId - The referral document ID
 * @param {string} referrerId - The referrer's user ID
 * @param {string} referredUserId - The referred user's ID
 * @returns {Promise<{success: boolean, referrerNewPoints: number|null, referredNewPoints: number, error?: string}>}
 */
async function awardReferralPoints(db, referralId, referrerId, referredUserId) {
  const REFERRAL_BONUS = 50;
  
  try {
    // Get the referral document
    const referralDoc = await db.collection('referrals').doc(referralId).get();
    if (!referralDoc.exists) {
      return { success: false, error: 'Referral not found' };
    }
    
    const referralData = referralDoc.data();
    
    // Check if already awarded
    if (referralData.status === 'awarded') {
      return { success: false, error: 'ALREADY_AWARDED' };
    }
    // Tombstoned (cancelled); do not award
    if (referralData.status === 'cancelled') {
      return { success: false, error: 'REFERRAL_CANCELLED' };
    }
    
    // Get the referred user's current points
    const referredUserRef = db.collection('users').doc(referredUserId);
    const referredUserDoc = await referredUserRef.get();
    
    if (!referredUserDoc.exists) {
      return { success: false, error: 'Referred user not found' };
    }
    
    const referredUserData = referredUserDoc.data();
    const referredUserPoints = referredUserData.points || 0;
    
    // Check if referred user has reached the 50-point threshold
    if (referredUserPoints < 50) {
      return { 
        success: false, 
        error: 'THRESHOLD_NOT_MET',
        currentPoints: referredUserPoints
      };
    }
    
    logger.info(`✅ User ${referredUserId} has ${referredUserPoints} points, eligible for referral bonus!`);
    
    // Get the referrer's document
    const referrerUserRef = db.collection('users').doc(referrerId);
    const referrerUserDoc = await referrerUserRef.get();
    
    if (!referrerUserDoc.exists) {
      logger.warn(`⚠️ Referrer ${referrerId} not found, proceeding with referred user award only`);
    }
    
    const referrerUserData = referrerUserDoc.exists ? referrerUserDoc.data() : null;
    
    // Use a transaction to award points atomically
    let referrerNewPoints = null;
    let referredNewPoints = null;
    let referrerFcmToken = null;
    let referredFcmToken = null;
    let referrerName = 'Friend';
    let referredName = 'Friend';
    
    await db.runTransaction(async (tx) => {
      // STEP 1: All reads must happen first (Firestore transaction requirement)
      
      // Re-fetch the referral doc inside the transaction to ensure consistency
      const txReferralDoc = await tx.get(db.collection('referrals').doc(referralId));
      if (txReferralDoc.data().status === 'awarded') {
        throw new Error('ALREADY_AWARDED');
      }
      
      // Re-fetch referred user document inside transaction
      const txReferredUserDoc = await tx.get(referredUserRef);
      if (!txReferredUserDoc.exists) {
        throw new Error('Referred user not found');
      }
      const txReferredData = txReferredUserDoc.data() || {};
      const currentReferredPoints = txReferredData.points || 0;
      const currentReferredLifetime = (typeof txReferredData.lifetimePoints === 'number') 
        ? txReferredData.lifetimePoints 
        : currentReferredPoints;
      referredFcmToken = txReferredData.fcmToken || null;
      referredName = txReferredData.firstName || 'Friend';
      
      // Re-fetch referrer user document inside transaction (BEFORE any writes)
      let txReferrerUserDoc = null;
      let txReferrerData = null;
      let referrerNewLifetime = null;
      if (referrerUserDoc.exists) {
        txReferrerUserDoc = await tx.get(referrerUserRef);
        if (txReferrerUserDoc.exists) {
          txReferrerData = txReferrerUserDoc.data() || {};
          const currentReferrerPoints = txReferrerData.points || 0;
          const currentReferrerLifetime = (typeof txReferrerData.lifetimePoints === 'number')
            ? txReferrerData.lifetimePoints
            : currentReferrerPoints;
          referrerFcmToken = txReferrerData.fcmToken || null;
          referrerName = txReferrerData.firstName || 'Friend';
          
          referrerNewPoints = currentReferrerPoints + REFERRAL_BONUS;
          referrerNewLifetime = currentReferrerLifetime + REFERRAL_BONUS;
        }
      }
      
      // STEP 2: Now do all writes (after all reads are complete)
      
      // Award +50 to referred user
      referredNewPoints = currentReferredPoints + REFERRAL_BONUS;
      const referredNewLifetime = currentReferredLifetime + REFERRAL_BONUS;
      
      tx.update(referredUserRef, {
        points: referredNewPoints,
        lifetimePoints: referredNewLifetime
      });
      
      // Create points transaction for referred user
      const referredTxId = `referral_referred_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      tx.set(db.collection('pointsTransactions').doc(referredTxId), {
        userId: referredUserId,
        type: 'referral',
        amount: REFERRAL_BONUS,
        description: 'Referral bonus - reached 50 points!',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          referralId: referralId,
          role: 'referred'
        }
      });
      
      // Award +50 to referrer if they exist
      if (txReferrerUserDoc && txReferrerUserDoc.exists && txReferrerData) {
        tx.update(referrerUserRef, {
          points: referrerNewPoints,
          lifetimePoints: referrerNewLifetime
        });
        
        // Create points transaction for referrer
        const referrerTxId = `referral_referrer_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        tx.set(db.collection('pointsTransactions').doc(referrerTxId), {
          userId: referrerId,
          type: 'referral',
          amount: REFERRAL_BONUS,
          description: `Referral bonus - ${referredName} reached 50 points!`,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          metadata: {
            referralId: referralId,
            role: 'referrer',
            referredUserId: referredUserId
          }
        });
      }
      
      // Update referral status to 'awarded' and set progress to 50
      tx.update(db.collection('referrals').doc(referralId), {
        status: 'awarded',
        awardedAt: admin.firestore.FieldValue.serverTimestamp(),
        pointsTowards50: 50 // Set to 50 when awarded
      });
    });
    
    logger.info(`🎉 Referral ${referralId} awarded! Referrer: +${referrerNewPoints !== null ? REFERRAL_BONUS : 0}, Referred: +${REFERRAL_BONUS}`);
    
    // Create Firestore notification documents for both users
    const notificationPromises = [];
    
    // Create notification for referrer
    if (referrerId) {
      const referrerNotifRef = db.collection('notifications').doc();
      notificationPromises.push(
        referrerNotifRef.set({
          userId: referrerId,
          title: 'Referral Bonus Awarded! 🎉',
          body: `${referredName} reached 50 points! You earned +${REFERRAL_BONUS} bonus points.`,
          type: 'referral',
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          metadata: {
            referralId: referralId,
            role: 'referrer'
          }
        })
      );
    }
    
    // Create notification for referred user
    const referredNotifRef = db.collection('notifications').doc();
    notificationPromises.push(
      referredNotifRef.set({
        userId: referredUserId,
        title: 'Referral Bonus Awarded! 🎉',
        body: `You reached 50 points! You and ${referrerName} each earned +${REFERRAL_BONUS} bonus points.`,
        type: 'referral',
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          referralId: referralId,
          role: 'referred'
        }
      })
    );
    
    // Send push notifications to both users (fire-and-forget, don't block response)
    const pushPromises = [];
    
    // Push to referrer
    if (referrerFcmToken) {
      pushPromises.push(
        sendPushNotificationToToken(
          referrerFcmToken,
          'Referral Bonus Awarded! 🎉',
          `${referredName} reached 50 points! You earned +${REFERRAL_BONUS} bonus points.`,
          { type: 'referral_awarded', role: 'referrer', referralId }
        ).then(result => {
          logger.info(`📱 Referrer push result:`, result);
        })
      );
    } else {
      logger.info(`ℹ️ Referrer ${referrerId} has no FCM token, skipping push`);
    }
    
    // Push to referred user
    if (referredFcmToken) {
      pushPromises.push(
        sendPushNotificationToToken(
          referredFcmToken,
          'Referral Bonus Awarded! 🎉',
          `You reached 50 points! You and ${referrerName} each earned +${REFERRAL_BONUS} bonus points.`,
          { type: 'referral_awarded', role: 'referred', referralId }
        ).then(result => {
          logger.info(`📱 Referred user push result:`, result);
        })
      );
    } else {
      logger.info(`ℹ️ Referred user ${referredUserId} has no FCM token, skipping push`);
    }
    
    // Don't await push notifications - let them complete in background
    Promise.all(pushPromises).catch(err => {
      logError(err, null, { operation: 'push_notifications', referralId });
    });
    
    // Don't await notification documents - let them complete in background
    Promise.all(notificationPromises).catch(err => {
      logError(err, null, { operation: 'notification_documents', referralId });
    });
    
    // Check for suspicious referral patterns (async, don't block response)
    try {
      const service = new SuspiciousBehaviorService(db);
      // Check timing - how fast did user reach 50 points?
      await service.checkReferralPatterns(referredUserId, {
        referrerId,
        referralId,
        pointsReached: referredUserPoints
      });
    } catch (detectionError) {
      logger.error('❌ Error in referral pattern detection (non-blocking):', detectionError);
    }
    
    // Update referralPairs to mark bonus as awarded (async, don't block response)
    try {
      const referrerPhoneHash = hashPhoneNumber(referrerUserData?.phone);
      const referredPhoneHash = hashPhoneNumber(referredUserData?.phone);
      if (referrerPhoneHash && referredPhoneHash) {
        const pairId = `${referrerPhoneHash}_${referredPhoneHash}`;
        await db.collection('referralPairs').doc(pairId).update({
          bonusAwarded: true,
          bonusAwardedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        logger.info(`✅ Referral pair ${pairId.substring(0, 16)}... marked as bonus awarded`);
      }
    } catch (pairUpdateError) {
      logger.warn('⚠️ Failed to update referral pair (non-blocking):', pairUpdateError);
    }
    
    return {
      success: true,
      referrerNewPoints,
      referredNewPoints
    };
  } catch (error) {
    if (error.message === 'ALREADY_AWARDED') {
      return { success: false, error: 'ALREADY_AWARDED' };
    }
    logger.error('❌ Error in awardReferralPoints:', error);
    return { success: false, error: error.message || 'Unknown error' };
  }
}

/**
 * POST /referrals/award-check
 * 
 * Called by the iOS app when a user's points cross the 50-point threshold.
 * Checks if the calling user is part of a pending referral and awards +50 bonus
 * points to BOTH the referrer and the referred user.
 * 
 * Also sends push notifications to both users.
 * 
 * Returns:
 *   - { status: 'awarded', referralId, referrerBonus, referredBonus } on success
 *   - { status: 'already_awarded', referralId } if already processed
 *   - { status: 'not_eligible', reason } if not eligible
 */
app.post('/referrals/award-check', requireFirebaseAuth, generalPerUserLimiter, generalPerIpLimiter, async (req, res) => {
  try {
    const authenticatedUid = req.auth.uid;
    
    const db = admin.firestore();
    
    // Check if this is an admin-initiated check for another user
    const targetUserId = req.body.targetUserId;
    let uid = authenticatedUid; // Default to authenticated user
    
    if (targetUserId && targetUserId !== authenticatedUid) {
      // Admin is checking another user - verify admin status
      const adminUserDoc = await db.collection('users').doc(authenticatedUid).get();
      if (!adminUserDoc.exists) {
        return res.status(403).json({ error: 'Only admins can check other users' });
      }
      const adminUserData = adminUserDoc.data();
      if (!adminUserData || !adminUserData.isAdmin) {
        return res.status(403).json({ error: 'Only admins can check other users' });
      }
      uid = targetUserId; // Use target user for referral check
      logger.info(`🔧 Admin ${authenticatedUid} checking referral for user ${uid}`);
    }

    logger.info(`🎯 Referral award-check for user: ${uid}`);

    const REFERRAL_BONUS = 50;

    // Find the referral document where this user is the referred person
    const referralSnap = await db.collection('referrals')
      .where('referredUserId', '==', uid)
      .limit(1)
      .get();

    if (referralSnap.empty) {
      logger.info(`ℹ️ User ${uid} has no referral relationship`);
      return res.json({ status: 'not_eligible', reason: 'no_referral' });
    }

    const referralDoc = referralSnap.docs[0];
    const referralId = referralDoc.id;
    const referralData = referralDoc.data();
    const referrerId = referralData.referrerUserId;

    logger.info(`📋 Found referral ${referralId}: referrer=${referrerId}, status=${referralData.status}`);

    // Check if already awarded
    if (referralData.status === 'awarded') {
      logger.info(`ℹ️ Referral ${referralId} already awarded`);
      return res.json({ status: 'already_awarded', referralId });
    }

    // Tombstoned referral (referrer or referred deleted); do not award
    if (referralData.status === 'cancelled' || !referrerId) {
      logger.info(`ℹ️ Referral ${referralId} cancelled or referrer deleted, skipping award`);
      return res.json({ status: 'not_eligible', reason: 'referral_cancelled' });
    }

    // Get the referred user's current points
    const referredUserRef = db.collection('users').doc(uid);
    const referredUserDoc = await referredUserRef.get();
    
    if (!referredUserDoc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    const referredUserData = referredUserDoc.data();
    const referredUserPoints = referredUserData.points || 0;

    // Check if referred user has reached the 50-point threshold
    if (referredUserPoints < 50) {
      logger.info(`ℹ️ User ${uid} has ${referredUserPoints} points, needs 50 for referral bonus`);
      return res.json({ 
        status: 'not_eligible', 
        reason: 'threshold_not_met',
        currentPoints: referredUserPoints,
        requiredPoints: 50
      });
    }

    // Use the shared helper function to award points
    const awardResult = await awardReferralPoints(db, referralId, referrerId, uid);
    
    if (!awardResult.success) {
      if (awardResult.error === 'ALREADY_AWARDED') {
        return res.json({ status: 'already_awarded', referralId });
      }
      if (awardResult.error === 'THRESHOLD_NOT_MET') {
        return res.json({ 
          status: 'not_eligible', 
          reason: 'threshold_not_met',
          currentPoints: awardResult.currentPoints,
          requiredPoints: 50
        });
      }
      return res.status(500).json({ error: awardResult.error || 'Failed to award points' });
    }

    return res.json({
      status: 'awarded',
      referralId,
      referrerBonus: awardResult.referrerNewPoints !== null ? REFERRAL_BONUS : 0,
      referredBonus: REFERRAL_BONUS,
      referrerNewPoints: awardResult.referrerNewPoints,
      referredNewPoints: awardResult.referredNewPoints
    });

  } catch (error) {
    if (error.message === 'ALREADY_AWARDED') {
      return res.json({ status: 'already_awarded' });
    }
    logger.error('❌ Error in /referrals/award-check:', error);
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

// Helper function to hash phone numbers for abuse prevention
// Uses SHA-256 to create a non-reversible hash that persists across account deletions
function hashPhoneNumber(phone) {
  const crypto = require('crypto');
  // Normalize: remove all non-digit characters
  const normalized = (phone || '').replace(/\D/g, '');
  if (!normalized) return null;
  return crypto.createHash('sha256').update(normalized).digest('hex');
}

// Normalize phone for bannedNumbers lookups: +1XXXXXXXXXX (matches iOS format)
function normalizePhoneForBannedNumbers(phone) {
  const digits = (phone || '').replace(/\D/g, '');
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

// Enhanced combo variety system to encourage exploration
const comboInsights = []; // Track combo patterns for insights, not restrictions
const MAX_INSIGHTS = 100;
const userComboPreferences = new Map(); // Track user preferences for personalization

// Helper function to safely add insights with size limit enforcement
function addComboInsight(insight) {
  comboInsights.push(insight);
  if (comboInsights.length > MAX_INSIGHTS) {
    comboInsights.shift(); // Remove oldest entry to maintain size limit
  }
}

// Size limit for user combo preferences Map (LRU eviction)
const MAX_USER_PREFERENCES = 1000;
function setUserComboPreference(userId, preference) {
  // If at capacity, remove oldest entry (first key in insertion order)
  if (userComboPreferences.size >= MAX_USER_PREFERENCES && !userComboPreferences.has(userId)) {
    const firstKey = userComboPreferences.keys().next().value;
    userComboPreferences.delete(firstKey);
  }
  userComboPreferences.set(userId, preference);
}

// Health check endpoint (basic - fast response)
app.get('/', async (req, res) => {
  const redisHealth = await checkRedisHealth();
  const firebaseHealth = await checkFirebaseHealth();
  
  res.json({ 
    status: 'Server is running!', 
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    server: 'BACKEND server.js with gpt-4o-mini',
    services: {
      firebase: {
        configured: !!admin.apps.length,
        connected: firebaseHealth.connected
      },
      redis: {
        configured: !!redisClient,
        connected: redisHealth.connected,
        status: redisHealth.status
      },
      openai: {
        configured: !!process.env.OPENAI_API_KEY
      },
      sentry: {
        configured: !!Sentry
      }
    }
  });
});

// Detailed health check endpoint (for monitoring services)
app.get('/health/detailed', async (req, res) => {
  const startTime = Date.now();
  const redisHealth = await checkRedisHealth();
  const firebaseHealth = await checkFirebaseHealth();
  const responseTime = Date.now() - startTime;
  
  const overallStatus = (
    firebaseHealth.connected && 
    (redisHealth.connected || !redisClient) && 
    !!process.env.OPENAI_API_KEY
  ) ? 'healthy' : 'degraded';
  
  const statusCode = overallStatus === 'healthy' ? 200 : 503;
  
  res.status(statusCode).json({
    status: overallStatus,
    timestamp: new Date().toISOString(),
    responseTimeMs: responseTime,
    environment: process.env.NODE_ENV || 'development',
    services: {
      firebase: {
        configured: !!admin.apps.length,
        connected: firebaseHealth.connected,
        status: firebaseHealth.status,
        error: firebaseHealth.error || null
      },
      redis: {
        configured: !!redisClient,
        connected: redisHealth.connected,
        status: redisHealth.status,
        error: redisHealth.error || null
      },
      openai: {
        configured: !!process.env.OPENAI_API_KEY
      },
      sentry: {
        configured: !!Sentry
      }
    },
    uptime: process.uptime(),
    memory: {
      used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
      total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
      rss: Math.round(process.memoryUsage().rss / 1024 / 1024)
    }
  });
});

// Status endpoint for uptime monitoring (fast, simple)
app.get('/status', async (req, res) => {
  const redisHealth = await checkRedisHealth();
  const firebaseHealth = await checkFirebaseHealth();
  
  const isHealthy = (
    firebaseHealth.connected && 
    (redisHealth.connected || !redisClient) && 
    !!process.env.OPENAI_API_KEY
  );
  
  res.status(isHealthy ? 200 : 503).json({
    status: isHealthy ? 'ok' : 'degraded',
    timestamp: new Date().toISOString()
  });
});

app.get('/metrics', async (req, res) => {
  const redisHealth = await checkRedisHealth();
  const uptime = process.uptime();
  
  res.json({
    timestamp: new Date().toISOString(),
    uptime: {
      seconds: Math.floor(uptime),
      formatted: `${Math.floor(uptime / 3600)}h ${Math.floor((uptime % 3600) / 60)}m ${Math.floor(uptime % 60)}s`
    },
    requests: {
      total: metrics.requests,
      errors: metrics.errors,
      rateLimitHits: metrics.rateLimitHits,
      perSecond: metrics.requests / uptime
    },
    services: {
      redis: {
        configured: !!redisClient,
        connected: redisHealth.connected,
        status: redisHealth.status
      },
      firebase: {
        configured: !!admin.apps.length
      },
      openai: {
        configured: !!process.env.OPENAI_API_KEY
      },
      sentry: {
        configured: !!Sentry
      }
    },
    memory: {
      used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
      total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
      rss: Math.round(process.memoryUsage().rss / 1024 / 1024)
    }
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
    logger.error('❌ Error in /app-version endpoint:', error);
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
const comboPerUserLimiter = createRateLimiter({
  keyFn: (req) => req.auth?.uid,
  windowMs: 60_000,
  max: parseInt(process.env.COMBO_UID_PER_MIN || '15', 10),
  errorCode: 'COMBO_RATE_LIMITED'
});
const comboPerIpLimiter = createRateLimiter({
  keyFn: (req) => getClientIp(req),
  windowMs: 60_000,
  max: parseInt(process.env.COMBO_IP_PER_MIN || '30', 10),
  errorCode: 'COMBO_RATE_LIMITED'
});

const receiptAnalyzePerUserLimiter = createRateLimiter({
  keyFn: (req) => req.auth?.uid,
  windowMs: 60_000,
  max: parseInt(process.env.RECEIPT_ANALYZE_UID_PER_MIN || '6', 10),
  errorCode: 'RECEIPT_RATE_LIMITED'
});

const receiptAnalyzePerIpLimiter = createRateLimiter({
  keyFn: (req) => getClientIp(req),
  windowMs: 60_000,
  max: parseInt(process.env.RECEIPT_ANALYZE_IP_PER_MIN || '20', 10),
  errorCode: 'RECEIPT_RATE_LIMITED'
});

const submitReceiptLimiter = createRateLimiter({
  keyFn: (req) => getClientIp(req),
  windowMs: 60 * 1000,
  max: 10,
  errorCode: 'RECEIPT_RATE_LIMITED'
});

app.post('/generate-combo', requireFirebaseAuth, comboPerUserLimiter, comboPerIpLimiter, validate(comboSchema), async (req, res) => {
  try {
    logger.info('🤖 Received personalized combo request');
    logger.info('📥 Request body:', JSON.stringify(req.body, null, 2));
    
    // Enforce a daily quota to prevent runaway OpenAI spend.
    if (admin.apps.length) {
      const db = admin.firestore();
      const quota = await enforceDailyQuota({
        db,
        uid: req.auth.uid,
        endpointKey: 'generate-combo',
        limit: process.env.COMBO_DAILY_LIMIT || 40
      });
      if (!quota.allowed) {
        return res.status(429).json({
          errorCode: 'DAILY_LIMIT_REACHED',
          error: 'Daily limit reached. Please try again tomorrow.',
          dayKey: quota.dayKey,
          limit: quota.limit
        });
      }
    }

    const { userName, dietaryPreferences, menuItems, previousRecommendations } = req.body;
    // Validation middleware ensures userName is present and valid

    // Normalize dietary preferences so downstream logic always has a safe object
    const normalizedDietaryPreferences = {
      likesSpicyFood: false,
      dislikesSpicyFood: false,
      hasPeanutAllergy: false,
      isVegetarian: false,
      hasLactoseIntolerance: false,
      doesntEatPork: false,
      tastePreferences: '',
      hasCompletedPreferences: false,
      ...(dietaryPreferences || {})
    };
    
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
          logger.info(`🔄 Skipping duplicate: ${item.id} (${item.price})`);
        }
      });
      
      logger.info(`✅ Deduplicated ${items.length} items to ${cleanedItems.length} unique items`);
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
          logger.info(`🍋 Categorized as Lemonade/Soda: ${item.id}`);
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
        logger.info(`✅ Categorized: ${item.id} -> ${category}`);
      });
      
      return categorizedItems;
    }
    
    // If no menu items provided, try to fetch from Firebase
    if (!allMenuItems || allMenuItems.length === 0) {
      logger.info('🔍 No menu items in request, trying to fetch from Firestore...');
      
      if (admin.apps.length) {
        try {
          const db = admin.firestore();
          
          // Get all menu categories
          const categoriesSnapshot = await db.collection('menu').get();
          
          for (const categoryDoc of categoriesSnapshot.docs) {
            const categoryId = categoryDoc.id;
            logger.info(`🔍 Processing category: ${categoryId}`);
            
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
                logger.info(`✅ Added item: ${menuItem.id} (${categoryId})`);
              } catch (error) {
                logger.error(`❌ Error processing item ${itemDoc.id} in category ${categoryId}:`, error);
              }
            }
          }
          
          logger.info(`✅ Successfully fetched ${allMenuItems.length} menu items from Firestore`);
        } catch (error) {
          logger.error('❌ Error fetching from Firestore:', error);
          logger.info('🔄 Firebase fetch failed, will use menu items from request if available');
        }
      } else {
        logger.info('⚠️ Firebase not configured, will use menu items from request if available');
        
        // Categorize items from request if they don't have categories
        if (allMenuItems.length > 0) {
          logger.info('🔍 Categorizing menu items from request...');
          allMenuItems = categorizeFromDescriptions(allMenuItems);
        }
      }
    }
    
    // If still no menu items, return error
    if (!allMenuItems || allMenuItems.length === 0) {
      logger.error('❌ No menu items available');
      return res.status(500).json({ 
        error: 'No menu items available',
        details: 'Unable to fetch menu from Firebase or request'
      });
    }
    
    // Clean and deduplicate menu items
    logger.info(`🔍 Cleaning and deduplicating ${allMenuItems.length} menu items...`);
    allMenuItems = deduplicateAndCleanMenuItems(allMenuItems);
    
    // Categorize items if they don't have categories
    if (allMenuItems.length > 0 && !allMenuItems[0].category) {
      logger.info('🔍 Categorizing menu items...');
      allMenuItems = categorizeFromDescriptions(allMenuItems);
    }
    
    logger.info(`🔍 Final menu items count: ${allMenuItems.length}`);
    logger.info(`🔍 Menu items:`, allMenuItems.map(item => `${item.id} (${item.category})`));
    logger.info(`🔍 Dietary preferences:`, dietaryPreferences);
    

    
    // Create dietary restrictions string
    const restrictions = [];
    if (normalizedDietaryPreferences.hasPeanutAllergy) restrictions.push('peanut allergy');
    if (normalizedDietaryPreferences.isVegetarian) restrictions.push('vegetarian');
    if (normalizedDietaryPreferences.hasLactoseIntolerance) restrictions.push('lactose intolerant');
    if (normalizedDietaryPreferences.doesntEatPork) restrictions.push('no pork');
    if (normalizedDietaryPreferences.dislikesSpicyFood) restrictions.push('no spicy food');
    
    const restrictionsText = restrictions.length > 0 ? 
      `Dietary restrictions: ${restrictions.join(', ')}. ` : '';
    
    const spicePreference = normalizedDietaryPreferences.likesSpicyFood ? 
      'The customer enjoys spicy food. ' : '';
    
    const tastePreference = normalizedDietaryPreferences.tastePreferences && normalizedDietaryPreferences.tastePreferences.trim() !== '' ? 
      `TASTE PREFERENCES (HIGH PRIORITY): ${normalizedDietaryPreferences.tastePreferences}. ` : '';

    const preferencesStatusText = normalizedDietaryPreferences.hasCompletedPreferences
      ? 'The customer has completed their dietary preferences. '
      : 'The customer has not provided detailed dietary preferences yet, so do not assume allergy information. ';
    
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
    logger.info(`🥤 Selected Drink Type: ${selectedDrinkType} - ${preferenceReason}`);
    
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
${preferencesStatusText}${restrictionsText}${spicePreference}${tastePreference}

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

    logger.info('🤖 Sending request to OpenAI...');
    logger.info('🔍 Exploration Strategy:', currentStrategy);
    logger.info('🔍 Variety Guideline:', varietyGuideline);
    logger.info('🥤 Selected Drink Type:', selectedDrinkType);
    logger.info('🥗 Selected Appetizer/Soup Type:', randomAppetizerSoup);
    
    const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    const completion = await openaiWithTimeout(openai, {
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

    logger.info('✅ Received response from OpenAI');
    
    const aiResponse = completion.choices[0].message.content;
    logger.info('🤖 AI Response:', aiResponse);
    
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
      
      logger.info('✅ Successfully parsed and validated AI response');

      // Enforce variety against recent combos (server-side)
      const recentCombos = Array.isArray(previousRecommendations) ? previousRecommendations.slice(-3) : [];
      if (recentCombos.length > 0) {
        const normalizeComboKey = (items) => items
          .map(item => (item.id || '').toLowerCase().trim())
          .filter(id => id.length > 0)
          .sort()
          .join('|');

        const previousKeys = new Set(recentCombos.map(combo => normalizeComboKey(combo.items || [])));
        const currentKey = normalizeComboKey(parsedResponse.items);

        if (previousKeys.has(currentKey)) {
          logger.info('🔁 Detected duplicate combo vs recent recommendations, attempting replacement');
          const previousIds = new Set(
            recentCombos
              .flatMap(combo => (combo.items || []).map(item => (item.id || '').toLowerCase().trim()))
              .filter(id => id.length > 0)
          );

          const duplicateIndex = parsedResponse.items.findIndex(item =>
            previousIds.has((item.id || '').toLowerCase().trim())
          );

          if (duplicateIndex !== -1) {
            const currentItem = parsedResponse.items[duplicateIndex];
            let candidates = allMenuItems.filter(mi => !previousIds.has((mi.id || '').toLowerCase().trim()));

            if (currentItem.category) {
              const targetCategory = currentItem.category.toLowerCase();
              const categoryCandidates = candidates.filter(mi => (mi.category || '').toLowerCase() === targetCategory);
              if (categoryCandidates.length > 0) {
                candidates = categoryCandidates;
              }
            }

            if (candidates.length > 0) {
              const replacement = candidates[Math.floor(Math.random() * candidates.length)];
              parsedResponse.items[duplicateIndex] = {
                id: replacement.id,
                category: replacement.category || currentItem.category || 'Other'
              };
            }
          }

          const updatedKey = normalizeComboKey(parsedResponse.items);
          if (previousKeys.has(updatedKey)) {
            logger.info('⚠️ Duplicate combo still present after replacement attempt');
          } else {
            logger.info('✅ Duplicate combo resolved with replacement item');
          }
        }
      }
      
      // 🛡️ PLAN B: Dietary Restriction Safety Validation System
      logger.info('🛡️ Running dietary restriction safety validation...');
      const validationResult = validateDietaryRestrictions(
        parsedResponse.items, 
        normalizedDietaryPreferences, 
        allMenuItems
      );
      
      // Update the combo with validated items
      parsedResponse.items = validationResult.items;
      parsedResponse.totalPrice = validationResult.totalPrice;
      
      // Add warning if items were removed
      if (validationResult.wasModified) {
        logger.info(`⚠️ AI DIETARY VIOLATION CAUGHT: Removed ${validationResult.removedCount} item(s)`);
        logger.info(`   Removed items: ${validationResult.removedItems.map(item => item.id).join(', ')}`);
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
      logger.error('❌ Error parsing AI response:', parseError);
      logger.error('Raw AI response:', aiResponse);
      
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
    logger.error('❌ Error in generate-combo:', error);
    res.status(500).json({ 
      error: 'Failed to generate combo',
      details: error.message 
    });
  }
});

// Check if OpenAI API key is configured
if (!process.env.OPENAI_API_KEY) {
  logger.error('❌ OPENAI_API_KEY environment variable is not set!');
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

  // Receipt daily limit (successful point-awarding scans)
  const RECEIPT_DAILY_SUCCESS_LIMIT = 2;
  const RECEIPT_DAILY_COUNTERS_COLLECTION = 'receiptDailyCounters';

  // Receipt scan rate limiting helpers
  async function checkReceiptScanRateLimit(userId, db) {
    if (!userId) return { allowed: true }; // No user = no rate limit (analyze-receipt endpoint)
    
    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) return { allowed: true };
    
    const userData = userDoc.data() || {};
    
    // Admin users bypass rate limiting AND clear any existing lockout
    if (userData.isAdmin === true) {
      // Clear any existing lockout state for admins
      if (userData.receiptScanLockoutUntil || userData.receiptScanLockoutCount) {
        await userRef.update({
          receiptScanLockoutUntil: admin.firestore.FieldValue.delete(),
          receiptScanLockoutCount: admin.firestore.FieldValue.delete()
        });
        logger.info(`✅ Cleared receipt scan lockout for admin user ${userId}`);
      }
      return { allowed: true };
    }
    
    // Check if user is currently locked out
    const lockoutUntil = userData.receiptScanLockoutUntil;
    if (lockoutUntil) {
      const lockoutTime = lockoutUntil.toDate();
      const now = new Date();
      if (lockoutTime > now) {
        return { allowed: false, reason: 'locked_out' };
      }
      // Lockout expired, clear it
      await userRef.update({
        receiptScanLockoutUntil: admin.firestore.FieldValue.delete()
      });
    }
    
    return { allowed: true };
  }

  function normalizeUserTimeZone(tzRaw) {
    const fallback = 'UTC';
    if (!tzRaw || typeof tzRaw !== 'string') return fallback;
    const trimmed = tzRaw.trim();
    if (!trimmed) return fallback;

    const dt = DateTime.now().setZone(trimmed);
    if (!dt.isValid) return fallback;
    return trimmed;
  }

  function getUserLocalDayKeys(timeZone) {
    const now = DateTime.now().setZone(timeZone);
    const dayKey = now.toFormat('yyyy-LL-dd');
    const yesterdayKey = now.minus({ days: 1 }).toFormat('yyyy-LL-dd');
    return { dayKey, yesterdayKey };
  }

  function calculateSuspiciousRiskScore(severity, evidence) {
    let baseScore = 0;
    switch (severity) {
      case 'critical': baseScore = 90; break;
      case 'high': baseScore = 70; break;
      case 'medium': baseScore = 50; break;
      case 'low': baseScore = 30; break;
      default: baseScore = 40;
    }

    if (evidence) {
      if (evidence.count && evidence.count > 5) baseScore += 10;
      if (evidence.rejectionRate && evidence.rejectionRate > 0.5) baseScore += 15;
      if (evidence.associatedUserIds && evidence.associatedUserIds.length > 2) baseScore += 10;
    }

    return Math.min(100, baseScore);
  }

  async function checkDailyReceiptSuccessLimit(userId, db, timeZone) {
    if (!userId) return { allowed: true, timeZone, dayKey: null };

    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    if (userDoc.exists) {
      const userData = userDoc.data() || {};
      if (userData.isAdmin === true) {
        return { allowed: true, timeZone, dayKey: null };
      }
    }

    const { dayKey } = getUserLocalDayKeys(timeZone);
    const counterRef = db
      .collection(RECEIPT_DAILY_COUNTERS_COLLECTION)
      .doc(`${userId}_${dayKey}`);

    const counterDoc = await counterRef.get();
    const count = counterDoc.exists ? (counterDoc.data()?.count || 0) : 0;

    return {
      allowed: count < RECEIPT_DAILY_SUCCESS_LIMIT,
      timeZone,
      dayKey,
      count,
      limit: RECEIPT_DAILY_SUCCESS_LIMIT
    };
  }

  async function logReceiptScanAttempt(userId, success, failureReason, db, ipAddress = null) {
    if (!userId) return; // Don't log for analyze-receipt (no user)
    
    const attemptsRef = db.collection('receiptScanAttempts');
    await attemptsRef.add({
      userId,
      success,
      failureReason: success ? null : failureReason,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ipAddress
    });
    
    // Clean up old attempts (older than 7 days) to keep collection size manageable
    // This runs asynchronously and doesn't block the response
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    attemptsRef.where('timestamp', '<', admin.firestore.Timestamp.fromDate(sevenDaysAgo))
      .limit(100)
      .get()
      .then(snapshot => {
        const batch = db.batch();
        snapshot.docs.forEach(doc => batch.delete(doc.ref));
        return batch.commit();
      })
      .catch(err => logger.error('Error cleaning up old scan attempts:', err));
  }

  function getProgressiveLockoutDuration(lockoutCount) {
    // Progressive lockout durations (in milliseconds)
    switch (lockoutCount) {
      case 0:
      case 1:
        return 1 * 60 * 60 * 1000; // 1 hour
      case 2:
        return 6 * 60 * 60 * 1000; // 6 hours
      case 3:
        return 24 * 60 * 60 * 1000; // 24 hours
      default:
        return 48 * 60 * 60 * 1000; // 48 hours
    }
  }

  async function applyReceiptScanLockout(userId, db) {
    if (!userId) return; // No user = no lockout
    
    // Check if user is admin - admins are exempt from lockouts
    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) return; // User doesn't exist, skip lockout
    
    const userData = userDoc.data() || {};
    if (userData.isAdmin === true) {
      return; // Admins never get locked out
    }
    
    const attemptsRef = db.collection('receiptScanAttempts');
    
    // Count failed attempts in last 24 hours
    const twentyFourHoursAgo = new Date();
    twentyFourHoursAgo.setHours(twentyFourHoursAgo.getHours() - 24);
    
    const failedAttempts = await attemptsRef
      .where('userId', '==', userId)
      .where('success', '==', false)
      .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(twentyFourHoursAgo))
      .get();
    
    if (failedAttempts.size >= 8) {
      // Get current lockout count (reuse userData from earlier fetch)
      const currentLockoutCount = userData.receiptScanLockoutCount || 0;
      
      // Calculate lockout duration
      const lockoutDuration = getProgressiveLockoutDuration(currentLockoutCount);
      const lockoutUntil = new Date(Date.now() + lockoutDuration);
      
      // Apply lockout
      await userRef.update({
        receiptScanLockoutUntil: admin.firestore.Timestamp.fromDate(lockoutUntil),
        receiptScanLockoutCount: currentLockoutCount + 1
      });
      
      logger.info(`🔒 Applied receipt scan lockout for user ${userId}: ${currentLockoutCount + 1} lockout(s), until ${lockoutUntil.toISOString()}`);
    }
  }

  // Helper to log failure and check for lockout
  async function logFailureAndCheckLockout(userId, failureReason, db, ipAddress = null) {
    if (!userId) return; // No user = no logging
    await logReceiptScanAttempt(userId, false, failureReason, db, ipAddress);
    await applyReceiptScanLockout(userId, db);
  }

  app.post('/analyze-receipt', requireFirebaseAuth, receiptAnalyzePerUserLimiter, receiptAnalyzePerIpLimiter, upload.single('image'), async (req, res) => {
    try {
      logger.info('📥 Received receipt analysis request');
      
      if (!req.file) {
        logger.info('❌ No image file received');
        return sendError(res, 400, "NO_IMAGE", "No image file provided");
      }
      
      logger.info('📁 Image file received:', req.file.originalname, 'Size:', req.file.size);
      
      const imagePath = req.file.path;
      const imageData = await fsPromises.readFile(imagePath, { encoding: 'base64' });
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

      logger.info('🤖 Sending request to OpenAI for FIRST validation...');
      logger.info('📊 API Call 1 - Starting at:', new Date().toISOString());
      
      // First OpenAI call (with timeout)
      const response1 = await openaiWithTimeout(openai, {
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

      logger.info('✅ First OpenAI response received');
      logger.info('📊 API Call 1 - Completed at:', new Date().toISOString());
      
      logger.info('🤖 Sending request to OpenAI for SECOND validation...');
      logger.info('📊 API Call 2 - Starting at:', new Date().toISOString());
      
      // Second OpenAI call (with timeout)
      const response2 = await openaiWithTimeout(openai, {
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

      logger.info('✅ Second OpenAI response received');
      logger.info('📊 API Call 2 - Completed at:', new Date().toISOString());
      
      // Clean up the uploaded file
      await fsPromises.unlink(imagePath).catch(err => logger.error('Failed to delete file:', err));

      // Parse first response
      const text1 = response1.choices[0].message.content;
      logger.info('📝 Raw OpenAI response 1:', text1);
      
      const jsonMatch1 = text1.match(/\{[\s\S]*\}/);
      if (!jsonMatch1) {
        logger.info('❌ Could not extract JSON from first response');
        return sendError(res, 422, "AI_JSON_EXTRACT_FAILED", "Could not extract JSON from first response", { raw: text1 });
      }
      
      const data1 = JSON.parse(jsonMatch1[0]);
      logger.info('✅ Parsed JSON data 1:', data1);
      
      // Parse second response
      const text2 = response2.choices[0].message.content;
      logger.info('📝 Raw OpenAI response 2:', text2);
      
      const jsonMatch2 = text2.match(/\{[\s\S]*\}/);
      if (!jsonMatch2) {
        logger.info('❌ Could not extract JSON from second response');
        return sendError(res, 422, "AI_JSON_EXTRACT_FAILED", "Could not extract JSON from second response", { raw: text2 });
      }
      
      const data2 = JSON.parse(jsonMatch2[0]);
      logger.info('✅ Parsed JSON data 2:', data2);
      
      // Check if either response contains an error
      if (data1.error) {
        logger.info('❌ First validation failed:', data1.error);
        return sendError(res, 400, "AI_VALIDATION_FAILED", data1.error);
      }
      
      if (data2.error) {
        logger.info('❌ Second validation failed:', data2.error);
        return sendError(res, 400, "AI_VALIDATION_FAILED", data2.error);
      }

      // Normalize both responses BEFORE comparing to reduce false mismatches
      // (e.g., "12-21" vs "12/21", whitespace, numeric string formatting).
      const normalizeOrderDate = (v) => {
        if (typeof v !== 'string') return v;
        const s = v.trim().replace(/-/g, '/');
        return s;
      };
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
      
      // Compare the two responses
      logger.info('🔍 COMPARING TWO VALIDATIONS:');
      logger.info('   Response 1 - Order Number:', norm1.orderNumber, 'Total:', norm1.orderTotal, 'Date:', norm1.orderDate, 'Time:', norm1.orderTime);
      logger.info('   Response 2 - Order Number:', norm2.orderNumber, 'Total:', norm2.orderTotal, 'Date:', norm2.orderDate, 'Time:', norm2.orderTime);
      
      // Check if responses match
      const responsesMatch = 
        norm1.orderNumber === norm2.orderNumber &&
        norm1.orderTotal === norm2.orderTotal &&
        norm1.tipAmount === norm2.tipAmount &&
        norm1.tipLineVisible === norm2.tipLineVisible &&
        norm1.orderDate === norm2.orderDate &&
        norm1.orderTime === norm2.orderTime;
      
      logger.info('🔍 COMPARISON DETAILS:');
      logger.info('   Order Number Match:', norm1.orderNumber === norm2.orderNumber, `(${norm1.orderNumber} vs ${norm2.orderNumber})`);
      logger.info('   Order Total Match:', norm1.orderTotal === norm2.orderTotal, `(${norm1.orderTotal} vs ${norm2.orderTotal})`);
      logger.info('   Order Date Match:', norm1.orderDate === norm2.orderDate, `(${norm1.orderDate} vs ${norm2.orderDate})`);
      logger.info('   Order Time Match:', norm1.orderTime === norm2.orderTime, `(${norm1.orderTime} vs ${norm2.orderTime})`);
      logger.info('   Overall Match:', responsesMatch);
      
      if (!responsesMatch) {
        logger.info('❌ VALIDATION MISMATCH - Responses do not match');
        logger.info('   This indicates unclear or ambiguous receipt data');
        return sendError(
          res,
          400,
          "DOUBLE_PARSE_MISMATCH",
          "Receipt data is unclear - the two validations returned different results. Please take a clearer photo of the receipt."
        );
      }
      
      logger.info('✅ VALIDATION MATCH - Both responses are identical');
      
      // Use the validated data (both are the same)
      const data = norm1;

      // Normalize date formatting to MM/DD (accept MM-DD from model/receipt)
      if (typeof data.orderDate === 'string') {
        data.orderDate = data.orderDate.trim().replace(/-/g, '/');
      }
      
      // Validate that we have the required fields
      if (!data.orderNumber || !data.orderTotal || !data.orderDate || !data.orderTime) {
        logger.info('❌ Missing required fields in receipt data');
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
        logger.info('❌ Receipt rejected due to obscured/tampered key fields or invalid order number source', {
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
      logger.info('🔍 Validating order number:', orderNumberStr);
      
      if (orderNumberStr.length > 3) {
        logger.info('❌ Order number too long:', orderNumberStr);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number format - must be 3 digits or less");
      }
      
      const orderNumber = parseInt(data.orderNumber);
      logger.info('🔍 Parsed order number:', orderNumber);
      
      if (isNaN(orderNumber)) {
        logger.info('❌ Order number is not a valid number:', data.orderNumber);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be a valid number");
      }
      
      if (orderNumber < 1) {
        logger.info('❌ Order number too small:', orderNumber);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be at least 1");
      }
      
      if (orderNumber > 400) {
        logger.info('❌ Order number too large (over 400):', orderNumber);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be 400 or less");
      }
      
      logger.info('✅ Order number validation passed:', orderNumber);
      
      // Validate date format (must be MM/DD; accept MM-DD but normalized above)
      const dateRegex = /^\d{2}\/\d{2}$/;
      if (!dateRegex.test(data.orderDate)) {
        logger.info('❌ Invalid date format:', data.orderDate);
        return sendError(res, 400, "DATE_FORMAT_INVALID", "Invalid date format - must be MM/DD (or MM-DD on receipt)");
      }
      
      // Validate time format (must be HH:MM)
      const timeRegex = /^\d{2}:\d{2}$/;
      if (!timeRegex.test(data.orderTime)) {
        logger.info('❌ Invalid time format:', data.orderTime);
        return sendError(res, 400, "TIME_FORMAT_INVALID", "Invalid time format - must be HH:MM");
      }
      
      // Validate time is reasonable (00:00 to 23:59)
      const [hours, minutes] = data.orderTime.split(':').map(Number);
      if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
        logger.info('❌ Invalid time values:', data.orderTime);
        return sendError(res, 400, "TIME_FORMAT_INVALID", "Invalid time - must be between 00:00 and 23:59");
      }
      
      logger.info('✅ Time validation passed:', data.orderTime);
      
      // Additional server-side validation to double-check extracted data
      logger.info('🔍 DOUBLE-CHECKING EXTRACTED DATA:');
      logger.info('   Order Number:', data.orderNumber);
      logger.info('   Order Total:', data.orderTotal);
      logger.info('   Order Date:', data.orderDate);
      logger.info('   Order Time:', data.orderTime);
      
      // Validate order total is a reasonable amount (between $1 and $500)
      const orderTotal = parseFloat(data.orderTotal);
      if (isNaN(orderTotal) || orderTotal < 1 || orderTotal > 500) {
        logger.info('❌ Order total validation failed:', data.orderTotal);
        return sendError(res, 400, "TOTAL_INVALID", "Invalid order total - must be a reasonable amount between $1 and $500");
      }
      
      // Validate date is reasonable (not in the future and not too far in the past)
      const [month, day] = data.orderDate.split('/').map(Number);
      const currentDate = new Date();
      const [h, m] = data.orderTime.split(':').map(Number);

      // Admin-only override for testing old receipts:
      // If the caller has explicitly enabled old-receipt testing on their user profile,
      // we relax the 48-hour window check (for this user only) but still enforce all other validations.
      //
      // NOTE: We key primarily off `oldReceiptTestingEnabled` to avoid false negatives if `isAdmin` is missing/stale.
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
              logger.info('⚠️ Old-receipt test mode active for user:', uid, 'isAdmin:', userData.isAdmin === true);
            }
          }
        }
      } catch (err) {
        logger.warn('⚠️ Failed to evaluate admin old-receipt test override:', err.message || err);
      }

      const receiptDateThisYear = new Date(currentDate.getFullYear(), month - 1, day, h, m, 0, 0);
      const receiptDatePrevYear = new Date(currentDate.getFullYear() - 1, month - 1, day, h, m, 0, 0);
      const hoursDiffThisYear = (currentDate - receiptDateThisYear) / (1000 * 60 * 60);
      const hoursDiffPrevYear = (currentDate - receiptDatePrevYear) / (1000 * 60 * 60);

      let receiptDate = receiptDateThisYear;
      let hoursDiff = hoursDiffThisYear;
      if (hoursDiffThisYear < 0) {
        // If old-receipt testing is enabled, interpret "future this year" as previous year
        // instead of rejecting with FUTURE_DATE (receipts omit year).
        if (allowOldReceiptForAdmin) {
          receiptDate = receiptDatePrevYear;
          hoursDiff = hoursDiffPrevYear;
          logger.info('⚠️ Old-receipt test mode: treating future-date receipt as previous year:', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiff);
        } else if (hoursDiffPrevYear >= 0 && hoursDiffPrevYear <= 48) {
          receiptDate = receiptDatePrevYear;
          hoursDiff = hoursDiffPrevYear;
          logger.info('🗓️ Year-boundary adjustment applied for receipt date:', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiff);
        } else {
          logger.info('❌ Receipt date appears to be in the future:', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiffThisYear);
          return sendError(res, 400, "FUTURE_DATE", "Invalid receipt date - receipt appears to be dated in the future");
        }
      }

      const daysDiff = hoursDiff / 24;
      if (allowOldReceiptForAdmin) {
        logger.info('⚠️ Old-receipt test mode daysDiff:', daysDiff);
      }

      if (hoursDiff > 48 && !allowOldReceiptForAdmin) {
        logger.info('❌ Receipt date too old:', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiff);
        return sendError(res, 400, "EXPIRED_48H", "Receipt expired - receipts must be scanned within 48 hours of purchase");
      }
      
      logger.info('✅ All validations passed - data integrity confirmed');
      
      // DUPLICATE DETECTION SYSTEM
      logger.info('🔍 CHECKING FOR DUPLICATE RECEIPTS...');
      
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
          const snapshot = await query.limit(1).get();
          if (!snapshot.empty) {
            logger.info('❌ DUPLICATE RECEIPT DETECTED');
            logger.info('   Matching criteria found in existing receipt');
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
        
        logger.info('✅ No duplicates found - receipt is unique');

        // Persist this validated receipt so future scans can be checked reliably
        try {
          await receiptsRef.add({
            orderNumber: String(data.orderNumber),
            orderDate: data.orderDate,
            orderTime: data.orderTime,
            orderTotal: orderTotal,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
          });
          logger.info('💾 Saved receipt to receipts collection for future duplicate checks');
        } catch (saveError) {
          logger.info('❌ Error saving receipt record:', saveError.message);
          // For safety, do NOT award points if we cannot persist the receipt
          return sendError(res, 500, "SERVER_SAVE_FAILED", "Server error while saving receipt - please try again with a clear photo");
        }
        
      } catch (duplicateError) {
        logger.info('❌ Error checking for duplicates:', duplicateError.message);
        // For safety, do NOT award points if we cannot verify duplicates
        return sendError(res, 500, "SERVER_DUPLICATE_CHECK_FAILED", "Server error while verifying receipt uniqueness - please try again with a clear photo");
      }
      
      res.json(data);
    } catch (err) {
      logger.error('❌ Error processing receipt:', err);
      return sendError(res, 500, "SERVER_ERROR", err.message || "Server error");
    }
  });

  // Receipt submit endpoint (server-authoritative points awarding)
  // This endpoint validates the receipt and awards points atomically on the server.
  // It does NOT rely on the client to update points, improving integrity.
  app.post('/submit-receipt', requireFirebaseAuth, submitReceiptLimiter, upload.single('image'), async (req, res) => {
    try {
      logger.info('📥 Received receipt SUBMISSION request');

      const uid = req.auth.uid;

      if (!req.file) {
        logger.info('❌ No image file received');
        return sendError(res, 400, "NO_IMAGE", "No image file provided");
      }

      logger.info('📁 Image file received:', req.file.originalname, 'Size:', req.file.size);

      const imagePath = req.file.path;
      const imageData = await fsPromises.readFile(imagePath, { encoding: 'base64' });
      const db = admin.firestore();
      const ipAddress = req.ip || req.headers['x-forwarded-for'] || null;

      // User-local timezone (for daily scan caps). If missing/invalid, fall back to UTC.
      const userTimeZone = normalizeUserTimeZone(req.headers['x-user-timezone']);
      const { dayKey: userLocalDayKey, yesterdayKey: userLocalYesterdayKey } = getUserLocalDayKeys(userTimeZone);
      
      // Extract device fingerprint if provided
      let deviceInfo = null;
      const fingerprintHeader = req.headers['x-device-fingerprint'];
      if (fingerprintHeader) {
        try {
          deviceInfo = JSON.parse(fingerprintHeader);
        } catch (e) {
          logger.warn('⚠️ Failed to parse device fingerprint:', e);
        }
      }
      
      // Record device fingerprint for multi-account detection (async, don't block)
      if (deviceInfo) {
        const service = new SuspiciousBehaviorService(db);
        service.recordDeviceFingerprint(uid, deviceInfo, ipAddress).catch(err => {
          logger.error('❌ Error recording device fingerprint (non-blocking):', err);
        });
      }

      // Check rate limit BEFORE making OpenAI API calls (cost savings)
      const rateLimitCheck = await checkReceiptScanRateLimit(uid, db);
      if (!rateLimitCheck.allowed) {
        logger.info(`🚫 Rate limit triggered for user ${uid}`);
        return sendError(res, 429, "RATE_LIMITED", "Too many failed scan attempts. Please wait a while and try again.");
      }

      // Enforce daily successful receipt scan cap BEFORE OpenAI calls (cost savings)
      const dailyLimitCheck = await checkDailyReceiptSuccessLimit(uid, db, userTimeZone);
      if (!dailyLimitCheck.allowed) {
        logger.info(`🚫 Daily receipt scan cap reached for user ${uid} (${dailyLimitCheck.count}/${dailyLimitCheck.limit}) day=${dailyLimitCheck.dayKey} tz=${dailyLimitCheck.timeZone}`);
        // Log this as a non-lockout failure for observability (do NOT apply progressive lockout)
        logReceiptScanAttempt(uid, false, "DAILY_LIMIT_REACHED", db, ipAddress).catch(() => {});
        return sendError(
          res,
          429,
          "DAILY_RECEIPT_LIMIT_REACHED",
          "You've hit your points limit for today. Come back tomorrow.",
          { day: dailyLimitCheck.dayKey, timeZone: dailyLimitCheck.timeZone, limit: dailyLimitCheck.limit }
        );
      }

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
- orderDate: The date in MM/DD format only (e.g. "12/25")
- orderTime: The time in HH:MM format only (e.g. "14:30"). This is always located to the right of the date on the receipt.
- subtotalAmount: The SUBTOTAL amount as a number (e.g. 15.95) or null if not visible.
- taxAmount: The TAX amount as a number (e.g. 1.60) or null if not visible.
- totalAmount: The TOTAL amount as a number (should match orderTotal) or null if not visible.
- tipAmount: The TIP/GRATUITY amount as a number (e.g. 4.81) or null if not visible.
- feeAmount: Any CONVENIENCE FEE, SERVICE FEE, DELIVERY FEE, or other additional fees as a number (e.g. 1.00) or null if not visible. Look for fees labeled as "Conv Fee", "Convenience Fee", "Service Fee", "Delivery Fee", or similar charges between tip and total.
- subtotalLineVisible: true only if the Subtotal line (label + digits) is clearly visible. Otherwise false.
- taxLineVisible: true only if the Tax line (label + digits) is clearly visible. Otherwise false.
- totalLineVisible: true only if the Total line (label + digits) is clearly visible. Otherwise false.
- tipLineVisible: true only if the Tip/Gratuity line (label + digits) is clearly visible. Otherwise false.
- feeLineVisible: true only if a fee line (Conv Fee, Convenience Fee, Service Fee, Delivery Fee, etc. with label + digits) is clearly visible. Otherwise false.

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
{"orderNumber": "...", "orderTotal": ..., "orderDate": "...", "orderTime": "...", "subtotalAmount": ..., "taxAmount": ..., "totalAmount": ..., "tipAmount": ..., "feeAmount": ..., "subtotalLineVisible": true/false, "taxLineVisible": true/false, "totalLineVisible": true/false, "tipLineVisible": true/false, "feeLineVisible": true/false, "totalVisibleAndClear": true/false, "orderNumberVisibleAndClear": true/false, "dateVisibleAndClear": true/false, "timeVisibleAndClear": true/false, "keyFieldsTampered": true/false, "tamperingReason": "...", "orderNumberInBlackBox": true/false, "orderNumberDirectlyUnderNashville": true/false, "paidOnlineReceipt": true/false, "orderNumberFromPaidOnlineSection": true/false} 
or {"error": "error message"}.
If a field is missing, use null.`;

      logger.info('🤖 Sending request to OpenAI for FIRST validation (submit-receipt)...');
      const response1 = await openaiWithTimeout(openai, {
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

      logger.info('🤖 Sending request to OpenAI for SECOND validation (submit-receipt)...');
      const response2 = await openaiWithTimeout(openai, {
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
      await fsPromises.unlink(imagePath).catch(err => logger.error('Failed to delete file:', err));

      const extractJson = (text) => {
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (!jsonMatch) return null;
        return JSON.parse(jsonMatch[0]);
      };

      const text1 = response1.choices[0].message.content;
      const text2 = response2.choices[0].message.content;
      const data1 = extractJson(text1);
      const data2 = extractJson(text2);
      
      if (!data1) {
        await logFailureAndCheckLockout(uid, "AI_JSON_EXTRACT_FAILED", db, ipAddress);
        return sendError(res, 422, "AI_JSON_EXTRACT_FAILED", "Could not extract JSON from first response", { raw: text1 });
      }
      if (!data2) {
        await logFailureAndCheckLockout(uid, "AI_JSON_EXTRACT_FAILED", db, ipAddress);
        return sendError(res, 422, "AI_JSON_EXTRACT_FAILED", "Could not extract JSON from second response", { raw: text2 });
      }

      if (data1.error) {
        await logFailureAndCheckLockout(uid, "AI_VALIDATION_FAILED", db, ipAddress);
        return sendError(res, 400, "AI_VALIDATION_FAILED", data1.error);
      }
      if (data2.error) {
        await logFailureAndCheckLockout(uid, "AI_VALIDATION_FAILED", db, ipAddress);
        return sendError(res, 400, "AI_VALIDATION_FAILED", data2.error);
      }

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
        orderDate: normalizeOrderDate(d.orderDate),
        orderTime: normalizeOrderTime(d.orderTime),
        subtotalAmount: normalizeMoney(d.subtotalAmount),
        taxAmount: normalizeMoney(d.taxAmount),
        totalAmount: normalizeMoney(d.totalAmount),
        tipAmount: normalizeMoney(d.tipAmount),
        feeAmount: normalizeMoney(d.feeAmount),
      });
      const norm1 = normalizeParsedReceipt(data1);
      const norm2 = normalizeParsedReceipt(data2);

      const responsesMatch =
        norm1.orderNumber === norm2.orderNumber &&
        norm1.orderTotal === norm2.orderTotal &&
        norm1.orderDate === norm2.orderDate &&
        norm1.orderTime === norm2.orderTime &&
        norm1.subtotalAmount === norm2.subtotalAmount &&
        norm1.taxAmount === norm2.taxAmount &&
        norm1.totalAmount === norm2.totalAmount &&
        norm1.tipAmount === norm2.tipAmount &&
        norm1.feeAmount === norm2.feeAmount &&
        norm1.subtotalLineVisible === norm2.subtotalLineVisible &&
        norm1.taxLineVisible === norm2.taxLineVisible &&
        norm1.totalLineVisible === norm2.totalLineVisible &&
        norm1.tipLineVisible === norm2.tipLineVisible &&
        norm1.feeLineVisible === norm2.feeLineVisible;

      if (!responsesMatch) {
        logger.info('⚠️ Double-parse mismatch details:', {
          orderNumber1: norm1.orderNumber,
          orderNumber2: norm2.orderNumber,
          orderTotal1: norm1.orderTotal,
          orderTotal2: norm2.orderTotal,
          tipAmount1: norm1.tipAmount,
          tipAmount2: norm2.tipAmount,
          feeAmount1: norm1.feeAmount,
          feeAmount2: norm2.feeAmount,
          subtotalAmount1: norm1.subtotalAmount,
          subtotalAmount2: norm2.subtotalAmount,
          taxAmount1: norm1.taxAmount,
          taxAmount2: norm2.taxAmount,
          totalAmount1: norm1.totalAmount,
          totalAmount2: norm2.totalAmount,
          subtotalLineVisible1: norm1.subtotalLineVisible,
          subtotalLineVisible2: norm2.subtotalLineVisible,
          taxLineVisible1: norm1.taxLineVisible,
          taxLineVisible2: norm2.taxLineVisible,
          totalLineVisible1: norm1.totalLineVisible,
          totalLineVisible2: norm2.totalLineVisible,
          tipLineVisible1: norm1.tipLineVisible,
          tipLineVisible2: norm2.tipLineVisible,
          feeLineVisible1: norm1.feeLineVisible,
          feeLineVisible2: norm2.feeLineVisible
        });
        await logFailureAndCheckLockout(uid, "DOUBLE_PARSE_MISMATCH", db, ipAddress);
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
        await logFailureAndCheckLockout(uid, "MISSING_FIELDS", db, ipAddress);
        return sendError(res, 400, "MISSING_FIELDS", "Could not extract all required fields from receipt");
      }

      // Require Subtotal/Tax/Total section evidence to prevent hallucinated totals.
      // If any of these are missing/unclear, fail closed and ask the user to rescan.
      if (
        data.subtotalLineVisible !== true ||
        data.taxLineVisible !== true ||
        data.totalLineVisible !== true ||
        data.subtotalAmount === null || data.subtotalAmount === undefined ||
        data.taxAmount === null || data.taxAmount === undefined ||
        data.totalAmount === null || data.totalAmount === undefined
      ) {
        logger.info('⚠️ Totals section not visible:', {
          subtotalLineVisible: data.subtotalLineVisible,
          taxLineVisible: data.taxLineVisible,
          totalLineVisible: data.totalLineVisible,
          subtotalAmount: data.subtotalAmount,
          taxAmount: data.taxAmount,
          totalAmount: data.totalAmount,
          orderTotal: data.orderTotal,
          tipAmount: data.tipAmount,
          feeAmount: data.feeAmount,
          tipLineVisible: data.tipLineVisible,
          feeLineVisible: data.feeLineVisible
        });
        await logFailureAndCheckLockout(uid, "TOTAL_SECTION_NOT_VISIBLE", db, ipAddress);
        return sendError(res, 400, "TOTAL_SECTION_NOT_VISIBLE", "Make sure all receipt text is visible and try again.");
      }

      // Consistency check: subtotal + tax must equal total (within a small rounding tolerance),
      // and totalAmount must match orderTotal. Account for tips and fees.
      const subtotal = parseFloat(data.subtotalAmount);
      const tax = parseFloat(data.taxAmount);
      const totalAmt = parseFloat(data.totalAmount);
      const orderTotalAmt = parseFloat(data.orderTotal);
      const tipAmount = data.tipAmount !== null && data.tipAmount !== undefined
        ? parseFloat(data.tipAmount)
        : null;
      const feeAmount = data.feeAmount !== null && data.feeAmount !== undefined
        ? parseFloat(data.feeAmount)
        : null;
      if ([subtotal, tax, totalAmt, orderTotalAmt].some(Number.isNaN)) {
        logger.info('⚠️ Totals invalid (NaN) from parsed values:', {
          subtotalRaw: data.subtotalAmount,
          taxRaw: data.taxAmount,
          totalRaw: data.totalAmount,
          orderTotalRaw: data.orderTotal,
          tipRaw: data.tipAmount,
          feeRaw: data.feeAmount
        });
        await logFailureAndCheckLockout(uid, "TOTAL_INVALID", db, ipAddress);
        return sendError(res, 400, "TOTAL_INVALID", "Could not validate totals — please rescan with Subtotal/Tax/Total visible.");
      }

      const tipIsUsable = data.tipLineVisible === true && tipAmount !== null && !Number.isNaN(tipAmount);
      const feeIsUsable = data.feeLineVisible === true && feeAmount !== null && !Number.isNaN(feeAmount);

      // Check multiple combinations to handle different receipt formats:
      // 1. subtotal + tax = total (no tip, no fee)
      const baseTotalMatches = Math.abs((subtotal + tax) - totalAmt) <= 0.02;
      // 2. subtotal + tax + tip = total (tip, no fee)
      const tipTotalMatches = tipIsUsable ? Math.abs((subtotal + tax + tipAmount) - totalAmt) <= 0.02 : false;
      // 3. subtotal + tax + fee = total (fee, no tip)
      const feeTotalMatches = feeIsUsable ? Math.abs((subtotal + tax + feeAmount) - totalAmt) <= 0.02 : false;
      // 4. subtotal + tax + tip + fee = total (both tip and fee)
      const tipAndFeeTotalMatches = (tipIsUsable && feeIsUsable) 
        ? Math.abs((subtotal + tax + tipAmount + feeAmount) - totalAmt) <= 0.02 
        : false;

      const totalMatchesOrderTotal = Math.abs(totalAmt - orderTotalAmt) <= 0.01;
      // Also allow totalAmount + tip to equal orderTotal (when "Total" is pre-tip and "Grand Total" is post-tip)
      const totalWithTipMatchesOrderTotal = tipIsUsable 
        ? Math.abs((totalAmt + tipAmount) - orderTotalAmt) <= 0.02 
        : false;
      // Also allow totalAmount + fee to equal orderTotal
      const totalWithFeeMatchesOrderTotal = feeIsUsable 
        ? Math.abs((totalAmt + feeAmount) - orderTotalAmt) <= 0.02 
        : false;
      // Also allow totalAmount + tip + fee to equal orderTotal
      const totalWithTipAndFeeMatchesOrderTotal = (tipIsUsable && feeIsUsable)
        ? Math.abs((totalAmt + tipAmount + feeAmount) - orderTotalAmt) <= 0.02
        : false;

      // Debug logging for totals reconciliation
      logger.info('💰 Totals reconciliation check:', {
        subtotal, tax, totalAmt, orderTotalAmt, tipAmount, feeAmount,
        baseTotalMatches, tipTotalMatches, feeTotalMatches, tipAndFeeTotalMatches,
        totalMatchesOrderTotal, totalWithTipMatchesOrderTotal, totalWithFeeMatchesOrderTotal, totalWithTipAndFeeMatchesOrderTotal
      });

      // At least one total calculation must match AND orderTotal must match
      const anyTotalMatches = baseTotalMatches || tipTotalMatches || feeTotalMatches || tipAndFeeTotalMatches;
      const orderTotalMatches = totalMatchesOrderTotal || totalWithTipMatchesOrderTotal || totalWithFeeMatchesOrderTotal || totalWithTipAndFeeMatchesOrderTotal;

      if (!anyTotalMatches || !orderTotalMatches) {
        logger.info('⚠️ Totals mismatch details:', {
          subtotal, tax, totalAmt, orderTotalAmt, tipAmount, feeAmount,
          subtotalLineVisible: data.subtotalLineVisible,
          taxLineVisible: data.taxLineVisible,
          totalLineVisible: data.totalLineVisible,
          tipLineVisible: data.tipLineVisible,
          feeLineVisible: data.feeLineVisible,
          baseTotalMatches, tipTotalMatches, feeTotalMatches, tipAndFeeTotalMatches,
          totalMatchesOrderTotal, totalWithTipMatchesOrderTotal, totalWithFeeMatchesOrderTotal, totalWithTipAndFeeMatchesOrderTotal
        });
        await logFailureAndCheckLockout(uid, "TOTAL_INCONSISTENT", db, ipAddress);
        return sendError(res, 400, "TOTAL_INCONSISTENT", "Totals don't reconcile — please rescan with Subtotal/Tax/Total clearly visible.");
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
            await logFailureAndCheckLockout(uid, "ORDER_NUMBER_SOURCE_INVALID", db, ipAddress);
            return sendError(res, 400, "ORDER_NUMBER_SOURCE_INVALID", "No valid order number found next to 'Order:' for paid online receipt");
          }
          await logFailureAndCheckLockout(uid, "ORDER_NUMBER_SOURCE_INVALID", db, ipAddress);
          return sendError(res, 400, "ORDER_NUMBER_SOURCE_INVALID", "No valid order number found under Nashville");
        }
        const failureReason = keyFieldsTampered ? "KEY_FIELDS_TAMPERED" : "KEY_FIELDS_INVALID";
        await logFailureAndCheckLockout(uid, failureReason, db, ipAddress);
        const msg = tamperingReason && typeof tamperingReason === 'string' && tamperingReason.trim().length > 0
          ? `Receipt invalid - ${tamperingReason}`
          : "Receipt invalid - key information is obscured or appears tampered with";
        return sendError(res, 400, "KEY_FIELDS_INVALID", msg, { tamperingReason: tamperingReason || null });
      }

      // Validate order number format (must be 3 digits or less and not exceed 400)
      const orderNumberStr = data.orderNumber.toString();
      if (orderNumberStr.length > 3) {
        await logFailureAndCheckLockout(uid, "ORDER_NUMBER_INVALID", db, ipAddress);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number format - must be 3 digits or less");
      }
      const orderNumber = parseInt(data.orderNumber);
      if (isNaN(orderNumber)) {
        await logFailureAndCheckLockout(uid, "ORDER_NUMBER_INVALID", db, ipAddress);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be a valid number");
      }
      if (orderNumber < 1) {
        await logFailureAndCheckLockout(uid, "ORDER_NUMBER_INVALID", db, ipAddress);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be at least 1");
      }
      if (orderNumber > 400) {
        await logFailureAndCheckLockout(uid, "ORDER_NUMBER_INVALID", db, ipAddress);
        return sendError(res, 400, "ORDER_NUMBER_INVALID", "Invalid order number - must be 400 or less");
      }

      // Validate date/time formats
      const dateRegex = /^\d{2}\/\d{2}$/;
      if (!dateRegex.test(data.orderDate)) {
        await logFailureAndCheckLockout(uid, "DATE_FORMAT_INVALID", db, ipAddress);
        return sendError(res, 400, "DATE_FORMAT_INVALID", "Invalid date format - must be MM/DD (or MM-DD on receipt)");
      }
      const timeRegex = /^\d{2}:\d{2}$/;
      if (!timeRegex.test(data.orderTime)) {
        await logFailureAndCheckLockout(uid, "TIME_FORMAT_INVALID", db, ipAddress);
        return sendError(res, 400, "TIME_FORMAT_INVALID", "Invalid time format - must be HH:MM");
      }
      const [hours, minutes] = data.orderTime.split(':').map(Number);
      if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
        await logFailureAndCheckLockout(uid, "TIME_FORMAT_INVALID", db, ipAddress);
        return sendError(res, 400, "TIME_FORMAT_INVALID", "Invalid time - must be between 00:00 and 23:59");
      }

      // Validate order total
      const orderTotal = parseFloat(data.orderTotal);
      if (isNaN(orderTotal) || orderTotal < 1 || orderTotal > 500) {
        await logFailureAndCheckLockout(uid, "TOTAL_INVALID", db, ipAddress);
        return sendError(res, 400, "TOTAL_INVALID", "Invalid order total - must be a reasonable amount between $1 and $500");
      }

      // 48-hour expiration logic (same as analyze endpoint, with admin override)
      const [month, day] = data.orderDate.split('/').map(Number);
      const currentDate = new Date();
      const [h, m] = data.orderTime.split(':').map(Number);

      // Read old-receipt test flag early so it can relax BOTH:
      // - the 48-hour window check
      // - the FUTURE_DATE guard (receipts omit year; common in early January when scanning December receipts)
      let allowOldReceiptForAdmin = false;
      try {
        const userDoc = await db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          const userData = userDoc.data() || {};
          if (userData.oldReceiptTestingEnabled === true) {
            allowOldReceiptForAdmin = true;
          }
        }
      } catch (err) {
        logger.warn('⚠️ Failed to evaluate admin old-receipt test override (submit-receipt):', err.message || err);
      }

      const receiptDateThisYear = new Date(currentDate.getFullYear(), month - 1, day, h, m, 0, 0);
      const receiptDatePrevYear = new Date(currentDate.getFullYear() - 1, month - 1, day, h, m, 0, 0);
      const hoursDiffThisYear = (currentDate - receiptDateThisYear) / (1000 * 60 * 60);
      const hoursDiffPrevYear = (currentDate - receiptDatePrevYear) / (1000 * 60 * 60);

      let receiptDate = receiptDateThisYear;
      let hoursDiff = hoursDiffThisYear;
      if (hoursDiffThisYear < 0) {
        if (allowOldReceiptForAdmin) {
          receiptDate = receiptDatePrevYear;
          hoursDiff = hoursDiffPrevYear;
          logger.info('⚠️ Old-receipt test mode: treating future-date receipt as previous year (submit-receipt):', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiff);
        } else if (hoursDiffPrevYear >= 0 && hoursDiffPrevYear <= 48) {
          receiptDate = receiptDatePrevYear;
          hoursDiff = hoursDiffPrevYear;
          logger.info('🗓️ Year-boundary adjustment applied (submit-receipt):', data.orderDate, data.orderTime, 'hoursDiff:', hoursDiff);
        } else {
          await logFailureAndCheckLockout(uid, "FUTURE_DATE", db, ipAddress);
          return sendError(res, 400, "FUTURE_DATE", "Invalid receipt date - receipt appears to be dated in the future");
        }
      }

      const daysDiff = hoursDiff / 24;
      if (allowOldReceiptForAdmin) {
        logger.info('⚠️ Old-receipt test mode active (submit-receipt):', uid, 'daysDiff:', daysDiff);
      }
      if (hoursDiff > 48 && !allowOldReceiptForAdmin) {
        await logFailureAndCheckLockout(uid, "EXPIRED_48H", db, ipAddress);
        return sendError(res, 400, "EXPIRED_48H", "Receipt expired - receipts must be scanned within 48 hours of purchase");
      }

      // Award points atomically with server-side duplicate prevention
      const pointsAwarded = Math.floor(orderTotal * 5);
      const userRef = db.collection('users').doc(uid);
      const receiptsRef = db.collection('receipts');
      const pointsTxId = `receipt_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const dailyCounterRef = db
        .collection(RECEIPT_DAILY_COUNTERS_COLLECTION)
        .doc(`${uid}_${userLocalDayKey}`);

      let newPointsBalance = null;
      let newLifetimePoints = null;
      let savedReceiptId = null;
      let currentPoints = 0; // Capture current points for referral check
      let shouldUpdateRiskScore = false;

      try {
        await db.runTransaction(async (tx) => {
          // Load user (needed for admin bypass + streak tracking)
          const userDoc = await tx.get(userRef);
          if (!userDoc.exists) {
            const err = new Error("USER_NOT_FOUND");
            err.code = "USER_NOT_FOUND";
            throw err;
          }
          const userData = userDoc.data() || {};
          const isAdminUser = userData.isAdmin === true;

          // Enforce daily successful scan cap atomically (prevents races between devices)
          // Admins bypass the daily cap (keeps behavior consistent with the pre-check).
          const dailyCounterDoc = await tx.get(dailyCounterRef);
          const currentDailyCount = dailyCounterDoc.exists ? (dailyCounterDoc.data()?.count || 0) : 0;
          if (!isAdminUser && currentDailyCount >= RECEIPT_DAILY_SUCCESS_LIMIT) {
            const err = new Error("DAILY_RECEIPT_LIMIT_REACHED");
            err.code = "DAILY_RECEIPT_LIMIT_REACHED";
            throw err;
          }

          // Duplicate detection (same logic as analyze endpoint)
          // Support legacy orderNumber type (string vs number) for duplicate detection
          const orderNumberStrForDup = String(data.orderNumber);
          const orderNumberNumForDup = parseInt(orderNumberStrForDup, 10);
          const orderNumberVariants = [orderNumberStrForDup];
          if (!isNaN(orderNumberNumForDup)) orderNumberVariants.push(orderNumberNumForDup);

          const duplicateQueries = [
            receiptsRef.where('orderDate', '==', data.orderDate).where('orderTime', '==', data.orderTime).limit(1),
            receiptsRef.where('orderDate', '==', data.orderDate).where('orderTime', '==', data.orderTime).where('orderTotal', '==', orderTotal).limit(1)
          ];
          for (const variant of orderNumberVariants) {
            duplicateQueries.push(
              receiptsRef.where('orderNumber', '==', variant).where('orderDate', '==', data.orderDate).limit(1)
            );
            duplicateQueries.push(
              receiptsRef.where('orderNumber', '==', variant).where('orderTime', '==', data.orderTime).limit(1)
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
          currentPoints = userData.points || 0; // Update outer variable
          const currentLifetime = (typeof userData.lifetimePoints === 'number')
            ? userData.lifetimePoints
            : currentPoints;
          newPointsBalance = currentPoints + pointsAwarded;
          newLifetimePoints = currentLifetime + pointsAwarded;

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

          // Increment daily counter inside the same transaction (skip for admins)
          const newDailyCount = isAdminUser ? currentDailyCount : (currentDailyCount + 1);
          if (!isAdminUser) {
            tx.set(
              dailyCounterRef,
              {
                userId: uid,
                day: userLocalDayKey,
                timeZone: userTimeZone,
                count: newDailyCount,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
              },
              { merge: true }
            );
          }

          // Update user points (and, if applicable, daily-limit streak fields)
          const userUpdate = {
            points: newPointsBalance,
            lifetimePoints: newLifetimePoints
          };

          // If the user just hit the daily cap today, update streak metadata.
          if (!isAdminUser && newDailyCount === RECEIPT_DAILY_SUCCESS_LIMIT) {
            const prevLastHitDay = (typeof userData.receiptLimitLastHitDay === 'string')
              ? userData.receiptLimitLastHitDay
              : null;
            const prevStreak = (typeof userData.receiptLimitHitStreak === 'number')
              ? userData.receiptLimitHitStreak
              : 0;

            const isConsecutive = (prevLastHitDay === userLocalYesterdayKey);
            const newStreak = isConsecutive ? (prevStreak > 0 ? prevStreak + 1 : 2) : 1;

            userUpdate.receiptLimitLastHitDay = userLocalDayKey;
            userUpdate.receiptLimitLastTimeZone = userTimeZone;
            userUpdate.receiptLimitHitStreak = newStreak;

            // Flag only when they hit the limit 2 days in a row (first time).
            if (newStreak === 2) {
              const flagType = 'receipt_daily_limit_2days';
              const severity = 'medium';
              const evidence = {
                day: userLocalDayKey,
                timeZone: userTimeZone,
                limit: RECEIPT_DAILY_SUCCESS_LIMIT,
                streak: newStreak
              };
              const riskScore = calculateSuspiciousRiskScore(severity, evidence);

              const flagId = `${flagType}_${uid}_${userLocalDayKey}`;
              const flagRef = db.collection('suspiciousFlags').doc(flagId);

              tx.set(flagRef, {
                userId: uid,
                flagType,
                severity,
                riskScore,
                description: 'Hit daily receipt scan limit on 2 consecutive days',
                evidence,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                status: 'pending',
                reviewedBy: null,
                reviewedAt: null,
                reviewNotes: null,
                actionTaken: null
              }, { merge: true });

              shouldUpdateRiskScore = true;
            }
          }

          tx.update(userRef, userUpdate);
        });
      } catch (e) {
        if (e && e.code === "DUPLICATE_RECEIPT") {
          await logFailureAndCheckLockout(uid, "DUPLICATE_RECEIPT", db, ipAddress);
          
          // Flag repeated duplicate receipt submissions within short windows
          try {
            const service = new SuspiciousBehaviorService(db);
            const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
            const recentDuplicates = await db.collection('receiptScanAttempts')
              .where('userId', '==', uid)
              .where('success', '==', false)
              .where('failureReason', '==', 'DUPLICATE_RECEIPT')
              .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(oneHourAgo))
              .get();
            
            if (recentDuplicates.size >= 3) {
              await service.flagSuspiciousBehavior(uid, {
                flagType: 'receipt_pattern',
                severity: 'medium',
                description: `Repeated duplicate receipt submissions: ${recentDuplicates.size} duplicate attempts in last hour`,
                evidence: {
                  duplicateAttempts: recentDuplicates.size,
                  timeWindow: '1 hour',
                  lastAttempt: new Date().toISOString()
                }
              });
            }
          } catch (detectionError) {
            logger.error('❌ Error flagging repeated duplicate receipts (non-blocking):', detectionError);
          }
          
          return sendError(
            res,
            409,
            "DUPLICATE_RECEIPT",
            "Receipt already submitted - this receipt has already been processed and points will not be awarded",
            { duplicate: true }
          );
        }
        if (e && e.code === "DAILY_RECEIPT_LIMIT_REACHED") {
          logger.info(`🚫 Daily receipt scan cap reached in transaction for user ${uid} day=${userLocalDayKey} tz=${userTimeZone}`);
          logReceiptScanAttempt(uid, false, "DAILY_LIMIT_REACHED", db, ipAddress).catch(() => {});
          return sendError(
            res,
            429,
            "DAILY_RECEIPT_LIMIT_REACHED",
            "You've hit your points limit for today. Come back tomorrow.",
            { day: userLocalDayKey, timeZone: userTimeZone, limit: RECEIPT_DAILY_SUCCESS_LIMIT }
          );
        }
        if (e && e.code === "USER_NOT_FOUND") {
          return sendError(res, 404, "USER_NOT_FOUND", "User not found");
        }
        logger.error('❌ submit-receipt transaction failed:', e);
        await logFailureAndCheckLockout(uid, "SERVER_AWARD_FAILED", db, ipAddress);
        return sendError(res, 500, "SERVER_AWARD_FAILED", "Server error while awarding points - please try again");
      }

      // Check if user crossed 50-point threshold and award referral if eligible
      // Note: currentPoints and newPointsBalance are set inside the transaction
      if (currentPoints < 50 && newPointsBalance >= 50) {
        logger.info(`✅ User ${uid} crossed 50-point threshold via receipt scan (${currentPoints} → ${newPointsBalance}), checking referral...`);
        try {
          const referralSnap = await db.collection('referrals')
            .where('referredUserId', '==', uid)
            .limit(1)
            .get();
          
          if (!referralSnap.empty) {
            const referralDoc = referralSnap.docs[0];
            const referralId = referralDoc.id;
            const referralData = referralDoc.data();
            
            if (referralData.status === 'pending') {
              const awardResult = await awardReferralPoints(db, referralId, referralData.referrerUserId, uid);
              if (awardResult.success) {
                logger.info(`🎉 Referral ${referralId} awarded via receipt scan! Referrer: +${awardResult.referrerNewPoints !== null ? 50 : 0}, Referred: +50`);
              } else {
                logger.warn(`⚠️ Failed to award referral via receipt scan: ${awardResult.error}`);
              }
            }
          }
        } catch (referralError) {
          logger.error('❌ Error checking referral after receipt scan (non-blocking):', referralError);
          // Don't fail the receipt submission if referral check fails
        }
      }

      // Log successful scan
      await logReceiptScanAttempt(uid, true, null, db, ipAddress);

      // Check for suspicious receipt patterns (async, don't block response)
      try {
        const service = new SuspiciousBehaviorService(db);
        if (shouldUpdateRiskScore) {
          service.updateUserRiskScore(uid).catch(() => {});
        }
        await service.checkReceiptPatterns(uid, {
          orderNumber: String(data.orderNumber),
          orderTotal: orderTotal,
          orderDate: data.orderDate,
          orderTime: data.orderTime,
          createdAt: new Date()
        });
        
        // Flag bursty scan attempts that approach rate-limit thresholds
        const oneMinuteAgo = new Date(Date.now() - 60 * 1000);
        const recentAttempts = await db.collection('receiptScanAttempts')
          .where('userId', '==', uid)
          .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(oneMinuteAgo))
          .get();
        
        // Flag if user is making 4+ attempts per minute (approaching the 6/min limit)
        if (recentAttempts.size >= 4) {
          await service.flagSuspiciousBehavior(uid, {
            flagType: 'receipt_pattern',
            severity: 'medium',
            description: `Bursty scan attempts: ${recentAttempts.size} attempts in last minute (approaching rate limit)`,
            evidence: {
              attemptsInLastMinute: recentAttempts.size,
              rateLimitThreshold: 6,
              timeWindow: '1 minute',
              lastAttempt: new Date().toISOString()
            }
          });
        }
      } catch (detectionError) {
        logger.error('❌ Error in receipt pattern detection (non-blocking):', detectionError);
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
      logger.error('❌ Error processing submit-receipt:', err);
      // Try to log failure if we have a user ID and db is available
      if (uid && typeof db !== 'undefined') {
        try {
          await logFailureAndCheckLockout(uid, "SERVER_ERROR", db, ipAddress);
        } catch (logErr) {
          logger.error('Failed to log receipt scan attempt:', logErr);
        }
      }
      return sendError(res, 500, "SERVER_ERROR", err.message || "Server error");
    }
  });

  // Welcome points claim (server-authoritative)
  // Prevents clients from directly incrementing their own points in Firestore.
  // Also checks abusePreventionHashes to prevent users who deleted accounts from re-claiming.
  app.post('/welcome/claim', requireFirebaseAuth, generalPerUserLimiter, generalPerIpLimiter, async (req, res) => {
    try {
      const uid = req.auth.uid;

      const db = admin.firestore();
      const userRef = db.collection('users').doc(uid);
      const txId = `welcome_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const welcomePoints = 5;

      // First, get the user document to retrieve phone number for hash check
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        return sendError(res, 404, "USER_NOT_FOUND", "User not found");
      }
      const userData = userDoc.data() || {};
      
      // Check if already claimed on this account
      if (userData.hasReceivedWelcomePoints === true) {
        return res.status(200).json({ success: true, alreadyClaimed: true });
      }

      // Check abuse prevention hash - this persists across account deletions
      const phoneHash = hashPhoneNumber(userData.phone);
      if (phoneHash) {
        const hashRef = db.collection('abusePreventionHashes').doc(phoneHash);
        const hashDoc = await hashRef.get();
        
        if (hashDoc.exists && hashDoc.data().hasReceivedWelcomePoints === true) {
          logger.info(`🚫 Welcome points blocked for ${uid} - phone hash previously claimed`);
          // Update the user document to mark as claimed (for UI consistency)
          await userRef.update({ hasReceivedWelcomePoints: true, isNewUser: false });
          return res.status(200).json({ 
            success: true, 
            alreadyClaimed: true, 
            reason: 'phone_previously_claimed' 
          });
        }
      }

      let newPointsBalance = null;
      let newLifetimePoints = null;

      await db.runTransaction(async (tx) => {
        const freshUserDoc = await tx.get(userRef);
        if (!freshUserDoc.exists) {
          const err = new Error("USER_NOT_FOUND");
          err.code = "USER_NOT_FOUND";
          throw err;
        }
        const freshUserData = freshUserDoc.data() || {};
        
        // Double-check in transaction
        if (freshUserData.hasReceivedWelcomePoints === true) {
          return; // Will be handled below
        }

        const currentPoints = freshUserData.points || 0;
        const currentLifetime = (typeof freshUserData.lifetimePoints === 'number') ? freshUserData.lifetimePoints : currentPoints;
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

      // If points weren't awarded (double-claim race condition), return early
      if (newPointsBalance === null) {
        return res.status(200).json({ success: true, alreadyClaimed: true });
      }

      // Update abuse prevention hash record (outside transaction for simplicity)
      if (phoneHash) {
        const hashRef = db.collection('abusePreventionHashes').doc(phoneHash);
        await hashRef.set({
          phoneHash,
          hasReceivedWelcomePoints: true,
          welcomePointsClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastAccountCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
          accountCreationCount: admin.firestore.FieldValue.increment(1)
        }, { merge: true });
        logger.info(`✅ Welcome points granted and hash recorded for ${uid}`);
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
      logger.error('❌ Error in /welcome/claim:', err);
      return sendError(res, 500, "SERVER_ERROR", "Failed to claim welcome points");
    }
  });

  // Chat endpoint for restaurant assistant (AUTH REQUIRED + rate limits)
  const chatPerUserLimiter = createRateLimiter({
    keyFn: (req) => req.auth?.uid,
    windowMs: 60_000,
    max: parseInt(process.env.CHAT_UID_PER_MIN || '12', 10),
    errorCode: 'CHAT_RATE_LIMITED'
  });
  const chatPerIpLimiter = createRateLimiter({
    keyFn: (req) => getClientIp(req),
    windowMs: 60_000,
    max: parseInt(process.env.CHAT_IP_PER_MIN || '30', 10),
    errorCode: 'CHAT_RATE_LIMITED'
  });

  app.post('/chat', requireFirebaseAuth, chatPerUserLimiter, chatPerIpLimiter, validate(chatSchema), async (req, res) => {
    try {
      logger.info('💬 Received chat request');
      
      const { message, conversation_history, userFirstName, userPreferences, userPoints } = req.body;
      // Validation middleware ensures message exists and meets length requirements

      // Daily quota (cross-restart protection against runaway spend)
      const db = admin.firestore();
      const chatQuota = await enforceDailyQuota({
        db,
        uid: req.auth.uid,
        endpointKey: 'chat',
        limit: process.env.CHAT_DAILY_LIMIT || 60
      });
      if (!chatQuota.allowed) {
        return sendError(res, 429, 'DAILY_LIMIT_REACHED', 'Daily chat limit reached. Please try again tomorrow.', {
          day: chatQuota.dayKey,
          limit: chatQuota.limit
        });
      }

      logger.info('📝 User message (truncated):', String(message).substring(0, 200));
      logger.info('👤 User first name:', userFirstName || 'Not provided');
      logger.info('⚙️ User preferences:', userPreferences || 'Not provided');
      logger.info('🏅 User points:', typeof userPoints === 'number' ? userPoints : 'Not provided');
      
      // Debug mode: Return full prompt information when user sends "9327"
      if (process.env.ENABLE_CHAT_DEBUG === 'true' && message === "9327") {
        logger.info('🔍 Debug mode activated - returning full prompt information');
        
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
- Peanut Butter Shrimp Dumplings $7.99
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
- Peanut Butter Shrimp Dumplings $7.99
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
        messages.push(...conversation_history.slice(-6)); // Keep last N messages for context
      }
      
      // Add current user message
      messages.push({ role: 'user', content: message });

      logger.info('🤖 Sending request to OpenAI...');
      logger.info('📋 System prompt preview:', systemPrompt.substring(0, 200) + '...');
      
      const response = await openaiWithTimeout(openai, {
        model: "gpt-4o-mini",
        messages: messages,
        max_tokens: parseInt(process.env.CHAT_MAX_TOKENS || '500', 10),
        temperature: 0.7
      });

      logger.info('✅ OpenAI response received');
      
      const botResponse = response.choices[0].message.content;
      logger.info('🤖 Bot response:', botResponse);
      
      res.json({ response: botResponse });
    } catch (err) {
      logger.error('❌ Error processing chat:', err);
      res.status(500).json({ error: err.message });
    }
  });

  // Fetch complete menu from Firestore endpoint
  app.get('/firestore-menu', requireAdminAuth, async (req, res) => {
    try {
      logger.info('🔍 Fetching complete menu from Firestore...');
      
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
        logger.info(`🔍 Processing category: ${categoryId}`);
        
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
            logger.info(`✅ Added item: ${menuItem.id} (${categoryId})`);
          } catch (error) {
            logger.error(`❌ Error processing item ${itemDoc.id} in category ${categoryId}:`, error);
          }
        }
      }
      
      logger.info(`✅ Fetched ${allMenuItems.length} menu items from Firestore`);
      
      res.json({
        success: true,
        menuItems: allMenuItems,
        totalItems: allMenuItems.length,
        categories: categoriesSnapshot.docs.map(doc => doc.id)
      });
      
    } catch (error) {
      logger.error('❌ Error fetching menu from Firestore:', error);
      res.status(500).json({ 
        error: 'Failed to fetch menu from Firestore',
        details: error.message 
      });
    }
  });

  // Shared rate limits for Dumpling Hero OpenAI endpoints
  const heroPerUserLimiter = createRateLimiter({
    keyFn: (req) => req.auth?.uid,
    windowMs: 60_000,
    max: parseInt(process.env.HERO_UID_PER_MIN || '8', 10),
    errorCode: 'HERO_RATE_LIMITED'
  });
  const heroPerIpLimiter = createRateLimiter({
    keyFn: (req) => getClientIp(req),
    windowMs: 60_000,
    max: parseInt(process.env.HERO_IP_PER_MIN || '20', 10),
    errorCode: 'HERO_RATE_LIMITED'
  });

  // Dumpling Hero Post Generation endpoint
  app.post('/generate-dumpling-hero-post', requireFirebaseAuth, validate(dumplingHeroPostSchema), heroPerUserLimiter, heroPerIpLimiter, async (req, res) => {
    try {
      logger.info('🤖 Received Dumpling Hero post generation request');
      logger.info('📥 Request body:', JSON.stringify(req.body, null, 2));
      
      const { prompt, menuItems } = req.body;

      const db = admin.firestore();
      const quota = await enforceDailyQuota({
        db,
        uid: req.auth.uid,
        endpointKey: 'generate-dumpling-hero-post',
        limit: process.env.HERO_DAILY_LIMIT || 30
      });
      if (!quota.allowed) {
        return res.status(429).json({
          errorCode: 'DAILY_LIMIT_REACHED',
          error: 'Daily limit reached. Please try again tomorrow.',
          dayKey: quota.dayKey,
          limit: quota.limit
        });
      }
      
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

      logger.info('🤖 Sending request to OpenAI for Dumpling Hero post...');
      
      const response = await openaiWithTimeout(openai, {
        model: "gpt-4o-mini",
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage }
        ],
        max_tokens: 500,
        temperature: 0.8
      });

      logger.info('✅ Received Dumpling Hero post from OpenAI');
      
      const generatedContent = response.choices[0].message.content;
      logger.info('📝 Generated content:', generatedContent);
      
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
        logger.info('⚠️ Could not parse JSON response, using raw text');
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
      logger.error('❌ Error generating Dumpling Hero post:', error);
      res.status(500).json({ 
        error: 'Failed to generate Dumpling Hero post',
        details: error.message 
      });
    }
  });

  // Dumpling Hero Comment Generation endpoint
  app.post('/generate-dumpling-hero-comment', requireFirebaseAuth, validate(dumplingHeroCommentSchema), heroPerUserLimiter, heroPerIpLimiter, async (req, res) => {
    try {
      logger.info('🤖 Received Dumpling Hero comment generation request');
      logger.info('📥 Request body:', JSON.stringify(req.body, null, 2));
      
      const { prompt, replyingTo, postContext } = req.body;

      const db = admin.firestore();
      const quota = await enforceDailyQuota({
        db,
        uid: req.auth.uid,
        endpointKey: 'generate-dumpling-hero-comment',
        limit: process.env.HERO_DAILY_LIMIT || 30
      });
      if (!quota.allowed) {
        return res.status(429).json({
          errorCode: 'DAILY_LIMIT_REACHED',
          error: 'Daily limit reached. Please try again tomorrow.',
          dayKey: quota.dayKey,
          limit: quota.limit
        });
      }
      
      // Debug logging for post context
      logger.info('🔍 Post Context Analysis:');
      if (postContext && Object.keys(postContext).length > 0) {
        logger.info('✅ Post context received:');
        logger.info('   - Content:', postContext.content);
        logger.info('   - Author:', postContext.authorName);
        logger.info('   - Type:', postContext.postType);
        logger.info('   - Images:', postContext.imageURLs?.length || 0);
        logger.info('   - Has Menu Item:', !!postContext.attachedMenuItem);
        logger.info('   - Has Poll:', !!postContext.poll);
        if (postContext.attachedMenuItem) {
          logger.info('   - Menu Item:', postContext.attachedMenuItem.description);
        }
        if (postContext.poll) {
          logger.info('   - Poll Question:', postContext.poll.question);
        }
      } else {
        logger.info('❌ No post context received or empty context');
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

      logger.info('🤖 Sending request to OpenAI for Dumpling Hero comment...');
      logger.info('📤 Final user message being sent to OpenAI:');
      logger.info('---START OF MESSAGE---');
      logger.info(userMessage);
      logger.info('---END OF MESSAGE---');
      
      const response = await openaiWithTimeout(openai, {
        model: "gpt-4o-mini",
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage }
        ],
        max_tokens: 300,
        temperature: 0.8
      });

      logger.info('✅ Received Dumpling Hero comment from OpenAI');
      
      const generatedContent = response.choices[0].message.content;
      logger.info('📝 Generated content:', generatedContent);
      
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
        logger.info('⚠️ Could not parse JSON response, using raw text');
        parsedResponse = {
          commentText: generatedContent
        };
      }
      
      res.json({
        success: true,
        comment: parsedResponse
      });
      
    } catch (error) {
      logger.error('❌ Error generating Dumpling Hero comment:', error);
      res.status(500).json({ 
        error: 'Failed to generate Dumpling Hero comment',
        details: error.message 
      });
    }
  });

  // Dumpling Hero Comment Preview endpoint (for preview before posting)
  const heroPreviewPerUserLimiter = createRateLimiter({
    keyFn: (req) => req.auth?.uid,
    windowMs: 60_000,
    max: parseInt(process.env.HERO_PREVIEW_UID_PER_MIN || '10', 10),
    errorCode: 'HERO_RATE_LIMITED'
  });
  const heroPreviewPerIpLimiter = createRateLimiter({
    keyFn: (req) => getClientIp(req),
    windowMs: 60_000,
    max: parseInt(process.env.HERO_PREVIEW_IP_PER_MIN || '25', 10),
    errorCode: 'HERO_RATE_LIMITED'
  });

  app.post('/preview-dumpling-hero-comment', requireFirebaseAuth, validate(dumplingHeroCommentPreviewSchema), heroPreviewPerUserLimiter, heroPreviewPerIpLimiter, async (req, res) => {
    try {
      logger.info('🤖 Received Dumpling Hero comment preview request');
      logger.info('📥 Request body:', JSON.stringify(req.body, null, 2));
      
      const { prompt, postContext } = req.body;

      // Daily quota (cross-restart protection)
      const db = admin.firestore();
      const quota = await enforceDailyQuota({
        db,
        uid: req.auth.uid,
        endpointKey: 'preview-dumpling-hero-comment',
        limit: process.env.HERO_PREVIEW_DAILY_LIMIT || 40
      });
      if (!quota.allowed) {
        return res.status(429).json({
          errorCode: 'DAILY_LIMIT_REACHED',
          error: 'Daily limit reached. Please try again tomorrow.',
          dayKey: quota.dayKey,
          limit: quota.limit
        });
      }
      
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
        logger.info('🔍 Post Context Analysis for Preview Endpoint:');
        logger.info('✅ Post context received:');
        logger.info('   - Content:', postContext.content);
        logger.info('   - Author:', postContext.authorName);
        logger.info('   - Type:', postContext.postType);
        
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

      logger.info('🤖 Sending request to OpenAI for Dumpling Hero comment preview...');
      logger.info('📝 User message being sent to ChatGPT:');
      logger.info(userMessage);
      
      const response = await openaiWithTimeout(openai, {
        model: "gpt-4o-mini",
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage }
        ],
        max_tokens: 200,
        temperature: 0.8
      });

      logger.info('✅ Received Dumpling Hero comment preview from OpenAI');
      
      const generatedContent = response.choices[0].message.content;
      logger.info('📝 Generated content:', generatedContent);
      
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
        logger.info('⚠️ Could not parse JSON response, using raw text');
        parsedResponse = {
          commentText: generatedContent
        };
      }
      
      res.json({
        success: true,
        comment: parsedResponse
      });
      
    } catch (error) {
      logger.error('❌ Error generating Dumpling Hero comment preview:', error);
      res.status(500).json({ 
        error: 'Failed to generate Dumpling Hero comment preview',
        details: error.message 
      });
    }
  });

  // Simple Dumpling Hero Comment Generation endpoint (for external use)
  app.post('/generate-dumpling-hero-comment-simple', requireFirebaseAuth, validate(dumplingHeroCommentPreviewSchema), heroPerUserLimiter, heroPerIpLimiter, async (req, res) => {
    try {
      logger.info('🤖 Received simple Dumpling Hero comment generation request');
      logger.info('📥 Request body:', JSON.stringify(req.body, null, 2));
      
      const { prompt, postContext } = req.body;

      const db = admin.firestore();
      const quota = await enforceDailyQuota({
        db,
        uid: req.auth.uid,
        endpointKey: 'generate-dumpling-hero-comment-simple',
        limit: process.env.HERO_DAILY_LIMIT || 30
      });
      if (!quota.allowed) {
        return res.status(429).json({
          errorCode: 'DAILY_LIMIT_REACHED',
          error: 'Daily limit reached. Please try again tomorrow.',
          dayKey: quota.dayKey,
          limit: quota.limit
        });
      }
      
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
        logger.info('🔍 Post Context Analysis for Simple Endpoint:');
        logger.info('✅ Post context received:');
        logger.info('   - Content:', postContext.content);
        logger.info('   - Author:', postContext.authorName);
        logger.info('   - Type:', postContext.postType);
        
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

      logger.info('🤖 Sending request to OpenAI for simple Dumpling Hero comment...');
      logger.info('📝 User message being sent to ChatGPT:');
      logger.info(userMessage);
      
      const response = await openaiWithTimeout(openai, {
        model: "gpt-4o-mini",
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage }
        ],
        max_tokens: 200,
        temperature: 0.8
      });

      logger.info('✅ Received simple Dumpling Hero comment from OpenAI');
      
      const generatedContent = response.choices[0].message.content;
      logger.info('📝 Generated content:', generatedContent);
      
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
        logger.info('⚠️ Could not parse JSON response, using raw text');
        parsedResponse = {
          commentText: generatedContent
        };
      }
      
      res.json(parsedResponse);
      
    } catch (error) {
      logger.error('❌ Error generating simple Dumpling Hero comment:', error);
      res.status(500).json({ 
        error: 'Failed to generate Dumpling Hero comment',
        details: error.message 
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Reward Tier Items - Fetch eligible items for a reward tier
  // ---------------------------------------------------------------------------
  
  app.get('/reward-tier-items/:pointsRequired', generalPerIpLimiter, async (req, res) => {
    try {
      const pointsRequired = parseInt(req.params.pointsRequired, 10);
      
      if (isNaN(pointsRequired) || pointsRequired <= 0) {
        return res.status(400).json({ error: 'Invalid pointsRequired parameter' });
      }
      
      logger.info(`🎁 Fetching eligible items for ${pointsRequired} point tier`);
      
      const db = admin.firestore();
      
      // Query rewardTierItems collection for this points tier
      const snapshot = await db.collection('rewardTierItems')
        .where('pointsRequired', '==', pointsRequired)
        .limit(1)
        .get();
      
      if (snapshot.empty) {
        logger.info(`📭 No configured items for ${pointsRequired} point tier`);
        return res.json({
          pointsRequired,
          tierName: null,
          eligibleItems: []
        });
      }
      
      const tierDoc = snapshot.docs[0];
      const tierData = tierDoc.data();
      
      logger.info(`✅ Found ${(tierData.eligibleItems || []).length} eligible items for tier`);
      
      res.json({
        pointsRequired: tierData.pointsRequired,
        tierName: tierData.tierName || null,
        eligibleItems: tierData.eligibleItems || []
      });
      
    } catch (error) {
      logger.error('❌ Error fetching reward tier items:', error);
      res.status(500).json({ 
        error: 'Failed to fetch reward tier items',
        details: error.message 
      });
    }
  });

  // Fetch eligible items for a reward tier by tier ID
  app.get('/reward-tier-items/by-id/:tierId', generalPerIpLimiter, async (req, res) => {
    try {
      const { tierId } = req.params;
      if (!tierId) {
        return res.status(400).json({ error: 'tierId is required' });
      }
      
      logger.info(`🎁 Fetching eligible items for tier ${tierId}`);
      
      const db = admin.firestore();
      const tierDoc = await db.collection('rewardTierItems').doc(tierId).get();
      
      if (!tierDoc.exists) {
        logger.info(`📭 No configured items for tier ${tierId}`);
        return res.json({
          tierId,
          pointsRequired: null,
          tierName: null,
          eligibleItems: []
        });
      }
      
      const tierData = tierDoc.data();
      logger.info(`✅ Found ${(tierData.eligibleItems || []).length} eligible items for tier`);
      
      res.json({
        tierId,
        pointsRequired: tierData.pointsRequired || null,
        tierName: tierData.tierName || null,
        eligibleItems: tierData.eligibleItems || []
      });
      
    } catch (error) {
      logger.error('❌ Error fetching reward tier items by ID:', error);
      res.status(500).json({ 
        error: 'Failed to fetch reward tier items',
        details: error.message 
      });
    }
  });

  // Redeem reward endpoint
  app.post('/redeem-reward', requireFirebaseAuth, validate(redeemRewardSchema), async (req, res) => {
    let pointsRequiredNumber = null;
    try {
      logger.info('🎁 Received reward redemption request');
      logger.info('📥 Request body:', JSON.stringify(req.body, null, 2));
      
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
        logger.info('❌ Missing required fields for reward redemption');
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
        
        logger.info(`👤 User ${userId} has ${currentPoints} points, needs ${pointsRequiredNumber} for reward`);
        
        if (currentPoints < pointsRequiredNumber) {
          const error = new Error('INSUFFICIENT_POINTS');
          error.code = 'INSUFFICIENT_POINTS';
          error.currentPoints = currentPoints;
          throw error;
        }
        
        const redemptionCode = Math.floor(10000000 + Math.random() * 90000000).toString();
        logger.info(`🔢 Generated redemption code: ${redemptionCode}`);
        
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
      
      logger.info(`✅ Reward redeemed successfully!`);
      logger.info(`🔢 Redemption code: ${responseData.redemptionCode}`);
      logger.info(`💰 Points deducted: ${responseData.pointsDeducted}`);
      logger.info(`💳 New balance: ${responseData.newPointsBalance}`);
      
      res.json(responseData);
      
    } catch (error) {
      logger.error('❌ Error redeeming reward:', error);
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
      logger.error('❌ Admin auth check failed:', err);
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
      logger.error('❌ Staff auth check failed:', err);
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
      logger.error('❌ User auth check failed:', err);
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
  app.post('/me/fcmToken', requireFirebaseAuth, generalPerUserLimiter, generalPerIpLimiter, async (req, res) => {
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
      logger.error('❌ Error in /me/fcmToken:', error);
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
      logger.error('❌ Error in /admin/debug/firebase:', error);
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
      logger.error('❌ Error in /admin/debug/pushTargets:', error);
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
          avatarColor: data.avatarColor || data.avatarColorName || null,
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
      logger.error('❌ Error listing admin users:', error);
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
  app.post('/admin/users/update', validate(adminUserUpdateSchema), async (req, res) => {
    try {
      logger.info('📥 Received admin user update request');
      logger.info('📦 Request body:', JSON.stringify(req.body, null, 2));
      
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) {
        logger.info('❌ Admin authentication failed');
        return; // requireAdmin already sent the response
      }

      logger.info('✅ Admin authenticated:', adminContext.uid);

      const {
        userId,
        points,
        phone,
        isAdmin: isAdminFlag,
        isVerified: isVerifiedFlag
      } = req.body || {};
      // Validation middleware ensures userId is present and valid

      const pointsInt = Number(points);
      if (!Number.isInteger(pointsInt) || pointsInt < 0) {
        logger.info('❌ Invalid points value:', points);
        return res.status(400).json({ 
          errorCode: 'INVALID_REQUEST',
          error: 'points must be a non-negative integer' 
        });
      }

      logger.info(`🔄 Updating user ${userId}: points=${pointsInt}, isAdmin=${isAdminFlag}, isVerified=${isVerifiedFlag}`);

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

        logger.info('📝 Update data:', JSON.stringify(updateData, null, 2));

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

      logger.info('✅ User update successful:', JSON.stringify(result, null, 2));
      return res.json({ success: true, ...result });
    } catch (error) {
      logger.error('❌ Error updating admin user:', error);
      logger.error('❌ Error stack:', error.stack);
      
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
   * POST /admin/users/:userId/clear-lockout
   *
   * Admin-only endpoint to clear receipt scan lockout for a user.
   * Useful for testing/debugging when lockouts interfere with development.
   *
   * Body: none (userId from URL param)
   *
   * Returns:
   * - success: boolean
   * - message: string
   */
  app.post('/admin/users/:userId/clear-lockout', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) {
        return; // requireAdmin already sent the response
      }

      const { userId } = req.params;
      if (!userId || typeof userId !== 'string') {
        return res.status(400).json({
          errorCode: 'INVALID_REQUEST',
          error: 'userId is required in URL path'
        });
      }

      const db = admin.firestore();
      const userRef = db.collection('users').doc(userId);
      const userDoc = await userRef.get();

      if (!userDoc.exists) {
        return res.status(404).json({
          errorCode: 'USER_NOT_FOUND',
          error: `User with ID '${userId}' not found`
        });
      }

      const userData = userDoc.data() || {};
      const hadLockout = !!(userData.receiptScanLockoutUntil || userData.receiptScanLockoutCount);

      await userRef.update({
        receiptScanLockoutUntil: admin.firestore.FieldValue.delete(),
        receiptScanLockoutCount: admin.firestore.FieldValue.delete()
      });

      logger.info(`✅ Admin ${adminContext.uid} cleared lockout for user ${userId}`);

      return res.json({
        success: true,
        message: hadLockout
          ? `Lockout cleared for user ${userId}`
          : `No lockout found for user ${userId} (already clear)`
      });
    } catch (error) {
      logger.error('❌ Error clearing lockout:', error);
      return res.status(500).json({
        errorCode: 'INTERNAL_ERROR',
        error: `Failed to clear lockout: ${error.message || 'Unknown error'}`
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
      
      logger.info('🧹 Starting orphaned accounts cleanup...');
      
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
              logger.info(`🔍 Found orphaned account: ${uid}`);
            } else {
              // Other errors (permissions, etc.) - log but don't treat as orphaned
              logger.warn(`⚠️ Error checking user ${uid}: ${error.code}`);
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
          logger.info(`✅ Deleted batch of ${batchUIDs.length} orphaned accounts`);
        } catch (error) {
          logger.error(`❌ Error deleting batch: ${error.message}`);
        }
      }
      
      logger.info(`✅ Cleanup complete: Deleted ${deletedCount} orphaned accounts out of ${checkedCount} checked`);
      
      return res.json({
        deletedCount,
        checkedCount,
        message: `Cleaned up ${deletedCount} orphaned account(s) out of ${checkedCount} checked`
      });
    } catch (error) {
      logger.error('❌ Error in /admin/users/cleanup-orphans:', error);
      res.status(500).json({ error: 'Failed to cleanup orphaned accounts' });
    }
  });

  /**
   * POST /admin/banned-account-archive
   *
   * Archives a banned user's data to bannedAccountHistory collection before deletion.
   * Called by banned users when they delete their account from BannedAccountDeletionView.
   * 
   * This endpoint:
   * 1. Copies user document to bannedAccountHistory (with 24hr expiration)
   * 2. Anonymizes redeemedRewards, receipts, posts, etc.
   * 3. Deletes the original users/{uid} document
   * 4. Returns success so client can delete Firebase Auth user
   *
   * Request: Requires Bearer token of the banned user
   * Response: { success: true, historyId: string } or error
   */
  app.post('/admin/banned-account-archive', async (req, res) => {
    try {
      // Verify the user's token
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
      if (!token) {
        return res.status(401).json({ error: 'Missing or invalid Authorization header' });
      }

      const decoded = await admin.auth().verifyIdToken(token);
      const uid = decoded.uid;
      logger.info(`🗑️ Starting banned account archive for user: ${uid}`);

      const db = admin.firestore();

      // Get the user document
      const userDoc = await db.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        return res.status(404).json({ error: 'User document not found' });
      }
      const userData = userDoc.data();

      // Verify user is banned (extra safety check)
      const isBanned = userData.isBanned === true;
      const phone = userData.phone || '';
      
      // Also check bannedNumbers collection
      let banInfo = null;
      if (phone) {
        const normalized = normalizePhoneForBannedNumbers(phone) || phone;
        const digitsOnlyLegacy = (normalized || '').replace('+', '');
        const hashedId = hashBannedNumbersDocId(normalized);
        let bannedDoc = null;
        if (hashedId) {
          const snap = await db.collection('bannedNumbers').doc(hashedId).get();
          if (snap.exists) bannedDoc = snap;
        }
        if (!bannedDoc) {
          const snap = await db.collection('bannedNumbers').doc(normalized).get();
          if (snap.exists) bannedDoc = snap;
        }
        if (!bannedDoc && digitsOnlyLegacy) {
          const snap = await db.collection('bannedNumbers').doc(digitsOnlyLegacy).get();
          if (snap.exists) bannedDoc = snap;
        }
        if (bannedDoc) banInfo = bannedDoc.data();
      }

      if (!isBanned && !banInfo) {
        return res.status(403).json({ error: 'User is not banned. Use regular account deletion.' });
      }

      // Get summary counts
      const [receiptsSnap, redeemedSnap, postsSnap, referralsSnap] = await Promise.all([
        db.collection('receipts').where('userId', '==', uid).get(),
        db.collection('redeemedRewards').where('userId', '==', uid).get(),
        db.collection('posts').where('userId', '==', uid).get(),
        db.collection('referrals').where('referrerUserId', '==', uid).get()
      ]);

      const receiptCount = receiptsSnap.size;
      const redeemedRewardsCount = redeemedSnap.size;
      const postCount = postsSnap.size;
      const referralCount = referralsSnap.size;

      // Create the archive document
      const now = admin.firestore.Timestamp.now();
      const expiresAt = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 hours from now
      );
      
      const historyId = `${uid}_${Date.now()}`;
      const archiveData = {
        originalUserId: uid,
        archivedAt: now,
        expiresAt: expiresAt,
        userData: {
          firstName: userData.firstName || '',
          lastName: userData.lastName || '',
          phone: userData.phone || '',
          points: userData.points || 0,
          lifetimePoints: userData.lifetimePoints || 0,
          accountCreatedDate: userData.accountCreatedDate || userData.createdAt || null,
          avatarEmoji: userData.avatarEmoji || '👤',
          avatarColor: userData.avatarColor || 'gray',
          isVerified: userData.isVerified || false,
          hasCompletedPreferences: userData.hasCompletedPreferences || false
        },
        receiptCount,
        redeemedRewardsCount,
        postCount,
        referralCount,
        banReason: banInfo?.reason || 'Banned',
        bannedAt: banInfo?.bannedAt || null,
        bannedBy: banInfo?.bannedBy || null
      };

      logger.info(`📦 Creating archive document: ${historyId}`);
      await db.collection('bannedAccountHistory').doc(historyId).set(archiveData);

      // Anonymize data (similar to AccountDeletionService)
      const batch = db.batch();
      let batchCount = 0;
      const BATCH_LIMIT = 450;

      // Anonymize redeemedRewards
      for (const doc of redeemedSnap.docs.slice(0, BATCH_LIMIT)) {
        batch.update(doc.ref, {
          userName: 'Deleted User',
          userPhone: ''
        });
        batchCount++;
      }

      // Anonymize receipts
      for (const doc of receiptsSnap.docs.slice(0, BATCH_LIMIT - batchCount)) {
        if (batchCount >= BATCH_LIMIT) break;
        batch.update(doc.ref, {
          userName: 'Deleted User',
          userPhone: '',
          userEmail: ''
        });
        batchCount++;
      }

      // Anonymize posts
      for (const doc of postsSnap.docs.slice(0, BATCH_LIMIT - batchCount)) {
        if (batchCount >= BATCH_LIMIT) break;
        batch.update(doc.ref, {
          userName: 'Deleted User',
          userDisplayName: 'Deleted User'
        });
        batchCount++;
      }

      // Commit anonymization batch
      if (batchCount > 0) {
        await batch.commit();
        logger.info(`✅ Anonymized ${batchCount} documents`);
      }

      // Delete points transactions
      const pointsSnap = await db.collection('pointsTransactions').where('userId', '==', uid).get();
      if (!pointsSnap.empty) {
        const deleteBatch = db.batch();
        for (const doc of pointsSnap.docs.slice(0, BATCH_LIMIT)) {
          deleteBatch.delete(doc.ref);
        }
        await deleteBatch.commit();
        logger.info(`✅ Deleted ${Math.min(pointsSnap.size, BATCH_LIMIT)} points transactions`);
      }

      // Delete referrals (both as referrer and referred)
      const referredSnap = await db.collection('referrals').where('referredUserId', '==', uid).get();
      if (!referralsSnap.empty || !referredSnap.empty) {
        const refBatch = db.batch();
        let refCount = 0;
        for (const doc of referralsSnap.docs.slice(0, BATCH_LIMIT / 2)) {
          refBatch.delete(doc.ref);
          refCount++;
        }
        for (const doc of referredSnap.docs.slice(0, BATCH_LIMIT / 2)) {
          refBatch.delete(doc.ref);
          refCount++;
        }
        if (refCount > 0) {
          await refBatch.commit();
          logger.info(`✅ Deleted ${refCount} referrals`);
        }
      }

      // Delete notifications
      const notifSnap = await db.collection('notifications').where('userId', '==', uid).get();
      if (!notifSnap.empty) {
        const notifBatch = db.batch();
        for (const doc of notifSnap.docs.slice(0, BATCH_LIMIT)) {
          notifBatch.delete(doc.ref);
        }
        await notifBatch.commit();
        logger.info(`✅ Deleted ${Math.min(notifSnap.size, BATCH_LIMIT)} notifications`);
      }

      // Delete user subcollections (clientState, activity)
      const clientStateSnap = await db.collection('users').doc(uid).collection('clientState').get();
      const activitySnap = await db.collection('users').doc(uid).collection('activity').get();
      
      if (!clientStateSnap.empty || !activitySnap.empty) {
        const subBatch = db.batch();
        for (const doc of clientStateSnap.docs) {
          subBatch.delete(doc.ref);
        }
        for (const doc of activitySnap.docs) {
          subBatch.delete(doc.ref);
        }
        await subBatch.commit();
        logger.info(`✅ Deleted user subcollections`);
      }

      // Delete userRiskScore if exists
      await db.collection('userRiskScores').doc(uid).delete().catch(() => {});

      // Delete the user document
      await db.collection('users').doc(uid).delete();
      logger.info(`✅ Deleted user document: ${uid}`);

      logger.info(`✅ Banned account archive complete for user: ${uid}`);
      return res.json({ 
        success: true, 
        historyId,
        message: 'Account archived and data cleaned up. You can now delete your Firebase Auth account.'
      });

    } catch (error) {
      logger.error('❌ Error in /admin/banned-account-archive:', error);
      res.status(500).json({ error: 'Failed to archive banned account' });
    }
  });

  /**
   * POST /user/delete-account
   *
   * Self-service account deletion endpoint.
   * Called by regular (non-banned) users to delete their own account.
   * Uses Firebase Admin SDK to bypass App Check and Firestore permission issues.
   *
   * This endpoint:
   * 1. Verifies user token and extracts UID
   * 2. Anonymizes PII in: receipts, redeemedRewards, giftedRewardClaims, posts, suspiciousFlags, bannedNumbers
   * 3. Deletes: pointsTransactions, referrals, notifications, receiptScanAttempts, user subcollections, userRiskScores
   * 4. Deletes profile photo from Firebase Storage (if exists)
   * 5. Deletes user document
   * 6. Deletes Firebase Auth user
   *
   * Request: Requires Bearer token of the user requesting deletion
   * Response: { success: true } or error
   */
  app.post('/user/delete-account', async (req, res) => {
    try {
      // Verify the user's token
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
      if (!token) {
        return res.status(401).json({ error: 'Missing or invalid Authorization header' });
      }

      const decoded = await admin.auth().verifyIdToken(token);
      const uid = decoded.uid;
      logger.info(`🗑️ Starting account deletion for user: ${uid}`);

      const db = admin.firestore();
      const BATCH_LIMIT = 450;

      // Get the user document to retrieve profile photo URL
      const userDoc = await db.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        // User document already deleted - try to delete Auth user anyway
        logger.info(`⚠️ User document not found for ${uid}, attempting Auth deletion only`);
        try {
          await admin.auth().deleteUser(uid);
          logger.info(`✅ Auth user deleted: ${uid}`);
        } catch (authErr) {
          logger.info(`ℹ️ Auth user may already be deleted: ${authErr.message}`);
        }
        return res.json({ success: true, message: 'Account already deleted or cleanup completed' });
      }
      const userData = userDoc.data();
      const profilePhotoURL = userData.profilePhotoURL || null;

      // ========== PHASE 1: ANONYMIZATION ==========
      logger.info(`📝 Phase 1: Anonymizing PII for user ${uid}`);

      // Get all documents to anonymize in parallel
      const [receiptsSnap, redeemedSnap, giftedClaimsSnap, postsSnap, suspiciousFlagsSnap] = await Promise.all([
        db.collection('receipts').where('userId', '==', uid).get(),
        db.collection('redeemedRewards').where('userId', '==', uid).get(),
        db.collection('giftedRewardClaims').where('userId', '==', uid).get(),
        db.collection('posts').where('userId', '==', uid).get(),
        db.collection('suspiciousFlags').where('userId', '==', uid).get()
      ]);

      // Anonymize in batches
      let batch = db.batch();
      let batchCount = 0;

      // Anonymize receipts
      for (const doc of receiptsSnap.docs) {
        if (batchCount >= BATCH_LIMIT) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
        batch.update(doc.ref, {
          userName: 'Deleted User',
          userPhone: '',
          userEmail: ''
        });
        batchCount++;
      }

      // Anonymize redeemedRewards
      for (const doc of redeemedSnap.docs) {
        if (batchCount >= BATCH_LIMIT) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
        batch.update(doc.ref, {
          userName: 'Deleted User',
          userPhone: ''
        });
        batchCount++;
      }

      // Anonymize giftedRewardClaims
      for (const doc of giftedClaimsSnap.docs) {
        if (batchCount >= BATCH_LIMIT) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
        batch.update(doc.ref, {
          userName: 'Deleted User',
          userPhone: ''
        });
        batchCount++;
      }

      // Anonymize posts
      for (const doc of postsSnap.docs) {
        if (batchCount >= BATCH_LIMIT) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
        batch.update(doc.ref, {
          userName: 'Deleted User',
          userDisplayName: 'Deleted User'
        });
        batchCount++;
      }

      // Anonymize suspiciousFlags (anonymize evidence fields)
      for (const doc of suspiciousFlagsSnap.docs) {
        if (batchCount >= BATCH_LIMIT) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
        const data = doc.data();
        const anonymizedEvidence = { ...(data.evidence || {}) };
        if (anonymizedEvidence.userName) anonymizedEvidence.userName = 'Deleted User';
        if (anonymizedEvidence.userPhone) anonymizedEvidence.userPhone = '';
        if (anonymizedEvidence.userEmail) anonymizedEvidence.userEmail = '';
        batch.update(doc.ref, { evidence: anonymizedEvidence });
        batchCount++;
      }

      // Anonymize bannedNumbers (if user was banned, just update originalUserName)
      const userPhone = userData.phone || '';
      if (userPhone) {
        const normalized = normalizePhoneForBannedNumbers(userPhone) || userPhone;
        const digitsOnlyLegacy = (normalized || '').replace('+', '');
        const hashedId = hashBannedNumbersDocId(normalized);
        let bannedDoc = null;
        if (hashedId) {
          const snap = await db.collection('bannedNumbers').doc(hashedId).get();
          if (snap.exists) bannedDoc = snap;
        }
        if (!bannedDoc) {
          const snap = await db.collection('bannedNumbers').doc(normalized).get();
          if (snap.exists) bannedDoc = snap;
        }
        if (!bannedDoc && digitsOnlyLegacy) {
          const snap = await db.collection('bannedNumbers').doc(digitsOnlyLegacy).get();
          if (snap.exists) bannedDoc = snap;
        }
        if (bannedDoc) {
          if (batchCount >= BATCH_LIMIT) {
            await batch.commit();
            batch = db.batch();
            batchCount = 0;
          }
          batch.update(bannedDoc.ref, { originalUserName: 'Deleted User' });
          batchCount++;
        }
      }

      // Commit final anonymization batch
      if (batchCount > 0) {
        await batch.commit();
        logger.info(`✅ Anonymized documents (receipts: ${receiptsSnap.size}, redeemedRewards: ${redeemedSnap.size}, giftedRewardClaims: ${giftedClaimsSnap.size}, posts: ${postsSnap.size}, suspiciousFlags: ${suspiciousFlagsSnap.size})`);
      }

      // ========== PHASE 2: DELETION ==========
      logger.info(`🗑️ Phase 2: Deleting user data for ${uid}`);

      // Get all documents to delete in parallel
      const [pointsSnap, referrerSnap, referredSnap, notifSnap, scanAttemptsSnap] = await Promise.all([
        db.collection('pointsTransactions').where('userId', '==', uid).get(),
        db.collection('referrals').where('referrerUserId', '==', uid).get(),
        db.collection('referrals').where('referredUserId', '==', uid).get(),
        db.collection('notifications').where('userId', '==', uid).get(),
        db.collection('receiptScanAttempts').where('userId', '==', uid).get()
      ]);

      // Delete pointsTransactions
      if (!pointsSnap.empty) {
        let deleteBatch = db.batch();
        let deleteCount = 0;
        for (const doc of pointsSnap.docs) {
          if (deleteCount >= BATCH_LIMIT) {
            await deleteBatch.commit();
            deleteBatch = db.batch();
            deleteCount = 0;
          }
          deleteBatch.delete(doc.ref);
          deleteCount++;
        }
        if (deleteCount > 0) await deleteBatch.commit();
        logger.info(`✅ Deleted ${pointsSnap.size} pointsTransactions`);
      }

      // Tombstone referrals instead of deleting (keeps referrer/referred counts stable)
      // 1) Deleting user was the referred: anonymize referred side, keep referrerUserId
      let tombstoneCount = 0;
      let refBatch = db.batch();
      for (const doc of referredSnap.docs) {
        if (tombstoneCount >= BATCH_LIMIT) {
          await refBatch.commit();
          refBatch = db.batch();
          tombstoneCount = 0;
        }
        const data = doc.data();
        const isAwarded = data.status === 'awarded';
        const updates = {
          referredFirstName: 'Deleted User',
          referredDeleted: true,
          referredDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
          referredUserId: admin.firestore.FieldValue.delete()
        };
        if (!isAwarded) {
          updates.status = 'cancelled';
          updates.pointsTowards50 = 0;
        }
        refBatch.update(doc.ref, updates);
        tombstoneCount++;
      }
      if (tombstoneCount > 0) {
        await refBatch.commit();
        logger.info(`✅ Tombstoned ${referredSnap.size} referrals (deleted user was referred)`);
      }
      // 2) Deleting user was the referrer: anonymize referrer side, keep referredUserId
      refBatch = db.batch();
      tombstoneCount = 0;
      for (const doc of referrerSnap.docs) {
        if (tombstoneCount >= BATCH_LIMIT) {
          await refBatch.commit();
          refBatch = db.batch();
          tombstoneCount = 0;
        }
        const data = doc.data();
        const isAwarded = data.status === 'awarded';
        const updates = {
          referrerFirstName: 'Deleted User',
          referrerDeleted: true,
          referrerDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
          referrerUserId: admin.firestore.FieldValue.delete()
        };
        if (!isAwarded) {
          updates.status = 'cancelled';
          updates.pointsTowards50 = 0;
        }
        refBatch.update(doc.ref, updates);
        tombstoneCount++;
      }
      if (tombstoneCount > 0) {
        await refBatch.commit();
        logger.info(`✅ Tombstoned ${referrerSnap.size} referrals (deleted user was referrer)`);
      }

      // Delete notifications
      if (!notifSnap.empty) {
        let notifBatch = db.batch();
        let notifCount = 0;
        for (const doc of notifSnap.docs) {
          if (notifCount >= BATCH_LIMIT) {
            await notifBatch.commit();
            notifBatch = db.batch();
            notifCount = 0;
          }
          notifBatch.delete(doc.ref);
          notifCount++;
        }
        if (notifCount > 0) await notifBatch.commit();
        logger.info(`✅ Deleted ${notifSnap.size} notifications`);
      }

      // Delete receiptScanAttempts
      if (!scanAttemptsSnap.empty) {
        let scanBatch = db.batch();
        let scanCount = 0;
        for (const doc of scanAttemptsSnap.docs) {
          if (scanCount >= BATCH_LIMIT) {
            await scanBatch.commit();
            scanBatch = db.batch();
            scanCount = 0;
          }
          scanBatch.delete(doc.ref);
          scanCount++;
        }
        if (scanCount > 0) await scanBatch.commit();
        logger.info(`✅ Deleted ${scanAttemptsSnap.size} receiptScanAttempts`);
      }

      // Delete user subcollections (clientState, activity)
      const [clientStateSnap, activitySnap] = await Promise.all([
        db.collection('users').doc(uid).collection('clientState').get(),
        db.collection('users').doc(uid).collection('activity').get()
      ]);

      if (!clientStateSnap.empty || !activitySnap.empty) {
        const subBatch = db.batch();
        for (const doc of clientStateSnap.docs) {
          subBatch.delete(doc.ref);
        }
        for (const doc of activitySnap.docs) {
          subBatch.delete(doc.ref);
        }
        await subBatch.commit();
        logger.info(`✅ Deleted user subcollections (clientState: ${clientStateSnap.size}, activity: ${activitySnap.size})`);
      }

      // Delete userRiskScore if exists
      await db.collection('userRiskScores').doc(uid).delete().catch(() => {});
      logger.info(`✅ Deleted userRiskScore (if existed)`);

      // ========== PHASE 3: PROFILE PHOTO DELETION ==========
      if (profilePhotoURL) {
        try {
          const storage = admin.storage();
          const bucket = storage.bucket();
          
          // Extract file path from URL
          // URL format: https://firebasestorage.googleapis.com/v0/b/BUCKET/o/PATH?token=...
          // or gs://BUCKET/PATH
          let filePath = null;
          if (profilePhotoURL.includes('firebasestorage.googleapis.com')) {
            const match = profilePhotoURL.match(/\/o\/(.+?)\?/);
            if (match) {
              filePath = decodeURIComponent(match[1]);
            }
          } else if (profilePhotoURL.startsWith('gs://')) {
            filePath = profilePhotoURL.replace(/^gs:\/\/[^/]+\//, '');
          }

          if (filePath) {
            await bucket.file(filePath).delete();
            logger.info(`✅ Deleted profile photo: ${filePath}`);
          }
        } catch (storageErr) {
          // Non-critical - photo may already be deleted or URL invalid
          logger.info(`ℹ️ Profile photo deletion skipped: ${storageErr.message}`);
        }
      }

      // ========== PHASE 4: RECORD DELETION FOR RECREATE DETECTION ==========
      // Record deletion metadata to detect rapid delete→recreate patterns
      try {
        const userPhone = userData.phone || '';
        if (userPhone) {
          const phoneHash = hashPhoneNumber(userPhone);
          if (phoneHash) {
            // Record deletion timestamp for this phone hash
            const deletionRecordRef = db.collection('accountDeletions').doc(`${phoneHash}_${Date.now()}`);
            await deletionRecordRef.set({
              phoneHash,
              deletedAt: admin.firestore.FieldValue.serverTimestamp(),
              deletedUserId: uid,
              // Store device fingerprint if available (from request headers)
              deviceFingerprint: req.headers['x-device-fingerprint'] || null
            });
            
            // Also update abusePreventionHashes with deletion timestamp
            const abuseHashRef = db.collection('abusePreventionHashes').doc(phoneHash);
            await abuseHashRef.set({
              phoneHash,
              lastAccountDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
              lastDeletedUserId: uid
            }, { merge: true });
          }
        }
      } catch (deletionRecordError) {
        // Non-critical - log but don't fail deletion
        logger.error('⚠️ Error recording deletion metadata (non-blocking):', deletionRecordError);
      }

      // ========== PHASE 5: USER DOCUMENT DELETION ==========
      await db.collection('users').doc(uid).delete();
      logger.info(`✅ Deleted user document: ${uid}`);

      // ========== PHASE 6: FIREBASE AUTH USER DELETION ==========
      try {
        await admin.auth().deleteUser(uid);
        logger.info(`✅ Deleted Firebase Auth user: ${uid}`);
      } catch (authErr) {
        // Log but don't fail - Firestore data is already cleaned up
        logger.error(`⚠️ Error deleting Auth user (data already cleaned): ${authErr.message}`);
      }

      logger.info(`✅ Account deletion complete for user: ${uid}`);
      return res.json({ success: true });

    } catch (error) {
      logger.error('❌ Error in /user/delete-account:', error);
      res.status(500).json({ error: 'Failed to delete account' });
    }
  });

  /**
   * POST /admin/cleanup-expired-history
   *
   * Cleans up expired bannedAccountHistory records (older than 24 hours).
   * Can be called by admin or triggered on admin view load.
   *
   * Request: Requires admin Bearer token
   * Response: { deletedCount: number, message: string }
   */
  app.post('/admin/cleanup-expired-history', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();

      logger.info('🧹 Cleaning up expired banned account history...');

      // Query expired records
      const expiredSnap = await db.collection('bannedAccountHistory')
        .where('expiresAt', '<=', now)
        .get();

      if (expiredSnap.empty) {
        logger.info('✅ No expired history records found');
        return res.json({ deletedCount: 0, message: 'No expired records to clean up' });
      }

      // Delete in batches
      const batch = db.batch();
      let deletedCount = 0;
      
      for (const doc of expiredSnap.docs.slice(0, 450)) {
        batch.delete(doc.ref);
        deletedCount++;
      }

      await batch.commit();
      logger.info(`✅ Deleted ${deletedCount} expired history records`);

      return res.json({ 
        deletedCount, 
        message: `Cleaned up ${deletedCount} expired history record(s)` 
      });

    } catch (error) {
      logger.error('❌ Error in /admin/cleanup-expired-history:', error);
      res.status(500).json({ error: 'Failed to cleanup expired history' });
    }
  });

  /**
   * POST /users/cleanup-orphan-by-phone
   *
   * Cleans up orphaned user documents during signup.
   * When a user signs up with a phone number that has orphaned Firestore docs,
   * this endpoint deletes those orphans using Admin SDK (bypasses security rules).
   *
   * Request body: { phone: string, newUid: string }
   * Response: { deletedCount: number }
   */
  app.post('/users/cleanup-orphan-by-phone', async (req, res) => {
    try {
      // Verify the user's token
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
      if (!token) {
        return res.status(401).json({ error: 'Missing or invalid Authorization header' });
      }

      const decoded = await admin.auth().verifyIdToken(token);
      const callerUid = decoded.uid;

      const { phone, newUid } = req.body;
      if (!phone) {
        return res.status(400).json({ error: 'Phone number is required' });
      }

      // Verify the caller is the new user (for security)
      if (newUid && newUid !== callerUid) {
        return res.status(403).json({ error: 'UID mismatch' });
      }

      logger.info(`🧹 Cleaning up orphaned accounts for phone: ${phone}, newUid: ${callerUid}`);

      const db = admin.firestore();
      const auth = admin.auth();

      // Normalize phone number
      let normalizedPhone = phone.trim();
      const digits = normalizedPhone.replace(/[^\d]/g, '');
      if (digits.length === 10) {
        normalizedPhone = '+1' + digits;
      } else if (digits.length === 11 && digits.startsWith('1')) {
        normalizedPhone = '+' + digits;
      }

      // Find all user documents with this phone number
      const usersSnap = await db.collection('users')
        .where('phone', '==', normalizedPhone)
        .get();

      if (usersSnap.empty) {
        logger.info('✅ No orphaned accounts found');
        
        // Check for rapid delete→recreate patterns even if no orphans found
        try {
          const phoneHash = hashPhoneNumber(normalizedPhone);
          if (phoneHash) {
            const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
            const recentDeletions = await db.collection('accountDeletions')
              .where('phoneHash', '==', phoneHash)
              .where('deletedAt', '>=', admin.firestore.Timestamp.fromDate(oneWeekAgo))
              .orderBy('deletedAt', 'desc')
              .get();
            
            if (recentDeletions.size >= 2) {
              const service = new SuspiciousBehaviorService(db);
              await service.flagSuspiciousBehavior(callerUid, {
                flagType: 'account_recreation',
                severity: recentDeletions.size >= 4 ? 'high' : 'medium',
                description: `Rapid account deletion/recreation pattern: ${recentDeletions.size} deletions in last 7 days for this phone number`,
                evidence: {
                  phoneHash,
                  deletionCount: recentDeletions.size,
                  timeWindow: '7 days',
                  lastDeletion: recentDeletions.docs[0]?.data()?.deletedAt?.toDate?.()?.toISOString() || null
                }
              });
            }
          }
        } catch (detectionError) {
          logger.error('❌ Error checking delete/recreate pattern (non-blocking):', detectionError);
        }
        
        return res.json({ deletedCount: 0 });
      }

      let deletedCount = 0;
      const batch = db.batch();

      for (const doc of usersSnap.docs) {
        const docUid = doc.id;
        
        // Skip the current user's document
        if (docUid === callerUid) {
          logger.info(`ℹ️ Skipping current user: ${docUid}`);
          continue;
        }

        // Check if this UID has a corresponding Firebase Auth account
        try {
          await auth.getUser(docUid);
          // Auth account exists - this is not an orphan, skip it
          logger.info(`ℹ️ Skipping non-orphan (Auth exists): ${docUid}`);
        } catch (error) {
          if (error.code === 'auth/user-not-found') {
            // This is an orphaned document - delete it
            logger.info(`🗑️ Deleting orphaned user doc: ${docUid}`);
            batch.delete(doc.ref);
            deletedCount++;
          } else {
            logger.warn(`⚠️ Error checking user ${docUid}: ${error.code}`);
          }
        }
      }

      if (deletedCount > 0) {
        await batch.commit();
        logger.info(`✅ Deleted ${deletedCount} orphaned user document(s)`);
      }

      // Check for rapid delete→recreate patterns after cleanup
      try {
        const phoneHash = hashPhoneNumber(normalizedPhone);
        if (phoneHash) {
          const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
          const recentDeletions = await db.collection('accountDeletions')
            .where('phoneHash', '==', phoneHash)
            .where('deletedAt', '>=', admin.firestore.Timestamp.fromDate(oneWeekAgo))
            .orderBy('deletedAt', 'desc')
            .get();
          
          if (recentDeletions.size >= 2) {
            const service = new SuspiciousBehaviorService(db);
            await service.flagSuspiciousBehavior(callerUid, {
              flagType: 'account_recreation',
              severity: recentDeletions.size >= 4 ? 'high' : 'medium',
              description: `Rapid account deletion/recreation pattern: ${recentDeletions.size} deletions in last 7 days for this phone number (${deletedCount} orphaned accounts cleaned up)`,
              evidence: {
                phoneHash,
                deletionCount: recentDeletions.size,
                orphanedAccountsDeleted: deletedCount,
                timeWindow: '7 days',
                lastDeletion: recentDeletions.docs[0]?.data()?.deletedAt?.toDate?.()?.toISOString() || null
              }
            });
          }
        }
      } catch (detectionError) {
        logger.error('❌ Error checking delete/recreate pattern (non-blocking):', detectionError);
      }

      return res.json({ deletedCount });

    } catch (error) {
      logger.error('❌ Error in /users/cleanup-orphan-by-phone:', error);
      res.status(500).json({ error: 'Failed to cleanup orphaned accounts' });
    }
  });

  // ---------------------------------------------------------------------------
  // Staff-only Rewards Validation / Consumption (QR scanning)
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

  // Helper function to refund an expired reward
  async function refundExpiredReward(rewardRef, rewardData, db) {
    const pointsRefunded = rewardData.pointsRefunded === true;
    
    // Skip if already refunded
    if (pointsRefunded) {
      return { alreadyRefunded: true };
    }
    
    const userId = rewardData.userId;
    const pointsRequired = rewardData.pointsRequired || 0;
    
    if (!userId || pointsRequired <= 0) {
      throw new Error('Invalid reward data for refund');
    }
    
    // Get user's current points
    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      throw new Error('User not found for refund');
    }
    
    const userData = userDoc.data();
    const currentPoints = userData.points || 0;
    const newPointsBalance = currentPoints + pointsRequired;
    
    // Build transaction description
    let transactionDescription = `Points refunded - reward expired unused: ${rewardData.rewardTitle || 'Reward'}`;
    if (rewardData.selectedItemName) {
      transactionDescription = `Points refunded - reward expired unused: ${rewardData.selectedItemName}`;
      if (rewardData.selectedToppingName) {
        transactionDescription += ` with ${rewardData.selectedToppingName}`;
      }
      if (rewardData.selectedItemName2) {
        transactionDescription = `Points refunded - reward expired unused: Half and Half: ${rewardData.selectedItemName} + ${rewardData.selectedItemName2}`;
        if (rewardData.cookingMethod) {
          transactionDescription += ` (${rewardData.cookingMethod})`;
        }
      }
    }
    
    // Create points transaction for refund
    const pointsTransaction = {
      id: `refund_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      userId: userId,
      type: 'reward_expiration_refund',
      amount: pointsRequired,
      description: transactionDescription,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isEarned: true,
      redemptionCode: rewardData.redemptionCode || null,
      rewardTitle: rewardData.rewardTitle || null,
      ...(rewardData.selectedItemName && { selectedItemName: rewardData.selectedItemName }),
      ...(rewardData.selectedToppingName && { selectedToppingName: rewardData.selectedToppingName }),
      ...(rewardData.selectedItemName2 && { selectedItemName2: rewardData.selectedItemName2 }),
      ...(rewardData.cookingMethod && { cookingMethod: rewardData.cookingMethod })
    };
    
    // Perform database operations in a transaction
    await db.runTransaction(async (tx) => {
      // Re-check reward status to prevent race conditions
      const rewardSnapshot = await tx.get(rewardRef);
      if (!rewardSnapshot.exists) {
        throw new Error('Reward not found');
      }
      
      const snapshotData = rewardSnapshot.data() || {};
      if (snapshotData.isUsed === true) {
        throw new Error('Reward already used');
      }
      if (snapshotData.pointsRefunded === true) {
        throw new Error('Points already refunded');
      }
      
      // Update user points
      tx.update(userRef, { points: newPointsBalance });
      
      // Mark reward as refunded
      tx.update(rewardRef, { 
        pointsRefunded: true,
        refundedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      // Add points transaction
      const transactionRef = db.collection('pointsTransactions').doc(pointsTransaction.id);
      tx.set(transactionRef, pointsTransaction);
    });
    
    logger.info(`✅ Auto-refunded expired reward: ${pointsRequired} points to user ${userId}`);
    
    return {
      success: true,
      pointsRefunded: pointsRequired,
      newPointsBalance: newPointsBalance
    };
  }

  // Refund expired reward endpoint
  app.post('/refund-expired-reward', async (req, res) => {
    try {
      logger.info('💰 Received refund expired reward request');
      logger.info('📥 Request body:', JSON.stringify(req.body, null, 2));
      
      // Require authenticated user
      const userContext = await requireUser(req, res);
      if (!userContext) return;
      
      const { rewardId, redemptionCode } = req.body;
      
      if (!rewardId && !redemptionCode) {
        logger.info('❌ Missing required field: rewardId or redemptionCode');
        return res.status(400).json({ 
          error: 'Missing required field: rewardId or redemptionCode'
        });
      }
      
      const db = admin.firestore();
      let rewardRef;
      let rewardDoc;
      
      // Find reward by ID or redemption code
      if (rewardId) {
        rewardRef = db.collection('redeemedRewards').doc(rewardId);
        rewardDoc = await rewardRef.get();
      } else {
        // Find by redemption code
        const snapshot = await db
          .collection('redeemedRewards')
          .where('redemptionCode', '==', redemptionCode)
          .limit(1)
          .get();
        
        if (snapshot.empty) {
          logger.info('❌ Reward not found with redemption code:', redemptionCode);
          return res.status(404).json({ error: 'Reward not found' });
        }
        
        rewardRef = snapshot.docs[0].ref;
        rewardDoc = snapshot.docs[0];
      }
      
      if (!rewardDoc.exists) {
        logger.info('❌ Reward document not found');
        return res.status(404).json({ error: 'Reward not found' });
      }
      
      const data = rewardDoc.data() || {};
      const expiresAt = parseFirestoreDate(data.expiresAt);
      const isExpired = data.isExpired === true || (expiresAt ? expiresAt <= new Date() : false);
      const isUsed = data.isUsed === true;
      const pointsRefunded = data.pointsRefunded === true;
      
      // Validate that reward is eligible for refund
      if (isUsed) {
        logger.info('❌ Reward already used, cannot refund');
        return res.status(400).json({ 
          error: 'Reward already used, cannot refund',
          status: 'already_used'
        });
      }
      
      if (!isExpired) {
        logger.info('❌ Reward not expired yet, cannot refund');
        return res.status(400).json({ 
          error: 'Reward not expired yet, cannot refund',
          status: 'not_expired'
        });
      }
      
      if (pointsRefunded) {
        logger.info('✅ Points already refunded for this reward');
        return res.json({ 
          success: true,
          message: 'Points already refunded',
          alreadyRefunded: true,
          pointsRefunded: data.pointsRequired || 0
        });
      }
      
      const userId = data.userId;
      const pointsRequired = data.pointsRequired || 0;
      
      if (!userId || pointsRequired <= 0) {
        logger.info('❌ Invalid reward data: missing userId or pointsRequired');
        return res.status(400).json({ error: 'Invalid reward data' });
      }
      
      // Verify user can only refund their own rewards
      if (userId !== userContext.uid) {
        logger.info('❌ User attempted to refund another user\'s reward');
        return res.status(403).json({ error: 'You can only refund your own rewards' });
      }
      
      // Get user's current points
      const userRef = db.collection('users').doc(userId);
      const userDoc = await userRef.get();
      
      if (!userDoc.exists) {
        logger.info('❌ User not found:', userId);
        return res.status(404).json({ error: 'User not found' });
      }
      
      // Use helper function to perform refund
      const refundResult = await refundExpiredReward(rewardRef, data, db);
      
      if (refundResult.alreadyRefunded) {
        return res.json({ 
          success: true,
          message: 'Points already refunded',
          alreadyRefunded: true,
          pointsRefunded: data.pointsRequired || 0
        });
      }
      
      res.json({
        success: true,
        pointsRefunded: refundResult.pointsRefunded,
        newPointsBalance: refundResult.newPointsBalance,
        rewardTitle: data.rewardTitle || null,
        message: 'Points refunded successfully'
      });
      
    } catch (error) {
      logger.error('❌ Error refunding expired reward:', error);
      res.status(500).json({ 
        error: 'Failed to refund expired reward',
        details: error.message 
      });
    }
  });

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
      const status = rewardStatusFromData(data);

      // Auto-refund if expired and not already refunded
      if (status === 'expired' && data.isUsed !== true && data.pointsRefunded !== true) {
        try {
          await refundExpiredReward(bestDoc.ref, data, db);
        } catch (error) {
          logger.error('⚠️ Error auto-refunding expired reward during validate:', error);
          // Continue with response even if refund fails
        }
      }

      return res.json({
        status: status,
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
          selectedDrinkItemName: data.selectedDrinkItemName || null, // NEW: For Full Combo
          iceLevel: data.iceLevel || null,
          sugarLevel: data.sugarLevel || null
        }
      });
    } catch (error) {
      logger.error('❌ Error validating reward code:', error);
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
              selectedDrinkItemName: data.selectedDrinkItemName || null,
              iceLevel: data.iceLevel || null,
              sugarLevel: data.sugarLevel || null
            }
          };
        }

        if (status === 'expired') {
          // Mark expired for consistency
          tx.update(rewardRef, { isExpired: true });
          
          // Note: Refund will be handled after transaction commits
          // We can't do async refund inside transaction, so we'll do it after
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
              isUsed: data.isUsed === true,
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
              selectedDrinkItemName: data.selectedDrinkItemName || null,
              iceLevel: data.iceLevel || null,
              sugarLevel: data.sugarLevel || null
            },
            needsRefund: data.pointsRefunded !== true // Flag to trigger refund after transaction
          };
        }

        // OK -> consume
        tx.update(rewardRef, {
          isUsed: true,
          usedAt: admin.firestore.FieldValue.serverTimestamp(),
          usedBy: staffUid,
          usedByEmail: staffEmail,
          usedByRole: staffRole
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
            selectedDrinkItemName: data.selectedDrinkItemName || null,
            iceLevel: data.iceLevel || null,
            sugarLevel: data.sugarLevel || null
          }
        };
      });

      // Auto-refund if expired and not already refunded
      if (result.status === 'expired' && result.needsRefund) {
        try {
          // Re-fetch the reward data after transaction
          const rewardDoc = await rewardRef.get();
          if (rewardDoc.exists) {
            const rewardData = rewardDoc.data() || {};
            await refundExpiredReward(rewardRef, rewardData, db);
          }
        } catch (error) {
          logger.error('⚠️ Error auto-refunding expired reward during consume:', error);
          // Continue with response even if refund fails
        }
      }

      // Remove needsRefund flag from response
      if (result.needsRefund) {
        delete result.needsRefund;
      }

      return res.json(result);
    } catch (error) {
      logger.error('❌ Error consuming reward code:', error);
      return res.status(500).json({ error: 'Failed to consume reward code' });
    }
  });

  // ---------------------------------------------------------------------------
  // Admin Gift Rewards - Send Rewards to Customers
  // ---------------------------------------------------------------------------

  /**
   * POST /admin/rewards/gift
   * 
   * Send an existing reward to all customers or specific users.
   * 
   * Request body:
   * {
   *   rewardTitle: string (required)
   *   rewardDescription: string (required)
   *   rewardCategory: string (required)
   *   imageName: string | null (for existing rewards)
   *   targetType: 'all' | 'individual' (required)
   *   userIds: string[] (required if targetType is 'individual')
   *   expiresAt: string | null (ISO date string, optional)
   * }
   */
  app.post('/admin/rewards/gift', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { rewardTitle, rewardDescription, rewardCategory, imageName, targetType, userIds, expiresAt } = req.body;

      // Validate required fields
      if (!rewardTitle || typeof rewardTitle !== 'string' || rewardTitle.trim().length === 0) {
        return res.status(400).json({ error: 'rewardTitle is required' });
      }

      if (!rewardDescription || typeof rewardDescription !== 'string' || rewardDescription.trim().length === 0) {
        return res.status(400).json({ error: 'rewardDescription is required' });
      }

      if (!rewardCategory || typeof rewardCategory !== 'string' || rewardCategory.trim().length === 0) {
        return res.status(400).json({ error: 'rewardCategory is required' });
      }

      if (!targetType || !['all', 'individual'].includes(targetType)) {
        return res.status(400).json({ error: 'targetType must be "all" or "individual"' });
      }

      if (targetType === 'individual') {
        if (!Array.isArray(userIds) || userIds.length === 0) {
          return res.status(400).json({ error: 'userIds array is required for individual targeting' });
        }
      }

      const db = admin.firestore();
      const trimmedTitle = rewardTitle.trim();
      const trimmedDescription = rewardDescription.trim();

      // Parse expiration date if provided
      let expiresAtTimestamp = null;
      if (expiresAt) {
        const parsedDate = new Date(expiresAt);
        if (isNaN(parsedDate.getTime())) {
          return res.status(400).json({ error: 'Invalid expiresAt date format' });
        }
        expiresAtTimestamp = admin.firestore.Timestamp.fromDate(parsedDate);
      }

      // Create gifted reward document
      const giftedRewardRef = db.collection('giftedRewards').doc();
      const giftedRewardData = {
        type: targetType === 'all' ? 'broadcast' : 'individual',
        targetUserIds: targetType === 'all' ? null : userIds,
        rewardTitle: trimmedTitle,
        rewardDescription: trimmedDescription,
        rewardCategory: rewardCategory.trim(),
        pointsRequired: 0, // Always free
        imageName: imageName || null,
        imageURL: null, // Not used for existing rewards
        isCustom: false,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        sentByAdminId: adminContext.uid,
        expiresAt: expiresAtTimestamp,
        isActive: true
      };

      await giftedRewardRef.set(giftedRewardData);

      logger.info(`🎁 Admin ${adminContext.uid} sent gift reward: "${trimmedTitle}" to ${targetType === 'all' ? 'all customers' : `${userIds.length} users`}`);

      // Get target users
      let targetUserIds = [];
      if (targetType === 'all') {
        // Get all users (excluding employees)
        // Fetch all users and filter client-side to include those without isEmployee field
        const pageSize = 500;
        let lastDoc = null;
        const allUserDocs = [];

        while (true) {
          let query = db.collection('users').limit(pageSize);
          if (lastDoc) {
            query = query.startAfter(lastDoc);
          }

          const pageSnapshot = await query.get();
          if (pageSnapshot.empty) {
            break;
          }

          // Filter to exclude employees (include if isEmployee is false or undefined)
          for (const doc of pageSnapshot.docs) {
            const userData = doc.data() || {};
            if (userData.isEmployee !== true) {
              allUserDocs.push(doc);
            }
          }

          lastDoc = pageSnapshot.docs[pageSnapshot.docs.length - 1];
          if (pageSnapshot.docs.length < pageSize) {
            break;
          }
        }

        targetUserIds = allUserDocs.map(doc => doc.id);
        logger.info(`📋 Found ${targetUserIds.length} eligible users (excluding employees)`);
      } else {
        targetUserIds = userIds;
      }

      // Create notifications and send FCM push
      const notificationPromises = [];
      const fcmTokens = [];
      const userDocs = [];

      // Fetch user documents and FCM tokens
      const batchSize = 30;
      for (let i = 0; i < targetUserIds.length; i += batchSize) {
        const batch = targetUserIds.slice(i, i + batchSize);
        const batchSnapshot = await db.collection('users')
          .where(admin.firestore.FieldPath.documentId(), 'in', batch)
          .get();
        
        for (const doc of batchSnapshot.docs) {
          const userData = doc.data() || {};
          if (userData.fcmToken && typeof userData.fcmToken === 'string') {
            fcmTokens.push(userData.fcmToken);
          }
          userDocs.push({ id: doc.id, data: userData });
        }
      }

      // Create in-app notifications
      for (const user of userDocs) {
        const notifRef = db.collection('notifications').doc();
        notificationPromises.push(
          notifRef.set({
            userId: user.id,
            title: "You've received a gift!",
            body: `Dumpling House sent you a free ${trimmedTitle}. Tap to claim!`,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
            type: 'reward_gift',
            giftedRewardId: giftedRewardRef.id
          })
        );
      }

      // Send FCM push notifications
      if (fcmTokens.length > 0) {
        const messaging = admin.messaging();
        const message = {
          notification: {
            title: "You've received a gift!",
            body: `Dumpling House sent you a free ${trimmedTitle}. Tap to claim!`
          },
          data: {
            type: 'reward_gift',
            giftedRewardId: giftedRewardRef.id
          }
        };

        // Send in batches (FCM allows up to 500 per batch)
        const fcmBatchSize = 500;
        for (let i = 0; i < fcmTokens.length; i += fcmBatchSize) {
          const batchTokens = fcmTokens.slice(i, i + fcmBatchSize);
          messaging.sendEachForMulticast({
            ...message,
            tokens: batchTokens
          }).catch(err => {
            logger.warn('⚠️ Some FCM notifications failed:', err);
          });
        }
      }

      // Wait for notification documents to be created
      await Promise.all(notificationPromises).catch(err => {
        logError(err, req, { operation: 'gift_reward_notifications' });
      });

      logger.info(`✅ Gift reward sent: ${userDocs.length} notifications, ${fcmTokens.length} push notifications`);

      // Return success even if no users found (gift is still created and available)
      res.json({
        success: true,
        giftedRewardId: giftedRewardRef.id,
        notificationCount: userDocs.length,
        pushNotificationCount: fcmTokens.length,
        message: userDocs.length === 0 
          ? 'Gift reward created but no eligible users found. Users will see it when they open the app.'
          : undefined
      });

    } catch (error) {
      logger.error('❌ Error sending gift reward:', error);
      const errorMessage = error.message || error.toString();
      res.status(500).json({ error: `Failed to send gift reward: ${errorMessage}` });
    }
  });

  /**
   * POST /admin/rewards/gift/custom
   * 
   * Send a custom reward with optional uploaded image to all customers or specific users.
   * 
   * Multipart form:
   * - image: File (optional)
   * - rewardTitle: string (required)
   * - rewardDescription: string (required)
   * - rewardCategory: string (required)
   * - targetType: 'all' | 'individual' (required)
   * - userIds: string[] (JSON string, required if targetType is 'individual')
   * - expiresAt: string | null (ISO date string, optional)
   */
  app.post('/admin/rewards/gift/custom', upload.single('image'), async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { rewardTitle, rewardDescription, rewardCategory, targetType, userIds, expiresAt } = req.body;

      // Validate required fields
      if (!rewardTitle || typeof rewardTitle !== 'string' || rewardTitle.trim().length === 0) {
        // Clean up uploaded file if it exists
        if (req.file && fs.existsSync(req.file.path)) {
          fsPromises.unlink(req.file.path).catch(err => logger.error('Failed to delete file:', err));
        }
        return res.status(400).json({ error: 'rewardTitle is required' });
      }

      if (!rewardDescription || typeof rewardDescription !== 'string' || rewardDescription.trim().length === 0) {
        if (req.file && fs.existsSync(req.file.path)) {
          fsPromises.unlink(req.file.path).catch(err => logger.error('Failed to delete file:', err));
        }
        return res.status(400).json({ error: 'rewardDescription is required' });
      }

      if (!rewardCategory || typeof rewardCategory !== 'string' || rewardCategory.trim().length === 0) {
        if (req.file && fs.existsSync(req.file.path)) {
          fsPromises.unlink(req.file.path).catch(err => logger.error('Failed to delete file:', err));
        }
        return res.status(400).json({ error: 'rewardCategory is required' });
      }

      if (!targetType || !['all', 'individual'].includes(targetType)) {
        if (req.file && fs.existsSync(req.file.path)) {
          fsPromises.unlink(req.file.path).catch(err => logger.error('Failed to delete file:', err));
        }
        return res.status(400).json({ error: 'targetType must be "all" or "individual"' });
      }

      let parsedUserIds = [];
      if (targetType === 'individual') {
        try {
          parsedUserIds = JSON.parse(userIds || '[]');
        } catch (e) {
          if (req.file && fs.existsSync(req.file.path)) {
            fsPromises.unlink(req.file.path).catch(err => logger.error('Failed to delete file:', err));
          }
          return res.status(400).json({ error: 'userIds must be a valid JSON array' });
        }
        if (!Array.isArray(parsedUserIds) || parsedUserIds.length === 0) {
          if (req.file && fs.existsSync(req.file.path)) {
            fsPromises.unlink(req.file.path).catch(err => logger.error('Failed to delete file:', err));
          }
          return res.status(400).json({ error: 'userIds array is required for individual targeting' });
        }
      }

      const db = admin.firestore();
      const storage = admin.storage();
      
      // Create giftedRewardId first (used for both image upload and document creation)
      const giftedRewardId = db.collection('giftedRewards').doc().id;
      
      // Initialize imageURL as null (will be set if image is uploaded)
      let imageURL = null;
      
      // Upload image to Firebase Storage if provided
      if (req.file) {
        const bucket = storage.bucket('dumplinghouseapp.firebasestorage.app');
        const imageFileName = `gifted-rewards/${giftedRewardId}/image.jpg`;
        const file = bucket.file(imageFileName);

        const imageData = await fsPromises.readFile(req.file.path);
        await file.save(imageData, {
          metadata: {
            contentType: 'image/jpeg',
            metadata: {
              uploadedBy: adminContext.uid,
              uploadedAt: new Date().toISOString()
            }
          }
        });

        // Generate a signed URL that expires far in the future (10 years)
        // This avoids the "uniform bucket-level access" error from makePublic()
        const [signedUrl] = await file.getSignedUrl({
          action: 'read',
          expires: Date.now() + 10 * 365 * 24 * 60 * 60 * 1000, // 10 years
        });
        imageURL = signedUrl;

        // Clean up local file
        await fsPromises.unlink(req.file.path).catch(err => logger.error('Failed to delete file:', err));
      }

      // Parse expiration date if provided
      let expiresAtTimestamp = null;
      if (expiresAt) {
        const parsedDate = new Date(expiresAt);
        if (isNaN(parsedDate.getTime())) {
          return res.status(400).json({ error: 'Invalid expiresAt date format' });
        }
        expiresAtTimestamp = admin.firestore.Timestamp.fromDate(parsedDate);
      }

      // Create gifted reward document
      const giftedRewardRef = db.collection('giftedRewards').doc(giftedRewardId);
      const trimmedTitle = rewardTitle.trim();
      const trimmedDescription = rewardDescription.trim();

      const giftedRewardData = {
        type: targetType === 'all' ? 'broadcast' : 'individual',
        targetUserIds: targetType === 'all' ? null : parsedUserIds,
        rewardTitle: trimmedTitle,
        rewardDescription: trimmedDescription,
        rewardCategory: rewardCategory.trim(),
        pointsRequired: 0, // Always free
        imageName: null, // Not used for custom rewards
        imageURL: imageURL,
        isCustom: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        sentByAdminId: adminContext.uid,
        expiresAt: expiresAtTimestamp,
        isActive: true
      };

      await giftedRewardRef.set(giftedRewardData);

      logger.info(`🎁 Admin ${adminContext.uid} sent custom gift reward: "${trimmedTitle}" to ${targetType === 'all' ? 'all customers' : `${parsedUserIds.length} users`}`);

      // Get target users
      let targetUserIds = [];
      if (targetType === 'all') {
        // Get all users (excluding employees)
        // Fetch all users and filter client-side to include those without isEmployee field
        const pageSize = 500;
        let lastDoc = null;
        const allUserDocs = [];

        while (true) {
          let query = db.collection('users').limit(pageSize);
          if (lastDoc) {
            query = query.startAfter(lastDoc);
          }

          const pageSnapshot = await query.get();
          if (pageSnapshot.empty) {
            break;
          }

          // Filter to exclude employees (include if isEmployee is false or undefined)
          for (const doc of pageSnapshot.docs) {
            const userData = doc.data() || {};
            if (userData.isEmployee !== true) {
              allUserDocs.push(doc);
            }
          }

          lastDoc = pageSnapshot.docs[pageSnapshot.docs.length - 1];
          if (pageSnapshot.docs.length < pageSize) {
            break;
          }
        }

        targetUserIds = allUserDocs.map(doc => doc.id);
        logger.info(`📋 Found ${targetUserIds.length} eligible users (excluding employees)`);
      } else {
        targetUserIds = parsedUserIds;
      }

      // Create notifications and send FCM push
      const notificationPromises = [];
      const fcmTokens = [];
      const userDocs = [];

      // Fetch user documents and FCM tokens
      const batchSize = 30;
      for (let i = 0; i < targetUserIds.length; i += batchSize) {
        const batch = targetUserIds.slice(i, i + batchSize);
        const batchSnapshot = await db.collection('users')
          .where(admin.firestore.FieldPath.documentId(), 'in', batch)
          .get();
        
        for (const doc of batchSnapshot.docs) {
          const userData = doc.data() || {};
          if (userData.fcmToken && typeof userData.fcmToken === 'string') {
            fcmTokens.push(userData.fcmToken);
          }
          userDocs.push({ id: doc.id, data: userData });
        }
      }

      // Create in-app notifications
      for (const user of userDocs) {
        const notifRef = db.collection('notifications').doc();
        notificationPromises.push(
          notifRef.set({
            userId: user.id,
            title: "You've received a gift!",
            body: `Dumpling House sent you a free ${trimmedTitle}. Tap to claim!`,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
            type: 'reward_gift',
            giftedRewardId: giftedRewardRef.id
          })
        );
      }

      // Send FCM push notifications
      if (fcmTokens.length > 0) {
        const messaging = admin.messaging();
        const message = {
          notification: {
            title: "You've received a gift!",
            body: `Dumpling House sent you a free ${trimmedTitle}. Tap to claim!`
          },
          data: {
            type: 'reward_gift',
            giftedRewardId: giftedRewardRef.id
          }
        };

        // Send in batches (FCM allows up to 500 per batch)
        const fcmBatchSize = 500;
        for (let i = 0; i < fcmTokens.length; i += fcmBatchSize) {
          const batchTokens = fcmTokens.slice(i, i + fcmBatchSize);
          messaging.sendEachForMulticast({
            ...message,
            tokens: batchTokens
          }).catch(err => {
            logger.warn('⚠️ Some FCM notifications failed:', err);
          });
        }
      }

      // Wait for notification documents to be created
      await Promise.all(notificationPromises).catch(err => {
        logError(err, req, { operation: 'gift_reward_notifications' });
      });

      logger.info(`✅ Custom gift reward sent: ${userDocs.length} notifications, ${fcmTokens.length} push notifications`);

      // Return success even if no users found (gift is still created and available)
      res.json({
        success: true,
        giftedRewardId: giftedRewardRef.id,
        imageURL: imageURL,
        notificationCount: userDocs.length,
        pushNotificationCount: fcmTokens.length,
        message: userDocs.length === 0 
          ? 'Custom gift reward created but no eligible users found. Users will see it when they open the app.'
          : undefined
      });

    } catch (error) {
      logger.error('❌ Error sending custom gift reward:', error);
      // Clean up uploaded file if it still exists
      if (req.file && fs.existsSync(req.file.path)) {
        fsPromises.unlink(req.file.path).catch(err => logger.error('Failed to delete file:', err));
      }
      const errorMessage = error.message || error.toString();
      res.status(500).json({ error: `Failed to send custom gift reward: ${errorMessage}` });
    }
  });

  /**
   * GET /me/gifted-rewards
   * 
   * Get user's available gifted rewards (unclaimed broadcast rewards + individual gifts)
   */
  app.get('/me/gifted-rewards', async (req, res) => {
    try {
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
      if (!token) {
        return res.status(401).json({ error: 'Missing or invalid Authorization header' });
      }

      let uid;
      try {
        const decoded = await admin.auth().verifyIdToken(token);
        uid = decoded.uid;
      } catch (e) {
        return res.status(401).json({ error: 'Invalid auth token' });
      }

      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();

      // Get broadcast gifts (active, not expired, not yet claimed by this user)
      const broadcastGiftsSnapshot = await db.collection('giftedRewards')
        .where('type', '==', 'broadcast')
        .where('isActive', '==', true)
        .get();

      // Get individual gifts for this user
      const individualGiftsSnapshot = await db.collection('giftedRewards')
        .where('type', '==', 'individual')
        .where('targetUserIds', 'array-contains', uid)
        .where('isActive', '==', true)
        .get();

      // Get user's existing claims
      const claimsSnapshot = await db.collection('giftedRewardClaims')
        .where('userId', '==', uid)
        .get();

      // Build a map of giftedRewardId -> array of redeemedRewardIds (handle multiple claims)
      // Also track gifts with claims that have no redeemedRewardId (treat as claimed to be safe)
      const claimMap = new Map();
      const giftsWithInvalidClaims = new Set();
      
      for (const doc of claimsSnapshot.docs) {
        const data = doc.data();
        if (data.giftedRewardId) {
          if (data.redeemedRewardId) {
            // Valid claim with redeemedRewardId
            if (!claimMap.has(data.giftedRewardId)) {
              claimMap.set(data.giftedRewardId, []);
            }
            claimMap.get(data.giftedRewardId).push(data.redeemedRewardId);
          } else {
            // Claim exists but no redeemedRewardId - treat as claimed to be safe
            giftsWithInvalidClaims.add(data.giftedRewardId);
          }
        }
      }

      // Collect all redeemedRewardIds and batch fetch them
      const allRedeemedRewardIds = [];
      for (const redeemedRewardIds of claimMap.values()) {
        allRedeemedRewardIds.push(...redeemedRewardIds);
      }
      const redeemedRewardsMap = new Map();

      if (allRedeemedRewardIds.length > 0) {
        // Firestore 'in' query supports up to 30 items, so batch if needed
        const batchSize = 30;
        for (let i = 0; i < allRedeemedRewardIds.length; i += batchSize) {
          const batch = allRedeemedRewardIds.slice(i, i + batchSize);
          const redeemedSnapshot = await db.collection('redeemedRewards')
            .where(admin.firestore.FieldPath.documentId(), 'in', batch)
            .get();
          
          for (const redeemedDoc of redeemedSnapshot.docs) {
            redeemedRewardsMap.set(redeemedDoc.id, redeemedDoc.data());
          }
        }
      }

      // Build claimedGiftIds set - only include gifts where ANY redemption was used OR is still active
      // Start with gifts that have invalid claims (no redeemedRewardId)
      const claimedGiftIds = new Set(giftsWithInvalidClaims);
      
      for (const [giftId, redeemedRewardIds] of claimMap.entries()) {
        let hasActiveOrUsedRedemption = false;
        
        for (const redeemedRewardId of redeemedRewardIds) {
          const rewardData = redeemedRewardsMap.get(redeemedRewardId);
          
          if (!rewardData) {
            // Reward document doesn't exist - treat as claimed to be safe
            hasActiveOrUsedRedemption = true;
            break;
          }
          
          const isUsed = rewardData.isUsed === true;
          const expiresAt = parseFirestoreDate(rewardData.expiresAt);
          const isExpired = rewardData.isExpired === true || (expiresAt ? expiresAt <= new Date() : false);
          
          // If ANY redemption was used OR is still active, mark gift as claimed
          if (isUsed || !isExpired) {
            hasActiveOrUsedRedemption = true;
            break;
          }
        }
        
        // Only mark as claimed if at least one redemption was used or is still active
        if (hasActiveOrUsedRedemption) {
          claimedGiftIds.add(giftId);
        }
        // If all redemptions expired unused, the gift will reappear (giftId not added to set)
      }

      // Filter and combine gifts
      const availableGifts = [];

      // Process broadcast gifts
      for (const doc of broadcastGiftsSnapshot.docs) {
        const data = doc.data();
        const giftId = doc.id;

        // Skip if already claimed
        if (claimedGiftIds.has(giftId)) {
          continue;
        }

        // Check expiration
        if (data.expiresAt) {
          const expiresAt = data.expiresAt.toDate();
          if (expiresAt < new Date()) {
            continue; // Expired
          }
        }

        availableGifts.push({
          id: giftId,
          type: data.type || 'broadcast',
          targetUserIds: data.targetUserIds || null,
          rewardTitle: data.rewardTitle || '',
          rewardDescription: data.rewardDescription || '',
          rewardCategory: data.rewardCategory || '',
          pointsRequired: data.pointsRequired || 0,
          imageName: data.imageName || null,
          imageURL: data.imageURL || null,
          isCustom: data.isCustom || false,
          sentByAdminId: data.sentByAdminId || '',
          isActive: data.isActive !== false,
          sentAt: data.sentAt ? data.sentAt.toDate().toISOString() : null,
          expiresAt: data.expiresAt ? data.expiresAt.toDate().toISOString() : null
        });
      }

      // Process individual gifts
      for (const doc of individualGiftsSnapshot.docs) {
        const data = doc.data();
        const giftId = doc.id;

        // Skip if already claimed
        if (claimedGiftIds.has(giftId)) {
          continue;
        }

        // Check expiration
        if (data.expiresAt) {
          const expiresAt = data.expiresAt.toDate();
          if (expiresAt < new Date()) {
            continue; // Expired
          }
        }

        availableGifts.push({
          id: giftId,
          type: data.type || 'individual',
          targetUserIds: data.targetUserIds || null,
          rewardTitle: data.rewardTitle || '',
          rewardDescription: data.rewardDescription || '',
          rewardCategory: data.rewardCategory || '',
          pointsRequired: data.pointsRequired || 0,
          imageName: data.imageName || null,
          imageURL: data.imageURL || null,
          isCustom: data.isCustom || false,
          sentByAdminId: data.sentByAdminId || '',
          isActive: data.isActive !== false,
          sentAt: data.sentAt ? data.sentAt.toDate().toISOString() : null,
          expiresAt: data.expiresAt ? data.expiresAt.toDate().toISOString() : null
        });
      }

      // Sort by sentAt (newest first)
      availableGifts.sort((a, b) => {
        const aTime = a.sentAt ? new Date(a.sentAt).getTime() : 0;
        const bTime = b.sentAt ? new Date(b.sentAt).getTime() : 0;
        return bTime - aTime;
      });

      res.json({ gifts: availableGifts });

    } catch (error) {
      logger.error('❌ Error fetching gifted rewards:', error);
      res.status(500).json({ error: 'Failed to fetch gifted rewards' });
    }
  });

  /**
   * POST /rewards/claim-gift
   * 
   * Claim a gifted reward and create a redeemed reward entry
   * 
   * Request body:
   * {
   *   giftedRewardId: string (required)
   *   selectedItemId?: string
   *   selectedItemName?: string
   *   selectedToppingId?: string
   *   selectedToppingName?: string
   *   selectedItemId2?: string
   *   selectedItemName2?: string
   *   cookingMethod?: string
   *   drinkType?: string
   *   selectedDrinkItemId?: string
   *   selectedDrinkItemName?: string
   * }
   */
  app.post('/rewards/claim-gift', async (req, res) => {
    try {
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
      if (!token) {
        return res.status(401).json({ error: 'Missing or invalid Authorization header' });
      }

      let uid;
      try {
        const decoded = await admin.auth().verifyIdToken(token);
        uid = decoded.uid;
      } catch (e) {
        return res.status(401).json({ error: 'Invalid auth token' });
      }

      const { giftedRewardId, selectedItemId, selectedItemName, selectedToppingId, selectedToppingName, 
              selectedItemId2, selectedItemName2, cookingMethod, drinkType, selectedDrinkItemId, selectedDrinkItemName,
              iceLevel, sugarLevel } = req.body;

      if (!giftedRewardId || typeof giftedRewardId !== 'string') {
        return res.status(400).json({ error: 'giftedRewardId is required' });
      }

      const db = admin.firestore();

      // Verify gift exists and is available
      const giftDoc = await db.collection('giftedRewards').doc(giftedRewardId).get();
      if (!giftDoc.exists) {
        return res.status(404).json({ error: 'Gift reward not found' });
      }

      const giftData = giftDoc.data();
      
      // Check if active
      if (!giftData.isActive) {
        return res.status(400).json({ error: 'Gift reward is no longer active' });
      }

      // Check expiration
      if (giftData.expiresAt) {
        const expiresAt = giftData.expiresAt.toDate();
        if (expiresAt < new Date()) {
          return res.status(400).json({ error: 'Gift reward has expired' });
        }
      }

      // Check if already claimed - but allow re-claiming if ALL previous redemptions expired unused
      const existingClaims = await db.collection('giftedRewardClaims')
        .where('giftedRewardId', '==', giftedRewardId)
        .where('userId', '==', uid)
        .get();

      if (!existingClaims.empty) {
        // Check all existing claims to see if any have an active or used redemption
        // First, collect all redeemedRewardIds and batch fetch them
        const redeemedRewardIds = [];
        const claimsWithoutRedeemedReward = [];
        
        for (const claimDoc of existingClaims.docs) {
          const claimData = claimDoc.data();
          const redeemedRewardId = claimData.redeemedRewardId;
          
          if (!redeemedRewardId) {
            // No redeemedRewardId - treat as claimed to be safe
            claimsWithoutRedeemedReward.push(claimDoc);
          } else {
            redeemedRewardIds.push(redeemedRewardId);
          }
        }
        
        // If any claim has no redeemedRewardId, block re-claiming
        if (claimsWithoutRedeemedReward.length > 0) {
          return res.status(400).json({ error: 'Gift reward already claimed' });
        }
        
        // Batch fetch all redeemed rewards
        const redeemedRewardsMap = new Map();
        if (redeemedRewardIds.length > 0) {
          // Firestore 'in' query supports up to 30 items
          const batchSize = 30;
          for (let i = 0; i < redeemedRewardIds.length; i += batchSize) {
            const batch = redeemedRewardIds.slice(i, i + batchSize);
            const redeemedSnapshot = await db.collection('redeemedRewards')
              .where(admin.firestore.FieldPath.documentId(), 'in', batch)
              .get();
            
            for (const redeemedDoc of redeemedSnapshot.docs) {
              redeemedRewardsMap.set(redeemedDoc.id, redeemedDoc.data());
            }
          }
        }
        
        // Check each redemption status
        let hasActiveOrUsedRedemption = false;
        for (const redeemedRewardId of redeemedRewardIds) {
          const rewardData = redeemedRewardsMap.get(redeemedRewardId);
          
          if (!rewardData) {
            // Redeemed reward doesn't exist - treat as claimed to be safe
            hasActiveOrUsedRedemption = true;
            break;
          }
          
          const isUsed = rewardData.isUsed === true;
          const expiresAt = parseFirestoreDate(rewardData.expiresAt);
          const isExpired = rewardData.isExpired === true || (expiresAt ? expiresAt <= new Date() : false);
          
          // If this redemption was used OR is still active, block re-claiming
          if (isUsed || !isExpired) {
            hasActiveOrUsedRedemption = true;
            break;
          }
        }
        
        // If any redemption is active or used, block re-claiming
        if (hasActiveOrUsedRedemption) {
          return res.status(400).json({ error: 'Gift reward already claimed' });
        }
        // If all redemptions expired unused, allow re-claiming (continue)
      }

      // Generate redemption code (8 digits)
      const redemptionCode = Math.floor(10000000 + Math.random() * 90000000).toString();

      // Calculate expiration (15 minutes from now)
      const expiresAt = new Date();
      expiresAt.setMinutes(expiresAt.getMinutes() + 15);

      // Create redeemed reward entry (same structure as regular redemption)
      const redeemedRewardRef = db.collection('redeemedRewards').doc();
      const redeemedReward = {
        id: redeemedRewardRef.id,
        userId: uid,
        rewardTitle: giftData.rewardTitle,
        rewardDescription: giftData.rewardDescription,
        rewardCategory: giftData.rewardCategory,
        pointsRequired: 0, // Free gift
        redemptionCode: redemptionCode,
        redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        isExpired: false,
        isUsed: false,
        selectedItemId: selectedItemId || null,
        selectedItemName: selectedItemName || null,
        selectedToppingId: selectedToppingId || null,
        selectedToppingName: selectedToppingName || null,
        selectedItemId2: selectedItemId2 || null,
        selectedItemName2: selectedItemName2 || null,
        cookingMethod: cookingMethod || null,
        drinkType: drinkType || null,
        selectedDrinkItemId: selectedDrinkItemId || null,
        selectedDrinkItemName: selectedDrinkItemName || null,
        iceLevel: iceLevel || null,
        sugarLevel: sugarLevel || null,
        isGiftedReward: true,
        giftedRewardId: giftedRewardId
      };

      // Create claim record
      const claimRef = db.collection('giftedRewardClaims').doc();
      const claim = {
        giftedRewardId: giftedRewardId,
        userId: uid,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
        redeemedRewardId: redeemedRewardRef.id,
        isUsed: false,
        usedAt: null
      };

      // Build description for transaction (matching regular reward format)
      let transactionDescription = `Redeemed gift: ${giftData.rewardTitle}`;
      if (selectedItemName) {
        transactionDescription = `Redeemed gift: ${selectedItemName}`;
        if (selectedToppingName) {
          transactionDescription += ` with ${selectedToppingName}`;
        }
        if (selectedItemName2) {
          transactionDescription = `Redeemed gift: Half and Half: ${selectedItemName} + ${selectedItemName2}`;
          if (cookingMethod) {
            transactionDescription += ` (${cookingMethod})`;
          }
        } else if (cookingMethod) {
          transactionDescription += ` (${cookingMethod})`;
        }
      }

      // Create points transaction for history (amount 0 since it's a free gift)
      const pointsTransactionId = `gift_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const pointsTransaction = {
        id: pointsTransactionId,
        userId: uid,
        type: 'reward_redeemed',
        amount: 0, // Free gift, no points deducted
        description: transactionDescription,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          rewardTitle: giftData.rewardTitle,
          isGiftedReward: true,
          giftedRewardId: giftedRewardId,
          redemptionCode: redemptionCode,
          ...(selectedItemName && { selectedItemName }),
          ...(selectedToppingName && { selectedToppingName }),
          ...(selectedItemName2 && { selectedItemName2 }),
          ...(cookingMethod && { cookingMethod }),
          ...(drinkType && { drinkType }),
          ...(selectedDrinkItemName && { selectedDrinkItemName }),
          ...(iceLevel && { iceLevel }),
          ...(sugarLevel && { sugarLevel })
        }
      };

      // Write all three in a batch
      const batch = db.batch();
      batch.set(redeemedRewardRef, redeemedReward);
      batch.set(claimRef, claim);
      batch.set(db.collection('pointsTransactions').doc(pointsTransactionId), pointsTransaction);
      await batch.commit();

      logger.info(`✅ User ${uid} claimed gift reward ${giftedRewardId}, redemption code: ${redemptionCode}`);

      res.json({
        success: true,
        redemptionCode: redemptionCode,
        newPointsBalance: 0, // No points deducted for gifts
        pointsDeducted: 0,
        rewardTitle: giftData.rewardTitle,
        selectedItemName: selectedItemName || null,
        selectedToppingName: selectedToppingName || null,
        selectedItemName2: selectedItemName2 || null,
        cookingMethod: cookingMethod || null,
        drinkType: drinkType || null,
        selectedDrinkItemId: selectedDrinkItemId || null,
        selectedDrinkItemName: selectedDrinkItemName || null,
        iceLevel: iceLevel || null,
        sugarLevel: sugarLevel || null,
        expiresAt: expiresAt.toISOString(),
        message: 'Gift reward claimed successfully! Show the code to your cashier.',
        error: null
      });

    } catch (error) {
      logger.error('❌ Error claiming gift reward:', error);
      res.status(500).json({ error: 'Failed to claim gift reward' });
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

      logger.info(`📋 Fetched ${tiers.length} reward tiers`);
      res.json({ tiers });

    } catch (error) {
      logger.error('❌ Error fetching reward tiers:', error);
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
        logger.info(`✏️ Updated reward tier ${pointsRequired} with ${eligibleItems.length} items`);
      } else {
        // Create new tier
        docId = `tier_${pointsRequired}`;
        tierData.createdAt = admin.firestore.FieldValue.serverTimestamp();
        await db.collection('rewardTierItems').doc(docId).set(tierData);
        logger.info(`➕ Created reward tier ${pointsRequired} with ${eligibleItems.length} items`);
      }

      res.json({
        success: true,
        tierId: docId,
        pointsRequired,
        itemCount: eligibleItems.length,
        message: existingSnapshot.empty ? 'Reward tier created' : 'Reward tier updated'
      });

    } catch (error) {
      logger.error('❌ Error saving reward tier items:', error);
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
        logger.info(`➕ Created tier ${tierId} with item: ${itemName}`);
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
        logger.info(`➕ Added item ${itemName} to tier ${tierId}`);
      }

      res.json({
        success: true,
        tierId,
        pointsRequired: pointsRequired || null,
        itemAdded: itemName,
        message: 'Item added to reward tier'
      });

    } catch (error) {
      logger.error('❌ Error adding item to reward tier:', error);
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

      logger.info(`🗑️ Removed item ${itemId} from tier ${tierId}`);

      res.json({
        success: true,
        tierId,
        itemRemoved: itemId,
        message: 'Item removed from reward tier'
      });

    } catch (error) {
      logger.error('❌ Error removing item from reward tier:', error);
      res.status(500).json({ error: 'Failed to remove item from reward tier' });
    }
  });

  // List scanned receipts for Admin Office
  app.get('/admin/receipts', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();

      // Basic pagination: limit + optional startAfter cursor (createdAt ISO string + docId)
      const pageSize = Math.min(parseInt(req.query.limit, 10) || 50, 200);
      let startAfterCursor = null;
      if (req.query.startAfter) {
        try {
          // Parse cursor: "timestampISO|docId" format
          const parts = req.query.startAfter.split('|');
          if (parts.length === 2) {
            const timestamp = admin.firestore.Timestamp.fromDate(new Date(parts[0]));
            const docId = parts[1];
            // Get the document reference to use as cursor
            const cursorDoc = await db.collection('receipts').doc(docId).get();
            if (cursorDoc.exists) {
              startAfterCursor = cursorDoc;
            }
          }
        } catch (e) {
          logger.warn('⚠️ Invalid pagination cursor, ignoring:', e.message);
        }
      }

      // Use compound ordering for stable pagination (createdAt desc, then docId desc)
      // This prevents skipping/duplicating receipts with identical timestamps
      let query = db.collection('receipts')
        .orderBy('createdAt', 'desc')
        .orderBy(admin.firestore.FieldPath.documentId(), 'desc')
        .limit(pageSize);

      if (startAfterCursor) {
        query = query.startAfter(startAfterCursor);
      }

      let snapshot;
      try {
        snapshot = await query.get();
        logger.info(`📋 Admin receipts query returned ${snapshot.size} documents`);
      } catch (queryError) {
        logger.error('❌ Error executing receipts query:', queryError);
        // If orderBy fails, try without it (fallback)
        logger.info('⚠️ Attempting fallback query without orderBy...');
        const fallbackQuery = db.collection('receipts').limit(pageSize);
        snapshot = await fallbackQuery.get();
        logger.info(`📋 Fallback query returned ${snapshot.size} documents`);
      }

      const receipts = [];
      const userIds = new Set();

      snapshot.forEach(doc => {
        const data = doc.data() || {};
        if (data.userId) {
          userIds.add(data.userId);
        }
      });

      // Fetch basic user info for all involved users (batched for efficiency)
      const usersMap = {};
      if (userIds.size > 0) {
        const userIdArray = Array.from(userIds);
        // Firestore getAll() is limited to 30 items, so batch them
        const batchSize = 30;
        const userBatches = [];
        for (let i = 0; i < userIdArray.length; i += batchSize) {
          const batch = userIdArray.slice(i, i + batchSize);
          // Use getAll() for efficient batch reads (Admin SDK supports this)
          const userRefs = batch.map(userId => db.collection('users').doc(userId));
          userBatches.push(db.getAll(...userRefs));
        }
        
        const allUserDocs = await Promise.all(userBatches);
        for (const userDocs of allUserDocs) {
          for (const userDoc of userDocs) {
            if (userDoc.exists) {
              usersMap[userDoc.id] = userDoc.data() || {};
            }
          }
        }
      }

      snapshot.forEach(doc => {
        const data = doc.data() || {};
        const userInfo = data.userId ? (usersMap[data.userId] || {}) : {};

        // Use stored userName/userPhone if present (for deleted users), otherwise lookup from user
        receipts.push({
          id: doc.id,
          orderNumber: data.orderNumber || null,
          orderDate: data.orderDate || null,
          timestamp: data.createdAt ? data.createdAt.toDate().toISOString() : null,
          userId: data.userId || null,
          userName: data.userName || userInfo.firstName || userInfo.name || null,
          userPhone: data.userPhone || userInfo.phone || null
        });
      });

      // Generate pagination token: "createdAtISO|docId" format for stable cursor
      const lastDoc = snapshot.docs[snapshot.docs.length - 1];
      const nextPageToken = lastDoc && lastDoc.get('createdAt')
        ? `${lastDoc.get('createdAt').toDate().toISOString()}|${lastDoc.id}`
        : null;

      res.json({
        receipts,
        nextPageToken
      });
    } catch (error) {
      logger.error('❌ Error listing admin receipts:', error);
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

      const receiptRef = db.collection('receipts').doc(receiptId);
      const receiptDoc = await receiptRef.get();

      if (!receiptDoc.exists) {
        return res.status(404).json({ error: 'Receipt not found' });
      }

      const receiptData = receiptDoc.data() || {};
      const { orderNumber, orderDate, userId } = receiptData;

      const batch = db.batch();

      // Delete the receipt entry
      batch.delete(receiptRef);

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

      logger.info('🗑️ Admin deleted receipt and related records:', {
        receiptId,
        orderNumber,
        orderDate,
        userId,
        adminId: adminContext.uid
      });

      res.json({ success: true });
    } catch (error) {
      logger.error('❌ Error deleting admin receipt:', error);
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
      logger.info(`📨 Admin ${adminContext.uid} sending ${notificationTypeDescription} notification: "${trimmedTitle}" to ${recipientDescription}`);

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
        logger.info('⚠️ No valid FCM tokens found for notification');
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

      logger.info(`📱 Sending to ${tokensToSend.length} devices...`);

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
                logger.warn(`❌ FCM send failed for token ${idx}: ${resp.error?.code || 'unknown'}`);
              }
            });
          }
        } catch (fcmError) {
          logger.error('❌ FCM batch send error:', fcmError);
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

      logger.info(`✅ Notification sent: ${successCount} success, ${failureCount} failed`);

      res.json({
        success: true,
        successCount,
        failureCount,
        notificationId: sentNotifRef.id,
        totalTargeted: tokensToSend.length
      });

    } catch (error) {
      logger.error('❌ Error sending admin notification:', error);
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
      logger.error('❌ Error fetching notification history:', error);
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
        logger.info('📊 Admin stats served from cache');
        return res.json(adminStatsCache.data);
      }

      const db = admin.firestore();
      
      // Calculate date boundaries in Central Time (America/Chicago) for consistent local day tracking
      // This ensures "today" aligns with the restaurant's local calendar day
      // Can be overridden with STATS_TIMEZONE environment variable
      const statsTimezone = process.env.STATS_TIMEZONE || 'America/Chicago';
      const now = DateTime.now().setZone(statsTimezone);
      const todayStart = now.startOf('day').toJSDate();
      const tomorrowStart = now.startOf('day').plus({ days: 1 }).toJSDate();
      const weekAgo = now.startOf('day').minus({ days: 7 }).toJSDate();
      const monthStart = now.startOf('month').toJSDate();
      const nextMonthStart = now.startOf('month').plus({ months: 1 }).toJSDate();
      
      logger.info(`📊 Admin stats using timezone: ${statsTimezone}`);
      logger.info(`📊 Today boundaries: ${todayStart.toISOString()} to ${tomorrowStart.toISOString()}`);

      // Run all queries in parallel for efficiency
      // Use count() aggregation for large collections to avoid reading all documents
      const [
        usersCount,
        usersTodayCount,
        usersWeekCount,
        receiptsCount,
        receiptsTodayCount,
        receiptsWeekCount,
        rewardsCount,
        rewardsTodayCount,
        pointsSnapshot
      ] = await Promise.all([
        // Total users count (using count aggregation)
        db.collection('users').count().get().then(snap => snap.data().count),
        
        // New users today (using count aggregation)
        db.collection('users')
          .where('accountCreatedDate', '>=', todayStart)
          .count()
          .get()
          .then(snap => snap.data().count),
        
        // New users this week (using count aggregation)
        db.collection('users')
          .where('accountCreatedDate', '>=', weekAgo)
          .count()
          .get()
          .then(snap => snap.data().count),
        
        // Total receipts scanned (using count aggregation)
        db.collection('receipts').count().get().then(snap => snap.data().count),
        
        // Receipts scanned today (using count aggregation)
        db.collection('receipts')
          .where('createdAt', '>=', todayStart)
          .count()
          .get()
          .then(snap => snap.data().count),
        
        // Receipts scanned this week (using count aggregation)
        db.collection('receipts')
          .where('createdAt', '>=', weekAgo)
          .count()
          .get()
          .then(snap => snap.data().count),
        
        // Rewards redeemed this month (using count aggregation) - only rewards with usedAt
        // Changed from all-time to this month to match Admin Overview display
        db.collection('redeemedRewards')
          .where('isUsed', '==', true)
          .where('usedAt', '>=', admin.firestore.Timestamp.fromDate(monthStart))
          .where('usedAt', '<', admin.firestore.Timestamp.fromDate(nextMonthStart))
          .count()
          .get()
          .then(snap => snap.data().count),
        
        // Rewards redeemed today - only verified rewards scanned today
        // Use both lower and upper bounds to ensure we only count rewards within the current UTC day
        db.collection('redeemedRewards')
          .where('isUsed', '==', true)
          .where('usedAt', '>=', admin.firestore.Timestamp.fromDate(todayStart))
          .where('usedAt', '<', admin.firestore.Timestamp.fromDate(tomorrowStart))
          .count()
          .get()
          .then(snap => {
            const count = snap.data().count;
            logger.info(`📊 Rewards redeemed today query: found ${count} rewards (between ${todayStart.toISOString()} and ${tomorrowStart.toISOString()})`);
            return count;
          }),
        
        // Get aggregate points from users collection (still need full docs for sum)
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
        totalUsers: usersCount || 0,
        newUsersToday: usersTodayCount || 0,
        newUsersThisWeek: usersWeekCount || 0,
        totalReceipts: receiptsCount || 0,
        receiptsToday: receiptsTodayCount || 0,
        receiptsThisWeek: receiptsWeekCount || 0,
        totalRewardsRedeemed: rewardsCount || 0,
        rewardsRedeemedToday: rewardsTodayCount || 0,
        totalPointsDistributed
      };

      // Update cache
      adminStatsCache.data = stats;
      adminStatsCache.timestamp = cacheNow;

      logger.info('📊 Admin stats fetched and cached:', stats);
      res.json(stats);

    } catch (error) {
      logger.error('❌ Error fetching admin stats:', error);
      res.status(500).json({ error: 'Failed to fetch admin statistics' });
    }
  });

  /**
   * GET /admin/rewards/history/months
   * 
   * Get list of available months with reward counts for the month picker.
   * Returns months in descending order (most recent first).
   * 
   * Response:
   * {
   *   months: [
   *     { month: "2026-01", count: 142 },
   *     { month: "2025-12", count: 98 }
   *   ]
   * }
   */
  
  // Cache for months list (5 minute TTL)
  const rewardHistoryMonthsCache = {
    data: null,
    timestamp: null,
    ttl: 5 * 60 * 1000 // 5 minutes in milliseconds
  };

  app.get('/admin/rewards/history/months', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      // Check cache first
      const cacheNow = Date.now();
      if (rewardHistoryMonthsCache.data && rewardHistoryMonthsCache.timestamp && 
          (cacheNow - rewardHistoryMonthsCache.timestamp) < rewardHistoryMonthsCache.ttl) {
        logger.info('📅 Reward history months served from cache');
        return res.json(rewardHistoryMonthsCache.data);
      }

      const db = admin.firestore();
      
      // Efficiently get months by scanning in batches - only fetch usedAt field
      // This avoids loading all document data into memory
      const monthMap = new Map();
      let lastDoc = null;
      const batchSize = 1000; // Process 1000 at a time
      let hasMore = true;
      
      while (hasMore) {
        let query = db.collection('redeemedRewards')
          .where('isUsed', '==', true)
          .orderBy('usedAt', 'desc')
          .select('usedAt') // Only fetch the usedAt field to minimize data transfer
          .limit(batchSize);
        
        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }
        
        const batchSnapshot = await query.get();
        hasMore = batchSnapshot.size === batchSize;
        
        batchSnapshot.forEach(doc => {
          const data = doc.data();
          const usedAt = data.usedAt;
          
          if (usedAt && usedAt.toDate) {
            const date = usedAt.toDate();
            // Use UTC methods to match Firestore timestamp timezone
            const monthKey = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
            monthMap.set(monthKey, (monthMap.get(monthKey) || 0) + 1);
          }
        });
        
        if (hasMore && batchSnapshot.docs.length > 0) {
          lastDoc = batchSnapshot.docs[batchSnapshot.docs.length - 1];
        } else {
          hasMore = false;
        }
      }

      // Convert to array and sort by month descending
      const months = Array.from(monthMap.entries())
        .map(([month, count]) => ({ month, count }))
        .sort((a, b) => b.month.localeCompare(a.month));

      const result = { months };

      // Update cache
      rewardHistoryMonthsCache.data = result;
      rewardHistoryMonthsCache.timestamp = cacheNow;

      logger.info(`📅 Found ${months.length} months with redeemed rewards`);
      res.json(result);

    } catch (error) {
      logger.error('❌ Error fetching reward history months:', error);
      res.status(500).json({ error: 'Failed to fetch reward history months' });
    }
  });

  /**
   * GET /admin/rewards/history
   * 
   * Get paginated list of redeemed rewards for a specific month.
   * Includes user first names and summary statistics.
   * 
   * Query params:
   * - month: YYYY-MM format (required)
   * - limit: number of items per page (default: 50)
   * - startAfter: document ID for pagination cursor (optional)
   * 
   * Response:
   * {
   *   month: "2026-01",
   *   summary: {
   *     totalRewards: 142,
   *     totalPointsRedeemed: 28400,
   *     uniqueUsers: 87
   *   },
   *   rewards: [
   *     {
   *       id: "...",
   *       userFirstName: "John",
   *       rewardTitle: "Free Dumpling",
   *       selectedItemName: "Pork Dumpling",
   *       cookingMethod: "Steamed",
   *       pointsRequired: 200,
   *       usedAt: "2026-01-15T14:30:00Z"
   *     }
   *   ],
   *   hasMore: true,
   *   nextCursor: "doc_id_123"
   * }
   */
  
  app.get('/admin/rewards/history', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const month = req.query.month;
      if (!month || !/^\d{4}-\d{2}$/.test(month)) {
        return res.status(400).json({ error: 'Invalid month format. Expected YYYY-MM' });
      }

      const limit = parseInt(req.query.limit) || 50;
      const startAfter = req.query.startAfter;

      const db = admin.firestore();

      // Parse month boundaries in UTC to match Firestore timestamps
      const [year, monthNum] = month.split('-').map(Number);
      const monthStart = new Date(Date.UTC(year, monthNum - 1, 1, 0, 0, 0, 0));
      const monthEnd = new Date(Date.UTC(year, monthNum, 1, 0, 0, 0, 0)); // First day of next month

      // Build query
      let query = db.collection('redeemedRewards')
        .where('isUsed', '==', true)
        .where('usedAt', '>=', admin.firestore.Timestamp.fromDate(monthStart))
        .where('usedAt', '<', admin.firestore.Timestamp.fromDate(monthEnd))
        .orderBy('usedAt', 'desc')
        .limit(limit + 1); // Fetch one extra to check if there's more

      // Apply pagination cursor if provided
      if (startAfter) {
        const cursorDoc = await db.collection('redeemedRewards').doc(startAfter).get();
        if (cursorDoc.exists) {
          query = query.startAfter(cursorDoc);
        }
      }

      const rewardsSnapshot = await query.get();
      const hasMore = rewardsSnapshot.size > limit;
      const rewardsDocs = hasMore ? rewardsSnapshot.docs.slice(0, limit) : rewardsSnapshot.docs;

      // Get all unique user IDs
      const userIds = [...new Set(rewardsDocs.map(doc => doc.data().userId).filter(Boolean))];

      // Batch fetch user first names (Firestore 'in' queries support up to 10 items)
      const userNamesMap = new Map();
      if (userIds.length > 0) {
        const batchSize = 10;
        for (let i = 0; i < userIds.length; i += batchSize) {
          const batch = userIds.slice(i, i + batchSize);
          const usersSnapshot = await db.collection('users')
            .where(admin.firestore.FieldPath.documentId(), 'in', batch)
            .get();
          
          usersSnapshot.forEach(userDoc => {
            const userData = userDoc.data();
            const firstName = userData.firstName || userData.name?.split(' ')[0] || 'Unknown';
            userNamesMap.set(userDoc.id, firstName);
          });
        }
      }

      // Get summary statistics for the month using efficient queries
      // Use aggregation queries if available, otherwise use select() to minimize data transfer
      let totalRewards = 0;
      let totalPointsRedeemed = 0;
      const uniqueUserIds = new Set();
      
      // Process in batches to avoid loading all documents at once
      let summaryLastDoc = null;
      let summaryHasMore = true;
      const summaryBatchSize = 1000;
      
      while (summaryHasMore) {
        let summaryQuery = db.collection('redeemedRewards')
          .where('isUsed', '==', true)
          .where('usedAt', '>=', admin.firestore.Timestamp.fromDate(monthStart))
          .where('usedAt', '<', admin.firestore.Timestamp.fromDate(monthEnd))
          .select('pointsRequired', 'userId') // Only fetch needed fields
          .limit(summaryBatchSize);
        
        if (summaryLastDoc) {
          summaryQuery = summaryQuery.startAfter(summaryLastDoc);
        }
        
        const summaryBatch = await summaryQuery.get();
        summaryHasMore = summaryBatch.size === summaryBatchSize;
        totalRewards += summaryBatch.size;
        
        summaryBatch.forEach(doc => {
          const data = doc.data();
          if (typeof data.pointsRequired === 'number') {
            totalPointsRedeemed += data.pointsRequired;
          }
          if (data.userId) {
            uniqueUserIds.add(data.userId);
          }
        });
        
        if (summaryHasMore && summaryBatch.docs.length > 0) {
          summaryLastDoc = summaryBatch.docs[summaryBatch.docs.length - 1];
        } else {
          summaryHasMore = false;
        }
      }

      // Format rewards with user names
      const rewards = rewardsDocs.map(doc => {
        const data = doc.data();
        const userId = data.userId;
        const userFirstName = userId ? (userNamesMap.get(userId) || 'Unknown') : 'Unknown';
        
        return {
          id: doc.id,
          userFirstName,
          rewardTitle: data.rewardTitle || 'Reward',
          rewardDescription: data.rewardDescription || '',
          rewardCategory: data.rewardCategory || '',
          selectedItemName: data.selectedItemName || null,
          selectedItemName2: data.selectedItemName2 || null,
          selectedToppingName: data.selectedToppingName || null,
          cookingMethod: data.cookingMethod || null,
          drinkType: data.drinkType || null,
          pointsRequired: data.pointsRequired || 0,
          redemptionCode: data.redemptionCode || '',
          usedAt: data.usedAt?.toDate?.().toISOString() || null
        };
      });

      const result = {
        month,
        summary: {
          totalRewards,
          totalPointsRedeemed,
          uniqueUsers: uniqueUserIds.size
        },
        rewards,
        hasMore,
        nextCursor: hasMore && rewardsDocs.length > 0 ? rewardsDocs[rewardsDocs.length - 1].id : null
      };

      logger.info(`📊 Fetched ${rewards.length} rewards for ${month} (hasMore: ${hasMore})`);
      res.json(result);

    } catch (error) {
      logger.error('❌ Error fetching reward history:', error);
      res.status(500).json({ error: 'Failed to fetch reward history' });
    }
  });

  /**
   * GET /admin/rewards/history/all-time-summary
   * 
   * Get all-time summary statistics for reward history page header.
   * Returns total rewards, total points redeemed, and unique users.
   */
  app.get('/admin/rewards/history/all-time-summary', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();
      
      // Use SAME batching pattern as monthly summary for consistency
      let totalRewards = 0;
      let totalPointsRedeemed = 0;
      const uniqueUserIds = new Set();
      let summaryLastDoc = null;
      let summaryHasMore = true;
      const summaryBatchSize = 1000;
      
      while (summaryHasMore) {
        let summaryQuery = db.collection('redeemedRewards')
          .where('isUsed', '==', true)
          .orderBy('usedAt', 'desc') // Required for startAfter pagination
          .select('pointsRequired', 'userId') // Only fetch needed fields
          .limit(summaryBatchSize);
        
        if (summaryLastDoc) {
          summaryQuery = summaryQuery.startAfter(summaryLastDoc);
        }
        
        const summaryBatch = await summaryQuery.get();
        summaryHasMore = summaryBatch.size === summaryBatchSize;
        totalRewards += summaryBatch.size;
        
        summaryBatch.forEach(doc => {
          const data = doc.data();
          if (typeof data.pointsRequired === 'number') {
            totalPointsRedeemed += data.pointsRequired;
          }
          if (data.userId) {
            uniqueUserIds.add(data.userId);
          }
        });
        
        if (summaryHasMore && summaryBatch.docs.length > 0) {
          summaryLastDoc = summaryBatch.docs[summaryBatch.docs.length - 1];
        } else {
          summaryHasMore = false;
        }
      }

      res.json({
        totalRewards,
        totalPointsRedeemed,
        uniqueUsers: uniqueUserIds.size
      });

    } catch (error) {
      logger.error('❌ Error fetching all-time summary:', error);
      res.status(500).json({ error: 'Failed to fetch all-time summary' });
    }
  });

  /**
   * GET /admin/rewards/history/all-time
   * 
   * Get paginated list of all redeemed rewards (all-time, no date filter).
   * Includes user first names and summary statistics.
   */
  app.get('/admin/rewards/history/all-time', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const limit = parseInt(req.query.limit) || 50;
      const startAfter = req.query.startAfter;

      const db = admin.firestore();

      // Build query - SAME as monthly but NO date filter
      let query = db.collection('redeemedRewards')
        .where('isUsed', '==', true)
        .orderBy('usedAt', 'desc')
        .limit(limit + 1); // Fetch one extra to check if there's more

      // Apply pagination cursor if provided
      if (startAfter) {
        const cursorDoc = await db.collection('redeemedRewards').doc(startAfter).get();
        if (cursorDoc.exists) {
          query = query.startAfter(cursorDoc);
        }
      }

      const rewardsSnapshot = await query.get();
      const hasMore = rewardsSnapshot.size > limit;
      const rewardsDocs = hasMore ? rewardsSnapshot.docs.slice(0, limit) : rewardsSnapshot.docs;

      // Get all unique user IDs
      const userIds = [...new Set(rewardsDocs.map(doc => doc.data().userId).filter(Boolean))];

      // Batch fetch user first names (Firestore 'in' queries support up to 10 items)
      const userNamesMap = new Map();
      if (userIds.length > 0) {
        const batchSize = 10;
        for (let i = 0; i < userIds.length; i += batchSize) {
          const batch = userIds.slice(i, i + batchSize);
          const usersSnapshot = await db.collection('users')
            .where(admin.firestore.FieldPath.documentId(), 'in', batch)
            .get();
          
          usersSnapshot.forEach(userDoc => {
            const userData = userDoc.data();
            const firstName = userData.firstName || userData.name?.split(' ')[0] || 'Unknown';
            userNamesMap.set(userDoc.id, firstName);
          });
        }
      }

      // Get summary statistics using SAME batching pattern as monthly endpoint
      let totalRewards = 0;
      let totalPointsRedeemed = 0;
      const uniqueUserIds = new Set();
      
      let summaryLastDoc = null;
      let summaryHasMore = true;
      const summaryBatchSize = 1000;
      
      while (summaryHasMore) {
        let summaryQuery = db.collection('redeemedRewards')
          .where('isUsed', '==', true)
          .orderBy('usedAt', 'desc') // Required for startAfter pagination
          .select('pointsRequired', 'userId')
          .limit(summaryBatchSize);
        
        if (summaryLastDoc) {
          summaryQuery = summaryQuery.startAfter(summaryLastDoc);
        }
        
        const summaryBatch = await summaryQuery.get();
        summaryHasMore = summaryBatch.size === summaryBatchSize;
        totalRewards += summaryBatch.size;
        
        summaryBatch.forEach(doc => {
          const data = doc.data();
          if (typeof data.pointsRequired === 'number') {
            totalPointsRedeemed += data.pointsRequired;
          }
          if (data.userId) {
            uniqueUserIds.add(data.userId);
          }
        });
        
        if (summaryHasMore && summaryBatch.docs.length > 0) {
          summaryLastDoc = summaryBatch.docs[summaryBatch.docs.length - 1];
        } else {
          summaryHasMore = false;
        }
      }

      // Format rewards with user names
      const rewards = rewardsDocs.map(doc => {
        const data = doc.data();
        const userId = data.userId;
        const userFirstName = userId ? (userNamesMap.get(userId) || 'Unknown') : 'Unknown';
        
        return {
          id: doc.id,
          userFirstName,
          rewardTitle: data.rewardTitle || 'Reward',
          rewardDescription: data.rewardDescription || '',
          rewardCategory: data.rewardCategory || '',
          selectedItemName: data.selectedItemName || null,
          selectedItemName2: data.selectedItemName2 || null,
          selectedToppingName: data.selectedToppingName || null,
          cookingMethod: data.cookingMethod || null,
          drinkType: data.drinkType || null,
          pointsRequired: data.pointsRequired || 0,
          redemptionCode: data.redemptionCode || '',
          usedAt: data.usedAt?.toDate?.().toISOString() || null
        };
      });

      const result = {
        month: 'all-time',
        summary: {
          totalRewards,
          totalPointsRedeemed,
          uniqueUsers: uniqueUserIds.size
        },
        rewards,
        hasMore,
        nextCursor: hasMore && rewardsDocs.length > 0 ? rewardsDocs[rewardsDocs.length - 1].id : null
      };

      logger.info(`📊 Fetched ${rewards.length} all-time rewards (hasMore: ${hasMore})`);
      res.json(result);

    } catch (error) {
      logger.error('❌ Error fetching all-time reward history:', error);
      res.status(500).json({ error: 'Failed to fetch all-time reward history' });
    }
  });

  /**
   * GET /admin/rewards/history/this-year
   * 
   * Get paginated list of redeemed rewards for the current year.
   * Includes user first names and summary statistics.
   */
  app.get('/admin/rewards/history/this-year', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const limit = parseInt(req.query.limit) || 50;
      const startAfter = req.query.startAfter;

      const db = admin.firestore();

      // Calculate year boundaries (same pattern as month boundaries)
      const now = new Date();
      const yearStart = new Date(Date.UTC(now.getUTCFullYear(), 0, 1, 0, 0, 0, 0));
      const nextYearStart = new Date(Date.UTC(now.getUTCFullYear() + 1, 0, 1, 0, 0, 0, 0));

      // Build query - SAME as monthly but with year boundaries
      let query = db.collection('redeemedRewards')
        .where('isUsed', '==', true)
        .where('usedAt', '>=', admin.firestore.Timestamp.fromDate(yearStart))
        .where('usedAt', '<', admin.firestore.Timestamp.fromDate(nextYearStart))
        .orderBy('usedAt', 'desc')
        .limit(limit + 1); // Fetch one extra to check if there's more

      // Apply pagination cursor if provided
      if (startAfter) {
        const cursorDoc = await db.collection('redeemedRewards').doc(startAfter).get();
        if (cursorDoc.exists) {
          query = query.startAfter(cursorDoc);
        }
      }

      const rewardsSnapshot = await query.get();
      const hasMore = rewardsSnapshot.size > limit;
      const rewardsDocs = hasMore ? rewardsSnapshot.docs.slice(0, limit) : rewardsSnapshot.docs;

      // Get all unique user IDs
      const userIds = [...new Set(rewardsDocs.map(doc => doc.data().userId).filter(Boolean))];

      // Batch fetch user first names (Firestore 'in' queries support up to 10 items)
      const userNamesMap = new Map();
      if (userIds.length > 0) {
        const batchSize = 10;
        for (let i = 0; i < userIds.length; i += batchSize) {
          const batch = userIds.slice(i, i + batchSize);
          const usersSnapshot = await db.collection('users')
            .where(admin.firestore.FieldPath.documentId(), 'in', batch)
            .get();
          
          usersSnapshot.forEach(userDoc => {
            const userData = userDoc.data();
            const firstName = userData.firstName || userData.name?.split(' ')[0] || 'Unknown';
            userNamesMap.set(userDoc.id, firstName);
          });
        }
      }

      // Get summary statistics using SAME batching pattern as monthly endpoint
      let totalRewards = 0;
      let totalPointsRedeemed = 0;
      const uniqueUserIds = new Set();
      
      let summaryLastDoc = null;
      let summaryHasMore = true;
      const summaryBatchSize = 1000;
      
      while (summaryHasMore) {
        let summaryQuery = db.collection('redeemedRewards')
          .where('isUsed', '==', true)
          .where('usedAt', '>=', admin.firestore.Timestamp.fromDate(yearStart))
          .where('usedAt', '<', admin.firestore.Timestamp.fromDate(nextYearStart))
          .orderBy('usedAt', 'desc') // Required for startAfter pagination
          .select('pointsRequired', 'userId')
          .limit(summaryBatchSize);
        
        if (summaryLastDoc) {
          summaryQuery = summaryQuery.startAfter(summaryLastDoc);
        }
        
        const summaryBatch = await summaryQuery.get();
        summaryHasMore = summaryBatch.size === summaryBatchSize;
        totalRewards += summaryBatch.size;
        
        summaryBatch.forEach(doc => {
          const data = doc.data();
          if (typeof data.pointsRequired === 'number') {
            totalPointsRedeemed += data.pointsRequired;
          }
          if (data.userId) {
            uniqueUserIds.add(data.userId);
          }
        });
        
        if (summaryHasMore && summaryBatch.docs.length > 0) {
          summaryLastDoc = summaryBatch.docs[summaryBatch.docs.length - 1];
        } else {
          summaryHasMore = false;
        }
      }

      // Format rewards with user names
      const rewards = rewardsDocs.map(doc => {
        const data = doc.data();
        const userId = data.userId;
        const userFirstName = userId ? (userNamesMap.get(userId) || 'Unknown') : 'Unknown';
        
        return {
          id: doc.id,
          userFirstName,
          rewardTitle: data.rewardTitle || 'Reward',
          rewardDescription: data.rewardDescription || '',
          rewardCategory: data.rewardCategory || '',
          selectedItemName: data.selectedItemName || null,
          selectedItemName2: data.selectedItemName2 || null,
          selectedToppingName: data.selectedToppingName || null,
          cookingMethod: data.cookingMethod || null,
          drinkType: data.drinkType || null,
          pointsRequired: data.pointsRequired || 0,
          redemptionCode: data.redemptionCode || '',
          usedAt: data.usedAt?.toDate?.().toISOString() || null
        };
      });

      const result = {
        month: 'this-year',
        summary: {
          totalRewards,
          totalPointsRedeemed,
          uniqueUsers: uniqueUserIds.size
        },
        rewards,
        hasMore,
        nextCursor: hasMore && rewardsDocs.length > 0 ? rewardsDocs[rewardsDocs.length - 1].id : null
      };

      logger.info(`📊 Fetched ${rewards.length} rewards for this year (hasMore: ${hasMore})`);
      res.json(result);

    } catch (error) {
      logger.error('❌ Error fetching this-year reward history:', error);
      res.status(500).json({ error: 'Failed to fetch this-year reward history' });
    }
  });

  // Rate limiter for ban check endpoint (IP-based since it's called before auth)
  // Prevents phone number enumeration attacks
  const banCheckLimiter = createRateLimiter({
    keyFn: (req) => getClientIp(req),
    windowMs: 60_000,
    max: 10, // 10 requests per minute per IP
    errorCode: 'BAN_CHECK_RATE_LIMITED'
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
   *   isBanned: boolean,
   *   hasUserProfile: boolean
   * }
   */
  app.get('/check-ban-status', banCheckLimiter, async (req, res) => {
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
        logger.warn(`⚠️ Phone normalization warning: ${phone} -> ${normalizedPhone} (expected +1XXXXXXXXXX)`);
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

      // Check whether there is an existing Firestore user profile for this phone number.
      // This supports the UX where banned users can still sign in to delete their account,
      // but if their account is already deleted (no profile exists), we block OTP.
      let hasUserProfile = false;
      try {
        const primaryProfileSnap = await db
          .collection('users')
          .where('phone', '==', normalizedPhone)
          .limit(1)
          .get();
        hasUserProfile = !primaryProfileSnap.empty;

        if (!hasUserProfile) {
          // Try legacy formats if the profile was stored without "+" or without country code.
          const digitsOnly = normalizedPhone.replace('+', '');
          const last10 = digitsOnly.slice(-10);
          const legacyCandidates = [digitsOnly, last10].filter(Boolean);

          for (const candidate of legacyCandidates) {
            const legacySnap = await db
              .collection('users')
              .where('phone', '==', candidate)
              .limit(1)
              .get();
            if (!legacySnap.empty) {
              hasUserProfile = true;
              break;
            }
          }
        }
      } catch (profileErr) {
        // Fail closed for profile existence (conservative): if we cannot verify,
        // treat as "profile exists" so we don't accidentally lock users out due to server issues.
        logger.warn('⚠️ Error checking hasUserProfile in /check-ban-status:', profileErr?.message || profileErr);
        hasUserProfile = true;
      }

      res.json({ isBanned, hasUserProfile });
    } catch (error) {
      logger.error('❌ Error checking ban status:', error);
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

      // Store bans under hashed doc IDs to reduce enumeration risk
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

      logger.info(`🚫 User ${userId} (${normalizedPhone}) banned by ${adminContext.email}`);
      res.json({ success: true, phone: normalizedPhone });
    } catch (error) {
      logger.error('❌ Error banning user:', error);
      res.status(500).json({ error: 'Failed to ban user' });
    }
  });

  /**
   * POST /admin/ban-phone
   * 
   * Ban a phone number directly. Searches for existing accounts
   * with this phone number and marks them as banned if found.
   * 
   * Body:
   * {
   *   phone: string,
   *   reason: string (optional)
   * }
   * 
   * Response:
   * {
   *   success: true,
   *   phone: string,
   *   existingAccountFound: boolean,
   *   bannedUserId: string | null,
   *   bannedUserName: string | null
   * }
   */
  app.post('/admin/ban-phone', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { phone, reason } = req.body;
      if (!phone || typeof phone !== 'string') {
        return res.status(400).json({ error: 'phone is required' });
      }

      const db = admin.firestore();
      
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

      // Search for existing users with this phone number
      const usersQuery = await db.collection('users')
        .where('phone', '==', normalizedPhone)
        .limit(1)
        .get();

      let existingAccountFound = false;
      let bannedUserId = null;
      let bannedUserName = null;

      if (!usersQuery.empty) {
        // Found existing account(s) - ban the first one (should only be one)
        const userDoc = usersQuery.docs[0];
        const userData = userDoc.data();
        
        bannedUserId = userDoc.id;
        bannedUserName = userData.firstName || 'Unknown';
        existingAccountFound = true;

        // Mark user as banned
        await db.collection('users').doc(bannedUserId).update({
          isBanned: true
        });
      }

      // Add to bannedNumbers collection
      const bannedData = {
        phone: normalizedPhone,
        bannedAt: admin.firestore.FieldValue.serverTimestamp(),
        bannedByUserId: adminContext.uid,
        bannedByEmail: adminContext.email || '',
        originalUserId: bannedUserId,
        originalUserName: bannedUserName,
        reason: reason || null
      };

      await db.collection('bannedNumbers').doc(bannedDocId).set(bannedData);

      // Best-effort cleanup of legacy doc IDs (migration)
      const digitsOnlyLegacy = normalizedPhone.replace('+', '');
      await Promise.all([
        db.collection('bannedNumbers').doc(normalizedPhone).delete().catch(() => {}),
        db.collection('bannedNumbers').doc(digitsOnlyLegacy).delete().catch(() => {})
      ]);

      logger.info(`🚫 Phone number ${normalizedPhone} banned by ${adminContext.email}${existingAccountFound ? ` (existing account: ${bannedUserId})` : ' (no existing account)'}`);
      
      res.json({
        success: true,
        phone: normalizedPhone,
        existingAccountFound,
        bannedUserId,
        bannedUserName
      });
    } catch (error) {
      logger.error('❌ Error banning phone number:', error);
      res.status(500).json({ error: 'Failed to ban phone number' });
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
        const docSnap = await db.collection('bannedNumbers').doc(bannedDocId).get();
        if (docSnap.exists) bannedDoc = docSnap;
      }
      if (!bannedDoc) {
        const docSnap = await db.collection('bannedNumbers').doc(normalizedPhone).get();
        if (docSnap.exists) bannedDoc = docSnap;
      }
      if (!bannedDoc) {
        const docSnap = await db.collection('bannedNumbers').doc(digitsOnlyLegacy).get();
        if (docSnap.exists) bannedDoc = docSnap;
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

      logger.info(`✅ Phone number ${normalizedPhone} unbanned by ${adminContext.email}`);
      res.json({ success: true });
    } catch (error) {
      logger.error('❌ Error unbanning number:', error);
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

      const limit = parseInt(req.query.limit) || 50;
      const startAfter = req.query.startAfter;

      const db = admin.firestore();

      // Build query
      let query = db.collection('bannedNumbers')
        .orderBy('bannedAt', 'desc')
        .limit(limit + 1); // Fetch one extra to check if there's more

      // Apply pagination cursor if provided
      if (startAfter) {
        const cursorDoc = await db.collection('bannedNumbers').doc(startAfter).get();
        if (cursorDoc.exists) {
          query = query.startAfter(cursorDoc);
        }
      }

      const snapshot = await query.get();
      const hasMore = snapshot.size > limit;
      const bannedDocs = hasMore ? snapshot.docs.slice(0, limit) : snapshot.docs;

      // Format banned numbers
      const bannedNumbers = bannedDocs.map(doc => {
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
        nextCursor: hasMore && bannedDocs.length > 0 ? bannedDocs[bannedDocs.length - 1].id : null
      };

      logger.info(`📋 Fetched ${bannedNumbers.length} banned numbers (hasMore: ${hasMore})`);
      res.json(result);
    } catch (error) {
      logger.error('❌ Error fetching banned numbers:', error);
      res.status(500).json({ error: 'Failed to fetch banned numbers' });
    }
  });

  /**
   * GET /admin/suspicious-flags
   * 
   * Get paginated list of suspicious behavior flags.
   * 
   * Query params:
   * - limit: number of items per page (default: 50)
   * - startAfter: cursor for pagination
   * - status: filter by status (pending, reviewed, dismissed, action_taken)
   * - severity: filter by severity (low, medium, high, critical)
   * - flagType: filter by flag type
   */
  app.get('/admin/suspicious-flags', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const db = admin.firestore();
      const limit = parseInt(req.query.limit) || 50;
      const status = req.query.status;
      const severity = req.query.severity;
      const flagType = req.query.flagType;

      // Helper function to format flag data
      const formatFlag = async (doc) => {
        const data = doc.data();
        const userId = data.userId;
        
        // Get user info
        let userInfo = null;
        if (userId) {
          try {
            const userDoc = await db.collection('users').doc(userId).get();
            if (userDoc.exists) {
              const userData = userDoc.data();
              userInfo = {
                id: userId,
                firstName: userData.firstName || '',
                lastName: userData.lastName || '',
                phone: userData.phone || '',
                email: userData.email || '',
                points: userData.points || 0
              };
            }
          } catch (err) {
            logger.error(`Error fetching user ${userId}:`, err);
          }
        }

        return {
          id: doc.id,
          userId,
          flagType: data.flagType,
          severity: data.severity,
          riskScore: data.riskScore,
          description: data.description,
          evidence: data.evidence || {},
          createdAt: data.createdAt?.toDate?.().toISOString() || null,
          status: data.status,
          reviewedBy: data.reviewedBy || null,
          reviewedAt: data.reviewedAt?.toDate?.().toISOString() || null,
          reviewNotes: data.reviewNotes || null,
          actionTaken: data.actionTaken || null,
          userInfo
        };
      };

      let snapshot;
      let flagDocs = [];
      let hasMore = false;

      try {
        // Try the indexed query first
        let query = db.collection('suspiciousFlags').orderBy('createdAt', 'desc');

        if (status) {
          query = query.where('status', '==', status);
        }
        if (severity) {
          query = query.where('severity', '==', severity);
        }
        if (flagType) {
          query = query.where('flagType', '==', flagType);
        }

        // Pagination
        if (req.query.startAfter) {
          const cursorDoc = await db.collection('suspiciousFlags').doc(req.query.startAfter).get();
          if (cursorDoc.exists) {
            query = query.startAfter(cursorDoc);
          }
        }

        snapshot = await query.limit(limit + 1).get();
        hasMore = snapshot.size > limit;
        flagDocs = hasMore ? snapshot.docs.slice(0, limit) : snapshot.docs;
        
        logger.info(`✅ Indexed query succeeded: ${flagDocs.length} flags`);
      } catch (queryError) {
        // Check if it's an index error
        const isIndexError = queryError.message && (
          queryError.message.includes('index') ||
          queryError.message.includes('requires an index') ||
          queryError.code === 9 || // FAILED_PRECONDITION
          queryError.code === 'failed-precondition'
        );

        if (isIndexError) {
          logger.warn('⚠️ Index not ready, using fallback query:', queryError.message);
          
          // Fallback: Fetch all flags (with reasonable limit), filter and sort in memory
          const maxFallbackLimit = 1000; // Reasonable limit for in-memory processing
          const allFlagsSnapshot = await db.collection('suspiciousFlags')
            .limit(maxFallbackLimit)
            .get();

          logger.info(`📋 Fallback: Fetched ${allFlagsSnapshot.size} flags for client-side filtering`);

          // Filter in memory
          let filteredDocs = allFlagsSnapshot.docs.filter(doc => {
            const data = doc.data();
            if (status && data.status !== status) return false;
            if (severity && data.severity !== severity) return false;
            if (flagType && data.flagType !== flagType) return false;
            return true;
          });

          // Sort by createdAt descending
          filteredDocs.sort((a, b) => {
            const aTime = a.data().createdAt?.toDate?.() || new Date(0);
            const bTime = b.data().createdAt?.toDate?.() || new Date(0);
            return bTime - aTime; // Descending
          });

          // Apply pagination
          let startIndex = 0;
          if (req.query.startAfter) {
            const startAfterIndex = filteredDocs.findIndex(doc => doc.id === req.query.startAfter);
            if (startAfterIndex >= 0) {
              startIndex = startAfterIndex + 1;
            }
          }

          const endIndex = startIndex + limit;
          flagDocs = filteredDocs.slice(startIndex, endIndex);
          hasMore = endIndex < filteredDocs.length;

          logger.info(`✅ Fallback query: ${flagDocs.length} flags after filtering (hasMore: ${hasMore})`);
        } else {
          // Re-throw non-index errors
          throw queryError;
        }
      }

      // Get user details for each flag
      const flags = await Promise.all(flagDocs.map(formatFlag));

      const result = {
        flags,
        hasMore,
        nextCursor: hasMore && flagDocs.length > 0 ? flagDocs[flagDocs.length - 1].id : null
      };

      logger.info(`📋 Fetched ${flags.length} suspicious flags (hasMore: ${hasMore})`);
      res.json(result);
    } catch (error) {
      logger.error('❌ Error fetching suspicious flags:', error);
      res.status(500).json({ 
        error: 'Failed to fetch suspicious flags',
        message: error.message || 'Unknown error'
      });
    }
  });

  /**
   * POST /admin/suspicious-flags/:id/review
   * 
   * Review a suspicious flag and take action.
   * 
   * Body:
   * - action: 'dismiss' | 'watch' | 'restrict' | 'ban'
   * - notes: optional review notes
   */
  app.post('/admin/suspicious-flags/:id/review', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { id } = req.params;
      const { action, notes } = req.body;

      if (!['dismiss', 'watch', 'restrict', 'ban'].includes(action)) {
        return res.status(400).json({ error: 'Invalid action. Must be: dismiss, watch, restrict, or ban' });
      }

      const db = admin.firestore();
      const flagRef = db.collection('suspiciousFlags').doc(id);
      const flagDoc = await flagRef.get();

      if (!flagDoc.exists) {
        return res.status(404).json({ error: 'Flag not found' });
      }

      const flagData = flagDoc.data();
      const userId = flagData.userId;

      const updateData = {
        status: action === 'dismiss' ? 'dismissed' : 'action_taken',
        reviewedBy: adminContext.uid,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        reviewNotes: notes || null,
        actionTaken: action
      };

      await flagRef.update(updateData);

      // Take action based on review decision
      if (action === 'watch') {
        // Update user risk score watch status
        await db.collection('userRiskScores').doc(userId).set({
          watchStatus: 'watching'
        }, { merge: true });
      } else if (action === 'restrict') {
        // Mark user as restricted (can be used to limit earning)
        await db.collection('userRiskScores').doc(userId).set({
          watchStatus: 'restricted'
        }, { merge: true });
      } else if (action === 'ban') {
        // Ban the user
        const userDoc = await db.collection('users').doc(userId).get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          const phone = userData.phone;
          
          if (phone) {
            const normalized = normalizePhoneForBannedNumbers(phone) || phone;
            const digitsOnlyLegacy = (normalized || '').replace('+', '');
            const bannedDocId = hashBannedNumbersDocId(normalized);
            if (!bannedDocId) {
              throw new Error('Failed to compute ban hash');
            }

            // Ban the phone number (hashed doc ID)
            await db.collection('bannedNumbers').doc(bannedDocId).set({
              phone: normalized,
              bannedAt: admin.firestore.FieldValue.serverTimestamp(),
              bannedByEmail: adminContext.userData.email || 'admin',
              originalUserId: userId,
              originalUserName: `${userData.firstName || ''} ${userData.lastName || ''}`.trim() || 'Unknown',
              reason: `Flagged for suspicious behavior: ${flagData.flagType}`
            });

            // Best-effort cleanup of legacy doc IDs
            await Promise.all([
              db.collection('bannedNumbers').doc(normalized).delete().catch(() => {}),
              digitsOnlyLegacy ? db.collection('bannedNumbers').doc(digitsOnlyLegacy).delete().catch(() => {}) : Promise.resolve()
            ]);
          }
        }
      }

      // Update risk score after action
      const service = new SuspiciousBehaviorService(db);
      await service.updateUserRiskScore(userId);

      logger.info(`✅ Admin ${adminContext.uid} reviewed flag ${id} with action: ${action}`);
      res.json({ success: true, message: `Flag ${action}ed successfully` });
    } catch (error) {
      logger.error('❌ Error reviewing flag:', error);
      res.status(500).json({ error: 'Failed to review flag' });
    }
  });

  /**
   * GET /admin/user-risk-score/:userId
   * 
   * Get user's risk profile including risk score and flag history.
   */
  app.get('/admin/user-risk-score/:userId', async (req, res) => {
    try {
      const adminContext = await requireAdmin(req, res);
      if (!adminContext) return;

      const { userId } = req.params;
      const db = admin.firestore();
      const service = new SuspiciousBehaviorService(db);

      const profile = await service.getUserRiskProfile(userId);

      if (!profile) {
        return res.status(404).json({ error: 'User risk profile not found' });
      }

      res.json(profile);
    } catch (error) {
      logger.error('❌ Error fetching user risk score:', error);
      res.status(500).json({ error: 'Failed to fetch user risk score' });
    }
  });
}

// ---------------------------------------------------------------------------
// Suspicious Behavior Detection Service
// ---------------------------------------------------------------------------

class SuspiciousBehaviorService {
  constructor(db) {
    this.db = db;
  }

  /**
   * Create a device fingerprint hash from device info
   */
  createDeviceFingerprint(deviceInfo) {
    const crypto = require('crypto');
    const data = JSON.stringify({
      vendorId: deviceInfo.vendorId || '',
      platform: deviceInfo.platform || '',
      model: deviceInfo.model || '',
      screenWidth: deviceInfo.screenWidth || 0,
      screenHeight: deviceInfo.screenHeight || 0,
      timezone: deviceInfo.timezone || ''
    });
    return crypto.createHash('sha256').update(data).digest('hex');
  }

  /**
   * Store device fingerprint and check for multi-account abuse
   */
  async recordDeviceFingerprint(userId, deviceInfo, ipAddress = null) {
    try {
      const fingerprintHash = this.createDeviceFingerprint(deviceInfo);
      const fingerprintRef = this.db.collection('deviceFingerprints').doc(fingerprintHash);
      
      const fingerprintDoc = await fingerprintRef.get();
      const now = admin.firestore.FieldValue.serverTimestamp();
      
      if (fingerprintDoc.exists) {
        const data = fingerprintDoc.data();
        const associatedUserIds = data.associatedUserIds || [];
        
        // Check if this user is already associated
        if (!associatedUserIds.includes(userId)) {
          // New user on same device - potential multi-account
          associatedUserIds.push(userId);
          
          await fingerprintRef.update({
            associatedUserIds,
            lastSeen: now,
            lastIp: ipAddress
          });
          
          // Flag if multiple users on same device
          if (associatedUserIds.length >= 2) {
            const severity = associatedUserIds.length >= 3 ? 'critical' : 'high';
            const otherAccounts = associatedUserIds.filter(id => id !== userId);
            
            // Flag the NEW account (current user)
            await this.flagSuspiciousBehavior(userId, {
              flagType: 'device_reuse',
              severity,
              description: `Device fingerprint shared with ${otherAccounts.length} other account(s)`,
              evidence: {
                fingerprintHash,
                associatedUserIds: otherAccounts,
                deviceInfo,
                totalAccountsOnDevice: associatedUserIds.length
              }
            });
            
            // Also flag ALL existing accounts on this device
            // This ensures all accounts get flagged when device reuse is detected
            for (const existingUserId of otherAccounts) {
              await this.flagSuspiciousBehavior(existingUserId, {
                flagType: 'device_reuse',
                severity,
                description: `Device fingerprint shared with ${associatedUserIds.length - 1} other account(s)`,
                evidence: {
                  fingerprintHash,
                  associatedUserIds: associatedUserIds.filter(id => id !== existingUserId),
                  deviceInfo,
                  totalAccountsOnDevice: associatedUserIds.length,
                  newAccountDetected: userId
                }
              });
            }
          }
        } else {
          // Update last seen
          await fingerprintRef.update({
            lastSeen: now,
            lastIp: ipAddress
          });
        }
      } else {
        // First time seeing this device
        await fingerprintRef.set({
          hash: fingerprintHash,
          associatedUserIds: [userId],
          firstSeen: now,
          lastSeen: now,
          platform: deviceInfo.platform || 'unknown',
          deviceModel: deviceInfo.model || 'unknown',
          lastIp: ipAddress
        });
      }
      
      return fingerprintHash;
    } catch (error) {
      logger.error('❌ Error recording device fingerprint:', error);
      return null;
    }
  }

  /**
   * Check receipt velocity and patterns
   */
  async checkReceiptPatterns(userId, receiptData) {
    try {
      const now = new Date();
      const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      
      // Get recent receipts
      const recentReceipts = await this.db.collection('receipts')
        .where('userId', '==', userId)
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .orderBy('createdAt', 'desc')
        .get();
      
      const receipts = recentReceipts.docs.map(doc => ({
        id: doc.id,
        ...doc.data(),
        createdAt: doc.data().createdAt?.toDate()
      }));
      
      // Check velocity (receipts in last 24 hours)
      const receiptsLast24h = receipts.filter(r => r.createdAt >= oneDayAgo);
      if (receiptsLast24h.length > 3) {
        await this.flagSuspiciousBehavior(userId, {
          flagType: 'receipt_velocity',
          severity: receiptsLast24h.length > 5 ? 'high' : 'medium',
          description: `${receiptsLast24h.length} receipts submitted in last 24 hours`,
          evidence: {
            count: receiptsLast24h.length,
            receipts: receiptsLast24h.map(r => ({
              orderNumber: r.orderNumber,
              orderTotal: r.orderTotal,
              createdAt: r.createdAt?.toISOString()
            }))
          }
        });
      }
      
      // Check sequential order numbers (same day)
      const todayReceipts = receipts.filter(r => {
        const receiptDate = r.createdAt;
        return receiptDate && receiptDate.toDateString() === now.toDateString();
      });
      
      if (todayReceipts.length >= 2) {
        const orderNumbers = todayReceipts
          .map(r => parseInt(r.orderNumber))
          .filter(n => !isNaN(n))
          .sort((a, b) => a - b);
        
        // Check if order numbers are suspiciously close
        for (let i = 0; i < orderNumbers.length - 1; i++) {
          if (orderNumbers[i + 1] - orderNumbers[i] <= 5) {
            await this.flagSuspiciousBehavior(userId, {
              flagType: 'receipt_pattern',
              severity: 'medium',
              description: 'Sequential order numbers detected on same day',
              evidence: {
                orderNumbers,
                receipts: todayReceipts.map(r => ({
                  orderNumber: r.orderNumber,
                  orderTotal: r.orderTotal
                }))
              }
            });
            break;
          }
        }
      }
      
      // Check for same total amounts (potential duplicate pattern)
      const totalCounts = {};
      receipts.forEach(r => {
        const total = r.orderTotal;
        totalCounts[total] = (totalCounts[total] || 0) + 1;
      });
      
      for (const [total, count] of Object.entries(totalCounts)) {
        if (count >= 3) {
          await this.flagSuspiciousBehavior(userId, {
            flagType: 'receipt_pattern',
            severity: 'low',
            description: `Same receipt total ($${total}) appears ${count} times`,
            evidence: {
              total: parseFloat(total),
              count
            }
          });
          break;
        }
      }
      
      // Check for edge-case timing (consistently at 48-hour boundary)
      if (receipts.length >= 3) {
        const submissionTimes = receipts.map(r => r.createdAt?.getHours() || 0);
        const avgHour = submissionTimes.reduce((a, b) => a + b, 0) / submissionTimes.length;
        // If all receipts submitted at similar times, could indicate gaming the system
        const variance = submissionTimes.reduce((sum, h) => sum + Math.pow(h - avgHour, 2), 0) / submissionTimes.length;
        if (variance < 2 && receipts.length >= 3) {
          await this.flagSuspiciousBehavior(userId, {
            flagType: 'receipt_pattern',
            severity: 'low',
            description: 'Receipts submitted at consistent times (potential automation)',
            evidence: {
              averageHour: avgHour,
              variance,
              count: receipts.length
            }
          });
        }
      }
      
      // Check rejection rate
      const scanAttempts = await this.db.collection('receiptScanAttempts')
        .where('userId', '==', userId)
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .get();
      
      const attempts = scanAttempts.docs.map(doc => doc.data());
      const failures = attempts.filter(a => !a.success).length;
      const totalAttempts = attempts.length;
      
      if (totalAttempts > 0 && failures >= 2 && (failures / totalAttempts) > 0.3) {
        await this.flagSuspiciousBehavior(userId, {
          flagType: 'receipt_pattern',
          severity: 'high',
          description: `High rejection rate: ${failures}/${totalAttempts} failed attempts in last 7 days`,
          evidence: {
            failures,
            totalAttempts,
            rejectionRate: (failures / totalAttempts).toFixed(2)
          }
        });
      }
      
    } catch (error) {
      logger.error('❌ Error checking receipt patterns:', error);
    }
  }

  /**
   * Check referral abuse patterns
   */
  async checkReferralPatterns(userId, referralData) {
    try {
      const now = new Date();
      const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      
      // Check referral velocity (accepting multiple referrals)
      const recentReferrals = await this.db.collection('referrals')
        .where('referredUserId', '==', userId)
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(oneDayAgo))
        .get();
      
      if (recentReferrals.size > 1) {
        await this.flagSuspiciousBehavior(userId, {
          flagType: 'referral_abuse',
          severity: 'high',
          description: `Multiple referrals accepted in 24 hours (should only be one)`,
          evidence: {
            count: recentReferrals.size,
            referrals: recentReferrals.docs.map(doc => ({
              id: doc.id,
              referrerId: doc.data().referrerUserId,
              createdAt: doc.data().createdAt?.toDate()?.toISOString()
            }))
          }
        });
      }
      
      // Check for circular referral patterns
      const userReferral = await this.db.collection('referrals')
        .where('referredUserId', '==', userId)
        .limit(1)
        .get();
      
      if (!userReferral.empty) {
        const referrerId = userReferral.docs[0].data().referrerUserId;
        
        // Check if referrer was referred by this user (circular)
        const circularCheck = await this.db.collection('referrals')
          .where('referrerUserId', '==', userId)
          .where('referredUserId', '==', referrerId)
          .limit(1)
          .get();
        
        if (!circularCheck.empty) {
          await this.flagSuspiciousBehavior(userId, {
            flagType: 'referral_abuse',
            severity: 'critical',
            description: 'Circular referral pattern detected',
            evidence: {
              referrerId,
              pattern: 'circular'
            }
          });
        }
      }
      
      // Check if user hit 50 points threshold suspiciously fast
      const userDoc = await this.db.collection('users').doc(userId).get();
      if (userDoc.exists) {
        const userData = userDoc.data();
        const accountCreated = userData.createdAt?.toDate();
        const points = userData.points || 0;
        
        if (accountCreated && points >= 50) {
          const timeToThreshold = (now - accountCreated) / (1000 * 60 * 60); // hours
          if (timeToThreshold < 1) {
            await this.flagSuspiciousBehavior(userId, {
              flagType: 'referral_abuse',
              severity: 'high',
              description: 'Reached 50 point threshold within 1 hour of account creation',
              evidence: {
                points,
                hoursToThreshold: timeToThreshold.toFixed(2),
                accountCreated: accountCreated.toISOString()
              }
            });
          }
        }
      }
      
      // Check referrer pattern (user referring many people)
      const referralsByUser = await this.db.collection('referrals')
        .where('referrerUserId', '==', userId)
        .get();
      
      if (referralsByUser.size > 10) {
        // Check how many reached threshold
        const awardedCount = referralsByUser.docs.filter(doc => 
          doc.data().status === 'awarded'
        ).length;
        
        const thresholdRate = awardedCount / referralsByUser.size;
        if (thresholdRate > 0.5) {
          await this.flagSuspiciousBehavior(userId, {
            flagType: 'referral_abuse',
            severity: 'medium',
            description: `High referral success rate: ${awardedCount}/${referralsByUser.size} reached threshold`,
            evidence: {
              totalReferrals: referralsByUser.size,
              awardedCount,
              thresholdRate: thresholdRate.toFixed(2)
            }
          });
        }
      }
      
    } catch (error) {
      logger.error('❌ Error checking referral patterns:', error);
    }
  }

  /**
   * Check for new account bonus abuse (welcome + referral + receipt all within 1 hour)
   */
  async checkNewAccountBonusPattern(userId) {
    try {
      const userDoc = await this.db.collection('users').doc(userId).get();
      if (!userDoc.exists) return;
      
      const userData = userDoc.data();
      const accountCreated = userData.createdAt?.toDate();
      if (!accountCreated) return;
      
      const oneHourAfterCreation = new Date(accountCreated.getTime() + 60 * 60 * 1000);
      const now = new Date();
      
      if (now > oneHourAfterCreation) return; // Only check new accounts
      
      // Check if user claimed welcome points
      const hasWelcomePoints = userData.hasReceivedWelcomePoints === true;
      
      // Check if user accepted referral
      const referral = await this.db.collection('referrals')
        .where('referredUserId', '==', userId)
        .limit(1)
        .get();
      const hasReferral = !referral.empty;
      
      // Check if user submitted receipt
      const receipts = await this.db.collection('receipts')
        .where('userId', '==', userId)
        .get();
      const hasReceipt = !receipts.empty;
      
      if (hasWelcomePoints && hasReferral && hasReceipt) {
        await this.flagSuspiciousBehavior(userId, {
          flagType: 'referral_abuse',
          severity: 'medium',
          description: 'New account claimed welcome bonus, referral, and receipt all within 1 hour',
          evidence: {
            hasWelcomePoints,
            hasReferral,
            hasReceipt,
            accountAge: ((now - accountCreated) / (1000 * 60)).toFixed(2) + ' minutes'
          }
        });
      }
      
    } catch (error) {
      logger.error('❌ Error checking new account bonus pattern:', error);
    }
  }

  /**
   * Create a suspicious behavior flag
   */
  async flagSuspiciousBehavior(userId, flagData) {
    try {
      // Check if similar flag already exists (avoid duplicates)
      const existingFlags = await this.db.collection('suspiciousFlags')
        .where('userId', '==', userId)
        .where('flagType', '==', flagData.flagType)
        .where('status', '==', 'pending')
        .limit(1)
        .get();
      
      if (!existingFlags.empty) {
        logger.info(`⚠️ Similar flag already exists for user ${userId}, type: ${flagData.flagType}`);
        return existingFlags.docs[0].id;
      }
      
      // Calculate risk score
      const riskScore = this.calculateRiskScore(flagData.severity, flagData.evidence);
      
      const flag = {
        userId,
        flagType: flagData.flagType,
        severity: flagData.severity || 'medium',
        riskScore,
        description: flagData.description,
        evidence: flagData.evidence || {},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: 'pending',
        reviewedBy: null,
        reviewedAt: null,
        reviewNotes: null,
        actionTaken: null
      };
      
      const flagRef = await this.db.collection('suspiciousFlags').add(flag);
      
      // Update user risk score
      await this.updateUserRiskScore(userId);
      
      logger.info(`🚩 Flagged user ${userId} for ${flagData.flagType} (severity: ${flagData.severity})`);
      
      return flagRef.id;
    } catch (error) {
      logger.error('❌ Error flagging suspicious behavior:', error);
      return null;
    }
  }

  /**
   * Calculate risk score based on severity and evidence
   */
  calculateRiskScore(severity, evidence) {
    let baseScore = 0;
    
    switch (severity) {
      case 'critical': baseScore = 90; break;
      case 'high': baseScore = 70; break;
      case 'medium': baseScore = 50; break;
      case 'low': baseScore = 30; break;
      default: baseScore = 40;
    }
    
    // Adjust based on evidence
    if (evidence) {
      if (evidence.count && evidence.count > 5) baseScore += 10;
      if (evidence.rejectionRate && evidence.rejectionRate > 0.5) baseScore += 15;
      if (evidence.associatedUserIds && evidence.associatedUserIds.length > 2) baseScore += 10;
    }
    
    return Math.min(100, baseScore);
  }

  /**
   * Update user's overall risk score
   */
  async updateUserRiskScore(userId) {
    try {
      // Get all active flags
      const activeFlags = await this.db.collection('suspiciousFlags')
        .where('userId', '==', userId)
        .where('status', '==', 'pending')
        .get();
      
      // Get all flags (for total count)
      const allFlags = await this.db.collection('suspiciousFlags')
        .where('userId', '==', userId)
        .get();
      
      // Calculate factors
      const now = new Date();
      const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      
      // Receipt velocity factor
      const recentReceipts = await this.db.collection('receipts')
        .where('userId', '==', userId)
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .get();
      const receiptVelocity = Math.min(100, (recentReceipts.size / 3) * 20);
      
      // Receipt rejection rate
      const scanAttempts = await this.db.collection('receiptScanAttempts')
        .where('userId', '==', userId)
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .get();
      const attempts = scanAttempts.docs.map(d => d.data());
      const failures = attempts.filter(a => !a.success).length;
      const rejectionRate = attempts.length > 0 ? (failures / attempts.length) * 100 : 0;
      
      // Referral anomalies
      const referrals = await this.db.collection('referrals')
        .where('referredUserId', '==', userId)
        .get();
      const referralAnomalies = referrals.size > 1 ? 50 : 0;
      
      // Device reuse
      const deviceFlags = activeFlags.docs.filter(d => d.data().flagType === 'device_reuse');
      const deviceReuse = deviceFlags.length > 0 ? 80 : 0;
      
      // Account age penalty (newer accounts are riskier)
      const userDoc = await this.db.collection('users').doc(userId).get();
      let accountAge = 0;
      if (userDoc.exists) {
        const createdAt = userDoc.data().createdAt?.toDate();
        if (createdAt) {
          const daysOld = (now - createdAt) / (1000 * 60 * 60 * 24);
          accountAge = daysOld < 7 ? (7 - daysOld) * 5 : 0; // Penalty for accounts < 7 days old
        }
      }
      
      // Behavior patterns (from active flags)
      const behaviorPatterns = activeFlags.size * 10;
      
      // Calculate overall score
      const overallScore = Math.min(100, Math.round(
        receiptVelocity * 0.20 +
        rejectionRate * 0.25 +
        referralAnomalies * 0.20 +
        deviceReuse * 0.25 +
        accountAge * 0.05 +
        behaviorPatterns * 0.05
      ));
      
      // Determine watch status
      let watchStatus = 'normal';
      if (overallScore >= 81) watchStatus = 'restricted';
      else if (overallScore >= 61) watchStatus = 'watching';
      else if (overallScore >= 31) watchStatus = 'watching';
      
      const riskScoreDoc = {
        userId,
        overallScore,
        factors: {
          receiptVelocity,
          receiptRejectionRate: rejectionRate,
          referralAnomalies,
          deviceReuse,
          accountAge,
          behaviorPatterns
        },
        activeFlags: activeFlags.size,
        totalFlags: allFlags.size,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        watchStatus
      };
      
      await this.db.collection('userRiskScores').doc(userId).set(riskScoreDoc, { merge: true });
      
      return riskScoreDoc;
    } catch (error) {
      logger.error('❌ Error updating user risk score:', error);
      return null;
    }
  }

  /**
   * Get user's risk profile
   */
  async getUserRiskProfile(userId) {
    try {
      const riskScoreDoc = await this.db.collection('userRiskScores').doc(userId).get();
      const flags = await this.db.collection('suspiciousFlags')
        .where('userId', '==', userId)
        .orderBy('createdAt', 'desc')
        .limit(20)
        .get();
      
      return {
        riskScore: riskScoreDoc.exists ? riskScoreDoc.data() : null,
        flags: flags.docs.map(doc => ({
          id: doc.id,
          ...doc.data(),
          createdAt: doc.data().createdAt?.toDate()?.toISOString(),
          reviewedAt: doc.data().reviewedAt?.toDate()?.toISOString()
        }))
      };
    } catch (error) {
      logger.error('❌ Error getting user risk profile:', error);
      return null;
    }
  }
}

// =============================================================================
// Global Error Handler (must be after all routes)
// =============================================================================

// Sentry error handler middleware (must be before custom error handler)
if (Sentry) {
  app.use(Sentry.Handlers.errorHandler());
}

app.use((err, req, res, next) => {
  logError(err, req, { errorCode: err.code || 'INTERNAL_ERROR' });
  res.status(err.status || 500).json({
    errorCode: err.code || 'INTERNAL_ERROR',
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message
  });
});

const port = process.env.PORT || 3001;
let server;
let isShuttingDown = false;

validateEnvironment();

server = app.listen(port, '0.0.0.0', async () => {
  logger.info('\n🚀 Server starting...\n');
  logger.info(`📍 Port: ${port}`);
  logger.info(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  logger.info(`🌐 URL: http://0.0.0.0:${port}\n`);
  
  // Check service status
  logger.info('📊 Service Status:');
  logger.info(`  ${admin.apps.length ? '✅' : '❌'} Firebase: ${admin.apps.length ? 'Initialized' : 'Not initialized'}`);
  logger.info(`  ${process.env.OPENAI_API_KEY ? '✅' : '❌'} OpenAI: ${process.env.OPENAI_API_KEY ? 'Configured' : 'Not configured'}`);
  
  const redisHealth = await checkRedisHealth();
  logger.info(`  ${redisHealth.connected ? '✅' : redisClient ? '⚠️' : 'ℹ️'} Redis: ${redisHealth.status || 'Not configured'}`);
  logger.info(`  ${Sentry ? '✅' : 'ℹ️'} Sentry: ${Sentry ? 'Configured' : 'Not configured'}`);
  
  logger.info('\n✅ Server ready!\n');
});

function shutdown(signal, exitCode = 0) {
  if (isShuttingDown) return;
  isShuttingDown = true;
  logger.info(`🧹 Shutdown initiated (${signal})`);
  
  // Close Redis connection if it exists
  if (redisClient) {
    redisClient.disconnect();
    logger.info('✅ Redis disconnected');
  }
  
  if (server) {
    server.close(() => {
      logger.info('✅ Server closed');
      process.exit(exitCode);
    });
  } else {
    process.exit(exitCode);
  }

  setTimeout(() => process.exit(exitCode || 1), 10000).unref();
}

// Process-level error handlers to prevent crashes
process.on('unhandledRejection', (reason, promise) => {
  const error = reason instanceof Error ? reason : new Error(String(reason));
  logError(error, null, { 
    type: 'unhandledRejection',
    promise: promise?.toString?.() || 'unknown'
  });
});

process.on('uncaughtException', (error) => {
  logError(error, null, { type: 'uncaughtException' });
  shutdown('uncaughtException', 1);
});

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Configure server timeouts
server.timeout = 30000; // 30 seconds request timeout
server.keepAliveTimeout = 65000; // Slightly higher than ALB's 60s default
server.headersTimeout = 66000; // Slightly higher than keepAliveTimeout
