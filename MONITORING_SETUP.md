# Monitoring Setup Guide

This guide helps you set up comprehensive monitoring and alerting for your production backend.

## Overview

The backend includes several monitoring endpoints and integrates with external services for error tracking and uptime monitoring.

## Available Monitoring Endpoints

### 1. Basic Health Check
**Endpoint:** `GET /`

Quick health check that returns service status.

```bash
curl https://your-backend-url/
```

**Response:**
```json
{
  "status": "Server is running!",
  "timestamp": "2024-01-27T12:00:00.000Z",
  "environment": "production",
  "services": {
    "firebase": { "configured": true, "connected": true },
    "redis": { "configured": true, "connected": true, "status": "connected" },
    "openai": { "configured": true },
    "sentry": { "configured": true }
  }
}
```

### 2. Detailed Health Check
**Endpoint:** `GET /health/detailed`

Comprehensive health check with response time and memory usage.

```bash
curl https://your-backend-url/health/detailed
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-27T12:00:00.000Z",
  "responseTimeMs": 45,
  "services": {
    "firebase": { "configured": true, "connected": true },
    "redis": { "configured": true, "connected": true },
    "openai": { "configured": true },
    "sentry": { "configured": true }
  },
  "uptime": 3600,
  "memory": {
    "used": 45,
    "total": 128,
    "rss": 180
  }
}
```

**Status Codes:**
- `200` - All services healthy
- `503` - Service degraded (one or more services unavailable)

### 3. Status Endpoint (Uptime Monitoring)
**Endpoint:** `GET /status`

Fast endpoint for uptime monitoring services (UptimeRobot, Pingdom, etc.).

```bash
curl https://your-backend-url/status
```

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-01-27T12:00:00.000Z"
}
```

**Status Codes:**
- `200` - System healthy
- `503` - System degraded

### 4. Metrics Endpoint
**Endpoint:** `GET /metrics`

Basic metrics for monitoring.

```bash
curl https://your-backend-url/metrics
```

**Response:**
```json
{
  "timestamp": "2024-01-27T12:00:00.000Z",
  "uptime": {
    "seconds": 3600,
    "formatted": "1h 0m 0s"
  },
  "requests": {
    "total": 1000,
    "errors": 5,
    "rateLimitHits": 12,
    "perSecond": 0.28
  },
  "services": {
    "redis": { "configured": true, "connected": true },
    "firebase": { "configured": true },
    "openai": { "configured": true },
    "sentry": { "configured": true }
  },
  "memory": {
    "used": 45,
    "total": 128,
    "rss": 180
  }
}
```

## Error Tracking with Sentry

### Setup

1. **Create Sentry Account:**
   - Go to [Sentry.io](https://sentry.io/)
   - Sign up for a free account
   - Create a new project (Node.js)

2. **Get DSN:**
   - After creating project, copy the DSN
   - Format: `https://xxx@xxx.ingest.sentry.io/xxx`

3. **Set Environment Variable:**
   - In your deployment platform (Render, etc.)
   - Add variable:
     - **Key**: `SENTRY_DSN`
     - **Value**: Your Sentry DSN
   - Optional: `SENTRY_RELEASE` - Release version (e.g., `1.0.0`)

4. **Redeploy:**
   - Service will automatically redeploy
   - Check logs: `✅ Sentry initialized for error tracking`

### What Gets Tracked

- Unhandled exceptions
- Unhandled promise rejections
- Errors in request handlers
- Errors in background operations
- Request context (user ID, endpoint, etc.)

### Viewing Errors

