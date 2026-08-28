library(testthat)
source("../../RCode/league_details.R")

# Client für POST /league-details: Payload-Aufbau aus details + TeamList und
# das Parsen der Antwort. Das Antwortformat ist in
# league-simulator-rust/src/api/tests.rs festgepinnt — die hier verwendete
# Beispiel-Antwort muss mit dem dortigen Vertrag übereinstimmen.

client_details <- function() {
  make_details(
    fd_row(1, 1, "2026-08-28 18:30", "FT", 101, 102, 2, 1),
    fd_row(2, 1, "2026-08-29 13:30", "FT", 103, 104, 0, 0),
    fd_row(3, 2, "2026-09-04 18:30", "NS", 102, 103),
    fd_row(4, 2, "2026-09-05 13:30", "1H", 104, 101, 1, 0) # live: Tore zählen nicht
  )
}

test_that("Payload nutzt 1-basierte Teamindizes in TeamList-Reihenfolge", {
  payload <- build_league_details_payload(client_details(), make_test_teams())

  expect_equal(length(payload$schedule), 4)
  # Spiel 1: 101 vs 102 -> Positionen 1 und 2 in der TeamList
  expect_equal(payload$schedule[[1]][[1]], 1)
  expect_equal(payload$schedule[[1]][[2]], 2)
  expect_equal(payload$schedule[[1]][[3]], 2)
  expect_equal(payload$schedule[[1]][[4]], 1)
  # Spiel 2: 103 vs 104 -> Positionen 3 und 4
  expect_equal(payload$schedule[[2]][[1]], 3)
  expect_equal(payload$schedule[[2]][[2]], 4)

  expect_equal(payload$elo_values, make_test_teams()$InitialELO)
  expect_equal(payload$team_names, make_test_teams()$ShortText)
})

test_that("Payload sendet Tore nur für beendete Spiele", {
  payload <- build_league_details_payload(client_details(), make_test_teams())

  # offenes Spiel: null
  expect_null(payload$schedule[[3]][[3]])
  expect_null(payload$schedule[[3]][[4]])
  # laufendes Spiel: Zwischenstand darf NICHT als Ergebnis gesendet werden
  expect_null(payload$schedule[[4]][[3]])
  expect_null(payload$schedule[[4]][[4]])
})

test_that("Payload trägt die Modellparameter mit Defaults", {
  payload <- build_league_details_payload(client_details(), make_test_teams())

  expect_equal(payload$mod_factor, 20)
  expect_equal(payload$home_advantage, 65)
  expect_equal(payload$max_goals, 6)
})

# --- Antwort parsen -----------------------------------------------------------

canned_response <- '{
  "matches": [
    {
      "index": 0, "team_home": 1, "team_away": 2, "played": true,
      "goals_home": 2, "goals_away": 1,
      "elo_home_pre": 1500.0, "elo_away_pre": 1500.0,
      "elo_delta_home": 8.150675388313,
      "lambda_home": 1.437896275893, "lambda_away": 1.205781885027,
      "p_home_win": 0.424217291957, "p_draw": 0.259291821451,
      "p_away_win": 0.316490886592,
      "score_matrix": [[0.25, 0.25], [0.25, 0.25]]
    },
    {
      "index": 1, "team_home": 2, "team_away": 3, "played": false,
      "goals_home": null, "goals_away": null,
      "elo_home_pre": 1491.849324611687, "elo_away_pre": 1500.0,
      "elo_delta_home": null,
      "lambda_home": 1.4, "lambda_away": 1.2,
      "p_home_win": 0.42, "p_draw": 0.26, "p_away_win": 0.32,
      "score_matrix": [[0.3, 0.2], [0.3, 0.2]]
    }
  ],
  "current_elos": [1508.150675388313, 1491.849324611687, 1500.0, 1500.0],
  "team_names": ["AAA", "BBB", "CCC", "DDD"]
}'

test_that("parse_league_details_response liefert ein Data-Frame je Spiel", {
  parsed <- parse_league_details_response(canned_response)

  m <- parsed$matches
  expect_s3_class(m, "data.frame")
  expect_equal(nrow(m), 2)
  expect_equal(m$index, c(0, 1))
  expect_equal(m$team_home, c(1, 2))
  expect_equal(m$played, c(TRUE, FALSE))
  expect_equal(m$goals_home, c(2, NA))
  expect_equal(m$elo_delta_home[1], 8.150675388313, tolerance = 1e-9)
  expect_true(is.na(m$elo_delta_home[2]))
  expect_equal(m$p_home_win[1], 0.424217291957, tolerance = 1e-9)
})

test_that("parse_league_details_response erhält die Score-Matrix als Matrix je Spiel", {
  parsed <- parse_league_details_response(canned_response)

  grids <- parsed$matches$score_matrix
  expect_true(is.list(grids))
  expect_true(is.matrix(grids[[1]]))
  expect_equal(dim(grids[[1]]), c(2, 2))
  # Zeile = Heimtore, Spalte = Auswärtstore
  expect_equal(grids[[2]][1, 2], 0.2)
  expect_equal(grids[[2]][2, 1], 0.3)
})

test_that("parse_league_details_response liefert aktuelle ELOs und Teamnamen", {
  parsed <- parse_league_details_response(canned_response)

  expect_equal(length(parsed$current_elos), 4)
  expect_equal(parsed$current_elos[1], 1508.150675388313, tolerance = 1e-9)
  expect_equal(parsed$team_names, c("AAA", "BBB", "CCC", "DDD"))
})
