library(testthat)
source("../../RCode/league_details.R")

# build_league_page_data(): die Phase-4a-Verdrahtung. Nimmt die rohen
# api-football-Fixtures einer Liga plus die (ligaübergreifende) TeamList,
# holt die Spieldetails vom Rust-Endpoint (injizierbar über fetch_fn) und
# liefert render-fertige Strukturen. Schlägt der Endpoint fehl, kommt NULL
# mit Warnung zurück — die Seite degradiert dann auf den Phase-3-Stand.

nested_league_fixtures <- function() {
  tibble::tibble(
    fixture = list(
      data.frame(
        id = 2001, date = "2026-08-28T18:30:00+00:00",
        status = I(list(data.frame(short = "FT")))
      ),
      data.frame(
        id = 2002, date = "2026-08-29T13:30:00+00:00",
        status = I(list(data.frame(short = "FT")))
      ),
      data.frame(
        id = 2003, date = "2026-09-04T18:30:00+00:00",
        status = I(list(data.frame(short = "NS")))
      )
    ),
    league = list(
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 2")
    ),
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "FC Alpha"))),
        away = I(list(data.frame(id = 102, name = "SV Beta")))
      ),
      data.frame(
        home = I(list(data.frame(id = 103, name = "TSV Gamma"))),
        away = I(list(data.frame(id = 104, name = "1. FC Delta")))
      ),
      data.frame(
        home = I(list(data.frame(id = 102, name = "SV Beta"))),
        away = I(list(data.frame(id = 103, name = "TSV Gamma")))
      )
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = 0, away = 0),
      data.frame(home = NA, away = NA)
    )
  )
}

# TeamList wie in Produktion: enthält auch Teams ANDERER Ligen, die
# herausgefiltert werden müssen.
teamlist_all_leagues <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104, 999),
    ShortText = c("ALP", "BET", "GAM", "DEL", "XXX"),
    Promotion = c(0, 0, 0, 0, 0),
    InitialELO = c(1500, 1480, 1520, 1500, 1700),
    stringsAsFactors = FALSE
  )
}

# Antwort des Endpoints, passend zu den drei Spielen oben (Indizes 0..2,
# Teamindizes 1-basiert in TeamList-Reihenfolge der LIGA-Teams 101..104).
canned_page_response <- function() {
  paste0('{
    "matches": [
      {"index": 0, "team_home": 1, "team_away": 2, "played": true,
       "goals_home": 2, "goals_away": 1,
       "elo_home_pre": 1500.0, "elo_away_pre": 1480.0,
       "elo_delta_home": 7.5,
       "lambda_home": 1.45, "lambda_away": 1.2,
       "p_home_win": 0.44, "p_draw": 0.26, "p_away_win": 0.30,
       "score_matrix": [[0.5, 0.5], [0.0, 0.0]]},
      {"index": 1, "team_home": 3, "team_away": 4, "played": true,
       "goals_home": 0, "goals_away": 0,
       "elo_home_pre": 1520.0, "elo_away_pre": 1500.0,
       "elo_delta_home": -1.8,
       "lambda_home": 1.4, "lambda_away": 1.25,
       "p_home_win": 0.43, "p_draw": 0.26, "p_away_win": 0.31,
       "score_matrix": [[0.5, 0.5], [0.0, 0.0]]},
      {"index": 2, "team_home": 2, "team_away": 3, "played": false,
       "goals_home": null, "goals_away": null,
       "elo_home_pre": 1487.5, "elo_away_pre": 1518.2,
       "elo_delta_home": null,
       "lambda_home": 1.3, "lambda_away": 1.35,
       "p_home_win": 0.38, "p_draw": 0.27, "p_away_win": 0.35,
       "score_matrix": [[0.4, 0.6], [0.0, 0.0]]}
    ],
    "current_elos": [1507.5, 1485.7, 1516.4, 1501.8],
    "team_names": ["ALP", "BET", "GAM", "DEL"]
  }')
}

