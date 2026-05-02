# Deployment

The League Simulator runs as a single Docker container that combines the Rust simulation engine and the R scheduler. This is the only production deployment path.

## Stack

- **`Dockerfile`** — multi-stage build: Rust 1.81 (alpine) compiles the simulation binary in stage 1; `rocker/r-ver:4.3.1` runs the R scheduler in stage 2.
- **`docker-compose.yml`** — single service `league-simulator-integrated`, exposes port 8081 → container port 8080 (Rust API for monitoring).
- **`docker-start.sh`** — container entrypoint. Starts the Rust server on `localhost:8080`, waits for it to be healthy, then runs `Rscript RCode/updateScheduler.R` with retry logic.
- **`RCode/updateScheduler.R`** — the R scheduler. Wakes at 14:45 Berlin time, polls api-football, calls the in-process Rust server when new fixtures arrive, pushes results to ShinyApps.io.

## Schedule

- **Active hours:** 14:45 – 22:45 Berlin time (`updateScheduler.R` enforces both bounds).
- **Loop frequency:** every 2 minutes inside the active window (Rust engine is fast enough to allow this).
- **Outside the window:** the scheduler sleeps until the next 14:45.

## Required environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `RAPIDAPI_KEY` | yes | — | api-football access via RapidAPI |
| `SHINYAPPS_IO_SECRET` | yes | — | ShinyApps.io deployment auth |
| `SHINYAPPS_IO_NAME` | no | `chrisschwer` | ShinyApps.io account name |
| `SHINYAPPS_IO_TOKEN` | no | (set in compose) | ShinyApps.io token |
| `SEASON` | no | auto-detect | Season year (e.g., `2025`); auto-detects from current month if unset |
| `DURATION` | no | `480` | Cap on scheduler runtime in minutes |
| `RUST_API_URL` | no | `http://localhost:8080` | Rust server endpoint inside the container |
| `TZ` | no | `Europe/Berlin` | Container timezone |

## Build and run

```bash
# Build
docker build -t league-simulator:latest .

# Run via docker-compose (recommended)
docker-compose up -d

# Inspect logs
docker-compose logs -f league-simulator-integrated

# Stop
docker-compose down
```

## Health check

The container exposes `http://localhost:8081/health` (the Rust server's health endpoint). Docker's `HEALTHCHECK` directive in the Dockerfile polls this every 30 seconds.

## Recovery

If you need to compare against the pre-cleanup deployment surface (which had multiple Dockerfiles, a `k8s/` directory, and several scheduler variants), check out the annotated tag:

```bash
git checkout pre-deployment-cleanup-2026-05-02
```

That tag captures the full pre-cleanup tree.

## Operator-side workflows (not covered here)

The season-transition workflow is a separate, locally-invoked operator procedure that runs **before** a container rebuild to produce fresh `RCode/TeamList_<year>.csv` files. It does not run inside the production container.

- **Operator guide:** [`docs/user-guide/season-transition.md`](../user-guide/season-transition.md)
- **Recent changes:** [`docs/SEASON_TRANSITION_UPDATES.md`](../SEASON_TRANSITION_UPDATES.md)
- **Discoverability for validation/report/cleanup helpers:** GitHub issue #74
