#!/bin/bash

echo "🚀 Deploying Restaurant Demo to Render..."
echo "=========================================="

# Check if render.yaml exists
if [ ! -f "render.yaml" ]; then
    echo "❌ render.yaml not found!"
    exit 1
fi

# Check if backend-deploy directory exists
if [ ! -d "backend-deploy" ]; then
    echo "❌ backend-deploy directory not found!"
    exit 1
fi

echo "✅ Configuration files found"

# Check if user is logged into Render
if ! render whoami > /dev/null 2>&1; then
    echo "🔐 Please log in to Render first:"
    echo "   render login"
    exit 1
fi

echo "✅ Authenticated with Render"

# Create a new service using render.yaml
echo "📦 Creating service from render.yaml..."
echo ""
echo "This will create a new web service called 'restaurant-stripe-server'"
echo "with the following configuration:"
echo "- Environment: Node.js"
echo "- Root Directory: backend-deploy"
echo "- Build Command: npm install"
echo "- Start Command: npm start"
echo ""

# Use render CLI to create service from yaml
echo "🔄 Creating service..."
render services create --from-yaml render.yaml

echo ""
echo "🎉 Deployment initiated!"
echo ""
echo "Next steps:"
echo "1. Go to https://dashboard.render.com to monitor the deployment"
echo "2. Set up your environment variables in the Render dashboard:"
echo "   - OPENAI_API_KEY (your OpenAI API key)"
echo "   - FIREBASE_SERVICE_ACCOUNT_KEY (if using service account)"
echo "3. The app will be available at: https://restaurant-stripe-server.onrender.com"
echo ""
echo "Note: The first deployment may take 5-10 minutes to complete." 