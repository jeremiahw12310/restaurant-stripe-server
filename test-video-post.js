const axios = require('axios');

// Test video post with caption "Meow"
async function testVideoPost() {
  try {
    console.log('🤖 Testing Video Post with Caption "Meow"...\n');
    
    const videoPostContext = {
      content: "https://firebasestorage.googleapis.com:443/v0/b/dumplinghouseapp.firebasestorage.app/o/community_posts%2F9EA92B84-E817-478B-9499-3D3071DF161F.mp4?alt=media&token=f0f87634-f411-4e91-af94-85d5bae8895f",
      authorName: "Jeremiah",
      postType: "video",
      caption: "Meow",
      videoURL: "https://firebasestorage.googleapis.com:443/v0/b/dumplinghouseapp.firebasestorage.app/o/community_posts%2F9EA92B84-E817-478B-9499-3D3071DF161F.mp4?alt=media&token=f0f87634-f411-4e91-af94-85d5bae8895f",
      imageURLs: [],
      hashtags: []
    };
    
    console.log('📝 Testing video post with caption: "Meow"');
    console.log('📊 Post Context:', JSON.stringify(videoPostContext, null, 2));
    
    const response = await axios.post('http://localhost:3001/generate-dumpling-hero-comment-simple', {
      postContext: videoPostContext
    });
    
    console.log('✅ Response received:');
    console.log(JSON.stringify(response.data, null, 2));
    
  } catch (error) {
    console.error('❌ Error testing video post:', error.response?.data || error.message);
  }
}

// Run the test
testVideoPost(); 