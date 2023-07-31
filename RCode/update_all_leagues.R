# complete rerun of model

n <- 10000
saison <- "2023"
  
  # get fixtures via API
  fixturesBL <- retrieveResults(league = "78", season = saison)
  fixturesBL2 <- retrieveResults(league = "79", season = saison)
  fixturesLiga3 <- retrieveResults(league = "80", season = saison)
  
  # transform data
  BL <- transform_data(fixturesBL, TeamList)
  BL2 <- transform_data(fixturesBL2, TeamList)
  Liga3 <- transform_data(fixturesLiga3, TeamList)
  
  View(BL)
  View(BL2)
  View(Liga3)
  
  # Penalize second teams in Liga3, so that they cannot promote
  
  adjPoints_Liga3_Aufstieg <- rep(0, dim(Liga3)[2]-4) # initialize to 0
  
  for (i in 5:dim(Liga3)[2]) {
    team_short <- names(Liga3)[i]
    last_char_team <- substr(team_short, nchar(team_short), nchar(team_short))
    if (last_char_team == "2") {
      adjPoints_Liga3_Aufstieg[i-4] <- -50 # if team name ends in "2", penalize
    }
  }
  
  # Run the models
  Ergebnis <- leagueSimulatorCPP(BL, n = n)
  View(Ergebnis)
  Ergebnis2 <- leagueSimulatorCPP(BL2, n = n)
  View(Ergebnis2)
  Ergebnis3 <- leagueSimulatorCPP(Liga3, n = n)
  View(Ergebnis3)
  Ergebnis3_Aufstieg <- leagueSimulatorCPP(Liga3, n = n, adjPoints = adjPoints_Liga3_Aufstieg)
  View(Ergebnis3_Aufstieg)
  
  # update Shiny
  
  updateShiny(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg)
  

  
  