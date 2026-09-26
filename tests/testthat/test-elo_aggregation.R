# elo_aggregation.R, Issue #146 Teil 2: Die End-ELOs des Saisonwechsels
# kommen ueber POST /league-details aus demselben Rust-Walk, der auch jede
# Prognose rechnet (home_advantage 40) -- nicht mehr aus einem eigenen
# R-Walk (calculate_elo_update(), home_advantage 100). calculate_final_elos()
# holt current_elos per zwei injizierbaren Seams (fetch_fn, fixtures_fn),
# damit die Tests ohne Rust-Server und API-Schluessel laufen; die
# Mock-Antwort folgt dabei dem gesendeten Payload (wie test-league_details-
# seitendaten.R).

library(testthat)

source("../../RCode/league_details.R")

# --- Fixture-Bau -------------------------------------------------------------
#
# Genestetes Format (List-Columns einzeiliger data.frames), wie
# test-league_details.R/test-transform_data.R und
# test-league_details-seitendaten.R es benutzen.
# extract_fixture_details() unterstuetzt es ausdruecklich.

eew_spiel <- function(fixture_id, datum, status, heim_id, gast_id,
                      tore_heim = NA_real_, tore_gast = NA_real_,
                      runde = 1L) {
  list(
    teams = data.frame(
      home = I(list(data.frame(id = heim_id, name = paste("Team", heim_id)))),
      away = I(list(data.frame(id = gast_id, name = paste("Team", gast_id))))
    ),
    goals = data.frame(home = tore_heim, away = tore_gast),
    fixture = data.frame(
      id = fixture_id,
      date = datum,
      status = I(list(data.frame(short = status)))
    ),
    league = data.frame(round = paste("Regular Season -", runde))
  )
}

eew_fixtures <- function(...) {
  spiele <- list(...)
  tibble::tibble(
    teams   = lapply(spiele, `[[`, "teams"),
    goals   = lapply(spiele, `[[`, "goals"),
    fixture = lapply(spiele, `[[`, "fixture"),
    league  = lapply(spiele, `[[`, "league")
  )
}

# Eine Liga mit vier Teams und drei gespielten Partien -- reicht, um zu
# zeigen, WOHER die End-ELOs kommen. Welche Zahl der Walk rechnet, ist hier
# ausdruecklich NICHT der Gegenstand: Das prueft die Rust-Testsuite.
eew_liga_fixtures <- function() {
  eew_fixtures(
    eew_spiel(3001, "2026-08-14T18:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    eew_spiel(3002, "2026-08-15T13:30:00+00:00", "FT", 103, 104, 0, 0, runde = 1),
    eew_spiel(3003, "2026-08-21T18:30:00+00:00", "FT", 102, 103, 1, 3, runde = 2)
  )
}

# --- TeamList ----------------------------------------------------------------
#
# Der Saisonwechsel liest die TeamList der ABLAUFENDEN Saison von Platte
# (RCode/TeamList_<season>.csv bzw. die *_temp.csv-Dateien waehrend einer
# laufenden Verarbeitung). Die Tests legen sie in einem tempdir() an und
# setzen das Arbeitsverzeichnis dorthin -- so wie die bestehenden
# Saisonwechsel-Tests (test-season_processor-regression.R) es tun. Kein Test
# fasst RCode/TeamList_2026.csv an.

eew_teamlist <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    Promotion = c(0, 0, 0, 0),
    InitialELO = c(1500, 1480, 1520, 1460),
    stringsAsFactors = FALSE
  )
}

# Legt ein Wegwerf-Projektverzeichnis mit RCode/TeamList_<season>.csv an,
# wechselt hinein und raeumt nach dem Test wieder auf.
eew_mit_teamlist <- function(season, teams, code) {
  wurzel <- file.path(tempdir(), paste0("eew-", season, "-", sample.int(1e6, 1)))
  dir.create(file.path(wurzel, "RCode"), recursive = TRUE, showWarnings = FALSE)
  write.table(teams, file.path(wurzel, "RCode", paste0("TeamList_", season, ".csv")),
              sep = ";", row.names = FALSE, quote = FALSE)

  alt <- getwd()
  on.exit({
    setwd(alt)
    unlink(wurzel, recursive = TRUE)
  }, add = TRUE)
  setwd(wurzel)

  force(code)
}

