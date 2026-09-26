# Helper functions and fixtures for unit tests

# Create a simple test season with 4 teams and 12 games (each team plays 3 games)
create_test_season <- function(games_played = 0) {
  # Season matrix: columns are TeamHome, TeamAway, GoalsHome, GoalsAway
  season <- matrix(NA, nrow = 12, ncol = 4)
  
  # Define match schedule (round-robin subset)
  matches <- list(
    c(1, 2), c(3, 4),  # Round 1
    c(1, 3), c(2, 4),  # Round 2
    c(1, 4), c(2, 3),  # Round 3
    c(2, 1), c(4, 3),  # Round 4
    c(3, 1), c(4, 2),  # Round 5
    c(4, 1), c(3, 2)   # Round 6
  )
  
  for (i in 1:12) {
    season[i, 1:2] <- matches[[i]]
  }
  
  # Fill in results for played games
  if (games_played > 0) {
    results <- list(
      c(2, 1), c(3, 1),  # Round 1: Home wins
      c(1, 1), c(2, 2),  # Round 2: Draw and draw
      c(0, 2), c(1, 0),  # Round 3: Away win and home win
      c(1, 2), c(2, 0),  # Round 4: Away win and home win
      c(2, 1), c(1, 1),  # Round 5: Home win and draw
      c(3, 0), c(0, 1)   # Round 6: Home win and away win
    )
    
    for (i in 1:min(games_played, 12)) {
      season[i, 3:4] <- results[[i]]
    }
  }
  
  return(season)
}

# Create test adjustments
create_test_adjustments <- function(num_teams = 4, type = "none") {
  if (type == "none") {
    return(rep(0, num_teams))
  } else if (type == "points") {
    # Team 1 gets -6 points penalty, team 3 gets +3 bonus
    adj <- rep(0, num_teams)
    adj[1] <- -6
    adj[3] <- 3
    return(adj)
  } else if (type == "goals") {
    # Various goal adjustments
    return(c(2, -1, 0, 1)[1:num_teams])
  } else if (type == "goals_against") {
    # Goals against adjustments
    return(c(-2, 1, 0, -1)[1:num_teams])
  } else if (type == "goal_diff") {
    # Goal difference adjustments
    return(c(1, -2, 3, 0)[1:num_teams])
  }
}

# Create test fixtures for transform_data.R
create_test_fixtures_api <- function() {
  # Create a tibble that mimics the API response structure
  # The key is that each row's columns contain data frames that will be unnested
  fixtures <- tibble::tibble(
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 102, name = "Team B")))
      ),
      data.frame(
        home = I(list(data.frame(id = 103, name = "Team C"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      ),
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 103, name = "Team C")))
      )
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = 1, away = 1),
      data.frame(home = NA, away = NA)  # Use NA instead of NULL for unplayed games
    ),
    fixture = list(
      data.frame(id = 1001, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 1002, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 1003, status = I(list(data.frame(short = "NS"))))
    )
  )
  return(fixtures)
}

# Create test teams data for transform_data.R
create_test_teams_api <- function() {
  # Create a data frame in the format transform_data expects
  teams <- data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("TEA", "TEB", "TEC", "TED"),
    InitialELO = c(1500, 1450, 1550, 1400),
    stringsAsFactors = FALSE
  )
  return(teams)
}

# Helper to create a completed season for table testing
create_completed_season <- function() {
  season <- create_test_season(12)
  # Ensure we have a variety of results for proper table testing
  return(season)
}

# Prognose-Attrappe: gleichverteilte Prognose (1/n je Platz), damit die
# erwarteten Prozentwerte der Panels exakt bekannt sind. Bisher kopiert in
# test-generate_static_site.R und test-rl_abstiegskopplung.R (#211, Stufe 2, T7).
mk_ergebnis <- function(teams) {
  m <- matrix(1 / teams, nrow = teams, ncol = teams,
              dimnames = list(paste0("T", seq_len(teams)),
                              as.character(seq_len(teams))))
  as.table(m)
}

# ELO-Walk-Attrappen: bisher kopiert in test-league_details.R und
# test-transform_data.R (#211, Stufe 2, T7).

# Ein Spiel als Liste der vier List-Column-Bausteine.
ewr_spiel <- function(fixture_id, datum, status, heim_id, gast_id,
                      tore_heim = NA_real_, tore_gast = NA_real_,
                      runde = 1L) {
  list(
    teams = data.frame(
      home = I(list(data.frame(id = heim_id, name = paste("Team", heim_id)))),
      away = I(list(data.frame(id = gast_id, name = paste("Team", gast_id))))
    ),
    goals = data.frame(home = tore_heim, away = tore_gast),
    fixture = data.frame(
      id = fixture_id,
      date = datum,
      status = I(list(data.frame(short = status)))
    ),
    league = data.frame(round = paste("Regular Season -", runde))
  )
}

# Aus mehreren ewr_spiel()-Ergebnissen den fixtures-Tibble bauen, wie ihn
# retrieveResults() liefert.
ewr_fixtures <- function(...) {
  spiele <- list(...)
  tibble::tibble(
    teams   = lapply(spiele, `[[`, "teams"),
    goals   = lapply(spiele, `[[`, "goals"),
    fixture = lapply(spiele, `[[`, "fixture"),
    league  = lapply(spiele, `[[`, "league")
  )
}

# Vier Teams, Kurznamen wie in helper-fixtures.R.
ewr_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("TEA", "TEB", "TEC", "TED"),
    InitialELO = c(1500, 1450, 1550, 1400),
    stringsAsFactors = FALSE
  )
}

# Regionalliga-Testkonstanten: bisher kopiert in test-generate_static_site.R,
# test-league_registry.R, test-league_views.R und test-round_filter.R
# (#211, Stufe 2, T7). RL_SCHLUESSEL bleibt lokal (zwei Fassungen, siehe README).
RL_IDS <- c("84", "85", "87", "86", "83")
RL_SLUGS <- c("rl-nord", "rl-nordost", "rl-west", "rl-suedwest", "rl-bayern")

# Slug der Seite "Aufstieg in die 3. Liga". Steht hier und nicht erst bei
# den Aufstiegstests: testthat wertet Top-Level-Code sequenziell aus, und
# die Navigations- und Seitenzahl-Tests weiter oben brauchen den Wert
# bereits.
AUFSTIEGSSEITE_SLUG <- "rl-aufstieg"

# Die Staffeln mit Direktaufstieg 2026/27 (Par. 55b DFB-SpO Nr. 2 plus der
# Rotationsplatz, den 2026/27 Nordost traegt).
RL_DIREKTAUFSTIEG <- c("rl_nordost", "rl_west", "rl_suedwest")
# Nord und Bayern spielen stattdessen zwei Aufstiegsspiele gegeneinander.
RL_AUFSTIEGSSPIELE <- c("rl_nord", "rl_bayern")

