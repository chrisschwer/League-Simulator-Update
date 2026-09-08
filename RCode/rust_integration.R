#' Rust Integration Functions
#'
#' Functions to integrate with the high-performance Rust simulation engine
#' Provides 50-100x performance improvement over R/C++ implementation

library(httr)
library(jsonlite)

# Global configuration
RUST_API_URL <- Sys.getenv("RUST_API_URL", "http://localhost:8080")

#' Connect to Rust Simulator
#'
#' Check if the Rust REST API is available and healthy
#' @return TRUE if connection successful, FALSE otherwise
#' @export
connect_rust_simulator <- function() {
  tryCatch(
    {
      response <- GET(paste0(RUST_API_URL, "/health"))
      if (status_code(response) == 200) {
        health <- content(response, "parsed")
        message(sprintf("✅ Connected to Rust simulator v%s", health$version))
        message(sprintf("   Performance: %s", health$performance))
        return(TRUE)
      } else {
        message("❌ Rust simulator not responding")
        return(FALSE)
      }
    },
    error = function(e) {
      message(sprintf("❌ Failed to connect to Rust simulator: %s", e$message))
      return(FALSE)
    }
  )
}

#' Simulate League using Rust Engine
#'
#' Call the Rust REST API to run Monte Carlo simulation
#' @param schedule Matrix of matches [team_home, team_away, goals_home, goals_away]
#' @param elo_values Vector of initial ELO values
#' @param team_names Vector of team names
#' @param iterations Number of Monte Carlo iterations (default: 10000)
#' @param mod_factor ELO modification factor (default: 20)
#' @param home_advantage Home advantage in ELO points. NULL (default) omits
#'   the field so the Rust server applies its own value -- the single source of
#'   truth for model constants (ADR 0002). Pass a number only to override it.
#' @param adj_points Optional point adjustments per team
#' @param adj_goals Optional goals adjustments per team
#' @param adj_goals_against Optional goals against adjustments per team
#' @param adj_goal_diff Optional goal difference adjustments per team
#' @return List with probability_matrix, team_names, and performance metrics
#' @export
simulate_league_rust <- function(schedule, elo_values, team_names,
                                 iterations = 10000,
                                 mod_factor = 20,
                                 home_advantage = NULL,
                                 adj_points = NULL,
                                 adj_goals = NULL,
                                 adj_goals_against = NULL,
                                 adj_goal_diff = NULL,
                                 elo_neutral = NULL,
                                 tore_slope = NULL,
                                 tore_intercept = NULL,
                                 group_of_team = NULL,
                                 relegation_places = NULL) {
  # Convert schedule matrix to list format for JSON
  schedule_list <- lapply(seq_len(nrow(schedule)), function(i) {
    goals_home <- if (is.na(schedule[i, 3])) NULL else as.integer(schedule[i, 3])
    goals_away <- if (is.na(schedule[i, 4])) NULL else as.integer(schedule[i, 4])

    list(
      as.integer(schedule[i, 1]), # team_home
      as.integer(schedule[i, 2]), # team_away
      goals_home, # goals_home (NULL or integer)
      goals_away # goals_away (NULL or integer)
    )
  })

  # Prepare request payload
  payload <- list(
    schedule = schedule_list,
    elo_values = as.numeric(elo_values),
    team_names = team_names,
    iterations = as.integer(iterations),
    mod_factor = as.numeric(mod_factor)
  )

  # home_advantage bleibt bewusst aus dem Payload: Der Rust-Server hält den
  # Wert (ADR 0002). Nur ein explizit übergebener Wert überschreibt ihn.
  if (!is.null(home_advantage)) {
    payload$home_advantage <- as.numeric(home_advantage)
  }

  # Add optional adjustments if provided
  if (!is.null(adj_points)) payload$adj_points <- as.integer(adj_points)
  if (!is.null(adj_goals)) payload$adj_goals <- as.integer(adj_goals)
  if (!is.null(adj_goals_against)) payload$adj_goals_against <- as.integer(adj_goals_against)
  if (!is.null(adj_goal_diff)) payload$adj_goal_diff <- as.integer(adj_goal_diff)

  # Am grünen Tisch gewertete Spiele: Das Ergebnis zählt für die Endtabelle,
  # bewegt aber den ELO-Walk nicht (Issue #157). Nur senden, wenn überhaupt
  # eines vorkommt -- so bleibt der Payload der Altligen unverändert.
  if (!is.null(elo_neutral) && any(elo_neutral)) {
    payload$elo_neutral <- as.logical(elo_neutral)
  }

  # Tormodell je Wechselgemeinschaft (ADR 0004). Wie beim home_advantage gilt:
  # Nur eine ABWEICHUNG wird gesendet -- fuer die Herren-Ligen haelt der
  # Rust-Server seine Defaults, und zwei Quellen koennten auseinanderlaufen
  # (ADR 0002). Die Werte kommen aus der Liga-Registry.
  if (!is.null(tore_slope)) payload$tore_slope <- as.numeric(tore_slope)
  if (!is.null(tore_intercept)) payload$tore_intercept <- as.numeric(tore_intercept)

  # Staffel-Zuordnung fuer die Abstiegskopplung. Beide Felder gehoeren
  # zusammen; die Engine lehnt eines allein ab. Teams ohne Stammregion
  # (NA) koennen nicht zugeordnet werden -- dann bleibt die Auszaehlung aus,
  # statt sie mit einer erfundenen Staffel zu verfaelschen.
  if (!is.null(group_of_team) && !is.null(relegation_places) &&
        !any(is.na(group_of_team))) {
    payload$group_of_team <- as.integer(group_of_team)
    payload$relegation_places <- as.integer(relegation_places)
  }

  # digits = NA: volle Praezision statt der vier Nachkommastellen, auf die
  # jsonlite sonst rundet. Bei tore_slope (0,0024058833) waeren das 0,245 %
  # Fehler -- der Parameter ist klein genug, dass die Rundung ihn in einer
  # signifikanten Stelle trifft. Fuer ELO-Werte macht es keinen Unterschied
  # (5e-05 Punkte), schadet aber nicht.
  json_body <- toJSON(payload, auto_unbox = TRUE, null = "null", digits = NA)

  # Make API request
  response <- POST(
    paste0(RUST_API_URL, "/simulate"),
    body = json_body,
    content_type_json(),
    accept_json()
  )

  if (status_code(response) != 200) {
    error_body <- content(response, "text")
    message("DEBUG: Request payload summary:")
    message("  Teams: ", length(team_names))
    message("  Schedule rows: ", nrow(schedule))
    message("  ELO values: ", length(elo_values))
    message("  Team indices range: ", min(schedule[, 1:2], na.rm = TRUE), "-", max(schedule[, 1:2], na.rm = TRUE))
    message("  Error response: ", error_body)
    stop(sprintf("Rust simulation failed with status %d: %s", status_code(response), error_body))
  }

  result <- content(response, "parsed")

  # Convert probability matrix to R matrix with proper numeric conversion
  prob_matrix <- do.call(rbind, lapply(result$probability_matrix, as.numeric))
  rownames(prob_matrix) <- result$team_names
  colnames(prob_matrix) <- seq_len(ncol(prob_matrix))

  return(list(
    probability_matrix = prob_matrix,
    team_names = result$team_names,
    simulations = result$simulations_performed,
    time_ms = result$time_ms,
    # Absteiger je Staffel, exakt ausgezaehlt. NULL, wenn keine
    # Staffel-Zuordnung gesendet wurde -- der Regelfall fuer die Altligen.
    relegation_group_counts = result$relegation_group_counts
  ))
}

