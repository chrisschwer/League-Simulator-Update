# Static Site Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shinyapps.io-hosted Shiny app with three statically pre-rendered pages produced by the simulator itself, served from the operator's existing homelab.

**Architecture:** Extract the three rendering primitives out of `ShinyApp/app.R` into `RCode/render_helpers.R`, then add `RCode/generate_static_site.R` which writes `index.html`, `2-bundesliga.html`, `3-liga.html` and PNG heatmaps into an output directory. Swap the `updateShiny()` call in the scheduler loop for `generate_static_site()`. The Shiny app stays on disk as a rollback path.

**Tech Stack:** R 4.6, `ggplot2`, `reshape2`, `htmltools` (already a dependency), `testthat` 3.2.3, `withr` 3.0.2.

## Global Constraints

- **No new dependencies.** `htmltools` is already in `packagelist.txt:24`; use it for HTML escaping and tag construction. Do not add `rmarkdown`, `knitr`, or `quarto`.
- **`rsconnect` and `shiny` are not required at runtime** by any new code. Do not `library(shiny)` in the generator.
- **Reuse, don't reimplement:** `display_result()`, `prozent()`, `groupResultsDF()` move verbatim from `ShinyApp/app.R`. Changing their behaviour would break `tests/testthat/test-prozent.R`.
- **Preserve exactly:** the DST-aware footer (`MESZ` when `updatetime$isdst > 0`, else `MEZ`), the 24-hour stale banner, the "Noch keine Prognosedaten verfügbar" fallback, the title "Fußball-Prognosen von 30Punkte", and the `30punkte.wordpress.com` link.
- **The three leagues are asymmetric.** 3. Liga's top table uses `Ergebnis3_Aufstieg`; its bottom table and heatmap use `Ergebnis3`. Full table in the spec — copy values from there, do not infer.
- Data shapes: `Ergebnis` 18×18, `Ergebnis2` 18×18, `Ergebnis3` 20×20, `Ergebnis3_Aufstieg` 20×20, all class `table`.
- Output dir env var: `STATIC_SITE_DIR`, default `ShinyApp/public`.
- Run the full suite with `Rscript -e 'source("tests/testthat.R")'`; a single file with `Rscript -e 'testthat::test_file("tests/testthat/<file>.R")'`.
- `ShinyApp/app.R` must keep working until Task 6 signs off. Do not delete it.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `RCode/render_helpers.R` | `display_result`, `prozent`, `groupResultsDF` — shared rendering primitives | Create (moved from `app.R`) |
| `ShinyApp/app.R` | Shiny UI; sources the shared helpers instead of defining them | Modify |
| `RCode/league_views.R` | Per-league config: sources, filters, labels, group matrices | Create |
| `RCode/generate_static_site.R` | Renders PNGs + HTML pages to the output directory | Create |
| `RCode/update_all_leagues_loop.R` | Call `generate_static_site()` instead of `updateShiny()` | Modify lines 163-169 |
| `tests/testthat/test-render-helpers-move.R` | Regression: helpers still behave after the move | Create |
| `tests/testthat/test-league-views.R` | Per-league config correctness, incl. the 3. Liga asymmetry | Create |
| `tests/testthat/test-generate-static-site.R` | Output files, nav, footer, stale banner, fallback, determinism | Create |
| `docs/deployment/static-site.md` | Operator runbook: web server, volume, cutover, rollback | Create |

---

### Task 1: Extract rendering helpers out of `app.R`

Pure move, no behaviour change. Unlocks reuse by the generator and ends the situation where tested functions live inside a Shiny app file.

**Files:**
- Create: `RCode/render_helpers.R`
- Modify: `ShinyApp/app.R:31-122` (remove the three functions), `ShinyApp/app.R:17` (add source)
- Test: `tests/testthat/test-render-helpers-move.R`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `display_result(result, colour = "grey", low = "white", high = "steelblue", Titel = "Endplatzierung", labeling = FALSE, Teams = 18)` → a ggplot object.
  - `prozent(x)` → numeric, or a tick character `intToUtf8(0x2713)` at exactly 1, `">99"` above .99, `"<1"` below .01.
  - `groupResultsDF(results, labels, groups)` → data.frame with `length(labels)` columns, rownames preserved from `results`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-render-helpers-move.R`:

```r
# The rendering primitives moved out of ShinyApp/app.R into
# RCode/render_helpers.R so the static site generator can reuse them.
# These assertions pin the behaviour across the move.

source_render_helpers <- function() {
  source(test_path("..", "..", "RCode", "render_helpers.R"), local = TRUE)
  environment()
}

test_that("render_helpers.R defines all three primitives", {
  env <- source_render_helpers()
  expect_true(is.function(env$display_result))
  expect_true(is.function(env$prozent))
  expect_true(is.function(env$groupResultsDF))
})

test_that("prozent keeps its boundary behaviour after the move", {
  env <- source_render_helpers()
  expect_equal(env$prozent(0), 0)
  expect_equal(env$prozent(0.5), 50)
  expect_equal(env$prozent(1), intToUtf8(0x2713))
  expect_equal(env$prozent(0.995), ">99")
  expect_equal(env$prozent(0.001), "<1")
  expect_equal(env$prozent("text"), "text")
})

test_that("groupResultsDF sums column ranges and preserves rownames", {
  env <- source_render_helpers()
  m <- matrix(0.1, nrow = 2, ncol = 4,
              dimnames = list(c("AAA", "BBB"), NULL))
  out <- env$groupResultsDF(m, labels = c("first", "rest"),
                            groups = cbind(c(1, 1), c(2, 4)))
  expect_equal(colnames(out), c("first", "rest"))
  expect_equal(rownames(out), c("AAA", "BBB"))
  expect_equal(out$first, c(0.1, 0.1))
  expect_equal(out$rest, c(0.3, 0.3), tolerance = 1e-8)
})

