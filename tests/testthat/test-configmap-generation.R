# Test specifications for ConfigMap generation during season transition
# These tests ensure ConfigMap YAML files are created correctly

test_that("generate_configmap_yaml creates valid Kubernetes ConfigMap", {
  # GIVEN: Team data for a new season
  # WHEN: ConfigMap YAML is generated
  # THEN: Valid Kubernetes manifest is created
  
  # Test setup
  team_data <- data.frame(
    TeamID = c(157, 158, 159),
    ShortText = c("FCB", "BVB", "S04"),
    Promotion = c(0, 0, 0),
    InitialELO = c(1900.5, 1850.3, 1600.2)
  )
  
  # Test 7.1: Function to generate ConfigMap YAML
  generate_configmap_yaml <- function(team_data, season, version = "1.0.0") {
    # Create CSV content
    csv_content <- paste(
      paste(names(team_data), collapse = ";"),
      paste(apply(team_data, 1, paste, collapse = ";"), collapse = "\n"),
      sep = "\n"
    )
    
    # Generate YAML
    yaml_content <- paste0(
      "apiVersion: v1\n",
      "kind: ConfigMap\n",
      "metadata:\n",
      "  name: team-data-", season, "\n",
      "  namespace: league-simulator\n",
      "  labels:\n",
      "    season: \"", season, "\"\n",
      "    version: \"", version, "\"\n",
      "    generated: \"", Sys.Date(), "\"\n",
      "data:\n",
      "  TeamList_", season, ".csv: |\n",
      paste0("    ", strsplit(csv_content, "\n")[[1]], collapse = "\n")
    )
    
    return(yaml_content)
  }
  
  # Test 7.2: Generate YAML
  yaml_output <- generate_configmap_yaml(team_data, "2025")
  
  # Test 7.3: Verify YAML structure
  expect_true(grepl("apiVersion: v1", yaml_output))
  expect_true(grepl("kind: ConfigMap", yaml_output))
  expect_true(grepl("name: team-data-2025", yaml_output))
  expect_true(grepl("TeamList_2025.csv:", yaml_output))
  
  # Test 7.4: Verify CSV content is properly indented
  expect_true(grepl("    TeamID;ShortText;Promotion;InitialELO", yaml_output))
  expect_true(grepl("    157;FCB;0;1900.5", yaml_output))
})

test_that("ConfigMap generation handles special characters correctly", {
  # GIVEN: Team names with special characters
  # WHEN: ConfigMap is generated
  # THEN: Characters are properly escaped for YAML
  
  # Test 8.1: Team data with special characters
  team_data <- data.frame(
    TeamID = 160,
    ShortText = "1.FCK",  # Contains dot
    Promotion = 0,
    InitialELO = 1650.5
  )
  
  # Test 8.2: Generate YAML (using function from previous test)
  generate_configmap_yaml <- function(team_data, season) {
    csv_content <- paste(
      paste(names(team_data), collapse = ";"),
      paste(apply(team_data, 1, paste, collapse = ";"), collapse = "\n"),
      sep = "\n"
    )
    
    # Escape special YAML characters if needed
    csv_content <- gsub("\\\\", "\\\\\\\\", csv_content)
    csv_content <- gsub("\"", "\\\"", csv_content)
    
    yaml_content <- paste0(
      "apiVersion: v1\n",
      "kind: ConfigMap\n",
      "metadata:\n",
      "  name: team-data-", season, "\n",
      "data:\n",
      "  TeamList_", season, ".csv: |\n",
      paste0("    ", strsplit(csv_content, "\n")[[1]], collapse = "\n")
    )
    
    return(yaml_content)
  }
  
  yaml_output <- generate_configmap_yaml(team_data, "2025")
  
  # Test 8.3: Verify special characters preserved
  expect_true(grepl("1\\.FCK", yaml_output))
})

