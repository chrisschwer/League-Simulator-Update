#' SpielCPP
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

SpielCPP <- function (ELOHeim, ELOGast, ToreHeim, ToreGast, 
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
  
  result <- SpielNichtSimulieren (ELOHeim + Heimvorteil, ELOGast,
                                  ToreHeim, ToreGast,
                                  ModFaktor, 0)
  
  return(result)
  
}