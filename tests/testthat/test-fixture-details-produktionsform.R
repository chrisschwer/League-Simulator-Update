library(testthat)
source("../../RCode/league_details.R")

# Regressionstest aus der Phase-4a-QA (2026-08-28): Die echte api-football-
# Antwort kommt über jsonlite::fromJSON (retrieveResults) als FLACHE
# Data-Frame-Struktur — fixture/league/teams/goals sind data.frames mit
# atomaren bzw. df-Spalten, keine Listen von data.frames wie in den
# genesteten Test-Mocks. extract_fixture_details() muss beide Formen
# verarbeiten (Spiegelfall zum transform_data-List-Column-Fix aus Phase 2).

flache_produktions_fixtures <- function() {
  n <- 3
  fx <- data.frame(platzhalter = seq_len(n))

  fixture <- data.frame(
    id = c(3001, 3002, 9999),
    date = c("2026-11-27T19:30:00+00:00", "2026-11-28T14:30:00+00:00",
             "2027-05-27T18:30:00+00:00")
  )
  fixture$status <- data.frame(
    long = c("Match Finished", "Not Started", "Not Started"),
    short = c("FT", "NS", "NS"),
    elapsed = c(90, NA, NA)
  )
  fx$fixture <- fixture

  fx$league <- data.frame(
    id = c(78, 78, 78),
    season = c(2026, 2026, 2026),
    round = c("Regular Season - 12", "Regular Season - 13", "Final")
  )

  teams <- data.frame(platzhalter = seq_len(n))
  teams$home <- data.frame(
    id = c(101, 103, 101),
    name = c("Team A", "Team C", "Team A"),
    winner = c(TRUE, NA, NA)
  )
  teams$away <- data.frame(
    id = c(102, 104, 104),
    name = c("Team B", "Team D", "Team D"),
    winner = c(FALSE, NA, NA)
  )
  teams$platzhalter <- NULL
  fx$teams <- teams

  fx$goals <- data.frame(home = c(2, NA, NA), away = c(1, NA, NA))

  fx$platzhalter <- NULL
  fx
}

test_that("extract_fixture_details verarbeitet die flache Produktionsform", {
  details <- extract_fixture_details(flache_produktions_fixtures())

  expect_equal(nrow(details), 2) # "Final" herausgefiltert
  expect_equal(details$fixture_id, c(3001, 3002))
  expect_equal(details$round, c(12L, 13L))
  expect_equal(details$status, c("FT", "NS"))
  expect_equal(details$home_id, c(101, 103))
  expect_equal(details$away_id, c(102, 104))
  expect_equal(details$home_name, c("Team A", "Team C"))
  expect_equal(details$away_name, c("Team B", "Team D"))
  expect_equal(details$goals_home, c(2, NA))
  expect_equal(
    details$kickoff[1],
    as.POSIXct("2026-11-27 19:30:00", tz = "UTC")
  )
})

test_that("flache und genestete Form liefern identische Details", {
  # Dieselben drei Spiele in der genesteten Mock-Form der frozen Suite.
  genestet <- tibble::tibble(
    fixture = list(
      data.frame(id = 3001, date = "2026-11-27T19:30:00+00:00",
                 status = I(list(data.frame(short = "FT")))),
      data.frame(id = 3002, date = "2026-11-28T14:30:00+00:00",
                 status = I(list(data.frame(short = "NS")))),
      data.frame(id = 9999, date = "2027-05-27T18:30:00+00:00",
                 status = I(list(data.frame(short = "NS"))))
    ),
    league = list(
      data.frame(round = "Regular Season - 12"),
      data.frame(round = "Regular Season - 13"),
      data.frame(round = "Final")
    ),
    teams = list(
      data.frame(home = I(list(data.frame(id = 101, name = "Team A"))),
                 away = I(list(data.frame(id = 102, name = "Team B")))),
      data.frame(home = I(list(data.frame(id = 103, name = "Team C"))),
                 away = I(list(data.frame(id = 104, name = "Team D")))),
      data.frame(home = I(list(data.frame(id = 101, name = "Team A"))),
                 away = I(list(data.frame(id = 104, name = "Team D"))))
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    )
  )

  aus_flach <- extract_fixture_details(flache_produktions_fixtures())
  aus_genestet <- extract_fixture_details(genestet)

  gemeinsame <- c("fixture_id", "round", "kickoff", "status",
                  "home_id", "home_name", "away_id", "away_name",
                  "goals_home", "goals_away")
  expect_equal(aus_flach[, gemeinsame], aus_genestet[, gemeinsame])
})
