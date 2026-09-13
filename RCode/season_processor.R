# Season Processing Pipeline
# Main processing logic for season transitions

# Helper function for robust sourcing
source_with_fallback <- function(path) {
  if (requireNamespace("here", quietly = TRUE)) {
    source(here::here(path))
  } else {
    # Fallback: try from project root or current directory
    if (file.exists(path)) {
      source(path)
    } else if (file.exists(file.path("..", "..", path))) {
      source(file.path("..", "..", path))
    } else {
      stop(paste("Cannot find", path))
    }
  }
}

# Source team data carryover module
source_with_fallback("RCode/team_data_carryover.R")

# ---------------------------------------------------------------------------
# Logging, Validierung und Datei-I/O -- seit der Geruest-Bereinigung (#209)
# hier statt in eigenen logging.R/error_handling.R/file_operations.R/
# input_validation.R-Dateien, weil scripts/season_transition.R diese
# Funktionen ausschliesslich von hier aus aufruft (bzw. safe_file_read()
# und validate_team_count() zusaetzlich aus dieser Datei selbst).
# ---------------------------------------------------------------------------

# Minimaler Logging-Kern (vormals logging.R), nur fuer create_processing_log()
# und log_error() gebraucht.
.LOG_CONFIG <- list(
  level = "INFO",
  file = "season_transition.log",
  console = TRUE,
  max_size = 10 * 1024 * 1024, # 10MB
  max_files = 5
)

LOG_LEVELS <- list(
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
  FATAL = 5
)

get_session_id <- function() {
  # Get or create session ID for tracking
  # Returns session identifier

  if (!exists(".SESSION_ID", envir = .GlobalEnv)) {
    session_id <- paste0("session_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    assign(".SESSION_ID", session_id, envir = .GlobalEnv)
  }

  return(get(".SESSION_ID", envir = .GlobalEnv))
}

format_log_message <- function(log_entry) {
  # Format log message for output
  # Returns formatted string

  formatted <- paste0(
    "[", log_entry$timestamp, "] ",
    "[", log_entry$level, "] ",
    log_entry$message
  )

  if (!is.null(log_entry$context)) {
    formatted <- paste0(formatted, " (", log_entry$context, ")")
  }

  return(formatted)
}

rotate_log_files <- function() {
  # Rotate log files when size limit is reached
  # Keeps specified number of historical files

  tryCatch(
    {
      log_file <- .LOG_CONFIG$file
      max_files <- .LOG_CONFIG$max_files

      if (!file.exists(log_file)) {
        return()
      }

      # Rotate existing files
      for (i in (max_files - 1):1) {
        old_file <- paste0(log_file, ".", i)
        new_file <- paste0(log_file, ".", i + 1)

        if (file.exists(old_file)) {
          file.rename(old_file, new_file)
        }
      }

      # Move current log to .1
      file.rename(log_file, paste0(log_file, ".1"))

      cat("Log files rotated\n")
    },
    error = function(e) {
      warning("Log rotation failed:", conditionMessage(e))
    }
  )
}

write_log_to_file <- function(log_entry, formatted_message) {
  # Write log entry to file
  # Handles file rotation and size limits

  tryCatch(
    {
      log_file <- .LOG_CONFIG$file

      # Check if log rotation is needed
      if (file.exists(log_file)) {
        file_size <- file.info(log_file)$size

        if (file_size > .LOG_CONFIG$max_size) {
          rotate_log_files()
        }
      }

      # Write to log file
      write(formatted_message, log_file, append = TRUE)
    },
    error = function(e) {
      # Fallback - write to console if file writing fails
      cat("LOG FILE ERROR:", conditionMessage(e), "\n")
      cat(formatted_message, "\n")
    }
  )
}

log_message <- function(level, message, context = NULL) {
  # Structured logging for debugging
  # Different log levels (DEBUG, INFO, WARN, ERROR, FATAL)

  tryCatch(
    {
      # Check if level is valid
      if (!level %in% names(LOG_LEVELS)) {
        level <- "INFO"
      }

      # Check if message should be logged based on level
      if (LOG_LEVELS[[level]] < LOG_LEVELS[[.LOG_CONFIG$level]]) {
        return()
      }

      # Create log entry
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

      log_entry <- list(
        timestamp = timestamp,
        level = level,
        message = message,
        context = context,
        pid = Sys.getpid(),
        session_id = get_session_id()
      )

      # Format log message
      formatted_message <- format_log_message(log_entry)

      # Write to console if enabled
      if (.LOG_CONFIG$console) {
        cat(formatted_message, "\n")
      }

      # Write to file
      write_log_to_file(log_entry, formatted_message)
    },
    error = function(e) {
      # Fallback - write to console if logging fails
      cat("LOGGING ERROR:", conditionMessage(e), "\n")
      cat("Original message:", message, "\n")
    }
  )
}

log_error <- function(message, context = NULL) {
  log_message("ERROR", message, context)
}

create_non_interactive_log <- function(from_season, to_season) {
  # Create detailed log file for non-interactive runs
  # Returns log file path

  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  log_filename <- paste0(
    "season_transition_", from_season, "_",
    to_season, "_", timestamp, ".log"
  )
  log_filepath <- file.path("logs", log_filename)

  # Create logs directory if it doesn't exist
  if (!dir.exists("logs")) {
    dir.create("logs")
  }

  # Initialize log file
  cat("=== Season Transition Log ===\n", file = log_filepath)
  cat("Mode: Non-Interactive\n", file = log_filepath, append = TRUE)
  cat("From Season:", from_season, "\n", file = log_filepath, append = TRUE)
  cat("To Season:", to_season, "\n", file = log_filepath, append = TRUE)
  cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n",
    file = log_filepath, append = TRUE
  )

  return(log_filepath)
}

