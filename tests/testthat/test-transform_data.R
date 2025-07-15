library(testthat)
source("../../RCode/transform_data.R")

test_that("transform_data converts API response correctly", {
  # Create test fixtures and teams
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()
  
  # Transform the data
  result <- transform_data(fixtures, teams)
  
  # Check structure
  expect_true(is.matrix(result))
  expect_equal(ncol(result), 6)  # TeamHome, TeamAway, GoalsHome, GoalsAway, ELOHome, ELOAway
  expect_equal(nrow(result), 3)  # 3 fixtures in test data
  
  # Check first finished game
  expect_equal(result[1, 1], 101)  # Team A ID
  expect_equal(result[1, 2], 102)  # Team B ID
  expect_equal(result[1, 3], 2)    # Goals home
  expect_equal(result[1, 4], 1)    # Goals away
  expect_equal(result[1, 5], 1500) # ELO home
  expect_equal(result[1, 6], 1450) # ELO away
  
  # Check second finished game
  expect_equal(result[2, 1], 103)  # Team C ID
  expect_equal(result[2, 2], 104)  # Team D ID
  expect_equal(result[2, 3], 1)    # Goals home
  expect_equal(result[2, 4], 1)    # Goals away
  expect_equal(result[2, 5], 1550) # ELO home
  expect_equal(result[2, 6], 1400) # ELO away
  
  # Check unfinished game (should have NA goals)
  expect_equal(result[3, 1], 101)  # Team A ID
  expect_equal(result[3, 2], 103)  # Team C ID
  expect_true(is.na(result[3, 3])) # Goals home NA
  expect_true(is.na(result[3, 4])) # Goals away NA
  expect_equal(result[3, 5], 1500) # ELO home
  expect_equal(result[3, 6], 1550) # ELO away
})

test_that("transform_data handles only finished games correctly", {
  # Create fixtures with only finished games
  fixtures <- list(
    fixtures = list(
      list(
        fixture = list(id = 1001, status = list(short = "FT")),
        teams = list(
          home = list(id = 101, name = "Team A"),
          away = list(id = 102, name = "Team B")
        ),
        goals = list(home = 3, away = 0)
      ),
      list(
        fixture = list(id = 1002, status = list(short = "FT")),
        teams = list(
          home = list(id = 103, name = "Team C"),
          away = list(id = 104, name = "Team D")
        ),
        goals = list(home = 2, away = 2)
      )
    )
  )
  
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # All games should have results
  expect_false(any(is.na(result[, 3])))
  expect_false(any(is.na(result[, 4])))
  expect_equal(nrow(result), 2)
})

test_that("transform_data handles only unfinished games correctly", {
  # Create fixtures with only unfinished games
  fixtures <- list(
    fixtures = list(
      list(
        fixture = list(id = 1001, status = list(short = "NS")),
        teams = list(
          home = list(id = 101, name = "Team A"),
          away = list(id = 102, name = "Team B")
        ),
        goals = list(home = NULL, away = NULL)
      ),
      list(
        fixture = list(id = 1002, status = list(short = "PST")),
        teams = list(
          home = list(id = 103, name = "Team C"),
          away = list(id = 104, name = "Team D")
        ),
        goals = list(home = NULL, away = NULL)
      )
    )
  )
  
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # All games should have NA results
  expect_true(all(is.na(result[, 3])))
  expect_true(all(is.na(result[, 4])))
  expect_equal(nrow(result), 2)
})

test_that("transform_data handles empty fixtures", {
  # Empty fixtures list
  fixtures <- list(fixtures = list())
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # Should return empty matrix with correct structure
  expect_true(is.matrix(result))
  expect_equal(nrow(result), 0)
  expect_equal(ncol(result), 6)
})

test_that("transform_data matches ELO values correctly", {
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # Verify ELO values are matched correctly
  # Team A (101) -> ELO 1500
  # Team B (102) -> ELO 1450
  # Team C (103) -> ELO 1550
  # Team D (104) -> ELO 1400
  
  # Check all fixtures have correct ELO values
  for (i in 1:nrow(result)) {
    home_id <- result[i, 1]
    away_id <- result[i, 2]
    
    # Find corresponding ELO values
    expected_home_elo <- switch(as.character(home_id),
      "101" = 1500,
      "102" = 1450,
      "103" = 1550,
      "104" = 1400
    )
    
    expected_away_elo <- switch(as.character(away_id),
      "101" = 1500,
      "102" = 1450,
      "103" = 1550,
      "104" = 1400
    )
    
    expect_equal(result[i, 5], expected_home_elo)
    expect_equal(result[i, 6], expected_away_elo)
  }
})

