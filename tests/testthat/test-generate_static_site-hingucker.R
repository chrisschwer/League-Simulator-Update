library(testthat)

# Die Seite "Hingucker der Woche" im Generator: Navigation, Dateibestand,
# Auswahl der fuenf Spiele und Darstellung.

gsh_jetzt <- as.POSIXct("2026-10-31 12:00:00", tz = "Europe/Berlin")

# Eine Bundesliga mit `n` offenen Spielen T1-T2, T3-T4, ... im Fenster.
gsh_league_data <- function(n = 8L) {
  stopifnot(n <= 9L)
  heim <- seq(1L, by = 2L, length.out = n)
  m <- data.frame(
    fixture_id = seq_len(n), round = 10L,
    kickoff = as.POSIXct("2026-11-01 14:30", tz = "UTC") + 3600 * seq_len(n),
    status = "NS", zeit_offen = FALSE, nachholspiel = FALSE,
    home_id = heim, away_id = heim + 1L,
    home_name = paste("Team", heim), away_name = paste("Team", heim + 1L),
    p_home_win = 0.4, p_draw = 0.3, p_away_win = 0.3,
    stringsAsFactors = FALSE
  )
  m$score_matrix <- rep(list(matrix(1 / 49, 7, 7)), n)
  list(bundesliga = list(
    matches = m,
    teams = data.frame(TeamID = 1:18, ShortText = paste0("T", 1:18),
                       stringsAsFactors = FALSE),
    tabelle = data.frame(
      platz = 1:18, team_id = 1:18, spiele = 9L, tore = 10L, gegentore = 10L,
      tordifferenz = 0L, punkte = 10L, name = paste("Team", 1:18),
      kuerzel = paste0("T", 1:18), elo = 1500, delta_elo = 0,
      stringsAsFactors = FALSE
    )
  ))
}

# Ein Zyklus in `out`; Rueckgabe: Seite "hingucker" als Text.
gsh_zyklus <- function(out, league_data, now = gsh_jetzt) {
  gen <- source_module("generate_static_site")
  # Die schmale Fixture traegt keine Verlaufsdaten; die Warnung der
  # Verlaufsseite gehoert nicht zu diesen Tests.
  withCallingHandlers(
    suppressMessages(gen$generate_static_site(
      ergebnisse = ergebnisse_aus_env(make_data_env()), output_dir = out,
      now = now, league_data = league_data
    )),
    warning = function(w) {
      if (grepl("kein ELO-Verlauf", conditionMessage(w), fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
  html_lesen(file.path(out, "hingucker.html"))
}

test_that("die Hingucker-Seite zeigt die fuenf besten von mehr Spielen im Fenster", {
  out <- withr::local_tempdir()

  html <- gsh_zyklus(out, gsh_league_data(8L))

  expect_equal(lengths(regmatches(html, gregexpr('<article class="hingucker-spiel">', html))), 5)
  expect_match(html, "Die 5 spannendsten Spiele", fixed = TRUE)
  expect_match(html, "31.10. – 6.11.", fixed = TRUE)
  expect_match(html, 'class="oddsbar"', fixed = TRUE)
  expect_match(html, 'class="hg-einsatz"', fixed = TRUE)
  expect_match(html, "Wie der Hingucker-Wert entsteht", fixed = TRUE)
})

test_that("jedes Team nennt, worum es geht", {
  out <- withr::local_tempdir()

  html <- gsh_zyklus(out, gsh_league_data(1L))

  expect_match(html, "<strong>Team 1</strong>", fixed = TRUE)
  expect_match(html, "Platz 1", fixed = TRUE)
  # Bundesliga-Gleichverteilung: Meister 1/18 = 6 %, CL 3/18 = 17 %.
  expect_match(html, "Meister <b>6", fixed = TRUE)
  expect_match(html, "Champions League <b>17", fixed = TRUE)
  expect_match(html, "Abstieg <b>11", fixed = TRUE)
  expect_match(html, "Das spannendste Spiel", fixed = TRUE)
})

test_that("ohne league_data entsteht die Seite trotzdem, mit Leermeldung", {
  out <- withr::local_tempdir()

  html <- gsh_zyklus(out, NULL)

  expect_match(html, "Keine Spiele im Blick", fixed = TRUE)
  expect_false(grepl('class="hingucker-spiel"', html, fixed = TRUE))
  # Die Seite traegt Navigation und Zeitstempel wie jede andere.
  expect_match(html, '<nav aria-label="Ligen">', fixed = TRUE)
  expect_match(html, '<time id="generated"', fixed = TRUE)
})

test_that("die Navigation verlinkt Hingucker neben Methodik und markiert die aktuelle Seite", {
  out <- withr::local_tempdir()

  html <- gsh_zyklus(out, gsh_league_data(1L))

  expect_match(html, '<a class="nav-current" aria-current="page" href="hingucker.html">Hingucker</a>',
               fixed = TRUE)
  expect_match(html, '<a href="methodik.html">Methodik</a>', fixed = TRUE)
  # Auch Seiten anderer Art verlinken sie.
  expect_match(html_lesen(file.path(out, "methodik.html")),
               '<a href="hingucker.html">Hingucker</a>', fixed = TRUE)
})

test_that("ein zweiter Zyklus loescht die Hingucker-Seite nicht als registryfremd", {
  out <- withr::local_tempdir()
  gsh_zyklus(out, gsh_league_data(1L))
  expect_true(file.exists(file.path(out, "hingucker.html")))

  gsh_zyklus(out, gsh_league_data(1L), now = gsh_jetzt + 3600)

  expect_true(file.exists(file.path(out, "hingucker.html")))
})

test_that("scheitert die Auswahl als Ganzes, entsteht die Seite mit Hinweis statt eines 404", {
  gen <- source_module("generate_static_site")
  gen$hingucker_kandidaten <- function(...) stop("kaputt")
  out <- withr::local_tempdir()

  expect_warning(
    suppressMessages(gen$generate_static_site(
      ergebnisse = ergebnisse_aus_env(make_data_env()), output_dir = out,
      now = gsh_jetzt, league_data = NULL
    )),
    "Hingucker-Auswahl gescheitert"
  )

  html <- html_lesen(file.path(out, "hingucker.html"))
  expect_match(html, "Auswahl derzeit nicht verfügbar", fixed = TRUE)
  expect_match(html, '<nav aria-label="Ligen">', fixed = TRUE)
})
