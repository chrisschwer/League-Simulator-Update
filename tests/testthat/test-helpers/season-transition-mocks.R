# Mock data generators for season transition tests
# Provides consistent test data for all season transition test suites

# Mock API response generators
create_mock_api_teams <- function(league_id, season, team_count = NULL) {
  # Generate mock API team responses
  
  # Default team counts per league
  if (is.null(team_count)) {
    team_count <- switch(as.character(league_id),
      "78" = 18,  # Bundesliga
      "79" = 18,  # 2. Bundesliga  
      "80" = 20,  # 3. Liga
      18
    )
  }
  
  # Generate team IDs based on league
  base_id <- switch(as.character(league_id),
    "78" = 157,   # Bundesliga starts at 157
    "79" = 158,   # 2. Bundesliga starts at 158
    "80" = 1000,  # 3. Liga starts at 1000
    1000
  )
  
  teams <- list()
  
  for (i in 1:team_count) {
    team_id <- base_id + i - 1
    
    # Known team mapping for realistic testing
    team_name <- if (league_id == "78") {
      switch(as.character(team_id),
        "157" = "Bayern Munich",
        "160" = "SC Freiburg", 
        "168" = "Bayer Leverkusen",
        "165" = "Borussia Dortmund",
        "167" = "Hoffenheim",
        paste("Bundesliga Team", i)
      )
    } else if (league_id == "79") {
      switch(as.character(team_id),
        "158" = "Fortuna Düsseldorf",
        "171" = "1. FC Nürnberg",
        "174" = "Schalke 04",
        paste("2. Bundesliga Team", i)
      )
    } else {
      switch(as.character(team_id),
        "1320" = "Energie Cottbus",
        "4259" = "Alemannia Aachen", 
        "1321" = "Hansa Rostock",
        "9364" = "Hoffenheim II",
        "12867" = "Stuttgart II",
        paste("3. Liga Team", i)
      )
    }
    
    # Detect second teams
    is_second_team <- grepl("II$", team_name) || 
                     team_id %in% c(9364, 12867, 9367, 9363)
    
    teams[[i]] <- list(
      id = team_id,
      name = team_name,
      is_second_team = is_second_team
    )
  }
  
  return(teams)
}

# Mock ELO data generators
create_mock_final_elos <- function(season, league_id = NULL, team_ids = NULL) {
  # Generate mock final ELO data for testing
  
  if (is.null(team_ids)) {
    # Default team IDs for testing
    team_ids <- switch(as.character(league_id),
      "78" = c(157, 160, 168, 165, 167),  # Top Bundesliga teams
      "79" = c(158, 171, 174, 176, 179),  # 2. Bundesliga teams
      "80" = c(1320, 4259, 1321, 9364, 12867),  # 3. Liga teams
      c(168, 167, 165, 1320, 4259)  # Mixed for general testing
    )
  }
  
  # Generate ELO values with realistic distributions
  base_elo <- switch(as.character(league_id),
    "78" = 1700,  # Bundesliga
    "79" = 1400,  # 2. Bundesliga
    "80" = 1100,  # 3. Liga
    1400  # Default
  )
  
  # Add variation for realistic ELO spread
  final_elos <- data.frame(
    TeamID = team_ids,
    FinalELO = base_elo + runif(length(team_ids), -200, 200),
    stringsAsFactors = FALSE
  )
  
  # Sort by ELO for consistent testing
  final_elos <- final_elos[order(final_elos$FinalELO, decreasing = TRUE), ]
  
  return(final_elos)
}

