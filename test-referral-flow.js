#!/usr/bin/env node

// Quick end-to-end test for referral flow
// Steps:
// 1) Create code as User A
// 2) Accept code as User B
// 3) Optionally bump B to 50 points using Firebase Admin (if SERVICE_ACCOUNT provided)
// 4) Run award-check twice (idempotent)

const axios = require('axios');

// Config via env
const SERVER_URL = process.env.SERVER_URL || 'http://localhost:3001';
const USER_A = process.env.USER_A; // referrer uid
const USER_B = process.env.USER_B; // receiver uid
const ID_TOKEN_A = process.env.ID_TOKEN_A; // optional Firebase ID token for A
const ID_TOKEN_B = process.env.ID_TOKEN_B; // optional Firebase ID token for B
const SERVICE_ACCOUNT_PATH = process.env.SERVICE_ACCOUNT; // optional path to service account JSON

let admin;
let db;
if (SERVICE_ACCOUNT_PATH) {
  try {
    admin = require('firebase-admin');
    admin.initializeApp({
      credential: admin.credential.cert(require(SERVICE_ACCOUNT_PATH))
    });
    db = admin.firestore();
    console.log('✅ Firebase Admin initialized for points bump');
  } catch (e) {
    console.warn('⚠️ Failed to initialize Firebase Admin:', e.message);
  }
}

if (!USER_A || !USER_B) {
  console.error('❌ Missing env: USER_A and USER_B are required');
  process.exit(1);
}

function headersFor(uid, idToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (ID_TOKEN_A || ID_TOKEN_B) {
    if (!idToken) throw new Error('ID token required but not provided');
    headers['Authorization'] = `Bearer ${idToken}`;
  } else {
    headers['x-user-id'] = uid; // dev-only fallback (requires ALLOW_HEADER_USER_ID=true or local)
  }
  return headers;
}

async function createCodeAsA() {
  console.log('\n📨 Creating referral code as A');
  const res = await axios.post(`${SERVER_URL}/referrals/create`, {}, {
    headers: headersFor(USER_A, ID_TOKEN_A)
  });
  console.log('✅ Code:', res.data.code, 'Share URL:', res.data.shareUrl);
  return res.data.code;
}

async function acceptAsB(code) {
  console.log('\n🔗 Accepting referral as B');
  const res = await axios.post(`${SERVER_URL}/referrals/accept`, { code, deviceId: 'test-device' }, {
    headers: headersFor(USER_B, ID_TOKEN_B)
  });
  console.log('✅ Accepted. ReferralId:', res.data.referralId, 'Referrer:', res.data.referrerUserId);
  return res.data.referralId;
}

async function bumpBTo50() {
  if (!db) {
    console.log('⏭️ Skipping points bump (no service account). Ensure B reaches 50 points manually.');
    return false;
  }
  console.log('\n⬆️ Setting B points to 50 via Admin');
  await db.collection('users').doc(USER_B).set({ points: 50 }, { merge: true });
  console.log('✅ B now has 50 points');
  return true;
}

async function awardCheck(referralId) {
  console.log('\n🏁 Running award-check');
  const res = await axios.post(`${SERVER_URL}/referrals/award-check`, { referralId }, {
    headers: headersFor(USER_B, ID_TOKEN_B)
  });
  console.log('➡️ Award-check result:', res.data);
}

async function main() {
  console.log('🧪 Referral Flow Test starting...');
  console.log('Server:', SERVER_URL);
  console.log('User A (referrer):', USER_A);
  console.log('User B (receiver):', USER_B);

  try {
    const code = await createCodeAsA();
    const referralId = await acceptAsB(code);

    // First award-check (likely too early or threshold not met)
    await awardCheck(referralId);

    // Bump B to 50 points if possible
    const bumped = await bumpBTo50();
    if (!bumped) {
      console.log('⏳ Please ensure USER_B has >= 50 points, then rerun award-check.');
    }

    // Award-check again
    await awardCheck(referralId);

    // Idempotency check
    await awardCheck(referralId);

    console.log('\n🎉 Test complete');
  } catch (e) {
    if (e.response) {
      console.error('❌ Error:', e.response.status, e.response.data);
    } else {
      console.error('❌ Error:', e.message);
    }
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}



