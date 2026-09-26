library(testthat)
source("../../RCode/transform_data.R")

test_that("transform_data converts API response correctly", {
  # Create test fixtures and teams
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()
  
  # Transform the data
  result <- transform_data(fixtures, teams)
  
  # Check structure - transform_data returns a tibble
  expect_true(is.data.frame(result) || tibble::is_tibble(result))
  expect_gte(ncol(result), 4)  # At least TeamHeim, TeamGast, ToreHeim, ToreGast
  expect_equal(nrow(result), 3)  # 3 fixtures in test data
  
  # Check first finished game - using column names
  expect_equal(result$TeamHeim[1], "TEA")  # Team A short name
  expect_equal(result$TeamGast[1], "TEB")  # Team B short name
  expect_equal(result$ToreHeim[1], 2)    # Goals home
  expect_equal(result$ToreGast[1], 1)    # Goals away
  
  # Check second finished game
  expect_equal(result$TeamHeim[2], "TEC")  # Team C short name
  expect_equal(result$TeamGast[2], "TED")  # Team D short name
  expect_equal(result$ToreHeim[2], 1)    # Goals home
  expect_equal(result$ToreGast[2], 1)    # Goals away
  
  # Check unfinished game (should have NA goals)
  expect_equal(result$TeamHeim[3], "TEA")  # Team A short name
  expect_equal(result$TeamGast[3], "TEC")  # Team C short name
  expect_true(is.na(result$ToreHeim[3])) # Goals home NA
  expect_true(is.na(result$ToreGast[3])) # Goals away NA
})

test_that("transform_data handles only finished games correctly", {
  # Create fixtures with only finished games
  fixtures <- tibble::tibble(
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 102, name = "Team B")))
      ),
      data.frame(
        home = I(list(data.frame(id = 103, name = "Team C"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      )
    ),
    goals = list(
      data.frame(home = 3, away = 0),
      data.frame(home = 2, away = 2)
    ),
    fixture = list(
      data.frame(id = 1001, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 1002, status = I(list(data.frame(short = "FT"))))
    )
  )
  
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # All games should have results
  expect_false(any(is.na(result$ToreHeim)))
  expect_false(any(is.na(result$ToreGast)))
  expect_equal(nrow(result), 2)
})

test_that("transform_data handles only unfinished games correctly", {
  # Create fixtures with only unfinished games
  fixtures <- tibble::tibble(
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 102, name = "Team B")))
      ),
      data.frame(
        home = I(list(data.frame(id = 103, name = "Team C"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      )
    ),
    goals = list(
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    ),
    fixture = list(
      data.frame(id = 1001, status = I(list(data.frame(short = "NS")))),
      data.frame(id = 1002, status = I(list(data.frame(short = "PST"))))
    )
  )
  
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # All games should have NA results
  expect_true(all(is.na(result$ToreHeim)))
  expect_true(all(is.na(result$ToreGast)))
  expect_equal(nrow(result), 2)
})

test_that("transform_data handles empty fixtures", {
  # Empty fixtures tibble
  fixtures <- tibble::tibble(
    teams = list(),
    goals = list(),
    fixture = list()
  )
  teams <- create_test_teams_api()

  # Bis Phase 0 des Ligen-Ausbaus stieg transform_data() hier mit einem
  # tidyselect-Folgefehler aus; der Test hielt diesen Mangel fest ("doesn't
  # handle empty fixtures properly, so expect an error"). Mit zehn Ligen und
  # verschiedenen Spielkalendern ist eine Liga ohne angesetzte Spiele aber ein
  # Normalfall -- ein Absturz waere ein echter Betriebsfehler. Erwartet wird
  # jetzt ein leeres Geruest mit den vier Basisspalten.
  result <- transform_data(fixtures, teams)

  expect_equal(nrow(result), 0)
  expect_true(all(c("TeamHeim", "TeamGast", "ToreHeim", "ToreGast") %in%
                    names(result)))
})

test_that("transform_data matches ELO values correctly", {
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # Verify that team columns are created with ELO values
  # The transform_data function creates columns for each team
  # Team A (TEA) -> ELO 1500
  # Team B (TEB) -> ELO 1450
  # Team C (TEC) -> ELO 1550
  # Team D (TED) -> ELO 1400
  
  # Check that team columns exist
  expect_true("TEA" %in% colnames(result))
  expect_true("TEB" %in% colnames(result))
  expect_true("TEC" %in% colnames(result))
  expect_true("TED" %in% colnames(result))
  
  # Check that ELO values are in first row (as per the function logic)
  expect_equal(as.numeric(result$TEA[1]), 1500)
  expect_equal(as.numeric(result$TEB[1]), 1450)
  expect_equal(as.numeric(result$TEC[1]), 1550)
  expect_equal(as.numeric(result$TED[1]), 1400)
})

