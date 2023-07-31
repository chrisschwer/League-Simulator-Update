#' Tabelle
#' 
#' Calculates the league table based on a complete season
#' 
#' @param season matrix m x 4 of completed games, containing number for home and
#'   away team in first two columns and respective goals in last two columns
#' @param numberTeams number of teams in league
#' @param numberGames number of games played, i.e. m
#' @param AdjPoints vector containing an adjustment for the points scored per
#'   team
#' @param AdjGoals vector containing an adjustment for the goals scored per team
#' @param AdjGoalsAgainst vector containing an adjustment for the goals scored
#'   against per team
#' @param AdjGoalDiff vector containing an adjustment for the goal difference 
#'   per team
#'   

Tabelle <- function (season, 
                     numberTeams, numberGames,
                     AdjPoints = rep_len (0, numberTeams),
                     AdjGoals = rep_len (0, numberTeams),
                     AdjGoalsAgainst = rep_len (0, numberTeams),
                     AdjGoalDiff = rep_len (0, numberTeams))
  
{
  # Create matrix to collect the results, prefilled with the priors
  A <- matrix (c (AdjPoints, AdjGoals, AdjGoalsAgainst, AdjGoalDiff),
               numberTeams, 4)
  
  # Splitting the data into vectors
  homeTeam <- season [,1]
  awayTeam <- season [,2]
  homeGoals <- season [,3]
  awayGoals <- season [,4]
  
  # Calculating results
  goalDiff <- homeGoals - awayGoals
  # result in ELO logic, i.e. 0 is loss, 0.5 draw and 1 is win
  result <- (sign (goalDiff) + 1) / 2 
  # result in 3-point system
  pointsHome <- floor (3 * result)
  pointsAway <- floor (3 - 3 * result)
  
  # concatenating first the home, then the away teams
  team <- c (homeTeam, awayTeam)
  goals <- c (homeGoals, awayGoals)
  goalsAgainst <- c (awayGoals, homeGoals)
  goalDiff <- c (goalDiff, -goalDiff)
  points <- c (pointsHome, pointsAway)
  
  # aggregating the data
  points <- tapply (points, team, sum) + AdjPoints
  goals <- tapply (goals, team, sum) + AdjGoals
  goalsAgainst <- tapply (goalsAgainst, team, sum) + AdjGoalsAgainst
  goalDiff <- tapply (goalDiff, team, sum) + AdjGoalDiff
  
  # calculating a rankscore
  rankScore <- 10000 * points + 100 * goalDiff + goals
  
  # putting it all together
  
  returnTabelle <- matrix (c (as.integer(names(points)),
                              rankScore, goals, goalsAgainst,
                              goalDiff, points),
                           numberTeams, 6)
  
  # adding the rank number
  returnTabelle[,2] <- 1 + numberTeams - rank (returnTabelle [,2],
                                               ties.method = "max")
    
  return (returnTabelle)
    
}