# Mock Liga3 baseline scenarios
create_mock_liga3_scenario <- function(season, scenario = "normal") {
  # Generate Liga3 data for baseline calculation testing
  
  # Base team IDs for Liga3
  liga3_teams <- c(1320, 4259, 1321, 1001, 1002, 1003, 1004, 1005, 1006, 1007)
  
  # Different ELO distributions for different scenarios
  elo_values <- switch(scenario,
    "normal" = c(1200, 1150, 1100, 1050, 1000, 950, 900, 850, 800, 750),
    "high" = c(1350, 1300, 1250, 1200, 1150, 1100, 1050, 1000, 950, 900),
    "low" = c(1100, 1050, 1000, 950, 900, 850, 800, 750, 700, 650),
    "compressed" = c(1150, 1140, 1130, 1120, 1110, 1100, 1090, 1080, 1070, 1060),
    c(1200, 1150, 1100, 1050, 1000, 950, 900, 850, 800, 750)
  )
  
  # Create match data
  matches <- data.frame(
    fixture_date = paste0(season, "-05-01"),
    teams_home_id = liga3_teams[1:5],
    teams_away_id = liga3_teams[6:10],
    goals_home = c(2, 1, 0, 3, 1),
    goals_away = c(1, 1, 2, 1, 0),
    fixture_status_short = rep("FT", 5),
    stringsAsFactors = FALSE
  )
  
  # Create final ELO data
  final_elos <- data.frame(
    TeamID = liga3_teams,
    FinalELO = elo_values,
    stringsAsFactors = FALSE
  )
  
  # Calculate expected baseline (mean of bottom 4)
  sorted_elos <- sort(elo_values)
  expected_baseline <- mean(sorted_elos[1:4])
  
  return(list(
    matches = matches,
    final_elos = final_elos,
    expected_baseline = expected_baseline,
    bottom_4_teams = liga3_teams[order(elo_values)][1:4],
    bottom_4_elos = sorted_elos[1:4]
  ))
}

# Mock team list generators
create_mock_team_list <- function(season, league_id = NULL) {
  # Generate mock TeamList data for testing
  
  if (is.null(league_id)) {
    # Create combined team list with all leagues
    bundesliga <- create_mock_team_list(season, "78")
    zweite <- create_mock_team_list(season, "79")
    liga3 <- create_mock_team_list(season, "80")
    
    return(rbind(bundesliga, zweite, liga3))
  }
  
  # Generate league-specific team list
  api_teams <- create_mock_api_teams(league_id, season)
  
  team_data <- data.frame(
    TeamID = sapply(api_teams, function(t) t$id),
    ShortText = sapply(api_teams, function(t) {
      # Generate realistic short names
      if (t$id == 1320) return("FCE")  # Cottbus
      if (t$id == 4259) return("AAC")  # Aachen
      if (t$id == 168) return("B04")   # Leverkusen
      if (t$id == 167) return("HOF")   # Hoffenheim
      if (t$id == 165) return("BVB")   # Dortmund
      if (t$id == 157) return("FCB")   # Bayern
      if (t$id == 9364) return("HO2")  # Hoffenheim II
      if (t$id == 12867) return("ST2") # Stuttgart II
      
      # Default short name generation
      paste0(substr(gsub("[^A-Z]", "", t$name), 1, 3))
    }),
    Promotion = sapply(api_teams, function(t) {
      if (t$is_second_team) return(-50)
      return(0)
    }),
    InitialELO = sapply(api_teams, function(t) {
      # League-appropriate ELO
      if (league_id == "78") return(sample(1500:1900, 1))
      if (league_id == "79") return(sample(1200:1600, 1))
      if (league_id == "80") return(sample(900:1300, 1))
      return(1400)
    }),
    stringsAsFactors = FALSE
  )
  
  return(team_data)
}

# Mock multi-season progression
create_mock_multi_season_progression <- function(start_season, end_season) {
  # Generate mock data for multi-season testing
  
  seasons <- start_season:end_season
  progression <- list()
  
  # Key teams for progression tracking
  key_teams <- c(168, 1320, 4259)  # B04, Cottbus, Aachen
  
  for (i in seq_along(seasons)) {
    season <- seasons[i]
    
    # Create team list for this season
    team_list <- data.frame(
      TeamID = key_teams,
      ShortText = c("B04", "FCE", "AAC"),
      Promotion = c(0, 0, 0),
      InitialELO = if (i == 1) {
        c(1765, 1100, 1050)  # Starting ELOs
      } else {
        # Progressive ELO improvement
        c(1765 + (i-1) * 50, 1100 + (i-1) * 25, 1050 + (i-1) * 20)
      },
      stringsAsFactors = FALSE
    )
    
    # Create final ELOs (showing progression)
    final_elos <- data.frame(
      TeamID = key_teams,
      FinalELO = team_list$InitialELO + c(30, 15, 10),  # Performance gains
      stringsAsFactors = FALSE
    )
    
    # Create Liga3 baseline for this season
    liga3_scenario <- create_mock_liga3_scenario(season, "normal")
    
    progression[[as.character(season)]] <- list(
      season = season,
      team_list = team_list,
      final_elos = final_elos,
      liga3_baseline = liga3_scenario$expected_baseline,
      api_teams = create_mock_api_teams("80", season)[1:3]  # Same teams return
    )
  }
  
  return(progression)
}

