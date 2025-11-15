#!/bin/bash

echo "🔧 Deploying Referral URL Fix"
echo "=============================="
echo ""

# Check if we're in a git repository
if [ ! -d .git ]; then
    echo "❌ Not in a git repository. Please run from project root."
    exit 1
fi

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo "📝 You have uncommitted changes:"
    git status --short
    echo ""
    read -p "Do you want to commit these changes? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add .
        git commit -m "Fix referral URL sandbox extension error and cache migration"
        echo "✅ Changes committed"
    else
        echo "⚠️  Skipping commit. Deploy will use last committed state."
    fi
else
    echo "✅ No uncommitted changes"
fi

echo ""
echo "📤 Pushing to GitHub..."
git push origin main

if [ $? -eq 0 ]; then
    echo "✅ Pushed to GitHub successfully"
    echo ""
    echo "🚀 Next Steps:"
    echo "1. Go to: https://dashboard.render.com/"
    echo "2. Find your 'restaurant-stripe-server-1' service"
    echo "3. Click 'Manual Deploy' → 'Deploy latest commit'"
    echo ""
    echo "📱 After deployment:"
    echo "- Rebuild the iOS app in Xcode"
    echo "- Old cache will be cleared automatically"
    echo "- New referral URLs will use: restaurantdemo://referral?code=..."
    echo ""
    echo "✨ The sandbox extension error will be fixed!"
else
    echo "❌ Failed to push to GitHub"
    exit 1
fi


