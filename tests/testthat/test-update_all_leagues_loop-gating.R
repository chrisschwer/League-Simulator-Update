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
      static_site_dir = tempdir()
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
      static_site_dir = tempdir()
    )
  })

  # Loop 1 always fetches; loops 2-3 both hit the NULL live poll -> full fetch every time.
  expect_length(full_fetch_leagues, 3 * n_ligen())
  expect_equal(live_poll_count, 2) # loops 2-3
})

test_that("the safety net forces a periodic full fetch even when idle", {
  full_fetch_leagues <- character()
  live_poll_count <- 0
  uhr <- runden_uhr(takt = 120) # Runde k steht auf (k - 1) * 120 s

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    full_fetch_leagues <<- c(full_fetch_leagues, league)
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    uhr$weiter()
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
      static_site_dir = tempdir(),
      full_fetch_mindestens_alle = 3 * 120, jetzt = uhr$jetzt
    )
  })

  # Loop 1 (0 s): full fetch (first iteration). Loop 2 (120 s): idle -> skip.
  # Loop 3: 240 s < 360 s -> skip. Loop 4: 360 s >= 360 s -> safety-net full fetch.
  # -> 2 full fetches x 3 leagues = 6 retrieveResults calls
  expect_length(full_fetch_leagues, 2 * n_ligen())
  expect_equal(live_poll_count, 3) # loops 2-4
})

# --- Der Safety-Timer haengt am ERFOLG des Fetches (Issue #128, Punkt 1) ---
#
# Das Sicherheitsnetz (full_fetch_mindestens_alle) existiert fuer den Fall, dass die
# Flanken-Erkennung etwas verpasst. Wird sein Zaehler schon beim VERSUCH
# zurueckgesetzt statt beim Erfolg, ist es genau dann abgeschaltet, wenn es
# gebraucht wird: waehrend die API klemmt. Mit dem Default von einer Stunde
# verzoegert das den naechsten Versuch um bis zu eine Stunde.
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

# Ein Durchlauf von fuenf durchgehend leeren Runden im Abstand von 120 s mit
# einem Netz-Intervall von 3 * 120 s.
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
  uhr <- runden_uhr(takt = 120)

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
    uhr$weiter()
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
      static_site_dir = tempdir(),
      full_fetch_mindestens_alle = 3 * 120, jetzt = uhr$jetzt
    )
  })

  fetch_loops
}

test_that("ein fehlgeschlagener Safety-Fetch setzt den Timer NICHT zurueck", {
  # Runden im Abstand 120 s, Netz 360 s. Loop 1 (0 s): Vollabruf ohne
  # Poll, gelingt -> Timer auf 0 s. Loops 2, 3 (120/240 s): idle, < 360 s
  # -> kein Abruf. Loop 4 (360 s): faellig -> Abruf, schlaegt fehl.
  # Loop 5 (480 s): Der Timer darf noch auf 0 s stehen, also 480 >= 360
  # -> erneuter Versuch. Mit dem Fehler stuende er auf 360 s (120 < 360)
  # und Loop 5 bliebe still.
  expect_identical(lauf_mit_safety_fetch(fetch_faellt_aus = TRUE), c(1L, 4L, 5L))
})

test_that("ein erfolgreicher Safety-Fetch setzt den Timer sehr wohl zurueck", {
  # Gegenprobe: Der Fix darf den Timer nicht abschaffen, sondern nur an den
  # Erfolg binden. Gelingt Loop 4, steht der Timer auf 360 s und Loop 5
  # bleibt still (480 - 360 = 120 < 360).
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
      static_site_dir = tempdir()
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
      static_site_dir = target
    )
  })
  expect_equal(seen_dir, target)
})

# --- Issue #154: a fixture leaving the live feed must stay "pending" until
# --- the season endpoint actually shows it as finished. The season fetch
# --- triggered by the live-feed edge can lag the live feed by seconds
# --- (observed 2026-08-29, BVB-HSV): the old one-shot edge consumed the
# --- trigger on a stale fetch and the finished game stayed in the Ausblick
# --- until the next safety-net fetch.

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
      static_site_dir = tempdir()
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
  uhr <- runden_uhr(takt = 120)
  stub(update_all_leagues_loop, "retrieveLiveFixtures",
       uhr$tick(function(...) integer(0)))
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
      static_site_dir = tempdir(),
      full_fetch_mindestens_alle = 2 * 120, jetzt = uhr$jetzt
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
  uhr <- runden_uhr(takt = 120)
  stub(update_all_leagues_loop, "retrieveLiveFixtures",
       uhr$tick(function(...) integer(0)))
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
      static_site_dir = tempdir(),
      full_fetch_mindestens_alle = 2 * 120, jetzt = uhr$jetzt
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
      static_site_dir = tempdir()
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
      static_site_dir = tempdir()
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
      static_site_dir = tempdir()
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
      static_site_dir = tempdir()
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
      static_site_dir = tempdir()
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
      static_site_dir = tempdir()
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
      static_site_dir = tempdir()
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
  uhr <- runden_uhr(takt = 120)
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    uhr$weiter()
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

  # Netz-Intervall = ein Rundenabstand (120 s): Loop 2 ist damit IMMER ein
  # faelliger Safety-Fetch, unabhaengig vom (hier durchgehend leeren)
  # Live-Poll -- sonst wuerde die idle-Erkennung den Vollabruf in Loop 2 gar
  # nicht erst ausloesen.
  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 2, initial_wait = 0, n = 10,
      saison = "2024", TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(),
      full_fetch_mindestens_alle = 120, jetzt = uhr$jetzt
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
      static_site_dir = tempdir()
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
      static_site_dir = tempdir()
    )
  }))

  # Loop 2 ueberlebt den geworfenen Fehler und faellt auf den Vollabruf
  # zurueck (wie bei einem NULL-Rueckgabewert: "live poll failed").
  expect_true(any(grepl("live poll failed", msgs, fixed = TRUE)) ||
                any(grepl("Resolving timed out", msgs, fixed = TRUE)))
  expect_gte(generated, 1L) # mindestens Loop 1 hat gerendert
})