#' League Simulator using Rust (Drop-in Replacement)
#'
#' Drop-in replacement for leagueSimulatorCPP that uses Rust engine
#' Maintains exact same interface and return format
#'
#' @param season table with schedule and ELO values
#' @param n number of iterations, defaults to 10000
#' @param modFactor Multiplier ("learning rate") for ELO adjustment
#' @param homeAdvantage Home field advantage in ELO points; NULL (default)
#'   leaves the value to the Rust server (ADR 0002)
#' @param numberTeams Number of teams in the league
#' @param adjPoints vector containing an adjustment for the points scored per team
#' @param adjGoals vector containing an adjustment for the goals scored per team
#' @param adjGoalsAgainst vector containing an adjustment for the goals scored against per team
#' @param adjGoalDiff vector containing an adjustment for the goal difference per team
#' @return Distribution matrix (teams x positions) with probabilities
#' @export
leagueSimulatorRust <- function(season, n = 10000,
                                modFactor = 20, homeAdvantage = NULL,
                                toreSlope = NULL, toreIntercept = NULL,
                                numberTeams = 18,
                                adjPoints = rep_len(0, numberTeams),
                                adjGoals = rep_len(0, numberTeams),
                                adjGoalsAgainst = rep_len(0, numberTeams),
                                adjGoalDiff = rep_len(0, numberTeams),
                                groupOfTeam = NULL, relegationPlaces = NULL) {
  # Caller (update_all_leagues_loop) has already asserted Rust availability.
  # Per-call connection checks were removed in issue #77 Phase 1; a Rust API
  # call failure surfaces via stop() in simulate_league_rust() below.

  # Convert tibble to data.frame if needed (transform_data returns tibble)
  if ("tbl_df" %in% class(season)) {
    season <- as.data.frame(season)
  }

  # Extract data from season dataframe - EXACTLY like the C++ version
  numberTeams <- dim(season)[2] - 4
  numberGames <- dim(season)[1]
  ELOValues <- as.double(season[1, 5:dim(season)[2]])
  teamNames <- colnames(season)[5:dim(season)[2]]

  # Replace team names in season with corresponding numbers - EXACTLY like C++ version
  season$TeamHeim <- factor(season$TeamHeim, levels = teamNames, ordered = TRUE)
  season$TeamGast <- factor(season$TeamGast, levels = teamNames, ordered = TRUE)
  season$TeamHeim <- as.integer(season$TeamHeim)
  season$TeamGast <- as.integer(season$TeamGast)

  # Validate that all team indices are valid (no NAs)
  if (any(is.na(season$TeamHeim)) || any(is.na(season$TeamGast))) {
    missing_teams <- unique(c(
      season$TeamHeim[is.na(as.integer(factor(season$TeamHeim, levels = teamNames)))],
      season$TeamGast[is.na(as.integer(factor(season$TeamGast, levels = teamNames)))]
    ))
    stop(sprintf("Team names not found in columns: %s", paste(missing_teams, collapse = ", ")))
  }

  # Create schedule matrix
  schedule <- as.matrix(season[, 1:4])

  # Keep 1-based indexing - Rust API expects 1-based indices and converts internally

  # Call Rust simulator
  start_time <- Sys.time()

  # transform_data() hinterlegt zeilengleich, welche Spiele am grünen Tisch
  # gewertet wurden. Fehlt das Attribut (handgebaute Testdaten, ältere
  # Aufrufer), ist kein Spiel ELO-neutral -- das Verhalten vor Issue #157.
  eloNeutral <- attr(season, "elo_neutral")

  result <- simulate_league_rust(
    schedule = schedule,
    elo_values = ELOValues,
    team_names = teamNames,
    iterations = n,
    mod_factor = modFactor,
    home_advantage = homeAdvantage,
    adj_points = adjPoints,
    adj_goals = adjGoals,
    adj_goals_against = adjGoalsAgainst,
    adj_goal_diff = adjGoalDiff,
    elo_neutral = eloNeutral,
    tore_slope = toreSlope,
    tore_intercept = toreIntercept,
    group_of_team = groupOfTeam,
    relegation_places = relegationPlaces
  )

  end_time <- Sys.time()

  # Log performance improvement
  time_taken <- as.numeric(difftime(end_time, start_time, units = "secs"))
  message(sprintf(
    "Rust simulation completed: %d iterations in %.2f seconds (%.0f/sec)",
    result$simulations, time_taken,
    result$simulations / time_taken
  ))

  # Return in same format as leagueSimulatorCPP
  distribution <- result$probability_matrix

  # Ensure proper ordering by average rank
  rankAverage <- rowSums(distribution * matrix(
    seq_len(ncol(distribution)),
    nrow = nrow(distribution),
    ncol = ncol(distribution),
    byrow = TRUE
  ))
  rankOrder <- order(rankAverage)

  distribution <- distribution[rankOrder, ]

  # Die Auszaehlung der Absteiger je Staffel reist als ATTRIBUT mit, nicht
  # als zweites Listenelement: Der Rueckgabewert dieser Funktion ist an rund
  # einem Dutzend Stellen eine Prognosematrix -- er wird gerendert, indiziert,
  # gespeichert. Eine Liste daraus zu machen haette jede davon gebrochen.
  # Ein Attribut faellt bei alledem hoechstens weg; es fuehrt nie zu einer
  # falschen Zahl.
  if (!is.null(result$relegation_group_counts)) {
    attr(distribution, "relegation_group_counts") <- result$relegation_group_counts
  }

  return(distribution)
}