test_that("display_result returns a ggplot for a probability table", {
  env <- source_render_helpers()
  m <- matrix(1 / 18, nrow = 18, ncol = 18,
              dimnames = list(paste0("T", 1:18), NULL))
  p <- env$display_result(m, Titel = "Test", Teams = 18)
  expect_s3_class(p, "ggplot")
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-render-helpers-move.R")'`

Expected: FAIL — `RCode/render_helpers.R` does not exist, so `source()` errors with "cannot open file".

- [ ] **Step 3: Create `RCode/render_helpers.R`**

Move lines 31-122 of `ShinyApp/app.R` verbatim into the new file, with a header. The bodies must not change — only their location.

```r
# Rendering primitives shared by the Shiny app (ShinyApp/app.R) and the static
# site generator (RCode/generate_static_site.R).
#
# Requires: ggplot2, reshape2 (melt).

display_result <- function (result, colour = "grey",
                            low = "white", high = "steelblue",
                            Titel = "Endplatzierung",
                            labeling = FALSE, Teams = 18)

  # Displays results from SimWrapper in a heatmap
  # result : results to display
  # colour : background colour for tiles
  # low : colour for lower end of scale
  # high : colour for higher end of scale
  # Titel : text of the title line of the chart
  # labeling : boolean, if true the tiles of the heatmap
  #            are labeled with the values in percent

{

  if (labeling)
  {
    result <- round(result*100,0)
  }

  result.m <- melt (result)
  plot <- ggplot (result.m) +
    aes (Var1, Var2) +
    geom_tile(aes (fill=value),
              colour = colour) +
    scale_fill_gradient (low = low, high = high,
                         name = "p") +
    labs (x = "Verein", y = "Platz") +
    ggtitle (Titel) +
    theme_grey()
  plot <- plot +
    theme (axis.text.x = element_text (size = rel (0.8), angle = 330,
                                       hjust = 0, colour = "grey50"))
  plot <- plot +
    theme (axis.ticks = element_line (linetype = 0)) +
    scale_y_reverse(breaks = 1:Teams)

  if (labeling)
  {
    plot <- plot + geom_text (aes (label = value))
  }


  return (plot)
}

prozent <- function (x) {
  if (!is.numeric(x)) {return (x)}
  if ((x >= .01) && (x <= .99)) {
    return (round (100 * x, digits = 0))
  } else if (x == 1) {
    return (intToUtf8(0x2713)) # Tick mark instead of 100 percent
  } else if (x == 0) {
    return (0)
  } else if (x > 0.99) {
    return (">99")
  } else if (x < 0.01) {
    return ("<1")
  }
}

groupResultsDF <- function (results,
                            labels = c("Meister", "Champions League", "Europa League",
                                       "Conference League Quali", "Mittelfeld", "Relegation", "Abstieg"),
                            groups = cbind(c(1,1), c(2,4), c(5,5),
                                           c(6,6), c(7,15), c(16,16), c(17,18))) {

  # groups results into a data frame of labeled groups
  # results : data frame with n probabilities for n teams
  # labels : vector of strings, labels for the groups
  # groups : 2xn matrix of integers, lower and upper bounds for groups

  outputDF <- data.frame (matrix(ncol=length(labels), nrow=dim(results)[1]))
  colnames (outputDF) <- labels
  rownames (outputDF) <- rownames (results)

  for (i in 1:length(labels)) {
    lower <- groups [1,i]
    upper <- groups [2,i]
    if (lower == upper) {
      newcol <- results[,lower]
    } else {
      range <- c(lower:upper)
      newcol <- rowSums(results[, range])
    }
    outputDF[,i] <- newcol

  }

  return (outputDF)
}
```

Note the test calls `display_result` with a plain `matrix`, and `melt()` on a matrix yields `Var1`/`Var2` columns — matching the existing behaviour with `table` inputs.

- [ ] **Step 4: Remove the moved functions from `ShinyApp/app.R` and source the new file**

Delete `ShinyApp/app.R` lines 31-122 (the three function definitions). Then change line 17 from:

```r
source("app_helpers.R", local = TRUE)
```

to:

```r
source("app_helpers.R", local = TRUE)
source("../RCode/render_helpers.R", local = TRUE)
```

The relative path works when the app is run from `ShinyApp/` (as `shiny::runApp("ShinyApp/app.R")` and the old `updateShiny()` `setwd()` both do). The app is now a local development tool only — it is no longer deployed, so bundling concerns do not apply.

- [ ] **Step 5: Run the new test and the full suite**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-render-helpers-move.R")'`
Expected: all four tests PASS.

Run: `Rscript -e 'source("tests/testthat.R")'`
Expected: no new failures. `test-prozent.R` and `test-shiny-app-helpers.R` are the regression net — if either fails, the move was not verbatim.

- [ ] **Step 6: Commit**

```bash
git add RCode/render_helpers.R ShinyApp/app.R tests/testthat/test-render-helpers-move.R
git commit -m "refactor: extract rendering primitives from app.R into RCode/render_helpers.R

display_result, prozent and groupResultsDF were defined inside the Shiny
app but are needed by the static site generator. Pure move, no behaviour
change; test-prozent.R is the regression net."
```

---

### Task 2: Per-league view configuration

The three leagues differ in data source, filter columns, labels and group matrices — and 3. Liga mixes two data objects. Isolating this as data makes the asymmetry reviewable and testable instead of buried in branching code.

**Files:**
- Create: `RCode/league_views.R`
- Test: `tests/testthat/test-league-views.R`

**Interfaces:**
- Consumes: nothing.
- Produces: `league_views()` → named list of three entries, keys `bundesliga`, `zweite_bundesliga`, `dritte_liga`. Each entry is a list with fields:
  - `slug` (character): output filename without extension — `"index"`, `"2-bundesliga"`, `"3-liga"`
  - `nav_label` (character): `"Bundesliga"`, `"2. Bundesliga"`, `"3. Liga"`
  - `plot_title` (character), `teams` (integer)
  - `plot_source` (character): name of the data object for the heatmap
  - `top` / `bottom` (list): `source`, `filter_cols` (integer vector), `labels` (character vector), `groups` (matrix)

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-league-views.R`:

```r
# Per-league configuration. The leagues are asymmetric: 3. Liga's promotion
# table comes from Ergebnis3_Aufstieg while its relegation table and heatmap
# come from Ergebnis3. These assertions pin that down.

source_league_views <- function() {
  source(test_path("..", "..", "RCode", "league_views.R"), local = TRUE)
  environment()$league_views
}

test_that("league_views defines exactly the three leagues", {
  views <- source_league_views()()
  expect_named(views, c("bundesliga", "zweite_bundesliga", "dritte_liga"))
})

test_that("Bundesliga is the canonical index page", {
  v <- source_league_views()()$bundesliga
  expect_equal(v$slug, "index")
  expect_equal(v$nav_label, "Bundesliga")
  expect_equal(v$plot_source, "Ergebnis")
  expect_equal(v$teams, 18)
  expect_equal(v$top$labels,
               c("Meister", "Champions League", "Europa League",
                 "Conference League Quali"))
  expect_equal(v$top$filter_cols, 1:6)
  expect_equal(v$bottom$labels, c("Relegation", "Abstieg"))
  expect_equal(v$bottom$filter_cols, 16:18)
})

test_that("2. Bundesliga uses Ergebnis2 for every panel", {
  v <- source_league_views()()$zweite_bundesliga
  expect_equal(v$slug, "2-bundesliga")
  expect_equal(v$plot_source, "Ergebnis2")
  expect_equal(v$top$source, "Ergebnis2")
  expect_equal(v$bottom$source, "Ergebnis2")
  expect_equal(v$top$labels, c("Aufstieg", "Relegation Bundesliga"))
  expect_equal(v$top$filter_cols, 1:3)
})

test_that("3. Liga draws its top table from Ergebnis3_Aufstieg but its bottom from Ergebnis3", {
  v <- source_league_views()()$dritte_liga
  expect_equal(v$slug, "3-liga")
  expect_equal(v$teams, 20)
  expect_equal(v$plot_source, "Ergebnis3")
  expect_equal(v$top$source, "Ergebnis3_Aufstieg")
  expect_equal(v$bottom$source, "Ergebnis3")
  expect_equal(v$top$labels, c("Aufstieg", "Relegation", "DFB-Pokal"))
  expect_equal(v$top$filter_cols, 1:4)
  expect_equal(v$bottom$labels, "Abstieg")
  expect_equal(v$bottom$filter_cols, 17:20)
})

test_that("group matrices have two rows and one column per label", {
  views <- source_league_views()()
  for (nm in names(views)) {
    v <- views[[nm]]
    for (panel in c("top", "bottom")) {
      g <- v[[panel]]$groups
      expect_equal(nrow(g), 2, info = paste(nm, panel))
      expect_equal(ncol(g), length(v[[panel]]$labels), info = paste(nm, panel))
      expect_true(all(g[1, ] <= g[2, ]), info = paste(nm, panel))
    }
  }
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-league-views.R")'`

Expected: FAIL — `RCode/league_views.R` does not exist.

- [ ] **Step 3: Create `RCode/league_views.R`**

Values transcribed from `ShinyApp/app.R:175-228`. Do not infer any of them.

```r
# Per-league view configuration for the static site.
#
# Transcribed from the Shiny server logic in ShinyApp/app.R. The leagues are
# deliberately asymmetric: 3. Liga's promotion table is built from
# Ergebnis3_Aufstieg, while its relegation table and heatmap use Ergebnis3.

league_views <- function() {
  list(
    bundesliga = list(
      slug = "index",
      nav_label = "Bundesliga",
      plot_title = "Saisonprognose Bundesliga",
      plot_source = "Ergebnis",
      teams = 18L,
      top = list(
        source = "Ergebnis",
        filter_cols = 1:6,
        labels = c("Meister", "Champions League", "Europa League",
                   "Conference League Quali"),
        groups = cbind(c(1, 1), c(2, 4), c(5, 5), c(6, 6))
      ),
      bottom = list(
        source = "Ergebnis",
        filter_cols = 16:18,
        labels = c("Relegation", "Abstieg"),
        groups = cbind(c(16, 16), c(17, 18))
      )
    ),
    zweite_bundesliga = list(
      slug = "2-bundesliga",
      nav_label = "2. Bundesliga",
      plot_title = "Saisonprognose 2. Bundesliga",
      plot_source = "Ergebnis2",
      teams = 18L,
      top = list(
        source = "Ergebnis2",
        filter_cols = 1:3,
        labels = c("Aufstieg", "Relegation Bundesliga"),
        groups = cbind(c(1, 2), c(3, 3))
      ),
      bottom = list(
        source = "Ergebnis2",
        filter_cols = 16:18,
        labels = c("Relegation 3. Liga", "Abstieg"),
        groups = cbind(c(16, 16), c(17, 18))
      )
    ),
    dritte_liga = list(
      slug = "3-liga",
      nav_label = "3. Liga",
      plot_title = "Saisonprognose 3. Liga",
      plot_source = "Ergebnis3",
      teams = 20L,
      top = list(
        source = "Ergebnis3_Aufstieg",
        filter_cols = 1:4,
        labels = c("Aufstieg", "Relegation", "DFB-Pokal"),
        groups = cbind(c(1, 2), c(3, 3), c(4, 4))
      ),
      bottom = list(
        source = "Ergebnis3",
        filter_cols = 17:20,
        labels = "Abstieg",
        groups = cbind(c(17, 20))
      )
    )
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-league-views.R")'`
Expected: all five tests PASS.

- [ ] **Step 5: Commit**

```bash
git add RCode/league_views.R tests/testthat/test-league-views.R
git commit -m "feat: add per-league view configuration for the static site

Extracts the asymmetric per-league table/plot config from the Shiny
server branches into reviewable data, including 3. Liga's split between
Ergebnis3_Aufstieg (promotion) and Ergebnis3 (relegation, heatmap)."
```

---

### Task 3: Render one league page

The core of the generator: given one league config and the loaded data, produce a PNG heatmap and an HTML page. Kept separate from the multi-page orchestration so it can be tested in isolation.

**Files:**
- Create: `RCode/generate_static_site.R`
- Test: `tests/testthat/test-generate-static-site.R`

**Interfaces:**
- Consumes: `league_views()` (Task 2); `display_result`, `prozent`, `groupResultsDF` (Task 1); `stale_warning_text`, `data_age_hours` from `ShinyApp/app_helpers.R`.
- Produces:
  - `render_panel_table(data_obj, panel)` → character HTML `<table>`; filters rows by `rowSums(data_obj[, panel$filter_cols]) >= 0.01`, groups via `groupResultsDF`, formats via `prozent`.
  - `footer_timestamp(mtime)` → character like `"Letztes Update: 26.07.2026 14:30 MESZ"`.
  - `render_league_page(view, data_env, output_dir, now)` → invisible path of the written HTML file; also writes `assets/<slug>.png`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-generate-static-site.R`:

```r
# Static site generation. Uses the real committed fixture shape (18x18, 18x18,
# 20x20, 20x20 probability tables) so the tests exercise realistic data.

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

# Build a data environment with the same object names and shapes as the
# production ShinyApp/data/Ergebnis.Rds.
make_data_env <- function() {
  env <- new.env()
  mk <- function(n, teams) {
    m <- matrix(1 / n, nrow = teams, ncol = n,
                dimnames = list(paste0("T", seq_len(teams)), NULL))
    as.table(m)
  }
  env$Ergebnis <- mk(18, 18)
  env$Ergebnis2 <- mk(18, 18)
  env$Ergebnis3 <- mk(20, 20)
  env$Ergebnis3_Aufstieg <- mk(20, 20)
  env
}

test_that("footer_timestamp labels summer time MESZ", {
  gen <- source_generator()
  ts <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  expect_match(gen$footer_timestamp(ts), "MESZ")
  expect_match(gen$footer_timestamp(ts), "26\\.07\\.2026 14:30")
})

test_that("footer_timestamp labels winter time MEZ", {
  gen <- source_generator()
  ts <- as.POSIXct("2026-01-15 14:30:00", tz = "Europe/Berlin")
  expect_match(gen$footer_timestamp(ts), "MEZ")
  expect_false(grepl("MESZ", gen$footer_timestamp(ts)))
})

test_that("render_panel_table emits one column per label", {
  gen <- source_generator()
  views <- gen$league_views()
  env <- make_data_env()
  html <- gen$render_panel_table(env$Ergebnis, views$bundesliga$top)

  for (lbl in views$bundesliga$top$labels) {
    expect_true(grepl(lbl, html, fixed = TRUE), info = lbl)
  }
  expect_match(html, "<table")
})

test_that("render_league_page writes an HTML file and a PNG asset", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()
  view <- gen$league_views()$bundesliga

  path <- gen$render_league_page(
    view, env, out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  expect_true(file.exists(path))
  expect_equal(basename(path), "index.html")
  expect_true(file.exists(file.path(out, "assets", "index.png")))

  html <- paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_true(grepl("Saisonprognose Bundesliga", html, fixed = TRUE))
  expect_true(grepl("Fußball-Prognosen von 30Punkte", html, fixed = TRUE))
  expect_true(grepl("30punkte.wordpress.com", html, fixed = TRUE))
})

test_that("every page carries links to all three leagues", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  for (view in gen$league_views()) {
    path <- gen$render_league_page(view, env, out, now = now)
    html <- paste(readLines(path, warn = FALSE), collapse = "\n")
    expect_true(grepl("index.html", html, fixed = TRUE), info = view$slug)
    expect_true(grepl("2-bundesliga.html", html, fixed = TRUE), info = view$slug)
    expect_true(grepl("3-liga.html", html, fixed = TRUE), info = view$slug)
  }
})

test_that("3. Liga page is built from Ergebnis3_Aufstieg on top and Ergebnis3 below", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  # Make the two sources distinguishable: give Ergebnis3_Aufstieg a team name
  # that appears nowhere in Ergebnis3.
  rownames(env$Ergebnis3_Aufstieg)[1] <- "AUFSTIEGONLY"
  rownames(env$Ergebnis3)[1] <- "ABSTIEGONLY"

  path <- gen$render_league_page(
    gen$league_views()$dritte_liga, env, out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )
  html <- paste(readLines(path, warn = FALSE), collapse = "\n")

  expect_true(grepl("AUFSTIEGONLY", html, fixed = TRUE))
  expect_true(grepl("ABSTIEGONLY", html, fixed = TRUE))
})

test_that("a stale timestamp produces the warning banner", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  path <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = now, mtime = now - as.difftime(30, units = "hours")
  )
  html <- paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_true(grepl("werden derzeit nicht aktualisiert", html, fixed = TRUE))
})