test_that("build_league_page_data liefert render-fertige Strukturen", {
  captured_payload <- NULL
  fetch_stub <- function(payload, ...) {
    captured_payload <<- payload
    canned_page_response()
  }

  pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                               fetch_fn = fetch_stub)

  expect_type(pd, "list")
  expect_true(all(c("details", "teams", "matches", "current_elos", "tabelle")
                  %in% names(pd)))

  # Teams sind auf die Liga gefiltert (999/XXX fliegt raus), Reihenfolge
  # bleibt TeamList-Reihenfolge — darauf beruhen die 1-basierten Indizes.
  expect_equal(pd$teams$TeamID, c(101, 102, 103, 104))
  expect_equal(captured_payload$elo_values, c(1500, 1480, 1520, 1500))
  expect_length(captured_payload$schedule, 3)
})

test_that("matches joint Details und Endpoint-Antwort positionsgleich", {
  pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                               fetch_fn = function(...) canned_page_response())

  m <- pd$matches
  expect_equal(nrow(m), 3)
  # Zeile 1 = fixture 2001 = Response-Index 0
  expect_equal(m$fixture_id, c(2001, 2002, 2003))
  expect_equal(m$p_home_win, c(0.44, 0.43, 0.38))
  expect_equal(m$elo_delta_home[1], 7.5)
  expect_true(is.na(m$elo_delta_home[3]))
  expect_equal(m$played, c(TRUE, TRUE, FALSE))
  # Fixture-Spalten bleiben erhalten (fürs Rendering)
  expect_true(all(c("round", "kickoff", "status", "home_name", "away_name")
                  %in% names(m)))
  expect_true(is.list(m$score_matrix))
})

test_that("tabelle ist mit Namen, ELO und Delta angereichert und sortiert", {
  pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                               fetch_fn = function(...) canned_page_response())

  tab <- pd$tabelle
  expect_true(all(c("platz", "team_id", "name", "spiele", "tore", "gegentore",
                    "tordifferenz", "punkte", "elo", "delta_elo")
                  %in% names(tab)))
  expect_equal(tab$platz, seq_len(nrow(tab)))

  # Nach 2:1 (Alpha) und 0:0 (Gamma/Delta): Alpha 3 Pkt, Gamma/Delta 1, Beta 0.
  expect_equal(tab$team_id[1], 101)
  expect_equal(tab$name[1], "FC Alpha")
  expect_equal(tab$punkte[1], 3)

  # ELO aus current_elos (TeamList-Reihenfolge), Delta gegen InitialELO.
  reihe_alpha <- tab[tab$team_id == 101, ]
  expect_equal(reihe_alpha$elo, 1507.5)
  expect_equal(reihe_alpha$delta_elo, 7.5)
  reihe_beta <- tab[tab$team_id == 102, ]
  expect_equal(reihe_beta$elo, 1485.7)
  expect_equal(reihe_beta$delta_elo, 1485.7 - 1480)
})

test_that("die team_id-zu-Name-Zuordnung übersteht die Tabellensortierung", {
  # Verwechslungs-Guard: Die Tabelle ist nach Punkten sortiert und weicht
  # damit von der TeamList-Reihenfolge ab (SV Beta: TeamList-Position 2,
  # Tabellenplatz 4). Ein positionaler Join statt eines id-Joins würde hier
  # falsche Namen liefern — jede Zeile muss den Namen IHRER team_id tragen.
  pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                               fetch_fn = function(...) canned_page_response())

  tab <- pd$tabelle
  erwartet <- c("101" = "FC Alpha", "102" = "SV Beta",
                "103" = "TSV Gamma", "104" = "1. FC Delta")
  expect_equal(
    unname(erwartet[as.character(tab$team_id)]),
    tab$name
  )
  # Der diskriminierende Fall explizit: Beta steht NICHT auf TeamList-Position
  expect_equal(tab$team_id[nrow(tab)], 102)
  expect_equal(tab$name[nrow(tab)], "SV Beta")
})

