updateShiny <- function (Ergebnis, Ergebnis2, Ergebnis3,  
                         Ergebnis3_Aufstieg = Ergebnis3,
                         directory = "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox-CSDataScience/Christoph Schwerdtfeger/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update/ShinyApp",
                         forceUpdate = TRUE) {
  
  # Ensure all required packages are loaded
  required_packages <- c("rsconnect", "shiny", "crayon", "ellipsis", "httpuv")
  
  for (pkg in required_packages) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
      stop(paste("Required package not available:", pkg, 
                 "\nPlease ensure all dependencies are installed in the Docker container"))
    }
  }
  
  library(rsconnect)
  
  # Use packrat mode to avoid "reproducible location" errors
  options(rsconnect.packrat = TRUE)
  
  account_name <- "chrisschwer"
  account_token <- "3EBFA2C60C1438DAAA98FE4C0CAEC9AC"
  account_secret <- Sys.getenv("SHINYAPPS_IO_SECRET")

  rsconnect::setAccountInfo(name = account_name, token = account_token, secret = account_secret)

  curr_wd <- getwd()
  message(sprintf("Changing to directory: %s", directory))
  setwd(directory)
  
  # Check if data directory exists
  if (!dir.exists("data")) {
    message("Creating data directory")
    dir.create("data", showWarnings = FALSE)
  }
  
  message("Saving simulation results to data/Ergebnis.Rds")
  save(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg, file = "data/Ergebnis.Rds")
  
  message("Deploying app to ShinyApps.io")
  deployApp (appFiles = c ("app.R", "data/Ergebnis.Rds"),
             appName = "FussballPrognosen", forceUpdate = forceUpdate)
  
  message("Deployment completed, returning to original directory")
  setwd(curr_wd)
}