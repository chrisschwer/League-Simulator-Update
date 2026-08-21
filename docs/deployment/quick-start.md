# Quick Start

Deploy the League Simulator in 5 minutes.

> The single-container production stack is described in detail in [Deployment Overview](README.md). This page is the fast path.

## Prerequisites

- Docker and Docker Compose installed
- A RapidAPI key for [api-football](https://rapidapi.com/api-sports/api/api-football)
- A web server (e.g. Caddy) to serve the generated pages — see [Static Site](static-site.md)

## 1. Clone and configure

```bash
git clone https://github.com/chrisschwer/League-Simulator-Update.git
cd League-Simulator-Update

cp .env.example .env
# Then edit .env and fill in the one required value: RAPIDAPI_KEY
# Optional vars are listed (commented out) in the template — see
# deployment/README.md for the full reference.
```

## 2. Build and run

```bash
docker volume create fussball-site
docker-compose pull && docker-compose up -d
```

`docker-compose.yml` defines a single service `scheduler` that runs the Rust simulation server (container-internal, port 8080) and the R scheduler in the same container. The generated site is written to the named volume `fussball-site`; images are built by CI, not locally.

## 3. Verify

```bash
# Container is up
docker-compose ps

# Rust health endpoint (inside the container)
docker-compose exec scheduler curl -f http://localhost:8080/health

# R scheduler logs (tails until you Ctrl-C)
docker-compose logs -f scheduler
```

The R scheduler wakes at 14:45 Berlin time, polls api-football every 2 minutes through 22:45, calls the in-process Rust server when new fixtures arrive, then renders the static site into the `fussball-site` volume.

## Common operations

```bash
# Stop
docker-compose down

# Update to a new CI image
docker-compose pull && docker-compose up -d

# Run the season-transition script (operator workflow — see docs/user-guide/season-transition.md)
docker-compose exec scheduler \
  Rscript scripts/season_transition.R 2025 2026 --non-interactive
```

## Troubleshooting

| Symptom | Where to look |
|---|---|
| Container exits immediately | `docker-compose logs scheduler` — usually a missing `RAPIDAPI_KEY` |
| Health check never turns `healthy` | Rust server didn't start — check container logs |
| Site not updating | Check the `generate_static_site:` lines in the scheduler logs and the volume contents (`docker run --rm -v fussball-site:/v alpine ls -la /v`) |
| Empty `.env` | The only required var is `RAPIDAPI_KEY`; everything else has defaults |

## Next steps

- [Deployment Overview](README.md) — full env-var table and stack details
- [Static Site](static-site.md) — volume, web server, verification
- [Local Development](local-development.md) — run the simulator outside Docker
- [Rollback](rollback.md) — roll back to a previous image or git tag
- [`CLAUDE.md`](../../CLAUDE.md) — common commands cheat-sheet
