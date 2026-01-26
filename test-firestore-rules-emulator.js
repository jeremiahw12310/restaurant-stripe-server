require('dotenv').config();
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  setDoc,
  updateDoc
} = require('firebase/firestore');

async function run() {
  const rules = fs.readFileSync(path.join(__dirname, 'firestore.rules'), 'utf8');
  const testEnv = await initializeTestEnvironment({
    projectId: 'restaurant-demo-security',
    firestore: { rules }
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const adminDb = context.firestore();

    await setDoc(doc(adminDb, 'users', 'admin1'), { isAdmin: true });
    await setDoc(doc(adminDb, 'users', 'staff1'), { isEmployee: true });
    await setDoc(doc(adminDb, 'users', 'user1'), { isAdmin: false });
    await setDoc(doc(adminDb, 'users', 'user2'), { isAdmin: false });

    await setDoc(doc(adminDb, 'redeemedRewards', 'reward1'), {
      userId: 'user1',
      rewardTitle: 'Test Reward',
      pointsRequired: 50,
      redemptionCode: '12345678',
      redeemedAt: new Date(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      isExpired: false,
      isUsed: false
    });

    await setDoc(doc(adminDb, 'pointsTransactions', 'tx1'), {
      userId: 'user1',
      type: 'receipt_scan',
      amount: 5,
      timestamp: new Date()
    });

    await setDoc(doc(adminDb, 'posts', 'post1'), {
      userId: 'user1',
      body: 'hello'
    });
  });

  const userDb = testEnv.authenticatedContext('user1').firestore();
  const otherDb = testEnv.authenticatedContext('user2').firestore();
  const staffDb = testEnv.authenticatedContext('staff1').firestore();

  console.log('🧪 Firestore rules: redeemedRewards read permissions');
  await assertSucceeds(getDoc(doc(userDb, 'redeemedRewards', 'reward1')));
  await assertFails(getDoc(doc(otherDb, 'redeemedRewards', 'reward1')));
  await assertSucceeds(getDoc(doc(staffDb, 'redeemedRewards', 'reward1')));

  console.log('🧪 Firestore rules: redeemedRewards update restrictions');
  await assertFails(
    updateDoc(doc(userDb, 'redeemedRewards', 'reward1'), { isUsed: true, usedAt: new Date() })
  );
  await assertFails(
    updateDoc(doc(userDb, 'redeemedRewards', 'reward1'), { isExpired: true })
  );
  await assertSucceeds(
    updateDoc(doc(staffDb, 'redeemedRewards', 'reward1'), { isUsed: true, usedAt: new Date() })
  );

  console.log('🧪 Firestore rules: pointsTransactions client writes blocked');
  await assertFails(
    setDoc(doc(userDb, 'pointsTransactions', 'tx2'), {
      userId: 'user1',
      type: 'admin_adjustment',
      amount: 10,
      timestamp: new Date()
    })
  );

  console.log('🧪 Firestore rules: posts/replies userId enforcement');
  await assertSucceeds(
    setDoc(doc(userDb, 'posts', 'post2'), { userId: 'user1', body: 'ok' })
  );
  await assertFails(
    setDoc(doc(userDb, 'posts', 'post3'), { userId: 'user2', body: 'spoof' })
  );

  await assertSucceeds(
    setDoc(doc(userDb, 'posts', 'post1', 'replies', 'reply1'), {
      userId: 'user1',
      body: 'reply'
    })
  );
  await assertFails(
    setDoc(doc(userDb, 'posts', 'post1', 'replies', 'reply2'), {
      userId: 'user2',
      body: 'spoof reply'
    })
  );

  console.log('✅ Firestore rules emulator tests passed');
  await testEnv.cleanup();
}

run().catch((error) => {
  console.error('❌ Firestore rules emulator tests failed:', error);
  process.exit(1);
});