# ===========================================================================
# Der Zweitvertretungs-Malus kommt aus der Spalte Promotion (Issue #206/#196)
# ===========================================================================
#
# Bis hierher vergab der Loop die -50 am ENDZEICHEN "2" des Kuerzels. Die
# Spalte Promotion, die genau diese Information traegt und die Christoph von
# Hand pflegt (ADR 0007), las im Produktivpfad niemand.
#
# Beide Richtungen sind falsch:
#   HO2A, HA2B  tragen Promotion = -50, enden aber auf einen Buchstaben --
#               und standen ohne Malus in der Aufstiegstabelle. Der
#               Mechanismus waechst mit: assign_short_names() weicht bei
#               Kollisionen bewusst auf Buchstaben aus.
#   ein Kuerzel auf "2" ohne gepflegten Malus bekaeme ihn umgekehrt zu
#               Unrecht.
#
# Der Test faehrt genau diese zwei Faelle in einer Liga, die laut Registry
# aufstiegsbeschraenkt ist und deshalb einen Malus-Lauf bekommt.

# Liga 80 (3. Liga) -- has_promotion_restriction() ist dort TRUE.
MALUS_LIGA <- "80"
# HOZA endet NICHT auf "2", traegt aber den gepflegten Malus (der Fall HO2A
# / HA2B). TST2 endet auf "2", ist aber laut Spalte keine Zweitvertretung.
MALUS_TEAMS <- c("HOZA", "TST2", "AAA", "BBB")
MALUS_PROMOTION <- c(-50, 0, 0, 0)

# TeamList mit den beiden Grenzfaellen in Liga 80. Die uebrigen aktiven
# Ligen bekommen Fuellzeilen, damit load_team_list() traegt.
malus_teamlist_datei <- function() {
  env <- new.env()
  source(file.path("..", "..", "RCode", "league_registry.R"), local = env)
  reg <- env$league_registry()

  zeilen <- list()
  id <- 0L
  for (key in names(reg)) {
    eintrag <- reg[[key]]
    if (!isTRUE(eintrag$active)) next
    ist_malus_liga <- identical(as.character(eintrag$api_id), MALUS_LIGA)
    kurz <- if (ist_malus_liga) {
      MALUS_TEAMS
    } else {
      sprintf("L%s%02d", substr(eintrag$api_id, 1, 2), 1:4)
    }
    prom <- if (ist_malus_liga) MALUS_PROMOTION else rep(0, 4)
    zeilen[[length(zeilen) + 1L]] <- data.frame(
      TeamID = id + seq_along(kurz),
      ShortText = kurz,
      Promotion = prom,
      InitialELO = 1500,
      League = eintrag$api_id,
      Region = "",
      Name = paste("Verein", kurz),
      stringsAsFactors = FALSE
    )
    id <- id + 100L
  }
  df <- do.call(rbind, zeilen)
  pfad <- tempfile("TeamList_malus_", fileext = ".csv")
  utils::write.table(df, pfad, sep = ";", quote = FALSE, row.names = FALSE)
  pfad
}

