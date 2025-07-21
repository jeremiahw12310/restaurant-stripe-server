#!/bin/bash

# Set Firebase Application Default Credentials environment variables
export FIREBASE_AUTH_TYPE=adc
export GOOGLE_CLOUD_PROJECT=dumplinghouseapp
export NODE_ENV=production

# Set other environment variables
export PORT=3001
export CORS_ORIGIN=*

echo "🚀 Starting server with Firebase ADC configuration..."
echo "📋 Environment variables set:"
echo "   - FIREBASE_AUTH_TYPE: $FIREBASE_AUTH_TYPE"
echo "   - GOOGLE_CLOUD_PROJECT: $GOOGLE_CLOUD_PROJECT"
echo "   - NODE_ENV: $NODE_ENV"
echo "   - PORT: $PORT"

# Start the server
node server.js 