# Production simulation loop. Calls the Rust REST API exclusively
# (issue #77 Phase 1: no in-process C++ fallback).

update_all_leagues_loop <- function(duration = 480, loops = 31, initial_wait = 0,
                                    n = 10000, saison = "2023",
                                    TeamList_file = "RCode/TeamList_2023.csv",
                                    shiny_directory = "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox-CSDataScience/Christoph Schwerdtfeger/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update/ShinyApp") {

  if (loops > 1) {
    waittime <- duration * 60 / (loops - 1) # time between loops
  } else {
    waittime <- 0
  }

  # Wait initial_wait before starting
  Sys.sleep(initial_wait)

  # FT values help only recalculating if new games finished
  # Initialize if they do not exist
  if (!exists("FT_BL")) {FT_BL <- 0}
  if (!exists("FT_BL2")) {FT_BL2 <- 0}
  if (!exists("FT_Liga3")) {FT_Liga3 <- 0}

  # Source the Rust REST client and assert the server is reachable before doing
  # any work. Phase 1 of issue #77: the production loop now requires Rust;
  # there is no in-process fallback to C++. A missing/broken Rust server fails
  # the scheduler at startup so the operator sees the real problem instead of
  # silent engine substitution.
  source("RCode/rust_integration.R")
  if (!connect_rust_simulator()) {
    stop(sprintf(
      "Rust simulator not available at %s. Check that the Rust server is running before starting the scheduler.",
      Sys.getenv("RUST_API_URL", "http://localhost:8080")
    ))
  }
  
  # Common R functions needed regardless of engine
  source("RCode/prozent.R")
  source("RCode/retrieveResults.R")
  source("RCode/Tabelle.R")
  source("RCode/transform_data.R")
  source("RCode/updateShiny.R")

  # Import Team Data
  TeamList <- read.csv(TeamList_file, sep=";")

  # Initialize result objects to ensure they exist
  Ergebnis <- NULL
  Ergebnis2 <- NULL
  Ergebnis3 <- NULL
  Ergebnis3_Aufstieg <- NULL

  # Start main loop
  for (i in 1:loops) {
    
    message(sprintf("\n=== Starting loop %d of %d at %s ===", i, loops, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
    
    # reset simulation_executed
    simulation_executed <- FALSE
    
    # get fixtures via API
    fixturesBL <- retrieveResults(league = "78", season = saison)
    fixturesBL2 <- retrieveResults(league = "79", season = saison)
    fixturesLiga3 <- retrieveResults(league = "80", season = saison)
    
    # Check if API calls failed
    if (is.null(fixturesBL) || is.null(fixturesBL2) || is.null(fixturesLiga3)) {
      message(sprintf("Loop %d: ERROR - One or more API calls failed. Skipping this iteration.", i))
      next
    }
    
    # New count of games
    FT_BL_new <-  sum(fixturesBL$fixture$status$short=="FT")
    FT_BL2_new <-  sum(fixturesBL2$fixture$status$short=="FT")
    FT_Liga3_new <-  sum(fixturesLiga3$fixture$status$short=="FT")
    
    # transform data
    BL <- transform_data(fixturesBL, TeamList)
    BL2 <- transform_data(fixturesBL2, TeamList)
    Liga3 <- transform_data(fixturesLiga3, TeamList)
    
    # Penalize second teams in Liga3, so that they cannot promote
    adjPoints_Liga3_Aufstieg <- rep(0, dim(Liga3)[2]-4) # initialize to 0
    
    for (j in 5:dim(Liga3)[2]) {
      team_short <- names(Liga3)[j]
      last_char_team <- substr(team_short, nchar(team_short), nchar(team_short))
      if (last_char_team == "2") {
        adjPoints_Liga3_Aufstieg[j-4] <- -50 # if team name ends in "2", penalize
      }
    }
    
    # On first iteration (i == 1), always run all simulations to ensure objects exist
    if (FT_BL != FT_BL_new || i == 1) {
      message(sprintf("Loop %d: Simulating Bundesliga with %d simulations (Rust engine)",
                      i, n))
      Ergebnis <- leagueSimulatorRust(BL, n = n)
      FT_BL <- FT_BL_new
      simulation_executed <- TRUE
    }
    
    if (FT_BL2 != FT_BL2_new || i == 1) {
      message(sprintf("Loop %d: Simulating 2. Bundesliga with %d simulations (Rust engine)",
                      i, n))
      Ergebnis2 <- leagueSimulatorRust(BL2, n = n)
      FT_BL2 <- FT_BL2_new
      simulation_executed <- TRUE
    }
    
    if (FT_Liga3 != FT_Liga3_new || i == 1) {
      message(sprintf("Loop %d: Simulating 3. Liga with %d simulations (Rust engine)",
                      i, n))
      Ergebnis3 <- leagueSimulatorRust(Liga3, n = n)
      FT_Liga3 <- FT_Liga3_new
      
      # calculate promotion table
      Ergebnis3_Aufstieg <- leagueSimulatorRust(Liga3, n = n, adjPoints = adjPoints_Liga3_Aufstieg)
      simulation_executed <- TRUE
    }
    
    # Update Shiny if simulations have been executed
    if (simulation_executed && !is.null(Ergebnis)) {
      message(sprintf("Loop %d: Updating Shiny app with new results", i))
      updateShiny(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg, directory = shiny_directory)
    } else {
      message(sprintf("Loop %d: No updates needed, skipping Shiny deployment", i))
    }
    
    # Wait if not last iteration
    if (i < loops) {
      message(sprintf("Loop %d: Waiting %.1f minutes until next update...", i, waittime/60))
      Sys.sleep(waittime)
    }
  }
  
  message(sprintf("\n=== Completed all %d loops at %s ===", loops, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
}