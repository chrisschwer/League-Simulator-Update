library(testthat)
source("../../RCode/league_details.R")

# extract_fixture_details() zieht aus der genesteten api-football-Struktur die
# Angaben, die transform_data() bisher verwirft: Spieltag, Anstoßzeit, Status,
# Team-IDs/-Namen und Tore. Eine Zeile je Spiel, API-Reihenfolge bleibt
# erhalten (Positions-Alignment mit dem transform_data-Spielplan).

make_nested_fixtures <- function() {
  tibble::tibble(
    fixture = list(
      data.frame(
        id = 1001, date = "2026-11-27T19:30:00+00:00",
        status = I(list(data.frame(short = "FT")))
      ),
      data.frame(
        id = 1002, date = "2026-11-28T14:30:00+00:00",
        status = I(list(data.frame(short = "NS")))
      ),
      data.frame(
        id = 9999, date = "2027-05-27T18:30:00+00:00",
        status = I(list(data.frame(short = "NS")))
      )
    ),
    league = list(
      data.frame(round = "Regular Season - 12"),
      data.frame(round = "Regular Season - 13"),
      data.frame(round = "Final")   # Relegation, gehört nicht in die Saison
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
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      )
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    )
  )
}

test_that("extract_fixture_details liefert eine flache Zeile je Regular-Season-Spiel", {
  details <- extract_fixture_details(make_nested_fixtures())

  expect_s3_class(details, "data.frame")
  expect_equal(nrow(details), 2) # "Final" ist herausgefiltert
  expect_true(all(c(
    "fixture_id", "round", "kickoff", "status",
    "home_id", "away_id", "home_name", "away_name",
    "goals_home", "goals_away"
  ) %in% names(details)))

  expect_equal(details$fixture_id, c(1001, 1002))
  expect_equal(details$round, c(12L, 13L))
  expect_equal(details$status, c("FT", "NS"))
  expect_equal(details$home_id, c(101, 103))
  expect_equal(details$away_id, c(102, 104))
  expect_equal(details$home_name, c("Team A", "Team C"))
  expect_equal(details$away_name, c("Team B", "Team D"))
})

test_that("extract_fixture_details parst die Anstoßzeit als POSIXct in UTC", {
  details <- extract_fixture_details(make_nested_fixtures())

  expect_s3_class(details$kickoff, "POSIXct")
  expect_equal(
    details$kickoff[1],
    as.POSIXct("2026-11-27 19:30:00", tz = "UTC")
  )
})

test_that("extract_fixture_details übernimmt Tore nur als Zahlen, NA für offene Spiele", {
  details <- extract_fixture_details(make_nested_fixtures())

  expect_equal(details$goals_home[1], 2)
  expect_equal(details$goals_away[1], 1)
  expect_true(is.na(details$goals_home[2]))
  expect_true(is.na(details$goals_away[2]))
})

test_that("extract_fixture_details ist positionsgleich mit transform_data", {
  # Beide Funktionen filtern auf Regular-Season-Runden und behalten die
  # API-Reihenfolge — Zeile i beschreibt in beiden dasselbe Spiel. Darauf
  # verlässt sich das Index-Mapping der /league-details-Antwort.
  source("../../RCode/transform_data.R")
  fixtures <- make_nested_fixtures()
  teams <- data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    InitialELO = c(1500, 1500, 1500, 1500),
    stringsAsFactors = FALSE
  )

  details <- extract_fixture_details(fixtures)
  schedule <- transform_data(fixtures, teams)

  expect_equal(nrow(details), nrow(schedule))
  expect_equal(
    teams$ShortText[match(details$home_id, teams$TeamID)],
    schedule$TeamHeim
  )
  expect_equal(
    teams$ShortText[match(details$away_id, teams$TeamID)],
    schedule$TeamGast
  )
})