#' Batch Simulate Multiple Leagues
#'
#' Simulate multiple leagues in parallel using Rust engine
#' Optimized for running Bundesliga, 2.Bundesliga, and 3.Liga together
#'
#' @param leagues List of league configurations
#' @return List of simulation results
#' @export
simulate_leagues_batch_rust <- function(leagues) {
  # Prepare batch request
  batch_request <- list(
    leagues = lapply(names(leagues), function(name) {
      league <- leagues[[name]]
      list(
        name = name,
        request = list(
          schedule = league$schedule,
          elo_values = league$elo_values,
          team_names = league$team_names,
          iterations = league$iterations %||% 10000,
          mod_factor = league$mod_factor %||% 20,
          home_advantage = league$home_advantage,
          adj_points = league$adj_points,
          adj_goals = league$adj_goals,
          adj_goals_against = league$adj_goals_against,
          adj_goal_diff = league$adj_goal_diff
        )
      )
    })
  )

  # Make batch API request
  response <- POST(
    paste0(RUST_API_URL, "/simulate/batch"),
    body = toJSON(batch_request, auto_unbox = TRUE),
    content_type_json(),
    accept_json()
  )

  if (status_code(response) != 200) {
    stop(sprintf("Batch simulation failed with status %d", status_code(response)))
  }

  result <- content(response, "parsed")

  # Process results
  output <- list()
  for (league_result in result$results) {
    prob_matrix <- do.call(rbind, lapply(league_result$response$probability_matrix, as.numeric))
    rownames(prob_matrix) <- league_result$response$team_names
    colnames(prob_matrix) <- seq_len(ncol(prob_matrix))

    output[[league_result$name]] <- list(
      probability_matrix = prob_matrix,
      team_names = league_result$response$team_names,
      simulations = league_result$response$simulations_performed,
      time_ms = league_result$response$time_ms
    )
  }

  message(sprintf(
    "Batch simulation completed in %.2f seconds",
    result$total_time_ms / 1000
  ))

  return(output)
}

