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
# Erwartungswerte folgen der Ligazahl, nicht festen Zahlen: Sobald eine
# weitere Liga aktiv geschaltet wird, muessen diese Tests weiterhin gelten --
# sie pruefen das GATING, nicht wie viele Ligen es gibt.
n_ligen <- function() {
  env <- new.env()
  source(file.path("..", "..", "RCode", "league_registry.R"), local = env)
  length(env$league_ids())
}

# Simulationen je Runde: eine je Liga, plus ein zweiter Lauf fuer jede Liga,
# aus der Zweitvertretungen nicht aufsteigen duerfen (3. Liga, 2. Frauen-BL).
n_sims_pro_runde <- function() {
  env <- new.env()
  source(file.path("..", "..", "RCode", "league_registry.R"), local = env)
  ids <- env$league_ids()
  length(ids) + sum(vapply(ids, env$has_promotion_restriction, logical(1)))
}

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
  expect_length(full_fetch_leagues, 4 * n_ligen())
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
  expect_length(full_fetch_leagues, 3 * n_ligen())
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
  expect_length(full_fetch_leagues, 2 * n_ligen())
  expect_equal(live_poll_count, 3) # loops 2-4
})

# --- Der Safety-Timer haengt am ERFOLG des Fetches (Issue #128, Punkt 1) ---
#
# Das Sicherheitsnetz (full_fetch_every) existiert fuer den Fall, dass die
# Flanken-Erkennung etwas verpasst. Wird sein Zaehler schon beim VERSUCH
# zurueckgesetzt statt beim Erfolg, ist es genau dann abgeschaltet, wenn es
# gebraucht wird: waehrend die API klemmt. Bei Produktionstakt (2 Minuten,
# Default 30) verzoegert das den naechsten Versuch um bis zu eine Stunde.
#
# Die beiden Tests halten die zwei Haelften derselben Aussage fest -- ohne
# den zweiten liesse sich der erste erfuellen, indem man den Timer gar nicht
# mehr setzt.
#
# ANNAHME BEIDER HARNESSE: Loop 1 ruft ohne Live-Poll voll ab, der erste
# Poll gehoert zu Loop 2. Daraus leiten sie die Rundennummer ab
# (aktueller_loop = polls + 1). Wuerde Punkt 2 des Issues (Loop-1-Seeding)
# je ueber einen ZUSAETZLICHEN Poll geloest, waere die Zaehlung um eins
# verschoben. Die im Issue-Kommentar vom 06.09.2026 vorgeschlagene
# billigere Variante -- prev_live_ids aus den Statusdaten des Loop-1-
# Vollabrufs seeden, ohne Extra-Request -- beruehrt sie nicht.

# Ein Durchlauf von fuenf durchgehend leeren Runden mit full_fetch_every = 3.
# Nur der Safety-Fetch kann hier abrufen; `fetch_faellt_aus` bestimmt, ob der
# faellige Abruf in Loop 4 gelingt. Genau darin unterscheiden sich die beiden
# Tests -- alles andere ist identisch, und als zwei Kopien nebeneinander
# waere der eine Unterschied nicht zu sehen.
#
# @return Die Loop-Nummern, in denen abgerufen wurde.
lauf_mit_safety_fetch <- function(fetch_faellt_aus) {
  fetch_loops <- integer(0)
  polls <- 0L
  aktueller_loop <- 1L # Loop 1 ruft ohne Poll voll ab

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") {
      fetch_loops <<- c(fetch_loops, aktueller_loop)
    }
    if (fetch_faellt_aus && aktueller_loop == 4L) {
      return(NULL) # der faellige Abruf scheitert, fuer JEDE Liga
    }
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    # Der Poll laeuft genau einmal je Loop und vor dem Abruf; der erste
    # gehoert zu Loop 2 (s. Annahme oben).
    polls <<- polls + 1L
    aktueller_loop <<- polls + 1L
    integer(0) # durchgehend idle
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 5, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 3
    )
  })

  fetch_loops
}