test_that("der Malus folgt der Spalte Promotion, nicht dem Kuerzel-Suffix", {
  teamlist <- malus_teamlist_datei()
  tl <- utils::read.csv(teamlist, sep = ";", stringsAsFactors = FALSE)
  gesehen <- list()

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  # Jede Liga bekommt DENSELBEN Spielplan -- den der Malus-Liga. Der Loop
  # ruft transform_data() je Liga auf, ohne die ID mitzugeben; entscheidend
  # ist allein, dass die Malus-Liga ihren eigenen Spielplan sieht.
  #
  # Die Teamspalten stehen in UMGEKEHRTER TeamList-Reihenfolge: Eine
  # Zuordnung nach Position statt nach Kurzname ergaebe einen anderen
  # Vektor und faellt hier auf.
  stub(update_all_leagues_loop, "transform_data", function(fixtures, teams) {
    kurz <- rev(teams$ShortText[as.character(teams$League) == MALUS_LIGA])
    df <- data.frame(
      TeamHeim = kurz[1], TeamGast = kurz[2], ToreHeim = 1, ToreGast = 0,
      stringsAsFactors = FALSE
    )
    for (k in kurz) df[[k]] <- 1500
    df
  })
  stub(update_all_leagues_loop, "leagueSimulatorRust",
       function(spielplan, n, adjPoints = NULL, ...) {
         if (!is.null(adjPoints)) {
           gesehen[[length(gesehen) + 1L]] <<- stats::setNames(
             as.numeric(adjPoints), names(spielplan)[5:ncol(spielplan)]
           )
         }
         m <- matrix(1 / length(MALUS_TEAMS),
                     nrow = length(MALUS_TEAMS), ncol = length(MALUS_TEAMS))
         rownames(m) <- names(spielplan)[5:ncol(spielplan)]
         m
       })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10,
      saison = "2026", TeamList_file = teamlist,
      static_site_dir = tempdir()
    )
  })

  expect_gt(length(gesehen), 0)
  adj <- gesehen[[1]]

  expect_identical(adj[["HOZA"]], -50,
                   info = "HO2A-Fall: gepflegter Malus ohne '2' am Ende")
  expect_identical(adj[["TST2"]], 0,
                   info = "'2'-Suffix ohne gepflegten Malus bleibt ohne Abzug")
  expect_identical(adj[["AAA"]], 0)
  expect_identical(adj[["BBB"]], 0)
})

test_that("ein Team ohne Zeile in der TeamList bekommt keinen erfundenen Malus", {
  # Die Zuordnung geht ueber den Kurznamen. Findet sie ein Team nicht --
  # eine unvollstaendige TeamList --, bleibt der Abzug 0, statt dass NA in
  # die Payload laeuft und die Engine still etwas anderes rechnet.
  teamlist <- malus_teamlist_datei()
  gesehen <- list()

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(fixtures, teams) {
    kurz <- c(MALUS_TEAMS, "XXX")
    df <- data.frame(
      TeamHeim = kurz[1], TeamGast = kurz[2], ToreHeim = 1, ToreGast = 0,
      stringsAsFactors = FALSE
    )
    for (k in kurz) df[[k]] <- 1500
    df
  })
  stub(update_all_leagues_loop, "leagueSimulatorRust",
       function(spielplan, n, adjPoints = NULL, ...) {
         if (!is.null(adjPoints)) {
           gesehen[[length(gesehen) + 1L]] <<- stats::setNames(
             as.numeric(adjPoints), names(spielplan)[5:ncol(spielplan)]
           )
         }
         n_t <- ncol(spielplan) - 4L
         m <- matrix(1 / n_t, nrow = n_t, ncol = n_t)
         rownames(m) <- names(spielplan)[5:ncol(spielplan)]
         m
       })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10,
      saison = "2026", TeamList_file = teamlist,
      static_site_dir = tempdir()
    )
  })

  adj <- gesehen[[1]]
  expect_false(anyNA(adj))
  expect_identical(adj[["XXX"]], 0)
})

# --- Issues 190 und 204: die Wartezeit gehoert JEDER Runde, und sie folgt
# --- dem echten Restkontingent statt einem beim Start eingefrorenen Plan.
#
# Bis hierher berechnete der Loop `waittime <- duration * 60 / (loops - 1)`
# einmal und schlief damit am Ende jeder Runde -- ausser im Fehlerpfad, wo
# ein `next` an der einzigen Sys.sleep()-Stelle vorbeisprang (#204). Die
# Header des Providers, die nach jedem Request ein taufrisches `remaining`
# liefern, las niemand (#190).
#
# Alle bisherigen Gating-Tests laufen mit `duration = 0` und damit
# waittime = 0; ob ueberhaupt geschlafen wird, war dort nicht beobachtbar.
# Die folgenden Tests arbeiten deshalb mit `duration > 0` und einem
# gestubbten Sys.sleep, das seine Argumente aufzeichnet.

