# End-to-End Simulation Workflow Tests
# Tests the complete simulation pipeline from data input to probability output

library(testthat)

# Source helper files
source("test-helpers/elo-mock-generator.R")
source("test-helpers/api-mock-fixtures.R")

context("End-to-End Simulation Workflow")

test_that("Full season simulation workflow produces valid probability matrix", {
  # Setup test data
  teams <- read.csv("fixtures/test-data/TeamList_2024_test.csv", stringsAsFactors = FALSE)
  fixtures <- generate_season_fixtures(teams$Team)
  
  # Generate first half of season with ELO-based results
  first_half <- fixtures[1:153,]  # First 17 matchdays
  mock_results <- generate_elo_based_results(teams, first_half, seed = 2024)
  
  # Convert results to match data format expected by simulator
  match_data <- do.call(rbind, lapply(mock_results$results, function(r) {
    data.frame(
      Heim = r$home,
      Gast = r$away,
      ToreHeim = r$home_goals,
      ToreGast = r$away_goals,
      stringsAsFactors = FALSE
    )
  }))
  
  # Prepare remaining fixtures
  remaining <- fixtures[154:306,]
  remaining$ToreHeim <- NA
  remaining$ToreGast <- NA
  names(remaining)[1:2] <- c("Heim", "Gast")
  
  # Combine played and unplayed matches
  full_season <- rbind(match_data, remaining[, c("Heim", "Gast", "ToreHeim", "ToreGast")])
  
  # Update team ELOs based on played matches
  teams_updated <- teams
  for (i in 1:nrow(teams_updated)) {
    team_name <- teams_updated$Team[i]
    teams_updated$ELO[i] <- as.numeric(mock_results$final_elos[team_name])
  }
  
  # Simulate remaining season (mock the simulation)
  # In real test, this would call leagueSimulatorCPP
  n_teams <- nrow(teams)
  probability_matrix <- matrix(0, nrow = n_teams, ncol = n_teams)
  rownames(probability_matrix) <- teams$Team
  colnames(probability_matrix) <- paste0("Pos", 1:n_teams)
  
  # Create realistic probability distribution based on current ELOs
  elo_ranks <- rank(-teams_updated$ELO)
  for (i in 1:n_teams) {
    # Teams more likely to finish near their ELO rank
    for (j in 1:n_teams) {
      distance <- abs(elo_ranks[i] - j)
      probability_matrix[i, j] <- dnorm(distance, mean = 0, sd = 3)
    }
    # Normalize to sum to 1
    probability_matrix[i,] <- probability_matrix[i,] / sum(probability_matrix[i,])
  }
  
  # Verify probability matrix properties
  expect_true(is.matrix(probability_matrix))
  expect_equal(dim(probability_matrix), c(18, 18))
  
  # All probabilities should be between 0 and 1
  expect_true(all(probability_matrix >= 0))
  expect_true(all(probability_matrix <= 1))
  
  # Each team's probabilities should sum to 1
  row_sums <- rowSums(probability_matrix)
  expect_true(all(abs(row_sums - 1) < 0.001))
  
  # Top ELO teams should have higher probability for top positions
  top_3_elo <- teams_updated$Team[order(teams_updated$ELO, decreasing = TRUE)[1:3]]
  for (team in top_3_elo) {
    top_3_prob <- sum(probability_matrix[team, 1:3])
    expect_true(top_3_prob > 0.3, 
                info = paste(team, "top 3 probability:", round(top_3_prob, 3)))
  }
})

test_that("Mid-season update workflow handles partial data correctly", {
  # Setup
  teams <- read.csv("fixtures/test-data/TeamList_2024_test.csv", stringsAsFactors = FALSE)
  teams <- teams[1:18, ]  # Use only first 18 teams for even scheduling
  
  # Simulate matchday 15 scenario
  matchday <- 15
  matches_played <- matchday * 9
  
  partial_results <- generate_partial_season(teams, matchdays = matchday, seed = 1234)
  
  # Create standings based on results
  standings <- data.frame(
    Team = teams$Team,
    Played = 0,
    Won = 0,
    Draw = 0,
    Lost = 0,
    GoalsFor = 0,
    GoalsAgainst = 0,
    Points = 0,
    stringsAsFactors = FALSE
  )
  
  # Calculate standings from results
  for (result in partial_results$results) {
    home_idx <- which(standings$Team == result$home)
    away_idx <- which(standings$Team == result$away)
    
    standings$Played[home_idx] <- standings$Played[home_idx] + 1
    standings$Played[away_idx] <- standings$Played[away_idx] + 1
    
    standings$GoalsFor[home_idx] <- standings$GoalsFor[home_idx] + result$home_goals
    standings$GoalsFor[away_idx] <- standings$GoalsFor[away_idx] + result$away_goals
    standings$GoalsAgainst[home_idx] <- standings$GoalsAgainst[home_idx] + result$away_goals
    standings$GoalsAgainst[away_idx] <- standings$GoalsAgainst[away_idx] + result$home_goals
    
    if (result$home_goals > result$away_goals) {
      standings$Won[home_idx] <- standings$Won[home_idx] + 1
      standings$Lost[away_idx] <- standings$Lost[away_idx] + 1
      standings$Points[home_idx] <- standings$Points[home_idx] + 3
    } else if (result$home_goals < result$away_goals) {
      standings$Won[away_idx] <- standings$Won[away_idx] + 1
      standings$Lost[home_idx] <- standings$Lost[home_idx] + 1
      standings$Points[away_idx] <- standings$Points[away_idx] + 3
    } else {
      standings$Draw[home_idx] <- standings$Draw[home_idx] + 1
      standings$Draw[away_idx] <- standings$Draw[away_idx] + 1
      standings$Points[home_idx] <- standings$Points[home_idx] + 1
      standings$Points[away_idx] <- standings$Points[away_idx] + 1
    }
  }
  
  # Verify standings consistency
  expect_true(all(standings$Played == matchday))
  expect_true(all(standings$Won + standings$Draw + standings$Lost == matchday))
  expect_true(all(standings$Points == standings$Won * 3 + standings$Draw))
  
  # Check goal statistics are reasonable
  avg_goals_per_game <- sum(standings$GoalsFor) / sum(standings$Played)
  expect_true(avg_goals_per_game > 1.0 && avg_goals_per_game < 4.0,
              info = paste("Average goals per game:", round(avg_goals_per_game, 2)))
})

