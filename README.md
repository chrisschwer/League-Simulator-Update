# League Simulator

This repository contains R scripts and a Shiny application for simulating football leagues.

## Architecture Overview

The system now supports two deployment modes:

1. **Monolithic Mode** (Original): Single container that handles all leagues and updates Shiny directly
2. **Microservices Mode** (New): Separate containers for each league with shared persistent storage

## Scripts

### Core Simulation Scripts
- `retrieveResults.R`: Downloads results from the football API
- `leagueSimulatorCPP.R`: Main simulation logic using C++ integration
- `simulationsCPP.R`: Monte Carlo simulation engine
- `SpielCPP.R`: Individual match simulation
- `Tabelle.R`: League table calculations
- `transform_data.R`: Data transformation utilities

### Deployment Scripts
- `updateScheduler.R`: Runs regular update loops inside the container (monolithic mode)
- `updateShiny.R`: Deploys the Shiny App via rsconnect
- `update_all_leagues_loop.R`: Loops through all league updates (monolithic mode)

### Microservices Scripts (New)
- `update_league.R`: Updates a single league and saves results to files
- `update_shiny_from_files.R`: Reads league results from files and updates Shiny app
- `league_scheduler.R`: Handles league-specific time windows and API rate limiting
- `shiny_scheduler.R`: Updates Shiny app only during active league windows

## Environment Variables

The containers expect the following variables at runtime:

- `RAPIDAPI_KEY` – API key for api-football
- `SHINYAPPS_IO_SECRET` – Secret for deploying to shinyapps.io
- `DURATION` – Duration in minutes for each update cycle (default: 480)
- `SEASON` – Season to analyse (e.g., `2024`)

### Additional Variables for Microservices Mode
- `LEAGUE` – Specific league to process ("BL", "BL2", or "Liga3")
- `MAX_DAILY_CALLS` – Maximum API calls per day per league (default: 30)
- `UPDATE_INTERVAL` – Interval between Shiny updates in seconds (default: 300)

## Deployment Options

### Option 1: Monolithic Docker Deployment

Build and run a single container that handles all leagues:

```bash
docker build -t league-simulator .

docker run -e RAPIDAPI_KEY=your_api_key \
           -e SHINYAPPS_IO_SECRET=your_shiny_secret \
           -e DURATION=480 \
           -e SEASON=2024 \
           league-simulator
```

### Option 2: Kubernetes Microservices Deployment

Deploy separate containers for each league with shared storage:

1. **Build the Docker images:**
```bash
# Build league updater image
docker build -f Dockerfile.league -t league-simulator:league .

# Build Shiny updater image
docker build -f Dockerfile.shiny -t league-simulator:shiny .
```

2. **Configure secrets:**
```bash
# Edit the k8s deployment file to add your API keys
kubectl edit -f k8s/k8s-deployment.yaml
# Or create the secret manually:
kubectl create secret generic league-simulator-secrets \
  --from-literal=RAPIDAPI_KEY=your_api_key \
  --from-literal=SHINYAPPS_IO_SECRET=your_shiny_secret \
  -n league-simulator
```

3. **Deploy to Kubernetes:**
```bash
kubectl apply -f k8s/k8s-deployment.yaml
```

This will create:
- A namespace `league-simulator`
- A persistent volume for sharing results
- Three league updater pods (one for each league)
- One Shiny updater pod that reads results and updates the app
- ConfigMaps and Secrets for configuration

## Project Structure

```
League-Simulator-Update/
├── RCode/                      # R scripts
│   ├── update_league.R         # Single league updater (new)
│   ├── update_shiny_from_files.R # Shiny updater from files (new)
│   └── ...                     # Other R scripts
├── ShinyApp/                   # Shiny application
│   └── app.R
├── k8s/                        # Kubernetes configurations
│   └── k8s-deployment.yaml
├── Dockerfile                  # Monolithic container
├── Dockerfile.league           # League updater container
├── Dockerfile.shiny           # Shiny updater container
└── README.md

```

## Scheduling and Time Windows

The microservices mode implements smart scheduling based on typical match times:

### League Update Windows:
- **Bundesliga (BL)**:
  - Weekends: 17:20 - 21:45
  - Weekdays: 19:30 - 23:30
- **2. Bundesliga (BL2)**:
  - Weekends: 14:50 - 23:00
  - Weekdays: 19:30 - 23:30
- **3. Liga (Liga3)**:
  - Weekends: 15:20 - 22:00
  - Weekdays: 19:20 - 23:00

### API Rate Limiting:
- Each league is limited to 30 API calls per day
- Calls are automatically distributed across active time windows
- The scheduler optimally spaces requests to maximize coverage

### Shiny App Updates:
- Updates every 5 minutes during any league's active window
- Automatically pauses when no leagues are active
- Resumes immediately when any league window opens

## Benefits of Microservices Architecture

1. **Independent Scaling**: Each league can be updated independently
2. **Fault Isolation**: If one league updater fails, others continue working
3. **Resource Efficiency**: Containers can be scheduled on different nodes
4. **Smart Scheduling**: Updates only run during match times
5. **API Rate Limiting**: Automatic management of daily API quotas
6. **Cost Optimization**: Resources used only when needed

## Monitoring

To monitor the Kubernetes deployment:

```bash
# Check pod status
kubectl get pods -n league-simulator

# View logs for a specific league
kubectl logs -n league-simulator -l league=bl

# View Shiny updater logs
kubectl logs -n league-simulator -l app=shiny-updater
```