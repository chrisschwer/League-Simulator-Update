# Minimal test suite for deployment - only tests critical functionality needed for production

library(testthat)

# Skip these tests in non-deployment contexts
skip_if_not(Sys.getenv("RUN_DEPLOYMENT_TESTS_ONLY") == "true" || Sys.getenv("CI_ENVIRONMENT") == "true", 
            "Deployment tests only run in CI or when explicitly enabled")

# Source required files
source("tests/testthat/helper-test-setup.R")

context("Deployment-Critical Tests")

test_that("C++ compilation works", {
  skip_on_cran()
  
  # Test that the C++ file can be compiled
  expect_no_error({
    Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
  })
  
  # Test that the function exists after compilation
  expect_true(exists("SpielNichtSimulieren"))
})

test_that("API connection can be established", {
  skip_on_cran()
  skip_if(Sys.getenv("RAPIDAPI_KEY") == "", "No API key available")
  
  # Source API helpers
  source("RCode/api_helpers.R")
  source("RCode/api_service.R")
  
  # Test basic API connectivity
  result <- tryCatch({
    httr::GET(
      "https://api-football-v1.p.rapidapi.com/v3/status",
      httr::add_headers(
        "X-RapidAPI-Key" = Sys.getenv("RAPIDAPI_KEY"),
        "X-RapidAPI-Host" = "api-football-v1.p.rapidapi.com"
      ),
      httr::timeout(10)
    )
  }, error = function(e) NULL)
  
  expect_false(is.null(result))
  if (!is.null(result)) {
    expect_equal(httr::status_code(result), 200)
  }
})

test_that("Core simulation functions exist", {
  skip_on_cran()
  
  # Compile C++ if not already done
  if (!exists("SpielNichtSimulieren")) {
    Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
  }
  
  # Source core files
  source("RCode/prozent.R")
  source("RCode/Tabelle.R")
  source("RCode/SaisonSimulierenCPP.R")
  source("RCode/simulationsCPP.R")
  source("RCode/SpielCPP.R")
  
  # Check that key functions exist
  expect_true(exists("prozent"))
  expect_true(exists("Tabelle"))
  expect_true(exists("SaisonSimulierenCPP"))
  expect_true(exists("simulationsCPP"))
  expect_true(exists("SpielCPP"))
})

test_that("Team data files exist and are valid", {
  skip_on_cran()
  
  # Check that at least one TeamList file exists
  team_files <- list.files("RCode", pattern = "^TeamList_.*\\.csv$", full.names = TRUE)
  expect_true(length(team_files) > 0)
  
  # Check that we can read at least one file
  if (length(team_files) > 0) {
    data <- read.csv(team_files[1], sep = ";")
    expect_true(nrow(data) > 0)
    expect_true("Team" %in% names(data))
    expect_true("Liga" %in% names(data))
    expect_true("ELO" %in% names(data))
  }
})

test_that("Scheduler functions can be loaded", {
  skip_on_cran()
  
  # Test league scheduler
  source("RCode/league_scheduler.R")
  expect_true(exists("league_scheduler"))
  expect_true(is.function(league_scheduler))
  
  # Test shiny scheduler
  source("RCode/shiny_scheduler.R")
  expect_true(exists("shiny_scheduler"))
  expect_true(is.function(shiny_scheduler))
})

test_that("Basic simulation can run", {
  skip_on_cran()
  skip_if(Sys.getenv("RAPIDAPI_KEY") == "", "No API key available")
  
  # This is a minimal test to ensure the core simulation pipeline works
  # We'll use a very small number of iterations for speed
  
  # Compile and source everything needed
  if (!exists("SpielNichtSimulieren")) {
    Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
  }
  
  source("RCode/prozent.R")
  source("RCode/Tabelle.R")
  source("RCode/SaisonSimulierenCPP.R")
  source("RCode/simulationsCPP.R")
  source("RCode/SpielCPP.R")
  source("RCode/transform_data.R")
  
  # Create minimal test data
  test_season <- data.frame(
    Spieltag = c(1, 1),
    Heim = c("Team A", "Team B"),
    Gast = c("Team C", "Team D"),
    ToreHeim = c(2, NA),
    ToreGast = c(1, NA),
    Gespielt = c(1, 0),
    stringsAsFactors = FALSE
  )
  
  test_teams <- data.frame(
    Team = c("Team A", "Team B", "Team C", "Team D"),
    Liga = c(78, 78, 78, 78),
    ELO = c(1500, 1450, 1400, 1350),
    stringsAsFactors = FALSE
  )
  
  # Run a minimal simulation
  expect_no_error({
    result <- simulationsCPP(
      Saison = test_season,
      TeamList = test_teams,
      n = 10,  # Very small number for testing
      Tordifferenz = numeric(0),
      ToreFuer = numeric(0),
      Punkte_Hinzufuegen = numeric(0),
      Punkte_Entfernen = numeric(0)
    )
  })
})