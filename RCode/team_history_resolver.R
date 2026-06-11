#' Resolve a team's history across previous-season data sources
#'
#' Looks up team_id first in previous_team_list (current-processing carryover
#' source) and falls back to final_elos (previous-season ELO source). Returns
#' a discriminated state the caller dispatches on.
#'
#' Extracted from process_league_teams in issue #73 to make existence
#' resolution testable in isolation.
#'
#' @param team_id Integer team ID to resolve.
#' @param previous_team_list Data frame with columns TeamID, ShortText, Promotion,
#'   InitialELO. May be NULL on the first season.
#' @param final_elos Data frame with columns TeamID, FinalELO. May be NULL or
#'   empty on the first season.
#' @return List with three slots:
#'   \describe{
#'     \item{state}{One of "carryover", "fallback", "new".}
#'     \item{previous_data}{Named list (short_name, promotion_value) when
#'       state == "carryover"; NULL for "fallback" and "new".}
#'     \item{team_elo}{Numeric ELO from final_elos when available, else NULL.}
#'   }
#' @export
resolve_team_history <- function(team_id, previous_team_list, final_elos) {
  previous_data <- if (!is.null(previous_team_list)) {
    get_existing_team_data(team_id, previous_team_list)
  } else {
    NULL
  }

  elo_match <- if (!is.null(final_elos) && nrow(final_elos) > 0) {
    final_elos$FinalELO[final_elos$TeamID == team_id]
  } else {
    integer(0)
  }
  team_elo <- if (length(elo_match) > 0) elo_match[1] else NULL

  state <- if (!is.null(previous_data)) {
    "carryover"
  } else if (!is.null(team_elo)) {
    "fallback"
  } else {
    "new"
  }

  list(
    state = state,
    previous_data = previous_data,
    team_elo = team_elo
  )
}
