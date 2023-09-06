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


repeat {
    
    # Calculate the time until 11:30 p.m. in seconds

    current_time <- Sys.time()
    target_time <- as.POSIXct(paste(format(current_time, "%Y-%m-%d"), 
                                    "23:30:30"), tz = "Europe/Berlin")
    time_diff <- difftime(target_time, current_time, units = "secs")

    # Calculate the maximum duration
    max_duration <- min(time_diff / 60, 480)
  
    # Calculate the time until 14:45 in seconds

    current_time <- Sys.time()
    target_time <- as.POSIXct(paste(format(current_time, "%Y-%m-%d"), 
                                    "14:45:00"), tz = "Europe/Berlin")
    time_diff <- difftime(target_time, current_time, units = "secs")

    initial_wait <- max(time_diff, 0)

    update_all_leagues_loop(duration = max_duration, 
                            initial_wait = initial_wait, loops = 31)

    # Wait for another 12 hours

    Sys.sleep (43200)

}

