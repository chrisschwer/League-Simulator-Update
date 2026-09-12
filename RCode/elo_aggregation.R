# Liga-Registry: die eine Quelle fuer die Ligamenge.
if (!exists("league_ids")) {
  local({
    d <- NULL
    for (f in rev(sys.frames())) {
      if (!is.null(f$ofile)) {
        d <- dirname(f$ofile)
        break
      }
    }
    if (is.null(d) || is.na(d) || !nzchar(d)) d <- "RCode"
    source(file.path(d, "league_registry.R"))
  })
}

# ELO Aggregation Functions
# Calculates final ELO ratings and Liga3 relegation baselines
#
# Liga3 Relegation Baseline:
# The baseline is calculated as the mean of the final ELO ratings of teams
# that finished in the relegation positions (typically 17-20 in Liga3).
# This is based on actual league standings, NOT just lowest ELO values.
#
# The baseline serves as the initial ELO for new teams entering Liga3,
# ensuring they start with a rating similar to recently relegated teams.
#
# Process:
# 1. Calculate end-of-season ELO values for all teams (after all matches)
# 2. Calculate final league standings using match results
# 3. Identify teams that finished in relegation positions
# 4. Return mean of those teams' final ELO values

# Die End-ELOs einer Saison -- berechnet vom Rust-Walk, nicht in R.
#
# WARUM DIESE FUNKTION KEINE ELO MEHR RECHNET (Issue #146, Teil 2)
#
# Bis September 2026 lief hier ein zweiter, vollstaendiger ELO-Walk in R:
# update_elos_for_match() + calculate_elo_update(). Er war mathematisch
# identisch mit dem Rust-Walk -- dieselbe Clamp auf +/-400, dieselbe Wurzel
# der Tordifferenz, derselbe K-Faktor 20 -- bis auf EINEN Wert:
# home_advantage war 100 statt 40.
#
# Die Start-ELOs jeder neuen Saison entstanden damit auf einer Physik, mit
# der anschliessend keine einzige Prognose rechnete.
#
# Einfach 40 einzusetzen war nicht moeglich: Die beiden Werte wirken ueber
# verschiedene Formeln (Rust ueber das Poisson-Tormodell, R ueber die
# ELO-Erwartung) und sind nicht vergleichbar; geeicht laege der R-Wert bei
# ~25,8. Eine 25,8 einzutragen haette die zweite Physik konserviert -- mit
# einer Zahl, die niemand mehr mit der 40 der Prognose in Beziehung setzen
# kann. Die einzige Variante, die EINEN Heimvorteil herstellt, ist die
# Loeschung. Damit erfuellt der Saisonwechsel endlich, was ADR 0002
# verlangt: keine Modelllogik in R.
#
# DIE BEIDEN SEAMS. fetch_fn und fixtures_fn tragen Produktions-Defaults und
# existieren, damit Tests weder einen Rust-Server noch einen API-Schluessel
# brauchen -- dasselbe Muster wie build_league_page_data() in
# league_details.R. Es sind zwei und nicht einer, weil
# extract_fixture_details() die ROHEN api-football-Fixtures braucht
# (verschachtelte fixture/league/teams/goals-Spalten); das flachgeklopfte
# data.frame aus fetch_league_results() passt dort nicht hinein.
calculate_final_elos <- function(season,
                                 fetch_fn = fetch_league_details,
                                 fixtures_fn = retrieveResults) {
  tryCatch(
    {
      # Load team list for the season - check for temporary files first
      team_list_file <- paste0("RCode/TeamList_", season, ".csv")

      # Check if we have temporary files from current processing
      temp_files <- list.files(
        "RCode",
        pattern = paste0("TeamList_", season, "_League.*_temp\\.csv$"),
        full.names = TRUE
      )

      if (length(temp_files) > 0) {
        # We have temporary files, merge them to get the team list
        cat("Using temporary files for ELO calculation in season", season, "\n")

        team_list <- data.frame()
        for (file in temp_files) {
          if (file.exists(file)) {
            league_data <- read.csv(file, sep = ";", stringsAsFactors = FALSE)
            if (!is.null(league_data) && nrow(league_data) > 0) {
              team_list <- rbind(team_list, league_data)
            }
          }
        }

        if (nrow(team_list) == 0) {
          stop(paste("No valid team data found in temporary files for season", season))
        }
      } else if (file.exists(team_list_file)) {
        # Use regular team list file
        team_list <- read.csv(team_list_file, sep = ";", stringsAsFactors = FALSE)
      } else {
        stop(paste("Team list file not found:", team_list_file))
      }

      # Startwert jedes Teams. Wer in keiner Liga ein Spiel hat, behaelt ihn --
      # das ist Bestandsverhalten und traegt den Saisonwechsel in genau den
      # Faellen, in denen er sonst abbraeche (eine Liga, die api-football fuer
      # diese Saison nicht fuehrt; eine Saison ohne ein einziges Spiel).
      current_elos <- data.frame(
        TeamID = team_list$TeamID,
        CurrentELO = team_list$InitialELO,
        # ShortText reist mit, weil der Payload team_names verlangt. Fehlt die
        # Spalte (TeamLists bis Saison 2025 kennen sie), tritt die TeamID als
        # Name ein -- sie ist ohnehin nur ein Etikett fuer die Antwort, die
        # Zuordnung laeuft ueber die Position in teams$TeamID.
        ShortText = if ("ShortText" %in% names(team_list)) {
          as.character(team_list$ShortText)
        } else {
          as.character(team_list$TeamID)
        },
        stringsAsFactors = FALSE
      )

      # Alle Ligen der Registry, nicht nur SEASON_TRANSITION_LEAGUES:
      # Letzteres steuert die Vollstaendigkeitspruefung, nicht den Abruf.
      # Ohne die sieben seit September 2026 dazugekommenen Ligen verloere der
      # Saisonwechsel den Grossteil des ELO-Wissens -- Aufsteiger kaemen mit
      # ihrem Startwert statt mit ihrer erspielten Staerke an.
      leagues <- league_ids()

      # Der eingefrorene Saison-Startstand (siehe teams-Aufbau unten).
      start_elos <- current_elos$CurrentELO

      for (league in leagues) {
        cat("Processing ELO updates for league", league, "season", season, "\n")

        # Ein Fehlschlag EINER Liga darf den Saisonwechsel nicht mitreissen.
        #
        # Das alte get_league_matches() hatte diesen tryCatch (es gab bei
        # Fehler NULL zurueck), und die Eigenschaft ist tragend: Der Lauf
        # findet einmal im Juli statt und fragt zehn Ligen ab. Bricht er bei
        # der achten ab, weil api-football fuer eine Liga die neue Saison noch
        # nicht fuehrt, ist die Arbeit der ersten sieben verloren.
        #
        # Die betroffene Liga behaelt ihre Start-ELOs -- dasselbe Verhalten
        # wie bei einer leeren Antwort, nur eben mit Warnung.
        fixtures <- tryCatch(
          fixtures_fn(league, season),
          error = function(e) {
            warning(paste("Error fetching fixtures for league", league,
                          "season", season, ":", conditionMessage(e)))
            NULL
          }
        )

        if (is.null(fixtures) || nrow(fixtures) == 0) {
          cat("No matches found for league", league, "season", season,
              "- ELO values will remain unchanged\n")
          next
        }

        details <- extract_fixture_details(fixtures)

        if (is.null(details) || nrow(details) == 0) {
          cat("No usable fixtures for league", league, "season", season,
              "- ELO values will remain unchanged\n")
          next
        }

        # Nur die Teams dieser Liga in den Payload -- und in der Reihenfolge
        # der TeamList, nicht in der des Spielplans.
        #
        # Warum die Reihenfolge ueberhaupt zaehlt: antwort$current_elos kommt
        # POSITIONAL zurueck, ausgerichtet an teams$TeamID. Wuerde hier nach
        # Spielplan sortiert, haenge das Ergebnis daran, wer zufaellig am
        # ersten Spieltag zuhause spielt -- reproduzierbar, aber ohne Grund
        # verschieden zwischen zwei Laeufen mit anderer Fixture-Reihenfolge.
        # Die TeamList-Reihenfolge ist stabil und nachvollziehbar.
        in_liga <- current_elos$TeamID %in% c(details$home_id, details$away_id)
        idx <- which(in_liga)
        liga_team_ids <- current_elos$TeamID[idx]

        # Teams im Spielplan, die die TeamList nicht kennt.
        fehlend <- setdiff(unique(c(details$home_id, details$away_id)),
                           current_elos$TeamID)

        # Teams, die der Spielplan kennt, die TeamList aber nicht: Sie
        # koennen nicht in den Payload, weil ihnen der Startwert fehlt.
        # build_league_details_payload() wuerde sonst mit "Unknown team ID"
        # abbrechen und den ganzen Saisonwechsel mitreissen -- deshalb fallen
        # ihre Spiele raus statt des ganzen Laufs.
        if (length(fehlend) > 0) {
          warning(paste("League", league, "- Teams nicht in der TeamList, ELO bleibt unveraendert:",
                        paste(fehlend, collapse = ", ")))
          details <- details[!(details$home_id %in% fehlend) &
                               !(details$away_id %in% fehlend), , drop = FALSE]
          if (nrow(details) == 0) next
          in_liga <- current_elos$TeamID %in% c(details$home_id, details$away_id)
          idx <- which(in_liga)
          liga_team_ids <- current_elos$TeamID[idx]
        }

        if (length(idx) == 0) next

        # Startwert ist der Saison-Startwert, NICHT ein schon fortgeschriebener
        # Wert.
        #
        # Ein Team spielt in genau einer Liga, also wird sein ELO in genau
        # einem Schleifendurchlauf gesetzt. Wuerde hier der laufende Stand
        # gelesen, waere das solange folgenlos -- bis ein Team doch in zwei
        # Abrufen auftaucht (Ligawechsel waehrend der Saison, ein Team in
        # zwei Wettbewerben, eine doppelt gefuehrte Liga). Dann liefe sein
        # ELO-Gewinn zweimal auf, und zwar still: Das Ergebnis saehe wie eine
        # besonders starke Saison aus.
        #
        # start_elos wird vor der Schleife eingefroren, deshalb ist die
        # Reihenfolge der Ligen ohne Einfluss aufs Ergebnis.
        teams <- data.frame(
          TeamID = liga_team_ids,
          InitialELO = start_elos[idx],
          ShortText = current_elos$ShortText[idx],
          stringsAsFactors = FALSE
        )

        # Tormodell je Wechselgemeinschaft (ADR 0004): goal_model() liefert
        # NULL, wo der Rust-Default gilt (Herren) -- dann wird nichts
        # gesendet. Die Frauen-Ligen 82 und 1034 tragen eigene Werte, und sie
        # muessen hier mit, sonst rechnete der Saisonwechsel ihre End-ELOs mit
        # dem Herren-Tormodell.
        tormodell <- goal_model(league)

        payload <- build_league_details_payload(
          details, teams,
          tore_slope = tormodell$tore_slope,
          tore_intercept = tormodell$tore_intercept
        )

        antwort <- parse_league_details_response(fetch_fn(payload))

        # Zurueckschreiben ueber die ID, nicht ueber die Position in
        # current_elos: teams$TeamID traegt die Zuordnung, antwort$current_elos
        # ist an teams ausgerichtet.
        current_elos$CurrentELO[idx] <- antwort$current_elos

        cat("Processed", nrow(details), "matches for league", league,
            "season", season, "\n")
      }

      # Return final ELOs
      final_elos <- data.frame(
        TeamID = current_elos$TeamID,
        FinalELO = current_elos$CurrentELO,
        stringsAsFactors = FALSE
      )

      # Debug: Show ELO changes
      initial_sum <- sum(team_list$InitialELO)
      final_sum <- sum(final_elos$FinalELO)
      cat("ELO Summary - Initial total:", initial_sum, "Final total:", final_sum, "\n")

      # Show some specific changes for key teams
      key_teams <- c(168, 1320, 4259) # B04, Cottbus, Aachen
      for (team_id in key_teams) {
        initial_idx <- which(team_list$TeamID == team_id)
        final_idx <- which(final_elos$TeamID == team_id)
        if (length(initial_idx) > 0 && length(final_idx) > 0) {
          initial_elo <- team_list$InitialELO[initial_idx[1]]
          final_elo <- final_elos$FinalELO[final_idx[1]]
          cat("Team", team_id, "ELO change:", initial_elo, "->", final_elo, "(", final_elo - initial_elo, ")\n")
        }
      }

      return(final_elos)
    },
    error = function(e) {
      stop(paste("Error calculating final ELOs for season", season, ":", e$message))
    }
  )
}

