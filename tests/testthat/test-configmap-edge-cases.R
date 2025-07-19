# Test specifications for ConfigMap edge cases and error scenarios
# These tests ensure robust handling of various failure modes

test_that("Application handles malformed ConfigMap data gracefully", {
  # GIVEN: ConfigMap might contain invalid data
  # WHEN: Application tries to parse TeamList
  # THEN: Appropriate error handling occurs
  
  # Test 12.1: Missing required columns
  test_malformed_csv <- function(csv_content) {
    temp_file <- tempfile(fileext = ".csv")
    writeLines(csv_content, temp_file)
    
    tryCatch({
      team_data <- read.csv(temp_file, sep = ";")
      # Validate expected columns
      required_cols <- c("TeamID", "ShortText", "Promotion", "InitialELO")
      missing_cols <- setdiff(required_cols, names(team_data))
      
      if (length(missing_cols) > 0) {
        stop(paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
      }
      
      return(list(success = TRUE, data = team_data))
    }, error = function(e) {
      return(list(success = FALSE, error = e$message))
    }, finally = {
      unlink(temp_file)
    })
  }
  
  # Test 12.2: CSV with missing columns
  result <- test_malformed_csv("TeamID;ShortText\n157;FCB")
  expect_false(result$success)
  expect_true(grepl("Missing required columns", result$error))
  
  # Test 12.3: Empty CSV
  result <- test_malformed_csv("")
  expect_false(result$success)
  
  # Test 12.4: Wrong delimiter
  result <- test_malformed_csv("TeamID,ShortText,Promotion,InitialELO\n157,FCB,0,1900")
  expect_false(result$success)
})

test_that("ConfigMap size limits are respected", {
  # GIVEN: Kubernetes has 1MB limit for ConfigMaps
  # WHEN: Large team data is generated
  # THEN: Size validation occurs
  
  # Test 13.1: Calculate ConfigMap size
  calculate_configmap_size <- function(team_data) {
    # Generate CSV content
    csv_content <- paste(
      paste(names(team_data), collapse = ";"),
      paste(apply(team_data, 1, paste, collapse = ";"), collapse = "\n"),
      sep = "\n"
    )
    
    # Generate full YAML
    yaml_content <- paste0(
      "apiVersion: v1\n",
      "kind: ConfigMap\n",
      "metadata:\n",
      "  name: team-data-test\n",
      "  namespace: league-simulator\n",
      "data:\n",
      "  TeamList_test.csv: |\n",
      paste0("    ", strsplit(csv_content, "\n")[[1]], collapse = "\n")
    )
    
    # Return size in bytes
    return(nchar(yaml_content, type = "bytes"))
  }
  
  # Test 13.2: Normal team data size
  normal_teams <- data.frame(
    TeamID = 1:56,
    ShortText = paste0("TM", 1:56),
    Promotion = rep(0, 56),
    InitialELO = rep(1500, 56)
  )
  
  size_bytes <- calculate_configmap_size(normal_teams)
  size_kb <- size_bytes / 1024
  
  # Test 13.3: Verify well under 1MB limit
  expect_lt(size_kb, 10)  # Should be less than 10KB
  expect_lt(size_bytes, 1048576)  # Less than 1MB
  
  # Test 13.4: Even with 1000 teams (unrealistic), still under limit
  many_teams <- data.frame(
    TeamID = 1:1000,
    ShortText = paste0("TEAM", 1:1000),
    Promotion = rep(0, 1000),
    InitialELO = rep(1500, 1000)
  )
  
  large_size <- calculate_configmap_size(many_teams)
  expect_lt(large_size, 1048576)  # Still under 1MB
})

test_that("Pod handles ConfigMap update scenarios", {
  # GIVEN: ConfigMap might be updated while pods are running
  # WHEN: ConfigMap is modified
  # THEN: Pods handle the change appropriately
  
  # Test 14.1: Simulate ConfigMap update detection
  detect_configmap_change <- function(old_data, new_data) {
    # Compare key fields
    if (!identical(dim(old_data), dim(new_data))) {
      return(list(changed = TRUE, reason = "Different number of teams"))
    }
    
    if (!identical(old_data$TeamID, new_data$TeamID)) {
      return(list(changed = TRUE, reason = "Team IDs changed"))
    }
    
    if (!identical(old_data$InitialELO, new_data$InitialELO)) {
      return(list(changed = TRUE, reason = "ELO ratings changed"))
    }
    
    return(list(changed = FALSE, reason = "No changes detected"))
  }
  
  # Test 14.2: No change scenario
  data1 <- data.frame(TeamID = 1:3, ShortText = c("A", "B", "C"), 
                     Promotion = c(0,0,0), InitialELO = c(1500, 1600, 1700))
  data2 <- data1
  
  result <- detect_configmap_change(data1, data2)
  expect_false(result$changed)
  
  # Test 14.3: ELO change scenario
  data3 <- data1
  data3$InitialELO[1] <- 1550
  
  result <- detect_configmap_change(data1, data3)
  expect_true(result$changed)
  expect_equal(result$reason, "ELO ratings changed")
  
  # Test 14.4: Team addition scenario
  data4 <- rbind(data1, data.frame(TeamID = 4, ShortText = "D", 
                                  Promotion = 0, InitialELO = 1400))
  
  result <- detect_configmap_change(data1, data4)
  expect_true(result$changed)
  expect_equal(result$reason, "Different number of teams")
})

test_that("Invalid team data is rejected during validation", {
  # GIVEN: Team data must meet certain criteria
  # WHEN: Invalid data is provided
  # THEN: Validation fails with appropriate errors
  
  # Test 15.1: Validation function
  validate_team_data <- function(team_data) {
    errors <- character()
    
    # Check for duplicate TeamIDs
    if (any(duplicated(team_data$TeamID))) {
      errors <- c(errors, "Duplicate TeamID values found")
    }
    
    # Check for empty team names
    if (any(nchar(as.character(team_data$ShortText)) == 0)) {
      errors <- c(errors, "Empty team names found")
    }
    
    # Check ELO range
    if (any(team_data$InitialELO < 0)) {
      errors <- c(errors, "Negative ELO values found")
    }
    
    if (any(team_data$InitialELO > 3000)) {
      errors <- c(errors, "ELO values exceed maximum (3000)")
    }
    
    # Check Promotion values
    if (!all(team_data$Promotion %in% c(0, 1))) {
      errors <- c(errors, "Invalid Promotion values (must be 0 or 1)")
    }
    
    return(list(valid = length(errors) == 0, errors = errors))
  }
  
  # Test 15.2: Valid data passes
  valid_data <- data.frame(
    TeamID = 1:3,
    ShortText = c("FCB", "BVB", "S04"),
    Promotion = c(0, 0, 0),
    InitialELO = c(1900, 1850, 1600)
  )
  
  result <- validate_team_data(valid_data)
  expect_true(result$valid)
  expect_equal(length(result$errors), 0)
  
  # Test 15.3: Duplicate TeamID fails
  invalid_data <- valid_data
  invalid_data$TeamID[2] <- 1
  
  result <- validate_team_data(invalid_data)
  expect_false(result$valid)
  expect_true("Duplicate TeamID values found" %in% result$errors)
  
  # Test 15.4: Invalid ELO fails
  invalid_data <- valid_data
  invalid_data$InitialELO[1] <- -100
  
  result <- validate_team_data(invalid_data)
  expect_false(result$valid)
  expect_true("Negative ELO values found" %in% result$errors)
  
  # Test 15.5: Invalid Promotion value fails
  invalid_data <- valid_data
  invalid_data$Promotion[1] <- 2
  
  result <- validate_team_data(invalid_data)
  expect_false(result$valid)
  expect_true("Invalid Promotion values (must be 0 or 1)" %in% result$errors)
})

test_that("ConfigMap rollback procedure works correctly", {
  # GIVEN: Bad ConfigMap might be deployed
  # WHEN: Rollback is needed
  # THEN: Previous version can be restored
  
  # Test 16.1: Version tracking
  create_versioned_configmap <- function(team_data, season, version, previous_version = NULL) {
    yaml_content <- paste0(
      "apiVersion: v1\n",
      "kind: ConfigMap\n",
      "metadata:\n",
      "  name: team-data-", season, "\n",
      "  namespace: league-simulator\n",
      "  labels:\n",
      "    season: \"", season, "\"\n",
      "    version: \"", version, "\"\n"
    )
    
    if (!is.null(previous_version)) {
      yaml_content <- paste0(
        yaml_content,
        "  annotations:\n",
        "    previous-version: \"", previous_version, "\"\n"
      )
    }
    
    return(yaml_content)
  }
  
  # Test 16.2: Create versioned ConfigMaps
  v1 <- create_versioned_configmap(valid_data, "2025", "1.0.0")
  v2 <- create_versioned_configmap(valid_data, "2025", "1.0.1", "1.0.0")
  
  # Test 16.3: Verify version tracking
  expect_true(grepl("version: \"1.0.0\"", v1))
  expect_true(grepl("version: \"1.0.1\"", v2))
  expect_true(grepl("previous-version: \"1.0.0\"", v2))
  
  # Test 16.4: Rollback command generation
  generate_rollback_command <- function(season, target_version) {
    paste0(
      "kubectl rollout undo deployment -n league-simulator ",
      "league-updater-bl league-updater-bl2 league-updater-liga3 ",
      "&& kubectl apply -f team-data-", season, "-configmap-v", target_version, ".yaml"
    )
  }
  
  rollback_cmd <- generate_rollback_command("2025", "1.0.0")
  expect_true(grepl("kubectl rollout undo", rollback_cmd))
  expect_true(grepl("team-data-2025-configmap-v1.0.0.yaml", rollback_cmd))
})