create_processing_log <- function(source_season, target_season) {
  # Create processing log file
  # Tracks all operations and decisions

  tryCatch(
    {
      log_file <- paste0("processing_", source_season, "_to_", target_season, ".log")

      # Set processing-specific log file
      old_log_file <- .LOG_CONFIG$file
      .LOG_CONFIG$file <<- log_file

      # Log processing start
      log_message("INFO", "Processing started", paste("Source:", source_season, "Target:", target_season))

      # Log system information
      log_message("DEBUG", "System information", paste("R version:", R.version.string))
      log_message("DEBUG", "Working directory", getwd())
      log_message("DEBUG", "Session ID", get_session_id())

      return(log_file)
    },
    error = function(e) {
      warning("Failed to create processing log:", conditionMessage(e))
      return(NULL)
    }
  )
}

# Minimale Datei-I/O-Helfer (vormals file_operations.R).
check_file_permissions <- function(file_path, operation = "read") {
  # Check file permissions for specified operation
  # Returns TRUE if operation is allowed

  tryCatch(
    {
      if (!file.exists(file_path)) {
        # Check parent directory permissions for write operations
        if (operation == "write" || operation == "create") {
          parent_dir <- dirname(file_path)
          if (!dir.exists(parent_dir)) {
            return(FALSE)
          }
          return(file.access(parent_dir, mode = 2) == 0) # Write permission
        }
        return(FALSE)
      }

      # Check existing file permissions
      if (operation == "read") {
        return(file.access(file_path, mode = 4) == 0) # Read permission
      } else if (operation == "write") {
        return(file.access(file_path, mode = 2) == 0) # Write permission
      } else if (operation == "execute") {
        return(file.access(file_path, mode = 1) == 0) # Execute permission
      }

      return(FALSE)
    },
    error = function(e) {
      warning("Error checking file permissions:", e$message)
      return(FALSE)
    }
  )
}

safe_file_read <- function(file_path, sep = ";", header = TRUE) {
  # Safe file reading with error handling
  # Returns data or NULL on error

  tryCatch(
    {
      # Check if file exists
      if (!file.exists(file_path)) {
        warning("File does not exist:", file_path)
        return(NULL)
      }

      # Check read permissions
      if (!check_file_permissions(file_path, "read")) {
        warning("No read permission for file:", file_path)
        return(NULL)
      }

      # Check file size
      file_size <- file.info(file_path)$size
      if (file_size == 0) {
        warning("File is empty:", file_path)
        return(NULL)
      }

      # Read file
      data <- read.csv(file_path, sep = sep, header = header, stringsAsFactors = FALSE)

      cat("File read successfully:", file_path, "(", nrow(data), "rows )\n")

      return(data)
    },
    error = function(e) {
      warning("Error reading file:", file_path, "-", e$message)
      return(NULL)
    }
  )
}

