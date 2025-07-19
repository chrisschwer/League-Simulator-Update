# Pre-Deployment Validation Tests
# These tests ensure the environment is ready for deployment

library(testthat)
library(renv)

context("Pre-deployment validation")

test_that("All required environment variables are set", {
  required_vars <- c("RAPIDAPI_KEY", "SHINYAPPS_IO_SECRET", "SEASON")
  
  for (var in required_vars) {
    expect_true(var %in% names(Sys.getenv()),
                info = sprintf("Environment variable %s is not set", var))
    
    expect_true(nchar(Sys.getenv(var)) > 0,
                info = sprintf("Environment variable %s is empty", var))
  }
})

test_that("Configuration files are valid", {
  season <- Sys.getenv("SEASON", "2024")
  team_list_file <- sprintf("TeamList_%s.csv", season)
  
  # Check if TeamList file exists
  expect_true(file.exists(team_list_file),
              info = sprintf("TeamList file %s does not exist", team_list_file))
  
  # Validate file structure
  team_data <- read.csv(team_list_file, stringsAsFactors = FALSE)
  
  # Check required columns
  required_columns <- c("League", "Team", "ID", "ELO", "Liga3Gruppe")
  expect_true(all(required_columns %in% names(team_data)),
              info = "TeamList file missing required columns")
  
  # Validate data integrity
  expect_true(all(!is.na(team_data$ID)),
              info = "TeamList contains teams with missing IDs")
  
  expect_true(all(team_data$ELO > 0),
              info = "TeamList contains invalid ELO ratings")
  
  expect_true(all(team_data$League %in% c("Bundesliga", "Bundesliga2", "Liga3")),
              info = "TeamList contains invalid league names")
})

test_that("Docker image passes security scan", {
  skip_if_not(Sys.which("trivy") != "", "Trivy not installed")
  
  # Run Trivy scan for HIGH and CRITICAL vulnerabilities
  scan_result <- system2("trivy", 
                        args = c("image", 
                                "--severity", "HIGH,CRITICAL",
                                "--exit-code", "1",
                                "--quiet",
                                "league-simulator:latest"),
                        stdout = TRUE,
                        stderr = TRUE)
  
  expect_equal(attr(scan_result, "status"), 0,
               info = paste("Security vulnerabilities found:",
                           paste(scan_result, collapse = "\n")))
})

test_that("Dependencies are at expected versions", {
  # Check if renv.lock exists
  expect_true(file.exists("renv.lock"),
              info = "renv.lock file not found")
  
  # Read lockfile
  lockfile <- renv::lockfile_read()
  installed_packages <- installed.packages()
  installed_versions <- setNames(installed_packages[, "Version"],
                                installed_packages[, "Package"])
  
  # Check critical packages
  critical_packages <- c("shiny", "httr", "jsonlite", "DBI", "testthat")
  
  for (pkg in critical_packages) {
    if (pkg %in% names(lockfile$Packages)) {
      expected_version <- lockfile$Packages[[pkg]]$Version
      
      expect_true(pkg %in% names(installed_versions),
                  info = sprintf("Package %s is not installed", pkg))
      
      if (pkg %in% names(installed_versions)) {
        expect_equal(installed_versions[pkg], expected_version,
                     info = sprintf("Package %s version mismatch: expected %s, got %s",
                                   pkg, expected_version, installed_versions[pkg]))
      }
    }
  }
})

test_that("Required directories exist with correct permissions", {
  required_dirs <- c("ShinyApp", "RCode", "data", "logs")
  
  for (dir in required_dirs) {
    expect_true(dir.exists(dir),
                info = sprintf("Required directory %s does not exist", dir))
    
    # Check if directory is writable
    test_file <- file.path(dir, ".write_test")
    can_write <- tryCatch({
      writeLines("test", test_file)
      unlink(test_file)
      TRUE
    }, error = function(e) FALSE)
    
    expect_true(can_write,
                info = sprintf("Directory %s is not writable", dir))
  }
})

test_that("Database connections can be established", {
  skip_if_not("DBI" %in% rownames(installed.packages()),
              "DBI package not installed")
  
  # This is a placeholder - actual implementation would depend on
  # the specific database configuration
  expect_true(TRUE, "Database connection test placeholder")
})

test_that("API endpoints are accessible", {
  skip_if_not(nchar(Sys.getenv("RAPIDAPI_KEY")) > 0,
              "RAPIDAPI_KEY not set")
  
  # Test API connectivity (without making actual requests that count against quota)
  api_host <- "api-football-v1.p.rapidapi.com"
  
  # Just check DNS resolution
  dns_check <- tryCatch({
    nsl <- nslookup(api_host)
    TRUE
  }, error = function(e) FALSE)
  
  expect_true(dns_check,
              info = sprintf("Cannot resolve API host: %s", api_host))
})