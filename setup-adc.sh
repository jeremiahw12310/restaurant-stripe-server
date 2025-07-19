#!/bin/bash

echo "🚀 Setting up Application Default Credentials for Firebase"
echo "=================================================="

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "❌ Google Cloud CLI is not installed."
    echo "Please install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "🔐 Please authenticate with Google Cloud:"
    gcloud auth login
fi

# Set the project
echo "📁 Setting project to: dumplinghouseapp"
gcloud config set project dumplinghouseapp

# Create application default credentials
echo "🔑 Creating Application Default Credentials..."
gcloud auth application-default login

# Verify the setup
echo "✅ Verification:"
echo "Project: $(gcloud config get-value project)"
echo "Account: $(gcloud config get-value account)"

echo ""
echo "🎉 Setup complete! Your server can now use Application Default Credentials."
echo ""
echo "📝 Next steps:"
echo "1. Deploy to Render with these environment variables:"
echo "   - FIREBASE_AUTH_TYPE=adc"
echo "   - GOOGLE_CLOUD_PROJECT=dumplinghouseapp"
echo ""
echo "2. Make sure your service account has these roles:"
echo "   - Firebase Admin"
echo "   - Firestore Admin"
echo "   - Storage Admin (if using Firebase Storage)"
echo ""
echo "3. Test your deployment with:"
echo "   curl https://your-render-app.onrender.com/" 