test_that("transform_data handles different game statuses", {
  # Test various game statuses
  fixtures <- tibble::tibble(
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 102, name = "Team B")))
      ),
      data.frame(
        home = I(list(data.frame(id = 103, name = "Team C"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      ),
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 103, name = "Team C")))
      ),
      data.frame(
        home = I(list(data.frame(id = 102, name = "Team B"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      ),
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      )
    ),
    goals = list(
      data.frame(home = 1, away = 0),
      data.frame(home = 2, away = 1),
      data.frame(home = 1, away = 1),
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    ),
    fixture = list(
      data.frame(id = 1001, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 1002, status = I(list(data.frame(short = "AET")))),
      data.frame(id = 1003, status = I(list(data.frame(short = "PEN")))),
      data.frame(id = 1004, status = I(list(data.frame(short = "NS")))),
      data.frame(id = 1005, status = I(list(data.frame(short = "CANC"))))
    )
  )
  
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)

  # FT, AET and PEN all count as finished games
  expect_equal(result$ToreHeim[1], 1)
  expect_equal(result$ToreGast[1], 0)

  # AET is finished (decided after extra time)
  expect_equal(result$ToreHeim[2], 2)
  expect_equal(result$ToreGast[2], 1)

  # PEN is finished (decided on penalties)
  expect_equal(result$ToreHeim[3], 1)
  expect_equal(result$ToreGast[3], 1)
  
  # NS should have NA
  expect_true(is.na(result$ToreHeim[4]))
  expect_true(is.na(result$ToreGast[4]))
  
  # CANC should have NA
  expect_true(is.na(result$ToreHeim[5]))
  expect_true(is.na(result$ToreGast[5]))
})

test_that("transform_data handles missing team in teams list", {
  # Create fixtures with a team not in the teams list
  fixtures <- tibble::tibble(
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 999, name = "Unknown Team")))  # Not in teams list
      )
    ),
    goals = list(
      data.frame(home = 2, away = 1)
    ),
    fixture = list(
      data.frame(id = 1001, status = I(list(data.frame(short = "FT"))))
    )
  )
  
  teams <- create_test_teams_api()
  
  # The function doesn't handle missing teams gracefully, so expect an error
  expect_error(transform_data(fixtures, teams))
})

test_that("transform_data preserves fixture order", {
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # Check that fixtures appear in the same order
  expect_equal(result$TeamHeim[1], "TEA")  # First fixture
  expect_equal(result$TeamGast[1], "TEB")
  expect_equal(result$TeamHeim[2], "TEC")  # Second fixture
  expect_equal(result$TeamGast[2], "TED")
  expect_equal(result$TeamHeim[3], "TEA")  # Third fixture
  expect_equal(result$TeamGast[3], "TEC")
})

test_that("transform_data handles NULL goal values", {
  # Test fixture with NULL goals (different from NA)
  fixtures <- tibble::tibble(
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 102, name = "Team B")))
      )
    ),
    goals = list(
      data.frame(home = NA, away = NA)
    ),
    fixture = list(
      data.frame(id = 1001, status = I(list(data.frame(short = "NS"))))
    )
  )
  
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # NULL should be converted to NA
  expect_true(is.na(result$ToreHeim[1]))
  expect_true(is.na(result$ToreGast[1]))
})

test_that("transform_data drops non-regular-season rounds (relegation playoff)", {
  # API-Football delivers the relegation playoff as round "Final" within the
  # league fixture list (e.g. Bundesliga 16th vs. 2. Bundesliga 3rd). Those
  # games must not enter the simulation: the lower-league team would appear
  # as an extra team and the playoff results would distort the table.
  fixtures <- tibble::tibble(
    league = data.frame(
      round = c("Regular Season - 33", "Regular Season - 34", "Final", "Final"),
      stringsAsFactors = FALSE
    ),
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 102, name = "Team B")))
      ),
      data.frame(
        home = I(list(data.frame(id = 103, name = "Team C"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      ),
      data.frame(  # playoff first leg: league team vs. playoff intruder
        home = I(list(data.frame(id = 102, name = "Team B"))),
        away = I(list(data.frame(id = 105, name = "Playoff Team")))
      ),
      data.frame(  # playoff second leg, decided after extra time
        home = I(list(data.frame(id = 105, name = "Playoff Team"))),
        away = I(list(data.frame(id = 102, name = "Team B")))
      )
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = 1, away = 1),
      data.frame(home = 0, away = 0),
      data.frame(home = 2, away = 1)
    ),
    fixture = list(
      data.frame(id = 1001, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 1002, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 1003, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 1004, status = I(list(data.frame(short = "AET"))))
    )
  )

  teams <- data.frame(
    TeamID = c(101, 102, 103, 104, 105),
    ShortText = c("TEA", "TEB", "TEC", "TED", "PLT"),
    InitialELO = c(1500, 1450, 1550, 1400, 1430),
    stringsAsFactors = FALSE
  )

  result <- transform_data(fixtures, teams)

  # Only the two regular-season games survive
  expect_equal(nrow(result), 2)
  expect_equal(result$TeamHeim, c("TEA", "TEC"))

  # The playoff team must not appear as a team column
  expect_false("PLT" %in% colnames(result))
})

test_that("transform_data creates proper data structure", {
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()
  
  result <- transform_data(fixtures, teams)
  
  # Should be a data frame or tibble
  expect_true(is.data.frame(result) || tibble::is_tibble(result))
  
  # Check goal columns are numeric
  expect_true(is.numeric(result$ToreHeim))
  expect_true(is.numeric(result$ToreGast))
})

# --- aus test-gewertete-spiele.R ---
# --- Simulationspfad: transform_data ----------------------------------------
# (eigene Datei-Sektion, weil transform_data.R separat gesourct wird)