# Ein Lauf mit aufgezeichneten Schlafzeiten. `rest_folge` gibt je Loop das
# `remaining` vor, das der Regler zu sehen bekommt; `fetch_ok = FALSE`
# laesst jeden Vollabruf fehlschlagen (der Fehlerpfad aus #204).
lauf_mit_schlafzeiten <- function(loops, duration, rest_folge = NULL,
                                  fetch_ok = TRUE, limit = 7500,
                                  live = "live") {
  schlaf <- numeric(0)
  abrufe <- 0L
  runde <- new.env(parent = emptyenv())
  runde$i <- 0L
  # Gefaelschte Uhr: Sys.sleep schlaeft hier nicht, also muss die Zeit
  # anderweitig vorruecken. Ohne das stuende die Uhr still, waehrend der
  # Loop Wartezeiten aufaddiert -- das Fenster-Ende (Issue #224) saehe
  # dann 600 Sekunden Wartezeit gegen eine eingefrorene Uhr und beendete
  # den Lauf sofort. In Produktion rueckt die Uhr mit dem Schlafen vor;
  # der Stub muss das nachbilden, sonst prueft der Test eine Lage, die es
  # nicht gibt.
  uhr <- new.env(parent = emptyenv())
  uhr$jetzt <- as.POSIXct("2026-09-13 11:00:00", tz = "UTC")

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "Sys.time", function() uhr$jetzt)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") abrufe <<- abrufe + 1L
    if (!fetch_ok) {
      return(NULL)
    }
    fake_fixtures(c("FT", "2H"), ids = c(100L, 101L))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    if (identical(live, "live")) c(101L) else integer(0)
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))
  stub(update_all_leagues_loop, "Sys.sleep", function(sekunden) {
    # initial_wait = 0 laeuft ebenfalls durch Sys.sleep und wird hier
    # ausgefiltert: Gezaehlt werden die Rundenpausen, nicht der Vorlauf.
    if (sekunden > 0) schlaf <<- c(schlaf, sekunden)
    uhr$jetzt <- uhr$jetzt + sekunden
    invisible(NULL)
  })
  # Der Loop liest den Kontingent-Stand ueber genau diesen Getter; ihn zu
  # stubben ersetzt HTTP, ohne die Rechnung im Loop zu umgehen.
  stub(update_all_leagues_loop, "api_rate_limit_stand", function() {
    runde$i <- runde$i + 1L
    rest <- if (is.null(rest_folge)) {
      NA_real_
    } else {
      rest_folge[[min(runde$i, length(rest_folge))]]
    }
    list(
      remaining = rest,
      limit = if (is.na(rest)) NA_real_ else limit,
      reset_seconds = if (is.na(rest)) NA_real_ else 8 * 3600,
      as_of = Sys.time()
    )
  })

  meldungen <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = duration, loops = loops, initial_wait = 0, n = 10,
      saison = "2024",
      TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir()
    )
  }))

  list(schlaf = schlaf, meldungen = meldungen, abrufe = abrufe)
}

test_that("ein fehlgeschlagener Vollabruf wartet trotzdem (issue #204)", {
  # Der Kern von #204: Schlaegt eine Liga fehl, sprang die Schleife per
  # `next` an der Wartezeit vorbei und feuerte sofort die naechste Runde --
  # 11 Requests je Runde ohne Pause, das Tageskontingent in rund zwei
  # Stunden verbrannt. Jede Runde muss warten, auch die gescheiterte.
  lauf <- lauf_mit_schlafzeiten(loops = 5, duration = 10, fetch_ok = FALSE)

  # Jede Runde ausser der ersten wartet genau einmal (initial_wait = 0
  # zaehlt hier nicht mit, weil der Loop bei 0 nicht schlaeft).
  expect_length(lauf$schlaf, 4L)
  expect_true(all(lauf$schlaf > 0))
  # Und der Fehlerpfad wurde wirklich genommen.
  expect_true(any(grepl("API calls failed", lauf$meldungen)))
})

test_that("auch der Leerlaufpfad wartet jede Runde", {
  # Gegenprobe zum Test oben: Der Fix darf nicht nur den Fehlerpfad
  # abdecken. Idle-Runden (kein Vollabruf) warten genauso.
  lauf <- lauf_mit_schlafzeiten(loops = 5, duration = 10, live = "idle")

  expect_length(lauf$schlaf, 4L)
  expect_true(all(lauf$schlaf > 0))
})

test_that("sinkendes Restkontingent streckt die Wartezeiten (issue #190)", {
  # Stufe 2: Ab Loop 2 liegen frische Header vor. Faellt `remaining` in den
  # Keller, muss der Takt sich strecken -- ohne dass jemand den Prozess neu
  # startet. Vorher war die Wartezeit fuer den Rest des Tages eingefroren.
  # Die Zahlen sind so gewaehlt, dass der Engpass echt ist: Ab Runde 4
  # traegt das Restbudget (20 Requests, 0,9 Sicherheitsabschlag, 11
  # Requests je Runde -> eine Runde) die noch geplanten Runden nicht mehr.
  # Vorher (7.400) ist es komfortabel.
  #
  # Rundenzahl und Fenster ergeben zusammen den Normaltakt von zwei Minuten
  # (361 Runden auf 720 Minuten -- der echte Tagesplan). Das ist seit Issue
  # #224 noetig, damit der Test misst, was er messen will: Bei einem sehr
  # duennen Plan laege der Ausgangstakt bereits an der Obergrenze, und die
  # Drosselung haette keinen Weg mehr nach oben. Und die ZEIT begrenzt den
  # Lauf jetzt -- mit den urspruenglichen zehn Minuten Fenster haette die
  # Drosselung ihn nach zwei Runden beendet.
  lauf <- lauf_mit_schlafzeiten(
    loops = 361, duration = 12 * 60,
    rest_folge = c(7400, 7400, 7400, 20, 20, 20)
  )

  # Mindestens die vier Runden, in denen sich das Restbudget aendert; der
  # Lauf endet danach am Fensterende, sobald die Drosselung greift.
  expect_gte(length(lauf$schlaf), 4L)
  # Die Runden mit knappem Budget warten laenger als die mit komfortablem.
  # Die Runden 2 und 3 sehen noch 7.400 Requests, Runde 4 dann 20.
  expect_gt(max(lauf$schlaf), min(lauf$schlaf))
  expect_gt(lauf$schlaf[3], lauf$schlaf[1])
  # Und es wird als Drosselung benannt, nicht still getan.
  expect_true(any(grepl("Takt", lauf$meldungen)))
})