# --- Mock-Endpoint -----------------------------------------------------------
#
# Baut eine /league-details-Antwort AUS DEM GESENDETEN PAYLOAD. `current_elos`
# ist der Rueckgabewert, an dem alles haengt: Ihn liefert der Rust-Walk, ihn
# muss der Saisonwechsel uebernehmen.
#
# `elo_offsets` erlaubt es, den Ligen unterscheidbare Ergebnisse zu geben,
# ohne die ELO-Formel nachzubauen -- die Tests pruefen die VERDRAHTUNG, nicht
# die Arithmetik.

antwort_zum_payload <- function(payload, elo_offsets = NULL) {
  n <- length(payload$elo_values)
  if (is.null(elo_offsets)) elo_offsets <- rep(0, n)

  current_elos <- payload$elo_values + elo_offsets

  matches <- lapply(seq_along(payload$schedule), function(i) {
    eintrag <- payload$schedule[[i]]
    gespielt <- length(eintrag) >= 4 && !is.null(eintrag[[3]])
    sprintf(
      '{"index": %d, "team_home": %d, "team_away": %d, "played": %s,
        "goals_home": %s, "goals_away": %s,
        "elo_home_pre": 1500.0, "elo_away_pre": 1500.0,
        "elo_delta_home": %s,
        "lambda_home": 1.4, "lambda_away": 1.3,
        "p_home_win": 0.42, "p_draw": 0.27, "p_away_win": 0.31,
        "score_matrix": [[0.5, 0.5], [0.0, 0.0]]}',
      i - 1L, eintrag[[1]], eintrag[[2]],
      if (gespielt) "true" else "false",
      if (gespielt) as.character(eintrag[[3]]) else "null",
      if (gespielt) as.character(eintrag[[4]]) else "null",
      if (gespielt) "5.0" else "null"
    )
  })

  sprintf('{"matches": [%s], "current_elos": [%s], "team_names": [%s]}',
          paste(unlist(matches), collapse = ", "),
          paste(format(current_elos, trim = TRUE, scientific = FALSE),
                collapse = ", "),
          paste0('"', payload$team_names, '"', collapse = ", "))
}

# =============================================================================
# 1. Die End-ELOs kommen aus /league-details -- nicht aus einer R-Rechnung
# =============================================================================

test_that("calculate_final_elos uebernimmt current_elos aus dem Endpoint", {
  # DER KERNTEST. Der Mock liefert current_elos, die mit keiner ELO-Formel
  # der Welt aus den Toren folgen (+100, -50, +7, -3 auf die Startwerte). Wer
  # das Ergebnis unveraendert in FinalELO wiederfindet, hat bewiesen, dass die
  # Zahlen aus dem Endpoint stammen und nicht in R nachgerechnet werden.
  #
  # Ein R-Walk koennte diese Werte nicht produzieren -- deshalb ist der Test
  # scharf und nicht bloss plausibel.
  offsets <- c(100, -50, 7, -3)

  ergebnis <- eew_mit_teamlist("2026", eew_teamlist(), {
    calculate_final_elos(
      "2026",
      fetch_fn = function(payload, ...) antwort_zum_payload(payload, offsets),
      fixtures_fn = function(league, season) eew_liga_fixtures()
    )
  })

  expect_s3_class(ergebnis, "data.frame")
  expect_named(ergebnis, c("TeamID", "FinalELO"), ignore.order = TRUE)
  expect_equal(sort(ergebnis$TeamID), c(101, 102, 103, 104))

  elo_nach_id <- setNames(ergebnis$FinalELO, ergebnis$TeamID)
  expect_equal(unname(elo_nach_id[["101"]]), 1600)
  expect_equal(unname(elo_nach_id[["102"]]), 1430)
  expect_equal(unname(elo_nach_id[["103"]]), 1527)
  expect_equal(unname(elo_nach_id[["104"]]), 1457)
})

