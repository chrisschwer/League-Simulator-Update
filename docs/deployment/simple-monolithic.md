# Simple Monolithic Deployment

A streamlined deployment approach for the League Simulator that runs as a single container with minimal complexity.

## Overview

This deployment runs the League Simulator as a single Docker container that:
- Executes simulations daily at 14:45 Berlin time
- Runs 32 loops over 480 minutes during normal operation
- Implements crash recovery with only 3 loops to prevent API limit violations
- Waits until next day if started after 22:45

## Quick Start

### 1. Build the Container

```bash
docker build -f Dockerfile.simple -t chrisschwer/league-simulator:simple .
```

### 2. Run with Docker

```bash
docker run -d \
  --name league-simulator \
  -e RAPIDAPI_KEY=your_api_key \
  -e SHINYAPPS_IO_SECRET=your_shiny_secret \
  chrisschwer/league-simulator:simple
```

### 3. Run with Docker Compose

Create `docker-compose.simple.yml`:

```yaml
version: '3'
services:
  league-simulator:
    image: chrisschwer/league-simulator:simple
    container_name: league-simulator
    environment:
      - RAPIDAPI_KEY=${RAPIDAPI_KEY}
      - SHINYAPPS_IO_SECRET=${SHINYAPPS_IO_SECRET}
      - SEASON=${SEASON}  # Optional, auto-detects if not set
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

Run:
```bash
docker-compose -f docker-compose.simple.yml up -d
```

## Configuration

### Environment Variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `RAPIDAPI_KEY` | Yes | Your RapidAPI key for api-football | - |
| `SHINYAPPS_IO_SECRET` | Yes | Secret for ShinyApps.io deployment | - |
| `SEASON` | No | Season year (e.g., "2025") | Auto-detected based on current month |

### Season Auto-Detection

If `SEASON` is not set, the system automatically determines the season:
- **July-December**: Uses current year (e.g., in Nov 2024 → "2024")
- **January-June**: Uses previous year (e.g., in Mar 2025 → "2024")

## Scheduling Logic

The scheduler implements dynamic timing logic based on API limits:

```
Current Time          Action
------------          ------
Before 14:45      →   Wait until 14:45, then run up to 96 loops (every 5 min)
14:45 - 22:45     →   Calculate loops based on time remaining and API limits
After 22:45       →   Wait until tomorrow's 14:45
```

### Dynamic Loop Calculation

The system now:
1. Calculates ideal loops: `minutes_until_22:45 / 5`
2. Checks your API rate limit via headers
3. Runs `min(ideal_loops, remaining_api_calls / 3)`

Benefits:
- **Free plan (100 calls/day)**: Automatically limits to ~33 loops
- **Paid plan (7,500 calls/day)**: Can run full 96 loops (every 5 minutes)
- **Smart recovery**: After crash, uses actual API quota instead of fixed 3 loops
- **No overages**: Always respects your plan's limits

## Container Architecture

The container includes only essential files:

```
/
├── RCode/
│   ├── updateSchedulerSimple.R      # Main scheduler with dynamic timing
│   ├── checkAPILimits.R            # API rate limit checker
│   ├── update_all_leagues_loop.R   # Core simulation loop
│   ├── SpielNichtSimulieren.cpp    # C++ performance code
│   ├── [simulation modules]         # Core R modules
│   └── TeamList_*.csv              # Team data files
└── ShinyApp/                       # Web app for deployment
```

## Monitoring

### View Logs

```bash
# Docker
docker logs -f league-simulator

# Docker Compose
docker-compose -f docker-compose.simple.yml logs -f
```

### Check Status

```bash
# Is it running?
docker ps | grep league-simulator

# Resource usage
docker stats league-simulator
```

### Log Messages

Normal operation logs:
```
League Simulator Simple Scheduler Starting
Season: 2025
Before 14:45 - waiting for scheduled run time
Current time: 2025-01-15 08:30:00
Next run at: 2025-01-15 14:45:00
Waiting 22500 seconds (6.2 hours)
API Rate Limit: 7423/7500 requests remaining
Planning to run 96 loops (ideal: 96)
Starting simulation with 96 loops at 2025-01-15 14:45:00
Simulation completed successfully
Waiting for next scheduled run
```

## Troubleshooting

### Container Exits Immediately

Check environment variables:
```bash
docker logs league-simulator
```

Common issues:
- Missing `RAPIDAPI_KEY`
- Invalid API key
- Missing team data files

### API Rate Limit Errors

The dynamic loop calculation prevents this by checking actual limits. If you see rate limit warnings:
1. Check logs for "API Rate Limit: X/Y requests remaining"
2. System automatically reduces loops to stay within limits
3. No manual intervention needed - it self-adjusts

### No Simulation Results

Check if ShinyApps.io deployment is working:
```bash
docker logs league-simulator | grep -i shiny
```

## Maintenance

### Update Team Data

1. Add new CSV file: `RCode/TeamList_2026.csv`
2. Rebuild container
3. Deploy with `SEASON=2026` or let auto-detection handle it

### View Simulation Results

Results are automatically uploaded to ShinyApps.io. Check your app at:
```
https://chrisschwer.shinyapps.io/FussballPrognosen/
```

## Advantages

- **Simple**: One container, one process, one log file
- **Reliable**: Automatic crash recovery with API protection
- **Efficient**: Runs only when needed, minimal resource usage
- **Maintainable**: Clear scheduling logic, easy to debug

## Migration from Complex Setup

If migrating from the previous multi-container setup:

1. Stop old containers: `docker-compose down`
2. Build new image: `docker build -f Dockerfile.simple -t chrisschwer/league-simulator:simple .`
3. Start simple version: `docker-compose -f docker-compose.simple.yml up -d`
4. Verify logs: `docker-compose -f docker-compose.simple.yml logs -f`

The simple deployment maintains all functionality while dramatically reducing complexity.