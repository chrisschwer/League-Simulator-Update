#' Spiel
#' 
#' Calculates new ELO values based on actual or simulated results
#' 
#' @param ELOHeim ELO value for home team
#' @param ELOGast ELO value for away team
#' @param ToreHeim Goals scored by home team
#' @param ToreGast Goals scored by away team
#' @param ModFaktor Multiplier ("learning rate") for ELO adjustment
#' @param Heimvorteil Home field advantage in ELO points
#' @param ToreSlope Additional goals per ELO delta point
#' @param ToreIntercept Average goals scored in a match between equals
#' 

Spiel <- function (ELOHeim, ELOGast, ToreHeim, ToreGast, 
                ZufallHeim, ZufallGast, 
                ModFaktor = 20, Heimvorteil = 65, 
                Simulieren = FALSE, 
                ToreSlope = 0.0017854953143549, ToreIntercept = 1.3218390804597700)

{
  # Berechnung des Delta der ELO-Stärke
  ELODelta <- ELOHeim + Heimvorteil - ELOGast
  
  if (Simulieren) 
    # Gegebenenfalls Zufallsergebnis berechnen
  {
    ToreHeimDurchschnitt <- max (ELODelta * ToreSlope + ToreIntercept,
                                 0.001)
    ToreGastDurchschnitt <- max ((-ELODelta) * ToreSlope 
                                 + ToreIntercept,
                                 0.001)
    ToreHeim <- qpois (p = ZufallHeim, lambda = ToreHeimDurchschnitt)
    ToreGast <- qpois (p = ZufallGast, lambda = ToreGastDurchschnitt)
  }
  
  # Absolutes ELODelta auf 400 kappen
  ELODelta <- min (max (ELODelta, -400), 400)
  
  # ELO-Prognose errechnen
  ELOProb <- 1 / (1 + 10 ^ (-ELODelta / 400))
  
  # Tor-Modifikator errechnen
  TD <- ToreHeim - ToreGast
  Ergebnis <- (sign (TD) + 1) / 2
  TorModifikator <- sqrt ( max ( abs (TD), 1) )
  
  
  # ELO-Modifikator errechnen
  ELOModifikator <- (Ergebnis - ELOProb) * TorModifikator * ModFaktor
  
  # Neue ELOWerte berechnen
  ELOHeim <- ELOHeim + ELOModifikator
  ELOGast <- ELOGast - ELOModifikator
  
  returnDF <- data.frame(ELOHeim = ELOHeim, ELOGast = ELOGast, 
                         ToreHeim = ToreHeim, ToreGast = ToreGast, 
                         ELOProb = ELOProb)
  # names(returnDF) <- c("ELOHeim", "ELOGast", "ToreHeim", "ToreGast",
  #                       "ELOProb")

  return (returnDF)
  
}