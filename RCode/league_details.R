# Spieldetails für die statische Seite (ADR 0002): Spieltag-Klassifikation,
# Rückblick-/Ausblick-Fensterung, Ligatabelle und der Client für den
# deterministischen Rust-Endpoint POST /league-details.
#
# Phase 2, TDD: Die Signaturen stehen, die Implementierung folgt nach dem
# Review der Tests (tests/testthat/test-fixture-details.R,
# test-spieltag-logik.R, test-ligatabelle.R, test-league-details-client.R).
# Die Tests definieren die Semantik; Kurzfassung:
#
# - Statusgruppen (api-football `fixture$status$short`):
#     beendet    = FT, AET, PEN
#     live       = 1H, HT, 2H, ET, BT, P, SUSP, INT, LIVE
#     verschoben = PST, CANC, TBD, ABD
#     offen      = alles andere (insb. NS)
# - Ein Spieltag ist "abgeschlossen", wenn mindestens ein Spiel beendet ist,
#   kein Spiel live ist und jedes Spiel beendet oder verschoben ist;
#   "laufend", wenn er begonnen hat (>= 1 beendet/live) und nicht abgeschlossen
#   ist; sonst "ausstehend".
# - Der aktuelle Spieltag ist der HÖCHSTE begonnene (ein wieder angesetztes
#   Nachholspiel macht seinen alten Spieltag nicht zum aktuellen).
# - Rückblick: alle beendeten Spiele mit Anstoß >= Beginn (früheste
#   Anstoßzeit) des zuletzt abgeschlossenen Spieltags; Spiele älterer Runden
#   werden als Nachholspiel markiert.
# - Ausblick: Ziel ist der laufende Spieltag, sonst die kleinste Runde über
#   dem aktuellen mit offenen Spielen; aufgenommen werden alle offenen, nicht
#   verschobenen Spiele mit Anstoß bis zum letzten offenen Spiel des Ziels
#   (früher angesetzte Nachholspiele eingeschlossen, markiert).

STATUS_BEENDET <- c("FT", "AET", "PEN")
STATUS_LIVE <- c("1H", "HT", "2H", "ET", "BT", "P", "SUSP", "INT", "LIVE")
STATUS_VERSCHOBEN <- c("PST", "CANC", "TBD", "ABD")

