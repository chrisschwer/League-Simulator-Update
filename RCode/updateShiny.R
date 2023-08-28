updateShiny <- function (Ergebnis, Ergebnis2, Ergebnis3,  
                         Ergebnis3_Aufstieg = Ergebnis3,
                         directory = "/ShinyApp",
                         forceUpdate = TRUE) {
  
  library(rsconnect)
  
  account_name <- 'chrisschwer'
  account_token <- '3EBFA2C60C1438DAAA98FE4C0CAEC9AC'
  account_secret <- Sys.getenv("SHINYAPPS_IO_SECRET")

  rsconnect::setAccountInfo(name = account_name, token = account_token, secret = account_secret)

  curr_wd <- getwd()
  setwd(directory)
  save(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg, file = "data/Ergebnis.Rds")
  deployApp (appFiles = c ("app.R", "data/Ergebnis.Rds"), forceUpdate = forceUpdate)
  setwd(curr_wd)
}