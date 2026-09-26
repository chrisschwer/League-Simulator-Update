# Ligatabelle-Sektion (Phase 4a): sortierbare Liga-/ELO-Tabelle nach dem
# freigegebenen Mock-up. Der Renderer bekommt die von build_league_page_data()
# angereicherte tabelle; ohne league_data bleibt die Seite exakt auf
# Phase-3-Stand (Degradation).

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

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

mk_tabelle <- function() {
  data.frame(
    platz = 1:3,
    team_id = c(102, 101, 103),
    name = c("Bayer Leverkusen", "Bayern München", "1. FC Köln"),
    spiele = c(2, 1, 2),
    tore = c(4, 2, 1),
    gegentore = c(2, 1, 4),
    tordifferenz = c(2, 1, -3),
    punkte = c(6, 3, 1),
    elo = c(1845.5, 2061.23, 1539.2),
    delta_elo = c(5.5, -13.34, 0),
    stringsAsFactors = FALSE
  )
}

league_entry <- function() list(tabelle = mk_tabelle())

test_that("render_liga_tabelle baut die sortierbare Tabelle nach Mock-up", {
  gen <- source_generator()
  html <- gen$render_liga_tabelle(mk_tabelle())

  expect_match(html, 'id="ligatabelle"', fixed = TRUE)
  # Sortier-Buttons mit data-key; Platz ist Default (aria-sort)
  expect_match(html, 'data-key="platz"', fixed = TRUE)
  expect_match(html, 'data-key="pkt"', fixed = TRUE)
  expect_match(html, 'data-key="elo"', fixed = TRUE)
  expect_match(html, 'aria-sort="ascending"', fixed = TRUE)

  # Volle Vereinsnamen, Reihenfolge wie geliefert
  expect_match(html, "Bayer Leverkusen", fixed = TRUE)
  expect_true(
    regexpr("Bayer Leverkusen", html, fixed = TRUE) <
      regexpr("Bayern München", html, fixed = TRUE)
  )
})

test_that("Zahlenformate: Komma-Dezimal, echtes Minus, ±0,0; data-Attribute mit Punkt", {
  gen <- source_generator()
  html <- gen$render_liga_tabelle(mk_tabelle())

  # ELO mit einer Nachkommastelle und Komma
  expect_match(html, ">1845,5<")
  expect_match(html, ">2061,2<")
  # Delta: Vorzeichen immer; U+2212 als Minus; Null als ±0,0
  expect_match(html, "+5,5", fixed = TRUE)
  expect_match(html, "−13,3", fixed = TRUE)
  expect_match(html, "±0,0", fixed = TRUE)
  # Sortier-Datenattribute maschinenlesbar (Punkt-Dezimal)
  expect_match(html, 'data-elo="2061.23"', fixed = TRUE)
  expect_match(html, 'data-pkt="6"', fixed = TRUE)
  expect_match(html, 'data-platz="1"', fixed = TRUE)
})

test_that("Sp. und Tordiff. sind als optionale Mobil-Spalten markiert", {
  gen <- source_generator()
  html <- gen$render_liga_tabelle(mk_tabelle())

  # je Zeile zwei opt-Zellen (Sp., Tordiff.) plus zwei opt-Spaltenköpfe
  expect_equal(
    lengths(regmatches(html, gregexpr('class="num opt"', html))), 8L
  )
  expect_match(html, "Tordiff", fixed = TRUE)
})

test_that("Tordifferenz wird mit Vorzeichen gesetzt", {
  gen <- source_generator()
  html <- gen$render_liga_tabelle(mk_tabelle())

  expect_match(html, ">+2<", fixed = TRUE)
  expect_match(html, ">−3<", fixed = TRUE)
})

test_that("Teamnamen werden HTML-escaped", {
  gen <- source_generator()
  tab <- mk_tabelle()
  tab$name[1] <- "A & B <FC>"
  html <- gen$render_liga_tabelle(tab)

  expect_match(html, "A &amp; B &lt;FC&gt;", fixed = TRUE)
  expect_false(grepl("<FC>", html, fixed = TRUE))
})

test_that("die Liga-Seite bindet die Sektion samt Sortier-Skript ein", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  path <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-08-28 19:00:00", tz = "Europe/Berlin"),
    league_entry = league_entry()
  )
  html <- read_html(path)

  expect_match(html, 'id="ligatabelle"', fixed = TRUE)
  expect_match(html, "Ligatabelle und ELO", fixed = TRUE)
  expect_match(html, ">Tabelle<")                   # Eyebrow
  expect_match(html, "ligatabelle", fixed = TRUE)   # Sortier-JS referenziert die Tabelle
  expect_false(grepl("<script src=", html, fixed = TRUE))

  # Sektionsreihenfolge: Prognose vor Tabelle
  expect_true(
    regexpr("Saisonprognose", html, fixed = TRUE) <
      regexpr("Ligatabelle und ELO", html, fixed = TRUE)
  )
})

test_that("ohne league_entry bleibt die Seite auf Phase-3-Stand", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  path <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-08-28 19:00:00", tz = "Europe/Berlin")
  )
  html <- read_html(path)

  expect_false(grepl('id="ligatabelle"', html, fixed = TRUE))
  expect_false(grepl("Ligatabelle und ELO", html, fixed = TRUE))
})

test_that("generate_static_site verteilt league_data je Liga", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  gen$generate_static_site(
    env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
    league_data = list(bundesliga = league_entry()),
    output_dir = out,
    now = as.POSIXct("2026-08-28 19:00:00", tz = "Europe/Berlin")
  )

  expect_true(grepl('id="ligatabelle"',
                    read_html(file.path(out, "index.html")), fixed = TRUE))
  expect_false(grepl('id="ligatabelle"',
                     read_html(file.path(out, "2-bundesliga.html")), fixed = TRUE))
})

test_that("ein NULL-Eintrag in league_data ist gleichbedeutend mit fehlend", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  expect_no_error(
    gen$generate_static_site(
      env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
      league_data = list(bundesliga = NULL, zweite_bundesliga = NULL,
                         dritte_liga = NULL),
      output_dir = out,
      now = as.POSIXct("2026-08-28 19:00:00", tz = "Europe/Berlin")
    )
  )
  expect_false(grepl('id="ligatabelle"',
                     read_html(file.path(out, "index.html")), fixed = TRUE))
})
