# Update Scheduler with Rust Engine Integration
# Uses high-performance Rust simulation engine for 50-100x speedup

# Load configuration from environment
RAPIDAPI_KEY <- Sys.getenv("RAPIDAPI_KEY")
SHINYAPPS_IO_SECRET <- Sys.getenv("SHINYAPPS_IO_SECRET")
DURATION <- as.numeric(Sys.getenv("DURATION", "480"))
SEASON <- Sys.getenv("SEASON", format(Sys.Date(), "%Y"))
RUST_API_URL <- Sys.getenv("RUST_API_URL", "http://localhost:8080")

# Validate environment
if (RAPIDAPI_KEY == "") {
  stop("ERROR: RAPIDAPI_KEY environment variable not set")
}

if (SHINYAPPS_IO_SECRET == "") {
  stop("ERROR: SHINYAPPS_IO_SECRET environment variable not set")
}

# Auto-detect season if not set
if (SEASON == "") {
  current_month <- as.numeric(format(Sys.Date(), "%m"))
  current_year <- as.numeric(format(Sys.Date(), "%Y"))
  
  if (current_month >= 7) {
    SEASON <- as.character(current_year)
  } else {
    SEASON <- as.character(current_year - 1)
  }
  
  message(sprintf("Auto-detected season: %s", SEASON))
}

# Set up team list file
team_list_file <- sprintf("RCode/TeamList_%s.csv", SEASON)
if (!file.exists(team_list_file)) {
  # Try next year's file
  team_list_file_next <- sprintf("RCode/TeamList_%d.csv", as.numeric(SEASON) + 1)
  if (file.exists(team_list_file_next)) {
    team_list_file <- team_list_file_next
    message(sprintf("Using team list file: %s", team_list_file))
  } else {
    stop(sprintf("ERROR: Team list file not found: %s or %s", team_list_file, team_list_file_next))
  }
}

# Source required functions
source("RCode/update_all_leagues_loop_rust.R")
source("RCode/checkAPILimits.R")

# Dynamic loop calculation based on current time
calculate_loops <- function() {
  current_time <- Sys.time()
  current_hour <- as.numeric(format(current_time, "%H"))
  current_minute <- as.numeric(format(current_time, "%M"))
  
  # Convert to minutes since midnight
  current_minutes <- current_hour * 60 + current_minute
  
  # Target end time: 22:45 (1365 minutes)
  target_minutes <- 22 * 60 + 45
  
  # Scheduled start time: 14:45 (885 minutes)
  scheduled_start <- 14 * 60 + 45
  
  # If before scheduled time, wait and run full duration
  if (current_minutes < scheduled_start) {
    wait_seconds <- (scheduled_start - current_minutes) * 60
    message(sprintf("Before 14:45 - waiting %.1f hours for scheduled run time", wait_seconds / 3600))
    Sys.sleep(wait_seconds)
    
    # After waiting, recalculate for full run
    minutes_available <- DURATION
    ideal_loops <- floor(minutes_available / 2) + 1  # Every 2 minutes with Rust
    
    # Check API limits
    loops <- checkAPILimits(ideal_loops)
    message(sprintf("Planning to run %d loops (ideal: %d)", loops, ideal_loops))
    
    return(list(loops = loops, initial_wait = 0))
  }
  
  # If after 22:45, wait until tomorrow
  if (current_minutes > target_minutes) {
    # Calculate wait until tomorrow's 14:45
    minutes_until_midnight <- (24 * 60) - current_minutes
    minutes_after_midnight <- scheduled_start
    wait_minutes <- minutes_until_midnight + minutes_after_midnight
    
    message(sprintf("After 22:45 - waiting %.1f hours until tomorrow's scheduled run", wait_minutes / 60))
    Sys.sleep(wait_minutes * 60)
    
    # After waiting, run full duration
    ideal_loops <- floor(DURATION / 2) + 1  # Every 2 minutes with Rust
    
    # Check API limits
    loops <- checkAPILimits(ideal_loops)
    message(sprintf("Planning to run %d loops (ideal: %d)", loops, ideal_loops))
    
    return(list(loops = loops, initial_wait = 0))
  }
  
  # Calculate remaining time until 22:45
  minutes_remaining <- target_minutes - current_minutes
  
  # With Rust engine, we can run more frequent updates (every 2 minutes instead of 5)
  # due to 50-100x performance improvement
  ideal_loops <- floor(minutes_remaining / 2) + 1  # More frequent with Rust!
  
  # Cap at reasonable maximum
  if (ideal_loops > 200) ideal_loops <- 200
  
  # Check API limits and adjust loops if necessary
  loops <- checkAPILimits(ideal_loops)
  message(sprintf("Planning to run %d loops (ideal: %d)", loops, ideal_loops))
  
  return(list(loops = loops, initial_wait = 0))
}

# Main execution
main <- function() {
  message("===========================================")
  message("League Simulator Scheduler with Rust Engine")
  message("===========================================")
  message(sprintf("Season: %s", SEASON))
  message(sprintf("Team list: %s", team_list_file))
  message(sprintf("Rust API: %s", RUST_API_URL))
  message("")
  
  # Test Rust connection
  source("RCode/rust_integration.R")
  rust_available <- connect_rust_simulator()
  
  if (!rust_available) {
    message("WARNING: Rust engine not available, will use C++ fallback")
    message("Performance will be significantly reduced")
  }
  
  # Calculate optimal number of loops
  loop_config <- calculate_loops()
  
  # Run the update loop with Rust engine
  update_all_leagues_loop_rust(
    duration = DURATION,
    loops = loop_config$loops,
    initial_wait = loop_config$initial_wait,
    n = 10000,  # Can handle more iterations with Rust
    saison = SEASON,
    TeamList_file = team_list_file,
    shiny_directory = "ShinyApp",
    use_rust = rust_available
  )
  
  message("Scheduler completed successfully")
}

# Run with error handling
tryCatch({
  main()
}, error = function(e) {
  message(sprintf("ERROR in scheduler: %s", e$message))
  quit(status = 1)
})