test_that("a fresh timestamp produces no warning banner", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  path <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = now, mtime = now - as.difftime(1, units = "hours")
  )
  html <- paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_false(grepl("werden derzeit nicht aktualisiert", html, fixed = TRUE))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-generate-static-site.R")'`

Expected: FAIL — `RCode/generate_static_site.R` does not exist.

- [ ] **Step 3: Create `RCode/generate_static_site.R`**

```r
# Static site generation.
#
# Renders the three league views to self-contained HTML pages plus PNG heatmaps.
# Replaces the shinyapps.io deployment: the simulator writes these files after
# each cycle and any web server serves the directory.

library(ggplot2)
library(reshape2)

# Resolve sibling modules relative to this file so the generator works from any
# working directory.
.gss_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) "RCode")
if (is.null(.gss_dir) || is.na(.gss_dir)) .gss_dir <- "RCode"

source(file.path(.gss_dir, "render_helpers.R"), local = TRUE)
source(file.path(.gss_dir, "league_views.R"), local = TRUE)
source(file.path(.gss_dir, "..", "ShinyApp", "app_helpers.R"), local = TRUE)

BLOG_URL <- "http://30punkte.wordpress.com"
SITE_TITLE <- "Fußball-Prognosen von 30Punkte"

footer_timestamp <- function(mtime) {
  lt <- as.POSIXlt(mtime, tz = "Europe/Berlin")
  # isdst: >0 = DST (MESZ), 0 = standard (MEZ), <0 = unknown -> falls through to MEZ
  tzlabel <- if (lt$isdst > 0) "MESZ" else "MEZ"
  paste0("Letztes Update: ", format(lt, "%d.%m.%Y %H:%M"), " ", tzlabel)
}

render_panel_table <- function(data_obj, panel) {
  keep <- rowSums(data_obj[, panel$filter_cols, drop = FALSE]) >= 0.01
  subset_obj <- data_obj[keep, , drop = FALSE]

  if (nrow(subset_obj) == 0) {
    return("")
  }

  grouped <- groupResultsDF(subset_obj,
                            labels = panel$labels,
                            groups = panel$groups)
  formatted <- apply(grouped, c(1, 2), prozent)

  # apply() drops to a vector when there is a single label column; restore shape.
  if (is.null(dim(formatted))) {
    formatted <- matrix(formatted, ncol = length(panel$labels),
                        dimnames = list(rownames(grouped), panel$labels))
  }

  cells <- apply(formatted, 1, function(row) {
    paste0("<td>", htmltools::htmlEscape(as.character(row)), "</td>",
           collapse = "")
  })

  rows <- paste0(
    "<tr><th scope=\"row\">",
    htmltools::htmlEscape(rownames(formatted)), "</th>",
    cells, "</tr>",
    collapse = "\n"
  )

  paste0(
    "<table>\n<thead><tr><th></th>",
    paste0("<th>", htmltools::htmlEscape(panel$labels), "</th>", collapse = ""),
    "</tr></thead>\n<tbody>\n", rows, "\n</tbody>\n</table>"
  )
}

.nav_html <- function(current_slug, views) {
  items <- vapply(views, function(v) {
    label <- htmltools::htmlEscape(v$nav_label)
    if (identical(v$slug, current_slug)) {
      paste0("<span class=\"nav-current\">", label, "</span>")
    } else {
      paste0("<a href=\"", v$slug, ".html\">", label, "</a>")
    }
  }, character(1))
  paste0("<nav>", paste(items, collapse = " · "), "</nav>")
}

.page_css <- paste(
  "body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;",
  "margin:0 auto;max-width:1000px;padding:1rem;line-height:1.5}",
  "nav{margin:1rem 0}nav a{margin-right:.25rem}",
  ".nav-current{font-weight:700;text-decoration:underline}",
  "table{border-collapse:collapse;margin:1rem 0;width:100%}",
  "th,td{border:1px solid #ddd;padding:.3rem .5rem;text-align:right}",
  "th[scope=row]{text-align:left}",
  "img{max-width:100%;height:auto}",
  ".stale{background-color:#f8d7da;color:#721c24;padding:10px;",
  "border-radius:4px;margin-bottom:12px}",
  "footer{margin-top:2rem;font-size:.9rem;color:#555}",
  sep = ""
)

render_league_page <- function(view, data_env, output_dir,
                               now = Sys.time(), mtime = now) {
  dir.create(file.path(output_dir, "assets"), recursive = TRUE,
             showWarnings = FALSE)

  plot_obj <- get(view$plot_source, envir = data_env)
  png_rel <- file.path("assets", paste0(view$slug, ".png"))
  ggplot2::ggsave(
    filename = file.path(output_dir, png_rel),
    plot = display_result(plot_obj, Titel = view$plot_title,
                          Teams = view$teams),
    width = 10, height = 6, dpi = 110
  )

  top_html <- render_panel_table(get(view$top$source, envir = data_env),
                                 view$top)
  bottom_html <- render_panel_table(get(view$bottom$source, envir = data_env),
                                    view$bottom)

  stale <- stale_warning_text(data_age_hours(mtime, now = now))
  stale_html <- if (is.null(stale)) {
    ""
  } else {
    paste0("<div class=\"stale\">", htmltools::htmlEscape(stale), "</div>")
  }

  html <- paste0(
    "<!doctype html>\n<html lang=\"de\">\n<head>\n",
    "<meta charset=\"utf-8\">\n",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n",
    "<title>", htmltools::htmlEscape(SITE_TITLE), " – ",
    htmltools::htmlEscape(view$nav_label), "</title>\n",
    "<style>", .page_css, "</style>\n</head>\n<body>\n",
    "<h1>", htmltools::htmlEscape(SITE_TITLE), "</h1>\n",
    .nav_html(view$slug, league_views()), "\n",
    stale_html, "\n",
    "<img src=\"", png_rel, "\" alt=\"",
    htmltools::htmlEscape(view$plot_title), "\">\n",
    top_html, "\n", bottom_html, "\n",
    "<footer>\n<p>Alle Prognosen als Wahrscheinlichkeiten in Prozent ",
    "angegeben. Nähere Infos unter <a href=\"", BLOG_URL,
    "\" target=\"blank_\">30punkte.wordpress.com</a></p>\n",
    "<p>", htmltools::htmlEscape(footer_timestamp(mtime)), "</p>\n",
    "</footer>\n</body>\n</html>\n"
  )

  out_path <- file.path(output_dir, paste0(view$slug, ".html"))
  writeLines(html, out_path, useBytes = TRUE)
  invisible(out_path)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-generate-static-site.R")'`

