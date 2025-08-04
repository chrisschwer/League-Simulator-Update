# Test version that runs immediately with just 1 loop for testing

# Get the project root directory
project_root <- "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox-CSDataScience/Christoph Schwerdtfeger/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update"

# Source required functions with local paths
source(file.path(project_root, "RCode/update_all_leagues_loop.R"))
source(file.path(project_root, "RCode/checkAPILimits.R"))

# Get season
season <- Sys.getenv("SEASON", "2025")

message("League Simulator Test - Running immediately with 1 loop")
message(sprintf("Season: %s", season))

# Get file path
teamlist_file <- file.path(project_root, paste0("RCode/TeamList_", season, ".csv"))

# Run ONE simulation loop for testing
message("Starting test simulation with 1 loop")

tryCatch({
  update_all_leagues_loop(
    duration = 480,
    loops = 1,  # Just 1 loop for testing
    initial_wait = 0,
    n = 10000,
    saison = season,
    TeamList_file = teamlist_file,
    shiny_directory = file.path(project_root, "ShinyApp")
  )
  message("Test simulation completed successfully")
}, error = function(e) {
  message(sprintf("ERROR in simulation: %s", e$message))
  message("Error details:")
  print(e)
})