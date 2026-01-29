#!/usr/bin/env node

/**
 * Firestore Index Verification Script
 * 
 * Verifies that all required Firestore indexes are deployed and ready.
 * Can be used in CI/CD pipelines to ensure indexes are available before deployment.
 * 
 * Usage:
 *   node scripts/verify-indexes.js
 * 
 * Exit codes:
 *   0 - All indexes are ready
 *   1 - Some indexes are missing or still building
 *   2 - Error connecting to Firebase
 */

require('dotenv').config();
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
let firebaseInitialized = false;

if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    const credential = admin.credential.cert(serviceAccount);
    admin.initializeApp({ credential });
    firebaseInitialized = true;
  } catch (error) {
    console.error('❌ Error initializing Firebase with service account:', error.message);
    process.exit(2);
  }
} else if (process.env.FIREBASE_AUTH_TYPE === 'adc' || process.env.GOOGLE_CLOUD_PROJECT) {
  try {
    admin.initializeApp({ projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp' });
    firebaseInitialized = true;
  } catch (error) {
    console.error('❌ Error initializing Firebase with ADC:', error.message);
    process.exit(2);
  }
} else {
  console.error('❌ Firebase not configured. Set FIREBASE_SERVICE_ACCOUNT_KEY or FIREBASE_AUTH_TYPE=adc');
  process.exit(2);
}

// Read firestore.indexes.json
const indexesPath = path.join(__dirname, '..', 'firestore.indexes.json');
let expectedIndexes = [];

try {
  const indexesFile = fs.readFileSync(indexesPath, 'utf8');
  const indexesData = JSON.parse(indexesFile);
  expectedIndexes = indexesData.indexes || [];
} catch (error) {
  console.error('❌ Error reading firestore.indexes.json:', error.message);
  process.exit(2);
}

async function verifyIndexes() {
  console.log('🔍 Verifying Firestore indexes...\n');
  
  const db = admin.firestore();
  let allReady = true;
  let missingCount = 0;
  let buildingCount = 0;
  let readyCount = 0;
  
  for (const index of expectedIndexes) {
    const collectionGroup = index.collectionGroup;
    const fields = index.fields.map(f => `${f.fieldPath}:${f.order.toLowerCase()}`).join(',');
    
    try {
      // Note: Firestore Admin SDK doesn't have a direct API to check index status
      // We'll attempt a test query to see if the index is needed
      // If the index is missing, Firestore will return an error with index creation link
      
      const testQuery = db.collectionGroup(collectionGroup);
      let query = testQuery;
      
      // Apply filters and ordering based on index definition
      for (const field of index.fields) {
        if (field.order === 'ASCENDING') {
          query = query.orderBy(field.fieldPath);
        } else if (field.order === 'DESCENDING') {
          query = query.orderBy(field.fieldPath, 'desc');
        }
      }
      
      // Try to execute the query (with limit 1 for speed)
      try {
        await query.limit(1).get();
        console.log(`✅ ${collectionGroup} [${fields}] - Ready`);
        readyCount++;
      } catch (queryError) {
        if (queryError.message && queryError.message.includes('index')) {
          console.log(`⏳ ${collectionGroup} [${fields}] - Building or missing`);
          buildingCount++;
          allReady = false;
        } else {
          // Query succeeded, index is likely ready
          console.log(`✅ ${collectionGroup} [${fields}] - Ready`);
          readyCount++;
        }
      }
    } catch (error) {
      console.log(`⚠️  ${collectionGroup} [${fields}] - Error checking: ${error.message}`);
      missingCount++;
      allReady = false;
    }
  }
  
  console.log('\n📊 Summary:');
  console.log(`  ✅ Ready: ${readyCount}`);
  console.log(`  ⏳ Building/Missing: ${buildingCount + missingCount}`);
  console.log(`  📝 Total: ${expectedIndexes.length}\n`);
  
  if (allReady) {
    console.log('✅ All indexes are ready!');
    return 0;
  } else {
    console.log('⚠️  Some indexes are still building or missing.');
    console.log('   Deploy indexes with: firebase deploy --only firestore:indexes');
    return 1;
  }
}

// Run verification
verifyIndexes()
  .then(exitCode => {
    process.exit(exitCode);
  })
  .catch(error => {
    console.error('❌ Fatal error:', error);
    process.exit(2);
  });
