#' Tabelle_presentation
#'
#' Calculates the league table in presentation format with match statistics.
#' This function wraps the core Tabelle function and provides additional
#' statistics including wins, draws, and losses for each team.
#'
#' @param season matrix m x 4 of completed games, containing number for home and
#'   away team in first two columns and respective goals in last two columns
#' @param numberTeams number of teams in league
#' @param numberGames number of games played, i.e. m (can be 0 for empty season)
#' @param AdjPoints vector containing an adjustment for the points scored per
#'   team
#' @param AdjGoals vector containing an adjustment for the goals scored per team
#' @param AdjGoalsAgainst vector containing an adjustment for the goals scored
#'   against per team
#' @param AdjGoalDiff vector containing an adjustment for the goal difference
#'   per team
#'
#' @return A dataframe with columns: Pl (position), Team (team ID),
#'   GP (games played), W (wins), D (draws), L (losses), Pts (points),
#'   GF (goals for), GA (goals against), GD (goal difference)
#'
#' @details
#' This function maintains backward compatibility with the core Tabelle function
#' while providing a more user-friendly output format. When no explicit goal
#' difference adjustments are applied (AdjGoalDiff = 0), the function ensures
#' that GD = GF - GA for consistency. NA values in the base table (which can
#' occur with partial seasons) are converted to 0.
#'
#' @seealso \code{\link{Tabelle}} for the core table calculation function
#'
#' @examples
#' # Create a simple season
#' season <- matrix(c(1, 2, 2, 1, 2, 1, 1, 1), nrow = 2, byrow = TRUE)
#' result <- Tabelle_presentation(season, 2, 2)
#' print(result)
#'
Tabelle_presentation <- function(season,
                                 numberTeams, numberGames,
                                 AdjPoints = rep_len(0, numberTeams),
                                 AdjGoals = rep_len(0, numberTeams),
                                 AdjGoalsAgainst = rep_len(0, numberTeams),
                                 AdjGoalDiff = rep_len(0, numberTeams)) {
  # Call the original Tabelle function to get the base table
  base_table <- Tabelle(
    season, numberTeams, numberGames,
    AdjPoints, AdjGoals, AdjGoalsAgainst, AdjGoalDiff
  )
  # Extract values from base table
  # Columns: [team_number, rank, goals_for, goals_against, goal_diff, points]
  team_numbers <- base_table[, 1]
  ranks <- base_table[, 2]
  goals_for <- base_table[, 3]
  goals_against <- base_table[, 4]
  goal_diff <- base_table[, 5]
  points <- base_table[, 6]

  # Handle NA values (can occur when numberGames > 0 but season has NA goals)
  goals_for[is.na(goals_for)] <- 0
  goals_against[is.na(goals_against)] <- 0
  goal_diff[is.na(goal_diff)] <- 0
  points[is.na(points)] <- 0

  # Check if goal difference adjustments were applied
  # If no explicit goal diff adjustments, recalculate GD for consistency
  if (all(AdjGoalDiff == 0)) {
    # Recalculate goal difference to maintain GD = GF - GA
    goal_diff <- goals_for - goals_against
  }

  # Calculate W/D/L for each team
  wins <- rep(0, numberTeams)
  draws <- rep(0, numberTeams)
  losses <- rep(0, numberTeams)
  games_played <- rep(0, numberTeams)

  if (numberGames > 0 && nrow(season) > 0) {
    played <- !is.na(season[, 3]) & !is.na(season[, 4])
    s <- season[played, , drop = FALSE]
    if (nrow(s) > 0) {
      games_played <- tabulate(s[, 1], nbins = numberTeams) +
        tabulate(s[, 2], nbins = numberTeams)
      home_win <- s[, 3] > s[, 4]
      away_win <- s[, 3] < s[, 4]
      draw <- s[, 3] == s[, 4]
      wins <- tabulate(s[home_win, 1], nbins = numberTeams) +
        tabulate(s[away_win, 2], nbins = numberTeams)
      losses <- tabulate(s[away_win, 1], nbins = numberTeams) +
        tabulate(s[home_win, 2], nbins = numberTeams)
      draws <- tabulate(s[draw, 1], nbins = numberTeams) +
        tabulate(s[draw, 2], nbins = numberTeams)
    }
  }
  # Create the presentation dataframe
  result_df <- data.frame(
    Pl = integer(numberTeams),
    Team = team_numbers,
    GP = games_played,
    W = wins,
    D = draws,
    L = losses,
    Pts = points,
    GF = goals_for,
    GA = goals_against,
    GD = goal_diff,
    stringsAsFactors = FALSE
  )
  # Sort by rank and assign position numbers
  # Order by rank from base_table (handles tiebreakers)
  sorted_indices <- order(ranks)
  result_df <- result_df[sorted_indices, ]
  result_df$Pl <- 1:numberTeams
  # Reset row names
  rownames(result_df) <- NULL

  return(result_df)
}
