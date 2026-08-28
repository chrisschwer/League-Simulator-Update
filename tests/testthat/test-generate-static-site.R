# Static site generation — Relaunch-Design (Phase 3).
#
# Verträge dieser Suite:
# - Vier Seiten (drei Ligen + Methodik) im 30-Punkte-Design, HTML-Heatmap
#   statt PNG, gemeinsames Stylesheet und selbst gehostete Fonts unter
#   assets/, Favicon; keinerlei externe Ressourcen.
# - Erhalten aus der Vor-Relaunch-Seite: Panels (inkl. 3.-Liga-Asymmetrie),
#   Stale-Banner-Mechanik, ISO-Zeitstempel, Fallback-Seite, Determinismus.
# Uses the real committed fixture shape (18x18, 18x18, 20x20, 20x20).

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

# Der Block der Prognose-Heatmap einer Seite (erste table.heatmap).
heatmap_block <- function(html) {
  m <- regmatches(html, regexpr('<table class="heatmap"(.|\n)*?</table>', html))
  expect_length(m, 1)
  m
}

render_bundesliga <- function(gen, env, out,
                              now = as.POSIXct("2026-07-26 14:30:00",
                                               tz = "Europe/Berlin")) {
  gen$render_league_page(gen$league_views()$bundesliga, env, out, now = now)
}

# ---------------------------------------------------------------------------
# Zeitstempel (unverändert aus der Vor-Relaunch-Suite)
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Panels (unverändert in der Sache, neues Umfeld)
# ---------------------------------------------------------------------------

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
  expect_equal(lengths(regmatches(html, gregexpr("<tr><th scope=\"row\">", html))), 20L)
  expect_true(grepl("Abstieg", html, fixed = TRUE))
})

test_that("3. Liga page is built from Ergebnis3_Aufstieg on top and Ergebnis3 below", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

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

# ---------------------------------------------------------------------------
# Relaunch: HTML-Heatmap statt PNG
# ---------------------------------------------------------------------------

test_that("render_league_page writes an HTML page and no PNG asset", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  path <- render_bundesliga(gen, env, out)

  expect_true(file.exists(path))
  expect_equal(basename(path), "index.html")
  expect_length(list.files(out, pattern = "\\.png$", recursive = TRUE), 0)
})

test_that("the prognosis heatmap is an HTML table with one row per team", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))
  hm <- heatmap_block(html)

  expect_equal(lengths(regmatches(hm, gregexpr("<th scope=\"row\"", hm))), 18L)
  # 18 Platz-Spaltenköpfe
  for (platz in c(">1<", ">10<", ">18<")) {
    expect_true(grepl(platz, hm, fixed = TRUE), info = platz)
  }

  # 3. Liga: 20 Zeilen
  html3 <- read_html(gen$render_league_page(
    gen$league_views()$dritte_liga, env, out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  ))
  hm3 <- heatmap_block(html3)
  expect_equal(lengths(regmatches(hm3, gregexpr("<th scope=\"row\"", hm3))), 20L)
})

test_that("heatmap cells use the prozent notation", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  # Zeile 1 bekommt die vier Randfälle: >99, <1, 0 (leer) — Zeile 2 ein
  # sicheres Ergebnis (Haken).
  env$Ergebnis["T1", ] <- 0
  env$Ergebnis["T1", "1"] <- 0.995
  env$Ergebnis["T1", "2"] <- 0.005
  env$Ergebnis["T2", ] <- 0
  env$Ergebnis["T2", "2"] <- 1

  html <- read_html(render_bundesliga(gen, env, out))
  hm <- heatmap_block(html)

  expect_true(grepl("&gt;99", hm, fixed = TRUE))
  # "<1" nur als Färbung auf schmalen Bildschirmen: eigener Span
  expect_true(grepl('<span class="lt1">&lt;1</span>', hm, fixed = TRUE))
  expect_true(grepl("✓", hm, fixed = TRUE))
  # Nullzellen bleiben leer
  expect_true(grepl("></td>", hm, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Relaunch: Identität, Navigation, Metadaten
# ---------------------------------------------------------------------------

test_that("pages carry the 30-Punkte masthead and identity", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))

  expect_true(grepl("<title>30 Punkte · Bundesliga</title>", html, fixed = TRUE))
  expect_true(grepl(">30 Punkte<", html, fixed = TRUE))       # Wortmarke
  expect_true(grepl('class="mastrule"', html, fixed = TRUE))  # die eine rote Linie
  expect_true(grepl('<html lang="de">', html, fixed = TRUE))
  expect_true(grepl('name="viewport"', html, fixed = TRUE))
  expect_true(grepl('name="description"', html, fixed = TRUE))
  expect_true(grepl('property="og:title"', html, fixed = TRUE))
  expect_true(grepl("30punkte.wordpress.com", html, fixed = TRUE))
})

