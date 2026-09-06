# Update Scheduler with Rust Engine Integration
# Uses high-performance Rust simulation engine for 50-100x speedup

# Das taegliche Zeitfenster, in dem der Scheduler laeuft (Minuten seit
# Mitternacht, Berliner Zeit).
#
# Der Start liegt am fruehesten Anstoss: Die 2. Frauen-Bundesliga spielt zu
# 37 % vormittags, ab 11 Uhr -- an den Spielplaenen 2023-2025 gemessen. Das
# vorherige, deutlich spaetere Fenster haette diese Spiele erst nach Abpfiff
# erfasst.
#
# Als Konstanten, nicht als Literale: Vorher standen die Uhrzeiten an neun
# Stellen -- als Zahl, in Kommentaren und in Meldungstexten. Eine Verschiebung
# musste alle treffen, eine vergessene Stelle waere nicht aufgefallen.
SCHEDULE_START_MINUTES <- 11 * 60
SCHEDULE_END_MINUTES <- 23 * 60

# "11:00" / "23:00" fuer Meldungstexte, aus den Konstanten abgeleitet.
.format_schedule_time <- function(minutes) {
  sprintf("%02d:%02d", minutes %/% 60, minutes %% 60)
}

# Load configuration from environment

RAPIDAPI_KEY <- Sys.getenv("RAPIDAPI_KEY")
DURATION <- as.numeric(Sys.getenv("DURATION", "480"))
SEASON <- Sys.getenv("SEASON", format(Sys.Date(), "%Y"))
RUST_API_URL <- Sys.getenv("RUST_API_URL", "http://localhost:8080")

# Validate environment
if (RAPIDAPI_KEY == "") {
  stop("ERROR: RAPIDAPI_KEY environment variable not set")
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
source("RCode/update_all_leagues_loop.R")
source("RCode/checkAPILimits.R")

# Dynamic loop calculation based on current time
calculate_loops <- function() {
  current_time <- Sys.time()
  current_hour <- as.numeric(format(current_time, "%H"))
  current_minute <- as.numeric(format(current_time, "%M"))

  # Convert to minutes since midnight
  current_minutes <- current_hour * 60 + current_minute

  target_minutes <- SCHEDULE_END_MINUTES
  scheduled_start <- SCHEDULE_START_MINUTES

  # If before scheduled time, wait and run full duration
  if (current_minutes < scheduled_start) {
    wait_seconds <- (scheduled_start - current_minutes) * 60
    message(sprintf("Before %s - waiting %.1f hours for scheduled run time",
                    .format_schedule_time(scheduled_start), wait_seconds / 3600))
    Sys.sleep(wait_seconds)

    # After waiting: the full window
    minutes_available <- target_minutes - scheduled_start

    # Cap at DURATION if specified
    if (DURATION > 0 && minutes_available > DURATION) {
      minutes_available <- DURATION
    }

    ideal_loops <- floor(minutes_available / 2) + 1 # Every 2 minutes with Rust

    # Check API limits
    loops <- checkAPILimits(ideal_loops)
    message(sprintf("Planning to run %d loops (ideal: %d)", loops, ideal_loops))
    message(sprintf("Time available: %.1f minutes", minutes_available))

    return(list(loops = loops, initial_wait = 0, duration = minutes_available))
  }

  # After the window: wait until tomorrow
  if (current_minutes > target_minutes) {
    # Wait until tomorrow's window start
    minutes_until_midnight <- (24 * 60) - current_minutes
    minutes_after_midnight <- scheduled_start
    wait_minutes <- minutes_until_midnight + minutes_after_midnight

    message(sprintf("After %s - waiting %.1f hours until tomorrow's scheduled run",
                    .format_schedule_time(target_minutes), wait_minutes / 60))
    Sys.sleep(wait_minutes * 60)

    # After waiting: the full window
    minutes_available <- target_minutes - scheduled_start

    # Cap at DURATION if specified
    if (DURATION > 0 && minutes_available > DURATION) {
      minutes_available <- DURATION
    }

    ideal_loops <- floor(minutes_available / 2) + 1 # Every 2 minutes with Rust

    # Check API limits
    loops <- checkAPILimits(ideal_loops)
    message(sprintf("Planning to run %d loops (ideal: %d)", loops, ideal_loops))
    message(sprintf("Time available: %.1f minutes", minutes_available))

    return(list(loops = loops, initial_wait = 0, duration = minutes_available))
  }

  # Remaining time in today's window
  minutes_remaining <- target_minutes - current_minutes

  # Cap at DURATION if specified (but use actual remaining time)
  if (DURATION > 0 && minutes_remaining > DURATION) {
    minutes_remaining <- DURATION
  }

  # With Rust engine, we can run more frequent updates (every 2 minutes instead of 5)
  # due to 50-100x performance improvement
  ideal_loops <- floor(minutes_remaining / 2) + 1 # More frequent with Rust!

  # Cap at reasonable maximum
  if (ideal_loops > 200) ideal_loops <- 200

  # Check API limits and adjust loops if necessary
  loops <- checkAPILimits(ideal_loops)
  message(sprintf("Planning to run %d loops (ideal: %d)", loops, ideal_loops))
  message(sprintf("Time remaining: %.1f minutes", minutes_remaining))

  return(list(loops = loops, initial_wait = 0, duration = minutes_remaining))
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

  # Assert Rust availability at scheduler startup. Issue #77 Phase 1: there is
  # no in-process fallback to C++. A missing Rust server fails the scheduler
  # here so the operator sees the real cause; the loop's own assertion is the
  # second-tier guard against the server dying mid-run.
  source("RCode/rust_integration.R")
  if (!connect_rust_simulator()) {
    stop(sprintf(
      "Rust simulator not available at %s. Start the Rust server before invoking this scheduler.",
      RUST_API_URL
    ))
  }

  # Calculate optimal number of loops
  loop_config <- calculate_loops()

  # Run the update loop. Rust availability has already been asserted above.
  update_all_leagues_loop(
    duration = loop_config$duration, # Use actual time remaining, not DURATION
    loops = loop_config$loops,
    initial_wait = loop_config$initial_wait,
    n = 10000,
    saison = SEASON,
    TeamList_file = team_list_file
    # static_site_dir defaults to STATIC_SITE_DIR (see update_all_leagues_loop.R)
  )

  message("Scheduler completed successfully")
}

# Run with error handling
tryCatch(
  {
    main()
  },
  error = function(e) {
    message(sprintf("ERROR in scheduler: %s", e$message))
    quit(status = 1)
  }
)