test_that("ein Endpoint-Fehler degradiert zu NULL mit Warnung", {
  expect_warning(
    pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                                 fetch_fn = function(...) stop("connection refused")),
    "connection refused"
  )
  expect_null(pd)
})

test_that("fetch_league_details existiert als httr-Client mit RUST_API_URL-Default", {
  # Nur Signatur-/Existenzprüfung — der HTTP-Weg selbst wird nicht getestet,
  # build_league_page_data injiziert ihn als Default.
  expect_true(is.function(fetch_league_details))
  expect_true(all(c("payload") %in% names(formals(fetch_league_details))))
})

# --- Issue #205: das abweichende Tormodell (ADR 0004) muss den Payload
# --- erreichen, sonst laufen Score-Matrix und 1/X/2 der Frauen-Ligen mit
# --- den Herren-Werten. build_league_page_data() bekommt dafuer einen
# --- `tormodell`-Parameter (Liste aus goal_model_args(), Default `list()`)
# --- und reicht ihn an build_league_details_payload() durch -- analog zu
# --- rl_aktuelle_elo(spielplan, tormodell) in rl_verdrahtung.R.

test_that("ein uebergebenes tormodell erreicht den league-details-Payload", {
  captured_payload <- NULL
  fetch_stub <- function(payload, ...) {
    captured_payload <<- payload
    canned_page_response()
  }

  pd <- build_league_page_data(
    nested_league_fixtures(), teamlist_all_leagues(),
    fetch_fn = fetch_stub,
    tormodell = list(tore_slope = 0.0024058833, tore_intercept = 1.6527603153)
  )

  expect_false(is.null(pd))
  expect_equal(captured_payload$tore_slope, 0.0024058833)
  expect_equal(captured_payload$tore_intercept, 1.6527603153)
})

test_that("ohne tormodell bleibt der Payload frei von tore_slope/tore_intercept", {
  # Gegenprobe: der Herren-Fall (leere Liste, wie goal_model_args() sie fuer
  # Liga 78 liefert). Der Rust-Server soll seine Defaults behalten (ADR 0002).
  captured_payload <- NULL
  fetch_stub <- function(payload, ...) {
    captured_payload <<- payload
    canned_page_response()
  }

  pd <- build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                               fetch_fn = fetch_stub)

  expect_false(is.null(pd))
  expect_false("tore_slope" %in% names(captured_payload))
  expect_false("tore_intercept" %in% names(captured_payload))
})

# --- aus test-league-page-data-rueckblick.R ---

# Phase 4b: build_league_page_data() liefert zusätzlich die gefensterten,
# mit Endpoint-Werten gejointen Spiellisten für Rückblick und Live-Sektion
# sowie die Spieltagsnummern für die Überschriften. Die Fensterlogik selbst
# ist in der eingefrorenen Phase-2-Suite gepinnt — hier geht es um die
# Integration: Join-Integrität nach der Fensterung und die neuen Felder.

