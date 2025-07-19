# League-specific scheduler that handles time windows and API limits

league_scheduler <- function(league = "BL", 
                           saison = "2024",
                           TeamList_file = "RCode/TeamList_2024.csv",
                           output_dir = "RCode/league_results/",
                           max_daily_calls = 30) {
  
  # Validate league parameter
  if (!league %in% c("BL", "BL2", "Liga3")) {
    stop("League must be one of: 'BL', 'BL2', 'Liga3'")
  }
  
  # Source the update function
  source("RCode/update_league.R")
  
  # Define time windows for each league
  # Times are in 24-hour format as decimal hours (e.g., 17.5 = 17:30)
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
  
  # Function to check if current time is within window
  is_within_window <- function(league_name) {
    current_time <- Sys.time()
    current_hour <- as.numeric(format(current_time, "%H")) + as.numeric(format(current_time, "%M"))/60
    current_dow <- as.numeric(format(current_time, "%w"))  # 0 = Sunday, 6 = Saturday
    
    # Determine if weekend or weekday
    is_weekend <- current_dow %in% c(0, 6)
    window_type <- ifelse(is_weekend, "weekend", "weekday")
    
    # Get appropriate time window
    window <- time_windows[[league_name]][[window_type]]
    
    # Check if within window
    return(current_hour >= window$start && current_hour <= window$end)
  }
  
  # Function to calculate wait time until next window
  get_wait_until_window <- function(league_name) {
    current_time <- Sys.time()
    current_hour <- as.numeric(format(current_time, "%H")) + as.numeric(format(current_time, "%M"))/60
    current_dow <- as.numeric(format(current_time, "%w"))
    
    # Check all upcoming time slots in the next 7 days
    min_wait <- Inf
    
    for (days_ahead in 0:6) {
      check_time <- current_time + days_ahead * 86400  # Add days in seconds
      check_dow <- as.numeric(format(check_time, "%w"))
      is_weekend <- check_dow %in% c(0, 6)
      window_type <- ifelse(is_weekend, "weekend", "weekday")
      window <- time_windows[[league_name]][[window_type]]
      
      if (days_ahead == 0) {
        # Today - check if we haven't passed the window yet
        if (current_hour < window$end) {
          if (current_hour < window$start) {
            # Window hasn't started yet today
            wait_hours <- window$start - current_hour
            min_wait <- min(min_wait, wait_hours * 3600)
          } else {
            # We're currently in the window
            min_wait <- 0
            break
          }
        }
      } else {
        # Future days - window starts at beginning
        wait_hours <- (days_ahead - 1) * 24 + (24 - current_hour) + window$start
        min_wait <- min(min_wait, wait_hours * 3600)
      }
    }
    
    return(ceiling(min_wait))  # Return wait time in seconds
  }
  
  # Function to calculate remaining time in current window
  get_remaining_window_time <- function(league_name) {
    current_time <- Sys.time()
    current_hour <- as.numeric(format(current_time, "%H")) + as.numeric(format(current_time, "%M"))/60
    current_dow <- as.numeric(format(current_time, "%w"))
    
    is_weekend <- current_dow %in% c(0, 6)
    window_type <- ifelse(is_weekend, "weekend", "weekday")
    window <- time_windows[[league_name]][[window_type]]
    
    if (current_hour >= window$start && current_hour <= window$end) {
      return((window$end - current_hour) * 3600)  # Convert hours to seconds
    }
    return(0)
  }
  
  # Main scheduling loop
  daily_calls <- 0
  last_reset_date <- Sys.Date()
  
  cat(paste0("[", Sys.time(), "] Starting ", league, " scheduler\n"))
  
  while (TRUE) {
    # Reset daily counter if new day
    current_date <- Sys.Date()
    if (current_date > last_reset_date) {
      daily_calls <- 0
      last_reset_date <- current_date
      cat(paste0("[", Sys.time(), "] ", league, " - Daily counter reset\n"))
    }
    
    # Check if within time window
    if (is_within_window(league)) {
      # Check if under daily limit
      if (daily_calls < max_daily_calls) {
        remaining_window <- get_remaining_window_time(league)
        remaining_calls <- max_daily_calls - daily_calls
        
        if (remaining_calls > 0 && remaining_window > 0) {
          # Calculate optimal spacing for remaining calls
          # Add some buffer time (5 minutes) to ensure we don't exceed window
          effective_window <- max(remaining_window - 300, 60)  # At least 1 minute
          interval <- effective_window / remaining_calls
          
          # Run single update with loops=1
          cat(paste0("[", Sys.time(), "] ", league, " - Running update (", 
                     daily_calls + 1, "/", max_daily_calls, ")\n"))
          
          tryCatch({
            update_league(league = league,
                         loops = 1,  # Single update
                         initial_wait = 0,
                         saison = saison,
                         TeamList_file = TeamList_file,
                         output_dir = output_dir)
            
            daily_calls <- daily_calls + 1
            
          }, error = function(e) {
            cat(paste0("[", Sys.time(), "] ", league, " - Error: ", e$message, "\n"))
          })
          
          # Wait until next update (if still within window and under limit)
          if (daily_calls < max_daily_calls && remaining_window > interval) {
            wait_time <- min(interval, remaining_window - 60)  # Leave buffer at end
            cat(paste0("[", Sys.time(), "] ", league, 
                      " - Waiting ", round(wait_time/60, 1), " minutes until next update\n"))
            Sys.sleep(wait_time)
          } else {
            # No more updates today in this window
            cat(paste0("[", Sys.time(), "] ", league, 
                      " - Completed updates for current window\n"))
          }
        }
      } else {
        # Daily limit reached
        cat(paste0("[", Sys.time(), "] ", league, 
                  " - Daily limit reached (", max_daily_calls, " calls)\n"))
      }
    }
    
    # If not in window or daily limit reached, wait until next window
    if (!is_within_window(league) || daily_calls >= max_daily_calls) {
      wait_time <- get_wait_until_window(league)
      
      # If daily limit reached and next window is today, wait until tomorrow
      if (daily_calls >= max_daily_calls && wait_time < 86400) {
        tomorrow <- Sys.Date() + 1
        wait_time <- as.numeric(difftime(
          as.POSIXct(paste(tomorrow, "00:00:00")), 
          Sys.time(), 
          units = "secs"
        )) + get_wait_until_window(league)
      }
      
      cat(paste0("[", Sys.time(), "] ", league, 
                " - Waiting ", round(wait_time/3600, 1), 
                " hours until next window\n"))
      
      # Sleep in chunks to allow for graceful shutdown
      while (wait_time > 0) {
        sleep_chunk <- min(wait_time, 3600)  # Sleep max 1 hour at a time
        Sys.sleep(sleep_chunk)
        wait_time <- wait_time - sleep_chunk
      }
    }
  }
}