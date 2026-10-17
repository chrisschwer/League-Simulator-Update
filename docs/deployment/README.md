# Deployment

The League Simulator runs as a single Docker container that combines the Rust simulation engine and the R scheduler. This is the only production deployment path.

## Stack

- **`Dockerfile`** — multi-stage build: `rust:1.98-alpine` compiles the simulation binary in stage 1; `rocker/r-ver:4.6.1` runs the R scheduler in stage 2. (CI's advisory `r-lint` job still pins R 4.3.1 for `lintr` — see `.github/workflows/ci.yml` — that pin is independent of the image the container actually ships.)
- **`docker-compose.yml`** — single service `scheduler` (container `fussball-scheduler`). The Rust API stays container-internal; the generated static site is written to the external named volume `fussball-site`.
- **`docker-start.sh`** — container entrypoint. Starts the Rust server on `localhost:8080`, waits for it to be healthy, then runs `Rscript RCode/updateScheduler.R` with retry logic.
- **`RCode/updateScheduler.R`** — the R scheduler. Wakes at 11:00 Berlin time, polls api-football, calls the in-process Rust server when new fixtures arrive, renders the static site (see [`static-site.md`](static-site.md)).

## Schedule

- **Active hours:** 11:00 – 23:00 Berlin time (`updateScheduler.R` enforces both bounds; the 11:00 start covers the 2. Frauen-Bundesliga, which kicks off from 11:00).
- **Loop frequency:** every 2 minutes inside the active window (Rust engine is fast enough to allow this).
- **Outside the window:** the scheduler sleeps until the next 11:00. Each process is one day-run: it exits once the next loop no longer fits before 23:00, Docker restarts the container (`unless-stopped`), and the new process sleeps until 11:00. A start from 22:58 on (at most one 2-minute cadence left) already counts as "after the window", so there is exactly **one restart per evening** — `RestartCount` should rise by one a day, not by ~7 (#287).
- **Daylight saving:** the sleep is the real elapsed time from now until the next 11:00:00 Berlin time (today if still ahead, otherwise tomorrow), to the second. It is not a difference of wall-clock minutes. The night into the last Sunday of March has 23 hours and the one into the last Sunday of October has 25. The old wall-clock calculation woke the scheduler at 12:00 in spring, which missed the first hour, and at 10:00 in autumn. It then ran a full 720-minute window until 22:00 and needed an extra restart for the last hour.

## Required environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `RAPIDAPI_KEY` | yes | — | api-football access via RapidAPI |
| `SEASON` | no | auto-detect | Season year (e.g., `2026`); auto-detects from current month if unset |
| `DURATION` | no | window length (720) | Cap on scheduler runtime in minutes. Leave unset — a fixed value silently truncates the window when its bounds move. |
| `RUST_API_URL` | no | `http://localhost:8080` | Rust server endpoint inside the container |
| `PORT` | no | `8080` | Port the Rust server itself listens on (`league-simulator-rust/src/main.rs`); change together with `RUST_API_URL` |
| `TZ` | no | `Europe/Berlin` | Container timezone (load-bearing for the 11:00–23:00 window) |
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

## Image-Pflege

Abhängigkeiten des Images kommen aus drei Quellen, und nur zwei davon pflegt Dependabot (`.github/dependabot.yml`, montags):

| Quelle | Pflege |
|---|---|
| Cargo-Crates, GitHub Actions, `FROM`-Tags | Dependabot-PRs |
| R-Pakete (`ARG P3M_SNAPSHOT` im `Dockerfile`, fester Snapshot des Posit Package Manager) | `.github/workflows/p3m-snapshot.yml` |
| Neubauten desselben Basis-Tags (`rocker/r-ver:4.6.1` mit Sicherheitsupdates) und apt-Schichten (libcurl, openssl, libxml2) | ebenfalls über den Snapshot-PR, weil dessen CI ohne Cache baut |

**Ablauf des Snapshot-Workflows:** Am ersten Montag im Monat (05:17 UTC) setzt er den Snapshot auf das Datum von vor sieben Tagen, prüft, dass `https://p3m.dev/cran/__linux__/noble/<datum>/src/contrib/PACKAGES` einen Index liefert, ersetzt das Datum in der ARG-Zeile und öffnet den PR `deps/p3m-snapshot-<datum>` mit den Labels `dependencies` und (falls vorhanden) `docker`. Ist schon ein solcher PR offen oder ist der Snapshot nicht älter, tut er nichts. Für Branches `deps/p3m-snapshot-*` baut die CI mit `no-cache` und `pull: true`, also Basis-Image, apt, R-Pakete und Rust komplett frisch.

**Manuell auslösen:** `gh workflow run p3m-snapshot.yml` (oder Actions → „P3M snapshot bump“ → Run workflow). Die Prüfung „erster Montag“ gilt nur für den Zeitplan.

**CI am PR:** PRs, die mit dem Standard-`GITHUB_TOKEN` geöffnet werden, lösen keine `pull_request`-Workflows aus. Der Workflow startet die CI deshalb selbst per `workflow_dispatch` auf dem Bump-Branch (die einzige Ereignisart, die `GITHUB_TOKEN` auslösen darf); die Läufe hängen am Commit des PRs. Wer zusätzlich die `pull_request`-Checks (u. a. CodeQL) sehen will, schließt den PR einmal und öffnet ihn wieder.

**Voraussetzung (einmalig):** Damit `GITHUB_TOKEN` überhaupt PRs öffnen darf, muss unter Settings → Actions → General → Workflow permissions das Häkchen „Allow GitHub Actions to create and approve pull requests“ gesetzt sein. Alternative ohne diese Einstellung: ein Secret `P3M_BUMP_TOKEN` (Fine-grained PAT nur für dieses Repo, Rechte *Contents: Read and write* und *Pull requests: Read and write*). Ist es gesetzt, pusht und öffnet der Workflow damit; die CI läuft dann ganz normal als `pull_request`, der `workflow_dispatch`-Schritt entfällt.

**Beim PR zu tun:** CI abwarten (Image-Build + testthat im Image), im Build-Log prüfen, dass die R-Pakete als Binärpakete kommen, mergen. `push-image` baut dann auf main das neue Produktionsimage; das Deployment auf Eddie ist ein eigener Schritt.

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