# 4 Teams, 3 Runden: Runde 1 komplett (2 FT), Runde 2 laufend (1 FT, 1 live),
# Runde 3 offen (2 NS). Kickoffs chronologisch.
vier_runden_fixtures <- function() {
  mk_fix <- function(id, date, status) {
    data.frame(id = id, date = date, status = I(list(data.frame(short = status))))
  }
  mk_teams <- function(hid, hname, aid, aname) {
    data.frame(home = I(list(data.frame(id = hid, name = hname))),
               away = I(list(data.frame(id = aid, name = aname))))
  }
  tibble::tibble(
    fixture = list(
      mk_fix(4001, "2026-11-20T19:30:00+00:00", "FT"),
      mk_fix(4002, "2026-11-21T14:30:00+00:00", "FT"),
      mk_fix(4003, "2026-11-27T19:30:00+00:00", "FT"),
      mk_fix(4004, "2026-11-28T14:30:00+00:00", "1H"),
      mk_fix(4005, "2026-12-04T19:30:00+00:00", "NS"),
      mk_fix(4006, "2026-12-05T14:30:00+00:00", "NS")
    ),
    league = list(
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 2"),
      data.frame(round = "Regular Season - 2"),
      data.frame(round = "Regular Season - 3"),
      data.frame(round = "Regular Season - 3")
    ),
    teams = list(
      mk_teams(101, "FC Alpha", 102, "SV Beta"),
      mk_teams(103, "TSV Gamma", 104, "1. FC Delta"),
      mk_teams(102, "SV Beta", 103, "TSV Gamma"),
      mk_teams(101, "FC Alpha", 104, "1. FC Delta"),
      mk_teams(102, "SV Beta", 104, "1. FC Delta"),
      mk_teams(103, "TSV Gamma", 101, "FC Alpha")
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = 0, away = 0),
      data.frame(home = 1, away = 1),
      data.frame(home = 1, away = 0),   # Live-Zwischenstand
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    )
  )
}

vier_runden_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("ALP", "BET", "GAM", "DEL"),
    Promotion = c(0, 0, 0, 0),
    InitialELO = c(1500, 1480, 1520, 1500),
    stringsAsFactors = FALSE
  )
}

# Antwort mit 6 Spielen (Indizes 0..5); das Live-Spiel (Index 3) geht ohne
# Tore in den Payload und kommt als ungespielt zurück.
vier_runden_response <- function() {
  eintrag <- function(index, th, ta, played, gh, ga, delta, ph, px, pa) {
    sprintf(paste0(
      '{"index": %d, "team_home": %d, "team_away": %d, "played": %s,',
      ' "goals_home": %s, "goals_away": %s,',
      ' "elo_home_pre": 1500.0, "elo_away_pre": 1500.0,',
      ' "elo_delta_home": %s,',
      ' "lambda_home": 1.4, "lambda_away": 1.2,',
      ' "p_home_win": %s, "p_draw": %s, "p_away_win": %s,',
      ' "score_matrix": [[0.5, 0.5], [0.0, 0.0]]}'
    ), index, th, ta, played, gh, ga, delta, ph, px, pa)
  }
  # ANGEPASST (#146): Die Antwort folgt jetzt der Reihenfolge des
  # GESENDETEN Payloads statt einer festen Liste.
  #
  # Vorher waren die sechs Eintraege hart in API-Reihenfolge notiert. Das
  # traf zu, solange extract_fixture_details() unsortiert durchreichte --
  # seit der chronologischen Sortierung nicht mehr, und der positionale
  # cbind in build_league_page_data() klebte die Werte an die falschen
  # Zeilen.
  #
  # Der echte Server verhaelt sich so, wie es hier jetzt nachgebildet ist:
  # `index` ist laut league_details/mod.rs:40 "Position im Request-Schedule".
  # Am laufenden Server gegengeprueft, mit einem Payload, dessen fixture_ids
  # absichtlich nicht aufsteigend waren -- die Antwort folgte dem Gesendeten.
  #
  # Damit ist der Mock immun gegen kuenftige Sortieraenderungen: Er
  # antwortet auf das, was tatsaechlich geschickt wurde.
  werte <- list(
    # Schluessel: "team_home-team_away" (1-basierte Team-Indizes)
    "1-2" = list("7.5", "0.44", "0.26", "0.30"),
    "3-4" = list("-1.8", "0.43", "0.26", "0.31"),
    "2-3" = list("2.1", "0.38", "0.27", "0.35"),
    "1-4" = list("null", "0.41", "0.27", "0.32"),
    "2-4" = list("null", "0.40", "0.26", "0.34"),
    "3-1" = list("null", "0.45", "0.26", "0.29")
  )

  function(payload) {
    teile <- vapply(seq_along(payload$schedule), function(i) {
      zeile <- payload$schedule[[i]]
      th <- zeile[[1]]
      ta <- zeile[[2]]
      gh <- zeile[[3]]
      ga <- zeile[[4]]
      gespielt <- !is.null(gh) && !is.na(gh) && !is.null(ga) && !is.na(ga)
      w <- werte[[paste0(th, "-", ta)]]
      eintrag(
        i - 1L, th, ta,
        if (gespielt) "true" else "false",
        if (gespielt) as.character(gh) else "null",
        if (gespielt) as.character(ga) else "null",
        if (gespielt) w[[1]] else "null",
        w[[2]], w[[3]], w[[4]]
      )
    }, character(1))

    paste0(
      '{"matches": [', paste(teile, collapse = ","),
      '], "current_elos": [1505.7, 1481.6, 1518.4, 1494.3],',
      ' "team_names": ["ALP", "BET", "GAM", "DEL"]}'
    )
  }
}