Expected: all eight tests PASS. If the `render_panel_table` single-label case fails for 3. Liga's bottom table (`labels = "Abstieg"`), the `is.null(dim(formatted))` restore is the code path to check — `apply()` collapses to a vector there.

- [ ] **Step 5: Commit**

```bash
git add RCode/generate_static_site.R tests/testthat/test-generate-static-site.R
git commit -m "feat: render a league view to static HTML plus PNG heatmap

Reuses display_result/prozent/groupResultsDF and the existing staleness
helpers, so the static pages preserve the Shiny app's DST-aware footer,
24h stale banner and table grouping."
```

---

### Task 4: Orchestrate all three pages with a fallback

Wraps the per-page renderer into the entry point the scheduler calls, including the "no data" degradation path the Shiny app had.

**Files:**
- Modify: `RCode/generate_static_site.R` (add the orchestrator)
- Test: `tests/testthat/test-generate-static-site.R` (extend)

**Interfaces:**
- Consumes: `render_league_page()`, `league_views()` from Task 3.
- Produces: `generate_static_site(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg = Ergebnis3, output_dir = Sys.getenv("STATIC_SITE_DIR", "ShinyApp/public"), now = Sys.time())` → invisible character vector of written page paths. Writes a fallback `index.html` when data is missing.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-generate-static-site.R`:

```r
test_that("generate_static_site writes all three pages and their assets", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  paths <- gen$generate_static_site(
    env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
    output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  expect_length(paths, 3)
  for (f in c("index.html", "2-bundesliga.html", "3-liga.html")) {
    expect_true(file.exists(file.path(out, f)), info = f)
  }
  for (f in c("index.png", "2-bundesliga.png", "3-liga.png")) {
    expect_true(file.exists(file.path(out, "assets", f)), info = f)
  }
})

