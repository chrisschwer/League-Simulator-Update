# League Simulator

A Monte Carlo simulator that predicts final standings for the three German football leagues — Bundesliga, 2. Bundesliga, 3. Liga. The system combines an ELO rating model with a Rust simulation engine and a fixed daily schedule, surfacing results as a statically generated site.

Live site: <https://fussball.csdatascience.de>

## What it does

- Pulls match results from [api-football](https://rapidapi.com/api-sports/api/api-football) every two minutes between 14:45 and 22:45 Berlin time.
- Runs 10,000 Monte Carlo simulations through the rest of the season for each league after each match-day update.
- Produces a probability matrix per league (each team × each final position) and renders it to four static HTML pages (see `docs/deployment/static-site.md`).
- Re-runs ELO updates after every match.

## How it works

Three pieces:

1. **Rust simulation engine** (`league-simulator-rust/`) — high-performance Monte Carlo runner over a season's remaining fixtures.
2. **R scheduler** (`RCode/`) — wakes during the active window, polls api-football, calls the in-process Rust server when new fixtures arrive, and renders the static site.
3. **Static site generator** (`RCode/generate_static_site.R`) — turns the probability matrices into four self-contained HTML pages with inline HTML heatmaps (Bundesliga, 2. Bundesliga, 3. Liga, Methodik) plus assets, written to a Docker volume that a web server (Caddy) serves. A page older than 24 hours shows a warning banner, computed in the browser.

Engine and scheduler run in a single Docker container; the scheduler talks to the Rust server over `localhost`. There is no application server behind the public site — only static files. Local preview of the same data runs via [`scripts/preview_site.R`](scripts/preview_site.R).

## Deploy

Images are built by CI on every push to `main` and published as `chrisschwer/league-simulator:<sha>`. On the host, pin the tag and pull:

```bash
cp .env.example .env          # set RAPIDAPI_KEY (and SEASON)
docker volume create fussball-site
docker-compose pull && docker-compose up -d
```

The full setup, env-var table, and verification steps are in [`docs/deployment/README.md`](docs/deployment/README.md); serving the generated pages is covered in [`docs/deployment/static-site.md`](docs/deployment/static-site.md). The fast path is in [`docs/deployment/quick-start.md`](docs/deployment/quick-start.md).

## Operate

Common operator tasks:

- **Season transition** (run before each new season starts): [`docs/user-guide/season-transition.md`](docs/user-guide/season-transition.md). Runs on host R; does not require Docker or the Rust server.
- **Roll back to a previous version:** [`docs/deployment/rollback.md`](docs/deployment/rollback.md).
- **Local development without the production container:** [`docs/deployment/local-development.md`](docs/deployment/local-development.md).
- **Common commands:** [`CLAUDE.md`](CLAUDE.md) Quick Commands.
- **Vocabulary and decisions:** [`CONTEXT.md`](CONTEXT.md) and [`docs/adr/`](docs/adr/).

## Project layout

```
.
├── league-simulator-rust/   # Rust simulation engine
├── RCode/                   # R scheduler, ELO, table calculations
├── ShinyApp/                # Result fixture, local Shiny preview, static-site output (gitignored)
├── scripts/                 # Operator scripts (season transition)
├── tests/testthat/          # R test suite
├── tools/                   # One-off tooling (e.g. the shinyapps.io farewell notice)
├── docs/                    # Documentation, ADRs
├── CONTEXT.md               # Shared vocabulary
├── Dockerfile               # Single multi-stage build
└── docker-compose.yml       # Reference compose file (single service + site volume)
```

## Related

The methodology and weekly running commentary on the predictions is published at [30punkte.wordpress.com](https://30punkte.wordpress.com).

Until September 2026 the predictions were hosted on shinyapps.io; that deployment path has been removed ([ADR 0001](docs/adr/0001-statische-seiten-statt-gehostetem-shiny.md)).
