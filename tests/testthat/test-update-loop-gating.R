# The production loop must not do a full 3-league fixture fetch on every
# iteration: it polls the cheap live endpoint and fetches fully only when
# a live fixture disappeared (finished), on the first iteration, or on the
# periodic safety net.
#
# Mocking approach: this project runs tests via plain source() (see
# tests/testthat.R -> test_dir()), not as an installed/loaded package, so
# testthat::local_mocked_bindings() cannot resolve a namespace here (it
# requires .package/pkgload context and errors with "No packages loaded
# with pkgload"). update_all_leagues_loop() also re-source()s its
# collaborators (retrieveResults.R, transform_data.R, ...) into globalenv()
# on every call, which would immediately clobber any globalenv() binding
# mock anyway. mockery::stub() sidesteps both problems: it rewrites the
# lookup inside update_all_leagues_loop()'s own function environment, so
# it is immune to those later source() calls - already the pattern used
# elsewhere in this suite (see test-season-processor.R).

library(testthat)
library(mockery)

source("../../RCode/update_all_leagues_loop.R")

# update_all_leagues_loop() itself source()s its collaborators with paths
# relative to the repo root (e.g. "RCode/rust_integration.R"), but testthat
# runs this file with the working directory set to tests/testthat. Run the
# call under test with cwd temporarily switched to the repo root, mirroring
# the with_repo_root() helper in test-rust-required.R.
with_repo_root <- function(expr) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(old, "..", "..")) # tests/testthat -> repo root
  force(expr)
}

# Minimal stand-in for one league's raw fixture list: only
# fixture$status$short is read directly by the loop (for the FT_*_new
# counts). transform_data() is mocked below, so the rest of the shape is
# irrelevant.
fake_fixtures <- function(statuses) {
  list(fixture = list(status = list(short = statuses)))
}

# Minimal stand-in for transform_data()'s output: leagueSimulatorRust() is
# mocked below and never inspects it, but the Liga3-second-team penalty
# loop in the production code does `for (j in 5:dim(Liga3)[2])` and reads
# `names(Liga3)[j]`, so the fake needs at least 5 columns with team-like
# names in columns 5+.
fake_transformed <- function() {
  data.frame(
    TeamHeim = "AAA", TeamGast = "BBB", ToreHeim = 1, ToreGast = 0,
    AAA = 1500, BBB = 1500
  )
}

test_that("full fetch happens only on loop 1 and when a live fixture ends", {
  full_fetch_leagues <- character()
  live_poll_count <- 0
  live_sequence <- list(
    c(101L, 102L), # loop 2: two matches live -> no full fetch
    c(101L, 102L), # loop 3: unchanged        -> no full fetch
    c(102L), # loop 4: 101 finished     -> full fetch
    integer(0) # loop 5: 102 finished     -> full fetch
  )

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    full_fetch_leagues <<- c(full_fetch_leagues, league)
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    live_poll_count <<- live_poll_count + 1
    live_sequence[[min(live_poll_count, length(live_sequence))]]
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "updateShiny", function(...) invisible(NULL))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 5, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      shiny_directory = tempdir(), full_fetch_every = 30
    )
  })

  # Full fetches: loop 1 (always), loop 4 and loop 5 (fixture left live set)
  # -> 3 full fetches x 3 leagues = 9 retrieveResults calls
  expect_length(full_fetch_leagues, 9)
  expect_equal(live_poll_count, 4) # loops 2-5
})

test_that("a failed live poll (NULL) forces a full fetch", {
  full_fetch_leagues <- character()
  live_poll_count <- 0

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    full_fetch_leagues <<- c(full_fetch_leagues, league)
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    live_poll_count <<- live_poll_count + 1
    NULL # simulate an API error on the live endpoint
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "updateShiny", function(...) invisible(NULL))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 3, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      shiny_directory = tempdir(), full_fetch_every = 30
    )
  })

  # Loop 1 always fetches; loops 2-3 both hit the NULL live poll -> full fetch every time.
  expect_length(full_fetch_leagues, 9)
  expect_equal(live_poll_count, 2) # loops 2-3
})

test_that("full_fetch_every forces a periodic safety-net fetch even with a stable live set", {
  full_fetch_leagues <- character()
  live_poll_count <- 0

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    full_fetch_leagues <<- c(full_fetch_leagues, league)
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    live_poll_count <<- live_poll_count + 1
    c(101L) # always the same single live fixture - never "finishes"
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "updateShiny", function(...) invisible(NULL))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 4, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      shiny_directory = tempdir(), full_fetch_every = 3
    )
  })

  # Loop 1: full fetch (first iteration). Loop 2: live poll, stable -> skip.
  # Loop 3: (3 - 1) = 2 < full_fetch_every(3) -> skip. Loop 4: (4 - 1) >= 3 -> safety-net full fetch.
  # -> 2 full fetches x 3 leagues = 6 retrieveResults calls
  expect_length(full_fetch_leagues, 6)
  expect_equal(live_poll_count, 3) # loops 2-4
})
