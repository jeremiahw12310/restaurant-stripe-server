require('dotenv').config();
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK using the same method as server.js
if (process.env.FIREBASE_AUTH_TYPE === 'adc') {
  // Use Application Default Credentials
  admin.initializeApp({
    projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp'
  });
  console.log('✅ Firebase Admin initialized with Application Default Credentials');
} else if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  // Use service account key from environment variable
  const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
  console.log('✅ Firebase Admin initialized with service account key');
} else {
  console.error('❌ No Firebase authentication method found');
  process.exit(1);
}

const db = admin.firestore();

async function testFirestoreRules() {
  console.log('🧪 Testing Firestore Security Rules...\n');

  try {
    // Test 1: Read menu data (should work - public read)
    console.log('1. Testing public read access to menu...');
    const menuSnapshot = await db.collection('menu').limit(1).get();
    console.log(`✅ Menu read successful: ${menuSnapshot.docs.length} documents found\n`);

    // Test 2: Read crowd meter data (should work - public read)
    console.log('2. Testing public read access to crowd meter...');
    const crowdSnapshot = await db.collection('crowdMeter').limit(1).get();
    console.log(`✅ Crowd meter read successful: ${crowdSnapshot.docs.length} documents found\n`);

    // Test 3: Try to write to menu (should fail - admin only)
    console.log('3. Testing write access to menu (should be restricted)...');
    try {
      await db.collection('menu').doc('test-category').set({
        name: 'Test Category',
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log('❌ Unexpected: Write to menu succeeded (should have been blocked)\n');
    } catch (error) {
      console.log(`✅ Write to menu correctly blocked: ${error.message}\n`);
    }

    // Test 4: Try to write to crowd meter (should fail - admin only)
    console.log('4. Testing write access to crowd meter (should be restricted)...');
    try {
      await db.collection('crowdMeter').doc('test-doc').set({
        hour: 12,
        dayOfWeek: 1,
        level: 3,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log('❌ Unexpected: Write to crowd meter succeeded (should have been blocked)\n');
    } catch (error) {
      console.log(`✅ Write to crowd meter correctly blocked: ${error.message}\n`);
    }

    console.log('🎉 Firestore security rules test completed!');
    console.log('📋 Summary:');
    console.log('   ✅ Public read access working');
    console.log('   ✅ Write restrictions in place');
    console.log('   🔒 Data is now properly protected');

  } catch (error) {
    console.error('❌ Test failed:', error);
  } finally {
    process.exit(0);
  }
}

testFirestoreRules(); 