# Minimaler Requirements-Check (vormals error_handling.R).
get_available_disk_space <- function(path = ".") {
  # Get available disk space for given path
  # Returns space in bytes

  tryCatch(
    {
      if (.Platform$OS.type == "windows") {
        # Windows-specific implementation
        system_info <- system(paste("dir", path), intern = TRUE)
        # Parse output for available space
        # This is a simplified implementation
        return(1e9) # Return 1GB as fallback
      } else {
        # Unix-like systems
        df_output <- system(paste("df", path), intern = TRUE)
        if (length(df_output) >= 2) {
          # Parse df output
          fields <- strsplit(df_output[2], "\\s+")[[1]]
          if (length(fields) >= 4) {
            available_kb <- as.numeric(fields[4])
            return(available_kb * 1024) # Convert to bytes
          }
        }
      }

      return(1e9) # Return 1GB as fallback
    },
    error = function(e) {
      warning("Error getting disk space:", e$message)
      return(1e9) # Return 1GB as fallback
    }
  )
}

validate_system_requirements <- function() {
  # Validate system requirements and dependencies
  # Returns validation results

  tryCatch(
    {
      requirements <- list(
        r_version = list(
          required = "4.0.0",
          actual = R.version.string,
          valid = as.numeric(R.version$major) >= 4
        ),
        packages = list(),
        environment = list(),
        system = list()
      )

      # Check required packages
      required_packages <- c("httr", "jsonlite", "tidyr")

      for (pkg in required_packages) {
        requirements$packages[[pkg]] <- list(
          required = TRUE,
          installed = requireNamespace(pkg, quietly = TRUE)
        )
      }

      # Check environment variables
      requirements$environment$RAPIDAPI_KEY <- list(
        required = TRUE,
        set = Sys.getenv("RAPIDAPI_KEY") != ""
      )

      # Check system resources
      requirements$system$disk_space <- list(
        required = "1GB",
        available = get_available_disk_space() > 1e9
      )

      # Overall validation
      all_valid <- all(
        requirements$r_version$valid,
        all(sapply(requirements$packages, function(p) p$installed)),
        all(sapply(requirements$environment, function(e) e$set)),
        all(sapply(requirements$system, function(s) s$available))
      )

      requirements$overall_valid <- all_valid

      return(requirements)
    },
    error = function(e) {
      return(list(
        overall_valid = FALSE,
        error = conditionMessage(e)
      ))
    }
  )
}

