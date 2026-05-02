# Quick Start

Deploy the League Simulator in 5 minutes.

> The single-container production stack is described in detail in [Deployment Overview](README.md). This page is the fast path.

## Prerequisites

- Docker and Docker Compose installed
- A RapidAPI key for [api-football](https://rapidapi.com/api-sports/api/api-football)
- (Optional) ShinyApps.io credentials if you want the dashboard live on the public web

## 1. Clone and configure

```bash
git clone https://github.com/chrisschwer/League-Simulator-Update.git
cd League-Simulator-Update

cat > .env <<'EOF'
RAPIDAPI_KEY=your_rapidapi_key_here
SHINYAPPS_IO_SECRET=your_shiny_secret_here
# Optional — see deployment/README.md for the full list:
# SHINYAPPS_IO_NAME=chrisschwer
# SHINYAPPS_IO_TOKEN=your_shiny_token
# SEASON=2025
# DURATION=480
EOF
```

## 2. Build and run

```bash
docker-compose up -d --build
```

`docker-compose.yml` defines a single service `league-simulator-integrated` that runs the Rust simulation server on container port 8080 (mapped to host 8081) and the R scheduler in the same container.

## 3. Verify

```bash
# Container is up
docker-compose ps

# Rust health endpoint
curl http://localhost:8081/health

# R scheduler logs (tails until you Ctrl-C)
docker-compose logs -f league-simulator-integrated
```

The R scheduler wakes at 14:45 Berlin time, polls api-football every 2 minutes through 22:45, calls the in-process Rust server when new fixtures arrive, then pushes results to ShinyApps.io.

## Common operations

```bash
# Stop
docker-compose down

# Rebuild after a code change
docker-compose up -d --build

# Run the season-transition script (operator workflow — see docs/user-guide/season-transition.md)
docker-compose exec league-simulator-integrated \
  Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

## Troubleshooting

| Symptom | Where to look |
|---|---|
| Container exits immediately | `docker-compose logs league-simulator-integrated` — usually a missing required env var |
| `curl localhost:8081/health` hangs | Rust server didn't start — check container logs for cargo/build errors |
| No simulation results landing in ShinyApps.io | Check `SHINYAPPS_IO_SECRET` and the deploy step in the scheduler logs |
| Empty `.env` | Required vars are `RAPIDAPI_KEY` and `SHINYAPPS_IO_SECRET`; everything else has defaults |

## Next steps

- [Deployment Overview](README.md) — full env-var table and stack details
- [Local Development](local-development.md) — run the simulator outside Docker
- [Rollback](rollback.md) — roll back to a previous image or git tag
- [`CLAUDE.md`](../../CLAUDE.md) — common commands cheat-sheet
