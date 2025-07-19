# League Simulator Quick Start Guide

Deploy the League Simulator in 5 minutes for experienced users.

## Prerequisites

- Docker and Docker Compose installed
- RapidAPI key for api-football
- (Optional) ShinyApps.io credentials for web deployment

## Quick Deploy

### 1. Clone and Configure

```bash
git clone https://github.com/chrisschwer/League-Simulator-Update.git
cd League-Simulator-Update

# Create .env file
cat > .env << EOF
RAPIDAPI_KEY=your_rapidapi_key_here
SHINYAPPS_IO_NAME=your_username
SHINYAPPS_IO_TOKEN=your_token
SHINYAPPS_IO_SECRET=your_secret
SEASON=2025
DURATION=480
EOF
```

### 2. Build and Run

```bash
# Build all images
docker-compose build

# Start all services
docker-compose up -d

# Check status
docker-compose ps
```

### 3. Verify Deployment

```bash
# Check logs
docker-compose logs -f league-simulator

# Test API connection
docker-compose exec league-simulator Rscript test_api_connection.R

# Access Shiny app (if deployed)
open https://your-username.shinyapps.io/league-simulator
```

## Service Endpoints

- **League Simulator**: Running on schedule (see logs)
- **Shiny App**: `http://localhost:3838` (local) or ShinyApps.io URL
- **Logs**: `./logs/` directory

## Quick Commands

```bash
# Stop all services
docker-compose down

# Restart specific service
docker-compose restart league-simulator

# Update team data
docker-compose exec league-simulator Rscript scripts/season_transition.R 2024 2025

# View recent simulations
docker-compose exec league-simulator ls -la ShinyApp/data/
```

## Troubleshooting Quick Fixes

| Issue | Solution |
|-------|----------|
| API key invalid | Check `.env` file and verify key on RapidAPI |
| Container exits | Check logs: `docker-compose logs league-simulator` |
| No simulation results | Verify schedule in `updateScheduler.R` |
| Shiny app not updating | Check deployment credentials in `.env` |

## Next Steps

- [Detailed Deployment Guide](detailed-guide.md) for configuration options
- [Production Deployment](production.md) for security hardening
- [Troubleshooting Guide](../troubleshooting/common-issues.md) for detailed solutions