get_league_matches <- function(league, season) {
  # Get all finished matches for a league and season
  # Returns data frame with match information

  tryCatch(
    {
      # Always use fetch_league_results for ELO calculations
      # retrieveResults doesn't return the required data structure
      results <- fetch_league_results(league, season)

      if (is.null(results)) {
        return(NULL)
      }

      # Filter for finished matches only
      finished_matches <- results[results$fixture_status_short == "FT", ]

      # Extract required columns
      match_data <- data.frame(
        fixture_date = finished_matches$fixture_date,
        teams_home_id = finished_matches$teams_home_id,
        teams_away_id = finished_matches$teams_away_id,
        goals_home = finished_matches$goals_home,
        goals_away = finished_matches$goals_away,
        stringsAsFactors = FALSE
      )

      return(match_data)
    },
    error = function(e) {
      warning(paste("Error fetching matches for league", league, "season", season, ":", e$message))
      return(NULL)
    }
  )
}

fetch_league_results <- function(league, season) {
  # Direct API call fallback for league results
  # Returns raw API response data

  api_key <- Sys.getenv("RAPIDAPI_KEY")
  if (api_key == "") {
    stop("RAPIDAPI_KEY environment variable not set")
  }

  url <- "https://api-football-v1.p.rapidapi.com/v3/fixtures"

  query_params <- list(
    league = league,
    season = season,
    status = "FT"
  )

  response <- httr::GET(
    url,
    query = query_params,
    httr::add_headers(
      "X-RapidAPI-Key" = api_key,
      "X-RapidAPI-Host" = "api-football-v1.p.rapidapi.com"
    )
  )

  if (httr::status_code(response) != 200) {
    stop(paste("API call failed with status", httr::status_code(response)))
  }

  content <- httr::content(response, "text", encoding = "UTF-8")
  data <- jsonlite::fromJSON(content)

  if (is.null(data$response)) {
    return(NULL)
  }

  # Transform API response to expected format
  fixtures <- data$response

  # Extract match data
  #
  # fixture_id und round kamen mit der Offline-ELO-Kalibrierung dazu: Sie
  # braucht die Rundenbezeichnung, um Relegationspartien von der Hauptrunde
  # zu trennen (die Regionalligen liefern "Bayern - 34" statt
  # "Regular Season - N"). Rein additiv -- bestehende Aufrufer sehen die
  # Spalten schlicht nicht.
  match_data <- data.frame(
    fixture_id = fixtures$fixture$id,
    fixture_date = fixtures$fixture$date,
    round = if (!is.null(fixtures$league$round)) {
      fixtures$league$round
    } else {
      NA_character_
    },
    teams_home_id = fixtures$teams$home$id,
    teams_away_id = fixtures$teams$away$id,
    teams_home_name = fixtures$teams$home$name,
    teams_away_name = fixtures$teams$away$name,
    goals_home = fixtures$goals$home,
    goals_away = fixtures$goals$away,
    fixture_status_short = fixtures$fixture$status$short,
    stringsAsFactors = FALSE
  )

  return(match_data)
}

