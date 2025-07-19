# Single league update function that saves results to file

update_league <- function(league = "BL", duration = 480, loops = 31, initial_wait = 0,
                         n = 10000, saison = "2023", 
                         TeamList_file = "/RCode/TeamList_2023.csv",
                         output_dir = "/RCode/league_results/")
{
  
  # Validate league parameter
  if (!league %in% c("BL", "BL2", "Liga3")) {
    stop("League must be one of: 'BL', 'BL2', 'Liga3'")
  }
  
  # Map league to API code
  league_codes <- list(
    "BL" = "78",
    "BL2" = "79", 
    "Liga3" = "80"
  )
  
  league_code <- league_codes[[league]]
  
  if (loops > 1) {
    waittime <- duration * 60 / (loops - 1) # time between loops
  } else {
    waittime <- 0
  }
  
  # Wait initial_wait before starting
  Sys.sleep(initial_wait)
  
  # FT value helps only recalculating if new games finished
  # Initialize if it does not exist
  FT_current <- 0
  
  # source C++ and R Code
  Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
  source("RCode/leagueSimulatorCPP.R")
  source("RCode/prozent.R")
  source("RCode/retrieveResults.R")
  source("RCode/SaisonSimulierenCPP.R")
  source("RCode/simulationsCPP.R")
  source("RCode/SpielCPP.R")
  source("RCode/Tabelle.R")
  source("/RCode/transform_data.R")
  
  # Import Team Data
  TeamList <- read.csv(TeamList_file, sep=";")
  
  # Create output directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # Start main loop
  for (i in 1:loops) {
    
    # reset simulation_executed
    simulation_executed <- FALSE
    
    # get fixtures via API
    fixtures <- retrieveResults(league = league_code, season = saison)
    
    # New count of games
    FT_new <- sum(fixtures$fixture$status$short == "FT")
    
    # transform data
    league_data <- transform_data(fixtures, TeamList)
    
    # Run the model if new games finished
    if (FT_current != FT_new) {
      
      # Special handling for Liga3 - need both regular and promotion results
      if (league == "Liga3") {
        # Penalize second teams in Liga3, so that they cannot promote
        adjPoints_Liga3_Aufstieg <- rep(0, dim(league_data)[2]-4) # initialize to 0
        
        for (j in 5:dim(league_data)[2]) {
          team_short <- names(league_data)[j]
          last_char_team <- substr(team_short, nchar(team_short), nchar(team_short))
          if (last_char_team == "2") {
            adjPoints_Liga3_Aufstieg[j-4] <- -50 # if team name ends in "2", penalize
          }
        }
        
        # Run both simulations for Liga3
        Ergebnis <- leagueSimulatorCPP(league_data, n = n)
        Ergebnis_Aufstieg <- leagueSimulatorCPP(league_data, n = n, 
                                                adjPoints = adjPoints_Liga3_Aufstieg)
        
        # Save both results
        saveRDS(Ergebnis, file = file.path(output_dir, paste0("Ergebnis_", league, ".Rds")))
        saveRDS(Ergebnis_Aufstieg, file = file.path(output_dir, paste0("Ergebnis_", league, "_Aufstieg.Rds")))
        
        # Log update
        cat(paste0("[", Sys.time(), "] ", league, " simulation completed and saved\n"))
        
      } else {
        # Regular simulation for BL and BL2
        Ergebnis <- leagueSimulatorCPP(league_data, n = n)
        
        # Save results
        saveRDS(Ergebnis, file = file.path(output_dir, paste0("Ergebnis_", league, ".Rds")))
        
        # Log update
        cat(paste0("[", Sys.time(), "] ", league, " simulation completed and saved\n"))
      }
      
      FT_current <- FT_new
      simulation_executed <- TRUE
      
    } else {
      cat(paste0("[", Sys.time(), "] ", league, " - No new games finished, skipping simulation\n"))
    }
    
    # If not the last loop, wait
    if (i < loops) {
      Sys.sleep(waittime)
    }
  }
  
  return(invisible(NULL))
}