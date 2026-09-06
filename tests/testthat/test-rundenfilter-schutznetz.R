library(testthat)
source("../../RCode/transform_data.R")
source("../../RCode/league_details.R")

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

# Flache Produktionsform (so kommt es real über jsonlite::fromJSON).
rl_fixtures_flach <- function(rounds) {
  n <- length(rounds)
  fx <- data.frame(platzhalter = seq_len(n))

  fixture <- data.frame(
    id = 4000 + seq_len(n),
    date = rep("2026-09-05T13:00:00+00:00", n)
  )
  fixture$status <- data.frame(
    long = rep("Match Finished", n),
    short = rep("FT", n),
    elapsed = rep(90, n)
  )
  fx$fixture <- fixture

  fx$league <- data.frame(
    id = rep(84, n), season = rep(2025, n), round = rounds,
    stringsAsFactors = FALSE
  )

  heim <- rep(c(201, 203), length.out = n)
  gast <- rep(c(202, 204), length.out = n)
  teams <- data.frame(platzhalter = seq_len(n))
  teams$home <- data.frame(id = heim, name = paste("Team", heim),
                           winner = rep(TRUE, n))
  teams$away <- data.frame(id = gast, name = paste("Team", gast),
                           winner = rep(FALSE, n))
  teams$platzhalter <- NULL
  fx$teams <- teams

  fx$goals <- data.frame(home = rep(1, n), away = rep(0, n))
  fx$platzhalter <- NULL
  fx
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

# --- extract_fixture_details ------------------------------------------------

test_that("extract_fixture_details behält Regionalliga-Runden", {
  details <- extract_fixture_details(rl_fixtures_flach(c("Nord - 12", "North - 13")))

  expect_equal(nrow(details), 2)
  # Die Spieltagsnummer muss trotz Staffelname korrekt geparst werden.
  expect_equal(details$round, c(12L, 13L))
})

test_that("extract_fixture_details verwirft K.-o.-Runden bei Staffelnamen", {
  details <- extract_fixture_details(
    rl_fixtures_flach(c("Bayern - 33", "Relegation Round", "Bayern - 34"))
  )

  expect_equal(nrow(details), 2)
  expect_equal(details$round, c(33L, 34L))
})

test_that("extract_fixture_details bricht ab, wenn der Filter alles entfernt", {
  expect_error(
    extract_fixture_details(rl_fixtures_flach(c("Final", "Semi-finals"))),
    "Final"
  )
})

test_that("extract_fixture_details lässt leere Eingabe unberührt durch", {
  expect_error(extract_fixture_details(rl_fixtures_flach(character(0))), NA)
})

test_that("extract_fixture_details verhält sich bei Bundesliga unverändert", {
  details <- extract_fixture_details(
    rl_fixtures_flach(c("Regular Season - 12", "Regular Season - 13", "Final"))
  )

  expect_equal(nrow(details), 2)
  expect_equal(details$round, c(12L, 13L))
})
