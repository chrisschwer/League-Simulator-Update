library(testthat)
source("../../RCode/league_details.R")

# Phase 4b: build_league_page_data() liefert zusätzlich die gefensterten,
# mit Endpoint-Werten gejointen Spiellisten für Rückblick und Live-Sektion
# sowie die Spieltagsnummern für die Überschriften. Die Fensterlogik selbst
# ist in der eingefrorenen Phase-2-Suite gepinnt — hier geht es um die
# Integration: Join-Integrität nach der Fensterung und die neuen Felder.

# 4 Teams, 3 Runden: Runde 1 komplett (2 FT), Runde 2 laufend (1 FT, 1 live),
# Runde 3 offen (2 NS). Kickoffs chronologisch.
vier_runden_fixtures <- function() {
  mk_fix <- function(id, date, status) {
    data.frame(id = id, date = date, status = I(list(data.frame(short = status))))
  }
  mk_teams <- function(hid, hname, aid, aname) {
    data.frame(home = I(list(data.frame(id = hid, name = hname))),
               away = I(list(data.frame(id = aid, name = aname))))
  }
  tibble::tibble(
    fixture = list(
      mk_fix(4001, "2026-11-20T19:30:00+00:00", "FT"),
      mk_fix(4002, "2026-11-21T14:30:00+00:00", "FT"),
      mk_fix(4003, "2026-11-27T19:30:00+00:00", "FT"),
      mk_fix(4004, "2026-11-28T14:30:00+00:00", "1H"),
      mk_fix(4005, "2026-12-04T19:30:00+00:00", "NS"),
      mk_fix(4006, "2026-12-05T14:30:00+00:00", "NS")
    ),
    league = list(
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 2"),
      data.frame(round = "Regular Season - 2"),
      data.frame(round = "Regular Season - 3"),
      data.frame(round = "Regular Season - 3")
    ),
    teams = list(
      mk_teams(101, "FC Alpha", 102, "SV Beta"),
      mk_teams(103, "TSV Gamma", 104, "1. FC Delta"),
      mk_teams(102, "SV Beta", 103, "TSV Gamma"),
      mk_teams(101, "FC Alpha", 104, "1. FC Delta"),
      mk_teams(102, "SV Beta", 104, "1. FC Delta"),
      mk_teams(103, "TSV Gamma", 101, "FC Alpha")
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = 0, away = 0),
      data.frame(home = 1, away = 1),
      data.frame(home = 1, away = 0),   # Live-Zwischenstand
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    )
  )
}

vier_runden_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("ALP", "BET", "GAM", "DEL"),
    Promotion = c(0, 0, 0, 0),
    InitialELO = c(1500, 1480, 1520, 1500),
    stringsAsFactors = FALSE
  )
}

# Antwort mit 6 Spielen (Indizes 0..5); das Live-Spiel (Index 3) geht ohne
# Tore in den Payload und kommt als ungespielt zurück.
vier_runden_response <- function() {
  eintrag <- function(index, th, ta, played, gh, ga, delta, ph, px, pa) {
    sprintf(paste0(
      '{"index": %d, "team_home": %d, "team_away": %d, "played": %s,',
      ' "goals_home": %s, "goals_away": %s,',
      ' "elo_home_pre": 1500.0, "elo_away_pre": 1500.0,',
      ' "elo_delta_home": %s,',
      ' "lambda_home": 1.4, "lambda_away": 1.2,',
      ' "p_home_win": %s, "p_draw": %s, "p_away_win": %s,',
      ' "score_matrix": [[0.5, 0.5], [0.0, 0.0]]}'
    ), index, th, ta, played, gh, ga, delta, ph, px, pa)
  }
  paste0(
    '{"matches": [',
    eintrag(0, 1, 2, "true", "2", "1", "7.5", "0.44", "0.26", "0.30"), ",",
    eintrag(1, 3, 4, "true", "0", "0", "-1.8", "0.43", "0.26", "0.31"), ",",
    eintrag(2, 2, 3, "true", "1", "1", "2.1", "0.38", "0.27", "0.35"), ",",
    eintrag(3, 1, 4, "false", "null", "null", "null", "0.41", "0.27", "0.32"), ",",
    eintrag(4, 2, 4, "false", "null", "null", "null", "0.40", "0.26", "0.34"), ",",
    eintrag(5, 3, 1, "false", "null", "null", "null", "0.45", "0.26", "0.29"),
    '], "current_elos": [1505.7, 1481.6, 1518.4, 1494.3],',
    ' "team_names": ["ALP", "BET", "GAM", "DEL"]}'
  )
}

