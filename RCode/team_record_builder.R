#' Build a team record from resolved history (carryover or fallback path)
#'
#' Pure function: takes a team's API row, its resolved history (from
#' resolve_team_history), and the league context, and returns the final
#' team record. Handles both "carryover" (use previous_data verbatim) and
#' "fallback" (generate fresh short_name, default promotion_value) cases.
#'
#' Extracted from process_league_teams in issue #73 to make record
#' construction testable without stubs.
#'
#' @param team Named list from API: id, name, is_second_team.
#' @param history Result of resolve_team_history; state must be
#'   "carryover" or "fallback".
#' @param league_id League identifier ("78", "79", "80").
#' @param liga3_baseline Baseline ELO for Liga 3.
#' @param existing_short_names Character vector of already-assigned short
#'   names; used to uniquify newly-generated names in fallback state.
#' @return Named list: id, name, short_name, initial_elo, promotion_value.
#' @export
build_carryover_team_record <- function(team, history, league_id, liga3_baseline, existing_short_names) {
  if (!is.null(history$previous_data)) {
    short_name <- history$previous_data$short_name
    promotion_value <- history$previous_data$promotion_value
  } else {
    warning(paste("Team", team$id, "-", team$name, "not found in previous season, generating new data"))
    short_name <- get_team_short_name(team$name)
    if (short_name %in% existing_short_names) {
      short_name <- generate_unique_short_name(short_name, existing_short_names)
    }
    promotion_value <- ifelse(team$is_second_team, -50, 0)
  }

  final_short_name <- convert_second_team_short_name(
    short_name,
    team$is_second_team,
    promotion_value
  )

  initial_elo <- if (!is.null(history$team_elo) && length(history$team_elo) > 0) {
    history$team_elo[1]
  } else {
    if (league_id == 80 || league_id == "80") liga3_baseline else 1500
  }

  list(
    id = team$id,
    name = team$name,
    short_name = final_short_name,
    initial_elo = initial_elo,
    promotion_value = promotion_value
  )
}
