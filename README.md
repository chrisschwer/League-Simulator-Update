# League Simulator

A Monte Carlo simulator that predicts final standings for the three German football leagues — Bundesliga, 2. Bundesliga, 3. Liga. The system combines an ELO rating model with a Rust simulation engine and a fixed daily schedule, surfacing results through a Shiny dashboard.

Live dashboard: <https://chrisschwer.shinyapps.io/FussballPrognosen/>

## What it does

- Pulls match results from [api-football](https://rapidapi.com/api-sports/api/api-football) every two minutes between 14:45 and 22:45 Berlin time.
- Runs 10,000 Monte Carlo simulations through the rest of the season for each league after each match-day update.
- Produces a probability matrix per league (each team × each final position) and pushes it to ShinyApps.io.
- Re-runs ELO updates after every match.

## How it works

Three pieces:

1. **Rust simulation engine** (`league-simulator-rust/`) — high-performance Monte Carlo runner over a season's remaining fixtures.
2. **R scheduler** (`RCode/`) — wakes during the active window, polls api-football, calls the in-process Rust server when new fixtures arrive, and pushes results to ShinyApps.io.
3. **Shiny app** (`ShinyApp/`) — renders the probability matrices as heatmaps.

All three run in a single Docker container on a Linux server; the scheduler talks to the Rust server over `localhost`.

## Deploy

```bash
docker-compose up -d --build
```

The full setup, env-var table, and verification steps are in [`docs/deployment/README.md`](docs/deployment/README.md). The fast path is in [`docs/deployment/quick-start.md`](docs/deployment/quick-start.md).

## Operate

Common operator tasks:

- **Season transition** (run before each new season starts): [`docs/user-guide/season-transition.md`](docs/user-guide/season-transition.md). Runs on host R with the C++ engine; does not require Docker or the Rust server.
- **Roll back to a previous version:** [`docs/deployment/rollback.md`](docs/deployment/rollback.md).
- **Local development without the production container:** [`docs/deployment/local-development.md`](docs/deployment/local-development.md).
- **Common commands:** [`CLAUDE.md`](CLAUDE.md) Quick Commands.

## Project layout

```
.
├── league-simulator-rust/   # Rust simulation engine
├── RCode/                   # R scheduler, ELO, table calculations
├── ShinyApp/                # Shiny dashboard
├── scripts/                 # Operator scripts (season transition)
├── tests/testthat/          # R test suite
├── docs/                    # Documentation
├── Dockerfile               # Single multi-stage build
└── docker-compose.yml       # Single-service deployment
```

## Related

The methodology and weekly running commentary on the predictions is published at [30punkte.wordpress.com](https://30punkte.wordpress.com).
