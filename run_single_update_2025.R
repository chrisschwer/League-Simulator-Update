#!/usr/bin/env Rscript

# Script to run a single update for season 2025
# Usage: Rscript run_single_update_2025.R

cat("=== Running Single Update for Season 2025 ===\n\n")

# Get the directory where this script is located
script_dir <- dirname(normalizePath(sub("--file=", "", 
                      grep("--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))

# Set working directory to project root
setwd(script_dir)

# Create modified version of update function with relative paths
update_all_leagues_single <- function(n = 10000, saison = "2025", 
                                     TeamList_file = "RCode/TeamList_2025.csv") {
  
  # Source C++ and R Code with relative paths
  Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
  source("RCode/leagueSimulatorCPP.R")
  source("RCode/leagueSimulatorCPP_Liga3.R")  # Add Liga3 version if needed
  source("RCode/prozent.R")
  source("RCode/retrieveResults.R")
  source("RCode/SaisonSimulierenCPP.R")
  source("RCode/simulationsCPP.R")
  source("RCode/SpielCPP.R")
  source("RCode/Tabelle.R")
  source("RCode/transform_data.R")
  source("RCode/updateShiny.R")
  
  # Import Team Data
  TeamList <- read.csv(TeamList_file, sep=";")
  cat("Loaded", nrow(TeamList), "teams for season", saison, "\n")
  
  # Get fixtures via API
  cat("\nFetching fixtures from API...\n")
  fixturesBL <- retrieveResults(league = "78", season = saison)
  fixturesBL2 <- retrieveResults(league = "79", season = saison)
  fixturesLiga3 <- retrieveResults(league = "80", season = saison)
  
  # Count finished games
  FT_BL <-  sum(fixturesBL$fixture$status$short=="FT")
  FT_BL2 <-  sum(fixturesBL2$fixture$status$short=="FT")
  FT_Liga3 <-  sum(fixturesLiga3$fixture$status$short=="FT")
  
  cat("Bundesliga: ", FT_BL, "finished matches\n")
  cat("2. Bundesliga: ", FT_BL2, "finished matches\n")
  cat("3. Liga: ", FT_Liga3, "finished matches\n")
  
  # Transform data
  cat("\nTransforming data...\n")
  BL <- transform_data(fixturesBL, TeamList)
  BL2 <- transform_data(fixturesBL2, TeamList)
  Liga3 <- transform_data(fixturesLiga3, TeamList)
  
  # Penalize second teams in Liga3, so that they cannot promote
  adjPoints_Liga3_Aufstieg <- rep(0, dim(Liga3)[2]-4) # initialize to 0
  
  for (i in 5:dim(Liga3)[2]) {
    team_short <- names(Liga3)[i]
    # Check TeamList for promotion value
    team_row <- TeamList[TeamList$ShortText == team_short, ]
    if (nrow(team_row) > 0 && team_row$Promotion[1] == -50) {
      adjPoints_Liga3_Aufstieg[i-4] <- -50 # penalize second teams
    }
  }
  
  # Run the simulations
  cat("\nRunning", n, "simulations for each league...\n")
  
  cat("Simulating Bundesliga...\n")
  Ergebnis <- leagueSimulatorCPP(BL, n = n)
  
  cat("Simulating 2. Bundesliga...\n")
  Ergebnis2 <- leagueSimulatorCPP(BL2, n = n)
  
  cat("Simulating 3. Liga...\n")
  Ergebnis3 <- leagueSimulatorCPP(Liga3, n = n)
  
  # Special simulation for Liga3 promotion (excluding second teams)
  if (file.exists("RCode/leagueSimulatorCPP_Liga3.R")) {
    Ergebnis3_Aufstieg <- leagueSimulatorCPP_Liga3(Liga3, n = n, 
                                                    adjPoints = adjPoints_Liga3_Aufstieg)
  } else {
    Ergebnis3_Aufstieg <- leagueSimulatorCPP(Liga3, n = n, 
                                             adjPoints = adjPoints_Liga3_Aufstieg)
  }
  
  # Update Shiny
  cat("\nUpdating Shiny app with results...\n")
  updateShiny(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg)
  
  cat("\nSimulation complete!\n")
}

# Check for required packages
required_packages <- c("Rcpp", "httr", "jsonlite")
missing_packages <- required_packages[!required_packages %in% installed.packages()[,"Package"]]

if (length(missing_packages) > 0) {
  cat("Missing required packages:", paste(missing_packages, collapse = ", "), "\n")
  cat("Install with: install.packages(c(", paste0('"', missing_packages, '"', collapse = ", "), "))\n")
  quit(status = 1)
}

# Check API key
if (Sys.getenv("RAPIDAPI_KEY") == "") {
  cat("\nERROR: RAPIDAPI_KEY environment variable not set!\n")
  cat("Set it with: export RAPIDAPI_KEY='your_key_here'\n")
  quit(status = 1)
}

# Run the update
tryCatch({
  update_all_leagues_single()
  cat("\n✅ Update completed successfully!\n")
  cat("Check the Shiny app for the updated prognoses.\n")
}, error = function(e) {
  cat("\n❌ Error during update:\n")
  cat(e$message, "\n")
  quit(status = 1)
})