test_that("transform_data behaelt die Tore eines gewerteten Spiels", {
  # Bisher setzte transform_data() alles ausser FT/AET/PEN auf NA -- die
  # Simulation wuerfelte das Wertungsspiel in jedem Durchlauf neu aus, obwohl
  # es sportrechtlich entschieden ist. Fuer die ENDTABELLE der Simulation
  # muss das Ergebnis feststehen.
  #
  # Der ELO-Walk der Engine darf es trotzdem nicht sehen -- das leistet das
  # Rust-Flag (siehe cargo-Tests), nicht diese Funktion.
  source("../../RCode/transform_data.R", local = TRUE)

  fixtures <- tibble::tibble(
    league = data.frame(round = c("Regular Season - 1", "Regular Season - 1"),
                        stringsAsFactors = FALSE),
    teams = list(
      data.frame(home = I(list(data.frame(id = 101, name = "A"))),
                 away = I(list(data.frame(id = 102, name = "B")))),
      data.frame(home = I(list(data.frame(id = 103, name = "C"))),
                 away = I(list(data.frame(id = 104, name = "D"))))
    ),
    goals = list(data.frame(home = 2, away = 1), data.frame(home = 3, away = 0)),
    fixture = list(
      data.frame(id = 1, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 2, status = I(list(data.frame(short = "AWD"))))
    )
  )
  teams <- data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    InitialELO = c(1500, 1500, 1500, 1500),
    stringsAsFactors = FALSE
  )

  result <- transform_data(fixtures, teams)

  expect_equal(result$ToreHeim, c(2, 3))
  expect_equal(result$ToreGast, c(1, 0))
})

test_that("transform_data laesst offene und verschobene Spiele weiter offen", {
  # Verhaltensneutralitaet: Nur AWD/WO kommt dazu, NS und PST bleiben NA.
  source("../../RCode/transform_data.R", local = TRUE)

  fixtures <- tibble::tibble(
    league = data.frame(round = rep("Regular Season - 1", 3),
                        stringsAsFactors = FALSE),
    teams = list(
      data.frame(home = I(list(data.frame(id = 101, name = "A"))),
                 away = I(list(data.frame(id = 102, name = "B")))),
      data.frame(home = I(list(data.frame(id = 103, name = "C"))),
                 away = I(list(data.frame(id = 104, name = "D")))),
      data.frame(home = I(list(data.frame(id = 101, name = "A"))),
                 away = I(list(data.frame(id = 103, name = "C"))))
    ),
    goals = list(data.frame(home = 2, away = 1), data.frame(home = NA, away = NA),
                 data.frame(home = NA, away = NA)),
    fixture = list(
      data.frame(id = 1, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 2, status = I(list(data.frame(short = "NS")))),
      data.frame(id = 3, status = I(list(data.frame(short = "PST"))))
    )
  )
  teams <- data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    InitialELO = c(1500, 1500, 1500, 1500),
    stringsAsFactors = FALSE
  )

  result <- transform_data(fixtures, teams)

  expect_equal(result$ToreHeim[1], 2)
  expect_true(all(is.na(result$ToreHeim[2:3])))
  expect_true(all(is.na(result$ToreGast[2:3])))
})

# --- aus test-rundenfilter-schutznetz.R ---
# Phase 0 des Ligen-Ausbaus: das Schutznetz vor den neuen Ligen.
#
# Der Produktivpfad filtert Hauptrundenspiele bisher über eine POSITIVLISTE
# (startsWith "Regular Season"). Am echten Fixture-Cache verifiziert:
#
#   Liga 83 (RL Bayern) liefert "Bayern - 34"
#   Liga 84 (RL Nord)   liefert "Nord - 20" -- und ab Saison 2025 "North - 20"
#   Liga 86 (RL SüdWest) liefert "Südwest - 12", mit Umlaut
#
# Die Positivliste würde damit JEDES Regionalliga-Spiel verwerfen und eine
# leere Liga simulieren -- ohne Fehlermeldung. Zwei Anforderungen folgen:
#
#   1. Der Filter muss eine NEGATIVLISTE sein: Hauptrunde ist alles, was
#      keine bekannte K.-o.-Runde ist. Das überlebt "Bayern - 34" ebenso wie
#      den Sprachwechsel "Nord" -> "North".
#   2. Wenn der Filter ALLE Spiele entfernt, ist das ein Abbruch mit den
#      beobachteten Rundenlabels in der Meldung -- nicht eine leere Liga,
#      die klaglos weitersimuliert wird.
#
# is_regular_season_round() (RCode/fixture_cache.R) implementiert die
# Negativliste bereits und ist dort getestet; sie muss in den Produktivpfad.
#
# Zum heutigen Verhalten: transform_data() filtert erst alles weg und scheitert
# danach in unnest() mit "Can't select columns that don't exist" -- ein
# Folgefehler, der die Ursache verdeckt. Auch deshalb die Postcondition: der
# Abbruch muss die beobachteten Rundenlabels nennen, nicht eine tidyselect-
# Meldung über eine fehlende Spalte.

# --- Fixture-Fabriken -------------------------------------------------------

# Genestete Mock-Form (wie in der bestehenden transform_data-Suite).
rl_fixtures_genestet <- function(rounds) {
  n <- length(rounds)
  ids <- 4000 + seq_len(n)
  heim <- rep(c(201, 203), length.out = n)
  gast <- rep(c(202, 204), length.out = n)

  tibble::tibble(
    league = data.frame(round = rounds, stringsAsFactors = FALSE),
    teams = lapply(seq_len(n), function(i) {
      data.frame(
        home = I(list(data.frame(id = heim[i], name = paste("Team", heim[i])))),
        away = I(list(data.frame(id = gast[i], name = paste("Team", gast[i]))))
      )
    }),
    goals = lapply(seq_len(n), function(i) data.frame(home = 1, away = 0)),
    fixture = lapply(seq_len(n), function(i) {
      data.frame(id = ids[i], status = I(list(data.frame(short = "FT"))))
    })
  )
}

