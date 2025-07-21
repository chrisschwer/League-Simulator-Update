# Test specifications for ConfigMap integration
# These tests ensure TeamList data can be loaded from ConfigMaps

# Helper function to get the appropriate path
get_teamlist_path <- function(season) {
  # Check for ConfigMap mount (Kubernetes environment)
  configmap_path <- paste0("/RCode/TeamList_", season, ".csv")
  if (file.exists(configmap_path)) {
    return(configmap_path)
  }
  
  # Check for relative path (CI/local environment)
  relative_path <- paste0("RCode/TeamList_", season, ".csv")
  if (file.exists(relative_path)) {
    return(relative_path)
  }
  
  # Try from test directory
  test_path <- paste0("../../RCode/TeamList_", season, ".csv")
  if (file.exists(test_path)) {
    return(test_path)
  }
  
  return(NULL)
}

test_that("ConfigMap loading preserves backward compatibility", {
  # GIVEN: TeamList files mounted via ConfigMap at expected paths
  # WHEN: Application reads TeamList data
  # THEN: Data loads successfully without code changes
  
  # Test 1.1: Verify file exists at expected path
  teamlist_path <- get_teamlist_path("2025")
  skip_if_null(teamlist_path, 
              "TeamList_2025.csv not found - skipping integration test")
  
  # Test 1.2: Verify CSV structure matches expected format
  team_data <- read.csv(teamlist_path, sep = ";")
  expect_equal(names(team_data), c("TeamID", "ShortText", "Promotion", "InitialELO"))
  
  # Test 1.3: Verify data types are preserved
  expect_type(team_data$TeamID, "integer")
  expect_type(team_data$ShortText, "character")
  expect_type(team_data$Promotion, "integer")
  expect_type(team_data$InitialELO, "double")
  
  # Test 1.4: Verify non-empty data
  expect_gt(nrow(team_data), 0)
})

test_that("Multiple season ConfigMaps can be mounted simultaneously", {
  # GIVEN: Multiple seasons need to be available
  # WHEN: Different ConfigMaps are mounted
  # THEN: All seasons are accessible
  
  # Test 2.1: Check 2024 season availability
  teamlist_2024 <- get_teamlist_path("2024")
  skip_if_null(teamlist_2024, "TeamList_2024.csv not found")
  team_2024 <- read.csv(teamlist_2024, sep = ";")
  expect_gt(nrow(team_2024), 0)
  
  # Test 2.2: Check 2025 season availability
  teamlist_2025 <- get_teamlist_path("2025")
  skip_if_null(teamlist_2025, "TeamList_2025.csv not found")
  team_2025 <- read.csv(teamlist_2025, sep = ";")
  expect_gt(nrow(team_2025), 0)
  
  # Test 2.3: Verify seasons have different data
  expect_false(identical(team_2024$InitialELO, team_2025$InitialELO))
})

test_that("ConfigMap mounting handles UTF-8 encoding correctly", {
  # GIVEN: Team names may contain special characters
  # WHEN: ConfigMap data is loaded
  # THEN: Character encoding is preserved
  
  teamlist_path <- get_teamlist_path("2025")
  skip_if_null(teamlist_path, "TeamList_2025.csv not found")
  
  # Test 3.1: Read with explicit encoding
  team_data <- read.csv(teamlist_path, sep = ";", 
                       encoding = "UTF-8")
  
  # Test 3.2: Verify known teams with special characters (if any)
  # Example: "1. FC Köln" would have umlaut
  expect_type(team_data$ShortText, "character")
  
  # Test 3.3: No encoding errors in team names
  expect_false(any(grepl("\\?", team_data$ShortText)))
})

test_that("Application handles missing ConfigMap gracefully", {
  # GIVEN: ConfigMap might not be mounted
  # WHEN: Application tries to read TeamList
  # THEN: Appropriate error handling occurs
  
  # Test 4.1: Check for non-existent season
  teamlist_2026 <- get_teamlist_path("2026")
  expect_null(teamlist_2026)
  
  # Test 4.2: Verify error handling for missing file
  # Use locale-agnostic approach - just verify an error occurs
  expect_error(
    read.csv("RCode/TeamList_2026.csv", sep = ";")
  )
  
  # Test 4.3: Fallback mechanism (if implemented)
  # This would be application-specific behavior
})

test_that("ConfigMap data validates against schema", {
  # GIVEN: TeamList has expected structure
  # WHEN: Data is loaded from ConfigMap
  # THEN: All validation rules pass
  
  teamlist_path <- get_teamlist_path("2025")
  skip_if_null(teamlist_path, "TeamList_2025.csv not found")
  team_data <- read.csv(teamlist_path, sep = ";")
  
  # Test 5.1: TeamID is unique
  expect_equal(length(unique(team_data$TeamID)), nrow(team_data))
  
  # Test 5.2: ShortText is non-empty
  expect_true(all(nchar(team_data$ShortText) > 0))
  
  # Test 5.3: Promotion is either 0 or -50 to reflect the artificial point punishment on teams that cannot be promoted
  expect_true(all(team_data$Promotion %in% c(0, -50)))
  
  # Test 5.4: InitialELO is within reasonable range
  expect_true(all(team_data$InitialELO > 1000))
  expect_true(all(team_data$InitialELO < 2500))
  
  # Test 5.5: Expected number of teams per league
  # Bundesliga: 18 teams, 2. Bundesliga: 18 teams, 3. Liga: 20 teams
  expect_true(nrow(team_data) %in% c(18, 20, 56))
})

test_that("Read-only ConfigMap mount prevents accidental writes", {
  # GIVEN: ConfigMaps are mounted read-only
  # WHEN: Application attempts to write
  # THEN: Write operations fail appropriately
  
  teamlist_path <- get_teamlist_path("2025")
  skip_if_null(teamlist_path, "TeamList_2025.csv not found")
  
  # Test 6.1: Verify write attempt fails (only in ConfigMap environment)
  if (grepl("^/RCode/", teamlist_path)) {
    # Use locale-agnostic approach - just verify an error occurs
    expect_error(
      write.csv(data.frame(test = 1), teamlist_path)
    )
  } else {
    skip("Write protection test only applicable in ConfigMap environment")
  }
  
  # Test 6.2: Original data remains unchanged
  team_data <- read.csv(teamlist_path, sep = ";")
  expect_true("TeamID" %in% names(team_data))
})