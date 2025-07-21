const axios = require('axios');

// Test with the exact same data from the user's logs
async function testActualPost() {
  try {
    console.log('🤖 Testing with actual post data from user logs...\n');
    
    const actualPostContext = {
      postType: "text",
      caption: "",
      authorName: "Dumpling House",
      imageURLs: [],
      videoURL: "",
      content: "My favorite ",
      hashtags: [],
      attachedMenuItem: {
        isDrink: false,
        category: "",
        price: 5.75,
        id: "Asian Pickled Cucumbers",
        isDumpling: false,
        description: "Cucumbers ",
        imageURL: "gs://dumplinghouseapp.firebasestorage.app/asianpic.png"
      }
    };
    
    console.log('📝 Testing with prompt: "Me too"');
    console.log('📊 Post Context:', JSON.stringify(actualPostContext, null, 2));
    
    const response = await axios.post('http://localhost:3001/generate-dumpling-hero-comment-simple', {
      prompt: "Me too",
      postContext: actualPostContext
    });
    
    console.log('✅ Response received:');
    console.log(JSON.stringify(response.data, null, 2));
    
  } catch (error) {
    console.error('❌ Error testing actual post:', error.response?.data || error.message);
  }
}

// Run the test
testActualPost(); 