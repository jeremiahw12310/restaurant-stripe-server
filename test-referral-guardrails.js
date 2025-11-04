#!/usr/bin/env node

// Guardrails tests:
// - Self referral
// - Receiver already referred
// - Receiver >= 50 points at accept

const axios = require('axios');

const SERVER_URL = process.env.SERVER_URL || 'http://localhost:3001';
const USER_A = process.env.USER_A; // referrer uid
const USER_B = process.env.USER_B; // receiver uid
const ID_TOKEN_A = process.env.ID_TOKEN_A; // optional Firebase ID token for A
const ID_TOKEN_B = process.env.ID_TOKEN_B; // optional Firebase ID token for B
const SERVICE_ACCOUNT_PATH = process.env.SERVICE_ACCOUNT; // optional

let admin;
let db;
if (SERVICE_ACCOUNT_PATH) {
  try {
    admin = require('firebase-admin');
    admin.initializeApp({ credential: admin.credential.cert(require(SERVICE_ACCOUNT_PATH)) });
    db = admin.firestore();
    console.log('✅ Firebase Admin initialized');
  } catch (e) {
    console.warn('⚠️ Failed to initialize Firebase Admin:', e.message);
  }
}

if (!USER_A || !USER_B) {
  console.error('❌ Missing env: USER_A and USER_B required');
  process.exit(1);
}

function headersFor(uid, idToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (ID_TOKEN_A || ID_TOKEN_B) {
    if (!idToken) throw new Error('ID token required but not provided');
    headers['Authorization'] = `Bearer ${idToken}`;
  } else {
    headers['x-user-id'] = uid; // dev-only fallback
  }
  return headers;
}

async function codeForA() {
  const res = await axios.post(`${SERVER_URL}/referrals/create`, {}, { headers: headersFor(USER_A, ID_TOKEN_A) });
  return res.data.code;
}

async function tryAccept(uid, idToken, code) {
  try {
    const res = await axios.post(`${SERVER_URL}/referrals/accept`, { code, deviceId: 'guardrails-test' }, {
      headers: headersFor(uid, idToken)
    });
    console.log('✅ Accept OK:', res.data);
  } catch (e) {
    if (e.response) {
      console.log('🚫 Accept denied:', e.response.status, e.response.data);
    } else {
      console.log('🚫 Accept error:', e.message);
    }
  }
}

async function setUserPoints(uid, points) {
  if (!db) {
    console.log('⏭️ Skipping points set (no service account)');
    return;
  }
  await db.collection('users').doc(uid).set({ points }, { merge: true });
  console.log(`✅ Set points for ${uid} -> ${points}`);
}

async function main() {
  console.log('🧪 Guardrails Test starting...');
  const code = await codeForA();
  console.log('Code for A:', code);

  console.log('\n1) Self-referral (A uses own code)');
  await tryAccept(USER_A, ID_TOKEN_A, code); // expect self_referral

  console.log('\n2) Receiver already referred');
  // First accept as B (should succeed once)
  try { await tryAccept(USER_B, ID_TOKEN_B, code); } catch {}
  // Second attempt as B (should be already_referred)
  await tryAccept(USER_B, ID_TOKEN_B, code);

  console.log('\n3) Receiver >= 50 at accept');
  await setUserPoints(USER_B, 50);
  await tryAccept(USER_B, ID_TOKEN_B, code); // expect receiver_not_eligible

  console.log('\n🎉 Guardrails checks complete');
}

if (require.main === module) {
  main().catch(err => {
    console.error(err);
    process.exit(1);
  });
}



