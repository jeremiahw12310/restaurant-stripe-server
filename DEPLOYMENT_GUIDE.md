# 🚀 Render Deployment Guide

## Quick Deploy (Recommended)

### Option 1: Manual Dashboard Deployment

1. **Go to Render Dashboard**
   - Visit: https://dashboard.render.com
   - Sign in with your account (jeremiahw12310@gmail.com)

2. **Create New Web Service**
   - Click "New +" → "Web Service"
   - Connect your GitHub repository (if not already connected)
   - Select your repository: `Restaurant Demo`

3. **Configure Service Settings**
   - **Name**: `restaurant-stripe-server`
   - **Environment**: `Node`
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Root Directory**: `backend-deploy`

4. **Set Environment Variables**
   - Click "Environment" tab
   - Add these variables:
     ```
     NODE_ENV=production
     OPENAI_API_KEY=your_openai_api_key_here
     FIREBASE_AUTH_TYPE=adc
     GOOGLE_CLOUD_PROJECT=dumplinghouseapp
     ```

5. **Deploy**
   - Click "Create Web Service"
   - Wait 5-10 minutes for deployment

### Option 2: Using render.yaml (Advanced)

Your `render.yaml` is already configured! You can:

1. **Push to GitHub** (if using Git-based deployment)
2. **Use Render CLI** (interactive mode):
   ```bash
   render services create
   ```
   Then follow the prompts to create from your yaml.

## ✅ What's Already Configured

### Backend Setup
- ✅ Node.js server with Express
- ✅ Firebase Admin SDK integration
- ✅ OpenAI API integration
- ✅ CORS enabled
- ✅ Production-ready configuration

### Firebase Configuration
- ✅ Application Default Credentials (ADC) setup
- ✅ Project ID: `dumplinghouseapp`
- ✅ Service account fallback option

### Environment Variables
- ✅ `NODE_ENV=production`
- ✅ `FIREBASE_AUTH_TYPE=adc`
- ✅ `GOOGLE_CLOUD_PROJECT=dumplinghouseapp`
- ⚠️ `OPENAI_API_KEY` (you need to add this)

## 🔧 Post-Deployment Setup

### 1. Add OpenAI API Key
- Go to your service in Render dashboard
- Environment → Add Variable
- Key: `OPENAI_API_KEY`
- Value: Your OpenAI API key

### 2. Test Your API
Once deployed, test these endpoints:
- `GET https://your-service.onrender.com/` (health check)
- `POST https://your-service.onrender.com/api/chat` (chat endpoint)

### 3. Update iOS App
Update your iOS app's API base URL to point to your Render service.

## 🎯 Expected Results

After deployment, you should have:
- ✅ Live API at `https://restaurant-stripe-server.onrender.com`
- ✅ Firebase integration working
- ✅ OpenAI chat functionality
- ✅ Menu variety system working
- ✅ No more duplicate combo suggestions

## 🚨 Troubleshooting

### Common Issues:
1. **Build fails**: Check Node.js version (should be 18.x)
2. **Firebase errors**: Verify ADC setup and project ID
3. **OpenAI errors**: Check API key is set correctly
4. **CORS errors**: CORS is already configured for all origins

### Logs:
- View logs in Render dashboard
- Use: `render logs --service restaurant-stripe-server`

## 📱 iOS App Integration

Once deployed, update your iOS app's API configuration to use the new Render URL instead of localhost.

---

**Ready to deploy?** Follow Option 1 (Manual Dashboard) for the easiest setup! 