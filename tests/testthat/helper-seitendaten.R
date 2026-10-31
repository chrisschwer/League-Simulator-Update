# Rohdaten fuer build_league_page_data(): geschachtelte api-football-Fixtures,
# TeamList mit Fremdliga und die dazu passende Endpoint-Antwort.

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