page_data <- function() {
  build_league_page_data(vier_runden_fixtures(), vier_runden_teams(),
                         fetch_fn = vier_runden_response())
}

test_that("rueckblick enthält die gefensterten Spiele mit Endpoint-Werten", {
  pd <- page_data()

  rb <- pd$rueckblick
  expect_equal(rb$fixture_id, c(4001, 4002, 4003)) # chronologisch, ohne Live
  expect_equal(rb$p_home_win, c(0.44, 0.43, 0.38)) # ex-ante aus der Antwort
  expect_equal(rb$elo_delta_home, c(7.5, -1.8, 2.1))
  expect_equal(rb$nachholspiel, c(FALSE, FALSE, FALSE))
  expect_true(all(c("home_name", "away_name", "kickoff", "goals_home",
                    "goals_away", "round") %in% names(rb)))
})

test_that("live enthält das laufende Spiel mit Zwischenstand", {
  pd <- page_data()

  lv <- pd$live
  expect_equal(lv$fixture_id, 4004)
  expect_equal(lv$goals_home, 1)
  expect_equal(lv$goals_away, 0)
  expect_equal(lv$home_name, "FC Alpha")
})

test_that("spieltag nennt die Runden für Rückblick-Überschrift und Ausblick-Ziel", {
  pd <- page_data()

  expect_equal(pd$spieltag$rueckblick, c(1L, 2L))
  expect_equal(pd$spieltag$ausblick, 3L)
})

test_that("ein gespieltes Nachholspiel behält seine Kennzeichnung nach dem Join", {
  # Spiel 4002 (Runde 1) ist auf den 29.11. verlegt und nachgeholt; Runde 2
  # ist komplett abgeschlossen (4004 jetzt FT). Anker = Runde 2 -> 4002 fällt
  # als markiertes Nachholspiel ins Fenster und trägt trotzdem SEINE eigenen
  # Endpoint-Werte, nicht die eines anderen Spiels.
  #
  # ANGEPASST (#146): Vorher stand hier "Endpoint-Werte von Index 1 (Join per
  # Position)" und zwei sub()-Aufrufe, die den Antwort-String umschrieben.
  # Beides hing daran, dass extract_fixture_details() in API-Reihenfolge
  # durchreichte. Seit der chronologischen Sortierung stimmt die feste
  # Index-Zuordnung nicht mehr; der Mock folgt jetzt dem gesendeten Payload
  # (s. vier_runden_response), und die Tore holt er sich von dort -- die
  # sub()-Manipulation ist damit entbehrlich.
  #
  # Die Aussage des Tests ist unverändert: 4002 behält seine Kennzeichnung
  # als Nachholspiel UND seine eigenen Werte.
  fx <- vier_runden_fixtures()
  fx$fixture[[2]] <- data.frame(id = 4002, date = "2026-11-29T17:30:00+00:00",
                                status = I(list(data.frame(short = "FT"))))
  fx$fixture[[4]] <- data.frame(id = 4004, date = "2026-11-28T14:30:00+00:00",
                                status = I(list(data.frame(short = "FT"))))
  fx$goals[[4]] <- data.frame(home = 2, away = 0)

  pd <- build_league_page_data(fx, vier_runden_teams(),
                               fetch_fn = vier_runden_response())

  rb <- pd$rueckblick
  expect_equal(rb$fixture_id, c(4003, 4004, 4002)) # chronologisch ab Runde-2-Beginn
  expect_equal(rb$nachholspiel, c(FALSE, FALSE, TRUE))
  nachzuegler <- rb[rb$fixture_id == 4002, ]
  # 4002 ist Gamma-Delta (Team-Indizes 3-4), sein Wert ist -1.8 -- derselbe
  # wie vor dieser Aenderung. Verrutschte die Zuordnung, staende hier der
  # Wert eines Nachbarn (7.5 fuer 1-2, 2.1 fuer 2-3).
  expect_equal(nachzuegler$elo_delta_home, -1.8)
  expect_equal(nachzuegler$round, 1L)
  expect_equal(pd$spieltag$rueckblick, 2L) # Überschrift ohne Nachholspiel-Runde
})

