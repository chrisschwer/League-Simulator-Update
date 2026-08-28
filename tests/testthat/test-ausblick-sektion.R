# Ausblick-Sektion (Phase 4c) nach dem freigegebenen Mock-up: kommende
# Spiele mit Termin, 1/X/2-Balken und aufklappbarer Ergebnis-Matrix.

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

mk_score_matrix <- function() {
  m <- matrix(0, nrow = 7, ncol = 7)
  m[1, 1] <- 0.123   # 0:0 -> "12,3"
  m[2, 3] <- 0.061   # 1:2 -> "6,1"
  m[7, 7] <- 0.0005  # unter 0,1 % -> leere Zelle
  m
}

mk_ausblick <- function() {
  df <- data.frame(
    fixture_id = c(6001, 6002),
    round = c(3L, 1L),
    kickoff = as.POSIXct(c("2026-12-04 19:30", "2026-12-01 17:30"), tz = "UTC"),
    status = "NS",
    home_id = c(102, 103), away_id = c(104, 101),
    home_name = c("SV Beta", "TSV Gamma"),
    away_name = c("1. FC Delta", "FC Alpha"),
    goals_home = NA_real_, goals_away = NA_real_,
    p_home_win = c(0.40, 0.45), p_draw = c(0.26, 0.26),
    p_away_win = c(0.34, 0.29),
    elo_delta_home = NA_real_,
    nachholspiel = c(FALSE, TRUE),
    stringsAsFactors = FALSE
  )
  df$score_matrix <- list(mk_score_matrix(), mk_score_matrix())
  df
}

test_that("render_ausblick baut Überschrift und Spielzeilen", {
  gen <- source_generator()
  html <- gen$render_ausblick(mk_ausblick(), runde = 3L)

  expect_match(html, ">Ausblick<")            # Eyebrow
  expect_match(html, ">3. Spieltag<")
  expect_match(html, "Fr. 4.12., 20:30 Uhr", fixed = TRUE) # Berliner Zeit, U+202F
  expect_match(html, "SV Beta", fixed = TRUE)
  expect_match(html, 'class="oddsbar"', fixed = TRUE)
  expect_match(html, "flex-basis:40%", fixed = TRUE)
  # kommende Spiele haben kein Ergebnis
  expect_false(grepl('class="mres"', html, fixed = TRUE))
})

test_that("die Ergebnis-Matrix ist je Spiel aufklappbar", {
  gen <- source_generator()
  html <- gen$render_ausblick(mk_ausblick(), runde = 3L)

  expect_match(html, '<details class="mscore">', fixed = TRUE)
  expect_match(html, "Ergebnis-Matrix", fixed = TRUE)
  expect_match(html, 'class="score"')
  # Achsenbeschriftung: 0..5 und die Restmassen-Spalte "6+"
  expect_match(html, ">6\\+<")
  expect_match(html, "Heim", fixed = TRUE)
  expect_match(html, "Gast", fixed = TRUE)
})

test_that("Matrixzellen tragen Komma-Prozente mit einer Nachkommastelle", {
  gen <- source_generator()
  html <- gen$render_ausblick(mk_ausblick(), runde = 3L)

  expect_match(html, ">12,3<")
  expect_match(html, ">6,1<")
  # Färbung nach Wahrscheinlichkeit wie in der Heatmap
  expect_match(html, "background:rgb", fixed = TRUE)
})

test_that("Zellen unter 0,1 Prozent bleiben leer", {
  gen <- source_generator()
  html <- gen$render_ausblick(mk_ausblick(), runde = 3L)

  expect_false(grepl(">0,0<", html, fixed = TRUE))
  expect_false(grepl(">0,1<", html, fixed = TRUE)) # 0,0005 wird nicht aufgerundet
})

test_that("Nachholspiele im Ausblick sind gekennzeichnet", {
  gen <- source_generator()
  html <- gen$render_ausblick(mk_ausblick(), runde = 3L)

  expect_match(html, 'class="nachhol"', fixed = TRUE)
  expect_match(html, "Nachholspiel, 1. Spieltag", fixed = TRUE)
})

test_that("Teamnamen im Ausblick werden HTML-escaped", {
  gen <- source_generator()
  ab <- mk_ausblick()[1, ]
  ab$home_name <- "A & B <FC>"
  html <- gen$render_ausblick(ab, runde = 3L)

  expect_match(html, "A &amp; B &lt;FC&gt;", fixed = TRUE)
  expect_false(grepl("<FC>", html, fixed = TRUE))
})

test_that("die Liga-Seite hängt den Ausblick ans Ende der Spielsektionen", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  entry <- list(
    tabelle = data.frame(
      platz = 1, team_id = 1, name = "FC Alpha", spiele = 1, tore = 2,
      gegentore = 1, tordifferenz = 1, punkte = 3, elo = 1507.5,
      delta_elo = 7.5, stringsAsFactors = FALSE
    ),
    rueckblick = data.frame(
      fixture_id = 6000, round = 2L,
      kickoff = as.POSIXct("2026-11-28 14:30", tz = "UTC"), status = "FT",
      home_id = 101, away_id = 102,
      home_name = "FC Alpha", away_name = "SV Beta",
      goals_home = 2, goals_away = 1,
      p_home_win = 0.44, p_draw = 0.26, p_away_win = 0.30,
      elo_delta_home = 7.5, nachholspiel = FALSE,
      stringsAsFactors = FALSE
    ),
    live = NULL,
    ausblick = mk_ausblick(),
    spieltag = list(rueckblick = 2L, ausblick = 3L)
  )

  path <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-12-01 19:00:00", tz = "Europe/Berlin"),
    league_entry = entry
  )
  html <- read_html(path)

  pos_rueck <- regexpr(">2. Spieltag<", html)
  pos_aus <- regexpr(">3. Spieltag<", html)
  expect_true(pos_rueck > 0 && pos_aus > 0)
  expect_true(pos_rueck < pos_aus)
})

test_that("ohne Ausblick-Feld oder mit leerem Fenster entfällt die Sektion", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  entry <- list(tabelle = data.frame(
    platz = 1, team_id = 1, name = "FC Alpha", spiele = 1, tore = 2,
    gegentore = 1, tordifferenz = 1, punkte = 3, elo = 1507.5,
    delta_elo = 7.5, stringsAsFactors = FALSE
  ))

  path <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-12-01 19:00:00", tz = "Europe/Berlin"),
    league_entry = entry
  )
  expect_false(grepl(">Ausblick<", read_html(path)))

  entry$ausblick <- mk_ausblick()[0, ]
  entry$spieltag <- list(rueckblick = integer(0), ausblick = 3L)
  path2 <- gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-12-01 19:00:00", tz = "Europe/Berlin"),
    league_entry = entry
  )
  expect_false(grepl(">Ausblick<", read_html(path2)))
})
