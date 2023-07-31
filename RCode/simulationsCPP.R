#' simulationsCPP
#' 
#' simulates n seasons and aggregates the results
#' 
#' @param season m x 4 matrix of matches, first and second column
#'   contain team number of home and away team respectively, third and 
#'   fourth column contain the goals scored 
#'   (or NA if match has not been played)
#' @param ELOValues vector of initial (pre-season) ELO values per team
#' @param modFactor Multiplier ("learning rate") for ELO adjustment
#' @param homeAdvantage Home field advantage in ELO points
#' @param iterations number of iterations
#' @param AdjPoints vector containing an adjustment for the points scored per
#'   team
#' @param AdjGoals vector containing an adjustment for the goals scored per team
#' @param AdjGoalsAgainst vector containing an adjustment for the goals scored
#'   against per team
#' @param AdjGoalDiff vector containing an adjustment for the goal difference 
#'   per team
#'   

simulationsCPP <- function (season, ELOValue,
                            numberTeams, numberGames,
                            modFactor = 20, homeAdvantage = 65, 
                            iterations = 10000,
                            AdjPoints = rep_len (0, numberTeams),
                            AdjGoals = rep_len (0, numberTeams),
                            AdjGoalsAgainst = rep_len (0, numberTeams),
                            AdjGoalDiff = rep_len (0, numberTeams))
  
{
  season_played <- season [!is.na (season [,3]),]
  season_played <- matrix (season_played, length (season_played) / 4, 4)
  season_unplayed <- season [is.na (season [,3]),]
  season_unplayed <- matrix (season_unplayed, length (season_unplayed) / 4, 4)
  games_played <- dim (season_played) [1]
  games_unplayed <- dim (season_unplayed) [1]
  
  # if games have been played, pre-calculate their results
  if (games_played > 0) {
    # calculate current ELO Values
    currentStandings <- SaisonSimulierenCPP (season_played, ELOValue,
                                             modFactor, homeAdvantage,
                                             numberTeams, games_played)
    # update ELO values
    ELOValue <- currentStandings [[2]]
    
    # calculate current league table, incl adjustments
    currentTable <- Tabelle (season_played,
                             numberTeams, games_played,
                             AdjPoints, AdjGoals, AdjGoalsAgainst, AdjGoalDiff)
    
    # extract new adjustments
    AdjPoints <- currentTable [,6]
    AdjGoals <- currentTable [,3]
    AdjGoalsAgainst <- currentTable [,4]
    AdjGoalDiff <- currentTable [,5]
  }
  
  # if unplayed games are left, simulate seasons
  
  if (games_unplayed > 0) {
    returnTable <- matrix(nrow = 0, ncol = 6)
    for (i in 1:iterations) {
      # simulate a single season
      iterResult <- SaisonSimulierenCPP (season_unplayed, ELOValue,
                                         modFactor, homeAdvantage,
                                         numberTeams, games_unplayed)
      # calculate its final table, including the previous results
      iterTable <- Tabelle (iterResult[[1]],
                            numberTeams, games_unplayed,
                            AdjPoints, AdjGoals, AdjGoalsAgainst, AdjGoalDiff)
      # append this seasons results to returnTable
      returnTable <- rbind (returnTable, iterTable)
    }
    return (returnTable)
  } else {
    # if no unplayed games, return the result of the played games
    return (currentTable)
  }
}
  