# --- aus test-league-page-data-ausblick.R ---

# Phase 4c: build_league_page_data() liefert zusätzlich das Ausblick-Fenster
# (offene, nicht verschobene Spiele des Ziel-Spieltags plus früher angesetzte
# Nachholspiele), positionsgleich mit den Endpoint-Werten gejoint — inklusive
# der Score-Matrix je Spiel.

ausblick_fixtures <- function(spiel2_datum = "2026-11-21T14:30:00+00:00",
                              spiel2_status = "FT") {
  mk_fix <- function(id, date, status) {
    data.frame(id = id, date = date, status = I(list(data.frame(short = status))))
  }
  mk_teams <- function(hid, hname, aid, aname) {
    data.frame(home = I(list(data.frame(id = hid, name = hname))),
               away = I(list(data.frame(id = aid, name = aname))))
  }
  tibble::tibble(
    fixture = list(
      mk_fix(5001, "2026-11-20T19:30:00+00:00", "FT"),
      mk_fix(5002, spiel2_datum, spiel2_status),
      mk_fix(5003, "2026-11-27T19:30:00+00:00", "FT"),
      mk_fix(5004, "2026-11-28T14:30:00+00:00", "FT"),
      mk_fix(5005, "2026-12-04T19:30:00+00:00", "NS"),
      mk_fix(5006, "2026-12-05T14:30:00+00:00", "NS")
    ),
    league = list(
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 1"),
      data.frame(round = "Regular Season - 2"),
      data.frame(round = "Regular Season - 2"),
      data.frame(round = "Regular Season - 3"),
      data.frame(round = "Regular Season - 3")
    ),
    teams = list(
      mk_teams(101, "FC Alpha", 102, "SV Beta"),
      mk_teams(103, "TSV Gamma", 104, "1. FC Delta"),
      mk_teams(102, "SV Beta", 103, "TSV Gamma"),
      mk_teams(101, "FC Alpha", 104, "1. FC Delta"),
      mk_teams(102, "SV Beta", 104, "1. FC Delta"),
      mk_teams(103, "TSV Gamma", 101, "FC Alpha")
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      if (spiel2_status == "FT") data.frame(home = 0, away = 0)
      else data.frame(home = NA, away = NA),
      data.frame(home = 1, away = 1),
      data.frame(home = 2, away = 0),
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    )
  )
}

ausblick_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("ALP", "BET", "GAM", "DEL"),
    Promotion = c(0, 0, 0, 0),
    InitialELO = c(1500, 1480, 1520, 1500),
    stringsAsFactors = FALSE
  )
}

