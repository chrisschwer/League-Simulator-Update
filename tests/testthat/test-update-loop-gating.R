# The production loop must not do a full 3-league fixture fetch on idle
# iterations: it polls the cheap live endpoint and fetches fully while
# fixtures are live (current scores for the Live section), while a finished
# fixture is pending confirmation in the season data, on the first
# iteration, and on the periodic safety net.
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

# Minimal stand-in for one league's raw fixture list. The loop reads
# fixture$id + fixture$status$short (beendet-set per league, pending-set
# resolution) and id/date/status/goals for the render signature.
# transform_data() is mocked below, so the rest of the shape is irrelevant.
fake_fixtures <- function(statuses, ids = seq_along(statuses),
                          goals_home = rep(NA_integer_, length(statuses)),
                          goals_away = rep(NA_integer_, length(statuses))) {
  list(
    fixture = list(
      id = ids,
      date = rep("2026-08-29T15:30:00+02:00", length(statuses)),
      status = list(
        short = statuses,
        elapsed = rep(NA_integer_, length(statuses))
      )
    ),
    goals = list(home = goals_home, away = goals_away)
  )
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

test_that("full fetch happens while fixtures are live and skips only when idle", {
  full_fetch_leagues <- character()
  live_poll_count <- 0
  live_sequence <- list(
    c(101L), # loop 2: match live        -> full fetch (live rendering)
    c(101L), # loop 3: still live        -> full fetch
    integer(0), # loop 4: 101 finished   -> full fetch (id unknown, dropped)
    integer(0), # loop 5: idle           -> no fetch
    integer(0) # loop 6: idle            -> no fetch
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
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 6, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  })

  # Full fetches: loop 1 (always), loops 2-3 (fixture live -> keep the Live
  # section current), loop 4 (fixture left the live feed; its id is unknown
  # to the fetched leagues and is dropped from pending). Loops 5-6 are idle.
  # -> 4 full fetches x 3 leagues = 12 retrieveResults calls
  expect_length(full_fetch_leagues, 12)
  expect_equal(live_poll_count, 5) # loops 2-6
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
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 3, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  })

  # Loop 1 always fetches; loops 2-3 both hit the NULL live poll -> full fetch every time.
  expect_length(full_fetch_leagues, 9)
  expect_equal(live_poll_count, 2) # loops 2-3
})

test_that("full_fetch_every forces a periodic safety-net fetch even when idle", {
  full_fetch_leagues <- character()
  live_poll_count <- 0

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    full_fetch_leagues <<- c(full_fetch_leagues, league)
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    live_poll_count <<- live_poll_count + 1
    integer(0) # nothing live, nothing finishing - pure idle loops
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 4, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 3
    )
  })

  # Loop 1: full fetch (first iteration). Loop 2: idle -> skip.
  # Loop 3: (3 - 1) = 2 < full_fetch_every(3) -> skip. Loop 4: (4 - 1) >= 3 -> safety-net full fetch.
  # -> 2 full fetches x 3 leagues = 6 retrieveResults calls
  expect_length(full_fetch_leagues, 6)
  expect_equal(live_poll_count, 3) # loops 2-4
})

# Shared harness for the site-generation gate: runs a short loop with every
# collaborator stubbed and returns how often generate_static_site() fired.
run_loop_counting_generation <- function(loops, simulate) {
  generated <- 0L
  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(...) fake_fixtures(c("FT", "NS")))
  # Idle live set: loops 2+ never trigger a full fetch/simulation.
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    if (!simulate) stop("simulation must not run in this scenario")
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    generated <<- generated + 1L
    invisible(character(0))
  })
  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = loops, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  })
  generated
}

test_that("the loop generates the static site exactly once per simulation run", {
  # Loop 1 always simulates; loop 2 is idle (nothing live, nothing pending).
  expect_equal(run_loop_counting_generation(loops = 2, simulate = TRUE), 1L)
})

test_that("the loop passes static_site_dir through to the generator", {
  seen_dir <- NULL
  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(...) fake_fixtures(c("FT", "NS")))
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) c(101L))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(..., output_dir) {
    seen_dir <<- output_dir
    invisible(character(0))
  })
  target <- file.path(tempdir(), "site-out")
  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = target, full_fetch_every = 30
    )
  })
  expect_equal(seen_dir, target)
})

