require('dotenv').config();
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');
const { OpenAI } = require('openai');

const app = express();
const upload = multer({ dest: 'uploads/' });
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/', (req, res) => {
  res.json({ 
    status: 'Server is running!', 
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    server: 'BACKEND server.js with gpt-4.1-mini'
  });
});

// Check if OpenAI API key is configured
if (!process.env.OPENAI_API_KEY) {
  console.error('❌ OPENAI_API_KEY environment variable is not set!');
  app.get('/analyze-receipt', (req, res) => {
    res.status(500).json({ 
      error: 'Server configuration error: OPENAI_API_KEY not set',
      message: 'Please configure the OpenAI API key in your environment variables'
    });
  });
  
  app.post('/chat', (req, res) => {
    res.status(500).json({ 
      error: 'Server configuration error: OPENAI_API_KEY not set',
      message: 'Please configure the OpenAI API key in your environment variables'
    });
  });
} else {
  const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

  app.post('/analyze-receipt', upload.single('image'), async (req, res) => {
    try {
      console.log('📥 Received receipt analysis request');
      
      if (!req.file) {
        console.log('❌ No image file received');
        return res.status(400).json({ error: 'No image file provided' });
      }
      
      console.log('📁 Image file received:', req.file.originalname, 'Size:', req.file.size);
      
      const imagePath = req.file.path;
      const imageData = fs.readFileSync(imagePath, { encoding: 'base64' });

      const prompt = `\nYou are a receipt parser. Extract the following fields from the receipt image:\n- orderNumber: Look for the largest number on the receipt that appears as white text inside a black container/box. This is typically located under \"Nashville, TN\" and next to \"Walk In\". This is the order number.\n- orderTotal: The total amount paid (as a number, e.g. 23.45)\n- orderDate: The date of the order (in MM/DD/YYYY or YYYY-MM-DD format)\n\nRespond ONLY as a JSON object: {\"orderNumber\": \"...\", \"orderTotal\": ..., \"orderDate\": \"...\"}\nIf a field is missing, use null.\n`;

      console.log('🤖 Sending request to OpenAI...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4o",
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageData}` } }
            ]
          }
        ],
        max_tokens: 300
      });

      console.log('✅ OpenAI response received');
      
      // Clean up the uploaded file
      fs.unlinkSync(imagePath);

      const text = response.choices[0].message.content;
      console.log('📝 Raw OpenAI response:', text);
      
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        console.log('❌ Could not extract JSON from response');
        return res.status(422).json({ error: "Could not extract JSON from response", raw: text });
      }
      
      const data = JSON.parse(jsonMatch[0]);
      console.log('✅ Parsed JSON data:', data);
      
      res.json(data);
    } catch (err) {
      console.error('❌ Error processing receipt:', err);
      res.status(500).json({ error: err.message });
    }
  });

  // Chat endpoint for restaurant assistant
  app.post('/chat', async (req, res) => {
    try {
      console.log('💬 Received chat request');
      
      const { message, conversation_history, userFirstName } = req.body;
      
      if (!message) {
        return res.status(400).json({ error: 'Message is required' });
      }
      
      console.log('📝 User message:', message);
      console.log('👤 User first name:', userFirstName || 'Not provided');
      
      // Create the system prompt with restaurant information
      const userGreeting = userFirstName ? `Hello ${userFirstName}! ` : '';
      const systemPrompt = `You are Dumpling Hero, the friendly and knowledgeable assistant for Dumpling House in Nashville, TN. 

You know your name is "Dumpling Hero" and you should never refer to yourself as any other name (such as Wanyi, AI, assistant, etc). However, you do not need to mention your name in every response—just avoid using any other name.

Your tone is humorous, professional, and casual. Feel free to make light-hearted jokes and puns, but never joke about items not on the menu (for example, do not joke about soup dumplings or anything we don't serve, to avoid confusing customers).

You're passionate about dumplings and love helping customers discover our authentic Chinese cuisine.

CRITICAL HONESTY GUIDELINES:
- NEVER make up information about menu items, ingredients, or restaurant details
- If you don't know specific details about something, simply don't mention those specifics
- Focus on what you do know from the provided menu and information
- If asked about something not covered in your knowledge, suggest calling the restaurant directly
- Always prioritize accuracy over speculation

MULTILINGUAL CAPABILITIES:
- You can communicate fluently in multiple languages including but not limited to: English, Spanish, French, German, Italian, Portuguese, Chinese (Mandarin/Cantonese), Japanese, Korean, Vietnamese, Thai, Arabic, Russian, Hindi, and many others.
- ALWAYS respond in the same language that the customer uses to communicate with you.
- If a customer speaks to you in a language other than English, respond naturally in that language.
- Maintain the same warm, enthusiastic personality regardless of the language you're speaking.
- Use appropriate cultural context and expressions for the language being used.
- If you're unsure about a language, respond in English and ask if they'd prefer another language.

IMPORTANT: If a user's first name is provided (${userFirstName || 'none'}), you should use their first name in your responses to make them feel welcome and personalized.

RESTAURANT INFORMATION:
- Name: Dumpling House
- Address: 2117 Belcourt Ave, Nashville, TN 37212
- Phone: +1 (615) 891-4728
- Hours: Sunday - Thursday 11:30 AM - 9:00 PM , Friday and Saturday 11:30 AM - 10:00 PM
- Lunch Special Hours: Monday - Friday only, ends at 4:00 PM
- Cuisine: Authentic Chinese dumplings and Asian cuisine

MOST POPULAR ITEMS (ACCURATE DATA):
🥟 Most Popular Dumplings:
1. #7 Curry Chicken - $12.99 (12 pieces) / $7.00 (6 pieces lunch special)
2. #3 Spicy Pork - $14.99 (12 pieces) / $8.00 (6 pieces lunch special)  
3. #5 Pork & Cabbage - $14.99 (12 pieces) / $8.00 (6 pieces lunch special)

🧋 Most Popular Milk Tea: Capped Thai Brown Sugar - $6.90
🍹 Most Popular Fruit Tea: Peach Strawberry - $6.75

DETAILED MENU INFORMATION:
🥟 Appetizers: Edamame $4.99, Asian Pickled Cucumbers $5.75, (Crab & Shrimp) Cold Noodle w/ Peanut Sauce $8.35, Peanut Butter Pork Dumplings $7.99, Spicy Tofu $5.99, Curry Rice w/ Chicken $7.75, Jasmine White Rice $2.75 | 🍲 Soup: Hot & Sour Soup $5.95, Pork Wonton Soup $6.95 | 🍕 Pizza Dumplings: Pork (6) $8.99, Curry Beef & Onion (6) $10.99 | 🍱 Lunch Special (6): No.9 Pork $7.50, No.2 Pork & Chive $8.50, No.4 Pork Shrimp $9.00, No.5 Pork & Cabbage $8.00, No.3 Spicy Pork $8.00, No.7 Curry Chicken $7.00, No.8 Chicken & Coriander $7.50, No.1 Chicken & Mushroom $8.00, No.10 Curry Beef & Onion $8.50, No.6 Veggie $7.50 (Available Monday-Friday only, ends at 4:00 PM) | 🥟 Dumplings (12): No.9 Pork $13.99, No.2 Pork & Chive $15.99, No.4 Pork Shrimp $16.99, No.5 Pork & Cabbage $14.99, No.3 Spicy Pork $14.99, No.7 Curry Chicken $12.99, No.8 Chicken & Coriander $13.99, No.1 Chicken & Mushroom $14.99, No.10 Curry Beef & Onion $15.99, No.6 Veggie $13.99, No.12 Half/Half $15.99 | 🍹 Fruit Tea: Lychee Dragon Fruit $6.50, Grape Magic w/ Cheese Foam $6.90, Full of Mango w/ Cheese Foam $6.90, Peach Strawberry $6.75, Kiwi Booster $6.75, Watermelon Code w/ Boba Jelly $6.50, Pineapple $6.90, Winter Melon Black $6.50, Peach Oolong w/ Cheese Foam $6.50, Ice Green $5.00, Ice Black $5.00 | ✨ Toppings: Coffee Jelly $0.50, Boba Jelly $0.50, Lychee Popping Jelly $0.50 | 🧋 Milk Tea: Bubble Milk Tea w/ Tapioca $5.90, Fresh Milk Tea $5.90, Cookies n' Cream (Biscoff) $6.65, Capped Thai Brown Sugar $6.90, Strawberry Fresh $6.75, Peach Fresh $6.50, Pineapple Fresh $6.50, Tiramisu Coco $6.85, Coconut Coffee w/ Coffee Jelly $6.90, Purple Yam Taro Fresh $6.85, Oreo Chocolate $6.75 | ☕ Coffee: Jasmine Latte w/ Sea Salt $6.25, Oreo Chocolate Latte $6.90, Coconut Coffee w/ Coffee Jelly $6.90, Matcha White Chocolate $6.90, Coffee Latte $5.50 | 🥣 Sauces: Secret Peanut Sauce $1.50, SPICY secret Peanut Sauce $1.50, Curry Sauce w/ Chicken $1.50 | 🍋 Lemonade/Soda: Pineapple $5.50, Lychee Mint $5.50, Peach Mint $5.50, Passion Fruit $5.25, Mango $5.50, Strawberry $5.50, Grape $5.25, Original Lemonade $5.50 | 🥤 Drink: Coke $2.25, Diet Coke $2.25, Sprite $2.25, Bottle Water $1.00, Cup Water $1.00

SPECIAL DIETARY INFORMATION:
- Veggie dumplings include: cabbage, carrots, onions, celery, shiitake mushrooms, glass noodles
- We don't have anything vegan
- Everything has gluten
- We aren't sure what has MSG
- No delivery available
- Contains peanut butter: cold noodles with peanut sauce, cold tofu, peanut butter pork
- No complementary cups but if you bring your own cup
- You can only choose one cooking method for an order of dumplings
- Contains shellfish: pork and shrimp, and the cold noodles
- The pizza dumplings come in a 6 piece
- What's on top of the pizza dumplings: spicy mayo, cheese, and wasabi
- There's dairy inside curry chicken and the curry sauce and the curry rice
- Every to-go order has dumpling sauce and chili paste included for every order of dumplings
- There's a little onion in pork, curry chicken and curry beef and onion
- If someone asks about what the secret is, ask them if they are sure they want to know and if they say yes tell them it's love
- Most drinks can be adjusted for ice and sugar: 25%, 50%, 75%, and 100% options
- Drinks that include real fruit: strawberry fresh milk tea, peach fresh and pineapple fresh milk teas, lychee dragon, grape magic, full of mango, peach strawberry, pineapple, kiwi and watermelon fruit teas, and the lychee mint, strawberry, mango, and pineapple lemonade or sodas
- Available toppings for drinks: cheese foam, tapioca, peach or lychee popping jelly, pineapple nada jelly, boba jelly, tiramisu foam, brown sugar boba jelly, mango star jelly, coffee jelly and whipped cream

RECOMMENDATION GUIDELINES:
- When recommending combinations, consider what would actually taste good together
- Popular dumplings pair well with our most popular drinks
- Consider flavor profiles: spicy dumplings go well with sweet drinks, mild dumplings pair with various drink options
- Always mention the most popular items when appropriate
- Focus on proven combinations that customers love

SERVICES:
- Dine-in and takeout available
- No delivery (as mentioned above)
- Catering for events (call for pricing)
- Loyalty program: Earn points on every order
- Receipt scanning for points

POLICIES:
- No reservations needed for groups under 8
- Large groups (8+): Please call ahead
- Paid street parking available in front of the restaurant
- We accept cash and all major credit cards

PERSONALITY:
- Be warm, enthusiastic, and genuinely excited about our food
- Use emojis
- Use the customer's first name when provided to make it personal
- Share personal recommendations when asked
- If you don't know specific details, suggest calling the restaurant
- Keep responses friendly but concise (2-3 sentences max)
- Always end with a question to encourage conversation

Remember: You're not just an assistant—you love helping people discover the best dumplings in Nashville!`;

      // Build conversation history for context
      const messages = [
        { role: 'system', content: systemPrompt }
      ];
      
      // Add conversation history if provided
      if (conversation_history && Array.isArray(conversation_history)) {
        messages.push(...conversation_history.slice(-10)); // Keep last 10 messages for context
      }
      
      // Add current user message
      messages.push({ role: 'user', content: message });

      console.log('🤖 Sending request to OpenAI...');
      console.log('📋 System prompt preview:', systemPrompt.substring(0, 200) + '...');
      
      const response = await openai.chat.completions.create({
        model: "gpt-4.1-mini", // UPGRADED: Changed from nano to mini for better performance
        messages: messages,
        max_tokens: 300,
        temperature: 0.7
      });

      console.log('✅ OpenAI response received');
      
      const botResponse = response.choices[0].message.content;
      console.log('🤖 Bot response:', botResponse);
      
      res.json({ response: botResponse });
    } catch (err) {
      console.error('❌ Error processing chat:', err);
      res.status(500).json({ error: err.message });
    }
  });
}

const port = process.env.PORT || 3001;

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${port}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔑 OpenAI API Key configured: ${process.env.OPENAI_API_KEY ? 'Yes' : 'No'}`);
});