# Minimale Team-Count-Validierung (vormals input_validation.R); einziger
# Aufrufer ist process_season_transition() weiter unten in dieser Datei.
validate_team_count <- function(file_path) {
  # Validate that the team count is within expected range
  # Returns validation result

  tryCatch(
    {
      if (!file.exists(file_path)) {
        return(list(
          valid = FALSE,
          message = "File does not exist"
        ))
      }

      # Read the CSV file
      team_data <- read.csv(file_path, sep = ";", stringsAsFactors = FALSE)
      team_count <- nrow(team_data)

      # Die Spanne folgt der Registry statt fester Zahlen. Frueher standen
      # hier 56-62 (18+18+20 plus willkuerliche Toleranz).
      #
      # KORRIGIERT (Issue #195): Die Untergrenze war die kleinste EINZELNE
      # Liga, begruendet damit, der Saisonwechsel validiere auch
      # Einzelligen-Dateien. Das trifft nicht zu -- validate_team_count() hat
      # genau einen Aufrufer (season_processor.R), und der uebergibt immer
      # die ZUSAMMENGEFUEHRTE Liste. Mit 12 gegen 194 Soll-Teams fing die
      # Pruefung praktisch nichts: Ein Ergebnis, dem neun von zehn Ligen
      # fehlen, bestand sie.
      #
      # Genau das passiert, wenn api-football die Spielplaene der neuen
      # Saison noch nicht hinterlegt hat (ADR 0007): season_processor.R warnt
      # bei einer leeren Antwort nur und ueberspringt die Liga.
      #
      # Untergrenze ist die Summe der Sollstaerken der Ligen, die der
      # Saisonwechsel TATSAECHLICH ABRUFT -- mit Abschlag, weil eine Liga
      # unter ihrer Sollstaerke spielen kann (Insolvenz, Rueckzug).
      #
      # Nicht alle aktiven Ligen: Der Lauf stuetzt sich auf aufgezeichnete
      # API-Antworten und deckt heute nur 78/79/80 ab
      # (SEASON_TRANSITION_LEAGUES, season_validation.R). Gegen alle zehn
      # gemessen lehnte die Pruefung jeden gueltigen Lauf ab. Sobald die
      # Kassetten fuer die uebrigen Ligen da sind, waechst die Grenze von
      # selbst mit.
      #
      # Obergrenze bleibt die Summe aller je gefuehrten Ligen plus Reserve --
      # die TeamList behaelt historische Eintraege.
      geprueft <- if (exists("SEASON_TRANSITION_LEAGUES")) {
        SEASON_TRANSITION_LEAGUES
      } else {
        league_ids()
      }
      soll_aktiv <- sum(vapply(lapply(geprueft, league_teams_range),
                               function(r) r[[2]], integer(1)))
      min_teams <- as.integer(floor(soll_aktiv * 0.9))

      ranges <- lapply(league_ids(active_only = FALSE), league_teams_range)
      max_teams <- sum(vapply(ranges, function(r) r[[2]], integer(1))) * 2L

      if (team_count < min_teams) {
        return(list(
          valid = FALSE,
          message = sprintf(
            paste0("Too few teams: %d - expected at least %d (Sollstaerke ",
                   "aller aktiven Ligen: %d). Fehlen ganze Ligen, hat die ",
                   "API die Spielplaene der neuen Saison womoeglich noch ",
                   "nicht hinterlegt."),
            team_count, min_teams, soll_aktiv
          )
        ))
      }

      if (team_count > max_teams) {
        return(list(
          valid = FALSE,
          message = paste("Too many teams:", team_count,
                          "- expected at most", max_teams)
        ))
      }

      return(list(
        valid = TRUE,
        message = paste("Team count valid:", team_count, "teams"),
        team_count = team_count
      ))
    },
    error = function(e) {
      return(list(
        valid = FALSE,
        message = paste("Error reading file:", e$message)
      ))
    }
  )
}

process_season_transition <- function(source_season, target_season) {
  # Main processing pipeline
  # Coordinates all phases of transition

  tryCatch(
    {
      # Display welcome message
      display_welcome_message(source_season, target_season)

      # Validate inputs
      validate_season_range(source_season, target_season)

      # Check API access
      if (!validate_api_access()) {
        stop("API access validation failed")
      }

      # Get seasons to process
      seasons_to_process <- get_seasons_to_process(source_season, target_season)

      # Initialize tracking
      files_created <- c()
      seasons_processed <- 0

      # Process each season
      for (i in seq_along(seasons_to_process)) {
        season <- seasons_to_process[i]

        # Display progress
        display_progress(i, length(seasons_to_process))

        # Process single season
        season_result <- process_single_season(
          season,
          ifelse(i == 1, source_season, seasons_to_process[i - 1])
        )

        if (season_result$success) {
          files_created <- c(files_created, season_result$files_created)
          seasons_processed <- seasons_processed + 1

          # Display season summary
          display_season_summary(season, season_result$teams_processed, season_result$files_created)
        } else {
          # Handle season processing error
          recovery_choice <- display_error_recovery_options(
            season_result$error,
            paste("Season", season, "processing")
          )

          if (recovery_choice == "abort") {
            stop("Season processing aborted by user")
          } else if (recovery_choice == "retry") {
            # Retry current season
            i <- i - 1
            next
          } else if (recovery_choice == "skip") {
            # Skip current season and continue
            warning(paste("Skipping season", season, ":", season_result$error))
            next
          }
        }
      }

      # End-of-pipeline validation: assert the produced target season is well-formed
      final_validation <- validate_season_processing(target_season)
      if (!final_validation$valid) {
        stop(final_validation$message)
      }

      # Display completion message
      display_completion_message(seasons_processed, files_created)

      return(list(
        success = TRUE,
        seasons_processed = seasons_processed,
        files_created = files_created
      ))
    },
    error = function(e) {
      cat("Season transition failed:", e$message, "\n")
      return(list(
        success = FALSE,
        error = e$message
      ))
    }
  )
}

