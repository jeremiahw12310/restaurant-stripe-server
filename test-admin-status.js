/**
 * Verifies admin status for Firestore users.
 *
 * Usage:
 *   node test-admin-status.js                 # lists a few admin users
 *   node test-admin-status.js <uid>           # checks a specific uid
 *
 * Auth:
 * - Uses ADC if FIREBASE_AUTH_TYPE=adc (recommended)
 * - Or FIREBASE_SERVICE_ACCOUNT_KEY (JSON) if provided
 */
require('dotenv').config();
const admin = require('firebase-admin');
 
function initAdmin() {
  if (admin.apps.length) return;
 
  if (process.env.FIREBASE_AUTH_TYPE === 'adc') {
    admin.initializeApp({
      projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp',
    });
    console.log('✅ Firebase Admin initialized with Application Default Credentials');
    return;
  }
 
  if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    console.log('✅ Firebase Admin initialized with service account key');
    return;
  }
 
  // Fall back to default initialization (will attempt ADC if present)
  admin.initializeApp({
    projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp',
  });
  console.log('⚠️ Firebase Admin initialized without explicit credentials (will use ADC if available)');
}
 
function typeOfValue(v) {
  if (v === null) return 'null';
  if (v === undefined) return 'undefined';
  if (Array.isArray(v)) return 'array';
  return typeof v;
}
 
async function checkUid(db, uid) {
  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
 
  if (!snap.exists) {
    console.log(`❌ users/${uid} does not exist`);
    return;
  }
 
  const data = snap.data() || {};
  const isAdmin = data.isAdmin;
  const isEmployee = data.isEmployee;
 
  console.log(`✅ users/${uid} exists`);
  console.log(`   - isAdmin: ${JSON.stringify(isAdmin)} (type: ${typeOfValue(isAdmin)})`);
  console.log(`   - isEmployee: ${JSON.stringify(isEmployee)} (type: ${typeOfValue(isEmployee)})`);
}
 
async function listAdmins(db) {
  // Note: Query requires consistent field typing (boolean). If some docs have non-boolean
  // values, Firestore may exclude them from the query rather than erroring.
  const snap = await db.collection('users').where('isAdmin', '==', true).limit(10).get();
  console.log(`🔎 Found ${snap.size} user(s) where isAdmin == true (showing up to 10):`);
  snap.docs.forEach((d, i) => {
    const data = d.data() || {};
    const isAdmin = data.isAdmin;
    console.log(`   ${i + 1}. ${d.id} (isAdmin type: ${typeOfValue(isAdmin)})`);
  });
 
  if (snap.size === 0) {
    console.log('⚠️ No admin users found via query. If you expect admins, check:');
    console.log('   - users/{uid}.isAdmin exists and is a boolean true');
    console.log('   - you are pointing at the correct project (dumplinghouseapp)');
  }
}
 
async function main() {
  initAdmin();
  const db = admin.firestore();
 
  const uid = process.argv[2];
  if (uid) {
    await checkUid(db, uid);
  } else {
    await listAdmins(db);
  }
}
 
main()
  .then(() => process.exit(0))
  .catch((err) => {
    const msg = err?.message || String(err);
    console.error('❌ Error:', msg);
    if (msg.includes('invalid_rapt') || msg.includes('invalid_grant')) {
      console.error('');
      console.error('Hint: your Application Default Credentials likely need re-auth.');
      console.error('Run: ./setup-adc.sh');
      console.error('Then re-run: node test-admin-status.js <uid>');
    }
    process.exit(1);
  });