test_that("der Loop schreibt je Runde eine Budget-Zeile (issue #190, Stufe 1)", {
  # Stufe 1: Heute existiert genau eine Rate-Limit-Zeile je PROZESSSTART
  # (checkAPILimits). Der Tagesverlauf ist im Log nicht nachvollziehbar.
  lauf <- lauf_mit_schlafzeiten(
    loops = 4, duration = 10,
    rest_folge = c(NA_real_, 7000, 6900, 6800)
  )

  # Eine Zeile je Runde, ohne Ausnahme -- auch Loop 1, der noch keine
  # Header gesehen hat. Dort sagt sie genau das, statt "NA/NA verbraucht"
  # zu melden, als waere das eine Messung.
  budget_zeilen <- grep("Loop \\d+/4: API", lauf$meldungen, value = TRUE)
  expect_length(budget_zeilen, 4L)
  expect_length(grep("verbleibend", budget_zeilen), 3L)
  expect_length(grep("noch unbekannt", budget_zeilen), 1L)
  expect_true(any(grepl("Reset in", budget_zeilen)))
})

test_that("ein gefallenes Limit wird als Plan-Herabstufung gewarnt (issue #190, Stufe 3)", {
  # Der Fall aus der Ueberschrift von #190: Nicht `remaining` faellt, das
  # `limit` selbst sinkt. Heute bliebe das voellig unbemerkt.
  schlaf <- numeric(0)
  runde <- new.env(parent = emptyenv())
  runde$i <- 0L
  limits <- c(7500, 7500, 100, 100)

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(...) {
    fake_fixtures(c("FT", "2H"), ids = c(100L, 101L))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) c(101L))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))
  stub(update_all_leagues_loop, "Sys.sleep", function(s) {
    schlaf <<- c(schlaf, s)
    invisible(NULL)
  })
  stub(update_all_leagues_loop, "api_rate_limit_stand", function() {
    runde$i <- runde$i + 1L
    l <- limits[[min(runde$i, length(limits))]]
    list(
      remaining = l - 10, limit = l,
      reset_seconds = 8 * 3600, as_of = Sys.time()
    )
  })

  meldungen <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = 10, loops = 4, initial_wait = 0, n = 10,
      saison = "2024",
      TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir()
    )
  }))

  expect_true(any(grepl("WARNUNG", meldungen)))
  expect_true(any(grepl("7\\.500", meldungen)))
  expect_true(any(grepl("Limit", meldungen)))
})


# --- Das Zeitfenster schlaegt die Rundenzahl ---------------------------
#
# Bis hierher endete der Loop AUSSCHLIESSLICH daran, dass `seq_len(loops)`
# erschoepft war -- eine Uhr kam in ihm nicht vor. Solange die Wartezeit
# fest bei `duration * 60 / (loops - 1)` stand, war das auch richtig: Die
# Rundenzahl war so gewaehlt, dass sie das Fenster genau ausfuellte.
#
# Mit dem nachgefuehrten Takt stimmt diese Rechnung nicht mehr. Der
# Scheduler plant 361 Runden a 2 Minuten; streckt der Regler auf 90
# Minuten (der freie Plan, s. test-rate-limit-takt.R), liefen dieselben 361
# Runden ueber drei Wochen statt bis 23:00. Ohne diese Abbruchbedingung
# waere die Drosselung also nicht Budgetschonung, sondern eine Verschiebung
# des Verbrauchs in die Folgetage.

# Ein Lauf mit gefaelschter Uhr: `Sys.sleep` schlaeft nicht, sondern stellt
# die Uhr vor. So laesst sich ein Zwoelf-Stunden-Fenster in Millisekunden
# durchlaufen, und der Abbruch wird an der Zeit beobachtbar statt am
# Wanduhr-Warten.
lauf_mit_falscher_uhr <- function(loops, duration, waittime_sekunden) {
  uhr <- new.env(parent = emptyenv())
  uhr$jetzt <- as.POSIXct("2026-09-13 11:00:00", tz = "UTC")
  runden <- 0L

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") runden <<- runden + 1L
    fake_fixtures(c("FT", "2H"), ids = c(100L, 101L))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) c(101L))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))
  stub(update_all_leagues_loop, "Sys.time", function() uhr$jetzt)
  stub(update_all_leagues_loop, "Sys.sleep", function(sekunden) {
    uhr$jetzt <- uhr$jetzt + sekunden
    invisible(NULL)
  })
  # Ein Kontingent, das den Regler auf `waittime_sekunden` streckt: Das
  # Budget traegt genau die Runden, die in das Fenster passen sollen.
  stub(update_all_leagues_loop, "api_rate_limit_stand", function() {
    list(remaining = 100, limit = 100,
         reset_seconds = 24 * 3600, as_of = uhr$jetzt)
  })

  meldungen <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = duration, loops = loops, initial_wait = 0, n = 10,
      saison = "2024",
      TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir()
    )
  }))

  list(runden = runden, meldungen = meldungen, ende = uhr$jetzt)
}

