# Restaurant Demo Backend

Backend server for the Restaurant Demo iOS app, providing receipt analysis using OpenAI's GPT-4o model.

## Features

- Receipt analysis using OpenAI GPT-4o
- Image upload and processing
- CORS enabled for cross-origin requests
- Health check endpoint

## Deployment

This backend is configured for deployment on Render.com.

### Environment Variables

- `OPENAI_API_KEY`: Your OpenAI API key (required)
- `NODE_ENV`: Environment (production/development)
- `PORT`: Server port (auto-assigned by Render)

### Endpoints

- `GET /`: Health check
- `POST /analyze-receipt`: Analyze receipt image (requires image file)

## Local Development

```bash
npm install
npm start
```

Server will run on port 3001 by default. 