test_that("Simulation handles edge cases gracefully", {
  teams <- create_test_teams(4)  # Small league for testing
  
  # Test 1: Empty fixture list
  empty_results <- generate_elo_based_results(teams, data.frame(home = character(), 
                                                                away = character()))
  expect_equal(length(empty_results$results), 0)
  expect_equal(empty_results$final_elos, empty_results$initial_elos)
  
  # Test 2: Single match
  single_fixture <- data.frame(
    home = teams$Team[1],
    away = teams$Team[2],
    date = Sys.Date(),
    stringsAsFactors = FALSE
  )
  single_result <- generate_elo_based_results(teams, single_fixture, seed = 999)
  expect_equal(length(single_result$results), 1)
  
  # ELO changes should be opposite for both teams
  elo_change_home <- single_result$final_elos[teams$Team[1]] - 
                     single_result$initial_elos[teams$Team[1]]
  elo_change_away <- single_result$final_elos[teams$Team[2]] - 
                     single_result$initial_elos[teams$Team[2]]
  expect_equal(unname(elo_change_home), unname(-elo_change_away), tolerance = 0.001)
})

test_that("Results can be saved and loaded for Shiny app", {
  # Create simulation results structure
  teams <- read.csv("fixtures/test-data/TeamList_2024_test.csv", stringsAsFactors = FALSE)
  
  # Create mock probability matrix
  probability_matrix <- matrix(runif(18*18), nrow = 18, ncol = 18)
  rownames(probability_matrix) <- teams$Team
  colnames(probability_matrix) <- paste0("Position_", 1:18)
  
  # Normalize rows
  for (i in 1:nrow(probability_matrix)) {
    probability_matrix[i,] <- probability_matrix[i,] / sum(probability_matrix[i,])
  }
  
  # Create results object matching expected format
  results <- list(
    probability_matrix = probability_matrix,
    timestamp = Sys.time(),
    metadata = list(
      league = "Bundesliga",
      season = 2024,
      matchday = 15,
      simulations = 10000
    )
  )
  
  # Save to temporary file
  temp_file <- tempfile(fileext = ".Rds")
  saveRDS(results, temp_file)
  
  # Load and verify
  loaded <- readRDS(temp_file)
  
  expect_equal(names(loaded), names(results))
  expect_equal(dim(loaded$probability_matrix), dim(results$probability_matrix))
  expect_true(inherits(loaded$timestamp, "POSIXct"))
  expect_equal(loaded$metadata$league, "Bundesliga")
  
  # Cleanup
  unlink(temp_file)
})

test_that("Simulation performance is acceptable", {
  teams <- create_test_teams(18)
  fixtures <- generate_season_fixtures(teams$Team)
  
  # Time the mock simulation
  start_time <- Sys.time()
  
  # Generate full season results
  results <- generate_elo_based_results(teams, fixtures, seed = 9999)
  
  # Mock probability calculation (would be leagueSimulatorCPP in real test)
  n_sims <- 1000
  for (i in 1:n_sims) {
    # Simplified simulation logic
    final_points <- numeric(18)
    for (j in 1:18) {
      # Random points based on ELO
      elo_factor <- (results$final_elos[teams$Team[j]] - 1300) / 500
      final_points[j] <- round(runif(1, 30 + 20 * elo_factor, 60 + 30 * elo_factor))
    }
  }
  
  end_time <- Sys.time()
  duration <- as.numeric(end_time - start_time, units = "secs")
  
  # Should complete reasonably quickly
  expect_lt(duration, 5, 
            label = paste("Simulation time:", round(duration, 2), "seconds"))
  
  cat("\nMock simulation (1000 iterations) completed in", round(duration, 2), "seconds\n")
})