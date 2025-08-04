# Simple daily scheduler for League Simulator - LOCAL VERSION
# Runs once daily at 14:45 Berlin time with appropriate loop counts

# Get the project root directory
project_root <- "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox-CSDataScience/Christoph Schwerdtfeger/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update"

# Source required functions with local paths
source(file.path(project_root, "RCode/update_all_leagues_loop.R"))
source(file.path(project_root, "RCode/checkAPILimits.R"))

# Helper function to calculate seconds until next 14:45 Berlin time
wait_until_1445 <- function() {
  now <- Sys.time()
  berlin_now <- as.POSIXlt(now, tz = "Europe/Berlin")
  
  # Target time: today at 14:45
  target <- as.POSIXlt(now, tz = "Europe/Berlin")
  target$hour <- 14
  target$min <- 45
  target$sec <- 0
  
  # If we're past 14:45 today, target tomorrow
  if (berlin_now >= target) {
    target <- target + 86400  # Add one day
  }
  
  wait_seconds <- as.numeric(difftime(target, berlin_now, units = "secs"))
  
  message(sprintf("Current time: %s", format(berlin_now, "%Y-%m-%d %H:%M:%S", tz = "Europe/Berlin")))
  message(sprintf("Next run at: %s", format(target, "%Y-%m-%d %H:%M:%S", tz = "Europe/Berlin")))
  message(sprintf("Waiting %.0f seconds (%.1f hours)", wait_seconds, wait_seconds/3600))
  
  Sys.sleep(wait_seconds)
}

# Get season - use smart default based on current month
season <- Sys.getenv("SEASON")
if (season == "") {
  current_month <- as.numeric(format(Sys.Date(), "%m"))
  current_year <- as.numeric(format(Sys.Date(), "%Y"))
  
  if (current_month >= 7) {
    season <- as.character(current_year)
  } else {
    season <- as.character(current_year - 1)
  }
  
  message(sprintf("No SEASON set, using %s based on current date", season))
}

# Main scheduler loop
message("League Simulator Simple Scheduler Starting (LOCAL VERSION)")
message(sprintf("Season: %s", season))

repeat {
  now <- Sys.time()
  berlin_now <- as.POSIXlt(now, tz = "Europe/Berlin")
  current_hour <- berlin_now$hour
  current_min <- berlin_now$min
  
  # Helper to create POSIXct for today in Berlin
  today_str <- format(berlin_now, "%Y-%m-%d", tz = "Europe/Berlin")
  make_time <- function(hm) {
    as.POSIXct(paste(today_str, hm), tz = "Europe/Berlin")
  }
  
  # Define end time (22:45)
  end_time <- make_time("22:45:00")
  
  # Determine number of loops based on current time
  if (current_hour < 14 || (current_hour == 14 && current_min < 45)) {
    # Before 14:45 - wait and calculate loops for full window
    message("Before 14:45 - waiting for scheduled run time")
    wait_until_1445()
    # After waiting, we'll be at 14:45, so 8 hours = 480 minutes until 22:45
    ideal_loops <- 96  # 480 minutes / 5 minutes per loop
  } else if (as.POSIXct(berlin_now) < end_time) {
    # Between 14:45 and 22:45 - calculate loops for remaining time
    minutes_to_end <- as.numeric(difftime(end_time, as.POSIXct(berlin_now), units = "mins"))
    minutes_remaining <- min(minutes_to_end, 480)  # Cap at 480 minutes
    ideal_loops <- max(1, floor(minutes_remaining / 5))
    message(sprintf("Time remaining until 22:45: %.1f minutes", minutes_remaining))
  } else {
    # After 22:45 - wait until tomorrow
    message("After 22:45 - waiting for tomorrow's scheduled run")
    wait_until_1445()
    ideal_loops <- 96  # Will run full window tomorrow
    # Update current time after waiting
    now <- Sys.time()
    berlin_now <- as.POSIXlt(now, tz = "Europe/Berlin")
  }
  
  # Check API limits and adjust loops if necessary
  loops <- checkAPILimits(ideal_loops)
  message(sprintf("Planning to run %d loops (ideal: %d)", loops, ideal_loops))
  
  # Get file path - use local path
  teamlist_file <- file.path(project_root, paste0("RCode/TeamList_", season, ".csv"))
  
  # Calculate actual duration based on current time and end time
  if (exists("minutes_remaining")) {
    actual_duration <- minutes_remaining
  } else {
    actual_duration <- 480  # Default for full window
  }
  
  # Run the simulation
  message(sprintf("Starting simulation with %d loops over %.1f minutes at %s", 
                  loops, actual_duration, format(as.POSIXct(berlin_now), "%Y-%m-%d %H:%M:%S", tz = "Europe/Berlin")))
  
  tryCatch({
    update_all_leagues_loop(
      duration = actual_duration,  # Pass actual remaining time
      loops = loops,
      initial_wait = 0,
      n = 10000,
      saison = season,
      TeamList_file = teamlist_file,
      shiny_directory = file.path(project_root, "ShinyApp")  # Local path
    )
    message("Simulation completed successfully")
  }, error = function(e) {
    message(sprintf("ERROR in simulation: %s", e$message))
  })
  
  # After completion or error, check if we should continue today or wait until tomorrow
  now <- Sys.time()
  berlin_now <- as.POSIXlt(now, tz = "Europe/Berlin")
  
  if (as.POSIXct(berlin_now) >= end_time) {
    # Past 22:45, wait until tomorrow
    message("Waiting for next scheduled run")
    wait_until_1445()
  } else {
    # Still time today, continue with next iteration
    message("Continuing with next iteration today")
  }
}