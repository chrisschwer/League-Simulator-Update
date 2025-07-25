# CSV Generation Functions
# Creates properly formatted TeamList CSV files

# Source required dependencies
if (!exists("confirm_overwrite")) {
  # Try to find and source interactive_prompts.R
  possible_paths <- c(
    "RCode/interactive_prompts.R",
    "interactive_prompts.R",
    file.path(dirname(sys.frame(1)$ofile %||% "."), "interactive_prompts.R"),
    "../RCode/interactive_prompts.R",
    "../../RCode/interactive_prompts.R"
  )
  
  sourced <- FALSE
  for (path in possible_paths) {
    if (file.exists(path)) {
      source(path)
      sourced <- TRUE
      break
    }
  }
  
  if (!sourced) {
    stop("Could not find interactive_prompts.R - required for csv_generation.R")
  }
}

generate_team_list_csv <- function(team_data, season, output_dir = "RCode") {
  # Generate properly formatted TeamList CSV
  # Handles all required columns and formatting
  
  tryCatch({
    # Validate input data
    if (is.null(team_data) || length(team_data) == 0 || 
        (is.data.frame(team_data) && nrow(team_data) == 0)) {
      stop("No team data provided")
    }
    
    # Format team data for CSV
    formatted_data <- format_team_data(team_data)
    
    # Validate formatted data
    validation <- validate_csv_data(formatted_data)
    if (!validation$valid) {
      stop(paste("CSV data validation failed:", validation$message))
    }
    
    # Generate file path
    file_path <- file.path(output_dir, paste0("TeamList_", season, ".csv"))
    
    # Check if file already exists
    if (file.exists(file_path)) {
      if (!confirm_overwrite(file_path)) {
        stop("File overwrite cancelled by user")
      }
      
      # Backup existing file
      backup_path <- backup_existing_file(file_path)
      cat("Backup created:", backup_path, "\n")
    }
    
    # Write CSV file
    write_team_list_safely(formatted_data, file_path)
    
    # Verify file integrity
    if (!verify_csv_integrity(file_path)) {
      stop("CSV integrity verification failed")
    }
    
    cat("Team list CSV created successfully:", file_path, "\n")
    cat("Teams:", nrow(formatted_data), "\n")
    
    # Generate corresponding ConfigMap YAML if ConfigMap generator is available
    tryCatch({
        # Try multiple paths for the configmap generator
        possible_paths <- c(
            "k8s/templates/configmap-generator.R",
            file.path("..", "k8s", "templates", "configmap-generator.R"),
            file.path("..", "..", "k8s", "templates", "configmap-generator.R"),
            file.path(getwd(), "k8s", "templates", "configmap-generator.R")
        )
        
        configmap_generator_path <- NULL
        for (path in possible_paths) {
            if (file.exists(path)) {
                configmap_generator_path <- path
                break
            }
        }
        
        if (!is.null(configmap_generator_path)) {
            source(configmap_generator_path)
            yaml_file <- generate_configmap_yaml(file_path, season, version = "1.0.0")
            cat("✓ Generated ConfigMap YAML:", yaml_file, "\n")
        } else {
            # This is not an error - ConfigMap generation is optional
            if (interactive() || getOption("verbose", FALSE)) {
                cat("ConfigMap generator not found, skipping YAML generation\n")
            }
        }
    }, error = function(e) {
        cat("Warning: Could not generate ConfigMap YAML:", e$message, "\n")
    })
    
    return(file_path)
    
  }, error = function(e) {
    stop(paste("Error generating CSV for season", season, ":", e$message))
  })
}

format_team_data <- function(team_data) {
  # Format team data for CSV output
  # Merges all required information
  
  if (is.data.frame(team_data)) {
    # Data is already a data frame
    formatted_data <- team_data
  } else if (is.list(team_data)) {
    # Convert list to data frame
    formatted_data <- list_to_dataframe(team_data)
  } else {
    stop("Invalid team data format")
  }
  
  # Ensure required columns exist
  required_columns <- c("TeamID", "ShortText", "Promotion", "InitialELO")
  
  for (col in required_columns) {
    if (!col %in% colnames(formatted_data)) {
      stop(paste("Missing required column:", col))
    }
  }
  
  # Ensure proper data types
  formatted_data$TeamID <- as.character(formatted_data$TeamID)
  formatted_data$ShortText <- as.character(formatted_data$ShortText)
  formatted_data$Promotion <- as.numeric(formatted_data$Promotion)
  formatted_data$InitialELO <- as.numeric(formatted_data$InitialELO)
  
  # Apply promotion penalties for second teams
  formatted_data <- apply_promotion_penalties(formatted_data)
  
  # Sort by TeamID for consistency (numeric order but keep as character)
  formatted_data <- formatted_data[order(as.numeric(formatted_data$TeamID)), ]
  
  # Select only required columns in correct order
  formatted_data <- formatted_data[, required_columns]
  
  return(formatted_data)
}

