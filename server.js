require('dotenv').config();
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');
const { OpenAI } = require('openai');

// Initialize Stripe only if API key is available
let stripe = null;
if (process.env.STRIPE_SECRET_KEY) {
  stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
}

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
    server: 'ROOT server.js with gpt-4o and Stripe',
    stripeConfigured: !!process.env.STRIPE_SECRET_KEY
  });
});

// MARK: - Stripe Checkout Endpoints

// Create checkout session endpoint
app.post('/create-checkout-session', async (req, res) => {
  try {
    const { line_items } = req.body;
    
    console.log('🛒 Received line items:', line_items);
    
    if (!process.env.STRIPE_SECRET_KEY || !stripe) {
      console.error('❌ STRIPE_SECRET_KEY not configured');
      return res.status(500).json({ error: 'Stripe not configured. Please set STRIPE_SECRET_KEY in environment variables.' });
    }
    
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: line_items,
      mode: 'payment',
      success_url: 'https://restaurant-stripe-server.onrender.com/success?session_id={CHECKOUT_SESSION_ID}',
      cancel_url: 'https://restaurant-stripe-server.onrender.com/cancel',
      metadata: {
        source: 'ios_app'
      }
    });
    
    console.log('✅ Created Stripe session:', session.id);
    
    res.json({ 
      url: session.url,
      sessionId: session.id 
    });
  } catch (error) {
    console.error('❌ Error creating checkout session:', error);
    res.status(500).json({ error: error.message });
  }
});