# Mock temporary file scenarios
create_mock_temp_files <- function(season, temp_dir = tempdir()) {
  # Generate mock temporary files for testing
  
  temp_files <- list()
  
  # Create temp files for each league
  for (league in c("78", "79", "80")) {
    filename <- file.path(temp_dir, paste0("TeamList_", season, "_League", league, "_temp.csv"))
    team_data <- create_mock_team_list(season, league)
    
    write.table(team_data, filename, sep = ";", row.names = FALSE, quote = FALSE)
    temp_files[[league]] <- filename
  }
  
  return(temp_files)
}

# Mock error scenarios
create_mock_error_scenarios <- function() {
  # Generate error scenarios for testing
  
  return(list(
    # API errors
    api_timeout = function() {
      stop("API timeout")
    },
    
    api_rate_limit = function() {
      stop("Rate limit exceeded")
    },
    
    # File errors
    file_not_found = function() {
      stop("File not found")
    },
    
    file_permission_denied = function() {
      stop("Permission denied")
    },
    
    # Data errors
    invalid_csv = function() {
      stop("Invalid CSV format")
    },
    
    missing_columns = function() {
      stop("Missing required columns")
    },
    
    # ELO calculation errors
    insufficient_teams = function() {
      return(data.frame(
        TeamID = c(1, 2),
        FinalELO = c(1000, 1100),
        stringsAsFactors = FALSE
      ))
    },
    
    no_matches = function() {
      return(NULL)
    }
  )
}

# Test data validation helpers
validate_mock_team_list <- function(team_list) {
  # Validate mock team list structure
  
  required_cols <- c("TeamID", "ShortText", "Promotion", "InitialELO")
  
  if (!all(required_cols %in% colnames(team_list))) {
    stop("Mock team list missing required columns")
  }
  
  if (any(is.na(team_list$TeamID))) {
    stop("Mock team list contains NA TeamIDs")
  }
  
  if (any(nchar(team_list$ShortText) != 3)) {
    stop("Mock team list contains invalid ShortText")
  }
  
  return(TRUE)
}

validate_mock_final_elos <- function(final_elos) {
  # Validate mock final ELO structure
  
  required_cols <- c("TeamID", "FinalELO")
  
  if (!all(required_cols %in% colnames(final_elos))) {
    stop("Mock final ELOs missing required columns")
  }
  
  if (any(is.na(final_elos$FinalELO))) {
    stop("Mock final ELOs contains NA values")
  }
  
  if (any(final_elos$FinalELO < 500 | final_elos$FinalELO > 2500)) {
    stop("Mock final ELOs contains unrealistic values")
  }
  
  return(TRUE)
}

# Cleanup helpers
cleanup_mock_files <- function(file_paths) {
  # Clean up mock files after testing
  
  for (file_path in file_paths) {
    if (file.exists(file_path)) {
      unlink(file_path)
    }
  }
}

cleanup_mock_temp_files <- function(temp_files) {
  # Clean up mock temporary files
  
  for (league in names(temp_files)) {
    if (file.exists(temp_files[[league]])) {
      unlink(temp_files[[league]])
    }
  }
}

# Mock stub helpers for common patterns
stub_season_transition_mocks <- function(test_env) {
  # Apply common stubs for season transition testing
  
  # Mock API functions
  stub(test_env, "fetch_all_leagues_teams", function(season) {
    return(list(
      "78" = create_mock_api_teams("78", season),
      "79" = create_mock_api_teams("79", season),
      "80" = create_mock_api_teams("80", season)
    ))
  })
  
  # Mock ELO calculation
  stub(test_env, "calculate_final_elos", function(season) {
    return(create_mock_final_elos(season))
  })
  
  # Mock Liga3 baseline
  stub(test_env, "calculate_liga3_relegation_baseline", function(season) {
    scenario <- create_mock_liga3_scenario(season)
    return(scenario$expected_baseline)
  })
  
  # Mock file operations
  stub(test_env, "generate_team_list_csv", function(data, season, output_dir = "RCode") {
    return(file.path(output_dir, paste0("TeamList_", season, ".csv")))
  })
}