#!/usr/bin/env node

/**
 * Firebase Menu Data Cleanup Script
 * 
 * This script helps clean up duplicate and inconsistent menu items in Firebase.
 * Run this script to identify and fix data issues.
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
if (process.env.FIREBASE_AUTH_TYPE === 'adc') {
  admin.initializeApp({
    projectId: process.env.GOOGLE_CLOUD_PROJECT || 'dumplinghouseapp'
  });
} else if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
} else {
  console.error('❌ No Firebase authentication configured');
  process.exit(1);
}

const db = admin.firestore();

async function analyzeMenuData() {
  console.log('🔍 Analyzing menu data...');
  
  try {
    const categoriesSnapshot = await db.collection('menu').get();
    const allItems = [];
    const duplicates = [];
    const inconsistencies = [];
    
    for (const categoryDoc of categoriesSnapshot.docs) {
      const categoryId = categoryDoc.id;
      console.log(`\n📁 Processing category: ${categoryId}`);
      
      const itemsSnapshot = await db.collection('menu').doc(categoryId).collection('items').get();
      
      itemsSnapshot.forEach(itemDoc => {
        const itemData = itemDoc.data();
        const item = {
          id: itemData.id || itemDoc.id,
          description: itemData.description || '',
          price: itemData.price || 0.0,
          category: categoryId,
          docId: itemDoc.id
        };
        
        allItems.push(item);
      });
    }
    
    console.log(`\n📊 Total items found: ${allItems.length}`);
    
    // Find duplicates
    const seen = new Map();
    allItems.forEach(item => {
      const key = `${item.id.toLowerCase().trim()}_${item.price}`;
      if (seen.has(key)) {
        duplicates.push({
          original: seen.get(key),
          duplicate: item
        });
      } else {
        seen.set(key, item);
      }
    });
    
    // Find inconsistencies
    allItems.forEach(item => {
      if (!item.id || item.id.trim() === '') {
        inconsistencies.push({
          type: 'empty_id',
          item: item
        });
      }
      
      if (item.price <= 0) {
        inconsistencies.push({
          type: 'invalid_price',
          item: item
        });
      }
      
      if (item.id.includes('🫛') || item.id.includes('🍑') || item.id.includes('🍍') || item.id.includes('🍓')) {
        inconsistencies.push({
          type: 'emoji_in_id',
          item: item
        });
      }
    });
    
    // Report findings
    console.log('\n🔍 ANALYSIS RESULTS:');
    console.log('==================');
    
    if (duplicates.length > 0) {
      console.log(`\n❌ DUPLICATES FOUND (${duplicates.length}):`);
      duplicates.forEach((dup, index) => {
        console.log(`${index + 1}. "${dup.original.id}" (${dup.original.category}) - $${dup.original.price}`);
        console.log(`   Duplicate: "${dup.duplicate.id}" (${dup.duplicate.category}) - $${dup.duplicate.price}`);
      });
    } else {
      console.log('\n✅ No duplicates found');
    }
    
    if (inconsistencies.length > 0) {
      console.log(`\n⚠️ INCONSISTENCIES FOUND (${inconsistencies.length}):`);
      inconsistencies.forEach((inc, index) => {
        console.log(`${index + 1}. ${inc.type.toUpperCase()}: "${inc.item.id}" (${inc.item.category})`);
      });
    } else {
      console.log('\n✅ No inconsistencies found');
    }
    
    // Show category breakdown
    const categoryCounts = {};
    allItems.forEach(item => {
      categoryCounts[item.category] = (categoryCounts[item.category] || 0) + 1;
    });
    
    console.log('\n📈 CATEGORY BREAKDOWN:');
    Object.entries(categoryCounts).forEach(([category, count]) => {
      console.log(`   ${category}: ${count} items`);
    });
    
    return {
      totalItems: allItems.length,
      duplicates: duplicates,
      inconsistencies: inconsistencies,
      categoryCounts: categoryCounts
    };
    
  } catch (error) {
    console.error('❌ Error analyzing menu data:', error);
    throw error;
  }
}

async function cleanupMenuData() {
  console.log('🧹 Starting menu data cleanup...');
  
  try {
    const analysis = await analyzeMenuData();
    
    if (analysis.duplicates.length === 0 && analysis.inconsistencies.length === 0) {
      console.log('\n✅ No cleanup needed - data is already clean!');
      return;
    }
    
    console.log('\n🔄 Starting cleanup process...');
    
    // Clean up duplicates
    for (const dup of analysis.duplicates) {
      console.log(`🗑️ Removing duplicate: "${dup.duplicate.id}" from ${dup.duplicate.category}`);
      
      try {
        await db.collection('menu')
          .doc(dup.duplicate.category)
          .collection('items')
          .doc(dup.duplicate.docId)
          .delete();
        
        console.log(`✅ Removed duplicate: ${dup.duplicate.id}`);
      } catch (error) {
        console.error(`❌ Failed to remove duplicate ${dup.duplicate.id}:`, error);
      }
    }
    
    // Clean up inconsistencies
    for (const inc of analysis.inconsistencies) {
      if (inc.type === 'emoji_in_id') {
        console.log(`🎨 Cleaning emoji from: "${inc.item.id}"`);
        
        try {
          const cleanId = inc.item.id.replace(/[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]/gu, '').trim();
          
          await db.collection('menu')
            .doc(inc.item.category)
            .collection('items')
            .doc(inc.item.docId)
            .update({
              id: cleanId
            });
          
          console.log(`✅ Cleaned ID: "${inc.item.id}" -> "${cleanId}"`);
        } catch (error) {
          console.error(`❌ Failed to clean ID ${inc.item.id}:`, error);
        }
      }
    }
    
    console.log('\n✅ Cleanup completed!');
    
    // Run analysis again to confirm
    console.log('\n🔍 Running post-cleanup analysis...');
    await analyzeMenuData();
    
  } catch (error) {
    console.error('❌ Error during cleanup:', error);
    throw error;
  }
}

async function generateSampleData() {
  console.log('📝 Generating sample clean menu data...');
  
  const sampleData = {
    'appetizers': [
      { id: 'Edamame', description: 'Steamed soybeans', price: 4.99 },
      { id: 'Asian Pickled Cucumbers', description: 'Refreshing pickled cucumbers', price: 5.75 },
      { id: 'Curry Rice with Chicken', description: 'Fragrant curry rice with tender chicken', price: 7.75 },
      { id: 'Peanut Butter Pork', description: 'Savory pork with peanut sauce', price: 7.99 },
      { id: 'Spicy Tofu with Peanut Sauce', description: 'Cold spicy tofu with peanut sauce', price: 5.99 },
      { id: 'Cold Noodles with Peanut Sauce', description: 'Crab and shrimp cold noodles with peanut sauce', price: 8.35 }
    ],
    'dumplings': [
      { id: 'Chicken & Coriander', description: '12pc - Fresh chicken with coriander', price: 13.99 },
      { id: 'Curry Beef & Onion', description: '12pc - Spiced beef with onions', price: 15.99 },
      { id: 'Curry Chicken', description: '12pc - Curry-spiced chicken', price: 12.99 },
      { id: 'Pork', description: '12pc - Classic pork dumplings', price: 13.99 },
      { id: 'Pork & Cabbage', description: '12pc - Pork with fresh cabbage', price: 14.99 },
      { id: 'Pork & Chive', description: '12 piece - Pork with chives', price: 15.99 },
      { id: 'Pork & Shrimp', description: '12pc - Pork with shrimp', price: 16.99 },
      { id: 'Spicy Pork', description: '12pc - Spicy pork dumplings', price: 14.99 },
      { id: 'Veggie', description: '12pc - Vegetable dumplings', price: 13.99 }
    ],
    'sauces': [
      { id: 'Extra Dumpling Sauce', description: 'Additional dumpling sauce', price: 0.25 },
      { id: 'Secret Peanut Sauce', description: 'Our signature peanut sauce', price: 1.50 },
      { id: 'SPICY Secret Peanut Sauce', description: 'Spicy version of our peanut sauce', price: 1.50 }
    ],
    'coffee': [
      { id: 'Coffee Latte', description: 'Smooth coffee latte', price: 5.50 }
    ],
    'soda': [
      { id: 'Coke', description: 'Classic Coca-Cola', price: 2.25 },
      { id: 'Diet Coke', description: 'Diet Coca-Cola', price: 2.25 },
      { id: 'Sprite', description: 'Refreshing Sprite', price: 2.25 }
    ],
    'milk tea': [
      { id: 'Bubble Milk Tea', description: 'Classic bubble milk tea with tapioca', price: 5.90 },
      { id: 'Cookies n Cream Milk Tea', description: 'Biscoff cookies and cream milk tea', price: 6.90 },
      { id: 'Fresh Milk Tea', description: 'Fresh whole milk tea', price: 5.90 },
      { id: 'Oreo Chocolate Milk Tea', description: 'Oreo chocolate milk tea', price: 6.75 },
      { id: 'Peach Fresh Milk Tea', description: 'Peach fresh milk tea', price: 6.50 },
      { id: 'Pineapple Fresh Milk Tea', description: 'Pineapple fresh milk tea', price: 6.50 },
      { id: 'Purple Yam & Taro Fresh Milk Tea', description: 'Milk tea with taro', price: 6.95 },
      { id: 'Strawberry Fresh Milk Tea', description: 'Strawberry fresh milk tea', price: 6.75 },
      { id: 'Thai Brown Sugar Milk Tea', description: 'Thai brown sugar milk tea', price: 6.90 }
    ],
    'fruit tea': [
      { id: 'Kiwi Booster', description: 'Refreshing kiwi tea', price: 6.75 },
      { id: 'Lychee Dragonfruit', description: 'Dragon fruit and lychee tea', price: 6.50 },
      { id: 'Peach Strawberry Tea', description: 'Peach and strawberry tea', price: 6.75 },
      { id: 'Pineapple Fruit Tea', description: 'Fresh pineapple tea', price: 6.75 },
      { id: 'Tropical Passion Fruit Tea', description: 'Tropical passion fruit tea', price: 6.75 },
      { id: 'Watermelon Code', description: 'Limited time watermelon tea', price: 6.50 }
    ],
    'other': [
      { id: 'Full of Mango', description: 'Mango drink with cheese foam', price: 6.90 },
      { id: 'Grape Magic Slush', description: 'Grape slush with cheese foam', price: 6.90 },
      { id: 'Tiramisu Coco', description: 'Tiramisu coconut drink', price: 6.85 }
    ],
    'soup': [
      { id: 'Hot and Sour Soup', description: 'Traditional hot and sour soup', price: 5.95 },
      { id: 'Pork Wonton Soup', description: 'Pork wonton soup', price: 6.95 }
    ]
  };
  
  console.log('\n📋 Sample data structure:');
  Object.entries(sampleData).forEach(([category, items]) => {
    console.log(`\n${category.toUpperCase()}:`);
    items.forEach(item => {
      console.log(`  - ${item.id}: $${item.price} - ${item.description}`);
    });
  });
  
  return sampleData;
}

// Main execution
async function main() {
  const command = process.argv[2];
  
  switch (command) {
    case 'analyze':
      await analyzeMenuData();
      break;
    case 'cleanup':
      await cleanupMenuData();
      break;
    case 'sample':
      await generateSampleData();
      break;
    default:
      console.log('Usage: node cleanup-menu-data.js [analyze|cleanup|sample]');
      console.log('');
      console.log('Commands:');
      console.log('  analyze  - Analyze current menu data for issues');
      console.log('  cleanup  - Clean up duplicates and inconsistencies');
      console.log('  sample   - Generate sample clean data structure');
      break;
  }
}

if (require.main === module) {
  main().catch(console.error);
}

module.exports = {
  analyzeMenuData,
  cleanupMenuData,
  generateSampleData
}; 