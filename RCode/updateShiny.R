updateShiny <- function (Ergebnis, Ergebnis2, Ergebnis3,  
                         Ergebnis3_Aufstieg = Ergebnis3,
                         directory = "/ShinyApp",
                         forceUpdate = TRUE) {
  
  library(rsconnect)
  
  account_name <- Sys.getenv("SHINYAPPS_IO_ACCOUNT")
  account_token <- Sys.getenv("SHINYAPPS_IO_TOKEN")
  account_secret <- Sys.getenv("SHINYAPPS_IO_SECRET")

  rsconnect::setAccountInfo(name = account_name, token = account_token, secret = account_secret)

  curr_wd <- getwd()
  setwd(directory)
  save(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg, file = "data/Ergebnis.Rds")
  deployApp (appFiles = c ("app.R", "data/Ergebnis.Rds"), forceUpdate = forceUpdate)
  setwd(curr_wd)
}