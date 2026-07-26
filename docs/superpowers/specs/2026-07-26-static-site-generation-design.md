# Static Site Generation — Design

**Date:** 2026-07-26
**Status:** Approved design, supersedes `2026-07-26-connect-cloud-migration-design.md`
**Trigger:** Posit retires shinyapps.io; the simulator already runs self-hosted in the operator's homelab

## Problem

The Shiny app is hosted on shinyapps.io (Starter plan, 13 USD/month), which Posit
is retiring — paid accounts are force-migrated on 2027-03-31. Migrating to
Connect Cloud would keep the cost and add an OAuth service-account migration.

Investigating what shinyapps.io actually provides revealed that the hosted Shiny
runtime buys almost nothing:

| Property | Measured |
|---|---|
| Data payload (`ShinyApp/data/Ergebnis.Rds`) | **5.4 KB** |
| Reactivity | none — no `reactive()`, no `observe()`, no session use, no writes |
| Distinct views | **three**, selected by one `selectInput` (`input$Liga`) |
| Data load timing | at app **startup** (`app.R:19`), not reactive |

Because data is read at startup rather than reactively, viewers with an open
session do not see new results until shinyapps.io recycles the process. The
server-side runtime therefore provides no interactivity that a static page
cannot.

Meanwhile the deployment path is grossly disproportionate: `updateShiny.R`
ships 5.4 KB of new data by **redeploying and restarting the entire
application**, up to ~241 times per matchday (`updateScheduler.R:80`, a loop
every 2 minutes from 14:45–22:45).

The simulator already runs 24/7 in the operator's homelab during the season, so
the marginal cost of serving three static pages from the same machine is
effectively zero.

## Solution

Replace the hosted Shiny app with **static pre-rendering**. After each
simulation cycle, render the three league views to self-contained HTML plus PNG
plots into an output directory. Any web server (Caddy, nginx) serves that
directory.

This eliminates: Shiny at runtime, `rsconnect`, the deployment credentials, the
Connect Cloud migration, the 2027-03-31 deadline, the undocumented deploy
rate-limit risk, and the 13 USD/month cost.

### Architecture

One new module, `RCode/generate_static_site.R`, exposing:

```r
generate_static_site(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg,
                     output_dir, now = Sys.time())
```

It writes:

```
<output_dir>/
├── index.html            # Bundesliga (canonical entry point)
├── 2-bundesliga.html
├── 3-liga.html
└── assets/
    ├── bundesliga.png
    ├── 2-bundesliga.png
    └── 3-liga.png
```

Navigation replaces the dropdown with three links present on every page, with
the current league marked. This is the one user-visible change.

**Reuse, don't reimplement.** The three rendering primitives already exist and
are already unit-tested: `display_result()` (heatmap, `app.R:31-76`),
`prozent()` (`app.R:78-91`), and `groupResultsDF()` (`app.R:93-122`). They are
currently trapped inside `app.R`. Move them verbatim into
`RCode/render_helpers.R` so both the static generator and the existing tests can
source them. `ShinyApp/app_helpers.R` (`load_results`, `data_age_hours`,
`stale_warning_text`) is reused unchanged.

### Per-league configuration

The three leagues are **not symmetric** — this is the detail most likely to be
got wrong, so it is specified exhaustively. Note especially that 3. Liga draws
its top table from `Ergebnis3_Aufstieg` but its bottom table and heatmap from
`Ergebnis3`.

