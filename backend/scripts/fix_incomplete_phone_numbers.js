/**
 * Migration script: Fix users with incomplete OR mismatched phone numbers in Firestore.
 *
 * This script:
 * 1. Finds users whose `phone` field is empty, "+1", or otherwise incomplete
 * 2. Finds users whose Firestore phone doesn't match their Firebase Auth phone
 * 3. Updates Firestore with the correct phone from Firebase Authentication
 *
 * Usage:
 *   node backend/scripts/fix_incomplete_phone_numbers.js
 *
 * Options:
 *   DRY_RUN=1 node backend/scripts/fix_incomplete_phone_numbers.js
 *     - Preview what would be changed without making actual updates
 *
 *   DELETE_ORPHANS=1 node backend/scripts/fix_incomplete_phone_numbers.js
 *     - Also delete Firestore user documents that have no Firebase Auth account
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

/**
 * Check if a phone number is incomplete (missing digits after country code)
 */
function isIncompletePhone(phone) {
  if (!phone || typeof phone !== 'string') return true;
  const trimmed = phone.trim();
  // Empty, just "+1", or too short to be a valid US phone number
  if (trimmed === '' || trimmed === '+1' || trimmed.length < 11) return true;
  return false;
}

async function main() {
  initFirebaseAdmin();

  const db = admin.firestore();
  const auth = admin.auth();
  const dryRun = (process.env.DRY_RUN || '').toString() === '1';
  const deleteOrphans = (process.env.DELETE_ORPHANS || '').toString() === '1';

  console.log(`📱 Fixing phone numbers in Firestore (dryRun=${dryRun}, deleteOrphans=${deleteOrphans})`);
  console.log('');

  const usersRef = db.collection('users');
  const pageSize = 100;
  let lastDoc = null;
  let processed = 0;
  let incomplete = 0;
  let mismatched = 0;
  let fixed = 0;
  let notFoundInAuth = 0;
  let orphansDeleted = 0;
  let authHasNoPhone = 0;

  while (true) {
    let q = usersRef.orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (lastDoc) q = q.startAfter(lastDoc);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      const uid = doc.id;
      const data = doc.data();
      const currentPhone = data.phone || '';
      processed++;

      // Look up phone from Firebase Auth for ALL users (to catch mismatches)
      let authPhone = null;
      let userNotInAuth = false;
      try {
        const userRecord = await auth.getUser(uid);
        authPhone = userRecord.phoneNumber;
      } catch (err) {
        if (err.code === 'auth/user-not-found') {
          userNotInAuth = true;
        } else {
          throw err;
        }
      }

      // Handle orphaned users (Firestore doc exists but no Auth account)
      if (userNotInAuth) {
        if (isIncompletePhone(currentPhone)) {
          incomplete++;
          console.log(`⚠️  User ${uid}: incomplete phone "${currentPhone || '(empty)'}" - NO AUTH ACCOUNT`);
          notFoundInAuth++;
          
          if (deleteOrphans) {
            if (!dryRun) {
              await usersRef.doc(uid).delete();
              console.log(`   🗑️  Deleted orphaned Firestore document`);
            } else {
              console.log(`   🗑️  Would delete orphaned Firestore document (dry run)`);
            }
            orphansDeleted++;
          } else {
            console.log(`   ❌ User not found in Firebase Auth (use DELETE_ORPHANS=1 to remove)`);
          }
        }
        continue;
      }

      // Check if phone is incomplete
      const phoneIncomplete = isIncompletePhone(currentPhone);
      
      // Check if phone mismatches Auth (even if it looks complete)
      const phoneMismatched = authPhone && currentPhone !== authPhone && !isIncompletePhone(authPhone);

      if (!phoneIncomplete && !phoneMismatched) {
        continue; // Phone looks correct, skip
      }

      if (phoneIncomplete) {
        incomplete++;
        console.log(`⚠️  User ${uid}: incomplete phone "${currentPhone || '(empty)'}"`);
      } else if (phoneMismatched) {
        mismatched++;
        console.log(`⚠️  User ${uid}: mismatched phone`);
        console.log(`      Firestore: "${currentPhone}"`);
        console.log(`      Auth:      "${authPhone}"`);
      }

      if (!authPhone || isIncompletePhone(authPhone)) {
        console.log(`   ⚠️  Firebase Auth also has no/incomplete phone: "${authPhone || '(none)'}"`);
        authHasNoPhone++;
        continue;
      }

      // We have a valid phone from Auth - update Firestore
      console.log(`   ✅ Correct phone from Auth: "${authPhone}"`);

      if (!dryRun) {
        await usersRef.doc(uid).update({ phone: authPhone });
        console.log(`   📝 Updated Firestore`);
      } else {
        console.log(`   📝 Would update Firestore (dry run)`);
      }

      fixed++;
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    console.log(`\n📊 Progress: processed=${processed}, issues=${incomplete + mismatched}, fixed=${fixed}\n`);
  }

  console.log('');
  console.log('═══════════════════════════════════════════════════════');
  console.log('📱 MIGRATION COMPLETE');
  console.log('═══════════════════════════════════════════════════════');
  console.log(`   Total users scanned:     ${processed}`);
  console.log(`   Incomplete phones:       ${incomplete}`);
  console.log(`   Mismatched phones:       ${mismatched}`);
  console.log(`   Fixed from Auth:         ${fixed}`);
  console.log(`   Not found in Auth:       ${notFoundInAuth}`);
  console.log(`   Orphans deleted:         ${orphansDeleted}`);
  console.log(`   Auth also has no phone:  ${authHasNoPhone}`);
  console.log(`   Dry run mode:            ${dryRun}`);
  console.log(`   Delete orphans mode:     ${deleteOrphans}`);
  console.log('═══════════════════════════════════════════════════════');

  if (dryRun && (fixed > 0 || orphansDeleted > 0)) {
    console.log('');
    console.log('💡 To apply these changes, run without DRY_RUN:');
    console.log('   node backend/scripts/fix_incomplete_phone_numbers.js');
    if (notFoundInAuth > 0 && !deleteOrphans) {
      console.log('');
      console.log('💡 To also delete orphaned users, add DELETE_ORPHANS=1:');
      console.log('   DELETE_ORPHANS=1 node backend/scripts/fix_incomplete_phone_numbers.js');
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('❌ Migration failed:', err);
    process.exit(1);
  });