# Helper function for null coalescing
`%||%` <- function(x, y) if (is.null(x)) y else x

# --- Aufstiegsspiele: Tor-Raten je Paarung ---------------------------------
#
# Der Endpunkt /match-preview rechnet ein virtuelles Spiel ohne Spielplan.
# Er ist die EINZIGE Quelle fuer den Schritt ELO -> lambda; RCode/
# aufstiegsspiele.R bekommt von hier nur fertige Raten (ADR 0002).

#' Ein virtuelles Spiel: die Tor-Raten und Ergebniswahrscheinlichkeiten.
#'
#' @param elo_home,elo_away ELO-Werte beider Teams.
#' @param home_advantage Heimvorteil in ELO-Punkten. NULL (Default) laesst
#'   das Feld weg, damit der Rust-Server seinen eigenen Wert nimmt -- die
#'   einzige Quelle der Modellkonstanten (ADR 0002). Nur eine ABWEICHUNG
#'   wird gesendet; 0 fuer ein Spiel auf neutralem Platz ist eine solche.
#' @param tore_slope,tore_intercept Tormodell einer abweichenden
#'   Wechselgemeinschaft (ADR 0004), sonst NULL.
#' @param max_goals Groesse der score_matrix, sonst der Server-Default.
#' @return list(lambda_home, lambda_away, p_home_win, p_draw, p_away_win,
#'   score_matrix).
match_preview_rust <- function(elo_home, elo_away, home_advantage = NULL,
                               tore_slope = NULL, tore_intercept = NULL,
                               max_goals = NULL) {
  payload <- list(
    elo_home = as.numeric(elo_home),
    elo_away = as.numeric(elo_away)
  )

  # NULL-Felder werden nicht gesendet -- sonst haette R eine zweite Kopie
  # jedes Defaults, und die beiden liefen frueher oder spaeter auseinander.
  if (!is.null(home_advantage)) payload$home_advantage <- as.numeric(home_advantage)
  if (!is.null(tore_slope)) payload$tore_slope <- as.numeric(tore_slope)
  if (!is.null(tore_intercept)) payload$tore_intercept <- as.numeric(tore_intercept)
  if (!is.null(max_goals)) payload$max_goals <- as.integer(max_goals)

  # digits = NA wie bei /simulate: volle Praezision statt der vier
  # Nachkommastellen, auf die jsonlite sonst rundet.
  response <- POST(
    paste0(RUST_API_URL, "/match-preview"),
    body = toJSON(payload, auto_unbox = TRUE, null = "null", digits = NA),
    content_type_json(),
    accept_json()
  )

  if (status_code(response) != 200) {
    stop(sprintf(
      "match_preview_rust: /match-preview antwortete mit Status %d: %s",
      status_code(response), content(response, "text")
    ), call. = FALSE)
  }

  result <- content(response, "parsed")

  score_matrix <- do.call(rbind, lapply(result$score_matrix, as.numeric))

  list(
    lambda_home = as.numeric(result$lambda_home),
    lambda_away = as.numeric(result$lambda_away),
    p_home_win = as.numeric(result$p_home_win),
    p_draw = as.numeric(result$p_draw),
    p_away_win = as.numeric(result$p_away_win),
    score_matrix = score_matrix
  )
}

