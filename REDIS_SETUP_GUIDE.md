# Redis Setup Guide

Redis is used for distributed rate limiting across multiple server instances. While the app works without Redis (using in-memory rate limiting), Redis is **highly recommended** for production deployments to ensure rate limits work correctly when scaling horizontally.

## Why Redis?

- **Distributed Rate Limiting**: Rate limits are shared across all server instances
- **Persistence**: Rate limit data survives server restarts
- **Scalability**: Works correctly when running multiple server instances behind a load balancer
- **Performance**: Faster than in-memory for high-traffic scenarios

## Setup Options

### Option 1: Render Redis (Recommended for Render Deployments)

If you're deploying on Render, use Render's managed Redis service:

1. **Create Redis Instance:**
   - Go to [Render Dashboard](https://dashboard.render.com/)
   - Click "New +" → "Redis"
   - Choose a name (e.g., `restaurant-redis`)
   - Select a plan (Free tier available for development)
   - Click "Create Redis"

2. **Get Connection String:**
   - After creation, click on your Redis instance
   - Copy the "Internal Redis URL" (for services on same account) or "External Redis URL"
   - Format: `redis://:password@host:port` or `rediss://:password@host:port` (SSL)

3. **Set Environment Variable:**
   - Go to your backend service (e.g., `restaurant-stripe-server`)
   - Navigate to "Environment" tab
   - Add new variable:
     - **Key**: `REDIS_URL`
     - **Value**: Paste the Redis URL you copied
   - Click "Save Changes"

4. **Redeploy:**
   - Your service will automatically redeploy
   - Check logs to verify: `✅ Redis connected`

### Option 2: Upstash Redis (Cloud Alternative)

Upstash offers a free tier with generous limits:

1. **Sign Up:**
   - Go to [Upstash](https://upstash.com/)
   - Create a free account

2. **Create Database:**
   - Click "Create Database"
   - Choose a name and region
   - Select "Regional" (free tier) or "Global" (paid)
   - Click "Create"

3. **Get Connection String:**
   - After creation, click on your database
   - Copy the "Redis REST URL" or "Redis URL"
   - Format: `redis://default:password@host:port`

4. **Set Environment Variable:**
   - Add `REDIS_URL` to your deployment platform
   - Use the connection string from Upstash

### Option 3: Self-Hosted Redis

For self-hosted Redis (Docker, VPS, etc.):

1. **Install Redis:**
   ```bash
   # Using Docker
   docker run -d -p 6379:6379 redis:latest
   
   # Or install on server
   # Ubuntu/Debian
   sudo apt-get install redis-server
   ```

2. **Get Connection String:**
   - Format: `redis://:password@host:port`
   - For local: `redis://localhost:6379`
   - For remote: `redis://:yourpassword@your-host:6379`

3. **Set Environment Variable:**
   - Add `REDIS_URL` with your connection string

## Testing Redis Connection

After setting up Redis, verify it's working:

1. **Check Health Endpoint:**
   ```bash
   curl https://your-backend-url/
   ```
   
   Look for:
   ```json
   {
     "services": {
       "redis": {
         "configured": true,
         "connected": true,
         "status": "connected"
       }
     }
   }
   ```

2. **Check Detailed Health:**
   ```bash
   curl https://your-backend-url/health/detailed
   ```

3. **Check Server Logs:**
   - Look for: `✅ Redis connected`
   - If you see `⚠️ Redis connection closed`, check your connection string

## Connection String Formats

### Standard Redis
```
redis://:password@host:port
redis://localhost:6379  (no password)
```

### Redis with SSL/TLS
```
rediss://:password@host:port
```

### Redis with Database Number
```
redis://:password@host:port/0
```

## Troubleshooting

### Redis Not Connecting

1. **Check Connection String:**
   - Verify `REDIS_URL` is set correctly
   - Ensure password is included if required
   - Check host and port are correct

2. **Check Network Access:**
   - For Render: Use "Internal Redis URL" if services are on same account
   - For external Redis: Ensure firewall allows connections
   - Check if Redis requires SSL (`rediss://` instead of `redis://`)

3. **Check Redis Status:**
   - Verify Redis instance is running
   - Check Redis logs for errors
   - Test connection with `redis-cli`

### Rate Limiting Not Working

If rate limiting seems inconsistent:

1. **Verify Redis is Connected:**
   - Check health endpoint shows `"connected": true`
   - Check server logs for Redis connection status

2. **Check Rate Limit Configuration:**
   - Verify rate limit environment variables are set
   - Check that Redis is being used (not in-memory fallback)

3. **Test Rate Limits:**
   - Make requests and check if rate limits are enforced
   - Check Redis directly to see if keys are being set

## Fallback Behavior

If Redis is not configured or unavailable:

- ✅ App continues to work normally
- ✅ Rate limiting falls back to in-memory storage
- ⚠️ Rate limits are **per-instance** (not shared across instances)
- ⚠️ Rate limits reset on server restart

**For production with multiple instances, Redis is required.**

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `REDIS_URL` | No (recommended) | Redis connection string |

## Security Notes

- Never commit `REDIS_URL` to version control
- Use environment variables or secrets management
- For production, use Redis with password authentication
- Consider using SSL/TLS (`rediss://`) for external connections
- Restrict Redis access to your backend servers only

## Cost Considerations

- **Render Redis**: Free tier available, paid plans start at ~$10/month
- **Upstash**: Free tier with 10K commands/day, paid plans start at ~$0.20/100K commands
- **Self-Hosted**: Server costs only

## Next Steps

After setting up Redis:

1. ✅ Verify connection in health endpoint
2. ✅ Test rate limiting works correctly
3. ✅ Monitor Redis usage in your provider dashboard
4. ✅ Set up alerts for Redis connection failures (optional)

For monitoring setup, see `MONITORING_SETUP.md`.