test_that("generate_static_site writes the fallback page when data is missing", {
  gen <- source_generator()
  out <- withr::local_tempdir()

  paths <- gen$generate_static_site(
    NULL, NULL, NULL, NULL, output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  expect_length(paths, 1)
  html <- paste(readLines(file.path(out, "index.html"), warn = FALSE),
                collapse = "\n")
  expect_true(grepl("Noch keine Prognosedaten verfügbar", html, fixed = TRUE))
  expect_true(grepl("30punkte.wordpress.com", html, fixed = TRUE))
})

test_that("generate_static_site output is deterministic for fixed inputs", {
  gen <- source_generator()
  env <- make_data_env()
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  out1 <- withr::local_tempdir()
  out2 <- withr::local_tempdir()
  gen$generate_static_site(env$Ergebnis, env$Ergebnis2, env$Ergebnis3,
                           env$Ergebnis3_Aufstieg, output_dir = out1, now = now)
  gen$generate_static_site(env$Ergebnis, env$Ergebnis2, env$Ergebnis3,
                           env$Ergebnis3_Aufstieg, output_dir = out2, now = now)

  for (f in c("index.html", "2-bundesliga.html", "3-liga.html")) {
    expect_equal(
      readLines(file.path(out1, f), warn = FALSE),
      readLines(file.path(out2, f), warn = FALSE),
      info = f
    )
  }
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-generate-static-site.R")'`

Expected: the eight Task 3 tests PASS; the three new ones FAIL because `generate_static_site` is not defined.

- [ ] **Step 3: Add the orchestrator to `RCode/generate_static_site.R`**

Append:

```r
.render_fallback_page <- function(output_dir) {
  html <- paste0(
    "<!doctype html>\n<html lang=\"de\">\n<head>\n",
    "<meta charset=\"utf-8\">\n",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n",
    "<title>", htmltools::htmlEscape(SITE_TITLE), "</title>\n",
    "<style>", .page_css, "</style>\n</head>\n<body>\n",
    "<h1>", htmltools::htmlEscape(SITE_TITLE), "</h1>\n",
    "<h3>Noch keine Prognosedaten verfügbar</h3>\n",
    "<p>Die Simulationsergebnisse wurden noch nicht erzeugt oder konnten ",
    "nicht geladen werden. Bitte versuchen Sie es später erneut.</p>\n",
    "<footer><p>Nähere Infos unter <a href=\"", BLOG_URL,
    "\" target=\"blank_\">30punkte.wordpress.com</a></p></footer>\n",
    "</body>\n</html>\n"
  )
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  out_path <- file.path(output_dir, "index.html")
  writeLines(html, out_path, useBytes = TRUE)
  invisible(out_path)
}

generate_static_site <- function(Ergebnis, Ergebnis2, Ergebnis3,
                                 Ergebnis3_Aufstieg = Ergebnis3,
                                 output_dir = Sys.getenv("STATIC_SITE_DIR",
                                                         "ShinyApp/public"),
                                 now = Sys.time()) {
  have_data <- !is.null(Ergebnis) && !is.null(Ergebnis2) && !is.null(Ergebnis3)

  if (!have_data) {
    message("generate_static_site: no simulation data, writing fallback page")
    return(invisible(.render_fallback_page(output_dir)))
  }

  data_env <- new.env(parent = emptyenv())
  assign("Ergebnis", Ergebnis, envir = data_env)
  assign("Ergebnis2", Ergebnis2, envir = data_env)
  assign("Ergebnis3", Ergebnis3, envir = data_env)
  assign("Ergebnis3_Aufstieg",
         if (is.null(Ergebnis3_Aufstieg)) Ergebnis3 else Ergebnis3_Aufstieg,
         envir = data_env)

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  paths <- vapply(league_views(), function(view) {
    message(sprintf("generate_static_site: rendering %s", view$slug))
    render_league_page(view, data_env, output_dir, now = now, mtime = now)
  }, character(1))

  message(sprintf("generate_static_site: wrote %d pages to %s",
                  length(paths), output_dir))
  invisible(unname(paths))
}
```

- [ ] **Step 4: Run the whole file and then the full suite**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-generate-static-site.R")'`
Expected: all eleven tests PASS.

Run: `Rscript -e 'source("tests/testthat.R")'`
Expected: no new failures.

- [ ] **Step 5: Generate the site from the real committed fixture and inspect it**

Run:

```bash
Rscript -e '
  source("RCode/generate_static_site.R")
  e <- new.env(); load("ShinyApp/data/Ergebnis.Rds", envir = e)
  generate_static_site(e$Ergebnis, e$Ergebnis2, e$Ergebnis3, e$Ergebnis3_Aufstieg,
                       output_dir = "ShinyApp/public")
'
ls -R ShinyApp/public
```

Expected: three HTML files and three PNGs. Open `ShinyApp/public/index.html` in a browser and confirm the heatmap renders, both tables appear, navigation switches between all three leagues, and the footer shows a plausible Berlin timestamp.

- [ ] **Step 6: Ignore the generated output and commit**

Add to `.gitignore`:

```
ShinyApp/public/
```

```bash
git add RCode/generate_static_site.R tests/testthat/test-generate-static-site.R .gitignore
git commit -m "feat: generate the full three-page static site

Adds the generate_static_site() entry point with the no-data fallback
page the Shiny app had, plus a determinism test so repeated cycles do not
produce spurious diffs."
```

---

### Task 5: Call the generator from the scheduler loop

Switches production over. Small change, but it is the one that matters — keep the existing gate so behaviour on "no new simulation" is unchanged.

**Files:**
- Modify: `RCode/update_all_leagues_loop.R:59` (source) and `:163-169` (call site)
- Test: `tests/testthat/test-update-loop-gating.R` (extend)

**Interfaces:**
- Consumes: `generate_static_site()` from Task 4.
- Produces: no new API.

- [ ] **Step 1: Read the current call site and its tests**

Run:

```bash
sed -n '55,62p;160,172p' RCode/update_all_leagues_loop.R
grep -n "updateShiny" tests/testthat/test-update-loop-gating.R
```

Note the existing gate `simulation_executed && !is.null(Ergebnis)` and how the test stubs `updateShiny` via `mockery::stub`. The stub target changes to `generate_static_site`.

- [ ] **Step 2: Write the failing test**

Add to `tests/testthat/test-update-loop-gating.R`, adapting to that file's existing setup helpers (it already builds a loop-invocation harness — reuse it rather than inventing a new one):

```r
test_that("the loop generates the static site when a simulation ran", {
  called <- new.env()
  called$n <- 0L

  # Reuse this file's existing harness for invoking one loop iteration.
  # Stub the generator and assert the gate still fires exactly once.
  stub_generate <- function(...) {
    called$n <- called$n + 1L
    invisible(character(0))
  }

  run_one_loop_iteration(simulation_executed = TRUE,
                         generate_static_site = stub_generate)
  expect_equal(called$n, 1L)
})

test_that("the loop skips site generation when no simulation ran", {
  called <- new.env()
  called$n <- 0L
  stub_generate <- function(...) {
    called$n <- called$n + 1L
    invisible(character(0))
  }

  run_one_loop_iteration(simulation_executed = FALSE,
                         generate_static_site = stub_generate)
  expect_equal(called$n, 0L)
})
```

If `test-update-loop-gating.R` has no reusable `run_one_loop_iteration` helper, mirror the `mockery::stub` pattern already used at its lines 76, 107 and 137, swapping the stubbed function name from `updateShiny` to `generate_static_site`.

- [ ] **Step 3: Run the test to verify it fails**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-update-loop-gating.R")'`

Expected: the new tests FAIL — the loop still calls `updateShiny`, so the `generate_static_site` stub is never invoked.

- [ ] **Step 4: Switch the call site**

In `RCode/update_all_leagues_loop.R`, change the source on line 59 from:

```r
source("RCode/updateShiny.R")
```

to:

```r
source("RCode/generate_static_site.R")
```

and replace the call block at lines 163-169:

```r
      # Update Shiny if simulations have been executed
      if (simulation_executed && !is.null(Ergebnis)) {
        message(sprintf("Loop %d: Updating Shiny app with new results", i))
        updateShiny(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg, directory = shiny_directory)
      } else {
        message(sprintf("Loop %d: No updates needed, skipping Shiny deployment", i))
      }
```

with:

```r
      # Regenerate the static site if simulations have been executed
      if (simulation_executed && !is.null(Ergebnis)) {
        message(sprintf("Loop %d: Regenerating static site with new results", i))
        generate_static_site(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg)
      } else {
        message(sprintf("Loop %d: No updates needed, skipping site generation", i))
      }
```

`generate_static_site()` takes its output directory from `STATIC_SITE_DIR`, so the `shiny_directory` argument is no longer passed here. Check whether `shiny_directory` is still used elsewhere in the file (`updateScheduler.R:167-175` passes it in) — if it has become unused, leave the parameter in place for now and note it for the follow-up cleanup rather than changing the scheduler's signature in this task.

- [ ] **Step 5: Run the tests and the full suite**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-update-loop-gating.R")'`
Expected: PASS, including the pre-existing gating tests.

Run: `Rscript -e 'source("tests/testthat.R")'`
Expected: no new failures. `tests/testthat/test-updateShiny-env.R` still passes because `RCode/updateShiny.R` is untouched and still on disk.

- [ ] **Step 6: Commit**

```bash
git add RCode/update_all_leagues_loop.R tests/testthat/test-update-loop-gating.R
git commit -m "feat: generate the static site instead of deploying to shinyapps.io

The scheduler loop now writes local files rather than redeploying the
whole app up to ~241 times per matchday. updateShiny.R stays on disk as
the rollback path until the static site has served one full matchday."
```

---

### Task 6: Operator runbook and cutover

The deliverable that makes this usable: how to serve the directory, how to cut over, how to roll back, and when to cancel the subscription.

**Files:**
- Create: `docs/deployment/static-site.md`
- Modify: `docker-compose.yml` (volume + `STATIC_SITE_DIR`), `.env.example`, `docs/deployment/README.md`, `README.md:5`

**Interfaces:**
- Consumes: `STATIC_SITE_DIR` from Task 4.
- Produces: nothing consumed by code.

- [ ] **Step 1: Expose the output directory from the container**

In `docker-compose.yml`, add to the `league-simulator-integrated` service's `environment:` list (after line 13):

```yaml
      - STATIC_SITE_DIR=/app/ShinyApp/public
```

and add a volume so the host web server can read the generated files:

```yaml
    volumes:
      - ./ShinyApp/public:/app/ShinyApp/public
```

The container runs as uid 1001 (per `Dockerfile:127-130`), so the host directory must be writable by that uid. Create it before first run:

```bash
mkdir -p ShinyApp/public && chmod 777 ShinyApp/public
```

- [ ] **Step 2: Document the env var**

In `.env.example`, add under the optional block:

```bash
# STATIC_SITE_DIR=ShinyApp/public
```

In `docs/deployment/README.md`, add a row to the env-var table and remove the three `SHINYAPPS_IO_*` rows, replacing them with a pointer:

```markdown
| `STATIC_SITE_DIR` | no | `ShinyApp/public` | Output directory for the generated static site |
```

Note below the table: ShinyApps.io deployment has been replaced by static site generation — see [`static-site.md`](static-site.md).

- [ ] **Step 3: Write the runbook**

Create `docs/deployment/static-site.md`:

```markdown
# Static Site

The simulator renders three pre-rendered pages after each simulation cycle and
writes them to `STATIC_SITE_DIR` (default `ShinyApp/public`). Any web server
serves that directory — there is no Shiny runtime, no `rsconnect`, and no
deployment credentials.

This replaced the shinyapps.io deployment. Background:
[`docs/superpowers/specs/2026-07-26-static-site-generation-design.md`](../superpowers/specs/2026-07-26-static-site-generation-design.md).

## Output

```
ShinyApp/public/
├── index.html          # Bundesliga
├── 2-bundesliga.html
├── 3-liga.html
└── assets/*.png
```

Total size is a few hundred KB. Writes are idempotent, so regenerating every
2 minutes during a matchday costs nothing.

## Serving it

Caddy handles TLS automatically and is the shortest path:

```caddyfile
prognosen.example.org {
    root * /srv/league-simulator/public
    file_server
    encode gzip
}
```

If you would rather not expose a port, a Cloudflare Tunnel pointed at a local
`file_server` works the same way.

Point the web root at the host side of the compose volume
(`./ShinyApp/public`).

## Generating manually

```bash
Rscript -e '
  source("RCode/generate_static_site.R")
  e <- new.env(); load("ShinyApp/data/Ergebnis.Rds", envir = e)
  generate_static_site(e$Ergebnis, e$Ergebnis2, e$Ergebnis3, e$Ergebnis3_Aufstieg)
'
```

## Cutover

1. Generate the site manually (above) and compare it against the live
   shinyapps.io app — same probabilities, same team lists, same timestamp
   behaviour.
2. Point the web server at the output directory and confirm it serves publicly
   over TLS.
3. Run one full matchday with both paths active. The scheduler already generates
   the static site; shinyapps.io stays live in parallel.
4. Once satisfied, update the dashboard link in `README.md` and cancel the
   shinyapps.io subscription. Do this well before **2027-03-31**, when Posit's
   forced migration to Connect Cloud would otherwise apply.

## Rollback

`RCode/updateShiny.R` and `ShinyApp/app.R` remain on disk. To go back, restore
the `updateShiny()` call in `RCode/update_all_leagues_loop.R` (see the commit
that switched it) and ensure `SHINYAPPS_IO_TOKEN` / `SHINYAPPS_IO_SECRET` are
still set.

## Local preview

`ShinyApp/app.R` still runs as a development tool:

```bash
Rscript -e 'shiny::runApp("ShinyApp/app.R")'
```
```

- [ ] **Step 4: Update the dashboard link in `README.md`**

`README.md:5` points at `https://chrisschwer.shinyapps.io/FussballPrognosen/`. Leave it until the static site is publicly served, then replace it with the new URL. Add a note now so it is not forgotten:

```markdown
Live dashboard: <https://chrisschwer.shinyapps.io/FussballPrognosen/>
(migrating to a self-hosted static site — see docs/deployment/static-site.md)
```

- [ ] **Step 5: Verify the container writes to the mounted directory**

Run:

```bash
mkdir -p ShinyApp/public && chmod 777 ShinyApp/public
docker-compose up -d --build
docker-compose exec league-simulator-integrated Rscript -e '
  source("RCode/generate_static_site.R")
  e <- new.env(); load("ShinyApp/data/Ergebnis.Rds", envir = e)
  generate_static_site(e$Ergebnis, e$Ergebnis2, e$Ergebnis3, e$Ergebnis3_Aufstieg)
'
ls -l ShinyApp/public ShinyApp/public/assets
```

Expected: the three HTML files and three PNGs appear on the **host**, proving the volume and uid-1001 write permissions work. If writes fail with a permission error, fix the host directory ownership rather than running the container as root.

- [ ] **Step 6: Commit**

```bash
git add docker-compose.yml .env.example docs/deployment/README.md docs/deployment/static-site.md README.md
git commit -m "docs: add static site runbook and expose the output directory

Documents serving the generated pages (Caddy/Cloudflare Tunnel), the
cutover sequence against the live Shiny app, and rollback. Adds the
STATIC_SITE_DIR volume so the host web server can read the output."
```

---

### Task 7: Retire the deployment path (after one clean matchday)

**Do not start this until the static site has served one full matchday successfully.** Until then `updateShiny.R` is the rollback path.

**Files:**
- Delete: `RCode/updateShiny.R`, `tests/testthat/test-updateShiny-env.R`
- Modify: `packagelist.txt` (drop `rsconnect` and its deploy-only deps), `Dockerfile:57,78`, `docker-compose.yml`, `.env.example`, `docs/deployment/README.md`, `docs/GITHUB_ACTIONS_CONFIG.md`

**Interfaces:**
- Consumes: a verified-working static site.
- Produces: nothing.

- [ ] **Step 1: Confirm nothing still references the deploy path**

Run:

```bash
grep -rn "updateShiny\|rsconnect\|SHINYAPPS_IO" --include="*.R" --include="*.yml" --include="*.yaml" --include="Dockerfile" --include="*.txt" . | grep -v "^./docs/"
```

Expected: hits only in the files this task deletes or edits. If `RCode/updateScheduler.R` still passes `shiny_directory`, remove that argument now (deferred from Task 5 Step 4).

- [ ] **Step 2: Delete the deployment module and its tests**

```bash
git rm RCode/updateShiny.R tests/testthat/test-updateShiny-env.R
```

- [ ] **Step 3: Drop the deploy-only dependencies**

In `packagelist.txt`, remove `rsconnect` (line 14) and the block added solely for deployment — `crayon`, `ellipsis`, `httpuv` (lines 20-22) — along with the comment on line 19. Keep `shiny` only if you still want `app.R` runnable inside the container; if not, drop `shiny`, `htmltools`, `promises` and `DT` too.

`htmltools` is used by `generate_static_site.R` — **keep it** regardless.

In `Dockerfile`, remove `'rsconnect'` from the vectors on lines 57 and 78.

- [ ] **Step 4: Remove the credentials from the runtime config**

In `docker-compose.yml`, delete the three `SHINYAPPS_IO_*` environment lines (7-9). In `.env.example`, delete the `SHINYAPPS_IO_SECRET` / `SHINYAPPS_IO_TOKEN` / `SHINYAPPS_IO_NAME` entries. In `docs/deployment/README.md`, remove the corresponding table rows.

In `docs/GITHUB_ACTIONS_CONFIG.md:14-16,127-130`, delete the `gh secret set SHINYAPPS_IO_*` instructions — no workflow ever read them (confirmed in `docs/superpowers/specs/2026-05-02-ci-rebuild-design.md:24`).

- [ ] **Step 5: Rebuild and run the full suite**

Run: `Rscript -e 'source("tests/testthat.R")'`
Expected: PASS with the `updateShiny` tests gone and no new failures.

Run: `docker build -t league-simulator:latest . && docker-compose up -d`
Expected: build succeeds without `rsconnect`; the scheduler starts and generates the site.

- [ ] **Step 6: Rotate the now-unused credentials and commit**

Revoke the shinyapps.io token/secret in the Posit account (they are no longer needed and exist in local `.env` history), then cancel the subscription.

```bash
git add -A
git commit -m "chore: retire the shinyapps.io deployment path

The static site has served a full matchday, so updateShiny.R, its tests,
rsconnect and the deploy-only dependencies come out. Credentials revoked
and the subscription cancelled, so the 2027-03-31 forced migration to
Connect Cloud no longer applies."
```

---

## Self-Review

**Spec coverage:** Helper extraction → Task 1. Per-league asymmetry incl. `Ergebnis3_Aufstieg`/`Ergebnis3` split → Task 2 (config) and Task 3 (rendering test that would catch a swap). Three pages + assets + nav → Tasks 3-4. DST footer → Task 3. Stale banner → Task 3. Fallback page → Task 4. Determinism → Task 4. Scheduler integration behind the existing gate → Task 5. Web server, volume, cutover, rollback → Task 6. Subscription cancellation before 2027-03-31 → Tasks 6 and 7. "Do not delete `app.R`" honoured — Task 7 removes only `updateShiny.R`, and gates even that on a clean matchday.

**Naming consistency:** `league_views()`, `render_panel_table()`, `footer_timestamp()`, `render_league_page()`, `generate_static_site()` are defined in Tasks 2-4 and referenced with identical signatures in Tasks 5-7. Slugs `index` / `2-bundesliga` / `3-liga` are used identically in the config, the tests, the nav, and the runbook. `STATIC_SITE_DIR` is spelled the same in Tasks 4, 5 and 6.

**Known risks flagged inline rather than hidden:** the `apply()` single-label collapse for 3. Liga's bottom table (Task 3 Step 4), uid-1001 write permission on the mounted volume (Task 6 Steps 1 and 5), and the possibly-absent `run_one_loop_iteration` harness in the existing gating test (Task 5 Step 2 gives the fallback pattern).

**Deferred deliberately:** removing the now-unused `shiny_directory` parameter threads through `updateScheduler.R:167-175`; Task 5 leaves it and Task 7 Step 1 picks it up, so the risky change happens when the deploy path is already gone.
