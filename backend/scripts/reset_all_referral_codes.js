/**
 * One-time migration script: reset ALL users' `referralCode` values to new unique codes.
 *
 * ⚠️ This will invalidate any previously shared referral codes.
 *
 * Usage:
 *   node backend/scripts/reset_all_referral_codes.js
 *
 * Optional:
 *   DRY_RUN=1 node backend/scripts/reset_all_referral_codes.js
 *
 * Auth:
 * - Supports ADC if `FIREBASE_AUTH_TYPE=adc` (Render / gcloud / local ADC)
 * - Supports service account JSON in `FIREBASE_SERVICE_ACCOUNT_KEY`
 */

require('dotenv').config();

const admin = require('firebase-admin');

function initFirebaseAdmin() {
  if (admin.apps.length) return;

  if (process.env.FIREBASE_AUTH_TYPE === 'adc') {
    admin.initializeApp({
      projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp',
    });
    return;
  }

  if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    return;
  }

  // Last-ditch: try initialize without explicit credential (may work in some environments)
  admin.initializeApp({
    projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp',
  });
}

function generateReferralCode(length = 6) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

function generateUniqueFromSet(used, length = 6, maxAttempts = 200) {
  for (let i = 0; i < maxAttempts; i++) {
    const c = generateReferralCode(length);
    if (!used.has(c)) {
      used.add(c);
      return c;
    }
  }
  throw new Error('Unable to generate unique referral code (set exhausted?)');
}

async function main() {
  initFirebaseAdmin();

  const db = admin.firestore();
  const dryRun = (process.env.DRY_RUN || '').toString() === '1';

  console.log(`🔁 Resetting ALL users.referralCode (dryRun=${dryRun})`);

  const used = new Set();

  const usersRef = db.collection('users');
  const pageSize = 450; // keep below 500 to be safe
  let lastDoc = null;
  let processed = 0;
  let updated = 0;

  while (true) {
    let q = usersRef.orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (lastDoc) q = q.startAfter(lastDoc);

    const snap = await q.get();
    if (snap.empty) break;

    let batch = db.batch();
    let batchOps = 0;

    for (const doc of snap.docs) {
      const uid = doc.id;
      const newCode = generateUniqueFromSet(used, 6);
      processed++;

      if (!dryRun) {
        batch.update(usersRef.doc(uid), { referralCode: newCode });
        batchOps++;
      }

      updated++;

      if (!dryRun && batchOps >= pageSize) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }

    if (!dryRun && batchOps > 0) {
      await batch.commit();
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    console.log(`✅ Progress: processed=${processed}, updated=${updated}`);
  }

  console.log(`🎉 Done. processed=${processed}, updated=${updated}, dryRun=${dryRun}`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('❌ Migration failed:', err);
    process.exit(1);
  });