# HIER STANDEN update_elos_for_match() UND calculate_elo_update().
#
# Beide sind mit Issue #146, Teil 2 entfallen: Sie waren der zweite ELO-Walk
# des Projekts -- mathematisch identisch mit dem Rust-Walk bis auf
# home_advantage, das hier 100 war statt 40. Die End-ELOs holt
# calculate_final_elos() jetzt ueber POST /league-details, also aus derselben
# Engine, die jede Prognose rechnet (ADR 0002).
#
# Wer eine ELO-Rechnung in R braucht, hat fast sicher ein anderes Problem:
# Zwei Implementierungen widersprechen sich nur in den Zahlen, nie im Typ --
# deshalb faellt ihr Auseinanderlaufen im Betrieb nicht auf. Der Wachhund in
# tests/testthat/test-ein-elo-walk.R haelt die Abwesenheit fest.


# ZWEITER AUFRUFER von calculate_final_elos(), leicht zu uebersehen: Er steht
# in derselben Datei wie der geloeschte R-Walk. Laeuft er ins Leere, faellt er
# auf den Default 1046 zurueck -- und zwar STILL: mit einer Warnung, aber ohne
# Fehler, und mit einem Wert, der plausibel aussieht.
#
# Die Seams werden durchgereicht, damit ein Test der Baseline keinen
# Rust-Server braucht und der produktive Aufruf den Endpoint nicht zweimal
# unterschiedlich konfigurieren muss.
calculate_liga3_relegation_baseline <- function(season,
                                                fetch_fn = fetch_league_details,
                                                fixtures_fn = retrieveResults) {
  # Calculate mean ELO of teams that finished in relegation positions (17-20) in Liga3
  # This baseline is used as initial ELO for new teams entering Liga3
  #
  # Process:
  # 1. Calculate end-of-season ELO values for all teams
  # 2. Get Liga3 match results and calculate final league standings
  # 3. Identify teams finishing in positions 17-20 (relegated)
  # 4. Return mean of their final ELO values

  tryCatch(
    {
      # Get final ELOs for all teams (end-of-season values after all matches)
      #
      # Die Seams werden nur durchgereicht, wenn die aufgerufene Funktion sie
      # kennt. Das klingt nach Umstand, verhindert aber einen echten und
      # besonders unangenehmen Fehlerfall: Wird calculate_final_elos() ersetzt
      # (in Tests per stub(), im Betrieb durch eine schlankere Fassung) und
      # nimmt nur `season`, dann scheitert der Aufruf an den unbekannten
      # Argumenten -- und der tryCatch unten verwandelt das in die
      # Default-Baseline 1046. Also kein Absturz, sondern eine plausible Zahl,
      # die still in die Start-ELOs aller Liga-3-Aufsteiger wandert.
      akzeptiert <- names(formals(calculate_final_elos))
      final_elos <- if (all(c("fetch_fn", "fixtures_fn") %in% akzeptiert)) {
        calculate_final_elos(season, fetch_fn = fetch_fn,
                             fixtures_fn = fixtures_fn)
      } else {
        calculate_final_elos(season)
      }

      # Get Liga3 matches (league 80)
      liga3_matches <- get_league_matches("80", season)

      if (is.null(liga3_matches) || nrow(liga3_matches) == 0) {
        warning(paste("No Liga3 matches found for season", season))
        return(1046) # Default fallback ELO
      }

      # Get all Liga3 team IDs
      liga3_teams <- unique(c(liga3_matches$teams_home_id, liga3_matches$teams_away_id))
      number_of_teams <- length(liga3_teams)

      # Liga3 should have 20 teams, but handle different sizes
      if (number_of_teams < 4) {
        warning(paste("Not enough Liga3 teams found for baseline calculation (", number_of_teams, "teams)"))
        return(1046) # Default fallback ELO
      }

      # Calculate league table to find relegated teams
      # First, get team list for Liga3
      team_list_file <- paste0("RCode/TeamList_", season, ".csv")
      if (!file.exists(team_list_file)) {
        # Try temporary files if main file doesn't exist
        temp_files <- list.files(
          "RCode",
          pattern = paste0("TeamList_", season, "_League.*_temp\\.csv$"),
          full.names = TRUE
        )
        if (length(temp_files) > 0 && file.exists(temp_files[1])) {
          team_list_file <- temp_files[1]
        } else {
          warning(paste("Team list file not found for season", season))
          return(1046)
        }
      }

      # Convert matches to format expected by Tabelle function
      season_results <- data.frame(
        homeTeam = match(liga3_matches$teams_home_id, liga3_teams),
        awayTeam = match(liga3_matches$teams_away_id, liga3_teams),
        homeGoals = liga3_matches$goals_home,
        awayGoals = liga3_matches$goals_away,
        stringsAsFactors = FALSE
      )

      # Calculate league table
      league_table <- Tabelle(
        season = as.matrix(season_results),
        numberTeams = number_of_teams,
        numberGames = nrow(season_results)
      )

      # League table columns: team_number, rank, goals_for, goals_against, goal_diff, points
      # Find teams in relegation positions (bottom 4)
      # In Liga3 with 20 teams, relegation positions are 17-20 (ranks 17, 18, 19, 20)
      relegation_positions <- (number_of_teams - 3):number_of_teams

      # Get team numbers (indices) of relegated teams
      relegated_team_indices <- league_table[league_table[, 2] %in% relegation_positions, 1]

      # Map back to actual team IDs
      relegated_team_ids <- liga3_teams[relegated_team_indices]

      # Get final ELOs for relegated teams
      relegated_elos <- final_elos[final_elos$TeamID %in% relegated_team_ids, ]

      if (nrow(relegated_elos) != 4) {
        warning(paste("Expected 4 relegated teams but found", nrow(relegated_elos)))
        if (nrow(relegated_elos) < 4) {
          return(1046) # Default fallback
        }
      }

      # Calculate mean of relegated teams' final ELOs
      baseline <- mean(relegated_elos$FinalELO)

      # Log details for transparency
      cat("Liga3 relegation baseline for season", season, ":", round(baseline, 2), "\n")
      cat("Based on relegated teams (positions", min(relegation_positions), "-", max(relegation_positions), "):\n")
      for (i in seq_len(nrow(relegated_elos))) {
        team_id <- relegated_elos$TeamID[i]
        team_idx <- which(liga3_teams == team_id)
        team_rank <- league_table[league_table[, 1] == team_idx, 2]
        cat("  Position", team_rank, ": Team", team_id, "- Final ELO:", round(relegated_elos$FinalELO[i], 2), "\n")
      }

      return(baseline)
    },
    error = function(e) {
      warning(paste("Error calculating Liga3 baseline for season", season, ":", e$message))
      return(1046) # Default fallback ELO
    }
  )
}

