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
  # ANGEPASST (#146): Die Antwort folgt jetzt der Reihenfolge des
  # GESENDETEN Payloads statt einer festen Liste.
  #
  # Vorher waren die sechs Eintraege hart in API-Reihenfolge notiert. Das
  # traf zu, solange extract_fixture_details() unsortiert durchreichte --
  # seit der chronologischen Sortierung nicht mehr, und der positionale
  # cbind in build_league_page_data() klebte die Werte an die falschen
  # Zeilen.
  #
  # Der echte Server verhaelt sich so, wie es hier jetzt nachgebildet ist:
  # `index` ist laut league_details/mod.rs:40 "Position im Request-Schedule".
  # Am laufenden Server gegengeprueft, mit einem Payload, dessen fixture_ids
  # absichtlich nicht aufsteigend waren -- die Antwort folgte dem Gesendeten.
  #
  # Damit ist der Mock immun gegen kuenftige Sortieraenderungen: Er
  # antwortet auf das, was tatsaechlich geschickt wurde.
  werte <- list(
    # Schluessel: "team_home-team_away" (1-basierte Team-Indizes)
    "1-2" = list("7.5", "0.44", "0.26", "0.30"),
    "3-4" = list("-1.8", "0.43", "0.26", "0.31"),
    "2-3" = list("2.1", "0.38", "0.27", "0.35"),
    "1-4" = list("null", "0.41", "0.27", "0.32"),
    "2-4" = list("null", "0.40", "0.26", "0.34"),
    "3-1" = list("null", "0.45", "0.26", "0.29")
  )

  function(payload) {
    teile <- vapply(seq_along(payload$schedule), function(i) {
      zeile <- payload$schedule[[i]]
      th <- zeile[[1]]
      ta <- zeile[[2]]
      gh <- zeile[[3]]
      ga <- zeile[[4]]
      gespielt <- !is.null(gh) && !is.na(gh) && !is.null(ga) && !is.na(ga)
      w <- werte[[paste0(th, "-", ta)]]
      eintrag(
        i - 1L, th, ta,
        if (gespielt) "true" else "false",
        if (gespielt) as.character(gh) else "null",
        if (gespielt) as.character(ga) else "null",
        if (gespielt) w[[1]] else "null",
        w[[2]], w[[3]], w[[4]]
      )
    }, character(1))

    paste0(
      '{"matches": [', paste(teile, collapse = ","),
      '], "current_elos": [1505.7, 1481.6, 1518.4, 1494.3],',
      ' "team_names": ["ALP", "BET", "GAM", "DEL"]}'
    )
  }
}

page_data <- function() {
  build_league_page_data(vier_runden_fixtures(), vier_runden_teams(),
                         fetch_fn = vier_runden_response())
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
  # als markiertes Nachholspiel ins Fenster und trägt trotzdem SEINE eigenen
  # Endpoint-Werte, nicht die eines anderen Spiels.
  #
  # ANGEPASST (#146): Vorher stand hier "Endpoint-Werte von Index 1 (Join per
  # Position)" und zwei sub()-Aufrufe, die den Antwort-String umschrieben.
  # Beides hing daran, dass extract_fixture_details() in API-Reihenfolge
  # durchreichte. Seit der chronologischen Sortierung stimmt die feste
  # Index-Zuordnung nicht mehr; der Mock folgt jetzt dem gesendeten Payload
  # (s. vier_runden_response), und die Tore holt er sich von dort -- die
  # sub()-Manipulation ist damit entbehrlich.
  #
  # Die Aussage des Tests ist unverändert: 4002 behält seine Kennzeichnung
  # als Nachholspiel UND seine eigenen Werte.
  fx <- vier_runden_fixtures()
  fx$fixture[[2]] <- data.frame(id = 4002, date = "2026-11-29T17:30:00+00:00",
                                status = I(list(data.frame(short = "FT"))))
  fx$fixture[[4]] <- data.frame(id = 4004, date = "2026-11-28T14:30:00+00:00",
                                status = I(list(data.frame(short = "FT"))))
  fx$goals[[4]] <- data.frame(home = 2, away = 0)

  pd <- build_league_page_data(fx, vier_runden_teams(),
                               fetch_fn = vier_runden_response())

  rb <- pd$rueckblick
  expect_equal(rb$fixture_id, c(4003, 4004, 4002)) # chronologisch ab Runde-2-Beginn
  expect_equal(rb$nachholspiel, c(FALSE, FALSE, TRUE))
  nachzuegler <- rb[rb$fixture_id == 4002, ]
  # 4002 ist Gamma-Delta (Team-Indizes 3-4), sein Wert ist -1.8 -- derselbe
  # wie vor dieser Aenderung. Verrutschte die Zuordnung, staende hier der
  # Wert eines Nachbarn (7.5 fuer 1-2, 2.1 fuer 2-3).
  expect_equal(nachzuegler$elo_delta_home, -1.8)
  expect_equal(nachzuegler$round, 1L)
  expect_equal(pd$spieltag$rueckblick, 2L) # Überschrift ohne Nachholspiel-Runde
})
