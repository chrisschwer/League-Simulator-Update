library(testthat)
source("../../RCode/league_details.R")

# Härtung des Payload-Builders (Übertrag aus dem Phase-2-Review, Minor 2):
# NA-Werte dürfen nie als String "NA" in den JSON-Payload gelangen — der
# Rust-Endpoint lehnt sonst die GANZE Liga-Anfrage mit 422 ab.

test_that("FT mit fehlenden Toren (API-Glitch) wird als offenes Spiel gesendet", {
  details <- make_details(
    fd_row(1, 1, "2026-08-28 18:30", "FT", 101, 102, NA, NA),
    fd_row(2, 1, "2026-08-29 13:30", "FT", 103, 104, 2, 1)
  )

  payload <- build_league_details_payload(details, make_test_teams())

  # Das defekte Spiel verliert seine Tore (null), statt "NA" zu serialisieren;
  # das intakte Spiel bleibt unberührt.
  expect_null(payload$schedule[[1]][[3]])
  expect_null(payload$schedule[[1]][[4]])
  expect_equal(payload$schedule[[2]][[3]], 2)

  json <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null")
  expect_false(grepl('"NA"', json, fixed = TRUE))
})

test_that("halb gesetztes Torpaar wird komplett verworfen", {
  details <- make_details(
    fd_row(1, 1, "2026-08-28 18:30", "FT", 101, 102, 1, NA)
  )

  payload <- build_league_details_payload(details, make_test_teams())

  expect_null(payload$schedule[[1]][[3]])
  expect_null(payload$schedule[[1]][[4]])
})

test_that("unbekannte Team-ID führt zu einem Fehler mit der ID in der Meldung", {
  details <- make_details(
    fd_row(1, 1, "2026-08-28 18:30", "FT", 999, 102, 2, 1)
  )

  expect_error(
    build_league_details_payload(details, make_test_teams()),
    "999"
  )
})