# --- Issue #154: a fixture leaving the live feed must stay "pending" until
# --- the season endpoint actually shows it as finished. The season fetch
# --- triggered by the live-feed edge can lag the live feed by seconds
# --- (observed 2026-08-29, BVB-HSV): the old one-shot edge consumed the
# --- trigger on a stale fetch and the finished game stayed in the Ausblick
# --- for up to full_fetch_every loops.

test_that("a finished fixture still live in season data is refetched until final (issue #154)", {
  bl_fetches <- 0L
  sim_calls <- 0L
  generated <- 0L
  live_poll_count <- 0L
  live_sequence <- list(
    c(101L), # loop 2: match live -> full fetch (live rendering)
    integer(0), # loop 3: 101 left the live feed -> full fetch (stale)
    integer(0), # loop 4: pending 101 not final yet -> full fetch again
    integer(0) # loop 5: pending resolved -> no fetch
  )

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") bl_fetches <<- bl_fetches + 1L
    # Fetches 1-3 (loops 1-3) still show fixture 101 as live ("2H"): the
    # loop-3 fetch is the stale one from issue #154. From fetch 4 (loop 4)
    # on, the season data has caught up ("FT").
    if (bl_fetches <= 3L) {
      fake_fixtures(c("FT", "2H"), ids = c(100L, 101L))
    } else {
      fake_fixtures(c("FT", "FT"), ids = c(100L, 101L))
    }
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    live_poll_count <<- live_poll_count + 1L
    live_sequence[[min(live_poll_count, length(live_sequence))]]
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    sim_calls <<- sim_calls + 1L
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    generated <<- generated + 1L
    invisible(character(0))
  })

  msgs <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 5, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  }))

  # Full fetches: loop 1, loop 2 (fixture live), loop 3 (edge, stale) AND
  # loop 4 (pending retry).
  expect_equal(bl_fetches, 4L)
  # Simulations: loop 1 all leagues (BL, BL2, Liga3 + Aufstieg = 4 calls),
  # loop 4 only the league whose beendet set changed (all three fakes share
  # the same fixtures here, so again 4 calls). The stale loop-3 fetch must
  # NOT simulate.
  expect_equal(sim_calls, 8L)
  # Renders: loop 1 and loop 4. The stale loop-3 fetch carries no visible
  # change (identical fixture data) and must not render.
  expect_equal(generated, 2L)
  # The unresolved pending fixture is logged instead of failing silently.
  expect_true(any(grepl("not yet final", msgs)))
})

test_that("a fixture-data change without new finished games renders without simulating", {
  sim_calls <- 0L
  generated <- 0L
  bl_fetches <- 0L

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") bl_fetches <<- bl_fetches + 1L
    # Same beendet set both fetches; only the live score of fixture 101
    # changes (0:0 -> 1:0) between fetch 1 (loop 1) and fetch 2 (safety
    # fetch, loop 3).
    fake_fixtures(c("FT", "2H"),
      ids = c(100L, 101L),
      goals_home = c(2L, if (bl_fetches <= 1L) 0L else 1L),
      goals_away = c(0L, 0L)
    )
  })
  # Idle live set: no edge- or live-triggered fetches, only the safety net.
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    sim_calls <<- sim_calls + 1L
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    generated <<- generated + 1L
    invisible(character(0))
  })

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 3, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 2
    )
  })

  expect_equal(bl_fetches, 2L) # loop 1 + safety fetch loop 3
  expect_equal(sim_calls, 4L) # loop 1 only; the score change simulates nothing
  expect_equal(generated, 2L) # ... but it does re-render the site
})

test_that("simulation triggers on a changed beendet set even when the count is unchanged", {
  sim_calls <- 0L
  bl_fetches <- 0L

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") bl_fetches <<- bl_fetches + 1L
    # One finished game in both fetches, but a DIFFERENT one: e.g. an
    # awarded result flipping while another goes final. A count-based
    # comparison ("1 == 1") would skip the simulation.
    if (bl_fetches <= 1L) {
      fake_fixtures(c("FT", "NS"), ids = c(100L, 101L))
    } else {
      fake_fixtures(c("NS", "FT"), ids = c(100L, 101L))
    }
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    sim_calls <<- sim_calls + 1L
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 3, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 2
    )
  })

  expect_equal(bl_fetches, 2L) # loop 1 + safety fetch loop 3
  expect_equal(sim_calls, 8L) # loop 1 AND loop 3: the beendet SET changed
})

