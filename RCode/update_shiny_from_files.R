# Function to read league results from files and update Shiny app

update_shiny_from_files <- function(results_dir = "/RCode/league_results/") {
  
  # Source the updateShiny function
  source("/RCode/updateShiny.R")
  
  # Define expected result files
  result_files <- list(
    BL = file.path(results_dir, "Ergebnis_BL.Rds"),
    BL2 = file.path(results_dir, "Ergebnis_BL2.Rds"),
    Liga3 = file.path(results_dir, "Ergebnis_Liga3.Rds"),
    Liga3_Aufstieg = file.path(results_dir, "Ergebnis_Liga3_Aufstieg.Rds")
  )
  
  # Check if all required files exist
  missing_files <- names(result_files)[!file.exists(unlist(result_files))]
  
  if (length(missing_files) > 0) {
    stop(paste("Missing result files:", paste(missing_files, collapse = ", ")))
  }
  
  # Read all result files
  cat(paste0("[", Sys.time(), "] Reading league results from files...\n"))
  
  Ergebnis <- readRDS(result_files$BL)
  Ergebnis2 <- readRDS(result_files$BL2)
  Ergebnis3 <- readRDS(result_files$Liga3)
  Ergebnis3_Aufstieg <- readRDS(result_files$Liga3_Aufstieg)
  
  cat(paste0("[", Sys.time(), "] All results loaded successfully\n"))
  
  # Update Shiny app with all results
  cat(paste0("[", Sys.time(), "] Updating Shiny app...\n"))
  
  updateShiny(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg)
  
  cat(paste0("[", Sys.time(), "] Shiny app updated successfully\n"))
  
  return(invisible(NULL))
}