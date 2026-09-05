# Der Heimvorteil ist eine Modellkonstante und lebt ausschliesslich im
# Rust-Server (ADR 0002). Dieser Test haelt fest, dass die R-Seite ihn im
# Simulationspfad nicht mitsendet; das Gegenstueck fuer /league-details steht
# in test-league-details-client.R.
#
# Warum beides abgedeckt sein muss: Die Prognose-Heatmap entsteht ueber
# POST /simulate, Ligatabelle/Rueckblick/Ausblick ueber POST /league-details.
# Sendet nur einer der beiden Pfade einen abweichenden Wert, widersprechen sich
# Heatmap und 1/X/2-Werte derselben Seite - ohne dass etwas fehlschlaegt.

library(mockery)

test_that("simulate_league_rust sendet home_advantage nicht mit", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "rust_integration.R"), local = env)

  captured <- NULL
  stub(env$simulate_league_rust, "POST", function(url, body, ...) {
    captured <<- jsonlite::fromJSON(body)
    stop("abbruch nach payload-erfassung")
  })

  try(env$simulate_league_rust(
    schedule = matrix(c(1, 2, NA, NA), nrow = 1),
    elo_values = c(1500, 1500),
    team_names = c("AAA", "BBB")
  ), silent = TRUE)

  expect_false(is.null(captured))
  expect_false("home_advantage" %in% names(captured))
  expect_equal(captured$mod_factor, 20)
})

test_that("ein explizit uebergebener home_advantage landet im Payload", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "rust_integration.R"), local = env)

  captured <- NULL
  stub(env$simulate_league_rust, "POST", function(url, body, ...) {
    captured <<- jsonlite::fromJSON(body)
    stop("abbruch nach payload-erfassung")
  })

  try(env$simulate_league_rust(
    schedule = matrix(c(1, 2, NA, NA), nrow = 1),
    elo_values = c(1500, 1500),
    team_names = c("AAA", "BBB"),
    home_advantage = 40
  ), silent = TRUE)

  expect_equal(captured$home_advantage, 40)
})
