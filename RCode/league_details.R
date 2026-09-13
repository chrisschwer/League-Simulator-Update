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
#     gewertet   = AWD, WO  (am grünen Tisch entschieden)
#     live       = 1H, HT, 2H, ET, BT, P, SUSP, INT, LIVE
#     verschoben = PST, CANC, TBD, ABD
#     offen      = alles andere (insb. NS)
#   Für Fensterung und Tabelle zählen beendete und gewertete Spiele gleich
#   (STATUS_ERGEBNIS); nur der ELO-Walk unterscheidet sie -- siehe
#   build_league_details_payload() und Issue #157.
# - Ein Spieltag ist "abgeschlossen", wenn mindestens ein Spiel ein Ergebnis
#   hat, kein Spiel live ist und jedes Spiel ein Ergebnis hat oder verschoben
#   ist;
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

# Rundenfilter (Negativliste) und Postcondition -- pfadunabhaengig, siehe
# gleichlautender Block in transform_data.R.
if (!exists("is_regular_season_round") || !exists("assert_rounds_kept")) {
  local({
    d <- NULL
    for (f in rev(sys.frames())) {
      if (!is.null(f$ofile)) {
        d <- dirname(f$ofile)
        break
      }
    }
    if (is.null(d) || is.na(d) || !nzchar(d)) d <- "RCode"
    source(file.path(d, "round_filter.R"))
  })
}

STATUS_BEENDET <- c("FT", "AET", "PEN")
STATUS_LIVE <- c("1H", "HT", "2H", "ET", "BT", "P", "SUSP", "INT", "LIVE")
STATUS_VERSCHOBEN <- c("PST", "CANC", "TBD", "ABD")
# Gewertete Spiele (Wertung am grünen Tisch / kampflos). Sportrechtlich ein
# Ergebnis: Sie zählen für Tabelle und Fensterung wie beendete Spiele, bleiben
# aber aus dem ELO-Walk heraus, weil sie nichts über Spielstärke sagen
# (Issue #157). Der Ausschluss sitzt an genau einer Stelle --
# build_league_details_payload(), siehe dort.
STATUS_AWARDED <- c("AWD", "WO")

# Spiele mit feststehendem Ergebnis: beendet oder gewertet. Das ist die
# Statusmenge für Fensterung und Tabelle -- NICHT die für das ELO.
STATUS_ERGEBNIS <- c(STATUS_BEENDET, STATUS_AWARDED)

