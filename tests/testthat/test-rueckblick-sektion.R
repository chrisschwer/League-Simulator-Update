# Rückblick- und Live-Sektion (Phase 4b) nach dem freigegebenen Mock-up.
# Der Renderer bekommt die von build_league_page_data() gefensterten und
# gejointen Spiellisten; Live-Spiele werden berichtet, aber ohne Prognose
# (Planergänzung 8a).

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

spielzeile <- function(kickoff, home, away, gh, ga, ph, px, pa, delta,
                       nachholspiel = FALSE, round = 2L) {
  data.frame(
    fixture_id = sample(9000:9999, 1),
    round = round,
    kickoff = as.POSIXct(kickoff, tz = "UTC"),
    status = "FT",
    home_id = 1, away_id = 2,
    home_name = home, away_name = away,
    goals_home = gh, goals_away = ga,
    p_home_win = ph, p_draw = px, p_away_win = pa,
    elo_delta_home = delta,
    nachholspiel = nachholspiel,
    stringsAsFactors = FALSE
  )
}

mk_rueckblick <- function() {
  rbind(
    spielzeile("2026-08-28 18:30", "FC Alpha", "SV Beta", 2, 1,
               0.44, 0.26, 0.30, 7.5),
    spielzeile("2026-08-29 13:30", "TSV Gamma", "1. FC Delta", 0, 3,
               0.05, 0.15, 0.80, -12.4, nachholspiel = TRUE, round = 1L),
    spielzeile("2026-08-30 15:30", "SV Beta", "TSV Gamma", 1, 1,
               0.38, 0.27, 0.35, NA)
  )
}

mk_live <- function() {
  df <- spielzeile("2026-08-30 17:30", "1. FC Delta", "FC Alpha", 1, 0,
                   NA, NA, NA, NA)
  df$status <- "1H"
  df
}

# ---------------------------------------------------------------- Rückblick --

test_that("render_rueckblick baut Überschrift und Spielzeilen nach Mock-up", {
  gen <- source_generator()
  html <- gen$render_rueckblick(mk_rueckblick(), runden = c(1L, 2L))

  expect_match(html, ">Rückblick<")          # Eyebrow
  expect_match(html, "1./2. Spieltag", fixed = TRUE)

  # Termin in Berliner Zeit mit schmalem geschützten Leerzeichen vor "Uhr"
  expect_match(html, "Fr. 28.8., 20:30 Uhr", fixed = TRUE)
  # Paarung mit Halbgeviert-Gedankenstrich
  expect_match(html, "FC Alpha", fixed = TRUE)
  expect_match(html, 'class="dash"', fixed = TRUE)
  expect_match(html, "–", fixed = TRUE)
  # Ergebnis
  expect_match(html, ">2:1<")
})

test_that("die Überschrift eines einzelnen Spieltags trägt keine Doppelform", {
  gen <- source_generator()
  html <- gen$render_rueckblick(mk_rueckblick()[1, ], runden = 2L)

  expect_match(html, ">2. Spieltag<")
  ueberschrift <- regmatches(html, regexpr("<h2[^>]*>[^<]*</h2>", html))
  inhalt <- gsub("<[^>]*>", "", ueberschrift)
  expect_false(grepl("/", inhalt, fixed = TRUE))
})

test_that("der 1/X/2-Balken kodiert die ex-ante-Wahrscheinlichkeiten", {
  gen <- source_generator()
  html <- gen$render_rueckblick(mk_rueckblick(), runden = c(1L, 2L))

  expect_match(html, 'class="oddsbar"', fixed = TRUE)
  expect_match(html, "Sieg Heim 44 %", fixed = TRUE)  # aria-label
  expect_match(html, "flex-basis:44%", fixed = TRUE)
  expect_match(html, "flex-basis:26%", fixed = TRUE)       # Remis = 100-44-30
  expect_match(html, "flex-basis:30%", fixed = TRUE)
  expect_match(html, "<i>44</i>", fixed = TRUE)
  # Segmente unter 8 % verlieren ihr Label (Mock-up-Regel)
  expect_match(html, 'class="oh nolabel"', fixed = TRUE)
})

test_that("die ELO-Anpassung erscheint als Heim/Gast-Paar mit echtem Minus", {
  gen <- source_generator()
  html <- gen$render_rueckblick(mk_rueckblick(), runden = c(1L, 2L))

  expect_match(html, "+7,5", fixed = TRUE)
  expect_match(html, "−7,5", fixed = TRUE)   # Gast = Gegenwert
  expect_match(html, "−12,4", fixed = TRUE)
  expect_match(html, "+12,4", fixed = TRUE)
})