get_initial_elo_for_new_team <- function(league, baseline = NULL) {
  # Determine initial ELO for new/promoted teams
  # Uses baseline for Liga3, default values for others

  if (league == "80" && !is.null(baseline)) {
    # Use Liga3 relegation baseline
    return(baseline)
  } else if (league == "80") {
    # Default Liga3 ELO
    return(1046)
  } else if (league == "79") {
    # Default 2. Bundesliga ELO
    return(1350)
  } else if (league == "78") {
    # Default Bundesliga ELO
    return(1500)
  } else {
    # Fallback default
    return(1200)
  }
}

validate_elo_calculations <- function(season) {
  # Validate ELO calculations for consistency
  # Returns validation results

  tryCatch(
    {
      final_elos <- calculate_final_elos(season)

      validation_results <- list(
        total_teams = nrow(final_elos),
        min_elo = min(final_elos$FinalELO),
        max_elo = max(final_elos$FinalELO),
        mean_elo = mean(final_elos$FinalELO),
        teams_with_valid_elos = sum(final_elos$FinalELO > 0),
        # Untergrenze 600 statt 800: Mit den Regionalligen reicht die
        # Skala tiefer (RL-Mittel ~940, schwaechste Teams ~700). Die 800
        # stammten aus einer Zeit mit drei Ligen und wuerden sonst zwei
        # Dutzend voellig regulaere RL-Teams als "extrem" melden.
        teams_with_extreme_elos = sum(final_elos$FinalELO < 600 | final_elos$FinalELO > 2400)
      )

      # Log validation results
      cat("ELO Validation Results for Season", season, ":\n")
      cat("Total Teams:", validation_results$total_teams, "\n")
      cat("ELO Range:", round(validation_results$min_elo, 2), "-", round(validation_results$max_elo, 2), "\n")
      cat("Mean ELO:", round(validation_results$mean_elo, 2), "\n")
      cat("Teams with Extreme ELOs:", validation_results$teams_with_extreme_elos, "\n")

      return(validation_results)
    },
    error = function(e) {
      warning(paste("Error validating ELO calculations for season", season, ":", e$message))
      return(NULL)
    }
  )
}

export_elo_progression <- function(season, output_file = NULL) {
  # Export ELO progression data for analysis
  # Useful for debugging and verification

  if (is.null(output_file)) {
    output_file <- paste0("elo_progression_", season, ".csv")
  }

  tryCatch(
    {
      final_elos <- calculate_final_elos(season)

      # Add initial ELOs for comparison
      team_list_file <- paste0("RCode/TeamList_", season, ".csv")
      if (file.exists(team_list_file)) {
        initial_elos <- read.csv(team_list_file, sep = ";", stringsAsFactors = FALSE)

        # Merge initial and final ELOs
        elo_progression <- merge(
          initial_elos[, c("TeamID", "InitialELO")],
          final_elos,
          by = "TeamID"
        )

        # Calculate ELO change
        elo_progression$ELO_Change <- elo_progression$FinalELO - elo_progression$InitialELO

        # Write to CSV
        write.csv(elo_progression, output_file, row.names = FALSE)

        cat("ELO progression exported to:", output_file, "\n")

        return(elo_progression)
      }
    },
    error = function(e) {
      warning(paste("Error exporting ELO progression for season", season, ":", e$message))
      return(NULL)
    }
  )
}