rl_teams <- function() {
  data.frame(
    TeamID = c(201, 202, 203, 204),
    ShortText = c("RLA", "RLB", "RLC", "RLD"),
    InitialELO = c(950, 900, 980, 870),
    stringsAsFactors = FALSE
  )
}

# --- transform_data ---------------------------------------------------------

test_that("transform_data behält Regionalliga-Runden mit Staffelnamen", {
  # Der Kernfall: keines dieser Labels beginnt mit "Regular Season".
  fixtures <- rl_fixtures_genestet(c("Bayern - 34", "Nord - 20", "West - 7"))

  result <- transform_data(fixtures, rl_teams())

  expect_equal(nrow(result), 3)
  expect_equal(result$TeamHeim, c("RLA", "RLC", "RLA"))
})

test_that("transform_data überlebt den Sprachwechsel Nord -> North", {
  # Liga 84 wechselt zwischen Saison 2024 und 2025 die Schreibweise. Beide
  # Formen müssen in DERSELBEN Abfrage durchkommen -- ein Filter, der auf
  # einen festen Staffelnamen ausweicht, würde hier scheitern.
  fixtures <- rl_fixtures_genestet(c("Nord - 12", "North - 12", "Nord - 13"))

  result <- transform_data(fixtures, rl_teams())

  expect_equal(nrow(result), 3)
})

test_that("transform_data behält Staffelnamen mit Umlaut", {
  # Liga 86 liefert "Südwest - N".
  fixtures <- rl_fixtures_genestet(c("Südwest - 12", "Südwest - 13"))

  result <- transform_data(fixtures, rl_teams())

  expect_equal(nrow(result), 2)
})

test_that("transform_data verwirft K.-o.-Runden auch bei Staffelnamen", {
  # Die Negativliste darf die Playoffs weiterhin herausfiltern. RL Bayern
  # 2025 liefert echte "Relegation Round"-Spiele neben der Hauptrunde.
  fixtures <- rl_fixtures_genestet(
    c("Bayern - 33", "Bayern - 34", "Relegation Round", "Promotion Play-offs - 1")
  )

  result <- transform_data(fixtures, rl_teams())

  expect_equal(nrow(result), 2)
})

test_that("transform_data bricht ab, wenn der Filter alle Spiele entfernt", {
  # DAS ist das eigentliche Schutznetz: lieber laut scheitern als eine leere
  # Liga simulieren. Die Meldung muss die beobachteten Labels nennen, sonst
  # ist der Fehler im Betrieb nicht zu diagnostizieren.
  fixtures <- rl_fixtures_genestet(c("Final", "Semi-finals"))

  expect_error(transform_data(fixtures, rl_teams()), "Final")
})

test_that("transform_data lässt leere Eingabe unberührt durch", {
  # Kein Spiel drin heißt nicht "Filter hat alles weggeworfen". Eine Liga
  # ohne angesetzte Spiele darf nicht denselben Abbruch auslösen -- sonst
  # scheitert der Saisonstart, bevor der erste Spielplan steht.
  fixtures <- rl_fixtures_genestet(character(0))

  expect_error(transform_data(fixtures, rl_teams()), NA)
})

test_that("transform_data verhält sich bei Bundesliga-Fixtures unverändert", {
  # Verhaltensneutralität für die drei Altligen: derselbe Fall wie im
  # bestehenden Playoff-Test, hier als Regression gegen den Umbau.
  fixtures <- rl_fixtures_genestet(
    c("Regular Season - 33", "Regular Season - 34", "Final")
  )

  result <- transform_data(fixtures, rl_teams())

  expect_equal(nrow(result), 2)
  expect_equal(result$TeamHeim, c("RLA", "RLC"))
})

