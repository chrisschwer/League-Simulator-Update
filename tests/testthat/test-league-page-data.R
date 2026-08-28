library(testthat)
source("../../RCode/league_details.R")

# build_league_page_data(): die Phase-4a-Verdrahtung. Nimmt die rohen
# api-football-Fixtures einer Liga plus die (ligaübergreifende) TeamList,
# holt die Spieldetails vom Rust-Endpoint (injizierbar über fetch_fn) und
# liefert render-fertige Strukturen. Schlägt der Endpoint fehl, kommt NULL
# mit Warnung zurück — die Seite degradiert dann auf den Phase-3-Stand.

nested_league_fixtures <- function() {
  tibble::tibble(
    fixture = list(
      data.frame(
        id = 2001, date = "2026-08-28T18:30:00+00:00",
        status = I(list(data.frame(short = "FT")))
      ),
      data.frame(
        id = 2002, date = "2026-08-29T13:30:00+00:00",
        status = I(list(data.frame(short = "FT")))
      ),
      data.frame(
        id = 2003, date = "2026-09-04T18:30:00+00:00",
        status = I(list(data.frame(short = "NS")))
      )
    ),
    league = list(
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 2")
    ),
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "FC Alpha"))),
        away = I(list(data.frame(id = 102, name = "SV Beta")))
      ),
      data.frame(
        home = I(list(data.frame(id = 103, name = "TSV Gamma"))),
        away = I(list(data.frame(id = 104, name = "1. FC Delta")))
      ),
      data.frame(
        home = I(list(data.frame(id = 102, name = "SV Beta"))),
        away = I(list(data.frame(id = 103, name = "TSV Gamma")))
      )
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = 0, away = 0),
      data.frame(home = NA, away = NA)
    )
  )
}

# TeamList wie in Produktion: enthält auch Teams ANDERER Ligen, die
# herausgefiltert werden müssen.
teamlist_all_leagues <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104, 999),
    ShortText = c("ALP", "BET", "GAM", "DEL", "XXX"),
    Promotion = c(0, 0, 0, 0, 0),
    InitialELO = c(1500, 1480, 1520, 1500, 1700),
    stringsAsFactors = FALSE
  )
}

# Antwort des Endpoints, passend zu den drei Spielen oben (Indizes 0..2,
# Teamindizes 1-basiert in TeamList-Reihenfolge der LIGA-Teams 101..104).
canned_page_response <- function() {
  paste0('{
    "matches": [
      {"index": 0, "team_home": 1, "team_away": 2, "played": true,
       "goals_home": 2, "goals_away": 1,
       "elo_home_pre": 1500.0, "elo_away_pre": 1480.0,
       "elo_delta_home": 7.5,
       "lambda_home": 1.45, "lambda_away": 1.2,
       "p_home_win": 0.44, "p_draw": 0.26, "p_away_win": 0.30,
       "score_matrix": [[0.5, 0.5], [0.0, 0.0]]},
      {"index": 1, "team_home": 3, "team_away": 4, "played": true,
       "goals_home": 0, "goals_away": 0,
       "elo_home_pre": 1520.0, "elo_away_pre": 1500.0,
       "elo_delta_home": -1.8,
       "lambda_home": 1.4, "lambda_away": 1.25,
       "p_home_win": 0.43, "p_draw": 0.26, "p_away_win": 0.31,
       "score_matrix": [[0.5, 0.5], [0.0, 0.0]]},
      {"index": 2, "team_home": 2, "team_away": 3, "played": false,
       "goals_home": null, "goals_away": null,
       "elo_home_pre": 1487.5, "elo_away_pre": 1518.2,
       "elo_delta_home": null,
       "lambda_home": 1.3, "lambda_away": 1.35,
       "p_home_win": 0.38, "p_draw": 0.27, "p_away_win": 0.35,
       "score_matrix": [[0.4, 0.6], [0.0, 0.0]]}
    ],
    "current_elos": [1507.5, 1485.7, 1516.4, 1501.8],
    "team_names": ["ALP", "BET", "GAM", "DEL"]
  }')
}

test_that("build_league_page_data liefert render-fertige Strukturen", {
  captured_payload <- NULL
  fetch_stub <- function(payload, ...) {
    captured_payload <<- payload
    canned_page_response()
  }

  pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                               fetch_fn = fetch_stub)

  expect_type(pd, "list")
  expect_true(all(c("details", "teams", "matches", "current_elos", "tabelle")
                  %in% names(pd)))

  # Teams sind auf die Liga gefiltert (999/XXX fliegt raus), Reihenfolge
  # bleibt TeamList-Reihenfolge — darauf beruhen die 1-basierten Indizes.
  expect_equal(pd$teams$TeamID, c(101, 102, 103, 104))
  expect_equal(captured_payload$elo_values, c(1500, 1480, 1520, 1500))
  expect_length(captured_payload$schedule, 3)
})

test_that("matches joint Details und Endpoint-Antwort positionsgleich", {
  pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                               fetch_fn = function(...) canned_page_response())

  m <- pd$matches
  expect_equal(nrow(m), 3)
  # Zeile 1 = fixture 2001 = Response-Index 0
  expect_equal(m$fixture_id, c(2001, 2002, 2003))
  expect_equal(m$p_home_win, c(0.44, 0.43, 0.38))
  expect_equal(m$elo_delta_home[1], 7.5)
  expect_true(is.na(m$elo_delta_home[3]))
  expect_equal(m$played, c(TRUE, TRUE, FALSE))
  # Fixture-Spalten bleiben erhalten (fürs Rendering)
  expect_true(all(c("round", "kickoff", "status", "home_name", "away_name")
                  %in% names(m)))
  expect_true(is.list(m$score_matrix))
})

test_that("tabelle ist mit Namen, ELO und Delta angereichert und sortiert", {
  pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                               fetch_fn = function(...) canned_page_response())

  tab <- pd$tabelle
  expect_true(all(c("platz", "team_id", "name", "spiele", "tore", "gegentore",
                    "tordifferenz", "punkte", "elo", "delta_elo")
                  %in% names(tab)))
  expect_equal(tab$platz, seq_len(nrow(tab)))

  # Nach 2:1 (Alpha) und 0:0 (Gamma/Delta): Alpha 3 Pkt, Gamma/Delta 1, Beta 0.
  expect_equal(tab$team_id[1], 101)
  expect_equal(tab$name[1], "FC Alpha")
  expect_equal(tab$punkte[1], 3)

  # ELO aus current_elos (TeamList-Reihenfolge), Delta gegen InitialELO.
  reihe_alpha <- tab[tab$team_id == 101, ]
  expect_equal(reihe_alpha$elo, 1507.5)
  expect_equal(reihe_alpha$delta_elo, 7.5)
  reihe_beta <- tab[tab$team_id == 102, ]
  expect_equal(reihe_beta$elo, 1485.7)
  expect_equal(reihe_beta$delta_elo, 1485.7 - 1480)
})

test_that("ein Endpoint-Fehler degradiert zu NULL mit Warnung", {
  expect_warning(
    pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                                 fetch_fn = function(...) stop("connection refused")),
    "connection refused"
  )
  expect_null(pd)
})

test_that("fetch_league_details existiert als httr-Client mit RUST_API_URL-Default", {
  # Nur Signatur-/Existenzprüfung — der HTTP-Weg selbst wird nicht getestet,
  # build_league_page_data injiziert ihn als Default.
  expect_true(is.function(fetch_league_details))
  expect_true(all(c("payload") %in% names(formals(fetch_league_details))))
})