ausblick_response <- function() {
  eintrag <- function(index, th, ta, played, gh, ga, delta, ph, px, pa, m11) {
    sprintf(paste0(
      '{"index": %d, "team_home": %d, "team_away": %d, "played": %s,',
      ' "goals_home": %s, "goals_away": %s,',
      ' "elo_home_pre": 1500.0, "elo_away_pre": 1500.0,',
      ' "elo_delta_home": %s,',
      ' "lambda_home": 1.4, "lambda_away": 1.2,',
      ' "p_home_win": %s, "p_draw": %s, "p_away_win": %s,',
      ' "score_matrix": [[%s, 0.5], [0.0, 0.0]]}'
    ), index, th, ta, played, gh, ga, delta, ph, px, pa, m11)
  }
  # ANGEPASST (#146): folgt dem GESENDETEN Payload statt einer festen Liste.
  # Begruendung wie oben (Rueckblick-Abschnitt dieser Datei) -- seit der
  # chronologischen Sortierung stimmt die feste Index-Zuordnung nicht mehr.
  werte <- list(
    "1-2" = list("7.5",  "0.44", "0.26", "0.30", "0.5"),
    "3-4" = list("null", "0.43", "0.26", "0.31", "0.5"),
    "2-3" = list("2.1",  "0.38", "0.27", "0.35", "0.5"),
    "1-4" = list("3.3",  "0.41", "0.27", "0.32", "0.5"),
    "2-4" = list("null", "0.40", "0.26", "0.34", "0.123"),
    "3-1" = list("null", "0.45", "0.26", "0.29", "0.456")
  )

  function(payload) {
    teile <- vapply(seq_along(payload$schedule), function(i) {
      zeile <- payload$schedule[[i]]
      th <- zeile[[1]]
      ta <- zeile[[2]]
      gh <- zeile[[3]]
      ga <- zeile[[4]]
      gespielt <- !is.null(gh) && !is.na(gh) && !is.null(ga) && !is.na(ga)
      w <- werte[[paste0(th, "-", ta)]]
      eintrag(
        i - 1L, th, ta,
        if (gespielt) "true" else "false",
        if (gespielt) as.character(gh) else "null",
        if (gespielt) as.character(ga) else "null",
        if (gespielt) w[[1]] else "null",
        w[[2]], w[[3]], w[[4]], w[[5]]
      )
    }, character(1))

    paste0(
      '{"matches": [', paste(teile, collapse = ","),
      '], "current_elos": [1505.7, 1481.6, 1518.4, 1494.3],',
      ' "team_names": ["ALP", "BET", "GAM", "DEL"]}'
    )
  }
}

test_that("ausblick enthält den nächsten Spieltag mit Endpoint-Werten", {
  pd <- build_league_page_data(ausblick_fixtures(), ausblick_teams(),
                               fetch_fn = ausblick_response())

  ab <- pd$ausblick
  expect_equal(ab$fixture_id, c(5005, 5006)) # chronologisch
  expect_equal(ab$p_home_win, c(0.40, 0.45))
  expect_equal(ab$nachholspiel, c(FALSE, FALSE))
  expect_true(is.list(ab$score_matrix))
  expect_equal(ab$score_matrix[[1]][1, 1], 0.123)
  expect_equal(ab$score_matrix[[2]][1, 1], 0.456)
  expect_equal(pd$spieltag$ausblick, 3L)
})

test_that("ein früher angesetztes Nachholspiel steht markiert im Ausblick", {
  # Spiel 5002 (Runde 1) ist verschoben und neu angesetzt auf den 1.12. —
  # vor dem Ende des Ziel-Spieltags 3. Es gehört markiert in den Ausblick,
  # mit seinen eigenen Endpoint-Werten (Index 1).
  pd <- build_league_page_data(
    ausblick_fixtures(spiel2_datum = "2026-12-01T17:30:00+00:00",
                      spiel2_status = "NS"),
    ausblick_teams(),
    fetch_fn = ausblick_response()
  )

  ab <- pd$ausblick
  expect_equal(ab$fixture_id, c(5002, 5005, 5006))
  expect_equal(ab$nachholspiel, c(TRUE, FALSE, FALSE))
  expect_equal(ab$p_home_win[1], 0.43) # Index 1, nicht verrutscht
  expect_equal(pd$spieltag$ausblick, 3L)
})
