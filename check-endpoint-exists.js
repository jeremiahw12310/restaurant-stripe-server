require('dotenv').config();
const axios = require('axios');

const baseUrl = process.env.BACKEND_BASE_URL || 'https://restaurant-stripe-server-1.onrender.com';

async function checkEndpoint() {
  console.log(`🔍 Checking if /admin/users/update endpoint exists at ${baseUrl}\n`);

  try {
    // Try to hit the endpoint without auth to see if it exists
    // It should return 401 (unauthorized) if it exists, or 404 if it doesn't
    const response = await axios.post(
      `${baseUrl}/admin/users/update`,
      { userId: 'test' },
      {
        validateStatus: () => true, // Don't throw on any status
        headers: {
          'Content-Type': 'application/json'
        }
      }
    );

    console.log(`📥 Response status: ${response.status}`);
    console.log(`📥 Response data:`, JSON.stringify(response.data, null, 2));

    if (response.status === 401) {
      console.log('\n✅ Endpoint EXISTS! (Got 401 - authentication required, which is expected)');
      console.log('   The endpoint is deployed and working.');
      console.log('   The issue is likely with authentication or permissions.');
    } else if (response.status === 404) {
      console.log('\n❌ Endpoint NOT FOUND (404)');
      console.log('   The /admin/users/update endpoint does not exist on the server.');
      console.log('   You need to redeploy backend-deploy/server.js to Render.');
    } else {
      console.log(`\n⚠️  Unexpected status: ${response.status}`);
      console.log('   The endpoint might exist but is behaving unexpectedly.');
    }
  } catch (error) {
    if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
      console.error('❌ Cannot reach server');
      console.error('   Check that the backend URL is correct:', baseUrl);
    } else {
      console.error('❌ Error:', error.message);
    }
  }
}

checkEndpoint();
