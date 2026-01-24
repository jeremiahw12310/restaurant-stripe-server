#!/usr/bin/env node

/**
 * Calls the /admin/users/cleanup-orphans endpoint to remove orphaned accounts
 * 
 * Usage:
 *   node test-cleanup-orphans.js
 * 
 * Environment variables:
 *   SERVER_URL - Backend server URL (default: http://localhost:3001)
 *   ID_TOKEN - Firebase ID token for an admin user (required)
 */

const axios = require('axios');

const SERVER_URL = process.env.SERVER_URL || 'http://localhost:3001';
const ID_TOKEN = process.env.ID_TOKEN;

if (!ID_TOKEN) {
  console.error('❌ Missing ID_TOKEN environment variable');
  console.error('   You need a Firebase ID token from an admin user.');
  console.error('');
  console.error('   To get one:');
  console.error('   1. Log in to the app as an admin user');
  console.error('   2. In the app, open developer tools or use Firebase console');
  console.error('   3. Get the ID token from Auth.currentUser.getIdToken()');
  console.error('');
  console.error('   Then run: ID_TOKEN=<token> node test-cleanup-orphans.js');
  process.exit(1);
}

async function cleanupOrphans() {
  try {
    console.log('🧹 Starting orphaned accounts cleanup...');
    console.log(`📡 Calling: ${SERVER_URL}/admin/users/cleanup-orphans`);
    console.log('');
    
    const response = await axios.post(
      `${SERVER_URL}/admin/users/cleanup-orphans`,
      {},
      {
        headers: {
          'Authorization': `Bearer ${ID_TOKEN}`,
          'Content-Type': 'application/json'
        }
      }
    );
    
    console.log('✅ Cleanup completed successfully!');
    console.log('');
    console.log('Results:');
    console.log(`  - Documents checked: ${response.data.checkedCount}`);
    console.log(`  - Orphaned accounts deleted: ${response.data.deletedCount}`);
    console.log(`  - Message: ${response.data.message}`);
    console.log('');
    
    if (response.data.deletedCount > 0) {
      console.log('🎉 Successfully removed duplicate/orphaned accounts!');
    } else {
      console.log('✨ No orphaned accounts found. Database is clean!');
    }
    
  } catch (error) {
    console.error('❌ Error during cleanup:');
    if (error.response) {
      console.error(`   Status: ${error.response.status}`);
      console.error(`   Message: ${error.response.data?.error || error.response.statusText}`);
      
      if (error.response.status === 401) {
        console.error('');
        console.error('   Authentication failed. Make sure your ID_TOKEN is valid.');
      } else if (error.response.status === 403) {
        console.error('');
        console.error('   Access denied. Make sure the user has admin privileges.');
      }
    } else {
      console.error(`   ${error.message}`);
      console.error('');
      console.error('   Make sure the server is running and SERVER_URL is correct.');
    }
    process.exit(1);
  }
}

cleanupOrphans();
