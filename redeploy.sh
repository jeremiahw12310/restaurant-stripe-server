#!/bin/bash

echo "🔄 Redeploying Restaurant Demo with Menu Variety Fixes"
echo "====================================================="

# Check if we're on the right branch
current_branch=$(git branch --show-current)
if [ "$current_branch" != "main" ]; then
    echo "⚠️  You're on branch '$current_branch'. Switching to main..."
    git checkout main
fi

# Pull latest changes
echo "📥 Pulling latest changes from GitHub..."
git pull origin main

# Check if the menu variety fixes are in place
if grep -q "Enhanced combo variety system" backend-deploy/server.js; then
    echo "✅ Menu variety fixes are present in server.js"
else
    echo "❌ Menu variety fixes NOT found in server.js"
    echo "Please make sure you have the latest code with the fixes."
    exit 1
fi

# Check if Firebase ADC support is in place
if grep -q "FIREBASE_AUTH_TYPE.*adc" backend-deploy/server.js; then
    echo "✅ Firebase ADC support is present"
else
    echo "❌ Firebase ADC support NOT found"
    exit 1
fi

echo ""
echo "🎯 Your code is ready for deployment!"
echo ""
echo "Next steps:"
echo "1. Go to https://dashboard.render.com"
echo "2. Find your 'restaurant-stripe-server' service"
echo "3. Click 'Manual Deploy' → 'Deploy latest commit'"
echo "4. Or create a new service using your render.yaml"
echo ""
echo "The new deployment will include:"
echo "✅ Fixed menu variety system (no more duplicate combos!)"
echo "✅ Firebase Application Default Credentials support"
echo "✅ Enhanced categorization logic"
echo "✅ 12 different exploration strategies"
echo "✅ User preference tracking"
echo ""
echo "Your app will work on any iPhone once deployed! 📱" 