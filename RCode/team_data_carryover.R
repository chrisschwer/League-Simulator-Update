# Team Data Carryover Module
# Handles loading and matching team data from previous seasons

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

#' Load team list from previous season
#'
#' Loads TeamList for specified season, checking for most recent merged file first
#'
#' @param season The season year to load
#' @return Data frame of team data or NULL if not found
#' @export
load_previous_team_list <- function(season) {
  # Load TeamList for specified season
  # Returns data frame or NULL if not found
  # Checks for most recent merged file first, then original file

  tryCatch(
    {
      # First check for a merged file that might have been created during current processing
      merged_file <- paste0("RCode/TeamList_", season, ".csv")

      # Check if we have temporary files from current processing (indicates season is being processed)
      temp_files <- list.files(
        "RCode",
        pattern = paste0("TeamList_", season, "_League.*_temp\\.csv$"),
        full.names = TRUE
      )

      if (length(temp_files) > 0) {
        # We have temporary files, merge them and use the result
        cat("Found temporary files for season", season, ", merging for carryover\n")

        all_teams <- data.frame()
        for (file in temp_files) {
          if (file.exists(file)) {
            cat("Reading temporary file:", basename(file), "\n")
            league_data <- read.csv(file, sep = ";", stringsAsFactors = FALSE)
            if (!is.null(league_data) && nrow(league_data) > 0) {
              all_teams <- rbind(all_teams, league_data)
            }
          }
        }

        if (nrow(all_teams) > 0) {
          return(all_teams)
        }
      }

      # Fall back to original merged file
      if (!file.exists(merged_file)) {
        warning(paste("TeamList file not found for season", season))
        return(NULL)
      }

      # Read using safe file read
      team_data <- safe_file_read(merged_file, sep = ";", header = TRUE)

      if (is.null(team_data)) {
        warning(paste("Could not read TeamList for season", season))
        return(NULL)
      }

      # Validate required columns
      required_cols <- c("TeamID", "ShortText", "Promotion", "InitialELO")
      if (!all(required_cols %in% colnames(team_data))) {
        warning(paste("TeamList for season", season, "missing required columns"))
        return(NULL)
      }

      return(team_data)
    },
    error = function(e) {
      warning(paste("Error loading TeamList for season", season, ":", e$message))
      return(NULL)
    }
  )
}

#' Get existing team data from previous season
#'
#' Retrieves team data from previous season by TeamID
#'
#' @param team_id The team ID to look up
#' @param previous_team_list Data frame of previous season teams
#' @return List with short_name, promotion_value and region, or NULL
#' @export
get_existing_team_data <- function(team_id, previous_team_list) {
  # Get team data from previous season by TeamID
  # Returns list with short_name, promotion_value and region, or NULL

  if (is.null(previous_team_list) || nrow(previous_team_list) == 0) {
    return(NULL)
  }

  # Find team by ID
  team_row <- previous_team_list[previous_team_list$TeamID == team_id, ]

  if (nrow(team_row) == 0) {
    return(NULL)
  }

  # Die Stammregion ist die EINZIGE der drei Zusatzspalten, die aus der
  # Vorsaison kommen muss: League entsteht aus der verarbeiteten Liga, Name
  # steht in der API-Antwort. Region fuehrt keine von beiden -- ihre einzige
  # Quelle ist das Offline-Kalibrierungsskript (ADR 0003). Kennt die
  # Vorsaison sie nicht (TeamList bis 2025, vier Spalten), bleibt sie leer;
  # geraten wird nichts (Issue #195, Entscheidung aus PR #199).
  region <- if ("Region" %in% names(previous_team_list)) {
    as.character(team_row$Region[1])
  } else {
    ""
  }
  if (is.na(region)) {
    region <- ""
  }

  return(list(
    short_name = as.character(team_row$ShortText[1]),
    promotion_value = as.numeric(team_row$Promotion[1]),
    region = region
  ))
}
