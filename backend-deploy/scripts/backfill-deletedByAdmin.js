/**
 * One-time migration script to add deletedByAdmin: false to existing rewards.
 *
 * Required before admin reward delete feature. Firestore queries with
 * deletedByAdmin != true exclude documents where the field doesn't exist.
 * This script ensures all existing rewards appear in the main overview.
 *
 * Run with: node scripts/backfill-deletedByAdmin.js
 *
 * Credentials (choose one):
 * 1. FIREBASE_SERVICE_ACCOUNT_KEY - JSON string in .env
 * 2. GOOGLE_APPLICATION_CREDENTIALS - path to service account JSON file
 * 3. FIREBASE_AUTH_TYPE=adc GOOGLE_CLOUD_PROJECT=your-project  (after: gcloud auth application-default login)
 */

const path = require('path');
require('dotenv').config();
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env.local') });
const admin = require('firebase-admin');

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
} else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  try {
    admin.initializeApp();
    console.log('✅ Firebase Admin initialized with GOOGLE_APPLICATION_CREDENTIALS');
  } catch (error) {
    console.error('❌ Failed to initialize Firebase Admin:', error);
    process.exit(1);
  }
} else if (process.env.FIREBASE_AUTH_TYPE === 'adc' || process.env.GOOGLE_CLOUD_PROJECT) {
  try {
    admin.initializeApp({
      projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp'
    });
    console.log('✅ Firebase Admin initialized with Application Default Credentials');
  } catch (error) {
    console.error('❌ Failed to initialize Firebase Admin:', error);
    process.exit(1);
  }
} else {
  console.error('❌ Failed to initialize Firebase Admin.');
  console.error('');
  console.error('Choose one of these options:');
  console.error('  1. Add FIREBASE_SERVICE_ACCOUNT_KEY (JSON string) to .env or backend-deploy/.env');
  console.error('  2. Set GOOGLE_APPLICATION_CREDENTIALS to the path of your service account JSON file');
  console.error('  3. Run: gcloud auth application-default login');
  console.error('     Then: FIREBASE_AUTH_TYPE=adc GOOGLE_CLOUD_PROJECT=dumplinghouseapp node scripts/backfill-deletedByAdmin.js');
  process.exit(1);
}

const db = admin.firestore();

async function backfillDeletedByAdmin() {
  console.log('🔍 Finding rewards missing deletedByAdmin...');

  let lastDoc = null;
  let total = 0;
  let missing = 0;
  const toUpdate = [];

  while (true) {
    let query = db.collection('redeemedRewards').limit(1000);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snapshot = await query.get();
    if (snapshot.empty) break;

    total += snapshot.size;
    snapshot.forEach(doc => {
      const data = doc.data();
      if (data.deletedByAdmin === undefined) {
        missing++;
        toUpdate.push(doc);
      }
    });
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }

  console.log(`📊 Total rewards: ${total}`);
  console.log(`⚠️  Missing deletedByAdmin: ${missing}`);

  if (missing === 0) {
    console.log('✅ No backfill needed!');
    return;
  }

  console.log('\n⏳ Starting backfill in 5 seconds... (Ctrl+C to cancel)');
  await new Promise(r => setTimeout(r, 5000));

  let updated = 0;
  const batchSize = 450;

  for (let i = 0; i < toUpdate.length; i += batchSize) {
    const batch = db.batch();
    const chunk = toUpdate.slice(i, i + batchSize);
    for (const doc of chunk) {
      batch.update(doc.ref, { deletedByAdmin: false });
      updated++;
    }
    await batch.commit();
    console.log(`✅ Batch ${Math.floor(i / batchSize) + 1}: updated ${chunk.length} documents`);
  }

  console.log(`\n🎉 Backfill complete! Updated: ${updated}`);
}

backfillDeletedByAdmin()
  .then(() => {
    console.log('\n✅ Script completed successfully');
    process.exit(0);
  })
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
