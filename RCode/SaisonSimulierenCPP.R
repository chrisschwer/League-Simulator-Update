#' SaisonSimulierenCPP
#' 
#' Simulates a single season based on the provided schedule and 
#' initial ELO values
#' 
#' @param Spielplan n x 4 matrix of matches, first and second column
#'   contain team number of home and away team respectively, third and 
#'   fourth column contain the goals scored 
#'   (or NA if match has not been played)
#' @param ELOWerte vector of length m, containing initial ELO values
#' @param ModFaktor Multiplier ("learning rate") for ELO adjustment
#' @param Heimvorteil Home field advantage in ELO points
#' @param AnzahlTeams number of teams in league n
#' @param AnzahlSpiele number of matches m
#

SaisonSimulierenCPP <- function (Spielplan, ELOWerte,
                                 ModFaktor = 20, Heimvorteil = 65,
                                 AnzahlTeams, AnzahlSpiele)
  
  
{
  # Handle empty season case
  if (AnzahlSpiele == 0) {
    return (list(Spielplan, ELOWerte))
  }
  
  for (i in 1:AnzahlSpiele) 
  {
    # Heim und Gastmannschaft ermitteln
    TeamHeim <- Spielplan [i, 1]
    TeamGast <- Spielplan [i, 2]
    
    # Ergebnis ermitteln
    ToreHeim <- Spielplan [i, 3]
    ToreGast <- Spielplan [i, 4]
    
    # Klären, ob Simulieren notwendig
    Simulieren <- is.na (ToreHeim)
    
    #ELO-Werte ermitteln
    ELOHeim <- ELOWerte[TeamHeim]
    ELOGast <- ELOWerte[TeamGast]
    
    # ELO-Werte nach Spieltag und ggf. Ergebnis ermitteln
    if (Simulieren) 
    {
      Zufall1 <- runif(1)
      Zufall2 <- runif(1)
      Ergebnis <- SpielCPP (ELOHeim = ELOHeim, ELOGast = ELOGast,
                            ZufallHeim = Zufall1, ZufallGast = Zufall2,
                            ModFaktor = ModFaktor,
                            Heimvorteil = Heimvorteil,
                            Simulieren = TRUE)
    }
    
    else
    {
      Ergebnis <- SpielCPP (ELOHeim = ELOHeim, ELOGast = ELOGast,
                            ToreHeim = ToreHeim, ToreGast = ToreGast,
                            ModFaktor = ModFaktor,
                            Heimvorteil = Heimvorteil)
    }
    
    # Tore übertragen
    Spielplan [i, 3] <- Ergebnis[3]
    Spielplan [i, 4] <- Ergebnis[4]
    
    # Anpasen der ELO-Werte
    ELOWerte[TeamHeim] <- Ergebnis[1]
    ELOWerte[TeamGast] <- Ergebnis[2]
    
  }
  
  return (list(Spielplan, ELOWerte))
  
}