test_that("ein fehlgeschlagener Safety-Fetch setzt den Timer NICHT zurueck", {
  # Loop 1: Vollabruf ohne Poll, gelingt -> Timer auf 1. Loops 2, 3: idle,
  # 1 bzw. 2 < 3 -> kein Abruf. Loop 4: 4 - 1 = 3 >= 3, faellig -> Abruf,
  # schlaegt fehl. Loop 5: Der Timer darf noch auf 1 stehen, also
  # 5 - 1 = 4 >= 3 -> erneuter Versuch. Mit dem Fehler stuende er auf 4
  # (5 - 4 = 1 < 3) und Loop 5 bliebe still.
  expect_identical(lauf_mit_safety_fetch(fetch_faellt_aus = TRUE), c(1L, 4L, 5L))
})

test_that("ein erfolgreicher Safety-Fetch setzt den Timer sehr wohl zurueck", {
  # Gegenprobe: Der Fix darf den Timer nicht abschaffen, sondern nur an den
  # Erfolg binden. Gelingt Loop 4, steht der Timer auf 4 und Loop 5 bleibt
  # still (5 - 4 = 1 < 3).
  expect_identical(lauf_mit_safety_fetch(fetch_faellt_aus = FALSE), c(1L, 4L))
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
  expect_equal(sim_calls, 2L * n_sims_pro_runde())
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
  expect_equal(sim_calls, n_sims_pro_runde()) # loop 1 only; the score change simulates nothing
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
  expect_equal(sim_calls, 2L * n_sims_pro_runde()) # loop 1 AND loop 3: the beendet SET changed
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
  expect_equal(sim_calls, n_sims_pro_runde()) # loop 1 only; live scores simulate nothing
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
  expect_equal(sim_calls, n_sims_pro_runde()) # loop 1 only: AWD is final but NOT beendet
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
  expect_equal(sim_calls, 2L * n_sims_pro_runde()) # loop 1 + loop 4 (101 newly finished)
  expect_equal(generated, 2L) # loop 1 + loop 4
})

test_that("update_all_leagues_loop has no machine-specific default output directory", {
  fmls <- formals(update_all_leagues_loop)
  expect_false("shiny_directory" %in% names(fmls))
  expect_false(grepl("Dropbox", paste(deparse(fmls$static_site_dir), collapse = ""), fixed = TRUE))
})

# --- Issue #205: das Frauen-Tormodell (ADR 0004) muss beide
# --- leagueSimulatorRust()-Aufrufe erreichen (Hauptlauf und Malus-Lauf),
# --- sonst laufen die Frauen-Ligen (82, 1034) mit den Herren-Konstanten.
#
# Die Registry bleibt UNGESTUBBT: Alle zehn Ligen sind aktiv, retrieveResults()
# wird fuer jede Liga einzeln aufgerufen (Parameter `league` = api_id), und
# leagueSimulatorRust() faellt fuer jede Liga in Registry-Reihenfolge an --
# genau wie in run_loop_capturing() aus test-n-ligen-entflechtung.R. Um einen
# Aufruf seiner Liga zuzuordnen, wird die Aufrufreihenfolge an
# active_league_keys() (plus, wo has_promotion_restriction() gilt, ein
# zweiter Malus-Aufruf direkt danach) ausgerichtet -- leagueSimulatorRust()
# selbst bekommt keine Liga-ID uebergeben.

