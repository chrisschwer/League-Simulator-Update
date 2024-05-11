# Scheduler for updates to the results

# source C++ and R Code

Rcpp::sourceCpp("/RCode/SpielNichtSimulieren.cpp")
source("/RCode/leagueSimulatorCPP.R")
source("/RCode/prozent.R")
source("/RCode/retrieveResults.R")
source("/RCode/SaisonSimulierenCPP.R")
source("/RCode/simulationsCPP.R")
source("/RCode/SpielCPP.R")
source("/RCode/Tabelle.R")
source("/RCode/transform_data.R")
source("/RCode/updateShiny.R")
source("/RCode/update_all_leagues_loop.R")

# Initialize loops to low number in case of restart
# and regular_loops to normal value

loops <- 3
regular_loops <- 31

# Initialize skip to false
skip <- FALSE


repeat {
    
    # Calculate the time until 11:30 p.m. in seconds

    current_time <- Sys.time()
    target_time <- as.POSIXct(paste(format(current_time, "%Y-%m-%d"), 
                                    "23:30:00"), tz = "Europe/Berlin")
    time_diff <- as.double(difftime(target_time, 
                                    current_time, 
                                    tz = "Europe/Berlin"
                                    units = "secs"))

    # Calculate the maximum duration
    max_duration <- min(time_diff / 60, 480)

    # If time is later than 22:30, skip the update
    if (time_diff < 0) {
        skip <- TRUE
    }
  
    # Calculate the time until 14:45 in seconds

    current_time <- Sys.time()
    target_time <- as.POSIXct(paste(format(current_time, "%Y-%m-%d"), 
                                    "14:45:00"), tz = "Europe/Berlin")
    time_diff <- as.double(difftime(target_time, 
                                    current_time,
                                    tz = "Europe/Berlin" 
                                    units = "secs"))

    initial_wait <- max(time_diff, 0)

    # If time is before 14:45, set loops to regular_loops

    if (time_diff > 0) {
        loops <- regular_loops
    }

    # Run updates unless skip is TRUE

    if (!skip) {
        update_all_leagues_loop(duration = max_duration, 
                                initial_wait = initial_wait, loops = loops,
                                n = 10000, saison = "2023", 
                                TeamList_file = "/RCode/TeamList_2023.csv")
    }

    # Wait for 3 hours

    Sys.sleep(10800)

    # Reset skip to false

    skip <- FALSE

}