test_that("der Loop endet am Fenster-Ende, nicht erst nach `loops` Runden", {
  # 361 geplante Runden, aber nur ein Fenster von 12 Stunden, und ein
  # Kontingent (100 Requests, 11 je Runde), das den Takt auf 90 Minuten
  # streckt. In 12 Stunden passen so hoechstens acht Wartezeiten.
  #
  # Ohne die Abbruchbedingung liefe dieser Test 361 Runden lang und die
  # gefaelschte Uhr stuende am Ende rund drei Wochen spaeter.
  lauf <- lauf_mit_falscher_uhr(loops = 361, duration = 12 * 60,
                                waittime_sekunden = 5400)

  expect_lt(lauf$runden, 361L)
  expect_lte(as.numeric(difftime(lauf$ende,
                                 as.POSIXct("2026-09-13 11:00:00", tz = "UTC"),
                                 units = "mins")), 12 * 60)
  expect_true(any(grepl("Zeitfenster", lauf$meldungen)))
})

test_that("ein Lauf, der ins Fenster passt, laeuft alle Runden durch", {
  # Gegenprobe: Die Abbruchbedingung darf keinen Lauf verkuerzen, der das
  # Fenster gar nicht ueberschreitet. Ohne sie liesse sich der Test oben
  # erfuellen, indem man nach der ersten Runde immer abbricht.
  #
  # Drei Runden, Fenster 12 Stunden: Selbst bei 90 Minuten Wartezeit sind
  # das hoechstens drei Stunden.
  lauf <- lauf_mit_falscher_uhr(loops = 3, duration = 12 * 60,
                                waittime_sekunden = 5400)

  expect_equal(lauf$runden, 3L)
  expect_false(any(grepl("Zeitfenster", lauf$meldungen)))
})


# --- Erschoepftes Kontingent: die Runde ruft gar nichts ab --------------
#
# Die Drosselung streckt den Takt, verbraucht aber weiter. Ist das
# Kontingent fast leer, gehen die letzten Requests fuer einzelne Runden
# drauf, statt fuer das, was nach dem Reset kommt. Unterhalb der
# Stopp-Grenze setzt der Loop die Runde deshalb ganz aus -- weder Live-Poll
# noch Vollabruf -- und wartet den Reset ab.
#
# Beobachtbar ist das an genau zwei Dingen: der Zahl der API-Aufrufe in
# dieser Runde (null) und der Laenge des Schlafs (die Reset-Frist, gekappt
# am Fenster-Ende).

# Ein Lauf mit gefaelschter Uhr, gezaehlten API-Aufrufen je Runde und
# einem Kontingent-Stand, den der Test je Runde vorgibt.
lauf_mit_kontingent <- function(loops, duration, stand_folge,
                                start = "2026-09-13 11:00:00",
                                plan_reduziert = FALSE) {
  uhr <- new.env(parent = emptyenv())
  uhr$jetzt <- as.POSIXct(start, tz = "UTC")
  runde <- new.env(parent = emptyenv())
  runde$i <- 0L
  polls <- integer(0)
  fetches <- integer(0)
  schlaf <- numeric(0)

  # Welche Runde gerade laeuft, leitet sich aus der Zahl der
  # Stand-Abfragen ab: api_rate_limit_stand() laeuft genau einmal je Runde
  # und als Erstes.
  aktuelle_runde <- function() runde$i

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") fetches <<- c(fetches, aktuelle_runde())
    fake_fixtures(c("FT", "2H"), ids = c(100L, 101L))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) {
    polls <<- c(polls, aktuelle_runde())
    c(101L)
  })
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))
  stub(update_all_leagues_loop, "Sys.time", function() uhr$jetzt)
  stub(update_all_leagues_loop, "Sys.sleep", function(sekunden) {
    if (sekunden > 0) schlaf <<- c(schlaf, sekunden)
    uhr$jetzt <- uhr$jetzt + sekunden
    invisible(NULL)
  })
  stub(update_all_leagues_loop, "api_rate_limit_stand", function() {
    runde$i <- runde$i + 1L
    s <- stand_folge[[min(runde$i, length(stand_folge))]]
    list(remaining = s$remaining, limit = s$limit,
         reset_seconds = s$reset, as_of = uhr$jetzt)
  })

  meldungen <- capture_messages(with_repo_root({
    update_all_leagues_loop(
      duration = duration, loops = loops, initial_wait = 0, n = 10,
      saison = "2024",
      TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(),
      plan_reduziert = plan_reduziert
    )
  }))

  list(polls = polls, fetches = fetches, schlaf = schlaf,
       meldungen = meldungen, ende = uhr$jetzt)
}