test_that("das Frauen-Tormodell erreicht beide leagueSimulatorRust-Aufrufe (Liga 82 vs. 78)", {
  reg <- new.env()
  source(file.path("..", "..", "RCode", "league_registry.R"), local = reg)
  liga_keys <- reg$active_league_keys()
  liga_ids <- stats::setNames(
    vapply(reg$active_leagues(), function(l) l$api_id, character(1)),
    liga_keys
  )
  hat_malus <- stats::setNames(
    vapply(liga_ids, reg$has_promotion_restriction, logical(1)),
    liga_keys
  )

  # Erwartete Aufrufreihenfolge: je Liga ein Hauptlauf-Call, direkt gefolgt
  # von einem Malus-Call, wo has_promotion_restriction() TRUE ist.
  erwartete_reihenfolge <- unlist(lapply(liga_keys, function(k) {
    if (hat_malus[[k]]) c(k, k) else k
  }))

  calls <- list()
  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    calls[[length(calls) + 1]] <<- list(...)
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  })

  expect_equal(length(calls), length(erwartete_reihenfolge))

  frauen_bl_idx <- which(erwartete_reihenfolge == "frauen_bundesliga")
  herren_bl_idx <- which(erwartete_reihenfolge == "bundesliga")

  # Liga 82 (Frauen-Bundesliga): das Frauen-Tormodell muss im Aufruf stehen.
  frauen_call <- calls[[frauen_bl_idx[[1]]]]
  expect_equal(frauen_call$toreSlope, 0.0024058833)
  expect_equal(frauen_call$toreIntercept, 1.6527603153)

  # Gegenprobe Liga 78 (Bundesliga, Herren): kein Tormodell im Aufruf --
  # der Rust-Server behaelt seine Defaults (ADR 0002).
  herren_call <- calls[[herren_bl_idx[[1]]]]
  expect_null(herren_call$toreSlope)
  expect_null(herren_call$toreIntercept)

  # 2. Frauen-Bundesliga (1034) hat has_promotion_restriction (ADR 0002-Regel
  # "Zweitvertretungen duerfen nicht aufsteigen") -- ihr Malus-Lauf
  # (Aufrufstelle 2, :284) muss dasselbe Tormodell tragen wie ihr Hauptlauf.
  zweite_frauen_idx <- which(erwartete_reihenfolge == "zweite_frauen_bundesliga")
  expect_length(zweite_frauen_idx, 2) # Hauptlauf und Malus-Lauf
  for (idx in zweite_frauen_idx) {
    expect_equal(calls[[idx]]$toreSlope, 0.0024058833, info = paste("Aufruf", idx))
    expect_equal(calls[[idx]]$toreIntercept, 1.6527603153, info = paste("Aufruf", idx))
  }
})

# --- Issue #208: eine Liga darf nicht mehr alle blockieren -----------------
#
# Vorher riss ein NULL aus retrieveResults() (bl_fetches == 3 in "a pending
# finished fixture survives a failed full fetch" oben) IMMER die ganze
# Runde mit -- aber in JEDEM bestehenden Test scheitert der Fetch fuer JEDE
# Liga zugleich (s. Kommentare "fuer JEDE Liga" an beiden Stellen oben). Kein
# bestehender Test bindet fest, was passiert, wenn NUR EINE von zehn Ligen
# fehlschlaegt -- also verlangt der Auftrag hier volle Pro-Liga-Isolation:
# ein Fehlschlag (Fetch-NULL, transform_data()- oder Simulations-Fehler)
# einer Liga darf die uebrigen neun weder am Simulieren noch am Rendern
# hindern.
#
# fake_transformed() liefert testweise IMMER dieselbe 1-Spiel-Tabelle,
# unabhaengig von der Liga -- die drei Tests unten muessen deshalb ihre
# jeweilige Fehlerquelle an EINEM Ligaschluessel/einer API-ID festmachen,
# nicht am Rueckgabewert.

test_that("ein NULL aus retrieveResults() fuer eine Liga blockiert die anderen neun nicht", {
  generated <- 0L
  seen_ergebnisse <- NULL
  # rl_bayern hat die api_id "83" (RCode/league_registry.R) -- fest verdrahtet
  # statt aus der Registry abgeleitet, damit der Test unabhaengig von ihr lesbar
  # bleibt.
  FEHLER_LIGA_ID <- "83"

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (identical(league, FEHLER_LIGA_ID)) {
      return(NULL) # nur DIESE Liga scheitert
    }
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(..., ergebnisse) {
    generated <<- generated + 1L
    seen_ergebnisse <<- ergebnisse
    invisible(character(0))
  })

  msgs <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  }))

  # Die neun anderen Ligen werden trotzdem gerendert.
  expect_equal(generated, 1L)
  expect_true("bundesliga" %in% names(seen_ergebnisse))
  # rl_bayern hat noch nie erfolgreich simuliert (Loop 1) -- ihr Schluessel
  # fehlt, statt mit erfundenen Daten aufzutauchen.
  expect_false("rl_bayern" %in% names(seen_ergebnisse))
  # Der Grund steht im Log, mit Ligabezug.
  expect_true(any(grepl("rl_bayern", msgs, fixed = TRUE)))
})

