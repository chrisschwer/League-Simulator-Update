# Production simulation loop. Calls the Rust REST API exclusively
# (issue #77 Phase 1: no in-process C++ fallback).

# Digest of one league's render-relevant fixture fields. Rückblick, Live and
# Ausblick depend on fixture data (status, goals, kickoff), not only on
# simulation results, so any change here warrants a re-render even when no
# simulation ran (issue #154).
.fixtures_render_signature <- function(fixtures) {
  f <- fixtures$fixture
  n <- length(f$id)
  elapsed <- f$status$elapsed
  if (is.null(elapsed)) elapsed <- rep(NA, n)
  goals_home <- fixtures$goals$home
  if (is.null(goals_home)) goals_home <- rep(NA, n)
  goals_away <- fixtures$goals$away
  if (is.null(goals_away)) goals_away <- rep(NA, n)
  paste(f$id, f$date, f$status$short, elapsed, goals_home, goals_away,
        sep = ":", collapse = "|")
}

# Fixture ids a league's season data reports as finished (STATUS_BEENDET is
# defined in league_details.R, sourced by the loop before use).
.fixtures_beendet_ids <- function(fixtures) {
  fixtures$fixture$id[fixtures$fixture$status$short %in% STATUS_BEENDET]
}

update_all_leagues_loop <- function(duration = 480, loops = 31, initial_wait = 0,
                                    n = 10000, saison = "2023",
                                    TeamList_file = "RCode/TeamList_2023.csv",
                                    static_site_dir = Sys.getenv("STATIC_SITE_DIR",
                                                                 "ShinyApp/public"),
                                    full_fetch_every = 30) {
  if (loops > 1) {
    waittime <- duration * 60 / (loops - 1) # time between loops
  } else {
    waittime <- 0
  }

  # Wait initial_wait before starting
  Sys.sleep(initial_wait)

  # Per-league SETS of finished fixture ids as of the last simulation. NULL
  # until loop 1 has simulated (i == 1 always simulates). A set comparison,
  # not a count: counts can coincidentally stay equal while the fixtures
  # behind them change (issue #154).
  beendet_bl <- NULL
  beendet_bl2 <- NULL
  beendet_liga3 <- NULL

  # Live-poll gating state: the cheap 1-request live check replaces the full
  # 3-request fetch on idle iterations. While fixtures are live, every loop
  # fetches so the rendered Live section shows current scores. Ids that
  # leave the live feed go into pending_finished_ids and stay there until a
  # full fetch actually shows them as final: the season endpoint can lag the
  # live feed by seconds (issue #154), so the trigger must re-arm the fetch
  # until the season data has caught up. full_fetch_every is the safety net
  # for status changes that bypass "live" (awarded/postponed results).
  prev_live_ids <- NULL # NULL = unknown (no live poll yet)
  pending_finished_ids <- integer(0)
  last_full_fetch_loop <- 0

  # Signature of the render-relevant fixture fields behind the last
  # generated site; any change re-renders even without a new simulation.
  last_render_signature <- NULL

  # Source the Rust REST client and assert the server is reachable before doing
  # any work. Phase 1 of issue #77: the production loop now requires Rust;
  # there is no in-process fallback to C++. A missing/broken Rust server fails
  # the scheduler at startup so the operator sees the real problem instead of
  # silent engine substitution.
  source("RCode/rust_integration.R")
  if (!connect_rust_simulator()) {
    stop(sprintf(
      "Rust simulator not available at %s. Check that the Rust server is running before starting the scheduler.",
      Sys.getenv("RUST_API_URL", "http://localhost:8080")
    ))
  }

  # Common R functions needed regardless of engine
  source("RCode/retrieveResults.R")
  source("RCode/Tabelle.R")
  source("RCode/transform_data.R")
  source("RCode/league_details.R")
  source("RCode/generate_static_site.R")

  # Import Team Data
  TeamList <- read.csv(TeamList_file, sep = ";")

  # Initialize result objects to ensure they exist
  Ergebnis <- NULL
  Ergebnis2 <- NULL
  Ergebnis3 <- NULL
  Ergebnis3_Aufstieg <- NULL

  # Start main loop
  for (i in 1:loops) {
    message(sprintf("\n=== Starting loop %d of %d at %s ===", i, loops, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

    # reset simulation_executed
    simulation_executed <- FALSE

    # Decide whether the full 3-league fetch is needed this iteration
    need_full_fetch <- TRUE
    if (i > 1) {
      live_ids <- retrieveLiveFixtures()
      if (is.null(live_ids)) {
        message(sprintf("Loop %d: live poll failed, falling back to full fetch", i))
      } else {
        if (!is.null(prev_live_ids)) {
          pending_finished_ids <- union(
            pending_finished_ids, setdiff(prev_live_ids, live_ids)
          )
        }
        due_safety_fetch <- (i - last_full_fetch_loop) >= full_fetch_every
        # Fetch while anything is live (the Live section shows current
        # scores), while a finished fixture is pending, or when the safety
        # net is due. Only a fully idle loop skips the fetch.
        if (length(live_ids) == 0 && length(pending_finished_ids) == 0 &&
              !due_safety_fetch) {
          need_full_fetch <- FALSE
        }
        prev_live_ids <- live_ids
      }
    }

    if (need_full_fetch) {
      last_full_fetch_loop <- i

      # get fixtures via API
      fixturesBL <- retrieveResults(league = "78", season = saison)
      fixturesBL2 <- retrieveResults(league = "79", season = saison)
      fixturesLiga3 <- retrieveResults(league = "80", season = saison)

      # Check if API calls failed
      if (is.null(fixturesBL) || is.null(fixturesBL2) || is.null(fixturesLiga3)) {
        message(sprintf("Loop %d: ERROR - One or more API calls failed. Skipping this iteration.", i))
        next
      }

      # Resolve pending finished fixtures: an id leaves the set once the
      # season data shows it final (beendet or verschoben), or when no league
      # knows it (guards against an id staying pending forever). One still
      # reported live means the season endpoint lags the live feed (issue
      # #154): keep it pending so the next loop fetches again.
      if (length(pending_finished_ids) > 0) {
        all_ids <- c(
          fixturesBL$fixture$id, fixturesBL2$fixture$id,
          fixturesLiga3$fixture$id
        )
        all_status <- c(
          fixturesBL$fixture$status$short, fixturesBL2$fixture$status$short,
          fixturesLiga3$fixture$status$short
        )
        # AWD/WO (awarded/walkover) are final too, though outside the
        # beendet set that drives simulations.
        final_status <- c(STATUS_BEENDET, STATUS_VERSCHOBEN, "AWD", "WO")
        final_ids <- all_ids[all_status %in% final_status]
        pending_finished_ids <- pending_finished_ids[
          pending_finished_ids %in% all_ids &
            !(pending_finished_ids %in% final_ids)
        ]
        if (length(pending_finished_ids) > 0) {
          message(sprintf(
            "Loop %d: %d finished fixture(s) not yet final in season data, refetching next loop",
            i, length(pending_finished_ids)
          ))
        }
      }

      # New per-league sets of finished fixtures
      beendet_bl_new <- .fixtures_beendet_ids(fixturesBL)
      beendet_bl2_new <- .fixtures_beendet_ids(fixturesBL2)
      beendet_liga3_new <- .fixtures_beendet_ids(fixturesLiga3)

      # transform data
      BL <- transform_data(fixturesBL, TeamList)
      BL2 <- transform_data(fixturesBL2, TeamList)
      Liga3 <- transform_data(fixturesLiga3, TeamList)

      # Penalize second teams in Liga3, so that they cannot promote
      adjPoints_Liga3_Aufstieg <- rep(0, dim(Liga3)[2] - 4) # initialize to 0

      for (j in 5:dim(Liga3)[2]) {
        team_short <- names(Liga3)[j]
        last_char_team <- substr(team_short, nchar(team_short), nchar(team_short))
        if (last_char_team == "2") {
          adjPoints_Liga3_Aufstieg[j - 4] <- -50 # if team name ends in "2", penalize
        }
      }

      # On first iteration (i == 1), always run all simulations to ensure objects exist
      if (i == 1 || !setequal(beendet_bl, beendet_bl_new)) {
        message(sprintf(
          "Loop %d: Simulating Bundesliga with %d simulations (Rust engine)",
          i, n
        ))
        Ergebnis <- leagueSimulatorRust(BL, n = n)
        beendet_bl <- beendet_bl_new
        simulation_executed <- TRUE
      }

      if (i == 1 || !setequal(beendet_bl2, beendet_bl2_new)) {
        message(sprintf(
          "Loop %d: Simulating 2. Bundesliga with %d simulations (Rust engine)",
          i, n
        ))
        Ergebnis2 <- leagueSimulatorRust(BL2, n = n)
        beendet_bl2 <- beendet_bl2_new
        simulation_executed <- TRUE
      }

      if (i == 1 || !setequal(beendet_liga3, beendet_liga3_new)) {
        message(sprintf(
          "Loop %d: Simulating 3. Liga with %d simulations (Rust engine)",
          i, n
        ))
        Ergebnis3 <- leagueSimulatorRust(Liga3, n = n)
        beendet_liga3 <- beendet_liga3_new

        # calculate promotion table
        Ergebnis3_Aufstieg <- leagueSimulatorRust(Liga3, n = n, adjPoints = adjPoints_Liga3_Aufstieg)
        simulation_executed <- TRUE
      }

      # Regenerate the static site if simulations have been executed OR any
      # render-relevant fixture field changed (issue #154): Rückblick, Live
      # and Ausblick follow the fixture data, not only simulation results.
      render_signature <- paste(
        .fixtures_render_signature(fixturesBL),
        .fixtures_render_signature(fixturesBL2),
        .fixtures_render_signature(fixturesLiga3),
        sep = "~"
      )
      fixtures_changed <- !identical(render_signature, last_render_signature)

      if ((simulation_executed || fixtures_changed) && !is.null(Ergebnis)) {
        if (simulation_executed) {
          message(sprintf("Loop %d: Regenerating static site with new results", i))
        } else {
          message(sprintf("Loop %d: Fixture data changed, re-rendering static site", i))
        }

        # Phase 4a: build the Ligatabelle/ELO section data per league. Errors
        # (endpoint down, parse failure, ...) are handled inside
        # build_league_page_data(), which returns NULL with a warning; the
        # page then degrades to the Phase-3 layout for that league.
        league_data <- list(
          bundesliga = build_league_page_data(fixturesBL, TeamList),
          zweite_bundesliga = build_league_page_data(fixturesBL2, TeamList),
          dritte_liga = build_league_page_data(fixturesLiga3, TeamList)
        )

        generate_static_site(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg,
                             output_dir = static_site_dir,
                             league_data = league_data)
        last_render_signature <- render_signature
      } else {
        message(sprintf("Loop %d: No updates needed, skipping site generation", i))
      }
    } else {
      message(sprintf(
        "Loop %d: idle (no live fixtures, nothing pending) - skipping full fetch",
        i
      ))
    }

    # Wait if not last iteration
    if (i < loops) {
      message(sprintf("Loop %d: Waiting %.1f minutes until next update...", i, waittime / 60))
      Sys.sleep(waittime)
    }
  }

  message(sprintf("\n=== Completed all %d loops at %s ===", loops, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
}
