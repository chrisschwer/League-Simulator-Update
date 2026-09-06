# CLAUDE.md

This file provides essential context for Claude Code when working with the League Simulator codebase.

## Project Overview

League Simulator is a football league prediction system using Monte Carlo simulations and ELO ratings to predict final standings for German football leagues (Bundesliga, 2. Bundesliga, 3. Liga).

## Quick Commands

```r
# Run all tests
source("tests/testthat.R")

# Run a single test file
testthat::test_file("tests/testthat/test-prozent.R")

# Install R dependencies from packagelist.txt
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])

# Render the static site from the committed fixture and preview it locally
Rscript scripts/preview_site.R
```

```bash
# Build and run the production Docker stack
docker build -t league-simulator:latest .
docker-compose up -d

# Season transition
Rscript scripts/season_transition.R 2025 2026 --non-interactive
```

## Architecture

Four main components:
1. **Simulation Engine** - Rust-based Monte Carlo simulations with ELO ratings (REST seam at `localhost:8080`)
2. **Scheduler** - Automated updates at match times (Berlin timezone)
3. **Season Transition** - Handles promotions/relegations between seasons
4. **Static Site** - four self-contained HTML pages (three league views + Methodik, with inline HTML heatmaps) rendered by the scheduler into `STATIC_SITE_DIR`, served by Caddy at fussball.csdatascience.de (`scripts/preview_site.R` renders a local preview from a saved fixture)

For detailed architecture, see @docs/architecture/overview.md

## Required Environment

```bash
RAPIDAPI_KEY=your_api_key  # Required for API-Football access
```

For all environment variables, see @docs/deployment/quick-start.md

## Modellkonstanten

Zwei Parametergruppen bestimmen jede Prognose. Sie leben **ausschliesslich
im Rust-Server** (`league-simulator-rust/src/models/mod.rs`); R sendet sie
nur, wenn eine Liga bewusst abweicht (ADR 0002).

| Konstante | Wert | Gilt für |
|---|---|---|
| `home_advantage` | 40 | alle Ligen |
| `mod_factor` (k) | 20 | alle Ligen |
| `tore_slope` | 0.0017854953143549 | Herren-Ligen |
| `tore_intercept` | 1.3218390804597700 | Herren-Ligen |
| `tore_slope` | 0.0024058833 | **Frauen-Ligen** (82, 1034) |
| `tore_intercept` | 1.6527603153 | **Frauen-Ligen** (82, 1034) |

**Warum das Tormodell je Liga abweichen darf — aber fast nie sollte:** ELO
ist das Einzige, was ein Team über eine Ligagrenze mitnimmt. Nur wenn Ligen,
die Mannschaften austauschen, dasselbe Tormodell benutzen, bedeutet ein
ELO-Wert dies- und jenseits der Grenze dasselbe. Massgeblich ist deshalb
nicht die einzelne Liga, sondern die **Wechselgemeinschaft**:

- *Herren* (78, 79, 80, 83–87) — tauschen Teams aus, ein gemeinsames Tormodell.
- *Frauen* (82, 1034) — untereinander verbunden, nie mit den Herren,
  daher ein eigenes.

Die Frauen-Werte sind an 1917 Spielen geschätzt und out-of-sample validiert
(Brier −2,96 %); Herleitung in
[`docs/reports/2026-09-05-frauen-tormodell.md`](docs/reports/2026-09-05-frauen-tormodell.md).

**Bekannte Schwächen** (Projekt „Prognosequalität", Sommer 2027):
`E[Tore/Spiel] = 2 × tore_intercept` — der Herren-Wert impliziert 2,64 Tore
gegen gemessene 3,18 in der Bundesliga. Und das unabhängige Poisson-Modell
erzeugt strukturell zu wenig Remis (Überdispersion 1,20); bei den
Frauen-Ligen bleiben 3,7 Prozentpunkte Lücke, in der 2. Bundesliga ist die
beobachtete Quote gar nicht darstellbar. Beides braucht ein korreliertes
Tormodell (Dixon-Coles), keine neuen Parameterwerte. Siehe
[`docs/reports/2026-09-05-liga-empirie-zehn-ligen.md`](docs/reports/2026-09-05-liga-empirie-zehn-ligen.md).

## Conventions

Shared vocabulary lives in `CONTEXT.md`; architecture decisions in `docs/adr/`.

When adding helper functions in `RCode/` that operators run outside the production call graph: provide a `scripts/` wrapper, document it in `docs/user-guide/`, default destructive operations to dry-run with explicit `--confirm`.

## Current Status

- **Season**: 2026-2027 (`SEASON=2026`)
- **API**: api-football via RapidAPI — Pro plan ($19/month): 7,500 requests/day
  (then $0.0025/request), rate limit 300 requests/minute, 10 GB bandwidth/month.
  Typical production usage is ~150–450 requests/day, so per-loop full fetches
  during live windows are well within budget.