// Success page that auto-redirects to app
app.get('/success', (req, res) => {
  const sessionId = req.query.session_id;
  console.log('🎉 Payment success for session:', sessionId);
  
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>Payment Successful</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 40px; }
            .success { color: #28a745; font-size: 24px; margin-bottom: 20px; }
            .button { background: #007AFF; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; display: inline-block; margin: 10px; }
            .auto-redirect { color: #666; font-size: 14px; margin-top: 20px; }
        </style>
    </head>
    <body>
        <div class="success">✅ Payment Successful!</div>
        <p>Your order has been placed successfully.</p>
        <a href="restaurantdemo://success" class="button">Return to App</a>
        <div class="auto-redirect">Redirecting to app in 2 seconds...</div>
        <script>
            setTimeout(function() {
                window.location.href = 'restaurantdemo://success';
            }, 2000);
        </script>
    </body>
    </html>
  `);
});

// Cancel page
app.get('/cancel', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>Payment Cancelled</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 40px; }
            .cancel { color: #dc3545; font-size: 24px; margin-bottom: 20px; }
            .button { background: #007AFF; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; display: inline-block; margin: 10px; }
        </style>
    </head>
    <body>
        <div class="cancel">❌ Payment Cancelled</div>
        <p>Your payment was cancelled.</p>
        <a href="restaurantdemo://cancel" class="button">Return to App</a>
    </body>
    </html>
  `);
});

// MARK: - Order Management Endpoints

// Create order endpoint
app.post('/orders', async (req, res) => {
  try {
    console.log('📦 Received order creation request:', req.body);
    
    const { items, customerName, customerPhone, orderType } = req.body;
    
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'Items array is required and must not be empty' });
    }
    
    // Calculate total amount
    const totalAmount = items.reduce((sum, item) => {
      return sum + (item.price * item.quantity);
    }, 0);
    
    // Generate order ID
    const orderId = 'ORD-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9);
    
    // Create order object
    const order = {
      id: orderId,
      items: items,
      customerName: customerName || 'Anonymous',
      customerPhone: customerPhone || '',
      orderType: orderType || 'takeout',
      status: 'preparing',
      createdAt: new Date().toISOString(),
      estimatedReadyTime: new Date(Date.now() + 20 * 60 * 1000).toISOString(), // 20 minutes from now
      estimatedMinutes: 20,
      totalAmount: totalAmount,
      statusHistory: [
        {
          status: 'preparing',
          timestamp: new Date().toISOString(),
          message: 'Order received and being prepared'
        }
      ]
    };
    
    console.log('✅ Created order:', orderId);
    
    res.json({
      success: true,
      order: order
    });
    
  } catch (error) {
    console.error('❌ Error creating order:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get order status endpoint
app.get('/orders/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    console.log('📋 Requesting order status for:', orderId);
    
    // For now, return a mock order status
    // In a real app, you'd fetch this from a database
    const mockOrder = {
      id: orderId,
      status: 'preparing',
      estimatedReadyTime: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      estimatedMinutes: 15,
      statusHistory: [
        {
          status: 'preparing',
          timestamp: new Date().toISOString(),
          message: 'Order is being prepared'
        }
      ]
    };
    
    res.json({
      success: true,
      order: mockOrder
    });
    
  } catch (error) {
    console.error('❌ Error fetching order status:', error);
    res.status(500).json({ error: error.message });
  }
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
  
  // MARK: - Order Management Endpoints
  
  // In-memory storage for orders (in production, use a database)
  let orders = new Map();
  let orderCounter = 1;
  
  // Create a new order - FIXED ENDPOINT PATH
  app.post('/orders', async (req, res) => {
    try {
      console.log('📦 Received order creation request');
      
      const { items, customerName, customerPhone, orderType } = req.body;
      
      if (!items || !Array.isArray(items) || items.length === 0) {
        return res.status(400).json({ error: 'Items array is required and cannot be empty' });
      }
      
      if (!customerName || !customerPhone) {
        return res.status(400).json({ error: 'Customer name and phone are required' });
      }
      
      // Calculate estimated time based on order type
      const hasDumplings = items.some(item => 
        item.name.toLowerCase().includes('dumpling') || 
        item.name.toLowerCase().includes('potsticker')
      );
      
      const hasDrinksOnly = items.every(item => 
        item.name.toLowerCase().includes('tea') || 
        item.name.toLowerCase().includes('coffee') || 
        item.name.toLowerCase().includes('soda') || 
        item.name.toLowerCase().includes('bubble tea') ||
        item.name.toLowerCase().includes('drink')
      );
      
      const hasAppetizersOnly = items.every(item => 
        item.name.toLowerCase().includes('spring roll') || 
        item.name.toLowerCase().includes('edamame') || 
        item.name.toLowerCase().includes('appetizer')
      );
      
      let estimatedMinutes;
      if (hasDrinksOnly || hasAppetizersOnly) {
        estimatedMinutes = Math.floor(Math.random() * 6) + 10; // 10-15 minutes
      } else if (hasDumplings) {
        estimatedMinutes = Math.floor(Math.random() * 6) + 20; // 20-25 minutes
      } else {
        estimatedMinutes = Math.floor(Math.random() * 6) + 15; // 15-20 minutes for mixed orders
      }
      
      const orderId = `DH${String(orderCounter).padStart(4, '0')}`;
      const createdAt = new Date();
      const estimatedReadyTime = new Date(createdAt.getTime() + estimatedMinutes * 60000);
      
      const order = {
        id: orderId,
        items: items,
        customerName: customerName,
        customerPhone: customerPhone,
        orderType: orderType || 'takeout',
        status: 'preparing',
        createdAt: createdAt.toISOString(),
        estimatedReadyTime: estimatedReadyTime.toISOString(),
        estimatedMinutes: estimatedMinutes,
        totalAmount: items.reduce((sum, item) => sum + (item.price * item.quantity), 0),
        statusHistory: [
          {
            status: 'preparing',
            timestamp: createdAt.toISOString(),
            message: 'Order received and being prepared'
          }
        ]
      };
      
      orders.set(orderId, order);
      orderCounter++;
      
      console.log('✅ Order created:', orderId);
      
      res.json({
        success: true,
        order: order
      });
    } catch (err) {
      console.error('❌ Error creating order:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // Get order status
  app.get('/orders/:orderId', async (req, res) => {
    try {
      const { orderId } = req.params;
      
      const order = orders.get(orderId);
      if (!order) {
        return res.status(404).json({ error: 'Order not found' });
      }
      
      res.json({
        success: true,
        order: order
      });
    } catch (err) {
      console.error('❌ Error fetching order:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // Update order status
  app.put('/orders/:orderId/status', async (req, res) => {
    try {
      const { orderId } = req.params;
      const { status, message } = req.body;
      
      const order = orders.get(orderId);
      if (!order) {
        return res.status(404).json({ error: 'Order not found' });
      }
      
      const validStatuses = ['preparing', 'ready', 'completed', 'cancelled'];
      if (!validStatuses.includes(status)) {
        return res.status(400).json({ error: 'Invalid status' });
      }
      
      order.status = status;
      order.statusHistory.push({
        status: status,
        timestamp: new Date().toISOString(),
        message: message || `Order status updated to ${status}`
      });
      
      // Update estimated time if status changes
      if (status === 'ready') {
        order.estimatedReadyTime = new Date().toISOString();
        order.estimatedMinutes = 0;
      }
      
      orders.set(orderId, order);
      
      console.log('✅ Order status updated:', orderId, 'to', status);
      
      res.json({
        success: true,
        order: order
      });
    } catch (err) {
      console.error('❌ Error updating order status:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // Get recent orders for a customer
  app.get('/orders/customer/:phone', async (req, res) => {
    try {
      const { phone } = req.params;
      
      const customerOrders = Array.from(orders.values())
        .filter(order => order.customerPhone === phone)
        .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
        .slice(0, 10); // Get last 10 orders
      
      res.json({
        success: true,
        orders: customerOrders
      });
    } catch (err) {
      console.error('❌ Error fetching customer orders:', err);
      res.status(500).json({ error: err.message });
    }
  });
  
  // Simulate order progress (for testing)
  app.post('/orders/:orderId/simulate-progress', async (req, res) => {
    try {
      const { orderId } = req.params;
      
      const order = orders.get(orderId);
      if (!order) {
        return res.status(404).json({ error: 'Order not found' });
      }
      
      // Simulate order progression
      const statuses = ['preparing', 'ready', 'completed'];
      const currentIndex = statuses.indexOf(order.status);
      
      if (currentIndex < statuses.length - 1) {
        const nextStatus = statuses[currentIndex + 1];
        order.status = nextStatus;
        order.statusHistory.push({
          status: nextStatus,
          timestamp: new Date().toISOString(),
          message: `Order ${nextStatus}`
        });
        
        if (nextStatus === 'ready') {
          order.estimatedReadyTime = new Date().toISOString();
          order.estimatedMinutes = 0;
        }
        
        orders.set(orderId, order);
      }
      
      res.json({
        success: true,
        order: order
      });
    } catch (err) {
      console.error('❌ Error simulating order progress:', err);
      res.status(500).json({ error: err.message });
    }
  });
}

// Orders endpoint - handles order creation
app.post('/orders', async (req, res) => {
  try {
    console.log('📦 Received order creation request');
    console.log('Order data:', JSON.stringify(req.body, null, 2));
    
    const { items, totalAmount, customerInfo, paymentMethod = 'stripe' } = req.body;
    
    // Validate required fields
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ 
        error: 'Items array is required and cannot be empty' 
      });
    }
    
    if (!totalAmount || typeof totalAmount !== 'number') {
      return res.status(400).json({ 
        error: 'Total amount is required and must be a number' 
      });
    }
    
    // Generate a mock order ID
    const orderId = `ORDER_${Date.now()}_${Math.random().toString(36).substr(2, 9).toUpperCase()}`;
    
    // Create order object
    const order = {
      id: orderId,
      items: items,
      totalAmount: totalAmount,
      customerInfo: customerInfo || {},
      paymentMethod: paymentMethod,
      status: 'pending',
      createdAt: new Date().toISOString(),
      estimatedCompletionTime: new Date(Date.now() + 15 * 60 * 1000).toISOString() // 15 minutes from now
    };
    
    console.log('✅ Order created successfully:', orderId);
    
    // In a real app, you would save this to a database
    // For now, we'll just return the order data
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

// Get order status endpoint
app.get('/orders/:orderId', (req, res) => {
  try {
    const { orderId } = req.params;
    console.log(`📋 Fetching order status for: ${orderId}`);
    
    // In a real app, you would fetch this from a database
    // For now, return a mock response
    const mockOrder = {
      id: orderId,
      status: 'in_progress',
      estimatedCompletionTime: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
      updates: [
        {
          timestamp: new Date().toISOString(),
          status: 'confirmed',
          message: 'Order confirmed and being prepared'
        }
      ]
    };
    
    res.json({
      success: true,
      order: mockOrder
    });
    
  } catch (err) {
    console.error('❌ Error fetching order:', err);
    res.status(500).json({ 
      error: 'Failed to fetch order',
      details: err.message 
    });
  }
});

// Stripe checkout session endpoint
app.post('/create-checkout-session', async (req, res) => {
  try {
    if (!stripe) {
      return res.status(500).json({ 
        error: 'Stripe not configured - STRIPE_SECRET_KEY environment variable missing' 
      });
    }

    const { line_items } = req.body;
    console.log('🛒 Creating Stripe checkout session');
    console.log('Line items:', line_items);
    
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: line_items,
      mode: 'payment',
      success_url: 'restaurantdemo://success',
      cancel_url: 'restaurantdemo://cancel',
    });

    console.log('✅ Stripe session created:', session.id);
    res.json({ url: session.url });
    
  } catch (error) {
    console.error('❌ Error creating checkout session:', error);
    res.status(500).json({ error: error.message });
  }
});

const port = process.env.PORT || 3001;

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${port}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔑 OpenAI API Key configured: ${process.env.OPENAI_API_KEY ? 'Yes' : 'No'}`);
  console.log(`💳 Stripe configured: ${process.env.STRIPE_SECRET_KEY ? 'Yes' : 'No'}`);
});