extract_fixture_details <- function(fixtures) {
  round_raw <- vapply(fixtures$league, function(x) x$round[[1]], character(1))
  fixtures <- fixtures[startsWith(round_raw, "Regular Season"), ]
  round_raw <- round_raw[startsWith(round_raw, "Regular Season")]

  fixture_id <- vapply(fixtures$fixture, function(x) x$id[[1]], numeric(1))
  date_raw <- vapply(fixtures$fixture, function(x) x$date[[1]], character(1))
  status <- vapply(fixtures$fixture, function(x) x$status[[1]]$short[[1]], character(1))
  round <- as.integer(sub(".*-\\s*", "", round_raw))

  home_id <- vapply(fixtures$teams, function(x) x$home[[1]]$id[[1]], numeric(1))
  home_name <- vapply(fixtures$teams, function(x) x$home[[1]]$name[[1]], character(1))
  away_id <- vapply(fixtures$teams, function(x) x$away[[1]]$id[[1]], numeric(1))
  away_name <- vapply(fixtures$teams, function(x) x$away[[1]]$name[[1]], character(1))

  goals_home <- vapply(fixtures$goals, function(x) as.numeric(x$home[[1]]), numeric(1))
  goals_away <- vapply(fixtures$goals, function(x) as.numeric(x$away[[1]]), numeric(1))

  # Anstoßzeit als POSIXct in UTC parsen. Format wie
  # "2026-11-27T19:30:00+00:00" (Offset-Doppelpunkt entfernen für %z) oder
  # mit "Z"-Suffix.
  date_clean <- sub("Z$", "+0000", date_raw)
  date_clean <- sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", date_clean)
  kickoff <- as.POSIXct(date_clean, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  attr(kickoff, "tzone") <- "UTC"

  data.frame(
    fixture_id = fixture_id,
    round = round,
    kickoff = kickoff,
    status = status,
    home_id = home_id,
    away_id = away_id,
    home_name = home_name,
    away_name = away_name,
    goals_home = goals_home,
    goals_away = goals_away,
    stringsAsFactors = FALSE
  )
}

classify_matchday_status <- function(details) {
  rounds <- sort(unique(details$round))
  result <- vapply(rounds, function(r) {
    rows <- details[details$round == r, ]
    any_beendet <- any(rows$status %in% STATUS_BEENDET)
    any_live <- any(rows$status %in% STATUS_LIVE)
    alle_beendet_oder_verschoben <- all(rows$status %in% c(STATUS_BEENDET, STATUS_VERSCHOBEN))
    begonnen <- any_beendet || any_live

    if (any_beendet && !any_live && alle_beendet_oder_verschoben) {
      "abgeschlossen"
    } else if (begonnen) {
      "laufend"
    } else {
      "ausstehend"
    }
  }, character(1))
  names(result) <- as.character(rounds)
  result
}

current_matchday <- function(details) {
  status <- classify_matchday_status(details)
  begonnen_rounds <- as.integer(names(status)[status %in% c("abgeschlossen", "laufend")])
  if (length(begonnen_rounds) == 0) {
    return(NA_integer_)
  }
  max(begonnen_rounds)
}

rueckblick_matches <- function(details) {
  empty <- details[0, ]
  empty$nachholspiel <- logical(0)

  aktuell <- current_matchday(details)
  if (is.na(aktuell)) {
    return(empty)
  }

  status <- classify_matchday_status(details)
  abgeschlossene_rounds <- as.integer(names(status)[status == "abgeschlossen"])
  abgeschlossene_rounds <- abgeschlossene_rounds[abgeschlossene_rounds <= aktuell]

  if (length(abgeschlossene_rounds) > 0) {
    anker_round <- max(abgeschlossene_rounds)
    anker <- min(details$kickoff[details$round == anker_round])
  } else {
    anker_round <- aktuell
    anker <- min(details$kickoff[details$round == aktuell])
  }

  rows <- details[details$status %in% STATUS_BEENDET & details$kickoff >= anker, ]
  rows <- rows[order(rows$kickoff), ]
  rows$nachholspiel <- rows$round < anker_round
  rownames(rows) <- NULL
  rows
}

ausblick_matches <- function(details) {
  empty <- details[0, ]
  empty$nachholspiel <- logical(0)

  aktuell <- current_matchday(details)
  status <- classify_matchday_status(details)

  offen_status <- !(details$status %in% c(STATUS_BEENDET, STATUS_LIVE, STATUS_VERSCHOBEN))

  if (!is.na(aktuell) && unname(status[[as.character(aktuell)]]) == "laufend" &&
      any(details$round == aktuell & offen_status)) {
    ziel <- aktuell
  } else {
    if (!is.na(aktuell)) {
      kandidaten <- unique(details$round[details$round > aktuell & offen_status])
    } else {
      kandidaten <- unique(details$round[offen_status])
    }
    if (length(kandidaten) == 0) {
      return(empty)
    }
    ziel <- min(kandidaten)
  }

  fensterende <- max(details$kickoff[details$round == ziel & offen_status])

  rows <- details[offen_status & details$kickoff <= fensterende, ]
  rows <- rows[order(rows$kickoff), ]
  rows$nachholspiel <- rows$round < ziel
  rownames(rows) <- NULL
  rows
}

live_matches <- function(details) {
  rows <- details[details$status %in% STATUS_LIVE, ]
  rows <- rows[order(rows$kickoff), ]
  rownames(rows) <- NULL
  rows
}

build_league_table <- function(details, teams) {
  finished <- details[details$status %in% STATUS_BEENDET, ]

  team_ids <- teams$TeamID
  spiele <- integer(length(team_ids))
  tore <- numeric(length(team_ids))
  gegentore <- numeric(length(team_ids))
  punkte <- numeric(length(team_ids))

  for (i in seq_along(team_ids)) {
    id <- team_ids[i]
    heim <- finished[finished$home_id == id, ]
    gast <- finished[finished$away_id == id, ]

    spiele[i] <- nrow(heim) + nrow(gast)
    tore[i] <- sum(heim$goals_home) + sum(gast$goals_away)
    gegentore[i] <- sum(heim$goals_away) + sum(gast$goals_home)

    pkt_heim <- sum(ifelse(heim$goals_home > heim$goals_away, 3,
                            ifelse(heim$goals_home == heim$goals_away, 1, 0)))
    pkt_gast <- sum(ifelse(gast$goals_away > gast$goals_home, 3,
                            ifelse(gast$goals_away == gast$goals_home, 1, 0)))
    punkte[i] <- pkt_heim + pkt_gast
  }

  tordifferenz <- tore - gegentore

  tab <- data.frame(
    team_id = team_ids,
    spiele = spiele,
    tore = tore,
    gegentore = gegentore,
    tordifferenz = tordifferenz,
    punkte = punkte,
    stringsAsFactors = FALSE
  )

  ord <- order(-tab$punkte, -tab$tordifferenz, -tab$tore)
  tab <- tab[ord, ]
  tab$platz <- seq_len(nrow(tab))
  rownames(tab) <- NULL

  tab[, c("platz", "team_id", "spiele", "tore", "gegentore", "tordifferenz", "punkte")]
}

build_league_details_payload <- function(details, teams, mod_factor = 20,
                                         home_advantage = 65, max_goals = 6) {
  schedule <- lapply(seq_len(nrow(details)), function(i) {
    row <- details[i, ]
    heim_idx <- match(row$home_id, teams$TeamID)
    gast_idx <- match(row$away_id, teams$TeamID)

    # Unbekannte Team-IDs führen zu einem Fehler mit der ID in der Meldung
    if (is.na(heim_idx)) {
      stop("Unknown team ID: ", row$home_id)
    }
    if (is.na(gast_idx)) {
      stop("Unknown team ID: ", row$away_id)
    }

    # Tore nur senden, wenn Status beendet UND beide Tore nicht NA sind
    if (row$status %in% STATUS_BEENDET && !is.na(row$goals_home) && !is.na(row$goals_away)) {
      tore_h <- row$goals_home
      tore_g <- row$goals_away
    } else {
      tore_h <- NULL
      tore_g <- NULL
    }
    list(heim_idx, gast_idx, tore_h, tore_g)
  })

  list(
    schedule = schedule,
    elo_values = teams$InitialELO,
    team_names = teams$ShortText,
    mod_factor = mod_factor,
    home_advantage = home_advantage,
    max_goals = max_goals
  )
}

parse_league_details_response <- function(json_text) {
  parsed <- jsonlite::fromJSON(json_text)

  matches <- parsed$matches
  matches$score_matrix <- lapply(matches$score_matrix, function(m) {
    as.matrix(m)
  })

  list(
    matches = matches,
    current_elos = parsed$current_elos,
    team_names = parsed$team_names
  )
}
