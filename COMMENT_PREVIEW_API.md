# Dumpling Hero Comment Preview API

## Overview

The Dumpling Hero Comment Preview API allows you to generate a preview of a Dumpling Hero comment before actually posting it, similar to how the post generation works. This gives you a chance to review the comment before it goes live.

## Endpoint

**URL:** `POST /preview-dumpling-hero-comment`

**Base URL:** 
- Local: `http://localhost:3001`
- Production: `https://your-production-domain.com`

## Request Format

### Headers
```
Content-Type: application/json
```

### Request Body
```json
{
  "prompt": "string (optional)",
  "postContext": "object (optional)"
}
```

**Parameters:**
- `prompt` (optional): A specific prompt or context for the comment generation
- `postContext` (optional): Detailed information about the post being commented on

## Response Format

### Success Response
```json
{
  "success": true,
  "comment": {
    "commentText": "The generated comment text with emojis"
  }
}
```

### Error Response
```json
{
  "error": "Error message",
  "details": "Detailed error information"
}
```

## Usage Examples

### Example 1: Preview comment for a video post
```javascript
const response = await fetch('http://localhost:3001/preview-dumpling-hero-comment', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    postContext: {
      content: "https://firebasestorage.googleapis.com:443/v0/b/dumplinghouseapp.firebasestorage.app/o/community_posts%2F9EA92B84-E817-478B-9499-3D3071DF161F.mp4?alt=media&token=f0f87634-f411-4e91-af94-85d5bae8895f",
      authorName: "Jeremiah",
      postType: "video",
      caption: "Meow",
      videoURL: "https://firebasestorage.googleapis.com:443/v0/b/dumplinghouseapp.firebasestorage.app/o/community_posts%2F9EA92B84-E817-478B-9499-3D3071DF161F.mp4?alt=media&token=f0f87634-f411-4e91-af94-85d5bae8895f",
      imageURLs: [],
      hashtags: []
    }
  })
});

const result = await response.json();
console.log('Preview comment:', result.comment.commentText);
// Output: "Meow indeed, Jeremiah! 🐱🥟 That video has me purring with excitement for dumplings! Can't wait to see what deliciousness is coming next! 😻✨"
```

### Example 2: Preview comment with prompt
```javascript
const response = await fetch('http://localhost:3001/preview-dumpling-hero-comment', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    prompt: "So glad you loved them!",
    postContext: {
      content: "Just tried the Spicy Pork Dumplings for the first time! 🔥 They're absolutely amazing!",
      authorName: "Sarah",
      postType: "food_review",
      imageURLs: ["https://example.com/dumpling1.jpg"],
      hashtags: ["#spicydumplings", "#dumplinghouse", "#nashvillefood"]
    }
  })
});

const result = await response.json();
console.log('Preview comment:', result.comment.commentText);
// Output: "So glad you loved the Spicy Pork Dumplings, Sarah! 🔥🥟 They're a flavor explosion! Can't wait for you to try more! #DumplingHouse #NashvilleFood"
```

## Integration with Your App

1. **Generate Preview**: Call the preview endpoint to see what the comment will look like
2. **Show Preview**: Display the generated comment to the user
3. **User Decision**: Let the user approve, regenerate, or cancel
4. **Post Comment**: If approved, call the actual posting endpoint with the same parameters

## Benefits

- ✅ **Preview before posting** - See exactly what the comment will look like
- ✅ **Contextual responses** - Comments reference specific post details
- ✅ **Consistent personality** - Maintains Dumpling Hero's enthusiastic style
- ✅ **Error prevention** - Catch any issues before the comment goes live
- ✅ **User control** - Users can approve or regenerate comments

## Post Context Fields

The `postContext` object can include:

- `content`: The main post content
- `authorName`: Name of the post author
- `postType`: Type of post (video, food_review, question, poll, etc.)
- `caption`: Caption for video/image posts
- `videoURL`: URL of video content
- `imageURLs`: Array of image URLs
- `hashtags`: Array of hashtags
- `attachedMenuItem`: Menu item information
- `poll`: Poll information

The more context you provide, the more specific and relevant the generated comment will be! 