test_that("every page links all three leagues and the Methodik page", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  for (view in gen$league_views()) {
    path <- gen$render_league_page(view, env, out, now = now)
    html <- read_html(path)
    for (f in c("index.html", "2-bundesliga.html", "3-liga.html", "methodik.html")) {
      expect_true(grepl(f, html, fixed = TRUE), info = paste(view$slug, f))
    }
    expect_true(grepl('aria-current="page"', html, fixed = TRUE), info = view$slug)
  }
})

test_that("pages reference the shared stylesheet and favicon and load nothing external", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))

  expect_true(grepl('href="assets/site.css"', html, fixed = TRUE))
  expect_true(grepl('rel="icon"', html, fixed = TRUE))

  # Selbstenthaltend: keine externen Ressourcen, keine Bilder mehr
  expect_false(grepl("<script src=", html, fixed = TRUE))
  expect_false(grepl('<link[^>]+href="http', html))
  expect_false(grepl("fonts.googleapis", html, fixed = TRUE))
  expect_false(grepl("<img", html, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Relaunch: Assets (Stylesheet, Fonts, Favicon)
# ---------------------------------------------------------------------------

test_that("generate_static_site ships stylesheet, self-hosted fonts and favicon", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  gen$generate_static_site(
    env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
    output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  css_path <- file.path(out, "assets", "site.css")
  expect_true(file.exists(css_path))
  css <- read_html(css_path)
  expect_true(grepl("#B0261E", css, fixed = TRUE))
  expect_true(grepl("@font-face", css, fixed = TRUE))
  expect_true(grepl("Source Serif 4", css, fixed = TRUE))
  expect_false(grepl("googleapis", css, fixed = TRUE))

  fonts <- list.files(file.path(out, "assets", "fonts"), pattern = "\\.woff2$")
  expect_gte(length(fonts), 3)

  expect_true(file.exists(file.path(out, "assets", "favicon.svg")))
})

# ---------------------------------------------------------------------------
# Relaunch: Methodik-Seite
# ---------------------------------------------------------------------------

test_that("generate_static_site renders the Methodik page from the content file", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  paths <- gen$generate_static_site(
    env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
    output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  methodik <- file.path(out, "methodik.html")
  expect_true(methodik %in% paths)
  html <- read_html(methodik)

  # Inhalt kommt aus der redigierbaren Datei RCode/site_assets/methodik_content.html
  expect_true(grepl("Was die Prognosen mit Schach zu tun haben", html, fixed = TRUE))
  expect_true(grepl('class="provenienz"', html, fixed = TRUE))
  # aber ohne den Redaktions-Kommentarkopf der Quelldatei
  expect_false(grepl("ENTWURF", html, fixed = TRUE))

  expect_true(grepl("<title>30 Punkte · Methodik</title>", html, fixed = TRUE))
  expect_true(grepl('aria-current="page" href="methodik.html"', html, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Erhalten: Zeitstempel, Stale-Banner, Fallback, Determinismus
# ---------------------------------------------------------------------------

test_that("the page embeds the generation time as ISO-8601 UTC", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))
  expect_true(grepl('<time id="generated" datetime="2026-07-26T12:30:00Z"',
                    html, fixed = TRUE))
})

test_that("the stale banner is embedded hidden and revealed by inline JS", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))

  expect_true(grepl('id="stale" hidden', html, fixed = TRUE))
  expect_true(grepl("werden derzeit nicht aktualisiert", html, fixed = TRUE))
  expect_true(grepl("<script>", html, fixed = TRUE))
  expect_false(grepl("<script src=", html, fixed = TRUE))
  expect_true(grepl("getElementById(\"generated\")", html, fixed = TRUE))
  expect_true(grepl("> 24", html, fixed = TRUE))
})

test_that("generate_static_site writes four pages and no PNGs", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  paths <- gen$generate_static_site(
    env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
    output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  expect_length(paths, 4)
  for (f in c("index.html", "2-bundesliga.html", "3-liga.html", "methodik.html")) {
    expect_true(file.exists(file.path(out, f)), info = f)
  }
  expect_length(list.files(out, pattern = "\\.png$", recursive = TRUE), 0)
})

test_that("generate_static_site writes the fallback page when data is missing", {
  gen <- source_generator()
  out <- withr::local_tempdir()

  paths <- gen$generate_static_site(
    NULL, NULL, NULL, NULL, output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  expect_length(paths, 1)
  html <- read_html(file.path(out, "index.html"))
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

  for (f in c("index.html", "2-bundesliga.html", "3-liga.html", "methodik.html",
              file.path("assets", "site.css"))) {
    expect_equal(
      readLines(file.path(out1, f), warn = FALSE),
      readLines(file.path(out2, f), warn = FALSE),
      info = f
    )
  }
})