test_that("transform_data handles different game statuses", {
  # Test various game statuses
  fixtures <- list(
    fixtures = list(
      list(
        fixture = list(id = 1001, status = list(short = "FT")),
        teams = list(
          home = list(id = 101, name = "Team A"),
          away = list(id = 102, name = "Team B")
        ),
        goals = list(home = 1, away = 0)
      ),
      list(
        fixture = list(id = 1002, status = list(short = "AET")),  # After extra time
        teams = list(
          home = list(id = 103, name = "Team C"),
          away = list(id = 104, name = "Team D")
        ),
        goals = list(home = 2, away = 1)
      ),
      list(
        fixture = list(id = 1003, status = list(short = "PEN")),  # Penalties
        teams = list(
          home = list(id = 101, name = "Team A"),
          away = list(id = 103, name = "Team C")
        ),
        goals = list(home = 1, away = 1)
      ),
      list(
        fixture = list(id = 1004, status = list(short = "NS")),   # Not started
        teams = list(
          home = list(id = 102, name = "Team B"),
          away = list(id = 104, name = "Team D")
        ),
        goals = list(home = NULL, away = NULL)
      ),
      list(
        fixture = list(id = 1005, status = list(short = "CANC")), # Cancelled
        teams = list(
          home = list(id = 101, name = "Team A"),
          away = list(id = 104, name = "Team D")
        ),
        goals = list(home = NULL, away = NULL)
      )
    )
  )
  
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # FT should have results
  expect_equal(result[1, 3], 1)
  expect_equal(result[1, 4], 0)
  
  # AET should have results (assuming it's treated as finished)
  expect_equal(result[2, 3], 2)
  expect_equal(result[2, 4], 1)
  
  # PEN should have results (assuming it's treated as finished)
  expect_equal(result[3, 3], 1)
  expect_equal(result[3, 4], 1)
  
  # NS should have NA
  expect_true(is.na(result[4, 3]))
  expect_true(is.na(result[4, 4]))
  
  # CANC should have NA
  expect_true(is.na(result[5, 3]))
  expect_true(is.na(result[5, 4]))
})

test_that("transform_data handles missing team in teams list", {
  # Create fixtures with a team not in the teams list
  fixtures <- list(
    fixtures = list(
      list(
        fixture = list(id = 1001, status = list(short = "FT")),
        teams = list(
          home = list(id = 101, name = "Team A"),
          away = list(id = 999, name = "Unknown Team")  # Not in teams list
        ),
        goals = list(home = 2, away = 1)
      )
    )
  )
  
  teams <- create_test_teams_api()
  
  # Should handle gracefully - likely using a default ELO or skipping
  expect_error(transform_data(fixtures, teams), NA)  # Expect no error or specific handling
})

test_that("transform_data preserves fixture order", {
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # Check that fixtures appear in the same order
  expect_equal(result[1, 1:2], c(101, 102))  # First fixture
  expect_equal(result[2, 1:2], c(103, 104))  # Second fixture
  expect_equal(result[3, 1:2], c(101, 103))  # Third fixture
})

test_that("transform_data handles NULL goal values", {
  # Test fixture with NULL goals (different from NA)
  fixtures <- list(
    fixtures = list(
      list(
        fixture = list(id = 1001, status = list(short = "NS")),
        teams = list(
          home = list(id = 101, name = "Team A"),
          away = list(id = 102, name = "Team B")
        ),
        goals = list(home = NULL, away = NULL)
      )
    )
  )
  
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # NULL should be converted to NA
  expect_true(is.na(result[1, 3]))
  expect_true(is.na(result[1, 4]))
})

test_that("transform_data creates numeric matrix", {
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # All values should be numeric
  expect_true(is.numeric(result))
  expect_equal(typeof(result), "double")
  
  # Check specific columns are numeric
  expect_true(all(is.numeric(result[, 1])))  # Team IDs
  expect_true(all(is.numeric(result[, 2])))
  expect_true(all(is.numeric(result[, 5])))  # ELO values
  expect_true(all(is.numeric(result[, 6])))
})