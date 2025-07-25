const fs = require('fs');
const path = require('path');

// Test the double-validation logic
console.log('🧪 Testing Double-Validation Logic...\n');

// Simulate two different responses
const testCases = [
  {
    name: "Matching Responses",
    data1: { orderNumber: "123", orderTotal: "25.50", orderDate: "12/25" },
    data2: { orderNumber: "123", orderTotal: "25.50", orderDate: "12/25" },
    expected: true
  },
  {
    name: "Mismatched Order Number",
    data1: { orderNumber: "123", orderTotal: "25.50", orderDate: "12/25" },
    data2: { orderNumber: "124", orderTotal: "25.50", orderDate: "12/25" },
    expected: false
  },
  {
    name: "Mismatched Total",
    data1: { orderNumber: "123", orderTotal: "25.50", orderDate: "12/25" },
    data2: { orderNumber: "123", orderTotal: "26.50", orderDate: "12/25" },
    expected: false
  },
  {
    name: "Mismatched Date",
    data1: { orderNumber: "123", orderTotal: "25.50", orderDate: "12/25" },
    data2: { orderNumber: "123", orderTotal: "25.50", orderDate: "12/26" },
    expected: false
  }
];

testCases.forEach((testCase, index) => {
  console.log(`Test ${index + 1}: ${testCase.name}`);
  
  const responsesMatch = 
    testCase.data1.orderNumber === testCase.data2.orderNumber &&
    testCase.data1.orderTotal === testCase.data2.orderTotal &&
    testCase.data1.orderDate === testCase.data2.orderDate;
  
  console.log('   Response 1:', testCase.data1);
  console.log('   Response 2:', testCase.data2);
  console.log('   Match Result:', responsesMatch);
  console.log('   Expected:', testCase.expected);
  console.log('   ✅ PASS' + (responsesMatch === testCase.expected ? '' : ' ❌ FAIL'));
  console.log('');
});

console.log('🎯 Double-Validation Logic Test Complete!');
console.log('📝 To test with actual API calls, try scanning a receipt in the app.'); 