# --- Live-Cadence (Folge-PR zu #154): solange Spiele live sind, wird jede
# --- Runde voll gefetcht, damit die Live-Sektion aktuelle Zwischenstände
# --- zeigt. Simuliert wird weiterhin nur, wenn sich die Menge beendeter
# --- Spiele ändert (Methodik: "nach jedem realen Spiel").

test_that("live fixtures trigger a full fetch and re-render every loop without simulating", {
  bl_fetches <- 0L
  sim_calls <- 0L
  generated <- 0L

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") bl_fetches <<- bl_fetches + 1L
    # The live score of fixture 101 changes on every fetch (goal per loop).
    fake_fixtures(c("FT", "2H"),
      ids = c(100L, 101L),
      goals_home = c(2L, bl_fetches),
      goals_away = c(0L, 0L)
    )
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) c(101L))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    sim_calls <<- sim_calls + 1L
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    generated <<- generated + 1L
    invisible(character(0))
  })

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 3, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  })

  expect_equal(bl_fetches, 3L) # one full fetch per loop while 101 is live
  expect_equal(sim_calls, 4L) # loop 1 only; live scores simulate nothing
  expect_equal(generated, 3L) # ... but every score change re-renders
})

test_that("an awarded result (AWD) resolves a pending finished fixture", {
  bl_fetches <- 0L
  sim_calls <- 0L
  live_poll_count <- 0L
  live_sequence <- list(
    c(101L), # loop 2: match live -> full fetch
    integer(0), # loop 3: 101 left the live feed -> full fetch, shows AWD
    integer(0), # loop 4: pending resolved -> no fetch
    integer(0) # loop 5: idle -> no fetch
  )

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") bl_fetches <<- bl_fetches + 1L
    # From fetch 3 (loop 3) on, fixture 101 is awarded (AWD): final for the
    # pending set, though not part of the beendet set (FT/AET/PEN).
    if (bl_fetches <= 2L) {
      fake_fixtures(c("FT", "2H"), ids = c(100L, 101L))
    } else {
      fake_fixtures(c("FT", "AWD"), ids = c(100L, 101L))
    }
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    live_poll_count <<- live_poll_count + 1L
    live_sequence[[min(live_poll_count, length(live_sequence))]]
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    sim_calls <<- sim_calls + 1L
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  msgs <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 5, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  }))

  expect_equal(bl_fetches, 3L) # loops 1-3 only; loops 4-5 are idle
  expect_false(any(grepl("not yet final", msgs))) # AWD must not stay pending
  expect_equal(sim_calls, 4L) # loop 1 only: AWD is final but NOT beendet
})

test_that("a pending finished fixture survives a failed full fetch", {
  bl_fetches <- 0L
  sim_calls <- 0L
  generated <- 0L
  live_poll_count <- 0L
  live_sequence <- list(
    c(101L), # loop 2: match live -> full fetch
    integer(0), # loop 3: 101 left the live feed -> full fetch FAILS (NULL)
    integer(0), # loop 4: pending must survive -> full fetch, now FT
    integer(0) # loop 5: resolved -> no fetch
  )

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") bl_fetches <<- bl_fetches + 1L
    if (bl_fetches == 3L) {
      return(NULL) # fetch 3 (loop 3) fails for every league
    }
    if (bl_fetches <= 2L) {
      fake_fixtures(c("FT", "2H"), ids = c(100L, 101L))
    } else {
      fake_fixtures(c("FT", "FT"), ids = c(100L, 101L))
    }
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    live_poll_count <<- live_poll_count + 1L
    live_sequence[[min(live_poll_count, length(live_sequence))]]
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    sim_calls <<- sim_calls + 1L
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    generated <<- generated + 1L
    invisible(character(0))
  })

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 5, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  })

  expect_equal(bl_fetches, 4L) # loops 1, 2, 3 (failed) and 4 (retry)
  expect_equal(sim_calls, 8L) # loop 1 + loop 4 (101 newly finished)
  expect_equal(generated, 2L) # loop 1 + loop 4
})

test_that("update_all_leagues_loop has no machine-specific default output directory", {
  fmls <- formals(update_all_leagues_loop)
  expect_false("shiny_directory" %in% names(fmls))
  expect_false(grepl("Dropbox", paste(deparse(fmls$static_site_dir), collapse = ""), fixed = TRUE))
})
