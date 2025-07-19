# Scheduler for updates to the results

# source C++ and R Code

Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
source("RCode/leagueSimulatorCPP.R")
source("RCode/prozent.R")
source("RCode/retrieveResults.R")
source("RCode/SaisonSimulierenCPP.R")
source("RCode/simulationsCPP.R")
source("RCode/SpielCPP.R")
source("RCode/Tabelle.R")
source("RCode/transform_data.R")
source("RCode/updateShiny.R")
source("RCode/update_all_leagues_loop.R")

season <- Sys.getenv("SEASON")
filename <- paste0("RCode/TeamList_", season, ".csv")

# Initialize skip to false
skip <- FALSE

repeat {

  # Current time in Berlin
  now <- Sys.time()
  tz <- "Europe/Berlin"

  # Helper to create POSIXct for today in Berlin
  today_str <- format(now, "%Y-%m-%d")
  make_time <- function(hm) {
    as.POSIXct(paste(today_str, hm), tz = tz)
  }

  # Define key times
  start_1445 <- make_time("14:45:00")
  end_2300 <- make_time("23:00:00")

  # Skip updates completely if past the last run of the day
  if (now > end_2300) {
    skip <- TRUE
  }

  if (now < start_1445) {
    loops <- 30
    initial_wait <- as.double(difftime(start_1445, now, units = "secs"))
    duration <- as.double(difftime(end_2300, start_1445, units = "mins"))
    if (!skip) {
      update_all_leagues_loop(duration = duration, initial_wait = initial_wait,
                              loops = loops, n = 10000, saison = season,
                              TeamList_file = filename)
    }
  } else {
    sched_times <- c("15:00:00", "15:30:00", "16:00:00",
                     "17:30:00", "18:00:00", "21:00:00", "23:00:00")
    for (t in sched_times) {
      run_time <- make_time(t)
      if (run_time > now) {
        wait <- as.double(difftime(run_time, Sys.time(), units = "secs"))
        if (wait > 0) Sys.sleep(wait)
        if (!skip) {
          update_all_leagues_loop(duration = 0, initial_wait = 0, loops = 1,
                                  n = 10000, saison = season,
                                  TeamList_file = filename)
        }
      }
    }
  }

  # Wait for 3 hours
  Sys.sleep(10800)

  # Reset skip to false
  skip <- FALSE
}

