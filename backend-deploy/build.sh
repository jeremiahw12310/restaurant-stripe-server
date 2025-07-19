#!/bin/bash

# Build script for Render deployment with Firebase ADC support

echo "🔧 Setting up Firebase Application Default Credentials..."

# Create service account file from environment variable if available
if [ ! -z "$FIREBASE_SERVICE_ACCOUNT_KEY" ]; then
    echo "📝 Creating service account file from environment variable..."
    echo "$FIREBASE_SERVICE_ACCOUNT_KEY" > service-account.json
    echo "✅ Service account file created"
else
    echo "⚠️ No FIREBASE_SERVICE_ACCOUNT_KEY found, will use fallback authentication"
fi

# Install dependencies
echo "📦 Installing dependencies..."
npm install

echo "✅ Build completed successfully" 