list_to_dataframe <- function(team_list) {
  # Convert list of teams to data frame
  # Handles missing fields gracefully
  
  if (length(team_list) == 0) {
    return(data.frame(
      TeamID = character(),
      ShortText = character(),
      Promotion = numeric(),
      InitialELO = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Extract data from list
  team_ids <- sapply(team_list, function(t) t$id %||% t$TeamID %||% NA)
  short_texts <- sapply(team_list, function(t) t$short_name %||% t$ShortText %||% "UNK")
  promotions <- sapply(team_list, function(t) t$promotion_value %||% t$Promotion %||% 0)
  initial_elos <- sapply(team_list, function(t) t$initial_elo %||% t$InitialELO %||% 1200)
  
  # Create data frame
  df <- data.frame(
    TeamID = team_ids,
    ShortText = short_texts,
    Promotion = promotions,
    InitialELO = initial_elos,
    stringsAsFactors = FALSE
  )
  
  # Remove rows with missing TeamID
  df <- df[!is.na(df$TeamID), ]
  
  return(df)
}

apply_promotion_penalties <- function(team_data) {
  # Apply -50 promotion penalty to second teams
  # Only for Liga3 teams
  
  for (i in 1:nrow(team_data)) {
    team_name <- team_data$ShortText[i]
    
    # Check if it's a second team
    if (detect_second_teams(team_name)) {
      team_data$Promotion[i] <- -50
    }
  }
  
  return(team_data)
}

detect_second_teams <- function(team_name) {
  # Detect if a team is a second team based on short name
  # Returns TRUE for second teams
  
  # Be more specific - only detect actual second team patterns
  second_team_patterns <- c(
    ".*II$",         # Ends with II
    ".*2$",          # Ends with 2
    "^[A-Z]{2,3}2$", # 3-4 character codes ending with 2 (like H962, VFB2)
    "^.*[0-9]+$"     # Ends with number(s) but be careful
  )
  
  # Exclude patterns that are NOT second teams
  # Many teams naturally have numbers in their names
  false_positive_patterns <- c(
    "^M02$",   # Mainz 05 -> M02
    "^S02$",   # Schalke 04 -> S02  
    "^H92$",   # Hannover 96 -> H92
    "^D92$",   # Darmstadt 98 -> D92
    "^SC2$",   # SC Paderborn -> SC2
    "^FC2$",   # FC Ingolstadt -> FC2
    "^UL2$"    # SSV Ulm -> UL2
  )
  
  # Check if it matches false positive patterns first
  for (pattern in false_positive_patterns) {
    if (grepl(pattern, team_name)) {
      return(FALSE)
    }
  }
  
  # Only consider teams ending in 2 as second teams if they have more than 3 chars
  # or if they explicitly end with "II"
  if (grepl("II$", team_name)) {
    return(TRUE)
  }
  
  if (grepl("2$", team_name) && nchar(team_name) >= 4) {
    return(TRUE)
  }
  
  return(FALSE)
}

validate_csv_data <- function(data) {
  # Validate CSV data structure and content
  # Returns validation results
  
  if (is.null(data) || nrow(data) == 0) {
    return(list(
      valid = FALSE,
      message = "No data to validate"
    ))
  }
  
  # Check required columns
  required_columns <- c("TeamID", "ShortText", "Promotion", "InitialELO")
  missing_columns <- setdiff(required_columns, colnames(data))
  
  if (length(missing_columns) > 0) {
    return(list(
      valid = FALSE,
      message = paste("Missing columns:", paste(missing_columns, collapse = ", "))
    ))
  }
  
  # Check data types
  type_errors <- c()
  
  # TeamID can be either numeric or character
  if (!is.numeric(data$TeamID) && !is.character(data$TeamID)) {
    type_errors <- c(type_errors, "TeamID must be numeric or character")
  }
  
  if (!is.character(data$ShortText)) {
    type_errors <- c(type_errors, "ShortText must be character")
  }
  
  if (!is.numeric(data$Promotion)) {
    type_errors <- c(type_errors, "Promotion must be numeric")
  }
  
  if (!is.numeric(data$InitialELO)) {
    type_errors <- c(type_errors, "InitialELO must be numeric")
  }
  
  if (length(type_errors) > 0) {
    return(list(
      valid = FALSE,
      message = paste("Type errors:", paste(type_errors, collapse = "; "))
    ))
  }
  
  # Check for missing values
  if (any(is.na(data$TeamID))) {
    return(list(
      valid = FALSE,
      message = "TeamID cannot contain NA values"
    ))
  }
  
  if (any(is.na(data$ShortText))) {
    return(list(
      valid = FALSE,
      message = "ShortText cannot contain NA values"
    ))
  }
  
  # Check for duplicate TeamIDs
  if (any(duplicated(data$TeamID))) {
    return(list(
      valid = FALSE,
      message = "Duplicate TeamIDs found"
    ))
  }
  
  # Check for duplicate ShortTexts
  duplicate_short_texts <- data$ShortText[duplicated(data$ShortText)]
  if (length(duplicate_short_texts) > 0) {
    return(list(
      valid = FALSE,
      message = paste("Duplicate ShortTexts found:", paste(unique(duplicate_short_texts), collapse = ", "))
    ))
  }
  
  # Check ShortText format - allow 2-3 chars for regular teams, 4 chars for second teams ending in "2"
  valid_patterns <- c(
    "^[A-Z0-9]{2,3}$",     # 2-3 characters for regular teams
    "^[A-Z0-9]{3}2$"       # 4 characters for second teams (3 chars + "2")
  )
  
  invalid_short_texts <- c()
  for (short_text in data$ShortText) {
    is_valid <- FALSE
    for (pattern in valid_patterns) {
      if (grepl(pattern, short_text)) {
        is_valid <- TRUE
        break
      }
    }
    if (!is_valid) {
      invalid_short_texts <- c(invalid_short_texts, short_text)
    }
  }
  
  if (length(invalid_short_texts) > 0) {
    return(list(
      valid = FALSE,
      message = paste("Invalid ShortText format:", paste(invalid_short_texts, collapse = ", "))
    ))
  }
  
  # Check ELO range
  if (any(data$InitialELO < 500 | data$InitialELO > 2500)) {
    return(list(
      valid = FALSE,
      message = "InitialELO values must be between 500 and 2500"
    ))
  }
  
  # Check promotion values
  valid_promotions <- c(0, -50)
  if (any(!data$Promotion %in% valid_promotions)) {
    return(list(
      valid = FALSE,
      message = "Promotion values must be 0 or -50"
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "CSV data validation passed"
  ))
}

write_team_list_safely <- function(data, file_path) {
  # Safe file writing with error handling
  # Atomic operations to prevent corruption
  
  tryCatch({
    # Create temporary file first
    temp_file <- paste0(file_path, ".tmp")
    
    # Write to temporary file
    write.table(
      data,
      temp_file,
      sep = ";",
      row.names = FALSE,
      col.names = TRUE,
      quote = FALSE
    )
    
    # Verify temporary file
    if (!file.exists(temp_file)) {
      stop("Temporary file creation failed")
    }
    
    # Move temporary file to final location
    if (file.exists(file_path)) {
      file.remove(file_path)
    }
    
    file.rename(temp_file, file_path)
    
    if (!file.exists(file_path)) {
      stop("Final file creation failed")
    }
    
    cat("CSV file written successfully:", file_path, "\n")
    return(TRUE)
    
  }, error = function(e) {
    # Clean up temporary file on error
    if (exists("temp_file") && file.exists(temp_file)) {
      file.remove(temp_file)
    }
    stop(paste("Error writing CSV file:", e$message))
  })
}

verify_csv_integrity <- function(file_path) {
  # Verify generated CSV has correct structure
  # Data validation and format checking
  
  tryCatch({
    # Check if file exists
    if (!file.exists(file_path)) {
      warning("CSV file does not exist:", file_path)
      return(FALSE)
    }
    
    # Read file back
    data <- read.csv(file_path, sep = ";", stringsAsFactors = FALSE)
    
    # Validate structure
    validation <- validate_csv_data(data)
    if (!validation$valid) {
      warning("CSV integrity check failed:", validation$message)
      return(FALSE)
    }
    
    # Check file size - adjust threshold based on actual content
    file_size <- file.info(file_path)$size
    if (file_size < 20) {  # Very minimal size for a CSV with headers
      warning("CSV file appears too small")
      return(FALSE)
    }
    
    return(TRUE)
    
  }, error = function(e) {
    warning("Error verifying CSV integrity:", e$message)
    return(FALSE)
  })
}

backup_existing_file <- function(file_path) {
  # Create backup of existing file before overwrite
  # Timestamp-based backup naming
  
  if (!file.exists(file_path)) {
    return(NULL)
  }
  
  # Generate backup filename with .bak extension
  backup_path <- paste0(file_path, ".bak")
  
  # Create backup
  tryCatch({
    file.copy(file_path, backup_path)
    
    if (file.exists(backup_path)) {
      return(backup_path)
    } else {
      warning("Backup file creation failed")
      return(NULL)
    }
    
  }, error = function(e) {
    warning("Error creating backup:", e$message)
    return(NULL)
  })
}

generate_csv_summary <- function(file_path) {
  # Generate summary of CSV file contents
  # Useful for verification and debugging
  
  tryCatch({
    if (!file.exists(file_path)) {
      return(list(error = "File does not exist"))
    }
    
    data <- read.csv(file_path, sep = ";", stringsAsFactors = FALSE)
    
    summary <- list(
      file_path = file_path,
      total_teams = nrow(data),
      unique_team_ids = length(unique(data$TeamID)),
      unique_short_texts = length(unique(data$ShortText)),
      min_elo = min(data$InitialELO),
      max_elo = max(data$InitialELO),
      mean_elo = mean(data$InitialELO),
      second_teams = sum(data$Promotion == -50),
      regular_teams = sum(data$Promotion == 0),
      file_size = file.info(file_path)$size,
      created_time = file.info(file_path)$mtime
    )
    
    return(summary)
    
  }, error = function(e) {
    return(list(error = e$message))
  })
}

export_team_comparison <- function(season1, season2, output_file = NULL) {
  # Export comparison between two seasons
  # Useful for analyzing team changes
  
  if (is.null(output_file)) {
    output_file <- paste0("team_comparison_", season1, "_", season2, ".csv")
  }
  
  tryCatch({
    # Read both season files
    file1 <- paste0("RCode/TeamList_", season1, ".csv")
    file2 <- paste0("RCode/TeamList_", season2, ".csv")
    
    if (!file.exists(file1)) {
      stop(paste("Season", season1, "file not found"))
    }
    
    if (!file.exists(file2)) {
      stop(paste("Season", season2, "file not found"))
    }
    
    data1 <- read.csv(file1, sep = ";", stringsAsFactors = FALSE)
    data2 <- read.csv(file2, sep = ";", stringsAsFactors = FALSE)
    
    # Find team changes
    teams_added <- setdiff(data2$TeamID, data1$TeamID)
    teams_removed <- setdiff(data1$TeamID, data2$TeamID)
    teams_common <- intersect(data1$TeamID, data2$TeamID)
    
    # Create comparison data
    comparison <- data.frame(
      Change_Type = c(
        rep("Added", length(teams_added)),
        rep("Removed", length(teams_removed)),
        rep("Common", length(teams_common))
      ),
      TeamID = c(teams_added, teams_removed, teams_common),
      stringsAsFactors = FALSE
    )
    
    # Add team details
    comparison <- merge(comparison, data1, by = "TeamID", all.x = TRUE, suffixes = c("", paste0("_", season1)))
    comparison <- merge(comparison, data2, by = "TeamID", all.x = TRUE, suffixes = c(paste0("_", season1), paste0("_", season2)))
    
    # Write comparison file
    write.csv(comparison, output_file, row.names = FALSE)
    
    cat("Team comparison exported to:", output_file, "\n")
    cat("Teams added:", length(teams_added), "\n")
    cat("Teams removed:", length(teams_removed), "\n")
    cat("Teams common:", length(teams_common), "\n")
    
    return(comparison)
    
  }, error = function(e) {
    warning("Error exporting team comparison:", e$message)
    return(NULL)
  })
}

# Utility operator for handling NULL values
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

merge_league_files <- function(season, output_dir) {
  # Merge individual league CSV files into final TeamList
  # Combines Liga1, Liga2, Liga3 files
  
  file_paths <- file.path(output_dir, c(
    paste0("TeamList_", season, "_Liga1.csv"),
    paste0("TeamList_", season, "_Liga2.csv"),
    paste0("TeamList_", season, "_Liga3.csv")
  ))
  
  # Check all files exist
  if (!all(file.exists(file_paths))) {
    missing <- file_paths[!file.exists(file_paths)]
    stop(paste("Missing league files:", paste(missing, collapse = ", ")))
  }
  
  # Read and combine
  all_data <- do.call(rbind, lapply(file_paths, function(f) {
    read.csv(f, sep = ";", stringsAsFactors = FALSE)
  }))
  
  # Write merged file
  output_file <- file.path(output_dir, paste0("TeamList_", season, ".csv"))
  write_team_list_safely(all_data, output_file)
  
  return(output_file)
}