#' Process a single season transition
#'
#' Handles team discovery and ELO assignment for a single season
#'
#' @param season The target season year
#' @param previous_season The source season year
#' @return A list with success status, files created, teams processed, and any error
#' @export
process_single_season <- function(season, previous_season) {
  # Process transition for single season
  # Handles team discovery and ELO assignment

  tryCatch(
    {
      cat("\n=== Processing Season", season, "===\n")

      # Validate previous season is complete before processing
      cat("Validating previous season completion\n")
      if (!validate_season_completion(previous_season)) {
        stop(sprintf("Season %s not finished, no season transition possible.", previous_season))
      }

      # Load previous season team list for carryover
      cat("Loading previous season team data\n")
      previous_team_list <- load_previous_team_list(previous_season)

      # Get final ELOs from previous season
      cat("Calculating final ELOs for season", previous_season, "\n")
      final_elos <- calculate_final_elos(previous_season)

      # Calculate Liga3 relegation baseline
      cat("Calculating Liga3 relegation baseline\n")
      liga3_baseline <- calculate_liga3_relegation_baseline(previous_season)

      # Fetch teams for all leagues
      cat("Fetching team data from API\n")
      all_teams <- fetch_all_leagues_teams(season)

      if (is.null(all_teams) || length(all_teams) == 0) {
        return(list(
          success = FALSE,
          error = "No team data retrieved from API"
        ))
      }

      # Process each league
      files_created <- c()
      total_teams <- 0

      for (league_id in names(all_teams)) {
        league_teams <- all_teams[[league_id]]

        if (is.null(league_teams) || length(league_teams) == 0) {
          warning(paste("No teams for league", league_id))
          next
        }

        cat("Processing", get_league_name(league_id), "teams\n")

        # Process league teams
        processed_teams <- process_league_teams(
          league_teams,
          league_id,
          season,
          final_elos,
          liga3_baseline,
          previous_team_list
        )

        if (is.null(processed_teams)) {
          warning(paste("Failed to process league", league_id))
          next
        }

        # Generate CSV for this league's teams
        league_file <- generate_league_csv(processed_teams, league_id, season)

        if (!is.null(league_file)) {
          files_created <- c(files_created, league_file)
          total_teams <- total_teams + length(processed_teams)
        }
      }

      # Merge all leagues into single team list
      cat("Merging all leagues into single team list\n")
      merged_file <- merge_league_files(files_created, season)

      if (!is.null(merged_file)) {
        files_created <- c(files_created, merged_file)

        # Validate team count
        team_count_validation <- validate_team_count(merged_file)
        if (!team_count_validation$valid) {
          stop(team_count_validation$message)
        }
      } else {
        stop("Failed to merge league files")
      }

      return(list(
        success = TRUE,
        teams_processed = total_teams,
        files_created = files_created
      ))
    },
    error = function(e) {
      return(list(
        success = FALSE,
        error = e$message
      ))
    }
  )
}

