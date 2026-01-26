require('dotenv').config();
const axios = require('axios');

const baseUrl = process.env.BACKEND_BASE_URL || 'http://localhost:3000';

async function testMissingToken() {
  try {
    await axios.post(`${baseUrl}/redeem-reward`, {
      userId: 'test-user',
      rewardTitle: 'Test Reward',
      rewardDescription: 'Test',
      pointsRequired: 1,
      rewardCategory: 'Test'
    });
    console.error('❌ Missing token test failed: request unexpectedly succeeded');
  } catch (error) {
    const status = error.response?.status;
    if (status === 401) {
      console.log('✅ Missing token correctly rejected (401)');
      return;
    }
    console.error(`❌ Missing token test failed: expected 401, got ${status || 'unknown'}`);
  }
}

async function testUserMismatch() {
  const token = process.env.FIREBASE_ID_TOKEN;
  const mismatchUserId = process.env.MISMATCH_USER_ID;

  if (!token || !mismatchUserId) {
    console.log('ℹ️ Skipping user mismatch test (set FIREBASE_ID_TOKEN and MISMATCH_USER_ID)');
    return;
  }

  try {
    await axios.post(
      `${baseUrl}/redeem-reward`,
      {
        userId: mismatchUserId,
        rewardTitle: 'Test Reward',
        rewardDescription: 'Test',
        pointsRequired: 1,
        rewardCategory: 'Test'
      },
      {
        headers: { Authorization: `Bearer ${token}` }
      }
    );
    console.error('❌ User mismatch test failed: request unexpectedly succeeded');
  } catch (error) {
    const status = error.response?.status;
    if (status === 403) {
      console.log('✅ User mismatch correctly rejected (403)');
      return;
    }
    console.error(`❌ User mismatch test failed: expected 403, got ${status || 'unknown'}`);
  }
}

async function run() {
  console.log(`🔐 Testing /redeem-reward auth at ${baseUrl}`);
  await testMissingToken();
  await testUserMismatch();
}

run().catch((error) => {
  console.error('❌ Redeem reward auth tests failed:', error);
  process.exit(1);
});
