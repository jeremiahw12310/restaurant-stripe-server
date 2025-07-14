#!/bin/bash

echo "🚀 Restaurant Demo Production Deployment"
echo "========================================"

# Check if git is clean
if [ -n "$(git status --porcelain)" ]; then
    echo "❌ Git working directory is not clean. Please commit your changes first."
    exit 1
fi

echo "✅ Git working directory is clean"

# Check if we're on main branch
current_branch=$(git branch --show-current)
if [ "$current_branch" != "main" ]; then
    echo "⚠️  You're on branch '$current_branch'. Consider switching to main for production deployment."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "📤 Pushing to GitHub..."
git push origin $current_branch

echo "✅ Code pushed to GitHub"
echo ""
echo "🌐 Render will automatically deploy your changes"
echo "📱 Your iOS app is now configured for production"
echo ""
echo "🔧 Next steps:"
echo "1. Go to https://dashboard.render.com/"
echo "2. Find your 'restaurant-stripe-server' service"
echo "3. Add environment variables:"
echo "   - STRIPE_SECRET_KEY=sk_live_your_key_here"
echo "   - OPENAI_API_KEY=your_openai_key_here"
echo "   - NODE_ENV=production"
echo ""
echo "📱 To test on any iPhone:"
echo "1. Archive your app in Xcode"
echo "2. Distribute via TestFlight or Ad Hoc"
echo "3. Install on any iPhone anywhere!"
echo ""
echo "🎉 Your app will work globally once deployed!" 