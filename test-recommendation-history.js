#!/usr/bin/env node

/**
 * Test script for Recommendation History Tracking System
 * This script tests the server's ability to handle previous recommendations
 */

const axios = require('axios');

const SERVER_URL = 'http://localhost:3001'; // Updated to correct port

// Sample menu items for testing
const sampleMenuItems = [
  { id: "Curry Chicken", category: "Dumplings", price: 12.99, description: "Delicious curry chicken dumplings" },
  { id: "Spicy Pork", category: "Dumplings", price: 14.99, description: "Spicy pork dumplings" },
  { id: "Pork & Cabbage", category: "Dumplings", price: 14.99, description: "Classic pork and cabbage dumplings" },
  { id: "Edamame", category: "Appetizers", price: 4.99, description: "Steamed edamame beans" },
  { id: "Asian Pickled Cucumbers", category: "Appetizers", price: 5.75, description: "Refreshing pickled cucumbers" },
  { id: "Hot & Sour Soup", category: "Soup", price: 5.95, description: "Traditional hot and sour soup" },
  { id: "Bubble Milk Tea", category: "Milk Tea", price: 5.90, description: "Classic bubble milk tea" },
  { id: "Peach Strawberry", category: "Fruit Tea", price: 6.75, description: "Refreshing peach strawberry tea" },
  { id: "Capped Thai Brown Sugar", category: "Milk Tea", price: 6.90, description: "Thai brown sugar milk tea" }
];

// Sample dietary preferences
const samplePreferences = {
  likesSpicyFood: false,
  dislikesSpicyFood: false,
  hasPeanutAllergy: false,
  isVegetarian: false,
  hasLactoseIntolerance: false,
  doesntEatPork: false
};

async function testRecommendationHistory() {
  console.log('🧪 Testing Recommendation History Tracking System');
  console.log('==================================================\n');

  const previousRecommendations = [];

  try {
    // Test 1: Generate first combo (no previous recommendations)
    console.log('📋 Test 1: Generate first combo (no previous recommendations)');
    const combo1 = await generateCombo("TestUser", samplePreferences, sampleMenuItems, []);
    console.log(`✅ Combo 1: ${combo1.items.map(item => item.id).join(', ')}`);
    previousRecommendations.push(combo1);
    console.log('');

    // Test 2: Generate second combo (with 1 previous recommendation)
    console.log('📋 Test 2: Generate second combo (with 1 previous recommendation)');
    const combo2 = await generateCombo("TestUser", samplePreferences, sampleMenuItems, previousRecommendations);
    console.log(`✅ Combo 2: ${combo2.items.map(item => item.id).join(', ')}`);
    previousRecommendations.push(combo2);
    console.log('');

    // Test 3: Generate third combo (with 2 previous recommendations)
    console.log('📋 Test 3: Generate third combo (with 2 previous recommendations)');
    const combo3 = await generateCombo("TestUser", samplePreferences, sampleMenuItems, previousRecommendations);
    console.log(`✅ Combo 3: ${combo3.items.map(item => item.id).join(', ')}`);
    previousRecommendations.push(combo3);
    console.log('');

    // Test 4: Generate fourth combo (with 3 previous recommendations)
    console.log('📋 Test 4: Generate fourth combo (with 3 previous recommendations)');
    const combo4 = await generateCombo("TestUser", samplePreferences, sampleMenuItems, previousRecommendations);
    console.log(`✅ Combo 4: ${combo4.items.map(item => item.id).join(', ')}`);
    console.log('');

    // Test 5: Check for variety
    console.log('📊 Variety Analysis:');
    const allItems = [...combo1.items, ...combo2.items, ...combo3.items, ...combo4.items];
    const itemCounts = {};
    allItems.forEach(item => {
      itemCounts[item.id] = (itemCounts[item.id] || 0) + 1;
    });

    const repeatedItems = Object.entries(itemCounts).filter(([item, count]) => count > 1);
    if (repeatedItems.length > 0) {
      console.log(`⚠️  Repeated items found: ${repeatedItems.map(([item, count]) => `${item} (${count}x)`).join(', ')}`);
    } else {
      console.log('✅ No repeated items - excellent variety!');
    }

    console.log('\n🎉 All tests completed successfully!');

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    if (error.response) {
      console.error('Response data:', error.response.data);
    }
  }
}

async function generateCombo(userName, dietaryPreferences, menuItems, previousRecommendations) {
  const requestBody = {
    userName,
    dietaryPreferences,
    menuItems,
    previousRecommendations: previousRecommendations.length > 0 ? previousRecommendations : undefined
  };

  const response = await axios.post(`${SERVER_URL}/generate-combo`, requestBody, {
    headers: {
      'Content-Type': 'application/json'
    },
    timeout: 30000 // 30 second timeout
  });

  return response.data.combo;
}

// Run the test
if (require.main === module) {
  testRecommendationHistory().catch(console.error);
}

module.exports = { testRecommendationHistory }; 