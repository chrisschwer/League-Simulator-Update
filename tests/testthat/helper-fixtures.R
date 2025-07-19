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

# Create test ELO values for teams
create_test_elo_values <- function(num_teams = 4) {
  # Different ELO values to test various scenarios
  elo_values <- c(1500, 1450, 1550, 1400)
  return(elo_values[1:num_teams])
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

# Helper to compare matrices with tolerance for floating point
expect_matrix_equal <- function(actual, expected, tolerance = 1e-6) {
  expect_equal(dim(actual), dim(expected))
  expect_true(all(abs(actual - expected) < tolerance | (is.na(actual) & is.na(expected))))
}

# Helper to create a completed season for table testing
create_completed_season <- function() {
  season <- create_test_season(12)
  # Ensure we have a variety of results for proper table testing
  return(season)
}

# Calculate expected points manually for verification
calculate_expected_points <- function(season, team_id) {
  points <- 0
  games <- 0
  
  for (i in 1:nrow(season)) {
    if (!is.na(season[i, 3]) && !is.na(season[i, 4])) {
      if (season[i, 1] == team_id) {
        games <- games + 1
        if (season[i, 3] > season[i, 4]) points <- points + 3
        else if (season[i, 3] == season[i, 4]) points <- points + 1
      } else if (season[i, 2] == team_id) {
        games <- games + 1
        if (season[i, 4] > season[i, 3]) points <- points + 3
        else if (season[i, 3] == season[i, 4]) points <- points + 1
      }
    }
  }
  
  return(list(points = points, games = games))
}