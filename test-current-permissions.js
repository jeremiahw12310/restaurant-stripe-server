const admin = require('firebase-admin');

// Initialize Firebase Admin SDK with Application Default Credentials
admin.initializeApp({
  projectId: 'dumplinghouseapp'
});

const db = admin.firestore();

async function testCurrentPermissions() {
  try {
    console.log('🔍 Testing current pointsTransactions collection state...');
    
    // Test 1: Check if collection exists and is accessible
    const snapshot = await db.collection('pointsTransactions').limit(1).get();
    console.log('✅ Collection is accessible to admin');
    console.log(`📊 Found ${snapshot.size} documents in collection`);
    
    // Test 2: List all documents to see what's there
    const allDocs = await db.collection('pointsTransactions').get();
    console.log(`📋 Total documents in pointsTransactions: ${allDocs.size}`);
    
    if (allDocs.size > 0) {
      console.log('📄 Sample document:');
      const sampleDoc = allDocs.docs[0];
      console.log(JSON.stringify(sampleDoc.data(), null, 2));
    }
    
    // Test 3: Check if there are any users
    const usersSnapshot = await db.collection('users').limit(1).get();
    console.log(`👥 Users in database: ${usersSnapshot.size}`);
    
    if (usersSnapshot.size > 0) {
      const userDoc = usersSnapshot.docs[0];
      console.log(`👤 Sample user ID: ${userDoc.id}`);
      
      // Test 4: Try to query with a specific userId
      const userTransactions = await db.collection('pointsTransactions')
        .whereField('userId', '==', userDoc.id)
        .limit(5)
        .get();
      
      console.log(`🔍 Transactions for user ${userDoc.id}: ${userTransactions.size}`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error('Full error:', error);
  }
}

testCurrentPermissions(); 