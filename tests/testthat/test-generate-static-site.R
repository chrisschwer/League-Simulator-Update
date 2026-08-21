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
    # Production tables carry team short names as rownames and the rank
    # ("1".."n") as colnames, exactly as SimWrapper emits them.
    m <- matrix(1 / n, nrow = teams, ncol = n,
                dimnames = list(paste0("T", seq_len(teams)), as.character(seq_len(n))))
    as.table(m)
  }
  env$Ergebnis <- mk(18, 18)
  env$Ergebnis2 <- mk(18, 18)
  env$Ergebnis3 <- mk(20, 20)
  env$Ergebnis3_Aufstieg <- mk(20, 20)
  env
}

read_html <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")

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

test_that("render_panel_table keeps its shape for a single-label panel", {
  gen <- source_generator()
  views <- gen$league_views()
  env <- make_data_env()
  html <- gen$render_panel_table(env$Ergebnis3, views$dritte_liga$bottom)
  # one header row plus one body row per team (all 20 pass the 1% filter)
  expect_equal(lengths(regmatches(html, gregexpr("<tr><th scope=\"row\">", html))), 20L)
  expect_true(grepl("Abstieg", html, fixed = TRUE))
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

  html <- read_html(path)
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
    html <- read_html(path)
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
  html <- read_html(path)

  expect_true(grepl("AUFSTIEGONLY", html, fixed = TRUE))
  expect_true(grepl("ABSTIEGONLY", html, fixed = TRUE))
})

test_that("the page embeds the generation time as ISO-8601 UTC", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  path <- gen$render_league_page(gen$league_views()$bundesliga, env, out,
                                 now = now)
  html <- read_html(path)
  expect_true(grepl('<time id="generated" datetime="2026-07-26T12:30:00Z"',
                    html, fixed = TRUE))
})

test_that("the stale banner is embedded hidden and revealed by inline JS", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  path <- gen$render_league_page(gen$league_views()$bundesliga, env, out,
                                 now = now)
  html <- read_html(path)

  # A static page goes stale exactly when nobody re-renders it, so the
  # banner cannot be decided at render time. It ships hidden ...
  expect_true(grepl('<div class="stale" id="stale" hidden>', html, fixed = TRUE))
  expect_true(grepl("werden derzeit nicht aktualisiert", html, fixed = TRUE))
  # ... and a self-contained script flips it after 24 hours.
  expect_true(grepl("<script>", html, fixed = TRUE))
  expect_false(grepl("<script src=", html, fixed = TRUE))
  expect_true(grepl("getElementById(\"generated\")", html, fixed = TRUE))
  expect_true(grepl("> 24", html, fixed = TRUE))
})