# --- aus test-elo-walk-reihenfolge.R ---
# Issue #146, Teil 1: Der ELO-Walk muss die Spiele in der Reihenfolge sehen,
# in der sie STATTGEFUNDEN haben -- nicht in der, in der api-football sie
# ausliefert.
#
# WARUM DAS UEBERHAUPT EIN PROBLEM IST: Der Rust-Walk verarbeitet den
# Spielplan in Listenreihenfolge. Solange die API nach Spieltag sortiert
# liefert, faellt das nicht auf. Bei einem NACHHOLSPIEL faellt es auf: Ein
# verlegtes Spiel des 5. Spieltags, tatsaechlich ausgetragen zwischen dem
# 13. und dem 14., wandert in der Liste an den Platz des 5. Spieltags. Der
# Walk verrechnet es dort -- mit ELO-Staenden, die zum Zeitpunkt des Spiels
# noch gar nicht galten -- und schreibt die Runden 6 bis 13 anschliessend mit
# leicht falschen Werten fort.
#
# Der R-Walk (elo_aggregation.R:96) sortiert laengst chronologisch. Nur die
# beiden Payload-Bauer tun es nicht. Entscheidung aus dem Design vom
# 12.09.2026: R sortiert, Rust bleibt unveraendert -- kein neues Payload-Feld,
# keine Schnittstellenaenderung. Die Anstosszeit liegt R ohnehin vor.
#
# SORTIERSCHLUESSEL: Anstosszeit aufsteigend, bei Gleichstand die bestehende
# OriginalOrder (die API-Reihenfolge). Bei identischer Anstosszeit spielen
# verschiedene Teams; fuers ELO-Ergebnis ist die Reihenfolge dort gleichgueltig
# -- sie muss nur DETERMINISTISCH sein, damit sich Prognosen nicht zwischen
# zwei Laeufen ueber dieselbe Eingabe bewegen.
#
# DIE STELLE, AN DER ES STILL SCHIEFGEHT -- und der eigentliche Grund fuer
# diese Datei:
#
# transform_data() haengt an den zurueckgegebenen data.frame ein Attribut
# `elo_neutral` (transform_data.R:298). Dieser logische Vektor reist
# ZEILENGLEICH mit; rust_integration.R:237 liest ihn und reicht ihn an die
# Engine (Issue #157: am gruenen Tisch gewertete Spiele -- AWD, WO -- zaehlen
# fuer die Endtabelle, duerfen die Staerkeschaetzung aber nicht bewegen).
#
# Das Attribut ist an nichts gekoppelt ausser an die Zeilenposition. Wer die
# Zeilen umsortiert und den Vektor stehen laesst, laesst den ELO-Walk die
# FALSCHEN Spiele ueberspringen: ein regulaer gespieltes Spiel faellt aus der
# Staerkeschaetzung, ein gewertetes geht hinein. Ohne Fehlermeldung, ohne
# Warnung, ohne dass irgendeine Spaltenpruefung anschlaegt. Der Test
# "elo_neutral wandert mit" unten ist die einzige Stelle, die das faengt.


# --- Fixture-Bau --------------------------------------------------------------
#
# Bewusst im GENESTETEN Format (List-Columns einzeiliger data.frames), weil
# beide Produktivfunktionen dieses Format ausdruecklich unterstuetzen und die
# bestehenden Tests es durchgaengig benutzen (siehe helper-fixtures.R:
# create_test_fixtures_api). Kein neues Fixture-Muster erfinden.
#
# Gegenueber create_test_fixtures_api() kommen zwei Felder dazu, die es dort
# nicht braucht, hier aber den ganzen Testgegenstand ausmachen: `date` (der
# Sortierschluessel) und `league$round` (damit der Rundenfilter greift und
# extract_fixture_details() die Runde ableiten kann).

# Ein Spiel als Liste der vier List-Column-Bausteine.
ewr_spiel <- function(fixture_id, datum, status, heim_id, gast_id,
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

# Aus mehreren ewr_spiel()-Ergebnissen den fixtures-Tibble bauen, wie ihn
# retrieveResults() liefert.
ewr_fixtures <- function(...) {
  spiele <- list(...)
  tibble::tibble(
    teams   = lapply(spiele, `[[`, "teams"),
    goals   = lapply(spiele, `[[`, "goals"),
    fixture = lapply(spiele, `[[`, "fixture"),
    league  = lapply(spiele, `[[`, "league")
  )
}

# Vier Teams, Kurznamen wie in helper-fixtures.R.
ewr_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("TEA", "TEB", "TEC", "TED"),
    InitialELO = c(1500, 1450, 1550, 1400),
    stringsAsFactors = FALSE
  )
}

# Paarung je Zeile als "HEIM-GAST" -- kompakter zu lesen als zwei Vektoren,
# und die Reihenfolge ist genau das, was diese Tests pruefen.
ewr_paarungen <- function(df) paste(df$TeamHeim, df$TeamGast, sep = "-")


# --- transform_data(): chronologische Sortierung ------------------------------

test_that("transform_data sortiert ein Nachholspiel chronologisch ein", {
  # Der Kernfall des Issues. Drei Spiele, von der API in SPIELTAG-Reihenfolge
  # geliefert:
  #   Position 1: Runde 1, gespielt am 10.08.  (regulaer)
  #   Position 2: Runde 2, NACHGEHOLT am 30.09. -- verlegt, spaeter als alles
  #   Position 3: Runde 3, gespielt am 24.08.  (regulaer)
  #
  # In Listenreihenfolge sieht der Walk das Nachholspiel VOR dem Spiel vom
  # 24.08. und schreibt dessen Ergebnis mit ELO-Staenden fort, die es am
  # 30.09. laengst nicht mehr gab. Chronologisch gehoert es ans Ende.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-10T18:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    ewr_spiel(1002, "2026-09-30T18:30:00+00:00", "FT", 103, 104, 0, 3, runde = 2),
    ewr_spiel(1003, "2026-08-24T18:30:00+00:00", "FT", 101, 103, 1, 1, runde = 3)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())

  expect_equal(ewr_paarungen(ergebnis), c("TEA-TEB", "TEA-TEC", "TEC-TED"))
  # Und die Tore muessen mit ihrer Zeile gewandert sein, nicht nur die Namen.
  expect_equal(ergebnis$ToreHeim, c(2, 1, 0))
  expect_equal(ergebnis$ToreGast, c(1, 1, 3))
})