page_data <- function() {
  build_league_page_data(vier_runden_fixtures(), vier_runden_teams(),
                         fetch_fn = function(...) vier_runden_response())
}

test_that("rueckblick enthält die gefensterten Spiele mit Endpoint-Werten", {
  pd <- page_data()

  rb <- pd$rueckblick
  expect_equal(rb$fixture_id, c(4001, 4002, 4003)) # chronologisch, ohne Live
  expect_equal(rb$p_home_win, c(0.44, 0.43, 0.38)) # ex-ante aus der Antwort
  expect_equal(rb$elo_delta_home, c(7.5, -1.8, 2.1))
  expect_equal(rb$nachholspiel, c(FALSE, FALSE, FALSE))
  expect_true(all(c("home_name", "away_name", "kickoff", "goals_home",
                    "goals_away", "round") %in% names(rb)))
})

test_that("live enthält das laufende Spiel mit Zwischenstand", {
  pd <- page_data()

  lv <- pd$live
  expect_equal(lv$fixture_id, 4004)
  expect_equal(lv$goals_home, 1)
  expect_equal(lv$goals_away, 0)
  expect_equal(lv$home_name, "FC Alpha")
})

test_that("spieltag nennt die Runden für Rückblick-Überschrift und Ausblick-Ziel", {
  pd <- page_data()

  expect_equal(pd$spieltag$rueckblick, c(1L, 2L))
  expect_equal(pd$spieltag$ausblick, 3L)
})

test_that("ein gespieltes Nachholspiel behält seine Kennzeichnung nach dem Join", {
  # Spiel 4002 (Runde 1) ist auf den 29.11. verlegt und nachgeholt; Runde 2
  # ist komplett abgeschlossen (4004 jetzt FT). Anker = Runde 2 -> 4002 fällt
  # als markiertes Nachholspiel ins Fenster und trägt trotzdem seine
  # Endpoint-Werte von Index 1 (Join per Position, nicht Fenster-Reihenfolge).
  fx <- vier_runden_fixtures()
  fx$fixture[[2]] <- data.frame(id = 4002, date = "2026-11-29T17:30:00+00:00",
                                status = I(list(data.frame(short = "FT"))))
  fx$fixture[[4]] <- data.frame(id = 4004, date = "2026-11-28T14:30:00+00:00",
                                status = I(list(data.frame(short = "FT"))))
  fx$goals[[4]] <- data.frame(home = 2, away = 0)

  antwort <- sub('"index": 3, "team_home": 1, "team_away": 4, "played": false, "goals_home": null, "goals_away": null,',
                 '"index": 3, "team_home": 1, "team_away": 4, "played": true, "goals_home": 2, "goals_away": 0,',
                 vier_runden_response(), fixed = TRUE)
  antwort <- sub('"elo_home_pre": 1500.0, "elo_away_pre": 1500.0, "elo_delta_home": null, "lambda_home": 1.4, "lambda_away": 1.2, "p_home_win": 0.41',
                 '"elo_home_pre": 1500.0, "elo_away_pre": 1500.0, "elo_delta_home": 3.3, "lambda_home": 1.4, "lambda_away": 1.2, "p_home_win": 0.41',
                 antwort, fixed = TRUE)

  pd <- build_league_page_data(fx, vier_runden_teams(),
                               fetch_fn = function(...) antwort)

  rb <- pd$rueckblick
  expect_equal(rb$fixture_id, c(4003, 4004, 4002)) # chronologisch ab Runde-2-Beginn
  expect_equal(rb$nachholspiel, c(FALSE, FALSE, TRUE))
  nachzuegler <- rb[rb$fixture_id == 4002, ]
  expect_equal(nachzuegler$elo_delta_home, -1.8) # Wert von Index 1, nicht verrutscht
  expect_equal(nachzuegler$round, 1L)
  expect_equal(pd$spieltag$rueckblick, 2L) # Überschrift ohne Nachholspiel-Runde
})
