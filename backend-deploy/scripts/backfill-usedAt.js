/**
 * One-time migration script to backfill usedAt for rewards missing it.
 * 
 * Run with: node scripts/backfill-usedAt.js
 * 
 * This finds rewards where isUsed=true but usedAt is missing,
 * and sets usedAt to the value of redeemedAt.
 */

// Try loading .env from current directory, then parent directory
const path = require('path');
require('dotenv').config();
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });
const admin = require('firebase-admin');

// Initialize Firebase Admin (same pattern as server.js)
if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    const credential = admin.credential.cert(serviceAccount);
    admin.initializeApp({ credential });
    console.log('✅ Firebase Admin initialized with service account key');
  } catch (error) {
    console.error('❌ Failed to initialize Firebase Admin:', error);
    process.exit(1);
  }
} else if (process.env.FIREBASE_AUTH_TYPE === 'adc' || process.env.GOOGLE_CLOUD_PROJECT) {
  // Try Application Default Credentials (ADC) with explicit project ID
  try {
    admin.initializeApp({ 
      projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp' 
    });
    console.log('✅ Firebase Admin initialized with Application Default Credentials');
  } catch (error) {
    console.error('❌ Failed to initialize Firebase Admin with ADC:', error);
    process.exit(1);
  }
} else {
  console.error('❌ Failed to initialize Firebase Admin. Make sure FIREBASE_SERVICE_ACCOUNT_KEY is set or ADC is configured.');
  process.exit(1);
}

const db = admin.firestore();

async function backfillUsedAt() {
  console.log('🔍 Finding rewards with isUsed=true but no usedAt...');
  
  // Query rewards that are used
  const snapshot = await db.collection('redeemedRewards')
    .where('isUsed', '==', true)
    .get();
  
  console.log(`📊 Found ${snapshot.size} total used rewards`);
  
  // Filter to those missing usedAt
  const missingUsedAt = snapshot.docs.filter(doc => {
    const data = doc.data();
    return !data.usedAt;
  });
  
  console.log(`⚠️  ${missingUsedAt.length} rewards are missing usedAt`);
  
  if (missingUsedAt.length === 0) {
    console.log('✅ No backfill needed!');
    return;
  }
  
  // Preview what we'll update
  console.log('\n📋 Preview of rewards to backfill:');
  for (const doc of missingUsedAt.slice(0, 5)) {
    const data = doc.data();
    const redeemedAtDate = data.redeemedAt?.toDate ? data.redeemedAt.toDate() : data.redeemedAt;
    console.log(`  - ${doc.id}: redeemedAt=${redeemedAtDate}, userId=${data.userId || 'N/A'}`);
  }
  if (missingUsedAt.length > 5) {
    console.log(`  ... and ${missingUsedAt.length - 5} more`);
  }
  
  // Confirm before proceeding
  console.log('\n⏳ Starting backfill in 5 seconds... (Ctrl+C to cancel)');
  await new Promise(r => setTimeout(r, 5000));
  
  // Batch update
  let updated = 0;
  let skipped = 0;
  const batchSize = 450; // Firestore batch limit is 500
  
  for (let i = 0; i < missingUsedAt.length; i += batchSize) {
    const batch = db.batch();
    const chunk = missingUsedAt.slice(i, i + batchSize);
    
    for (const doc of chunk) {
      const data = doc.data();
      const redeemedAt = data.redeemedAt;
      
      if (redeemedAt) {
        // Use redeemedAt as usedAt (reasonable approximation)
        batch.update(doc.ref, { usedAt: redeemedAt });
        updated++;
      } else {
        // No redeemedAt either - use current time as fallback
        console.log(`  ⚠️  ${doc.id} has no redeemedAt, using current time`);
        batch.update(doc.ref, { usedAt: admin.firestore.FieldValue.serverTimestamp() });
        updated++;
      }
    }
    
    await batch.commit();
    console.log(`✅ Batch ${Math.floor(i / batchSize) + 1}: updated ${chunk.length} documents`);
  }
  
  console.log(`\n🎉 Backfill complete! Updated: ${updated}, Skipped: ${skipped}`);
}

backfillUsedAt()
  .then(() => {
    console.log('\n✅ Script completed successfully');
    process.exit(0);
  })
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