test_that("transform_data laesst die Reihenfolge ohne Nachholspiele unveraendert", {
  # Das Gegenstueck, und betrieblich das Wichtigere: Der Normalfall ist eine
  # Liga OHNE verlegte Spiele. Dort darf sich nichts bewegen -- eine
  # Prognose, die sich ohne sachlichen Grund aendert, waere eine Regression,
  # auch wenn niemand sie als Fehler meldet.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-10T15:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    ewr_spiel(1002, "2026-08-10T18:30:00+00:00", "FT", 103, 104, 1, 1, runde = 1),
    ewr_spiel(1003, "2026-08-17T15:30:00+00:00", "FT", 101, 103, 0, 2, runde = 2),
    ewr_spiel(1004, "2026-08-17T18:30:00+00:00", "NS", 102, 104, runde = 2)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())

  expect_equal(ewr_paarungen(ergebnis),
               c("TEA-TEB", "TEC-TED", "TEA-TEC", "TEB-TED"))
})

test_that("transform_data entscheidet bei gleicher Anstosszeit nach OriginalOrder", {
  # Vier Spiele, alle am selben Samstag um 15:30 -- der Regelfall eines
  # Bundesliga-Spieltags. Die Anstosszeit kann hier nichts entscheiden; die
  # API-Reihenfolge muss die Sortierung ueberleben.
  #
  # WARUM DAS GENUEGT: Bei identischer Anstosszeit spielen vier verschiedene
  # Paarungen, acht verschiedene Teams. Kein ELO-Wert, den das eine Spiel
  # veraendert, geht in ein anderes ein -- die Reihenfolge ist fuers Ergebnis
  # gleichgueltig. Gefordert ist allein Determinismus.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-10T15:30:00+00:00", "FT", 103, 102, 1, 0, runde = 1),
    ewr_spiel(1002, "2026-08-10T15:30:00+00:00", "FT", 101, 104, 2, 2, runde = 1),
    ewr_spiel(1003, "2026-08-10T15:30:00+00:00", "FT", 102, 104, 0, 1, runde = 2),
    ewr_spiel(1004, "2026-08-10T15:30:00+00:00", "FT", 101, 103, 3, 1, runde = 2)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())

  expect_equal(ewr_paarungen(ergebnis),
               c("TEC-TEB", "TEA-TED", "TEB-TED", "TEA-TEC"))
})

test_that("transform_data ist deterministisch: zwei Laeufe, dieselbe Reihenfolge", {
  # Mischform aus verschiedenen und gleichen Anstosszeiten. Ein
  # Sortierverfahren, das bei Gleichstand nicht stabil ist (oder das
  # Tiebreak vergisst), liefert hier nicht zwingend beim zweiten Lauf
  # dasselbe -- und die Prognose flackerte dann zwischen zwei
  # Scheduler-Zyklen ohne neue Daten.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-09-30T18:30:00+00:00", "FT", 103, 104, 0, 3, runde = 2),
    ewr_spiel(1002, "2026-08-10T15:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    ewr_spiel(1003, "2026-08-10T15:30:00+00:00", "FT", 103, 102, 1, 1, runde = 3),
    ewr_spiel(1004, "2026-08-24T15:30:00+00:00", "FT", 101, 103, 1, 1, runde = 3)
  )
  teams <- ewr_teams()

  lauf_a <- transform_data(fixtures, teams)
  lauf_b <- transform_data(fixtures, teams)

  expect_equal(ewr_paarungen(lauf_a), ewr_paarungen(lauf_b))
  expect_equal(attr(lauf_a, "elo_neutral"), attr(lauf_b, "elo_neutral"))
  # Und die Sortierung muss auch tatsaechlich gegriffen haben: Das
  # Nachholspiel von Position 1 gehoert ans Ende.
  expect_equal(ewr_paarungen(lauf_a),
               c("TEA-TEB", "TEC-TEB", "TEA-TEC", "TEC-TED"))
})


# --- Rueckwaertskompatibilitaet: Fixtures ohne Anstosszeit --------------------
#
# Die geteilte Fixture create_test_fixtures_api() (helper-fixtures.R:64) traegt
# KEIN date-Feld; ihre fixture-Spalte enthaelt nur id und status. Nach dem
# unnest() existiert die Spalte `fixture_date` schlicht nicht -- geprueft, nicht
# vermutet.
#
# Das ist kein Randfall, sondern die Eingabe fast aller bestehenden
# transform_data-Tests, darunter "transform_data preserves fixture order"
# (test-transform_data.R:239), der die Eingabereihenfolge ausdruecklich pinnt.
#
# Eine Sortierung, die die Spalte blind anspricht (etwa arrange(fixture_date)),
# stuerzt hier mit einem "object not found" ab -- sie wuerde die Reihenfolge
# nicht einmal falsch herstellen, sondern gar keine. Die Implementierung muss
# das Fehlen der Anstosszeit also aktiv behandeln und in diesem Fall auf die
# Eingabereihenfolge zurueckfallen.
#
# Fachlich ist dieser Rueckfall genau richtig: Ohne Anstosszeit ist die
# API-Reihenfolge die beste verfuegbare Naeherung an die Chronologie -- und
# sie ist das Verhalten von heute.

test_that("transform_data haelt ohne Anstosszeiten die Eingabereihenfolge", {
  # Exakt die geteilte Fixture, die auch die Bestandstests benutzen -- kein
  # nachgebautes Aequivalent, damit dieser Test mit ihnen zusammen bricht
  # oder zusammen haelt.
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()

  ergebnis <- transform_data(fixtures, teams)

  # Dieselbe Zusicherung wie "transform_data preserves fixture order"
  # (test-transform_data.R:239), hier als ausdruecklicher Schutz der
  # Sortier-Aenderung.
  expect_equal(ewr_paarungen(ergebnis), c("TEA-TEB", "TEC-TED", "TEA-TEC"))

  # Und die uebrigen Vertraege gelten unveraendert weiter.
  expect_equal(ergebnis$ToreHeim, c(2, 1, NA))
  expect_equal(ergebnis$ToreGast, c(1, 1, NA))
  expect_equal(ncol(ergebnis) - 4, nrow(teams))
  expect_equal(attr(ergebnis, "elo_neutral"), c(FALSE, FALSE, FALSE))
})

