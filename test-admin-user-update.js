require('dotenv').config();
const axios = require('axios');

const baseUrl = process.env.BACKEND_BASE_URL || 'https://restaurant-stripe-server-1.onrender.com';
const adminToken = process.env.FIREBASE_ID_TOKEN;
const testUserId = process.env.TEST_USER_ID;

async function testAdminUserUpdate() {
  console.log(`🧪 Testing /admin/users/update endpoint at ${baseUrl}\n`);

  if (!adminToken) {
    console.error('❌ FIREBASE_ID_TOKEN environment variable not set');
    console.log('   Set it to your Firebase ID token to test admin authentication');
    return;
  }

  if (!testUserId) {
    console.error('❌ TEST_USER_ID environment variable not set');
    console.log('   Set it to a user ID you want to update');
    return;
  }

  try {
    console.log('📤 Sending request to update user...');
    console.log(`   User ID: ${testUserId}`);
    console.log(`   Endpoint: ${baseUrl}/admin/users/update\n`);

    const response = await axios.post(
      `${baseUrl}/admin/users/update`,
      {
        userId: testUserId,
        points: 100,
        phone: '+1234567890',
        isAdmin: true,
        isVerified: true
      },
      {
        headers: {
          'Authorization': `Bearer ${adminToken}`,
          'Content-Type': 'application/json'
        }
      }
    );

    console.log('✅ Request successful!');
    console.log('📥 Response status:', response.status);
    console.log('📥 Response data:', JSON.stringify(response.data, null, 2));
  } catch (error) {
    console.error('❌ Request failed!');
    
    if (error.response) {
      console.error('📥 HTTP Status:', error.response.status);
      console.error('📥 Response headers:', error.response.headers);
      console.error('📥 Response data:', JSON.stringify(error.response.data, null, 2));
      
      if (error.response.status === 401) {
        console.error('\n💡 This means admin authentication failed. Check:');
        console.error('   - Your Firebase ID token is valid');
        console.error('   - Your user has isAdmin=true in Firestore');
      } else if (error.response.status === 403) {
        console.error('\n💡 This means permission denied. Check:');
        console.error('   - Your user has isAdmin=true in Firestore');
        console.error('   - The backend service account has proper Firestore permissions');
      } else if (error.response.status === 404) {
        console.error('\n💡 User not found. Check:');
        console.error('   - The TEST_USER_ID exists in Firestore');
      }
    } else if (error.request) {
      console.error('📥 No response received');
      console.error('   Request:', error.request);
      console.error('\n💡 This usually means:');
      console.error('   - The backend is not reachable');
      console.error('   - Network connectivity issue');
      console.error('   - Backend URL is incorrect');
    } else {
      console.error('📥 Error setting up request:', error.message);
    }
  }
}

testAdminUserUpdate();
