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
      // Skip no-op writes (reduces unnecessary collection scans)
      const beforeData = event.data?.before?.data?.() || null;
      const afterSnap = event.data?.after;
      const afterData = afterSnap && afterSnap.exists ? (afterSnap.data?.() || null) : null;

      const stableStringify = (obj) => {
        if (obj === null || obj === undefined) return String(obj);
        if (Array.isArray(obj)) return `[${obj.map(stableStringify).join(',')}]`;
        if (typeof obj === 'object') {
          const keys = Object.keys(obj).sort();
          return `{${keys.map(k => `${k}:${stableStringify(obj[k])}`).join(',')}}`;
        }
        return JSON.stringify(obj);
      };

      if (beforeData && afterData && stableStringify(beforeData) === stableStringify(afterData)) {
        return null;
      }

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

/**
 * Firestore trigger: maintain referral progress and award bonus when user reaches 50 points.
 * This makes referral awarding reliable for admin adjustments, receipt scans, etc.
 * Also updates pointsTowards50 on referral docs so clients can display progress without cross-user reads.
 *
 * Trigger: fires on any users/{userId} write where points field changes
 */
exports.awardReferralOnPointsCross = onDocumentWritten(
  'users/{userId}',
  async (event) => {
    try {
      const userId = event.params.userId;
      const beforeData = event.data?.before?.data?.() || {};
      const afterSnap = event.data?.after;

      // Ignore deletes
      if (!afterSnap || afterSnap.exists === false) return null;

      const afterData = afterSnap.data?.() || {};

      const beforePointsRaw = beforeData.points ?? 0;
      const afterPointsRaw = afterData.points ?? 0;
      const beforePoints = typeof beforePointsRaw === 'number' ? beforePointsRaw : (parseFloat(String(beforePointsRaw)) || 0);
      const afterPoints = typeof afterPointsRaw === 'number' ? afterPointsRaw : (parseFloat(String(afterPointsRaw)) || 0);

      // Cost guard: if points didn't change, do nothing.
      // This prevents extra referral queries on unrelated writes (FCM token, profile updates, etc.).
      if (beforePoints === afterPoints) return null;

      // Only run the awarding logic when it can matter:
      // - points cross the 50 threshold upward (award), OR
      // - points are below 50 (progress tracking).
      const crossedUpTo50 = beforePoints < 50 && afterPoints >= 50;
      const progressRangeRelevant = afterPoints < 50 || beforePoints < 50;
      if (!crossedUpTo50 && !progressRangeRelevant) return null;

      // Clamp points towards 50 (0-50 range)
      const pointsTowards50 = Math.max(0, Math.min(50, afterPoints));

      const db = admin.firestore();

      // Find referral doc where this user is the referred person
      const referralSnap = await db.collection('referrals')
        .where('referredUserId', '==', userId)
        .limit(1)
        .get();

      if (referralSnap.empty) {
        // No referral for this user, nothing to do
        return null;
      }

      const referralDoc = referralSnap.docs[0];
      const referralRef = referralDoc.ref;
      const referralId = referralDoc.id;
      const referralData = referralDoc.data() || {};

      const BONUS = 50;

      // Deterministic IDs (safe if trigger runs twice)
      const txIdReferred = `referral_${referralId}_referred`;
      const txIdReferrer = `referral_${referralId}_referrer`;
      const notifIdReferred = `referralAward_${referralId}_referred`;
      const notifIdReferrer = `referralAward_${referralId}_referrer`;

      let referrerId = null;
      let referrerNewPoints = null;
      let referredNewPoints = null;
      let referrerFcmToken = null;
      let referredFcmToken = null;
      let referrerName = 'Friend';
      let referredName = 'Friend';
      let didAward = false;
      let needsProgressUpdate = false;

      await db.runTransaction(async (tx) => {
        const referralSnapTx = await tx.get(referralRef);
        if (!referralSnapTx.exists) return;
        const referralDataTx = referralSnapTx.data() || {};

        // Get current progress value from referral doc (if exists)
        const currentProgress = typeof referralDataTx.pointsTowards50 === 'number' 
          ? referralDataTx.pointsTowards50 
          : 0;

        // Update progress if it changed (avoid unnecessary writes)
        if (currentProgress !== pointsTowards50) {
          needsProgressUpdate = true;
        }

        // Check if we should award: afterPoints >= 50 AND referral still pending
        const shouldAward = afterPoints >= 50 && referralDataTx.status !== 'awarded';

        if (!shouldAward && !needsProgressUpdate) {
          // Nothing to do
          return;
        }

        // Use denormalized names from referral doc (preferred) or fallback to user doc
        referrerName = referralDataTx.referrerFirstName || 'Friend';
        referredName = referralDataTx.referredFirstName || 'Friend';

        referrerId = referralDataTx.referrerUserId || null;

        // Update progress on referral doc
        if (needsProgressUpdate) {
          const updateData = { pointsTowards50 };
          tx.update(referralRef, updateData);
        }

        // Award logic (only if shouldAward is true)
        if (shouldAward) {
          const referredUserRef = db.collection('users').doc(userId);
          const referredUserSnap = await tx.get(referredUserRef);
          if (!referredUserSnap.exists) return;

          const referredUserData = referredUserSnap.data() || {};
          const currentReferredPoints = referredUserData.points || 0;
          const currentReferredLifetime = (typeof referredUserData.lifetimePoints === 'number')
            ? referredUserData.lifetimePoints
            : currentReferredPoints;

          referredFcmToken = referredUserData.fcmToken || null;
          
          // Prefer denormalized name, but fallback to user doc if missing
          if (referredName === 'Friend') {
            referredName = referredUserData.firstName || referredUserData.name?.split?.(' ')?.[0] || 'Friend';
          }

          // Award referred user
          referredNewPoints = currentReferredPoints + BONUS;
          const referredNewLifetime = currentReferredLifetime + BONUS;

          tx.update(referredUserRef, {
            points: referredNewPoints,
            lifetimePoints: referredNewLifetime
          });

          // Points transaction for referred
          tx.set(db.collection('pointsTransactions').doc(txIdReferred), {
            userId: userId,
            type: 'referral',
            amount: BONUS,
            description: 'Referral bonus - reached 50 points!',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            metadata: { referralId, role: 'referred' }
          }, { merge: true });

          // Notification doc for referred
          tx.set(db.collection('notifications').doc(notifIdReferred), {
            userId: userId,
            title: 'Referral Bonus Awarded! 🎉',
            body: `You reached 50 points! You and ${referrerName} each earned +${BONUS} bonus points.`,
            type: 'referral',
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            metadata: { referralId, role: 'referred' }
          }, { merge: true });

          // Award referrer if present and exists
          if (referrerId) {
            const referrerUserRef = db.collection('users').doc(referrerId);
            const referrerUserSnap = await tx.get(referrerUserRef);
            if (referrerUserSnap.exists) {
              const referrerUserData = referrerUserSnap.data() || {};
              const currentReferrerPoints = referrerUserData.points || 0;
              const currentReferrerLifetime = (typeof referrerUserData.lifetimePoints === 'number')
                ? referrerUserData.lifetimePoints
                : currentReferrerPoints;

              referrerFcmToken = referrerUserData.fcmToken || null;
              
              // Prefer denormalized name, but fallback to user doc if missing
              if (referrerName === 'Friend') {
                referrerName = referrerUserData.firstName || referrerUserData.name?.split?.(' ')?.[0] || 'Friend';
              }

              referrerNewPoints = currentReferrerPoints + BONUS;
              const referrerNewLifetime = currentReferrerLifetime + BONUS;

              tx.update(referrerUserRef, {
                points: referrerNewPoints,
                lifetimePoints: referrerNewLifetime
              });

              // Points transaction for referrer
              tx.set(db.collection('pointsTransactions').doc(txIdReferrer), {
                userId: referrerId,
                type: 'referral',
                amount: BONUS,
                description: `Referral bonus - ${referredName} reached 50 points!`,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                metadata: { referralId, role: 'referrer', referredUserId: userId }
              }, { merge: true });

              // Notification doc for referrer
              tx.set(db.collection('notifications').doc(notifIdReferrer), {
                userId: referrerId,
                title: 'Referral Bonus Awarded! 🎉',
                body: `${referredName} reached 50 points! You earned +${BONUS} bonus points.`,
                type: 'referral',
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                metadata: { referralId, role: 'referrer' }
              }, { merge: true });
            } else {
              console.warn(`⚠️ [awardReferralOnPointsCross] Referrer ${referrerId} missing; awarding referred only`);
            }
          }

          // Mark referral as awarded and set progress to 50
          tx.update(referralRef, {
            status: 'awarded',
            awardedAt: admin.firestore.FieldValue.serverTimestamp(),
            pointsTowards50: 50
          });

          didAward = true;
        }
      });

      // Send push notifications (best-effort, only if we awarded)
      if (didAward) {
        const pushPromises = [];
        if (referrerFcmToken) {
          pushPromises.push(
            admin.messaging().send({
              token: referrerFcmToken,
              notification: {
                title: 'Referral Bonus Awarded! 🎉',
                body: `${referredName} reached 50 points! You earned +${BONUS} bonus points.`
              },
              data: { type: 'referral_awarded', role: 'referrer', referralId }
            }).catch(err => {
              console.warn('⚠️ [awardReferralOnPointsCross] Referrer push failed:', err?.message || err);
            })
          );
        }
        if (referredFcmToken) {
          pushPromises.push(
            admin.messaging().send({
              token: referredFcmToken,
              notification: {
                title: 'Referral Bonus Awarded! 🎉',
                body: `You reached 50 points! You and ${referrerName} each earned +${BONUS} bonus points.`
              },
              data: { type: 'referral_awarded', role: 'referred', referralId }
            }).catch(err => {
              console.warn('⚠️ [awardReferralOnPointsCross] Referred push failed:', err?.message || err);
            })
          );
        }

        await Promise.all(pushPromises);

        console.log(`🎉 [awardReferralOnPointsCross] Awarded referral ${referralId} via trigger. ReferrerNewPoints=${referrerNewPoints}, ReferredNewPoints=${referredNewPoints}`);
      } else if (needsProgressUpdate) {
        console.log(`📊 [awardReferralOnPointsCross] Updated progress for referral ${referralId}: ${pointsTowards50}/50`);
      }

      return null;
    } catch (error) {
      console.error('❌ [awardReferralOnPointsCross] Error:', error);
      return null;
    }
  }
);

exports.api = onRequest(app);






