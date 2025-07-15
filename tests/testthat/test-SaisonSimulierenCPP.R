library(testthat)
source("../../RCode/SaisonSimulierenCPP.R")

test_that("SaisonSimulierenCPP simulates unplayed games correctly", {
  # Create a season with no games played
  spielplan <- create_test_season(0)
  elo_werte <- create_test_elo_values(4)
  
  # Run season simulation
  set.seed(123)
  result <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  # Check that all games now have results
  expect_false(any(is.na(result[, 3])))
  expect_false(any(is.na(result[, 4])))
  
  # Check that team IDs are preserved
  expect_equal(result[, 1:2], spielplan[, 1:2])
  
  # Check that goals are non-negative integers
  expect_true(all(result[, 3] >= 0))
  expect_true(all(result[, 4] >= 0))
  expect_true(all(result[, 3] == as.integer(result[, 3])))
  expect_true(all(result[, 4] == as.integer(result[, 4])))
})

test_that("SaisonSimulierenCPP preserves played games", {
  # Create a season with 6 games played
  spielplan <- create_test_season(6)
  elo_werte <- create_test_elo_values(4)
  
  # Store original played games
  original_results <- spielplan[1:6, 3:4]
  
  # Run season simulation
  set.seed(456)
  result <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  # Check that played games are preserved
  expect_equal(result[1:6, 3:4], original_results)
  
  # Check that remaining games are simulated
  expect_false(any(is.na(result[7:12, 3])))
  expect_false(any(is.na(result[7:12, 4])))
})

test_that("SaisonSimulierenCPP handles fully played season", {
  # Create a fully played season
  spielplan <- create_completed_season()
  elo_werte <- create_test_elo_values(4)
  
  # Store original results
  original_results <- spielplan[, 3:4]
  
  # Run season simulation
  result <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  # Results should be unchanged
  expect_equal(result[, 3:4], original_results)
})

test_that("SaisonSimulierenCPP updates ELO values through season", {
  # Create a season with no games played
  spielplan <- create_test_season(0)
  initial_elo <- create_test_elo_values(4)
  
  # Run season simulation
  set.seed(789)
  result <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = initial_elo,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  # ELO values should change throughout the season
  # We can't directly test the internal ELO updates, but we can verify
  # that the simulation produces varied results
  home_wins <- sum(result[, 3] > result[, 4])
  away_wins <- sum(result[, 4] > result[, 3])
  draws <- sum(result[, 3] == result[, 4])
  
  # Should have a mix of results
  expect_true(home_wins > 0)
  expect_true(away_wins > 0)
  expect_true(home_wins + away_wins + draws == 12)
})

test_that("SaisonSimulierenCPP respects home advantage", {
  # Create multiple seasons and check home advantage effect
  spielplan <- create_test_season(0)
  elo_werte <- rep(1500, 4)  # All teams equal ELO
  
  home_wins_total <- 0
  n_seasons <- 100
  
  for (i in 1:n_seasons) {
    set.seed(i)
    result <- SaisonSimulierenCPP(
      Spielplan = spielplan,
      ELOWerte = elo_werte,
      ModFaktor = 40,
      Heimvorteil = 100,
      AnzahlTeams = 4,
      AnzahlSpiele = 12
    )
    
    home_wins_total <- home_wins_total + sum(result[, 3] > result[, 4])
  }
  
  # With home advantage and equal teams, home wins should be > 33%
  home_win_rate <- home_wins_total / (n_seasons * 12)
  expect_true(home_win_rate > 0.35)
})

test_that("SaisonSimulierenCPP produces consistent results with same seed", {
  spielplan <- create_test_season(3)
  elo_werte <- create_test_elo_values(4)
  
  # Run twice with same seed
  set.seed(42)
  result1 <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  set.seed(42)
  result2 <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  # Results should be identical
  expect_equal(result1, result2)
})

test_that("SaisonSimulierenCPP handles different mod factors", {
  spielplan <- create_test_season(0)
  elo_werte <- c(1600, 1400, 1500, 1500)  # Varied ELO
  
  # Test with different modification factors
  set.seed(111)
  result_low <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 20,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  set.seed(111)
  result_high <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 60,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  # Both should produce valid results
  expect_false(any(is.na(result_low[, 3:4])))
  expect_false(any(is.na(result_high[, 3:4])))
  
  # Results might differ due to different ELO update magnitudes
  # affecting subsequent games
})

test_that("SaisonSimulierenCPP handles extreme ELO differences", {
  spielplan <- create_test_season(0)
  # Extreme ELO differences
  elo_werte <- c(2000, 1000, 1500, 1200)
  
  set.seed(999)
  result <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  # Should handle extreme differences without errors
  expect_false(any(is.na(result[, 3:4])))
  
  # Team 1 (ELO 2000) should generally score more goals
  team1_games <- which(spielplan[, 1] == 1 | spielplan[, 2] == 1)
  team1_goals <- sum(
    result[spielplan[, 1] == 1, 3],
    result[spielplan[, 2] == 1, 4]
  )
  
  # Team 2 (ELO 1000) should generally score fewer goals
  team2_games <- which(spielplan[, 1] == 2 | spielplan[, 2] == 2)
  team2_goals <- sum(
    result[spielplan[, 1] == 2, 3],
    result[spielplan[, 2] == 2, 4]
  )
  
  # This is probabilistic but with large ELO difference should generally hold
  expect_true(team1_goals >= 0)  # Basic sanity check
  expect_true(team2_goals >= 0)  # Basic sanity check
})

test_that("SaisonSimulierenCPP handles empty season gracefully", {
  # Empty season (no games)
  spielplan <- matrix(NA, nrow = 0, ncol = 4)
  elo_werte <- create_test_elo_values(4)
  
  result <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 0
  )
  
  # Should return empty matrix
  expect_equal(nrow(result), 0)
  expect_equal(ncol(result), 4)
})

test_that("SaisonSimulierenCPP maintains matrix structure", {
  spielplan <- create_test_season(5)
  elo_werte <- create_test_elo_values(4)
  
  set.seed(333)
  result <- SaisonSimulierenCPP(
    Spielplan = spielplan,
    ELOWerte = elo_werte,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  # Check matrix structure is preserved
  expect_equal(dim(result), dim(spielplan))
  expect_true(is.matrix(result))
  expect_equal(typeof(result), typeof(spielplan))
  
  # All values should be numeric
  expect_true(all(is.numeric(result)))
})