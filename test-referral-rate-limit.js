require('dotenv').config();
const axios = require('axios');

const baseUrl = process.env.BACKEND_BASE_URL || 'https://restaurant-stripe-server-1.onrender.com';
const token = process.env.FIREBASE_ID_TOKEN;

async function hit(path, body) {
  return axios.post(`${baseUrl}${path}`, body, {
    validateStatus: () => true,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    }
  });
}

async function run() {
  if (!token) {
    console.error('Missing FIREBASE_ID_TOKEN in env. Set it to an admin/user token for testing.');
    process.exit(1);
  }

  console.log(`Testing referral rate limiting against ${baseUrl}`);
  console.log('Expect: after ~5 requests/min/user, you should see HTTP 429.\n');

  // Use create because it’s harmless and token-protected.
  for (let i = 1; i <= 8; i++) {
    const res = await hit('/referrals/create', {});
    console.log(`#${i} -> ${res.status}`, typeof res.data === 'object' ? res.data.errorCode || '' : '');
    if (res.status === 429) {
      console.log('✅ Rate limit triggered as expected');
      break;
    }
    await new Promise((r) => setTimeout(r, 250));
  }
}

run().catch((e) => {
  console.error('Test failed:', e?.message || e);
  process.exit(1);
});