#' Tor-Raten aller Paarungen zweier Staffeln fuer die Aufstiegsspiele.
#'
#' @param elo_a Benannter ELO-Vektor der Staffel A (Hinspiel zu Hause).
#' @param elo_b Benannter ELO-Vektor der Staffel B (Rueckspiel zu Hause).
#' @param tore_slope,tore_intercept Abweichendes Tormodell (ADR 0004).
#' @return data.frame mit a, b, hin_a, hin_b, rueck_a, rueck_b, neutral_a,
#'   neutral_b -- eine Zeile je Paarung, wie p_sieg_matrix() es erwartet.
zweikampf_paarungen_rust <- function(elo_a, elo_b, tore_slope = NULL,
                                     tore_intercept = NULL) {
  if (is.null(names(elo_a)) || is.null(names(elo_b))) {
    stop(
      paste0(
        "zweikampf_paarungen_rust: elo_a und elo_b brauchen Teamnamen. Ohne ",
        "sie bliebe nur die Zuordnung ueber die Position, und die ist ",
        "zwischen zwei Simulationslaeufen zufaellig."
      ),
      call. = FALSE
    )
  }

  zeilen <- vector("list", length(elo_a) * length(elo_b))
  k <- 0L

  for (a in names(elo_a)) {
    for (b in names(elo_b)) {
      # Hinspiel: A hat Heimrecht. Rueckspiel: B hat Heimrecht.
      hin <- match_preview_rust(elo_a[[a]], elo_b[[b]],
                                tore_slope = tore_slope,
                                tore_intercept = tore_intercept)
      rueck <- match_preview_rust(elo_b[[b]], elo_a[[a]],
                                  tore_slope = tore_slope,
                                  tore_intercept = tore_intercept)

      hin_a <- hin$lambda_home
      hin_b <- hin$lambda_away
      rueck_a <- rueck$lambda_away
      rueck_b <- rueck$lambda_home

      # WARUM DIE NEUTRALE RATE NICHT ABGEFRAGT WIRD: Der Heimvorteil geht
      # im Modell additiv auf lambda ein, mit vertauschtem Vorzeichen fuer
      # den Gast. Ueber Hin- und Rueckspiel hebt er sich deshalb exakt auf:
      # hin + rueck = 2 * neutral. Das ist keine Modellannahme, die hier
      # nachgebaut wuerde, sondern eine ARITHMETISCHE Identitaet auf den
      # beiden bereits gelieferten Werten -- die Integrationstests pruefen
      # sie ausdruecklich. Ein dritter Aufruf je Paarung wuerde denselben
      # Wert noch einmal holen: Bei 18 x 19 Teams sind das 342 statt 513
      # HTTP-Aufrufe je Zyklus, fuer eine Simulation, die selbst 42 ms
      # dauert.
      #
      # Weiter gehende Abkuerzungen (etwa eine Interpolation ueber die
      # ELO-Differenz) waeren NICHT erlaubt: Sie braeuchten die Annahme,
      # lambda sei linear in ELO, und die gehoert in den Rust-Server.
      neutral_a <- (hin_a + rueck_a) / 2
      neutral_b <- (hin_b + rueck_b) / 2

      k <- k + 1L
      zeilen[[k]] <- data.frame(
        a = a, b = b,
        hin_a = hin_a, hin_b = hin_b,
        rueck_a = rueck_a, rueck_b = rueck_b,
        neutral_a = neutral_a, neutral_b = neutral_b,
        stringsAsFactors = FALSE
      )
    }
  }

  do.call(rbind, zeilen)
}
