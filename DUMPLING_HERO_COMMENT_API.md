# Dumpling Hero Comment Generation API

## Overview

The Dumpling Hero Comment Generation API provides a simple way to generate engaging, personality-driven comments from Dumpling Hero, the official mascot of Dumpling House restaurant in Nashville, TN.

## Endpoint

**URL:** `POST /generate-dumpling-hero-comment-simple`

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
- `prompt` (optional): A specific prompt or context for the comment generation. If not provided, a random enthusiastic comment will be generated.
- `postContext` (optional): Detailed information about the post being commented on. This allows Dumpling Hero to generate contextually relevant responses.

## Response Format

### Success Response
```json
{
  "commentText": "The generated comment text with emojis"
}
```

### Error Response
```json
{
  "error": "Error message",
  "details": "Detailed error information"
}
```

## Examples

### Example 1: With a specific prompt
**Request:**
```json
{
  "prompt": "Me too"
}
```

**Response:**
```json
{
  "commentText": "Yes! Dumpling love is a universal language! 🥟❤️ Let's keep the delicious vibes flowing! ✨"
}
```

### Example 2: With a food-related prompt
**Request:**
```json
{
  "prompt": "I love spicy food"
}
```

**Response:**
```json
{
  "commentText": "Spicy food lovers unite! 🔥 Our Spicy Pork Dumplings will set your taste buds on fire! 🌶️🥟 Ready for the heat? 💪"
}
```

### Example 3: With post context (no prompt)
**Request:**
```json
{
  "postContext": {
    "content": "Just tried the Spicy Pork Dumplings for the first time! 🔥 They're absolutely amazing!",
    "authorName": "Sarah",
    "postType": "food_review",
    "imageURLs": ["https://example.com/dumpling1.jpg"],
    "hashtags": ["#spicydumplings", "#dumplinghouse", "#nashvillefood"]
  }
}
```

**Response:**
```json
{
  "commentText": "Yesss, Sarah! Those Spicy Pork Dumplings are a flavor explosion! 🔥🥟 I'm so glad you loved them! Your pic looks delicious! 🤤 #DumplingLove #NashvilleFood"
}
```

### Example 4: With post context AND prompt
**Request:**
```json
{
  "prompt": "So glad you loved them!",
  "postContext": {
    "content": "Just tried the Spicy Pork Dumplings for the first time! 🔥 They're absolutely amazing!",
    "authorName": "Sarah",
    "postType": "food_review"
  }
}
```

**Response:**
```json
{
  "commentText": "So glad you loved the Spicy Pork Dumplings, Sarah! 🔥🥟 They're a flavor explosion! Can't wait for you to try more! #spicydumplings #dumplinghouse"
}
```

### Example 5: With menu item context
**Request:**
```json
{
  "postContext": {
    "content": "What should I order today?",
    "authorName": "Mike",
    "postType": "question",
    "attachedMenuItem": {
      "description": "Curry Chicken Dumplings",
      "price": 12.99,
      "category": "Dumplings",
      "isDumpling": true
    }
  }
}
```

**Response:**
```json
{
  "commentText": "Hey Mike! 🌟 You absolutely HAVE to try the Curry Chicken Dumplings! 🥟✨ They're only $12.99 and bursting with flavor! You won't regret it! 🤤"
}
```

### Example 6: Random comment (no prompt or context)
**Request:**
```json
{}
```

**Response:**
```json
{
  "commentText": "Just pulled these beauties out of the steamer! 🥟✨ The way the steam rises... it's like a dumpling spa day! 💆‍♂️"
}
```

## Dumpling Hero Personality

Dumpling Hero is characterized by:

### Personality Traits
- **Enthusiastic**: Always excited about dumplings and food
- **Funny**: Uses humor and puns related to food
- **Supportive**: Encouraging and positive towards users
- **Casual**: Friendly, approachable tone
- **Passionate**: Genuine love for dumplings and the restaurant
- **Context-Aware**: References specific details from posts and comments

### Comment Style
- **Length**: 50-200 characters (including emojis)
- **Emojis**: 2-5 relevant emojis per comment
- **Tone**: Naturally engaging and supportive
- **Context-Aware**: References specific details from the post being commented on
- **Variety**: Different types of responses:
  - Agreement and enthusiasm
  - Food appreciation
  - Encouragement
  - Humor
  - Support
  - Food facts

### Restaurant Information
- **Name**: Dumpling House
- **Address**: 2117 Belcourt Ave, Nashville, TN 37212
- **Phone**: +1 (615) 891-4728
- **Hours**: 
  - Sunday - Thursday: 11:30 AM - 9:00 PM
  - Friday and Saturday: 11:30 AM - 10:00 PM
- **Cuisine**: Authentic Chinese dumplings and Asian cuisine

## Post Context Structure

The `postContext` object can include the following fields:

