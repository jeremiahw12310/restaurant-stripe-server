const admin = require('firebase-admin');

// Initialize Firebase Admin SDK with Application Default Credentials
admin.initializeApp({
  projectId: 'dumplinghouseapp'
});

const db = admin.firestore();

async function testAuthenticationAndPermissions() {
  try {
    console.log('🔍 Testing authentication and permissions...');
    
    // Test 1: Check if we can access the users collection
    const usersSnapshot = await db.collection('users').limit(1).get();
    console.log(`✅ Users collection accessible. Found ${usersSnapshot.size} users`);
    
    if (usersSnapshot.empty) {
      console.log('❌ No users found in the database');
      return;
    }
    
    const userId = usersSnapshot.docs[0].id;
    console.log(`👤 Testing with user ID: ${userId}`);
    
    // Test 2: Check if we can access pointsTransactions for this user
    const pointsSnapshot = await db.collection('pointsTransactions')
      .where('userId', '==', userId)
      .limit(1)
      .get();
    
    console.log(`✅ Points transactions query successful. Found ${pointsSnapshot.size} transactions for user ${userId}`);
    
    // Test 3: Check if we can write a test transaction
    const testTransaction = {
      id: `test-auth-${Date.now()}`,
      userId: userId,
      type: 'test',
      amount: 10,
      description: 'Authentication test transaction',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isEarned: true
    };
    
    await db.collection('pointsTransactions').doc(testTransaction.id).set(testTransaction);
    console.log('✅ Successfully wrote test transaction');
    
    // Test 4: Verify the transaction was written
    const verifySnapshot = await db.collection('pointsTransactions')
      .where('userId', '==', userId)
      .where('id', '==', testTransaction.id)
      .get();
    
    console.log(`✅ Transaction verification successful. Found ${verifySnapshot.size} matching transactions`);
    
    // Test 5: Clean up test transaction
    await db.collection('pointsTransactions').doc(testTransaction.id).delete();
    console.log('✅ Test transaction cleaned up');
    
    console.log('🎉 All authentication and permission tests passed!');
    
  } catch (error) {
    console.error('❌ Error during authentication test:', error.message);
    console.error('Full error:', error);
  }
}

testAuthenticationAndPermissions(); 