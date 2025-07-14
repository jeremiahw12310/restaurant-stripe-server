# Backend Deployment Guide 🚀

## Overview
To make the receipt scanning feature work on any iPhone (not just the simulator), you need to deploy the backend server to the cloud.

## Quick Deploy Options

### Option 1: Railway (Recommended - Free)
1. Go to [railway.app](https://railway.app)
2. Sign up with GitHub
3. Click "New Project" → "Deploy from GitHub repo"
4. Select your repository
5. Add environment variable: `OPENAI_API_KEY=your_openai_key`
6. Deploy!

### Option 2: Render (Free)
1. Go to [render.com](https://render.com)
2. Sign up with GitHub
3. Click "New" → "Web Service"
4. Connect your repository
5. Set build command: `npm install`
6. Set start command: `npm start`
7. Add environment variable: `OPENAI_API_KEY=your_openai_key`

### Option 3: Heroku (Paid)
1. Install Heroku CLI
2. Run: `heroku create your-app-name`
3. Run: `heroku config:set OPENAI_API_KEY=your_openai_key`
4. Run: `git push heroku main`

## Environment Variables Needed
- `OPENAI_API_KEY`: Your OpenAI API key for receipt analysis

## After Deployment

### 1. Get Your Server URL
After deployment, you'll get a URL like:
- Railway: `https://your-app.railway.app`
- Render: `https://your-app.onrender.com`
- Heroku: `https://your-app.herokuapp.com`

### 2. Update iOS App
Replace the URL in `ReceiptScanView.swift`:

```swift
// Replace this line:
guard let url = URL(string: "http://10.37.129.2:3001/analyze-receipt") else {

// With your deployed URL:
guard let url = URL(string: "https://your-app.railway.app/analyze-receipt") else {
```

### 3. Test the Deployment
```bash
curl -X GET https://your-app.railway.app
```

## Local Development
For local development, keep using:
```bash
./start-backend.sh
```

And use: `http://localhost:3001/analyze-receipt`

## Troubleshooting

### Server Not Responding
- Check if the deployment completed successfully
- Verify environment variables are set
- Check deployment logs for errors

### CORS Issues
- The server already has CORS enabled
- If issues persist, check the deployment platform's CORS settings

### OpenAI API Errors
- Verify your OpenAI API key is correct
- Check your OpenAI account has sufficient credits
- Ensure you're using a supported model

## Security Notes
- Never commit your OpenAI API key to version control
- Use environment variables for all sensitive data
- Consider adding rate limiting for production use

## Cost Considerations
- Railway: Free tier available
- Render: Free tier available  
- Heroku: Paid only
- OpenAI: Pay per API call (~$0.01-0.03 per receipt)

---
**Next Steps**: Choose a deployment platform and follow the steps above! 