test_that("ein transform_data()-Fehler in einer Liga bricht den Loop nicht ab", {
  generated <- 0L
  seen_ergebnisse <- NULL

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) fake_fixtures(c("FT", "NS")))
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  # transform_data() wird je Liga einmal aufgerufen, in Registry-Reihenfolge
  # (bundesliga zuerst). Der dritte Aufruf gehoert zu dritte_liga -- dort
  # wirft der Stub, alle anderen liefern normal.
  call_count <- 0L
  stub(update_all_leagues_loop, "transform_data", function(fixtures, TeamList) {
    call_count <<- call_count + 1L
    if (call_count == 3L) {
      stop("simulierter transform_data()-Fehler")
    }
    fake_transformed()
  })
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(..., ergebnisse) {
    generated <<- generated + 1L
    seen_ergebnisse <<- ergebnisse
    invisible(character(0))
  })

  msgs <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  }))

  expect_equal(generated, 1L)
  # dritte_liga ist die dritte Liga in Registry-Reihenfolge (s. n_ligen()-
  # Kommentar oben zur Fetch-Reihenfolge als Vertrag).
  expect_false("dritte_liga" %in% names(seen_ergebnisse))
  expect_true("bundesliga" %in% names(seen_ergebnisse))
  expect_true("zweite_bundesliga" %in% names(seen_ergebnisse))
  expect_true(any(grepl("dritte_liga", msgs, fixed = TRUE)))
})

test_that("ein leagueSimulatorRust()-Fehler in einer Liga bricht den Loop nicht ab", {
  generated <- 0L
  seen_ergebnisse <- NULL

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) fake_fixtures(c("FT", "NS")))
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  # Simulationsaufrufe (leagueSimulatorRust) folgen ebenfalls der
  # Registry-Reihenfolge der liga_keys-Schleife; der zweite Aufruf gehoert
  # zu zweite_bundesliga.
  sim_call_count <- 0L
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    sim_call_count <<- sim_call_count + 1L
    if (sim_call_count == 2L) {
      stop("simulierter Rust-Fehler")
    }
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(..., ergebnisse) {
    generated <<- generated + 1L
    seen_ergebnisse <<- ergebnisse
    invisible(character(0))
  })

  msgs <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  }))

  expect_equal(generated, 1L)
  expect_false("zweite_bundesliga" %in% names(seen_ergebnisse))
  expect_true("bundesliga" %in% names(seen_ergebnisse))
  expect_true("dritte_liga" %in% names(seen_ergebnisse))
  expect_true(any(grepl("zweite_bundesliga", msgs, fixed = TRUE)))
})

test_that("ein per-Liga-Fehler behaelt die vorherige Prognose der betroffenen Liga", {
  # Loop 1 simuliert alle zehn Ligen erfolgreich. Loop 2 laesst
  # leagueSimulatorRust() fuer dritte_liga scheitern (neue beendete Spiele
  # loesen dort einen neuen Simulationsversuch aus) -- die ALTE Prognose aus
  # Loop 1 muss danach noch da sein, statt zu verschwinden.
  loop_num <- 0L
  seen_ergebnisse <- list()

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (loop_num == 0L) {
      fake_fixtures(c("FT", "NS"), ids = c(100L, 101L))
    } else {
      # dritte_liga bekommt ein neu beendetes Spiel -> neuer Sim-Versuch.
      fake_fixtures(c("FT", "FT"), ids = c(100L, 101L))
    }
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    loop_num <<- loop_num + 1L
    integer(0)
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  sim_call_count <- 0L
  # Vor with_repo_root() ausgewertet: n_ligen() sourced RCode/league_registry.R
  # relativ zu tests/testthat und darf das cwd des Loop-Aufrufs nicht sehen.
  ligen_pro_loop <- n_ligen()
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    sim_call_count <<- sim_call_count + 1L
    # Loop 2 (sim_call_count > ligen_pro_loop): dritte_liga ist dort der
    # dritte Aufruf.
    if (sim_call_count == ligen_pro_loop + 3L) {
      stop("simulierter Rust-Fehler in Loop 2")
    }
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(..., ergebnisse) {
    seen_ergebnisse[[length(seen_ergebnisse) + 1L]] <<- ergebnisse
    invisible(character(0))
  })

  # full_fetch_every = 1: Loop 2 ist damit IMMER ein faelliger Safety-Fetch,
  # unabhaengig vom (hier durchgehend leeren) Live-Poll -- sonst wuerde die
  # idle-Erkennung den Vollabruf in Loop 2 gar nicht erst ausloesen.
  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 2, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 1
    )
  })

  expect_equal(length(seen_ergebnisse), 2L)
  # Nach Loop 2 ist dritte_liga trotz Fehlschlag noch die ALTE Matrix aus
  # Loop 1 -- kein NULL, kein Verschwinden.
  expect_true("dritte_liga" %in% names(seen_ergebnisse[[2]]))
  expect_identical(seen_ergebnisse[[2]][["dritte_liga"]],
                   seen_ergebnisse[[1]][["dritte_liga"]])
})