#' Process teams for a league
#'
#' Thin orchestrator over resolve_team_history + build_*_team_record.
#' Refactored in issue #73 from a 120-line mixed-concern implementation.
#'
#' @param teams List of team records from API
#' @param league_id League ID ("78", "79", "80")
#' @param season Season year (currently unused; kept for caller signature stability)
#' @param final_elos Data frame of previous-season final ELOs
#' @param liga3_baseline Baseline ELO for Liga 3
#' @param previous_team_list Previous season's team list (or NULL on first season)
#' @param prompt_fn Function used to prompt for new-team data; default
#'   prompt_for_team_info. Tests can pass a stub closure to bypass I/O.
#' @return List of team records, or NULL on error
#' @export
process_league_teams <- function(teams, league_id, season, final_elos, liga3_baseline,
                                 previous_team_list = NULL,
                                 prompt_fn = prompt_for_team_info) {
  tryCatch(
    {
      processed_teams <- list()
      existing_short_names <- character()

      for (i in seq_along(teams)) {
        team <- teams[[i]]
        history <- resolve_team_history(team$id, previous_team_list, final_elos)

        processed_team <- if (history$state == "new") {
          build_new_team_record(
            team, league_id, liga3_baseline,
            existing_short_names, prompt_fn
          )
        } else {
          if (history$state == "carryover") {
            if (!is.null(history$team_elo)) {
              cat(
                "Team", team$id, "(", team$name, "): Using final ELO",
                round(history$team_elo, 2), "\n"
              )
            } else {
              cat(
                "Team", team$id, "(", team$name, "): Using baseline ELO",
                round(league_baseline_elo(league_id, liga3_baseline), 2), "\n"
              )
            }
          }
          build_carryover_team_record(
            team, history, league_id,
            liga3_baseline, existing_short_names
          )
        }

        existing_short_names <- c(existing_short_names, processed_team$short_name)
        processed_teams[[i]] <- processed_team
      }

      return(processed_teams)
    },
    error = function(e) {
      warning(paste("Error processing league", league_id, "teams:", e$message))
      return(NULL)
    }
  )
}

generate_league_csv <- function(teams, league_id, season) {
  # Generate CSV file for league teams
  # Returns file path or NULL on error

  tryCatch(
    {
      if (is.null(teams) || length(teams) == 0) {
        return(NULL)
      }

      # Convert to data frame format
      team_data <- data.frame(
        TeamID = sapply(teams, function(t) t$id),
        ShortText = sapply(teams, function(t) t$short_name),
        Promotion = sapply(teams, function(t) t$promotion_value),
        InitialELO = sapply(teams, function(t) t$initial_elo),
        stringsAsFactors = FALSE
      )

      # Generate temporary file name with unique league identifier
      temp_filename <- paste0("TeamList_", season, "_League", league_id, "_temp.csv")
      temp_file <- file.path("RCode", temp_filename)

      # Write CSV directly with league-specific name
      write.table(team_data, temp_file, sep = ";", row.names = FALSE, quote = FALSE)

      file_path <- temp_file

      return(file_path)
    },
    error = function(e) {
      warning(paste("Error generating CSV for league", league_id, ":", e$message))
      return(NULL)
    }
  )
}