test_that("transform_data sortiert bei teilweise fehlenden Anstosszeiten stabil", {
  # Zweite Gestalt desselben Problems: Die Spalte EXISTIERT, traegt aber bei
  # einzelnen Spielen NA. Das ist der realistischere Produktionsfall -- ein
  # neu angesetztes Spiel ohne Termin steht im Feed neben terminierten.
  #
  # Anders als beim voelligen Fehlen der Spalte laeuft hier kein Absturz,
  # sondern eine stille Fehlsortierung: order() schiebt NA per Voreinstellung
  # ans ENDE, sortiert die uebrigen Zeilen aber um. Der Test fordert nur,
  # dass ueberhaupt eine deterministische, vollstaendige Reihenfolge
  # herauskommt und das Attribut zeilengleich bleibt -- welche Position die
  # terminlosen Spiele bekommen, legt die Implementierung fest.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, NA_character_,                "NS",  101, 102, runde = 4),
    ewr_spiel(1002, "2026-09-20T15:30:00+00:00",  "FT",  103, 104, 2, 0, runde = 3),
    ewr_spiel(1003, "2026-08-10T15:30:00+00:00",  "AWD", 101, 103, 3, 0, runde = 1)
  )
  teams <- ewr_teams()

  lauf_a <- transform_data(fixtures, teams)
  lauf_b <- transform_data(fixtures, teams)

  # Kein Spiel darf verschwinden oder doppelt auftauchen.
  expect_equal(nrow(lauf_a), 3)
  expect_setequal(ewr_paarungen(lauf_a), c("TEA-TEB", "TEC-TED", "TEA-TEC"))

  # Deterministisch ueber zwei Laeufe.
  expect_equal(ewr_paarungen(lauf_a), ewr_paarungen(lauf_b))

  # Und die Kopplung haelt auch hier: Das gewertete Spiel ist TEA-TEC, wo
  # immer die Implementierung es einsortiert.
  neutral <- attr(lauf_a, "elo_neutral")
  expect_length(neutral, 3)
  expect_equal(sum(neutral), 1)
  expect_equal(ewr_paarungen(lauf_a)[neutral], "TEA-TEC")

  # Die beiden terminierten Spiele muessen untereinander chronologisch
  # stehen -- das ist der Teil, den die Sortierung auch bei Luecken leisten
  # muss.
  paarungen <- ewr_paarungen(lauf_a)
  expect_lt(match("TEA-TEC", paarungen), match("TEC-TED", paarungen))
})


# --- Die Kopplung: elo_neutral muss mitwandern --------------------------------

test_that("transform_data laesst elo_neutral mit seiner Zeile wandern", {
  # DER TEST, DER DEN STILLEN FEHLER FAENGT.
  #
  # Aufbau, bewusst so konstruiert, dass eine vergessene Mitsortierung
  # zwingend rot wird -- und nicht zufaellig durchrutscht:
  #
  #   Position 1 (API): 05.09., FT   -- regulaer gespielt
  #   Position 2 (API): 20.08., AWD  -- am gruenen Tisch gewertet, NACHHOLFALL
  #                                     in der Zeit: es liegt VOR Position 1
  #   Position 3 (API): 06.09., FT   -- regulaer gespielt
  #
  # Vor der Sortierung ist elo_neutral == c(FALSE, TRUE, FALSE).
  # Nach chronologischer Sortierung steht das AWD-Spiel an Position 1, also
  # muss elo_neutral == c(TRUE, FALSE, FALSE) sein.
  #
  # Wer nur die Zeilen sortiert und den Vektor stehen laesst, behaelt
  # c(FALSE, TRUE, FALSE) -- und markiert damit das regulaer gespielte Spiel
  # TEA-TEB (05.09.) als ELO-neutral, waehrend das gewertete TEC-TED in die
  # Staerkeschaetzung einginge. Genau verkehrt herum. Der Vektor hat hier
  # auch nicht zufaellig dieselbe Gestalt vor und nach der Sortierung: Die
  # TRUE-Position aendert sich nachweislich von 2 auf 1.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-09-05T18:30:00+00:00", "FT",  101, 102, 2, 1, runde = 3),
    ewr_spiel(1002, "2026-08-20T18:30:00+00:00", "AWD", 103, 104, 3, 0, runde = 1),
    ewr_spiel(1003, "2026-09-06T18:30:00+00:00", "FT",  101, 103, 0, 3, runde = 3)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())
  neutral <- attr(ergebnis, "elo_neutral")

  # Erst die Zeilenfolge festnageln -- sonst waere unklar, worauf sich der
  # Vektor bezieht.
  expect_equal(ewr_paarungen(ergebnis), c("TEC-TED", "TEA-TEB", "TEA-TEC"))

  # Das Attribut muss ueberhaupt noch da sein. Ein Helfer, der elo_neutral
  # als Spalte anfuegt und sortiert, kann es beim Zurueckbauen verlieren;
  # rust_integration.R:237 faellt dann still auf "kein Spiel ist neutral"
  # zurueck.
  expect_false(is.null(neutral))
  expect_type(neutral, "logical")
  expect_length(neutral, nrow(ergebnis))

  # Und der Kern: Die Markierung sitzt auf dem gewerteten Spiel, dort wo es
  # nach der Sortierung steht.
  expect_equal(neutral, c(TRUE, FALSE, FALSE))
  expect_equal(ewr_paarungen(ergebnis)[neutral], "TEC-TED")
})