# --- Issue #224: ein GEWORFENER Fehler (DNS, Timeout, Connection refused) --
#
# Der Vorfall vom 14.09.: Ein 16-Sekunden-DNS-Ausfall liess retrieveResults()
# und den Live-Poll "Resolving timed out" werfen. Die Isolation aus #208 fing
# nur ein NULL-Rueckgabewert ab -- ein GEWORFENER Fehler war auf dem
# Produktivpfad ungefangen und riss updateScheduler.R mit (quit(status = 1)).
# Diese Tests pinnen: ein throw() an EINER Liga verhaelt sich wie ein NULL
# (Liga geloggt mit dem Grund, die anderen neun laufen weiter, kein
# Prozessabbruch); ein throw() im Live-Poll wird wie ein NULL behandelt --
# "kein Live-Wissen diese Runde", Rueckfall auf die Safety-Net-Logik.

test_that("ein geworfener Fehler aus retrieveResults() fuer eine Liga blockiert die anderen neun nicht (issue #224)", {
  generated <- 0L
  seen_ergebnisse <- NULL
  FEHLER_LIGA_ID <- "83" # rl_bayern

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (identical(league, FEHLER_LIGA_ID)) {
      stop("Resolving timed out after 10000 ms") # DNS-Ausfall, kein NULL-Rueckgabewert
    }
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(..., ergebnisse) {
    generated <<- generated + 1L
    seen_ergebnisse <<- ergebnisse
    invisible(character(0))
  })

  msgs <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  }))

  # Der Loop ueberlebt (kein Prozessabbruch) und rendert die neun anderen.
  expect_equal(generated, 1L)
  expect_true("bundesliga" %in% names(seen_ergebnisse))
  expect_false("rl_bayern" %in% names(seen_ergebnisse))
  # Liga UND Grund stehen im Log.
  expect_true(any(grepl("rl_bayern", msgs, fixed = TRUE)))
  expect_true(any(grepl("Resolving timed out", msgs, fixed = TRUE)))
})

test_that("ein geworfener Fehler aus retrieveLiveFixtures() bricht den Loop nicht ab (issue #224)", {
  generated <- 0L

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) fake_fixtures(c("FT", "NS")))
  # Loop 1 ruft retrieveLiveFixtures() nicht auf (i > 1 Gate); erst Loop 2.
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    stop("Resolving timed out after 10000 ms")
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) matrix(1 / 18, nrow = 18, ncol = 18))
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    generated <<- generated + 1L
    invisible(character(0))
  })

  msgs <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 2, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  }))

  # Loop 2 ueberlebt den geworfenen Fehler und faellt auf den Vollabruf
  # zurueck (wie bei einem NULL-Rueckgabewert: "live poll failed").
  expect_true(any(grepl("live poll failed", msgs, fixed = TRUE)) ||
                any(grepl("Resolving timed out", msgs, fixed = TRUE)))
  expect_gte(generated, 1L) # mindestens Loop 1 hat gerendert
})
