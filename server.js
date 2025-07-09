require('dotenv').config();
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');
const { OpenAI } = require('openai');

// Add Stripe for real payment processing
const stripe = process.env.STRIPE_SECRET_KEY ? require('stripe')(process.env.STRIPE_SECRET_KEY) : null;

// Updated for Render deployment with latest OpenAI model
// ROOT SERVER.JS - USING GPT-4O MODEL
const app = express();
const upload = multer({ dest: 'uploads/' });
app.use(cors());
app.use(express.json());

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// Health check endpoint
app.get('/', (req, res) => {
  res.json({ 
    status: 'Server is running!', 
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    server: 'ROOT server.js with gpt-4o'
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
} else {
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

      const prompt = `
You are a receipt parser. Extract the following fields from the receipt image:
- orderNumber: The order or transaction number (if present)
- orderTotal: The total amount paid (as a number, e.g. 23.45)
- orderDate: The date of the order (in MM/DD/YYYY or YYYY-MM-DD format)

Respond ONLY as a JSON object: {"orderNumber": "...", "orderTotal": ..., "orderDate": "..."}
If a field is missing, use null.
`;

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
      
      const { message, conversation_history } = req.body;
      
      if (!message) {
        return res.status(400).json({ error: 'Message is required' });
      }
      
      console.log('📝 User message:', message);
      
      // Create the system prompt with restaurant information
      const systemPrompt = `You are Dumpling Hero, the friendly and knowledgeable assistant for Dumpling House in Nashville, TN. 

CRITICAL: You must ALWAYS refer to yourself as "Dumpling Hero" and NEVER use any other name (such as Wanyi, AI, assistant, or any other name). This is a strict requirement. If you see yourself using any other name in your response, immediately correct it to "Dumpling Hero".

You're passionate about dumplings and love helping customers discover our authentic Chinese cuisine.

RESTAURANT INFORMATION:
- Name: Dumpling House
- Address: 2117 Belcourt Ave, Nashville, TN 37212
- Phone: +1 (615) 891-4728
- Hours: Monday - Thursday 11:30 AM - 9:00 PM
- Cuisine: Authentic Chinese dumplings and Asian cuisine

MENU & PRICING:
- Dumplings (Steamed/Boiled/Pan-fried): $8-12 per order (6-8 pieces)
- Popular flavors: Pork & Chive ($9), Beef & Onion ($10), Vegetable ($8), Shrimp & Pork ($12)
- Half & Half options: Mix any two flavors for $11
- Appetizers: Spring rolls ($6), Potstickers ($7), Edamame ($4)
- Drinks: Bubble tea ($5), Sodas ($3), Hot tea ($2), Coffee ($3)
- Desserts: Mochi ($4), Ice cream ($5)

SERVICES:
- Dine-in and takeout available
- Delivery through Phone, App, or Website
- Catering for events (call for pricing)
- Loyalty program: Earn points on every order
- Receipt scanning for points

POLICIES:
- No reservations needed for groups under 8
- Large groups (8+): Please call ahead
- Paid street parking available in front of the restaurant
- We accept cash and all major credit cards
- 15% gratuity added for groups of 6+

PERSONALITY:
- You must always refer to yourself as "Dumpling Hero" and never use any other name (such as Wanyi)
- Be warm, enthusiastic, and genuinely excited about our food
- Use emojis
- Use your name "Dumpling Hero" when introducing yourself
- Share personal recommendations when asked
- If you don't know specific details, suggest calling the restaurant
- Keep responses friendly but concise (2-3 sentences max)
- Always end with a question to encourage conversation

Remember: You're not just an assistant - you're Dumpling Hero, and you love helping people discover the best dumplings in Nashville!`;

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
      
      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini", // Using the cheapest model
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

// Orders endpoint to create orders
app.post('/orders', async (req, res) => {
  try {
    console.log('📦 Received order creation request');
    console.log('📋 Request body:', JSON.stringify(req.body, null, 2));
    
    const { items, total, tip, customerInfo, paymentMethod } = req.body;
    
    if (!items || !total) {
      return res.status(400).json({ 
        error: 'Missing required fields: items and total are required' 
      });
    }
    
    // Generate a random order number
    const orderNumber = Math.floor(Math.random() * 9000) + 1000;
    
    // Create order object
    const order = {
      id: orderNumber.toString(),
      orderNumber: orderNumber.toString(),
      items: items,
      subtotal: total - (tip || 0),
      tip: tip || 0,
      total: total,
      status: 'confirmed',
      statusHistory: [
        {
          status: 'confirmed',
          timestamp: new Date().toISOString(),
          description: 'Order confirmed and being prepared'
        }
      ],
      customerInfo: customerInfo || {},
      paymentMethod: paymentMethod || 'stripe',
      orderDate: new Date().toISOString(),
      estimatedReadyTime: new Date(Date.now() + 15 * 60 * 1000).toISOString() // 15 minutes from now
    };
    
    console.log('✅ Order created successfully:', orderNumber);
    console.log('📄 Order details:', JSON.stringify(order, null, 2));
    
    res.status(201).json({
      success: true,
      order: order,
      message: 'Order created successfully'
    });
    
  } catch (err) {
    console.error('❌ Error creating order:', err);
    res.status(500).json({ 
      error: 'Failed to create order',
      details: err.message 
    });
  }
});

// Stripe checkout session endpoint
app.post('/create-checkout-session', async (req, res) => {
  try {
    console.log('💳 Received Stripe checkout session request');
    console.log('📋 Line items:', JSON.stringify(req.body.line_items, null, 2));
    
    const { line_items } = req.body;
    
    if (!line_items || !Array.isArray(line_items)) {
      return res.status(400).json({ 
        error: 'line_items is required and must be an array' 
      });
    }
    
    // Check if Stripe is configured
    if (!stripe) {
      console.log('⚠️ Stripe not configured - using mock checkout');
      
      // For development, return a mock URL that includes success/cancel callbacks
      const devSessionUrl = `data:text/html,<html><body style="font-family: Arial, sans-serif; text-align: center; padding: 50px;"><h2>🧪 Mock Stripe Checkout</h2><p>This is a development mock for testing without Stripe keys</p><br><button onclick="window.location.href='restaurantdemo://success'" style="background: #28a745; color: white; padding: 15px 30px; border: none; border-radius: 5px; font-size: 16px; margin: 10px; cursor: pointer;">✅ Complete Payment</button><br><br><button onclick="window.location.href='restaurantdemo://cancel'" style="background: #dc3545; color: white; padding: 15px 30px; border: none; border-radius: 5px; font-size: 16px; margin: 10px; cursor: pointer;">❌ Cancel Payment</button><br><br><small>To use real Stripe, set STRIPE_SECRET_KEY environment variable</small></body></html>`;
      
      return res.json({ 
        url: devSessionUrl,
        sessionId: `cs_test_mock_${Date.now()}`
      });
    }
    
    // Real Stripe checkout session
    console.log('🔑 Creating real Stripe checkout session');
    
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: line_items,
      mode: 'payment',
      success_url: 'restaurantdemo://success',
      cancel_url: 'restaurantdemo://cancel',
      automatic_tax: { enabled: false }, // Disable for simplicity
    });
    
    console.log('✅ Real Stripe checkout session created:', session.id);
    
    res.json({ 
      url: session.url,
      sessionId: session.id
    });
    
  } catch (err) {
    console.error('❌ Error creating checkout session:', err);
    res.status(500).json({ 
      error: 'Failed to create checkout session',
      details: err.message 
    });
  }
});

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${port}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔑 OpenAI API Key configured: ${process.env.OPENAI_API_KEY ? 'Yes' : 'No'}`);
  console.log(`💳 Stripe configured: ${process.env.STRIPE_SECRET_KEY ? 'Yes (Real payments)' : 'No (Mock checkout)'}`);
  if (stripe) {
    console.log('✅ Ready for real Stripe payments in sandbox mode');
  } else {
    console.log('⚠️ Using mock checkout - set STRIPE_SECRET_KEY for real payments');
  }
});