test_that("bei erschoepftem Kontingent ruft die Runde nichts ab und wartet den Reset ab", {
  # Runde 1 ruft ab (voller Stand). Runde 2 sieht 5 Restrequests -- unter
  # der Grenze von 10 -- und darf deshalb NICHTS abrufen, sondern wartet
  # die 30 Minuten bis zum Reset. Runde 3 sieht wieder 100 und ruft ab.
  #
  # Ohne den Stopp kostete Runde 2 einen Live-Poll plus zehn Vollabrufe --
  # 11 Requests, die das Kontingent nicht mehr hergibt.
  lauf <- lauf_mit_kontingent(
    loops = 3, duration = 12 * 60,
    stand_folge = list(
      list(remaining = 7000, limit = 7500, reset = 8 * 3600),
      list(remaining = 5, limit = 7500, reset = 30 * 60),
      list(remaining = 100, limit = 7500, reset = 8 * 3600)
    )
  )

  # Runde 2 taucht weder bei den Polls noch bei den Abrufen auf.
  expect_false(2L %in% lauf$polls)
  expect_false(2L %in% lauf$fetches)
  # Runde 1 und 3 rufen sehr wohl ab (Runde 1 ohne Poll -- der erste Poll
  # gehoert zu Runde 2, die hier aber aussetzt).
  expect_true(1L %in% lauf$fetches)
  expect_true(3L %in% lauf$fetches)
  # Genau ein Schlaf von 30 Minuten.
  expect_true(any(abs(lauf$schlaf - 30 * 60) < 1))
  # Und beides steht im Log: der Stopp und die Wiederaufnahme.
  expect_true(any(grepl("Kontingent erschoepft", lauf$meldungen)))
  expect_true(any(grepl("5/7\\.500", lauf$meldungen)))
  expect_true(any(grepl("fortgesetzt", lauf$meldungen)))
})

test_that("die Reset-Wartezeit wird am Fenster-Ende gekappt", {
  # Liegt der Reset (5 h) jenseits des Rests im Fenster (40 min), waere
  # Warten bis zum Reset ein Warten in den naechsten Tag hinein. Der Lauf
  # endet dann hier -- der Scheduler startet ohnehin zum naechsten Fenster.
  #
  # Gepruefte Zusicherung: Es wird HOECHSTENS bis zum Fenster-Ende
  # geschlafen, nie darueber hinaus.
  lauf <- lauf_mit_kontingent(
    loops = 10, duration = 40,
    stand_folge = list(
      list(remaining = 7000, limit = 7500, reset = 8 * 3600),
      list(remaining = 5, limit = 7500, reset = 5 * 3600)
    )
  )

  verstrichen <- as.numeric(difftime(lauf$ende,
                                     as.POSIXct("2026-09-13 11:00:00", tz = "UTC"),
                                     units = "mins"))
  expect_lte(verstrichen, 40)
  expect_true(all(lauf$schlaf <= 40 * 60))
  expect_true(any(grepl("Reset liegt hinter dem Zeitfenster", lauf$meldungen)))
  # Nach dem Abbruch darf keine weitere Runde abgerufen haben.
  expect_false(2L %in% lauf$fetches)
})



# --- Takt-Erholung nach reduziertem Tagesplan (Issue #224) --------------
#
# Der Vorfall vom 14.09.2026: Ein DNS-Ausfall liess die Probe in
# checkAPILimits() ins Timeout laufen, der konservative Fehlerpfad plante
# 9 Runden statt 361, und daraus wurde ein Takt von 83 Minuten -- fuer den
# REST DES TAGES, obwohl ab dem ersten erfolgreichen Request wieder 7.179
# freie Requests gemeldet wurden. Ein Frauen-Bundesliga-Spiel um 18:00
# fiel in die Luecke zwischen 18:51 und 20:15.
#
# Das konservative Verhalten bei UNBEKANNTEM Kontingent bleibt gewollt
# (Entscheidung Christoph): Wer nichts weiss, faehrt langsam. Aber sobald
# die Header da sind, muss der Loop auf den Normaltakt zurueck.
#
# Ausgeloest wird die Erholung durch ein EXPLIZITES Signal
# (`plan_reduziert`), nicht durch eine Heuristik ueber Taktverhaeltnisse:
# Ob 9 Runden eine Notbremse oder eine Ansage sind, sieht man der Zahl
# nicht an. checkAPILimits() weiss es und sagt es ueber
# api_limits_plan_reduziert(); calculate_loops() reicht es durch.

