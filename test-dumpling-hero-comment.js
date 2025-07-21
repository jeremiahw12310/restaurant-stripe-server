const axios = require('axios');

// Test the new Dumpling Hero comment generation endpoint
async function testDumplingHeroComment() {
  try {
    console.log('🤖 Testing Dumpling Hero Comment Generation...\n');
    
    // Test with the specific prompt from your example
    const testPrompt = "Me too";
    
    console.log(`📝 Testing with prompt: "${testPrompt}"`);
    
    const response = await axios.post('http://localhost:3001/generate-dumpling-hero-comment-simple', {
      prompt: testPrompt
    });
    
    console.log('✅ Response received:');
    console.log(JSON.stringify(response.data, null, 2));
    
    // Test with a different prompt
    console.log('\n📝 Testing with prompt: "I love spicy food"');
    
    const response2 = await axios.post('http://localhost:3001/generate-dumpling-hero-comment-simple', {
      prompt: "I love spicy food"
    });
    
    console.log('✅ Response received:');
    console.log(JSON.stringify(response2.data, null, 2));
    
    // Test with post context (no prompt)
    console.log('\n📝 Testing with post context (no prompt)');
    
    const postContext = {
      content: "Just tried the Spicy Pork Dumplings for the first time! 🔥 They're absolutely amazing!",
      authorName: "Sarah",
      postType: "food_review",
      imageURLs: ["https://example.com/dumpling1.jpg"],
      hashtags: ["#spicydumplings", "#dumplinghouse", "#nashvillefood"]
    };
    
    const response3 = await axios.post('http://localhost:3001/generate-dumpling-hero-comment-simple', {
      postContext: postContext
    });
    
    console.log('✅ Response received:');
    console.log(JSON.stringify(response3.data, null, 2));
    
    // Test with post context AND prompt
    console.log('\n📝 Testing with post context AND prompt: "So glad you loved them!"');
    
    const response4 = await axios.post('http://localhost:3001/generate-dumpling-hero-comment-simple', {
      prompt: "So glad you loved them!",
      postContext: postContext
    });
    
    console.log('✅ Response received:');
    console.log(JSON.stringify(response4.data, null, 2));
    
    // Test with menu item context
    console.log('\n📝 Testing with menu item context');
    
    const menuItemContext = {
      content: "What should I order today?",
      authorName: "Mike",
      postType: "question",
      attachedMenuItem: {
        description: "Curry Chicken Dumplings",
        price: 12.99,
        category: "Dumplings",
        isDumpling: true,
        isDrink: false
      }
    };
    
    const response5 = await axios.post('http://localhost:3001/generate-dumpling-hero-comment-simple', {
      postContext: menuItemContext
    });
    
    console.log('✅ Response received:');
    console.log(JSON.stringify(response5.data, null, 2));
    
    // Test with poll context
    console.log('\n📝 Testing with poll context');
    
    const pollContext = {
      content: "Vote for your favorite!",
      authorName: "Dumpling House",
      postType: "poll",
      poll: {
        question: "Which dumpling style is your favorite?",
        options: [
          { text: "Steamed", voteCount: 45 },
          { text: "Pan-fried", voteCount: 32 }
        ],
        totalVotes: 77
      }
    };
    
    const response6 = await axios.post('http://localhost:3001/generate-dumpling-hero-comment-simple', {
      postContext: pollContext
    });
    
    console.log('✅ Response received:');
    console.log(JSON.stringify(response6.data, null, 2));
    
  } catch (error) {
    console.error('❌ Error testing Dumpling Hero comment generation:', error.response?.data || error.message);
  }
}

// Run the test
testDumplingHeroComment(); 