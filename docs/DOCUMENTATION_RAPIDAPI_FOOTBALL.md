# RapidAPI Football Documentation

## RapidAPI Account Management

### Developer Dashboard

Access your RapidAPI developer dashboard to manage all aspects of your API subscription:

- **URL**: https://rapidapi.com/developer/dashboard
- **Access**: Login to RapidAPI → Select 'My Apps' in top-right menu

The dashboard provides:
- Account-wide analytics
- API key management
- Billing settings
- App-specific information

### Analytics

#### App-Level Analytics

View detailed analytics for each app by selecting the 'Analytics' tab in your application dashboard.

Available metrics:
- **API Calls**: Total number of requests made
- **Error Rates**: Percentage of failed requests
- **Latency**: Average request execution time

Features:
- Filter analytics by specific APIs
- Adjustable time range via calendar icon
- Request logs with detailed data

## API Response Headers

Every API response includes these headers:

| Header | Description |
|--------|-------------|
| `server` | Current API proxy version used by RapidAPI |
| `x-ratelimit-requests-limit` | Total requests allowed by your plan before overages |
| `x-ratelimit-requests-remaining` | Remaining requests before hitting plan limit |
| `X-RapidAPI-Proxy-Response` | Set to `true` when response is from RapidAPI proxy (not our servers) |

## Rate Limiting

Monitor your API usage through the `x-ratelimit-*` headers to avoid overage charges. The League Simulator implements smart scheduling to stay within these limits.