updateShiny <- function (Ergebnis, Ergebnis2, Ergebnis3,  
                         Ergebnis3_Aufstieg = Ergebnis3,
                         directory = "/ShinyApp",
                         forceUpdate = TRUE) {
  
  library(rsconnect)
  
  curr_wd <- getwd()
  setwd(directory)
  save(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg, file = "data/Ergebnis.Rds")
  deployApp (appFiles = c ("app.R", "data/Ergebnis.Rds"), forceUpdate = forceUpdate)
  setwd(curr_wd)
}