test_that("transform_data markiert bei mehreren gewerteten Spielen jedes an seinem Platz", {
  # Zwei gewertete Spiele, die durch die Sortierung in VERSCHIEDENE
  # Richtungen wandern -- eines nach vorn, eines nach hinten. Ein Helfer, der
  # den Vektor zwar mitnimmt, aber mit einer falschen Permutation (etwa der
  # umgekehrten), kaeme hier nicht durch.
  #
  #   API-Position 1: 15.09. WO   -> chronologisch Platz 4
  #   API-Position 2: 12.08. FT
  #   API-Position 3: 01.08. AWD  -> chronologisch Platz 1
  #   API-Position 4: 20.08. FT
  #
  # vorher:  c(TRUE, FALSE, TRUE, FALSE)
  # nachher: c(TRUE, FALSE, FALSE, TRUE)
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-09-15T18:30:00+00:00", "WO",  101, 102, 0, 3, runde = 5),
    ewr_spiel(1002, "2026-08-12T18:30:00+00:00", "FT",  103, 104, 1, 1, runde = 2),
    ewr_spiel(1003, "2026-08-01T18:30:00+00:00", "AWD", 102, 103, 3, 0, runde = 1),
    ewr_spiel(1004, "2026-08-20T18:30:00+00:00", "FT",  104, 101, 2, 2, runde = 3)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())
  neutral <- attr(ergebnis, "elo_neutral")

  expect_equal(ewr_paarungen(ergebnis),
               c("TEB-TEC", "TEC-TED", "TED-TEA", "TEA-TEB"))
  expect_equal(neutral, c(TRUE, FALSE, FALSE, TRUE))
})

test_that("transform_data haelt elo_neutral auch bei gleicher Anstosszeit zeilengleich", {
  # Der Tiebreak-Pfad muss den Vektor genauso mitnehmen wie der
  # Zeitvergleich. Zwei Spiele am selben Termin, das zweite davon gewertet;
  # zusaetzlich ein spaeteres Spiel, das die Sortierung tatsaechlich arbeiten
  # laesst (sonst waere die Eingabe schon sortiert und der Test blind).
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-29T15:30:00+00:00", "FT",  101, 102, 1, 0, runde = 4),
    ewr_spiel(1002, "2026-08-10T15:30:00+00:00", "FT",  103, 104, 2, 2, runde = 1),
    ewr_spiel(1003, "2026-08-10T15:30:00+00:00", "AWD", 101, 103, 3, 0, runde = 1)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())

  expect_equal(ewr_paarungen(ergebnis), c("TEC-TED", "TEA-TEC", "TEA-TEB"))
  expect_equal(attr(ergebnis, "elo_neutral"), c(FALSE, TRUE, FALSE))
})


# --- Der Vertrag nach aussen --------------------------------------------------

test_that("transform_data behaelt die Spaltenstruktur: numberTeams = ncol - 4", {
  # Die Sortierung ist eine INTERNE Angelegenheit. Der Helfer, der
  # elo_neutral als Spalte anfuegt, muss sie hinterher restlos wieder
  # entfernen -- eine uebrig gebliebene Hilfsspalte (elo_neutral, kickoff,
  # OriginalOrder) verschoebe die Team-Spalten und damit numberTeams.
  #
  # rust_integration.R leitet die Teamzahl genau so ab: ab Spalte 5 stehen
  # die Teams, also ncol - 4. Eine zusaetzliche Spalte erzeugte ein
  # Phantom-Team im Payload.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-09-30T18:30:00+00:00", "FT",  101, 102, 2, 1, runde = 2),
    ewr_spiel(1002, "2026-08-10T18:30:00+00:00", "AWD", 103, 104, 3, 0, runde = 1),
    ewr_spiel(1003, "2026-08-24T18:30:00+00:00", "FT",  101, 103, 1, 1, runde = 3)
  )
  teams <- ewr_teams()

  ergebnis <- transform_data(fixtures, teams)

  expect_equal(names(ergebnis)[1:4],
               c("TeamHeim", "TeamGast", "ToreHeim", "ToreGast"))
  expect_equal(ncol(ergebnis) - 4, nrow(teams))
  expect_equal(sort(names(ergebnis)[5:ncol(ergebnis)]), sort(teams$ShortText))

  # Keine Hilfsspalte darf ueberleben.
  expect_false(any(c("elo_neutral", "OriginalOrder", "kickoff",
                     "fixture_date") %in% names(ergebnis)))

  # Die ELO-Werte stehen weiterhin nur in der ERSTEN Zeile je Teamspalte --
  # das ist der Vertrag, den rust_integration.R als elo_values ausliest.
  # Diese Schleife laeuft ueber Zeilenpositionen; wird nach ihr sortiert,
  # wandert der Wert aus Zeile 1 weg und der Vertrag ist gebrochen.
  for (spalte in teams$ShortText) {
    werte <- ergebnis[[spalte]]
    expect_false(is.na(werte[1]))
    expect_true(all(is.na(werte[-1])))
  }
})
