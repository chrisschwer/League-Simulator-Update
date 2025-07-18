# Team Configuration Loader
# Loads team information from JSON configuration files to bypass interactive prompts

# Load team configuration from JSON file
load_team_config <- function(config_file) {
  # Validate file exists
  if (!file.exists(config_file)) {
    stop("Configuration file not found: ", config_file)
  }
  
  # Read and parse JSON
  config_content <- tryCatch({
    jsonlite::read_json(config_file)
  }, error = function(e) {
    stop("Failed to parse JSON configuration: ", e$message)
  })
  
  # Validate structure
  if (!is.list(config_content)) {
    stop("Configuration must be a JSON object")
  }
  
  # Extract new teams if present
  new_teams <- config_content$new_teams
  if (is.null(new_teams)) {
    return(list())
  }
  
  # Validate and transform team data
  team_list <- list()
  
  for (team_name in names(new_teams)) {
    team_data <- new_teams[[team_name]]
    
    # Validate required fields
    if (!all(c("short_name", "initial_elo") %in% names(team_data))) {
      stop("Team '", team_name, "' missing required fields: short_name, initial_elo")
    }
    
    # Validate short name
    short_name <- as.character(team_data$short_name)
    if (nchar(short_name) != 3) {
      stop("Team '", team_name, "' has invalid short_name: must be exactly 3 characters")
    }
    
    # Validate ELO
    initial_elo <- as.numeric(team_data$initial_elo)
    if (is.na(initial_elo) || initial_elo < 0 || initial_elo > 3000) {
      stop("Team '", team_name, "' has invalid initial_elo: must be between 0 and 3000")
    }
    
    # Get promotion value (default to 0)
    promotion_value <- as.numeric(team_data$promotion_value %||% 0)
    
    # Get league (if specified)
    league <- as.character(team_data$league %||% "")
    
    # Add to list
    team_list[[team_name]] <- list(
      name = team_name,
      short_name = toupper(short_name),
      initial_elo = initial_elo,
      promotion_value = promotion_value,
      league = league
    )
  }
  
  return(team_list)
}

# Check if team configuration is available
has_team_config <- function() {
  # Check for --config argument
  args <- commandArgs(trailingOnly = TRUE)
  config_index <- which(args == "--config")
  
  if (length(config_index) > 0 && length(args) > config_index) {
    return(TRUE)
  }
  
  # Check for environment variable
  if (Sys.getenv("TEAM_CONFIG_FILE") != "") {
    return(TRUE)
  }
  
  # Check for default config file
  default_configs <- c(
    "team_config.json",
    "config/team_config.json",
    "RCode/team_config.json"
  )
  
  for (config_path in default_configs) {
    if (file.exists(config_path)) {
      return(TRUE)
    }
  }
  
  return(FALSE)
}

# Get team configuration file path
get_team_config_path <- function() {
  # Check for --config argument
  args <- commandArgs(trailingOnly = TRUE)
  config_index <- which(args == "--config")
  
  if (length(config_index) > 0 && length(args) > config_index) {
    return(args[config_index + 1])
  }
  
  # Check for environment variable
  env_config <- Sys.getenv("TEAM_CONFIG_FILE")
  if (env_config != "") {
    return(env_config)
  }
  
  # Check for default config file
  default_configs <- c(
    "team_config.json",
    "config/team_config.json",
    "RCode/team_config.json"
  )
  
  for (config_path in default_configs) {
    if (file.exists(config_path)) {
      return(config_path)
    }
  }
  
  return(NULL)
}

# Get team info from config or prompt
get_team_info_with_config <- function(team_name, league, existing_short_names = NULL) {
  # Check if we have configuration
  config_path <- get_team_config_path()
  
  if (!is.null(config_path)) {
    # Try to load from config
    tryCatch({
      team_config <- load_team_config(config_path)
      
      # Check if this team is in config
      if (team_name %in% names(team_config)) {
        team_info <- team_config[[team_name]]
        
        # Validate against existing short names
        if (!is.null(existing_short_names) && 
            team_info$short_name %in% existing_short_names) {
          stop("Short name '", team_info$short_name, 
               "' already exists for team '", team_name, "'")
        }
        
        cat("Loaded team information from config for:", team_name, "\n")
        return(team_info)
      }
    }, error = function(e) {
      cat("Warning: Failed to load team from config:", e$message, "\n")
      cat("Falling back to interactive prompts...\n")
    })
  }
  
  # Fall back to interactive prompts
  if (exists("prompt_for_team_info") && is.function(prompt_for_team_info)) {
    return(prompt_for_team_info(team_name, league, existing_short_names))
  } else {
    stop("No team configuration found and interactive prompts not available")
  }
}

# Create example configuration file
create_example_team_config <- function(output_file = "team_config_example.json") {
  example_config <- list(
    new_teams = list(
      "Energie Cottbus" = list(
        short_name = "ENE",
        initial_elo = 1046,
        promotion_value = 0,
        league = "3. Liga"
      ),
      "Alemannia Aachen" = list(
        short_name = "AAC",
        initial_elo = 1050,
        promotion_value = 0,
        league = "3. Liga"
      ),
      "Bayern Munich II" = list(
        short_name = "FC2",
        initial_elo = 1040,
        promotion_value = -50,
        league = "3. Liga"
      )
    )
  )
  
  jsonlite::write_json(
    example_config, 
    output_file, 
    pretty = TRUE,
    auto_unbox = TRUE
  )
  
  cat("Example configuration created:", output_file, "\n")
}

# Define null coalesce operator if not already defined
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}
