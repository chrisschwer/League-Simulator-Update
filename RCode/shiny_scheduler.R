# Shiny updater scheduler that runs during any league's active window

shiny_scheduler <- function(update_interval = 300,  # 5 minutes in seconds
                          results_dir = "RCode/league_results/") {
  
  # Source the update function
  source("RCode/update_shiny_from_files.R")
  
  # Define time windows for all leagues (same as in league_scheduler.R)
  time_windows <- list(
    BL = list(
      weekend = c(start = 17 + 20/60, end = 21 + 45/60),  # 17:20 - 21:45
      weekday = c(start = 19 + 30/60, end = 23 + 30/60)   # 19:30 - 23:30
    ),
    BL2 = list(
      weekend = c(start = 14 + 50/60, end = 23),          # 14:50 - 23:00
      weekday = c(start = 19 + 30/60, end = 23 + 30/60)   # 19:30 - 23:30
    ),
    Liga3 = list(
      weekend = c(start = 15 + 20/60, end = 22),          # 15:20 - 22:00
      weekday = c(start = 19 + 20/60, end = 23)           # 19:20 - 23:00
    )
  )
  
  # Function to check if any league is currently active
  is_any_league_active <- function() {
    current_time <- Sys.time()
    current_hour <- as.numeric(format(current_time, "%H")) + as.numeric(format(current_time, "%M"))/60
    current_dow <- as.numeric(format(current_time, "%w"))  # 0 = Sunday, 6 = Saturday
    
    # Determine if weekend or weekday
    is_weekend <- current_dow %in% c(0, 6)
    window_type <- ifelse(is_weekend, "weekend", "weekday")
    
    # Check each league
    for (league in names(time_windows)) {
      window <- time_windows[[league]][[window_type]]
      if (current_hour >= window$start && current_hour <= window$end) {
        return(TRUE)
      }
    }
    
    return(FALSE)
  }
  
  # Function to get next active window start time
  get_next_active_window <- function() {
    current_time <- Sys.time()
    current_hour <- as.numeric(format(current_time, "%H")) + as.numeric(format(current_time, "%M"))/60
    current_dow <- as.numeric(format(current_time, "%w"))
    
    min_wait <- Inf
    next_league <- ""
    next_window_time <- ""
    
    # Check all upcoming time slots in the next 7 days
    for (days_ahead in 0:6) {
      check_time <- current_time + days_ahead * 86400
      check_dow <- as.numeric(format(check_time, "%w"))
      is_weekend <- check_dow %in% c(0, 6)
      window_type <- ifelse(is_weekend, "weekend", "weekday")
      
      for (league in names(time_windows)) {
        window <- time_windows[[league]][[window_type]]
        
        if (days_ahead == 0) {
          # Today - check if we haven't passed the window yet
          if (current_hour < window$end) {
            if (current_hour < window$start) {
              # Window hasn't started yet today
              wait_hours <- window$start - current_hour
              if (wait_hours * 3600 < min_wait) {
                min_wait <- wait_hours * 3600
                next_league <- league
                next_window_time <- format(current_time + wait_hours * 3600, "%H:%M")
              }
            } else {
              # We're currently in a window
              min_wait <- 0
              next_league <- league
              next_window_time <- "now"
              break
            }
          }
        } else {
          # Future days
          wait_hours <- (days_ahead - 1) * 24 + (24 - current_hour) + window$start
          if (wait_hours * 3600 < min_wait) {
            min_wait <- wait_hours * 3600
            next_league <- league
            future_date <- format(check_time, "%A")
            next_window_time <- paste(future_date, sprintf("%02d:%02d", 
                                                          floor(window$start), 
                                                          round((window$start %% 1) * 60)))
          }
        }
      }
      
      if (min_wait == 0) break
    }
    
    return(list(wait_seconds = ceiling(min_wait), 
                league = next_league, 
                time = next_window_time))
  }
  
  # Main scheduling loop
  cat(paste0("[", Sys.time(), "] Starting Shiny scheduler (update interval: ", 
             update_interval, " seconds)\n"))
  
  while (TRUE) {
    if (is_any_league_active()) {
      # At least one league is active - update Shiny
      cat(paste0("[", Sys.time(), "] Shiny scheduler - Active window detected, updating app\n"))
      
      tryCatch({
        update_shiny_from_files(results_dir = results_dir)
      }, error = function(e) {
        cat(paste0("[", Sys.time(), "] Shiny scheduler - Error updating: ", e$message, "\n"))
      })
      
      # Wait for next update
      cat(paste0("[", Sys.time(), "] Shiny scheduler - Waiting ", 
                update_interval/60, " minutes until next update\n"))
      Sys.sleep(update_interval)
      
    } else {
      # No leagues active - wait until next window
      next_window <- get_next_active_window()
      
      cat(paste0("[", Sys.time(), "] Shiny scheduler - No active leagues. Next window: ", 
                next_window$league, " at ", next_window$time, 
                " (waiting ", round(next_window$wait_seconds/3600, 1), " hours)\n"))
      
      # Sleep in chunks to allow for graceful shutdown
      wait_time <- next_window$wait_seconds
      while (wait_time > 0) {
        sleep_chunk <- min(wait_time, 3600)  # Sleep max 1 hour at a time
        Sys.sleep(sleep_chunk)
        wait_time <- wait_time - sleep_chunk
        
        # Check if we should wake up early (in case system time changed)
        if (is_any_league_active()) {
          cat(paste0("[", Sys.time(), "] Shiny scheduler - League became active, resuming updates\n"))
          break
        }
      }
    }
  }
}