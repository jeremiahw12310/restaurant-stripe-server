#!/bin/bash

# Start the server with Firebase Application Default Credentials
echo "🚀 Starting Restaurant Demo Server with Firebase ADC..."
echo "📋 Environment:"
echo "   - FIREBASE_AUTH_TYPE: adc"
echo "   - GOOGLE_CLOUD_PROJECT: dumplinghouseapp"
echo "   - Firebase configured: Yes"
echo ""

# Set environment variables and start server
FIREBASE_AUTH_TYPE=adc GOOGLE_CLOUD_PROJECT=dumplinghouseapp node server.js 