merge_league_files <- function(league_files, season) {
  # Merge all league files into single team list
  # Returns merged file path or NULL on error

  tryCatch(
    {
      if (is.null(league_files) || length(league_files) == 0) {
        return(NULL)
      }

      # Filter only temp league files
      temp_league_files <- league_files[grepl("_League[0-9]+_temp\\.csv$", league_files)]

      if (length(temp_league_files) == 0) {
        warning("No temporary league files found to merge")
        return(NULL)
      }

      cat("Merging", length(temp_league_files), "league files\n")

      # Read all league files
      all_teams <- data.frame()

      for (file in temp_league_files) {
        if (file.exists(file)) {
          cat("Reading:", basename(file), "\n")
          league_data <- read.csv(file, sep = ";", stringsAsFactors = FALSE)

          if (!is.null(league_data) && nrow(league_data) > 0) {
            all_teams <- rbind(all_teams, league_data)
          }
        }
      }

      if (nrow(all_teams) == 0) {
        warning("No team data found in league files")
        return(NULL)
      }

      cat("Total teams to merge:", nrow(all_teams), "\n")

      # Remove duplicate TeamIDs (keep first occurrence)
      if (any(duplicated(all_teams$TeamID))) {
        duplicate_ids <- all_teams$TeamID[duplicated(all_teams$TeamID)]
        cat("Warning: Removing duplicate TeamIDs:", paste(unique(duplicate_ids), collapse = ", "), "\n")
        all_teams <- all_teams[!duplicated(all_teams$TeamID), ]
        cat("Teams after deduplication:", nrow(all_teams), "\n")
      }

      # Fix duplicate ShortTexts by appending numbers
      # Kuerzel-Vertrag pruefen, NICHT reparieren (ADR 0007).
      #
      # Hier stand eine stille Umbenennung: Jedes zweite Vorkommen eines
      # Kuerzels wurde durch ein Kunstkuerzel ersetzt ("FC1", "VF1"), einzige
      # Spur eine cat-Zeile, und der Lauf meldete Erfolg. Zwei Fehler in
      # einem: Sie prueft GLOBAL -- seit PR #186 traegt die TeamList rund
      # vierzig absichtlich gleiche Kuerzel ueber Ligagrenzen -- und sie
      # verdeckt den einen Fall, der wirklich einer ist.
      #
      # Ein echter Konflikt (zwei Teams derselben Liga) gehoert dem
      # Betreiber vorgelegt: Welcher Verein sein Kuerzel behaelt, ist eine
      # Frage der Vereinsidentitaet, keine der Reihenfolge in der Datei.
      verstoesse <- pruefe_kuerzel_vertrag(all_teams)
      if (length(verstoesse) > 0) {
        warning(sprintf(
          "Kuerzel-Vertrag verletzt, Saisonwechsel abgebrochen:\n  - %s",
          paste(verstoesse, collapse = "\n  - ")
        ))
        return(NULL)
      }

      # Sort by TeamID
      all_teams <- all_teams[order(all_teams$TeamID), ]

      # Generate final merged file
      cat("Generating final merged file for season", season, "\n")
      merged_file <- generate_team_list_csv(all_teams, season)

      if (is.null(merged_file)) {
        warning("Failed to generate merged file")
        return(NULL)
      }

      cat("Merged file created:", merged_file, "\n")

      # Clean up temporary league files
      for (file in temp_league_files) {
        if (file.exists(file)) {
          file.remove(file)
          cat("Removed temp file:", basename(file), "\n")
        }
      }

      return(merged_file)
    },
    error = function(e) {
      warning(paste("Error merging league files:", e$message))
      return(NULL)
    }
  )
}

validate_season_processing <- function(season, team_count_expected = 60) {
  # Validate season processing results
  # Returns validation status

  tryCatch(
    {
      # Check if team list file exists
      team_list_file <- paste0("RCode/TeamList_", season, ".csv")

      if (!file.exists(team_list_file)) {
        return(list(
          valid = FALSE,
          message = "Team list file not found"
        ))
      }

      # Verify file integrity
      integrity_check <- verify_csv_integrity(team_list_file)

      if (!integrity_check) {
        return(list(
          valid = FALSE,
          message = "Team list file integrity check failed"
        ))
      }

      # Read and validate data
      team_data <- safe_file_read(team_list_file)

      if (is.null(team_data)) {
        return(list(
          valid = FALSE,
          message = "Could not read team list file"
        ))
      }

      # Check team count
      if (nrow(team_data) < team_count_expected * 0.8) { # Allow 20% variance
        return(list(
          valid = FALSE,
          message = paste("Team count too low:", nrow(team_data), "expected ~", team_count_expected)
        ))
      }

      # Check for required columns
      required_columns <- c("TeamID", "ShortText", "Promotion", "InitialELO")
      missing_columns <- setdiff(required_columns, colnames(team_data))

      if (length(missing_columns) > 0) {
        return(list(
          valid = FALSE,
          message = paste("Missing columns:", paste(missing_columns, collapse = ", "))
        ))
      }

      # Check for duplicates
      if (any(duplicated(team_data$TeamID))) {
        return(list(
          valid = FALSE,
          message = "Duplicate team IDs found"
        ))
      }

      if (any(duplicated(team_data$ShortText))) {
        return(list(
          valid = FALSE,
          message = "Duplicate short names found"
        ))
      }

      return(list(
        valid = TRUE,
        message = "Season processing validation passed",
        teams = nrow(team_data)
      ))
    },
    error = function(e) {
      return(list(
        valid = FALSE,
        message = paste("Validation error:", e$message)
      ))
    }
  )
}
