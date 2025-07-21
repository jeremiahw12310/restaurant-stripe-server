const axios = require('axios');

// Test the new Dumpling Hero comment preview endpoint
async function testCommentPreview() {
  try {
    console.log('🤖 Testing Dumpling Hero Comment Preview...\n');
    
    // Test video post with caption "Meow" (like the one from your logs)
    const videoPostContext = {
      content: "https://firebasestorage.googleapis.com:443/v0/b/dumplinghouseapp.firebasestorage.app/o/community_posts%2F9EA92B84-E817-478B-9499-3D3071DF161F.mp4?alt=media&token=f0f87634-f411-4e91-af94-85d5bae8895f",
      authorName: "Jeremiah",
      postType: "video",
      caption: "Meow",
      videoURL: "https://firebasestorage.googleapis.com:443/v0/b/dumplinghouseapp.firebasestorage.app/o/community_posts%2F9EA92B84-E817-478B-9499-3D3071DF161F.mp4?alt=media&token=f0f87634-f411-4e91-af94-85d5bae8895f",
      imageURLs: [],
      hashtags: []
    };
    
    console.log('📝 Testing comment preview for video post with caption: "Meow"');
    console.log('📊 Post Context:', JSON.stringify(videoPostContext, null, 2));
    
    const response = await axios.post('http://localhost:3001/preview-dumpling-hero-comment', {
      postContext: videoPostContext
    });
    
    console.log('✅ Preview Response received:');
    console.log(JSON.stringify(response.data, null, 2));
    
    // Test with a food review post
    console.log('\n📝 Testing comment preview for food review post');
    
    const foodReviewContext = {
      content: "Just tried the Spicy Pork Dumplings for the first time! 🔥 They're absolutely amazing!",
      authorName: "Sarah",
      postType: "food_review",
      imageURLs: ["https://example.com/dumpling1.jpg"],
      hashtags: ["#spicydumplings", "#dumplinghouse", "#nashvillefood"]
    };
    
    const response2 = await axios.post('http://localhost:3001/preview-dumpling-hero-comment', {
      postContext: foodReviewContext
    });
    
    console.log('✅ Preview Response received:');
    console.log(JSON.stringify(response2.data, null, 2));
    
    // Test with a prompt
    console.log('\n📝 Testing comment preview with prompt: "So glad you loved them!"');
    
    const response3 = await axios.post('http://localhost:3001/preview-dumpling-hero-comment', {
      prompt: "So glad you loved them!",
      postContext: foodReviewContext
    });
    
    console.log('✅ Preview Response received:');
    console.log(JSON.stringify(response3.data, null, 2));
    
  } catch (error) {
    console.error('❌ Error testing comment preview:', error.response?.data || error.message);
  }
}

// Run the test
testCommentPreview(); 