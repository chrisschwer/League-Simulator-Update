# Phase 4a: Der Produktionsloop baut je Liga die Seitendaten
# (build_league_page_data) und reicht sie als league_data an
# generate_static_site() weiter. Fehlt eine Liga (Endpoint-Fehler ->
# NULL), wird trotzdem gerendert — Degradation statt Abbruch.
#
# Mocking wie in test-update-loop-gating.R: mockery::stub() gegen die
# Funktionsumgebung von update_all_leagues_loop(), Aufruf unter Repo-Root.

library(testthat)
library(mockery)

source("../../RCode/update_all_leagues_loop.R")

with_repo_root <- function(expr) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(old, "..", ".."))
  force(expr)
}

fake_fixtures <- function(statuses) {
  list(fixture = list(status = list(short = statuses)))
}

fake_transformed <- function() {
  data.frame(
    TeamHeim = "AAA", TeamGast = "BBB", ToreHeim = 1, ToreGast = 0,
    AAA = 1500, BBB = 1500
  )
}

run_one_loop <- function(build_stub, capture_env) {
  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    capture_env$fetched_leagues <- c(capture_env$fetched_leagues, league)
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust",
       function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "build_league_page_data", build_stub)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    capture_env$site_calls <- capture_env$site_calls + 1
    capture_env$league_data <- list(...)$league_data
    invisible(character(0))
  })

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10,
      saison = "2024",
      TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  })
}

test_that("der Loop baut je Liga Seitendaten und übergibt sie an den Generator", {
  capture <- new.env()
  capture$site_calls <- 0
  capture$fetched_leagues <- character()
  capture$build_calls <- list()

  build_stub <- function(fixtures, teams, ...) {
    n <- length(capture$build_calls) + 1
    capture$build_calls[[n]] <- list(fixtures = fixtures, teams = teams)
    list(tabelle = paste0("SENTINEL-", n))
  }

  run_one_loop(build_stub, capture)

  expect_equal(capture$site_calls, 1)
  # Drei Ligen -> drei Aufrufe, mit der eingelesenen TeamList als zweitem Argument
  expect_length(capture$build_calls, 3)
  expect_true(all(vapply(capture$build_calls,
                         function(x) "TeamID" %in% names(x$teams), logical(1))))

  # league_data ist nach den league_views()-Schlüsseln benannt und trägt die
  # drei Ergebnisse in Liga-Reihenfolge (BL, BL2, Liga3)
  expect_equal(names(capture$league_data),
               c("bundesliga", "zweite_bundesliga", "dritte_liga"))
  expect_equal(capture$league_data$bundesliga$tabelle, "SENTINEL-1")
  expect_equal(capture$league_data$zweite_bundesliga$tabelle, "SENTINEL-2")
  expect_equal(capture$league_data$dritte_liga$tabelle, "SENTINEL-3")
})

test_that("NULL aus build_league_page_data verhindert das Rendern nicht", {
  capture <- new.env()
  capture$site_calls <- 0
  capture$fetched_leagues <- character()

  run_one_loop(function(...) NULL, capture)

  expect_equal(capture$site_calls, 1)
  expect_type(capture$league_data, "list")
  expect_null(capture$league_data$bundesliga)
  expect_null(capture$league_data$dritte_liga)
})
