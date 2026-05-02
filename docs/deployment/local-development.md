# Local Development

Run, edit, and iterate on parts of the League Simulator outside the production container.

> **Production is a single Docker container that runs continuously on a Linux server.** Local development is *not* about running the production scheduler on your machine. It's about iterating on individual pieces — the R modules, the Rust simulation engine, the Shiny app, the season-transition operator workflow — without rebuilding and redeploying the container.
>
> See [Quick Start](quick-start.md) for the actual deployment path. See [Deployment Overview](README.md) for what runs in production.

## Prerequisites

- **R 4.3.x** (the production container uses 4.3.1 via `rocker/r-ver:4.3.1`)
- **Rust 1.81+** (only if you'll iterate on the simulation engine)
- A **RapidAPI key** in `RAPIDAPI_KEY` if you'll exercise api-football

## 1. Install R dependencies

```r
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])
```

This installs every package the production container installs at build time. Idempotent; running it again is cheap.

## 2. Run the test suite

```r
testthat::test_dir("tests/testthat")
```

Some tests target deleted infrastructure and are being cleaned up in a separate effort. Look for failures in the files that protect the production loop or the season-transition workflow — those are the signal-bearing ones.

## 3. Iterate on the Rust simulation engine

```bash
cd league-simulator-rust

# Run unit tests
cargo test

# Build a release binary (matches the production image's stage 1)
cargo build --release
# Binary at: target/release/league-simulator-server

# Run the server locally for manual integration testing
cargo run --release
# Listens on localhost:8080 by default
```

To exercise the R-side integration against this locally-running server:

```bash
RUST_API_URL=http://localhost:8080 Rscript -e '
  source("RCode/rust_integration.R")
  source("RCode/update_all_leagues_loop.R")
  # ...one league pass against your local Rust server...
'
```

## 4. Run the Shiny app locally

```r
shiny::runApp("ShinyApp/app.R", port = 3838)
# http://localhost:3838
```

Reads `ShinyApp/data/Ergebnis.Rds` — same file the production scheduler writes when it pushes to ShinyApps.io.

## 5. Season transition (operator workflow)

The season-transition script runs **on your local machine, on host R**. It does not require Docker, the production container, or the Rust simulation server. It uses the C++ simulation engine via Rcpp, which is sufficient because season transition isn't time-critical and the speed gain from Rust isn't needed here.

```bash
# From the repo root, with a valid RAPIDAPI_KEY in the environment:
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

The script writes `RCode/TeamList_<year>.csv`, which is then committed to the repo and picked up by the next container rebuild.

The Rcpp build happens automatically when the script sources `SpielCPP.R` and friends — `Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")`. The C++ source files are intentionally kept in the repo for this workflow even though the production container uses Rust.

For the canonical operator guide, see [`docs/user-guide/season-transition.md`](../user-guide/season-transition.md). Issue [#74](https://github.com/chrisschwer/League-Simulator-Update/issues/74) tracks discoverability of the validation/report/cleanup helpers.

## Building Docker images

> **You don't build production Docker images on macOS. You build them on a Linux machine** — historically by hand on a server you control. The Mac-side workflow is R + Rust + Shiny iteration only.

A future goal is to **move image-build to CI**: a GitHub Actions workflow that builds and (optionally) pushes to a registry on pushes to `main`. That work is tracked in issue [#76](https://github.com/chrisschwer/League-Simulator-Update/issues/76) (CI rebuild). Until #76 lands, treat `docker build` / `docker-compose build` as a Linux-only operation.

## Environment variables

The full table is in [Deployment Overview](README.md#required-environment-variables). For local iteration you typically only need:

- `RAPIDAPI_KEY` — required if you're hitting api-football
- `RUST_API_URL=http://localhost:8080` — only if you're running the Rust server outside the container

`SHINYAPPS_IO_SECRET` and friends only matter if you're testing the deploy step against a real ShinyApps.io account.

## Related

- [Quick Start](quick-start.md) — get a deployed container running
- [Deployment Overview](README.md) — what runs in production
- [`CLAUDE.md`](../../CLAUDE.md) — common commands cheat-sheet
- [Season Transition](../user-guide/season-transition.md) — operator guide