test_that("calculate_final_elos ordnet current_elos per ID zu, nicht positional", {
  # current_elos kommt in der Reihenfolge von payload$elo_values zurueck, also
  # in der Reihenfolge der an den Endpoint uebergebenen LIGA-Teams. Die
  # TeamList kann mehr Teams und eine andere Reihenfolge haben.
  #
  # Wer die Werte positional in die TeamList schreibt, vertauscht die ELOs
  # zwischen Teams -- ohne Fehlermeldung, mit plausibel aussehenden Zahlen.
  # Deshalb steht hier eine TeamList, deren Reihenfolge NICHT der
  # Spielplanreihenfolge entspricht, und ein Team (999), das gar nicht
  # mitspielt.
  teamlist <- data.frame(
    TeamID = c(999, 104, 101, 103, 102),
    ShortText = c("XXX", "DDD", "AAA", "CCC", "BBB"),
    Promotion = c(0, 0, 0, 0, 0),
    InitialELO = c(1700, 1460, 1500, 1520, 1480),
    stringsAsFactors = FALSE
  )

  gesendet <- NULL
  ergebnis <- eew_mit_teamlist("2026", teamlist, {
    calculate_final_elos(
      "2026",
      fetch_fn = function(payload, ...) {
        gesendet <<- payload
        # Jedes Team bekommt einen unverwechselbaren Aufschlag, abgeleitet
        # aus seinem eigenen Startwert -- eine Vertauschung faellt damit
        # zwingend auf.
        antwort_zum_payload(payload, seq_along(payload$elo_values) * 10)
      },
      fixtures_fn = function(league, season) eew_liga_fixtures()
    )
  })

  # Der Payload enthaelt nur die vier Liga-Teams; 999 bleibt draussen.
  expect_length(gesendet$elo_values, 4)
  expect_false("XXX" %in% gesendet$team_names)

  elo_nach_id <- setNames(ergebnis$FinalELO, ergebnis$TeamID)
  erwartet <- setNames(gesendet$elo_values + seq_along(gesendet$elo_values) * 10,
                       gesendet$team_names)

  # Ueber den Kurznamen zurueckgejoint: AAA=101, BBB=102, CCC=103, DDD=104.
  expect_equal(unname(elo_nach_id[["101"]]), unname(erwartet[["AAA"]]))
  expect_equal(unname(elo_nach_id[["102"]]), unname(erwartet[["BBB"]]))
  expect_equal(unname(elo_nach_id[["103"]]), unname(erwartet[["CCC"]]))
  expect_equal(unname(elo_nach_id[["104"]]), unname(erwartet[["DDD"]]))
})