extract_fixture_details <- function(fixtures) {
  # api-football fixtures arrive in two shapes depending on how the caller
  # built them: FLACH (production, via retrieveResults()/jsonlite::fromJSON's
  # default simplification) has fixture/league/teams/goals as data.frames
  # with atomic or df columns (fixtures$league$round works directly,
  # fixtures$teams$home is itself a data.frame). GENESTET (the frozen test
  # mocks, hand-built tibbles) has them as LIST columns of one-row
  # data.frames per fixture (fixtures$league is a list, so
  # fixtures$league$round is NULL and each round lives at
  # fixtures$league[[i]]$round instead). Spiegelfall zum
  # transform_data()-List-Column-Fix aus Phase 2. Detect via is.data.frame()
  # and normalize both into plain atomic vectors before proceeding.
  flach <- is.data.frame(fixtures$league)

  if (flach) {
    round_raw <- as.character(fixtures$league$round)
  } else {
    round_raw <- vapply(fixtures$league, function(x) x$round[[1]], character(1))
  }

  keep <- is_regular_season_round(round_raw)
  assert_rounds_kept(length(round_raw), sum(keep), round_raw,
                     "extract_fixture_details")
  round_raw <- round_raw[keep]
  fixtures <- fixtures[keep, ]

  if (flach) {
    fixture_id <- as.numeric(fixtures$fixture$id)
    date_raw <- as.character(fixtures$fixture$date)
    status <- as.character(fixtures$fixture$status$short)

    home_id <- as.numeric(fixtures$teams$home$id)
    home_name <- as.character(fixtures$teams$home$name)
    away_id <- as.numeric(fixtures$teams$away$id)
    away_name <- as.character(fixtures$teams$away$name)

    goals_home <- as.numeric(fixtures$goals$home)
    goals_away <- as.numeric(fixtures$goals$away)
  } else {
    fixture_id <- vapply(fixtures$fixture, function(x) x$id[[1]], numeric(1))
    date_raw <- vapply(fixtures$fixture, function(x) x$date[[1]], character(1))
    status <- vapply(fixtures$fixture, function(x) x$status[[1]]$short[[1]], character(1))

    home_id <- vapply(fixtures$teams, function(x) x$home[[1]]$id[[1]], numeric(1))
    home_name <- vapply(fixtures$teams, function(x) x$home[[1]]$name[[1]], character(1))
    away_id <- vapply(fixtures$teams, function(x) x$away[[1]]$id[[1]], numeric(1))
    away_name <- vapply(fixtures$teams, function(x) x$away[[1]]$name[[1]], character(1))

    goals_home <- vapply(fixtures$goals, function(x) as.numeric(x$home[[1]]), numeric(1))
    goals_away <- vapply(fixtures$goals, function(x) as.numeric(x$away[[1]]), numeric(1))
  }

  round <- as.integer(sub(".*-\\s*", "", round_raw))

  # Anstoßzeit als POSIXct in UTC parsen. Format wie
  # "2026-11-27T19:30:00+00:00" (Offset-Doppelpunkt entfernen für %z) oder
  # mit "Z"-Suffix.
  date_clean <- sub("Z$", "+0000", date_raw)
  date_clean <- sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", date_clean)
  kickoff <- as.POSIXct(date_clean, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  attr(kickoff, "tzone") <- "UTC"

  # WARUM HIER SORTIERT WIRD (Design 2026-09-12, Teil 1): Der Rust-ELO-Walk
  # verarbeitet den `schedule` aus build_league_details_payload() in genau
  # der Reihenfolge, in der er hier ankommt. Bisher war das die
  # API-Reihenfolge -- bei einem Nachholspiel weicht die vom Kalender ab, und
  # der Walk verrechnet es mit ELO-Staenden, die zum Anstosszeitpunkt nicht
  # mehr galten. rueckblick_matches()/ausblick_matches()/live_matches()
  # sortieren zwar schon nach kickoff, aber nur fuer die ANZEIGE --
  # build_league_details_payload() bekam bislang das unsortierte `details`.
  #
  # Sortierschluessel: Anstosszeit aufsteigend, bei Gleichstand die
  # Eingabereihenfolge (API-Reihenfolge). `order()` ist stabil, das allein
  # reicht fuer den Tiebreak -- solange nur einmal sortiert wird. `NA`-Zeiten
  # (Spiel ohne Termin) schiebt `order(..., na.last = TRUE)` ans Ende, statt
  # mit "object not found" abzustuerzen oder die Sortierung ganz zu verweigern.
  reihenfolge <- order(kickoff, na.last = TRUE)

  ergebnis <- data.frame(
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
  )[reihenfolge, ]
  rownames(ergebnis) <- NULL
  ergebnis
}

classify_matchday_status <- function(details) {
  rounds <- sort(unique(details$round))
  result <- vapply(rounds, function(r) {
    rows <- details[details$round == r, ]
    any_beendet <- any(rows$status %in% STATUS_ERGEBNIS)
    any_live <- any(rows$status %in% STATUS_LIVE)
    alle_beendet_oder_verschoben <- all(rows$status %in% c(STATUS_ERGEBNIS, STATUS_VERSCHOBEN))
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

  rows <- details[details$status %in% STATUS_ERGEBNIS & details$kickoff >= anker, ]
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

  offen_status <- !(details$status %in% c(STATUS_ERGEBNIS, STATUS_LIVE, STATUS_VERSCHOBEN))

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
  # Gewertete Spiele zählen sportrechtlich und gehören in die Tabelle. Anders
  # als bei beendeten Spielen sind die Tore hier aber nicht garantiert:
  # api-football liefert bei einer Wertung üblicherweise 3:0, aber nicht
  # zwingend. Ohne diesen Filter erzeugte die Summenbildung unten NA in
  # Punkten und Toren -- eine unbrauchbare Tabelle wäre schlimmer als ein
  # fehlendes Spiel (Issue #157).
  finished <- details[details$status %in% STATUS_ERGEBNIS &
                        !is.na(details$goals_home) &
                        !is.na(details$goals_away), ]

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
                                         home_advantage = NULL, max_goals = 6,
                                         tore_slope = NULL,
                                         tore_intercept = NULL) {
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

    # Tore nur senden, wenn Status beendet UND beide Tore nicht NA sind.
    #
    # STATUS_BEENDET, nicht STATUS_ERGEBNIS -- das ist Absicht, kein
    # vergessener Fall: Ein gewertetes Spiel zählt für Tabelle und Fensterung,
    # darf die Stärkeschätzung aber nicht bewegen. Der Seam ist torbasiert;
    # Rust leitet "gespielt" allein aus der Präsenz beider Tore ab. Würden die
    # Tore hier mitgesendet, liefe das Wertungsergebnis ins ELO (Issue #157).
    #
    # Die Simulation (transform_data + /simulate) braucht die Tore dagegen für
    # die Endtabelle und bekommt sie -- dort trennt das Flag `elo_neutral`
    # zwischen Ergebnis und ELO. Hier genügt das Weglassen, weil
    # /league-details ohnehin keine Endtabelle rechnet.
    if (row$status %in% STATUS_BEENDET && !is.na(row$goals_home) && !is.na(row$goals_away)) {
      tore_h <- row$goals_home
      tore_g <- row$goals_away
    } else {
      tore_h <- NULL
      tore_g <- NULL
    }
    list(heim_idx, gast_idx, tore_h, tore_g)
  })

  payload <- list(
    schedule = schedule,
    elo_values = teams$InitialELO,
    team_names = teams$ShortText,
    mod_factor = mod_factor,
    max_goals = max_goals
  )

  # home_advantage bleibt bewusst aus dem Payload: Die Modellkonstante lebt
  # ausschliesslich im Rust-Server (ADR 0002), damit Prognose (Heatmap) und
  # Spieldetails (1/X/2, Score-Matrix) nicht auseinanderlaufen koennen. Nur
  # ein explizit uebergebener Wert ueberschreibt sie.
  if (!is.null(home_advantage)) {
    payload$home_advantage <- home_advantage
  }

  # Tormodell je Wechselgemeinschaft. BEIDE Endpunkte zwingend gemeinsam:
  # Liefen Prognose-Heatmap (/simulate) und Score-Matrix (/league-details) mit
  # verschiedenen Tormodellen, widersprächen sich die Zahlen auf derselben
  # Seite (ADR 0004). Die Registry ist die eine Quelle für beide.
  if (!is.null(tore_slope)) payload$tore_slope <- tore_slope
  if (!is.null(tore_intercept)) payload$tore_intercept <- tore_intercept

  payload
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

# --- Phase 4a: Verdrahtung ---------------------------------------------------

# Dünner httr-Client für POST /league-details; base_url-Default folgt der
# RUST_API_URL-Konvention aus rust_integration.R. Rückgabe: Response-Body als
# JSON-Text (wird von parse_league_details_response() geparst).
fetch_league_details <- function(payload,
                                 base_url = Sys.getenv("RUST_API_URL",
                                                       "http://localhost:8080")) {
  # digits = NA: volle Praezision -- siehe gleichlautende Stelle in
  # rust_integration.R. Beide Endpunkte muessen dasselbe Tormodell sehen
  # (ADR 0004), also auch dieselbe Genauigkeit.
  json_body <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null",
                                digits = NA)

  response <- httr::POST(
    paste0(base_url, "/league-details"),
    body = json_body,
    httr::content_type_json(),
    httr::accept_json()
  )

  if (httr::status_code(response) != 200) {
    error_body <- httr::content(response, "text", encoding = "UTF-8")
    stop(sprintf("league-details request failed with status %d: %s",
                 httr::status_code(response), error_body))
  }

  httr::content(response, "text", encoding = "UTF-8")
}

# Verdrahtung je Liga: rohe Fixtures + TeamList -> render-fertige Strukturen
# (details, teams, matches, current_elos, tabelle); NULL mit Warnung bei
# Endpoint-Fehlern (Degradation auf Phase-3-Seite).
#
# @param tormodell Abweichendes Tormodell (ADR 0004, Issue #205), Liste aus
#   goal_model_args() -- leer (Default), wo die Rust-Defaults gelten. Der
#   Aufrufer (update_all_leagues_loop.R) kennt die Liga-ID und uebergibt die
#   fertige Liste; diese Funktion bleibt damit frei von einer Abhaengigkeit
#   auf league_registry.R, analog zu rl_aktuelle_elo(spielplan, tormodell)
#   in rl_verdrahtung.R.
build_league_page_data <- function(fixtures, teams,
                                   fetch_fn = fetch_league_details,
                                   tormodell = list()) {
  tryCatch({
    details <- extract_fixture_details(fixtures)

    liga_teams <- teams[teams$TeamID %in% c(details$home_id, details$away_id), ]

    payload <- build_league_details_payload(details, liga_teams,
                                            tore_slope = tormodell$tore_slope,
                                            tore_intercept = tormodell$tore_intercept)
    response_json <- fetch_fn(payload)
    parsed <- parse_league_details_response(response_json)

    # matches: Details-Zeile i <-> Response-Index i-1 (positionsgleich).
    matches <- cbind(details, parsed$matches)

    # tabelle: Grundgerüst aus build_league_table(), angereichert um Name
    # (id-Join, NIE positional), ELO (current_elos in Teams-Reihenfolge,
    # id-Join) und Delta-ELO gegen InitialELO.
    tabelle <- build_league_table(details, liga_teams)

    name_by_id <- setNames(details$home_name, details$home_id)
    name_by_id[as.character(details$away_id)] <- details$away_name
    tabelle$name <- unname(name_by_id[as.character(tabelle$team_id)])

    elo_by_id <- setNames(parsed$current_elos, liga_teams$TeamID)
    tabelle$elo <- unname(elo_by_id[as.character(tabelle$team_id)])

    initial_elo_by_id <- setNames(liga_teams$InitialELO, liga_teams$TeamID)
    tabelle$delta_elo <- tabelle$elo -
      unname(initial_elo_by_id[as.character(tabelle$team_id)])

    # Rückblick/Live: Fensterung liefert Zeilen aus `details` (ggf. neu
    # geordnet/reduziert); die Endpoint-Spalten werden per fixture_id gegen
    # `matches` gejoint — NIE über die Fenster-Reihenfolge, da die
    # Fensterfunktionen chronologisch sortieren, während `matches` die
    # ursprüngliche Details-Reihenfolge (= Response-Index) trägt.
    endpoint_cols <- setdiff(names(parsed$matches), names(details))
    join_endpoint <- function(rows) {
      idx <- match(rows$fixture_id, matches$fixture_id)
      cbind(rows, matches[idx, endpoint_cols, drop = FALSE])
    }

    rueckblick <- join_endpoint(rueckblick_matches(details))
    live <- join_endpoint(live_matches(details))

    ausblick_ziel <- ausblick_matches(details)
    ausblick <- join_endpoint(ausblick_ziel)

    rueckblick_runden <- sort(unique(rueckblick$round[!rueckblick$nachholspiel]))
    ausblick_runden <- if (nrow(ausblick_ziel) > 0) {
      sort(unique(ausblick_ziel$round[!ausblick_ziel$nachholspiel]))
    } else {
      integer(0)
    }
    ausblick_runde <- if (length(ausblick_runden) > 0) {
      min(ausblick_runden)
    } else {
      NA_integer_
    }

    list(
      details = details,
      teams = liga_teams,
      matches = matches,
      current_elos = parsed$current_elos,
      tabelle = tabelle,
      rueckblick = rueckblick,
      live = live,
      ausblick = ausblick,
      spieltag = list(rueckblick = rueckblick_runden, ausblick = ausblick_runde)
    )
  }, error = function(e) {
    warning(e$message)
    NULL
  })
}
