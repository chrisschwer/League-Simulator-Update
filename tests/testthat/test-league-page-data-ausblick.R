library(testthat)
source("../../RCode/league_details.R")

# Phase 4c: build_league_page_data() liefert zusätzlich das Ausblick-Fenster
# (offene, nicht verschobene Spiele des Ziel-Spieltags plus früher angesetzte
# Nachholspiele), positionsgleich mit den Endpoint-Werten gejoint — inklusive
# der Score-Matrix je Spiel.

ausblick_fixtures <- function(spiel2_datum = "2026-11-21T14:30:00+00:00",
                              spiel2_status = "FT") {
  mk_fix <- function(id, date, status) {
    data.frame(id = id, date = date, status = I(list(data.frame(short = status))))
  }
  mk_teams <- function(hid, hname, aid, aname) {
    data.frame(home = I(list(data.frame(id = hid, name = hname))),
               away = I(list(data.frame(id = aid, name = aname))))
  }
  tibble::tibble(
    fixture = list(
      mk_fix(5001, "2026-11-20T19:30:00+00:00", "FT"),
      mk_fix(5002, spiel2_datum, spiel2_status),
      mk_fix(5003, "2026-11-27T19:30:00+00:00", "FT"),
      mk_fix(5004, "2026-11-28T14:30:00+00:00", "FT"),
      mk_fix(5005, "2026-12-04T19:30:00+00:00", "NS"),
      mk_fix(5006, "2026-12-05T14:30:00+00:00", "NS")
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
      if (spiel2_status == "FT") data.frame(home = 0, away = 0)
      else data.frame(home = NA, away = NA),
      data.frame(home = 1, away = 1),
      data.frame(home = 2, away = 0),
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    )
  )
}

ausblick_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("ALP", "BET", "GAM", "DEL"),
    Promotion = c(0, 0, 0, 0),
    InitialELO = c(1500, 1480, 1520, 1500),
    stringsAsFactors = FALSE
  )
}

ausblick_response <- function() {
  eintrag <- function(index, th, ta, played, gh, ga, delta, ph, px, pa, m11) {
    sprintf(paste0(
      '{"index": %d, "team_home": %d, "team_away": %d, "played": %s,',
      ' "goals_home": %s, "goals_away": %s,',
      ' "elo_home_pre": 1500.0, "elo_away_pre": 1500.0,',
      ' "elo_delta_home": %s,',
      ' "lambda_home": 1.4, "lambda_away": 1.2,',
      ' "p_home_win": %s, "p_draw": %s, "p_away_win": %s,',
      ' "score_matrix": [[%s, 0.5], [0.0, 0.0]]}'
    ), index, th, ta, played, gh, ga, delta, ph, px, pa, m11)
  }
  paste0(
    '{"matches": [',
    eintrag(0, 1, 2, "true", "2", "1", "7.5", "0.44", "0.26", "0.30", "0.5"), ",",
    eintrag(1, 3, 4, "false", "null", "null", "null", "0.43", "0.26", "0.31", "0.5"), ",",
    eintrag(2, 2, 3, "true", "1", "1", "2.1", "0.38", "0.27", "0.35", "0.5"), ",",
    eintrag(3, 1, 4, "true", "2", "0", "3.3", "0.41", "0.27", "0.32", "0.5"), ",",
    eintrag(4, 2, 4, "false", "null", "null", "null", "0.40", "0.26", "0.34", "0.123"), ",",
    eintrag(5, 3, 1, "false", "null", "null", "null", "0.45", "0.26", "0.29", "0.456"),
    '], "current_elos": [1505.7, 1481.6, 1518.4, 1494.3],',
    ' "team_names": ["ALP", "BET", "GAM", "DEL"]}'
  )
}

test_that("ausblick enthält den nächsten Spieltag mit Endpoint-Werten", {
  pd <- build_league_page_data(ausblick_fixtures(), ausblick_teams(),
                               fetch_fn = function(...) ausblick_response())

  ab <- pd$ausblick
  expect_equal(ab$fixture_id, c(5005, 5006)) # chronologisch
  expect_equal(ab$p_home_win, c(0.40, 0.45))
  expect_equal(ab$nachholspiel, c(FALSE, FALSE))
  expect_true(is.list(ab$score_matrix))
  expect_equal(ab$score_matrix[[1]][1, 1], 0.123)
  expect_equal(ab$score_matrix[[2]][1, 1], 0.456)
  expect_equal(pd$spieltag$ausblick, 3L)
})

test_that("ein früher angesetztes Nachholspiel steht markiert im Ausblick", {
  # Spiel 5002 (Runde 1) ist verschoben und neu angesetzt auf den 1.12. —
  # vor dem Ende des Ziel-Spieltags 3. Es gehört markiert in den Ausblick,
  # mit seinen eigenen Endpoint-Werten (Index 1).
  pd <- build_league_page_data(
    ausblick_fixtures(spiel2_datum = "2026-12-01T17:30:00+00:00",
                      spiel2_status = "NS"),
    ausblick_teams(),
    fetch_fn = function(...) ausblick_response()
  )

  ab <- pd$ausblick
  expect_equal(ab$fixture_id, c(5002, 5005, 5006))
  expect_equal(ab$nachholspiel, c(TRUE, FALSE, FALSE))
  expect_equal(ab$p_home_win[1], 0.43) # Index 1, nicht verrutscht
  expect_equal(pd$spieltag$ausblick, 3L)
})