test_that("ein reduzierter Plan kehrt zum Normaltakt zurueck (issue #224)", {
  # Der Vorfall, nachgestellt: 9 geplante Runden auf 665 Minuten (der
  # 83-Minuten-Takt). Runde 1 sieht noch keine Header. Ab Runde 2 meldet
  # die API 7.000 freie Requests -- ab da muss der Takt 120 s sein.
  lauf <- lauf_mit_kontingent(
    loops = 9, duration = 665,
    plan_reduziert = TRUE,
    stand_folge = list(
      list(remaining = NA_real_, limit = NA_real_, reset = NA_real_),
      list(remaining = 7000, limit = 7500, reset = 8 * 3600)
    )
  )

  # Runde 1 wartet nicht (die Wartezeit steht am Kopf ab Runde 2), und
  # Runde 2 sieht bereits Header -- die erste beobachtbare Wartezeit ist
  # deshalb schon die erholte. Genau das ist der Punkt: Die Erholung
  # greift ab dem ERSTEN Moment, in dem gemessene Zahlen vorliegen, nicht
  # erst irgendwann danach.
  expect_true(length(lauf$schlaf) >= 2)
  expect_true(all(abs(lauf$schlaf - 120) < 1),
              info = paste(round(lauf$schlaf), collapse = ", "))
  # Und der Wechsel steht im Log.
  expect_true(any(grepl("zurueck auf Normaltakt", lauf$meldungen)))
})

test_that("der erholte Lauf endet an der Uhr, nicht nach 9 Runden", {
  # Der zweite Teil: Waere die Rundenzahl weiterhin die Grenze, endete der
  # Tag im Normaltakt nach 9 x 2 = 18 Minuten. Der Lauf muss das Fenster
  # ausschoepfen -- und genau dort aufhoeren.
  lauf <- lauf_mit_kontingent(
    loops = 9, duration = 665,
    plan_reduziert = TRUE,
    stand_folge = list(
      list(remaining = 7000, limit = 7500, reset = 8 * 3600)
    )
  )

  expect_gt(length(lauf$fetches), 9)
  verstrichen <- as.numeric(difftime(lauf$ende,
                                     as.POSIXct("2026-09-13 11:00:00", tz = "UTC"),
                                     units = "mins"))
  expect_lte(verstrichen, 665)
  expect_gt(verstrichen, 600) # das Fenster wird wirklich genutzt
})

test_that("bei unbekanntem Kontingent bleibt auch ein reduzierter Plan langsam", {
  # Die ausdrueckliche Entscheidung aus #224: Ohne Header wird NICHT auf
  # 120 s beschleunigt. Ein fehlender Header ist keine Meldung eines
  # vollen Kontingents.
  #
  # Ohne diesen Test liesse sich der erste erfuellen, indem man bei
  # `plan_reduziert` einfach immer 120 s nimmt -- und genau das waere der
  # 120-s-Fallback, den Christoph nicht will.
  lauf <- lauf_mit_kontingent(
    loops = 9, duration = 665,
    plan_reduziert = TRUE,
    stand_folge = list(
      list(remaining = NA_real_, limit = NA_real_, reset = NA_real_)
    )
  )

  expect_true(all(lauf$schlaf > 120 * 1.5),
              info = paste(round(lauf$schlaf), collapse = ", "))
})

test_that("ohne plan_reduziert bleibt die Rundenzahl die Ansage", {
  # Die Gegenprobe zum Signal: Derselbe Lauf OHNE das Flag verhaelt sich
  # wie bisher -- 9 Runden, konservativer Takt, keine Erholung. Ein
  # Aufrufer, der wenige Runden bestellt, bekommt wenige Runden.
  lauf <- lauf_mit_kontingent(
    loops = 9, duration = 665,
    plan_reduziert = FALSE,
    stand_folge = list(
      list(remaining = 7000, limit = 7500, reset = 8 * 3600)
    )
  )

  expect_lte(length(lauf$fetches), 9)
  expect_false(any(grepl("zurueck auf Normaltakt", lauf$meldungen)))
})

test_that("checkAPILimits meldet, ob die Planung aus einem Fallback kam", {
  # Die Quelle des Signals. Eine echte Messung ist keine Notbremse; ein
  # Probe-Fehler und ein fehlender Header sind es.
  env <- new.env()
  source(file.path("..", "..", "RCode", "league_registry.R"), local = env)
  source(file.path("..", "..", "RCode", "checkAPILimits.R"), local = env)

  alt <- Sys.getenv("RAPIDAPI_KEY", unset = NA)
  Sys.setenv(RAPIDAPI_KEY = "test-key")
  on.exit({
    if (is.na(alt)) Sys.unsetenv("RAPIDAPI_KEY") else Sys.setenv(RAPIDAPI_KEY = alt)
  }, add = TRUE)

  # Echte Messung -> kein Fallback.
  f_ok <- env$checkAPILimits
  stub(f_ok, "httr::GET", function(...) structure(list(), class = "response"))
  stub(f_ok, "httr::headers", function(response) {
    list(`x-ratelimit-requests-remaining` = "7000",
         `x-ratelimit-requests-limit` = "7500")
  })
  f_ok(360)
  expect_false(env$api_limits_plan_reduziert())

  # Probe im Timeout -> Fallback. Genau der Fall vom 14.09.
  f_err <- env$checkAPILimits
  stub(f_err, "httr::GET", function(...) stop("Resolving timed out after 10000 ms"))
  suppressWarnings(suppressMessages(f_err(360)))
  expect_true(env$api_limits_plan_reduziert())

  # Und eine erneute echte Messung setzt das Signal zurueck.
  f_ok(360)
  expect_false(env$api_limits_plan_reduziert())
})