```json
{
  "content": "string",
  "authorName": "string", 
  "postType": "string",
  "caption": "string (optional)",
  "imageURLs": ["string array (optional)"],
  "videoURL": "string (optional)",
  "hashtags": ["string array (optional)"],
  "attachedMenuItem": {
    "description": "string",
    "price": "number",
    "category": "string",
    "isDumpling": "boolean",
    "isDrink": "boolean"
  },
  "poll": {
    "question": "string",
    "options": [
      {
        "text": "string",
        "voteCount": "number"
      }
    ],
    "totalVotes": "number"
  }
}
```

## Usage Examples

### JavaScript/Node.js
```javascript
const axios = require('axios');

async function generateDumplingHeroComment(prompt, postContext) {
  try {
    const requestBody = {};
    if (prompt) requestBody.prompt = prompt;
    if (postContext) requestBody.postContext = postContext;
    
    const response = await axios.post('http://localhost:3001/generate-dumpling-hero-comment-simple', requestBody);
    
    return response.data.commentText;
  } catch (error) {
    console.error('Error generating comment:', error.response?.data || error.message);
    throw error;
  }
}

// Usage examples
// With prompt only
generateDumplingHeroComment("I'm hungry")
  .then(comment => console.log(comment))
  .catch(error => console.error(error));

// With post context
const postContext = {
  content: "Just tried the Spicy Pork Dumplings! 🔥",
  authorName: "Sarah",
  postType: "food_review"
};

generateDumplingHeroComment(null, postContext)
  .then(comment => console.log(comment))
  .catch(error => console.error(error));

// With both prompt and context
generateDumplingHeroComment("So glad you loved them!", postContext)
  .then(comment => console.log(comment))
  .catch(error => console.error(error));
```

### Python
```python
import requests

def generate_dumpling_hero_comment(prompt=None, post_context=None):
    url = "http://localhost:3001/generate-dumpling-hero-comment-simple"
    data = {}
    if prompt:
        data["prompt"] = prompt
    if post_context:
        data["postContext"] = post_context
    
    try:
        response = requests.post(url, json=data)
        response.raise_for_status()
        return response.json()["commentText"]
    except requests.exceptions.RequestException as e:
        print(f"Error generating comment: {e}")
        raise

# Usage examples
# With prompt only
comment = generate_dumpling_hero_comment("I love dumplings!")
print(comment)

# With post context
post_context = {
    "content": "Just tried the Spicy Pork Dumplings! 🔥",
    "authorName": "Sarah",
    "postType": "food_review"
}
comment = generate_dumpling_hero_comment(post_context=post_context)
print(comment)

# With both prompt and context
comment = generate_dumpling_hero_comment("So glad you loved them!", post_context)
print(comment)
```

### cURL
```bash
# With prompt
curl -X POST http://localhost:3001/generate-dumpling-hero-comment-simple \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Me too"}'

# With post context
curl -X POST http://localhost:3001/generate-dumpling-hero-comment-simple \
  -H "Content-Type: application/json" \
  -d '{
    "postContext": {
      "content": "Just tried the Spicy Pork Dumplings! 🔥",
      "authorName": "Sarah",
      "postType": "food_review"
    }
  }'

# With both prompt and post context
curl -X POST http://localhost:3001/generate-dumpling-hero-comment-simple \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "So glad you loved them!",
    "postContext": {
      "content": "Just tried the Spicy Pork Dumplings! 🔥",
      "authorName": "Sarah",
      "postType": "food_review"
    }
  }'

# Without prompt or context (random comment)
curl -X POST http://localhost:3001/generate-dumpling-hero-comment-simple \
  -H "Content-Type: application/json" \
  -d '{}'
```

## Error Handling

### Common Error Codes
- **500**: Server error (OpenAI API issues, configuration problems)
- **400**: Bad request (invalid JSON format)

### Error Response Example
```json
{
  "error": "OpenAI API key not configured",
  "message": "Please configure the OPENAI_API_KEY environment variable"
}
```

## Rate Limiting

The API uses OpenAI's GPT-4o-mini model with the following parameters:
- **Max tokens**: 200
- **Temperature**: 0.8 (for creative variation)
- **Model**: gpt-4o-mini

## Best Practices

1. **Provide Context**: When possible, include relevant prompts to get more specific and engaging comments
2. **Handle Errors**: Always implement proper error handling for network issues and API errors
3. **Cache Responses**: Consider caching responses for similar prompts to reduce API calls
4. **User Experience**: Use the generated comments to enhance user engagement in your application

## Integration Tips

- The API is designed to be lightweight and fast
- Comments are optimized for social media engagement
- The personality is consistent across all responses
- Comments are always positive and supportive
- Perfect for community engagement and customer interaction

## Testing

Use the provided test script to verify the API functionality:

```bash
node test-dumpling-hero-comment.js
```

This will test various scenarios including:
- Specific prompts
- Random comment generation
- Error handling 