test_that("Season transition creates ConfigMap alongside CSV", {
  # GIVEN: Season transition process
  # WHEN: New TeamList CSV is generated
  # THEN: Corresponding ConfigMap YAML is also created
  
  # Test 9.1: Mock season transition function
  create_team_files <- function(team_data, season, output_dir) {
    # Create CSV file
    csv_path <- file.path(output_dir, paste0("TeamList_", season, ".csv"))
    write.table(team_data, csv_path, sep = ";", row.names = FALSE, quote = FALSE)
    
    # Create ConfigMap YAML
    yaml_path <- file.path(output_dir, paste0("team-data-", season, "-configmap.yaml"))
    
    # Generate YAML content
    csv_content <- paste(
      paste(names(team_data), collapse = ";"),
      paste(apply(team_data, 1, paste, collapse = ";"), collapse = "\n"),
      sep = "\n"
    )
    
    yaml_content <- paste0(
      "apiVersion: v1\n",
      "kind: ConfigMap\n",
      "metadata:\n",
      "  name: team-data-", season, "\n",
      "  namespace: league-simulator\n",
      "data:\n",
      "  TeamList_", season, ".csv: |\n",
      paste0("    ", strsplit(csv_content, "\n")[[1]], collapse = "\n")
    )
    
    writeLines(yaml_content, yaml_path)
    
    return(list(csv = csv_path, yaml = yaml_path))
  }
  
  # Test 9.2: Create test data
  temp_dir <- tempdir()
  team_data <- data.frame(
    TeamID = 157:159,
    ShortText = c("FCB", "BVB", "S04"),
    Promotion = c(0, 0, 0),
    InitialELO = c(1900, 1850, 1600)
  )
  
  # Test 9.3: Run creation
  result <- create_team_files(team_data, "2025", temp_dir)
  
  # Test 9.4: Verify both files created
  expect_true(file.exists(result$csv))
  expect_true(file.exists(result$yaml))
  
  # Test 9.5: Verify YAML content
  yaml_content <- readLines(result$yaml)
  expect_true(any(grepl("kind: ConfigMap", yaml_content)))
  expect_true(any(grepl("name: team-data-2025", yaml_content)))
  
  # Cleanup
  unlink(result$csv)
  unlink(result$yaml)
})

test_that("ConfigMap generation includes proper metadata", {
  # GIVEN: ConfigMap generation process
  # WHEN: YAML is created
  # THEN: Proper labels and annotations are included
  
  # Test 10.1: Generate ConfigMap with full metadata
  generate_configmap_with_metadata <- function(team_data, season, version) {
    csv_content <- paste(
      paste(names(team_data), collapse = ";"),
      paste(apply(team_data, 1, paste, collapse = ";"), collapse = "\n"),
      sep = "\n"
    )
    
    yaml_content <- paste0(
      "apiVersion: v1\n",
      "kind: ConfigMap\n",
      "metadata:\n",
      "  name: team-data-", season, "\n",
      "  namespace: league-simulator\n",
      "  labels:\n",
      "    app: league-simulator\n",
      "    component: team-data\n",
      "    season: \"", season, "\"\n",
      "    version: \"", version, "\"\n",
      "  annotations:\n",
      "    generated-by: \"season-transition\"\n",
      "    generated-at: \"", Sys.time(), "\"\n",
      "    team-count: \"", nrow(team_data), "\"\n",
      "data:\n",
      "  TeamList_", season, ".csv: |\n",
      paste0("    ", strsplit(csv_content, "\n")[[1]], collapse = "\n")
    )
    
    return(yaml_content)
  }
  
  # Test 10.2: Create test data
  team_data <- data.frame(
    TeamID = 157:174,
    ShortText = paste0("TM", 1:18),
    Promotion = rep(0, 18),
    InitialELO = seq(1500, 1900, length.out = 18)
  )
  
  # Test 10.3: Generate with metadata
  yaml_output <- generate_configmap_with_metadata(team_data, "2025", "1.0.0")
  
  # Test 10.4: Verify metadata
  expect_true(grepl("app: league-simulator", yaml_output))
  expect_true(grepl("season: \"2025\"", yaml_output))
  expect_true(grepl("version: \"1.0.0\"", yaml_output))
  expect_true(grepl("team-count: \"18\"", yaml_output))
})

test_that("ConfigMap handles all three leagues correctly", {
  # GIVEN: Full season data with all leagues
  # WHEN: ConfigMap is generated
  # THEN: All 56 teams are included (18 + 18 + 20)
  
  # Test 11.1: Create full league data
  bundesliga_teams <- data.frame(
    TeamID = 157:174,
    ShortText = paste0("BL", 1:18),
    Promotion = rep(0, 18),
    InitialELO = seq(1700, 2000, length.out = 18)
  )
  
  bundesliga2_teams <- data.frame(
    TeamID = 175:192,
    ShortText = paste0("B2", 1:18),
    Promotion = rep(0, 18),
    InitialELO = seq(1400, 1700, length.out = 18)
  )
  
  liga3_teams <- data.frame(
    TeamID = 193:212,
    ShortText = paste0("L3", 1:20),
    Promotion = rep(0, 20),
    InitialELO = seq(1200, 1400, length.out = 20)
  )
  
  # Test 11.2: Combine all leagues
  all_teams <- rbind(bundesliga_teams, bundesliga2_teams, liga3_teams)
  
  # Test 11.3: Verify total team count
  expect_equal(nrow(all_teams), 56)
  
  # Test 11.4: Generate ConfigMap for all teams
  csv_content <- paste(
    paste(names(all_teams), collapse = ";"),
    paste(apply(all_teams, 1, paste, collapse = ";"), collapse = "\n"),
    sep = "\n"
  )
  
  # Test 11.5: Verify content includes all leagues
  expect_true(grepl("BL1", csv_content))
  expect_true(grepl("B2", csv_content))
  expect_true(grepl("L3", csv_content))
})