1. Go to [Sentry Dashboard](https://sentry.io/)
2. Select your project
3. View errors, performance, and releases
4. Set up alerts for critical errors

### Alert Configuration

In Sentry dashboard:

1. Go to "Alerts" → "Create Alert Rule"
2. Configure:
   - **Trigger**: When error count exceeds threshold
   - **Conditions**: Error rate, specific error types, etc.
   - **Actions**: Email, Slack, PagerDuty, etc.

## Uptime Monitoring

### Option 1: UptimeRobot (Free)

1. **Sign Up:**
   - Go to [UptimeRobot](https://uptimerobot.com/)
   - Create free account (50 monitors)

2. **Add Monitor:**
   - Click "Add New Monitor"
   - **Monitor Type**: HTTP(s)
   - **Friendly Name**: Your Backend API
   - **URL**: `https://your-backend-url/status`
   - **Monitoring Interval**: 5 minutes (free tier)
   - Click "Create Monitor"

3. **Set Up Alerts:**
   - Configure email/SMS alerts
   - Set alert contacts

### Option 2: Pingdom

1. **Sign Up:**
   - Go to [Pingdom](https://www.pingdom.com/)
   - Create account

2. **Add Check:**
   - Go to "Add New Check"
   - **Check Type**: HTTP
   - **URL**: `https://your-backend-url/status`
   - **Check Interval**: 1 minute (or your plan allows)
   - Configure alerts

### Option 3: Render Built-in Monitoring

If using Render:

1. Go to your service dashboard
2. View "Metrics" tab for:
   - CPU usage
   - Memory usage
   - Request rate
   - Error rate

3. Set up alerts:
   - Go to "Alerts" tab
   - Configure thresholds for CPU, memory, errors

## Log Aggregation

### Render Logs

If using Render:

1. View logs in Render dashboard
2. Use "Log Drains" to send logs to external services:
   - Datadog
   - Logtail
   - Papertrail
   - Custom webhook

### Structured Logging

The backend uses Pino for structured logging:

- All logs are JSON formatted
- Request IDs included for tracing
- Error context included automatically

## Recommended Monitoring Setup

### Minimum (Free Tier)

1. ✅ **Sentry** - Error tracking (free tier: 5K events/month)
2. ✅ **UptimeRobot** - Uptime monitoring (free: 50 monitors)
3. ✅ **Render Metrics** - Basic server metrics (if using Render)

### Recommended (Paid)

1. ✅ **Sentry** - Error tracking (Team plan: $26/month)
2. ✅ **Pingdom** - Uptime monitoring ($10/month)
3. ✅ **Datadog** - APM and log aggregation ($31/month)
4. ✅ **New Relic** - Alternative APM ($25/month)

## Alert Configuration

### Critical Alerts

Set up alerts for:

1. **Service Down**
   - Monitor: `/status` endpoint
   - Alert: Immediate (SMS/Email)
   - Threshold: 1 failed check

2. **High Error Rate**
   - Monitor: Sentry error count
   - Alert: When errors exceed 10/minute
   - Threshold: 5 minutes

3. **High Response Time**
   - Monitor: `/health/detailed` responseTimeMs
   - Alert: When > 1000ms
   - Threshold: 3 consecutive checks

4. **Memory Usage**
   - Monitor: Server memory
   - Alert: When > 80% of limit
   - Threshold: 5 minutes

5. **Redis Disconnection**
   - Monitor: Redis health in `/health/detailed`
   - Alert: When disconnected
   - Threshold: Immediate

### Warning Alerts

Set up warnings for:

1. **Increased Error Rate**
   - Alert: When errors exceed 5/minute
   - Threshold: 10 minutes

2. **Degraded Service**
   - Alert: When `/health/detailed` returns 503
   - Threshold: 2 consecutive checks

## Dashboard Setup

### Sentry Dashboard

1. Create custom dashboards for:
   - Error trends
   - Performance metrics
   - Release health

2. Set up widgets for:
   - Error count by type
   - Error rate over time
   - Affected users
   - Performance breakdown

### UptimeRobot Dashboard

1. View uptime percentage
2. Response time graphs
3. Incident history

## Testing Your Monitoring

1. **Test Health Endpoints:**
   ```bash
   curl https://your-backend-url/
   curl https://your-backend-url/health/detailed
   curl https://your-backend-url/status
   curl https://your-backend-url/metrics
   ```

2. **Test Error Tracking:**
   - Trigger a test error (if you have a test endpoint)
   - Verify it appears in Sentry

3. **Test Uptime Monitoring:**
   - Temporarily stop your service
   - Verify alert is triggered
   - Restart service
   - Verify recovery alert

## Best Practices

1. **Monitor Key Endpoints:**
   - `/status` for uptime
   - `/health/detailed` for comprehensive health
   - `/metrics` for performance trends

2. **Set Realistic Thresholds:**
   - Don't alert on every minor issue
   - Use warning alerts for gradual degradation
   - Use critical alerts for immediate issues

3. **Review Regularly:**
   - Check error trends weekly
   - Review performance metrics monthly
   - Adjust thresholds based on actual usage

4. **Document Runbooks:**
   - Document common issues and solutions
   - Create playbooks for alerts
   - Train team on monitoring tools

## Next Steps

1. ✅ Set up Sentry for error tracking
2. ✅ Set up UptimeRobot for uptime monitoring
3. ✅ Configure alerts
4. ✅ Test monitoring setup
5. ✅ Review `RELEASE_READINESS_CHECKLIST.md` for pre-launch verification
