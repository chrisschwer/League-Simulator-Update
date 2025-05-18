#' leagueSimulatorCPP
#' 
#' NOT WORKING
#' 
#' simulates the outcomes of a sports league based on ELO values
#' 
#' @param season table with schedule and ELO values
#' @param n number of iterations, defaults to 10000
#' @param modFactor Multiplier ("learning rate") for ELO adjustment
#' @param homeAdvantage Home field advantage in ELO points
#' @param AdjPoints vector containing an adjustment for the points scored per
#'   team
#' @param AdjGoals vector containing an adjustment for the goals scored per team
#' @param AdjGoalsAgainst vector containing an adjustment for the goals scored
#'   against per team
#' @param AdjGoalDiff vector containing an adjustment for the goal difference 
#'   per team
#' @param promotable vector of Booleans whether team may be promoted
#' @export 

leagueSimulatorCPP_Liga3 <- function (season, n = 10000,
                             modFactor = 20, homeAdvantage = 65,
                             numberTeams = 18,
                             adjPoints = rep_len(0, numberTeams), adjGoals = rep_len(0, numberTeams),
                             adjGoalsAgainst = rep_len(0, numberTeams), 
                             adjGoalDiff = rep_len(0, numberTeams),
                             promotable = rep_len(TRUE, numberTeams))
  
{
  library (parallel)
  # housekeeping
  numberTeams <- dim (season) [2] - 4
  numberGames <- dim (season) [1]
  ELOValues <- as.double(season [1, 5:dim (season) [2]])
  teamNames <- colnames (season) [5:dim (season) [2]]
  
  # replace team names in season with corresponding numbers
  season$TeamHeim <- factor (season$TeamHeim, levels = teamNames,
                             ordered = TRUE)
  season$TeamGast <- factor (season$TeamGast, levels = teamNames,
                             ordered = TRUE)
  season$TeamHeim <- as.integer (season$TeamHeim)
  season$TeamGast <- as.integer (season$TeamGast)
  
  schedule <- as.matrix (season[,1:4])
  teamNames <- colnames (season) [5:dim (season) [2]]
  
  results <- simulationsCPP (season = schedule, ELOValue = ELOValues,
                                        numberTeams = numberTeams, numberGames = numberGames,
                                        modFactor = modFactor, homeAdvantage = homeAdvantage,
                                        iterations = n,
                                        AdjPoints = adjPoints,
                                        AdjGoals = adjGoals,
                                        AdjGoalsAgainst = adjGoalsAgainst,
                                        AdjGoalDiff = adjGoalDiff)

  distribution <- table (results [,1], results [,2]) / n
  
  rankAverage <- tapply (results [,2], results [,1], sum)
  rankOrder <- order (rankAverage)
  
  distribution <- distribution [rankOrder, ]
  rownames(distribution) <- teamNames[as.integer(rownames(distribution))]

  


  distribution_total <- c(distribution, distribution_promotion) #' concatenate distributions for return
  return (distribution_total)

}