| | Bundesliga | 2. Bundesliga | 3. Liga |
|---|---|---|---|
| Page | `index.html` | `2-bundesliga.html` | `3-liga.html` |
| Heatmap source | `Ergebnis` | `Ergebnis2` | `Ergebnis3` |
| Heatmap `Teams` | 18 | 18 | 20 |
| Heatmap title | `Saisonprognose Bundesliga` | `Saisonprognose 2. Bundesliga` | `Saisonprognose 3. Liga` |
| Top table source | `Ergebnis` | `Ergebnis2` | **`Ergebnis3_Aufstieg`** |
| Top table filter | `rowSums(x[,1:6]) >= 0.01` | `rowSums(x[,1:3]) >= 0.01` | `rowSums(x[,1:4]) >= 0.01` |
| Top table labels | Meister, Champions League, Europa League, Conference League Quali | Aufstieg, Relegation Bundesliga | Aufstieg, Relegation, DFB-Pokal |
| Top table groups | `cbind(c(1,1),c(2,4),c(5,5),c(6,6))` | `cbind(c(1,2),c(3,3))` | `cbind(c(1,2),c(3,3),c(4,4))` |
| Bottom table source | `Ergebnis` | `Ergebnis2` | `Ergebnis3` |
| Bottom table filter | `rowSums(x[,16:18]) >= 0.01` | `rowSums(x[,16:18]) >= 0.01` | `rowSums(x[,17:20]) >= 0.01` |
| Bottom table labels | Relegation, Abstieg | Relegation 3. Liga, Abstieg | Abstieg |
| Bottom table groups | `cbind(c(16,16),c(17,18))` | `cbind(c(16,16),c(17,18))` | `cbind(c(17,20))` |

Data shapes, verified from the live file: `Ergebnis` 18×18, `Ergebnis2` 18×18,
`Ergebnis3` 20×20, `Ergebnis3_Aufstieg` 20×20 (all class `table`).

### Behaviour preserved from the Shiny app

- **Footer timestamp** with DST-correct label: `MESZ` when `updatetime$isdst > 0`,
  else `MEZ` (`app.R:160-165`). Existing test
  `tests/testthat/test-shiny-footer-timezone.R` covers this logic and currently
  duplicates the expression by hand; the static generator should use the shared
  helper so the duplication ends.
- **Stale-data banner** past 24 hours, via `stale_warning_text()`.
- **Graceful degradation**: when results cannot be loaded, emit a page carrying
  the existing "Noch keine Prognosedaten verfügbar" message rather than failing.
- Title "Fußball-Prognosen von 30Punkte" and the `30punkte.wordpress.com` link.

### Integration

`RCode/update_all_leagues_loop.R:163-169` currently calls `updateShiny()` behind
a `simulation_executed && !is.null(Ergebnis)` gate. Replace that call with
`generate_static_site()`, keeping the gate. Output directory comes from
`STATIC_SITE_DIR` (default `ShinyApp/public`), mounted as a volume so the web
server sees it.

Writing 5.4 KB of local files is cheap and idempotent, so the redeploy-frequency
concern disappears entirely — no hash-gating needed.

## Out of scope

- The `RAPIDAPI_KEY` / simulation pipeline — untouched.
- Web server, TLS, and public routing (Caddy/Cloudflare Tunnel) — operator
  infrastructure, documented but not automated here.
- Deleting `ShinyApp/app.R`. It stays as a local development tool and rollback
  path until the static site has run one full matchday. Retiring it is a
  follow-up.

## Testing strategy

`display_result`, `prozent`, and `groupResultsDF` move to
`RCode/render_helpers.R` unchanged, so existing tests keep passing —
`tests/testthat/test-prozent.R` and `test-shiny-app-helpers.R` are the
regression net for the move.

New tests for `generate_static_site()`, using the real 5.4 KB fixture:

- writes all four expected files (three HTML + `assets/` PNGs)
- each page contains its league's title and all three navigation links
- the Bundesliga page's top table contains the expected group labels
- 3. Liga's top table is built from `Ergebnis3_Aufstieg`, its bottom from
  `Ergebnis3` (guards the asymmetry)
- footer renders `MESZ` for a summer timestamp and `MEZ` for a winter one
- stale banner appears for a 30-hour-old timestamp, absent for a fresh one
- missing/corrupt data produces the fallback page and does not error
- output is deterministic: two runs with the same inputs and fixed `now`
  produce byte-identical HTML

Manual gate: open the generated `index.html` in a browser, confirm all three
pages render heatmaps and tables and that navigation works.

## Rollback

`ShinyApp/app.R` remains functional and shinyapps.io stays live until the static
site has served one full matchday. Rollback is reverting the one call site in
`update_all_leagues_loop.R`.

## Migration sequence

1. Implement and test the generator (no production change).
2. Run it alongside the existing deploy for one matchday; compare output against
   the live Shiny app.
3. Point the homelab web server at the output directory.
4. Switch the call site; stop deploying to shinyapps.io.
5. Cancel the shinyapps.io subscription — well before 2027-03-31, so the forced
   migration never applies.