test_that("fehlende ELO-Anpassung wird als Strich gezeigt, nie als NA", {
  gen <- source_generator()
  html <- gen$render_rueckblick(mk_rueckblick(), runden = c(1L, 2L))

  expect_false(grepl(">NA<", html, fixed = TRUE))
  expect_false(grepl("NA / NA", html, fixed = TRUE))
  expect_match(html, "–")  # Platzhalter-Strich in der Delta-Spalte
})

test_that("Nachholspiele sind als solche gekennzeichnet", {
  gen <- source_generator()
  html <- gen$render_rueckblick(mk_rueckblick(), runden = c(1L, 2L))

  expect_match(html, 'class="nachhol"', fixed = TRUE)
  expect_match(html, "Nachholspiel, 1. Spieltag", fixed = TRUE)
})

test_that("die Legende erklärt die Balkenfarben", {
  gen <- source_generator()
  html <- gen$render_rueckblick(mk_rueckblick(), runden = c(1L, 2L))

  for (s in c("Sieg Heim", "Remis", "Sieg Gast")) {
    expect_match(html, s, fixed = TRUE)
  }
  expect_match(html, 'class="chip h"', fixed = TRUE)
})

test_that("Teamnamen im Rückblick werden HTML-escaped", {
  gen <- source_generator()
  rb <- mk_rueckblick()[1, ]
  rb$home_name <- "A & B <FC>"
  html <- gen$render_rueckblick(rb, runden = 2L)

  expect_match(html, "A &amp; B &lt;FC&gt;", fixed = TRUE)
  expect_false(grepl("<FC>", html, fixed = TRUE))
})

# --------------------------------------------------------------------- Live --

test_that("render_live berichtet Zwischenstände ohne Prognose", {
  gen <- source_generator()
  html <- gen$render_live(mk_live())

  expect_match(html, "Laufende Spiele", fixed = TRUE)
  expect_match(html, "Prognosen werden während des Spiels nicht aktualisiert",
               fixed = TRUE)
  expect_match(html, ">1:0<")
  expect_match(html, "1. FC Delta", fixed = TRUE)
  expect_false(grepl("oddsbar", html, fixed = TRUE))
})

test_that("ohne laufende Spiele entfällt die Live-Sektion vollständig", {
  gen <- source_generator()
  expect_equal(gen$render_live(mk_live()[0, ]), "")
})

# -------------------------------------------------------------- Integration --

league_entry_4b <- function() {
  list(
    tabelle = data.frame(
      platz = 1, team_id = 1, name = "FC Alpha", spiele = 1, tore = 2,
      gegentore = 1, tordifferenz = 1, punkte = 3, elo = 1507.5,
      delta_elo = 7.5, stringsAsFactors = FALSE
    ),
    rueckblick = mk_rueckblick(),
    live = mk_live(),
    spieltag = list(rueckblick = c(1L, 2L), ausblick = 3L)
  )
}

test_that("die Liga-Seite ordnet Tabelle, Rückblick und Live-Sektion", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  path <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-08-30 19:00:00", tz = "Europe/Berlin"),
    league_entry = league_entry_4b()
  )
  html <- read_html(path)

  pos_tab <- regexpr("Ligatabelle und ELO", html, fixed = TRUE)
  pos_rueck <- regexpr("1./2. Spieltag", html, fixed = TRUE)
  pos_live <- regexpr("Laufende Spiele", html, fixed = TRUE)
  expect_true(pos_tab > 0 && pos_rueck > 0 && pos_live > 0)
  expect_true(pos_tab < pos_rueck)
  expect_true(pos_rueck < pos_live)
})

test_that("ein 4a-Entry ohne Rückblick-Felder rendert wie bisher", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  entry <- league_entry_4b()
  entry$rueckblick <- NULL
  entry$live <- NULL
  entry$spieltag <- NULL

  path <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-08-30 19:00:00", tz = "Europe/Berlin"),
    league_entry = entry
  )
  html <- read_html(path)

  expect_match(html, "Ligatabelle und ELO", fixed = TRUE)
  expect_false(grepl("Spieltag<", html, fixed = TRUE))
  expect_false(grepl("Laufende Spiele", html, fixed = TRUE))
})

test_that("ein leeres Live-Fenster erzeugt keine Live-Sektion auf der Seite", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  entry <- league_entry_4b()
  entry$live <- entry$live[0, ]

  path <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-08-30 19:00:00", tz = "Europe/Berlin"),
    league_entry = entry
  )
  expect_false(grepl("Laufende Spiele", read_html(path), fixed = TRUE))
})