test_that("calculate_final_elos sendet den Spielplan chronologisch an den Endpoint", {
  # Teil 1 (PR #200) hat die chronologische Sortierung in
  # extract_fixture_details() eingebaut. Teil 2 darf sie nicht wieder
  # verlieren: Der Saisonwechsel muss denselben Weg nehmen wie die Prognose,
  # sonst rechnet er zwar mit der richtigen Physik, aber in der falschen
  # Reihenfolge -- und die End-ELOs wichen wieder von denen der Seite ab.
  #
  # Das Nachholspiel (fixture 3002, Runde 1, ausgetragen erst am 30.09.)
  # steht in der API-Liste an Position 2 und muss im schedule ans ENDE.
  fixtures <- eew_fixtures(
    eew_spiel(3001, "2026-08-14T18:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    eew_spiel(3002, "2026-09-30T18:30:00+00:00", "FT", 103, 104, 0, 3, runde = 1),
    eew_spiel(3003, "2026-08-21T18:30:00+00:00", "FT", 102, 103, 1, 3, runde = 2)
  )

  gesendet <- NULL
  eew_mit_teamlist("2026", eew_teamlist(), {
    calculate_final_elos(
      "2026",
      fetch_fn = function(payload, ...) {
        gesendet <<- payload
        antwort_zum_payload(payload)
      },
      fixtures_fn = function(league, season) fixtures
    )
  })

  heim_idx <- vapply(gesendet$schedule, function(e) e[[1]], numeric(1))
  gast_idx <- vapply(gesendet$schedule, function(e) e[[2]], numeric(1))

  # 101->1, 102->2, 103->3, 104->4 (TeamList-Reihenfolge)
  expect_equal(heim_idx, c(1, 2, 3))
  expect_equal(gast_idx, c(2, 3, 4))
})

# =============================================================================
# 2. Alle zehn Ligen -- und das Ueberspringen leerer Ligen
# =============================================================================

test_that("calculate_final_elos fragt den Endpoint fuer jede aktive Liga", {
  # ENTSCHEIDUNG DES USERS: Der Saisonwechsel iteriert weiter ueber ALLE
  # Ligen aus league_ids(), nicht ueber SEASON_TRANSITION_LEAGUES. Letzteres
  # steuert nur die VOLLSTAENDIGKEITSPRUEFUNG (season_validation.R:31), nicht
  # den Abruf.
  #
  # Warum das wichtig ist: Ohne die sieben seit September 2026 dazugekommenen
  # Ligen verloere der Saisonwechsel den Grossteil des ELO-Wissens -- Teams,
  # die aus der Regionalliga aufsteigen, kaemen mit ihrem Startwert statt mit
  # ihrer erspielten Staerke an.
  abgefragt <- character(0)

  eew_mit_teamlist("2026", eew_teamlist(), {
    calculate_final_elos(
      "2026",
      fetch_fn = function(payload, ...) antwort_zum_payload(payload),
      fixtures_fn = function(league, season) {
        abgefragt <<- c(abgefragt, as.character(league))
        eew_liga_fixtures()
      }
    )
  })

  expect_setequal(abgefragt, league_ids())
  expect_length(abgefragt, length(league_ids()))
})

test_that("calculate_final_elos ueberspringt Ligen ohne Spiele und laesst deren ELOs stehen", {
  # BESTANDSVERHALTEN, das erhalten bleiben muss (elo_aggregation.R:89-92,
  # "ELO values will remain unchanged"). Es traegt den Saisonwechsel in genau
  # den Faellen, in denen er sonst abbraeche: eine Liga, die api-football fuer
  # diese Saison nicht fuehrt, oder eine Saison, die noch kein Spiel gesehen
  # hat.
  #
  # Hier liefert NUR die erste Liga Spiele; alle uebrigen geben NULL zurueck.
  # Die vier Teams stehen alle in dieser einen Liga, also muessen ihre ELOs
  # den Aufschlag aus genau einem Endpoint-Aufruf tragen -- nicht zehn.
  aufrufe <- 0L
  erste_liga <- league_ids()[1]

  ergebnis <- eew_mit_teamlist("2026", eew_teamlist(), {
    calculate_final_elos(
      "2026",
      fetch_fn = function(payload, ...) {
        aufrufe <<- aufrufe + 1L
        antwort_zum_payload(payload, rep(11, length(payload$elo_values)))
      },
      fixtures_fn = function(league, season) {
        if (as.character(league) == erste_liga) eew_liga_fixtures() else NULL
      }
    )
  })

  expect_equal(aufrufe, 1L)

  elo_nach_id <- setNames(ergebnis$FinalELO, ergebnis$TeamID)
  expect_equal(unname(elo_nach_id[["101"]]), 1511)
  expect_equal(unname(elo_nach_id[["102"]]), 1491)
  expect_equal(unname(elo_nach_id[["103"]]), 1531)
  expect_equal(unname(elo_nach_id[["104"]]), 1471)
})

test_that("calculate_final_elos laesst Teams ohne Spiel auf ihrem Startwert", {
  # Ein Team, das in KEINER abgefragten Liga vorkommt (etwa weil seine Liga
  # keine Spiele geliefert hat), muss trotzdem mit einer FinalELO in der
  # Rueckgabe stehen -- und zwar mit seinem InitialELO.
  #
  # Der Grund ist betrieblich: season_processor.R schlaegt die FinalELO je
  # Team nach (league_processor.R:38 u.a.). Ein fehlender Eintrag laesst das
  # Team stillschweigend auf einen Default fallen; ein NA rechnet sich durch
  # die ganze neue Saison fort.
  teamlist <- rbind(
    eew_teamlist(),
    data.frame(TeamID = 555, ShortText = "EEE", Promotion = 0,
               InitialELO = 1333, stringsAsFactors = FALSE)
  )

  ergebnis <- eew_mit_teamlist("2026", teamlist, {
    calculate_final_elos(
      "2026",
      fetch_fn = function(payload, ...) antwort_zum_payload(payload, rep(11, length(payload$elo_values))),
      fixtures_fn = function(league, season) {
        if (as.character(league) == league_ids()[1]) eew_liga_fixtures() else NULL
      }
    )
  })

  expect_true(555 %in% ergebnis$TeamID)
  expect_false(any(is.na(ergebnis$FinalELO)))

  elo_nach_id <- setNames(ergebnis$FinalELO, ergebnis$TeamID)
  expect_equal(unname(elo_nach_id[["555"]]), 1333)
})

test_that("calculate_final_elos gibt bei durchweg spiellosen Ligen die Startwerte zurueck", {
  # Der Extremfall des vorigen Tests, und der eigentlich gefaehrliche: KEINE
  # Liga liefert Spiele. Erwartet wird keine Ausnahme, kein leeres
  # data.frame, sondern die unveraenderte TeamList in FinalELO-Gestalt. Der
  # Endpoint wird gar nicht erst befragt.
  aufrufe <- 0L

  ergebnis <- eew_mit_teamlist("2026", eew_teamlist(), {
    calculate_final_elos(
      "2026",
      fetch_fn = function(payload, ...) {
        aufrufe <<- aufrufe + 1L
        antwort_zum_payload(payload)
      },
      fixtures_fn = function(league, season) NULL
    )
  })

  expect_equal(aufrufe, 0L)
  expect_equal(nrow(ergebnis), 4)
  expect_equal(ergebnis$FinalELO[order(ergebnis$TeamID)],
               eew_teamlist()$InitialELO[order(eew_teamlist()$TeamID)])
})

# =============================================================================
# 3. Beide Aufrufer -- der zweite steht in derselben Datei
# =============================================================================

test_that("calculate_liga3_relegation_baseline nutzt den Endpoint-Walk weiter", {
  # DER ZWEITE AUFRUFER, leicht zu uebersehen: Er steht in derselben Datei
  # (elo_aggregation.R:325), aus der die drei Funktionen verschwinden. Er
  # mittelt die End-ELOs der Drittliga-Absteiger zur Basis-ELO fuer
  # Aufsteiger -- laeuft er nach der Umstellung ins Leere, faellt er auf den
  # Default 1046 zurueck. Und zwar STILL: mit einer Warnung, aber ohne
  # Fehler, und mit einem Wert, der plausibel aussieht.
  #
  # Dieser Test haelt fest, dass der Rueckfall NICHT eintritt: Die Basis-ELO
  # muss der Mittelwert der vier vom Endpoint gelieferten End-ELOs sein.
  #
  # Aufbau: sechs Liga3-Teams, die bottom 4 (Plaetze 3-6) werden ueber eine
  # gestubbte Tabelle() festgelegt.
  skip_if_not_installed("mockery")
  library(mockery)

  final_elos <- data.frame(
    TeamID = c(2001, 2002, 2003, 2004, 2005, 2006),
    FinalELO = c(1400, 1300, 1200, 1100, 1000, 900),
    stringsAsFactors = FALSE
  )

  liga3_matches <- data.frame(
    fixture_date = paste0("2026-04-", sprintf("%02d", 1:6)),
    teams_home_id = c(2001, 2002, 2003, 2004, 2005, 2006),
    teams_away_id = c(2002, 2003, 2004, 2005, 2006, 2001),
    goals_home = c(2, 1, 0, 0, 1, 0),
    goals_away = c(1, 0, 1, 2, 0, 3),
    stringsAsFactors = FALSE
  )

  # Die Baseline muss die vom ENDPOINT gelieferten Werte mitteln. Der Stub
  # gibt vor, was calculate_final_elos() in der neuen Welt liefert -- die
  # Baseline darf sich nicht heimlich anderswoher bedienen.
  stub(calculate_liga3_relegation_baseline, "calculate_final_elos",
       function(season, ...) final_elos)
  stub(calculate_liga3_relegation_baseline, "get_league_matches",
       function(league, season, ...) liga3_matches)
  stub(calculate_liga3_relegation_baseline, "Tabelle",
       function(season, numberTeams, numberGames) {
         # Spalten: team_number, rank, tore, gegentore, differenz, punkte.
         # Teams 3-6 (also 2003..2006) auf den Abstiegsplaetzen 3-6.
         matrix(c(
           1, 1, 20,  8, 12, 15,
           2, 2, 18, 10,  8, 12,
           3, 3, 12, 14, -2,  8,
           4, 4, 10, 16, -6,  6,
           5, 5,  8, 18, -10, 4,
           6, 6,  6, 22, -16, 2
         ), ncol = 6, byrow = TRUE)
       })

  baseline <- eew_mit_teamlist("2026", eew_teamlist(), {
    calculate_liga3_relegation_baseline("2026")
  })

  # Absteiger sind 2003, 2004, 2005, 2006 -> Mittel aus 1200, 1100, 1000, 900.
  expect_equal(baseline, mean(c(1200, 1100, 1000, 900)))
  expect_false(baseline == 1046)  # kein stiller Rueckfall auf den Default
})

test_that("calculate_liga3_relegation_baseline reicht die Seams durch", {
  # Wenn calculate_final_elos() injizierbare Seams bekommt, muss der zweite
  # Aufrufer sie durchreichen koennen -- sonst braeuchte jeder Test der
  # Baseline einen laufenden Rust-Server, und der produktive Aufruf im
  # Saisonwechsel muesste den Endpoint zweimal unterschiedlich konfigurieren.
  #
  # Geprueft wird nur die SIGNATUR, nicht das Ergebnis: Die Funktion muss die
  # Parameter kennen.
  argumente <- names(formals(calculate_liga3_relegation_baseline))
  expect_true("fetch_fn" %in% argumente)
  expect_true("fixtures_fn" %in% argumente)
})

test_that("process_single_season ruft calculate_final_elos ohne R-Walk auf", {
  # Der erste Aufrufer (season_processor.R:140). Geprueft wird die
  # VERDRAHTUNG: Das, was calculate_final_elos() liefert, muss unveraendert
  # bei process_league_teams() ankommen. Alles dazwischen ist gestubbt --
  # dieser Test sagt nichts ueber Teamerkennung oder CSV-Erzeugung.
  skip_if_not_installed("mockery")
  library(mockery)

  endgueltige_elos <- data.frame(
    TeamID = c(101, 102),
    FinalELO = c(1601, 1402),
    stringsAsFactors = FALSE
  )

  gesehen <- NULL

  stub(process_single_season, "validate_season_completion", function(...) TRUE)
  stub(process_single_season, "load_previous_team_list", function(...) eew_teamlist())
  stub(process_single_season, "calculate_final_elos", function(...) endgueltige_elos)
  stub(process_single_season, "calculate_liga3_relegation_baseline", function(...) 1046)
  stub(process_single_season, "fetch_all_leagues_teams",
       function(...) list("78" = list(list(id = 101, name = "Team 101"))))
  stub(process_single_season, "process_league_teams",
       function(teams, league_id, season, final_elos, liga3_baseline,
                previous_team_list, ...) {
         gesehen <<- final_elos
         list()
       })

  process_single_season("2027", "2026")

  expect_equal(gesehen, endgueltige_elos)
})

test_that("die Funktionen, die bleiben, sind noch da", {
  # Das Gegenstueck zum Wachhund: Teil 2 loescht DREI Funktionen, nicht die
  # halbe Datei. Diese drei haben andere Aufrufer und muessen ueberleben --
  # ein zu grosszuegiges Aufraeumen faellt hier auf.
  expect_true(exists("get_initial_elo_for_new_team"),
              info = "Aufrufer: interactive_prompts.R:40")
  expect_true(exists("fetch_league_results"),
              info = "Aufrufer: fixture_cache.R:52 (cached_fixtures)")
  expect_true(exists("get_league_matches"),
              info = "Aufrufer: calculate_liga3_relegation_baseline() fuer die Ligatabelle")
  expect_true(exists("calculate_final_elos"),
              info = "bleibt als Name, aber mit Endpoint-Implementierung")
})

test_that("elo_aggregation.R definiert keinen eigenen ELO-Schritt mehr", {
  # Schaerfer als exists(): Die Datei selbst wird in eine LEERE Umgebung
  # gesourct, ohne den globalen Zustand der uebrigen Testsuite. Wer die
  # Funktionen in eine andere Datei verschoebe statt sie zu loeschen, kaeme
  # am exists()-Test oben nicht vorbei -- wer sie hier wieder einfuegte,
  # kommt an diesem nicht vorbei.
  umgebung <- new.env(parent = globalenv())
  sys.source(normalizePath("../../RCode/elo_aggregation.R"), envir = umgebung)

  definiert <- ls(umgebung)
  expect_false("calculate_elo_update" %in% definiert)
  expect_false("update_elos_for_match" %in% definiert)
  expect_true("calculate_final_elos" %in% definiert)
})
