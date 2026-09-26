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
