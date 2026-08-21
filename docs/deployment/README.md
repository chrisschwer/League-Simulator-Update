# Deployment

The League Simulator runs as a single Docker container that combines the Rust simulation engine and the R scheduler. This is the only production deployment path.

## Stack

- **`Dockerfile`** — multi-stage build: Rust 1.81 (alpine) compiles the simulation binary in stage 1; `rocker/r-ver:4.3.1` runs the R scheduler in stage 2.
- **`docker-compose.yml`** — single service `scheduler` (container `fussball-scheduler`). The Rust API stays container-internal; the generated static site is written to the external named volume `fussball-site`.
- **`docker-start.sh`** — container entrypoint. Starts the Rust server on `localhost:8080`, waits for it to be healthy, then runs `Rscript RCode/updateScheduler.R` with retry logic.
- **`RCode/updateScheduler.R`** — the R scheduler. Wakes at 14:45 Berlin time, polls api-football, calls the in-process Rust server when new fixtures arrive, renders the static site (see [`static-site.md`](static-site.md)).

## Schedule

- **Active hours:** 14:45 – 22:45 Berlin time (`updateScheduler.R` enforces both bounds).
- **Loop frequency:** every 2 minutes inside the active window (Rust engine is fast enough to allow this).
- **Outside the window:** the scheduler sleeps until the next 14:45.

## Required environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `RAPIDAPI_KEY` | yes | — | api-football access via RapidAPI |
| `SEASON` | no | auto-detect | Season year (e.g., `2026`); auto-detects from current month if unset |
| `DURATION` | no | `480` | Cap on scheduler runtime in minutes |
| `RUST_API_URL` | no | `http://localhost:8080` | Rust server endpoint inside the container |
| `TZ` | no | `Europe/Berlin` | Container timezone (load-bearing for the 14:45–22:45 window) |
| `STATIC_SITE_DIR` | no | `ShinyApp/public` | Output directory for the generated static site |

A ready-to-copy template with all variables lives at [`.env.example`](../../.env.example): `cp .env.example .env`, then fill in `RAPIDAPI_KEY`. `.env` itself is gitignored.

ShinyApps.io deployment has been replaced by static site generation — see [`static-site.md`](static-site.md) and [ADR 0001](../adr/0001-statische-seiten-statt-gehostetem-shiny.md).

## Build and run

```bash
# Build
docker build -t league-simulator:latest .

# Run via docker-compose (recommended)
docker-compose up -d

# Inspect logs
docker-compose logs -f scheduler

# Stop
docker-compose down
```

## Health check

Docker's `HEALTHCHECK` polls the Rust server's `http://localhost:8080/health` inside the container every 30 seconds (`docker compose ps` shows `healthy`). The port is not published to the host.

## Public site

The rendered pages are served at <https://fussball.csdatascience.de>.

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
