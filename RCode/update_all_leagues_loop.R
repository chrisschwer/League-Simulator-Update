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
  source("RCode/league_registry.R")

  # Die Ligen dieses Laufs. Reihenfolge = Registry-Reihenfolge und damit
  # Fetch-Reihenfolge; sie ist Vertrag (test-update-loop-league-data.R).
  liga_keys <- active_league_keys()
  liga_ids <- stats::setNames(
    vapply(active_leagues(), function(l) l$api_id, character(1)),
    liga_keys
  )

  # Je Liga die Menge beendeter Fixture-Ids zum Zeitpunkt der letzten
  # Simulation. NULL bis Loop 1 simuliert hat. Ein Mengenvergleich, keine
  # Zaehlung: Zaehlungen koennen zufaellig gleich bleiben, waehrend sich die
  # Fixtures dahinter aendern (issue #154).
  beendet <- stats::setNames(vector("list", length(liga_keys)), liga_keys)

  # Import Team Data. load_team_list() (transform_data.R) prueft dabei die
  # Invarianten, auf die transform_data() baut: global eindeutige Kurznamen
  # und TeamIDs. Beide Verstoesse wuerden sonst still zu vertauschten Teams
  # bzw. vervielfachten Spielzeilen fuehren.
  TeamList <- load_team_list(TeamList_file)

  # Initialize result objects to ensure they exist
  # Prognosen je Liga. `dritte_liga_aufstieg` ist kein eigener Ligaslot,
  # sondern der zweite Lauf der 3. Liga mit -50-Malus fuer Zweitvertretungen;
  # league_views() loest ihn ueber seinen Namen auf.
  ergebnisse <- list()

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

      # Fixtures je Liga. Der lapply-Aufruf bleibt bewusst INLINE: Die Tests
      # stubben retrieveResults() gegen die Umgebung dieser Funktion; in eine
      # ausgelagerte Helferfunktion greift der Stub nicht mehr.
      fixtures <- stats::setNames(
        lapply(liga_ids, function(id) retrieveResults(league = id, season = saison)),
        liga_keys
      )

      # Check if API calls failed
      if (any(vapply(fixtures, is.null, logical(1)))) {
        message(sprintf("Loop %d: ERROR - One or more API calls failed. Skipping this iteration.", i))
        next
      }

      # Resolve pending finished fixtures: an id leaves the set once the
      # season data shows it final (beendet or verschoben), or when no league
      # knows it (guards against an id staying pending forever). One still
      # reported live means the season endpoint lags the live feed (issue
      # #154): keep it pending so the next loop fetches again.
      if (length(pending_finished_ids) > 0) {
        all_ids <- unlist(lapply(fixtures, function(f) f$fixture$id),
                          use.names = FALSE)
        all_status <- unlist(lapply(fixtures, function(f) f$fixture$status$short),
                             use.names = FALSE)
        # Awarded results (AWD/WO) are final too, though outside the
        # beendet set that drives simulations.
        final_status <- c(STATUS_BEENDET, STATUS_VERSCHOBEN, STATUS_AWARDED)
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
      beendet_new <- lapply(fixtures, .fixtures_beendet_ids)

      # transform data
      spielplaene <- lapply(fixtures, function(f) transform_data(f, TeamList))

      # Simulation je Liga. Loop 1 simuliert immer, damit die Objekte
      # existieren; danach nur bei geaenderter Menge beendeter Spiele.
      #
      # Die Schleife bleibt INLINE: Die Tests stubben leagueSimulatorRust()
      # gegen die Umgebung dieser Funktion.
      for (key in liga_keys) {
        if (!(i == 1 || !setequal(beendet[[key]], beendet_new[[key]]))) {
          next
        }

        spielplan <- spielplaene[[key]]
        message(sprintf(
          "Loop %d: Simulating %s with %d simulations (Rust engine)",
          i, league_name(liga_ids[[key]]), n
        ))
        ergebnisse[[key]] <- leagueSimulatorRust(spielplan, n = n)
        beendet[[key]] <- beendet_new[[key]]

        # Ligen, aus denen Zweitvertretungen nicht aufsteigen duerfen,
        # brauchen eine eigene Aufstiegstabelle: ein zweiter Lauf, in dem
        # sie -50 Punkte tragen und damit aus dem Rennen sind. Bisher war
        # das an die Liga-ID "80" gebunden; jetzt an die Liga-Eigenschaft --
        # die Regionalligen brauchen dasselbe, sobald sie live gehen.
        #
        # NAMENSKOLLISION seit Phase 5: Der Schluessel folgt der VIEW. Wo
        # sie das obere Panel aus "<key>_aufstieg" liest (3. Liga,
        # 2. Frauen-Bundesliga), landet der Lauf dort. Bei den
        # Regionalligen ist dieser Name aber schon vergeben -- er traegt die
        # BERECHNETE Aufstiegsspalte (rl_aufstiegsprognose(), ein data.frame
        # je Team). Eine ganze Platzmatrix unter demselben Namen
        # uebernaehme die Spalte lautlos, und die Seite zeigte statt der
        # Aufstiegswahrscheinlichkeit eine Platzverteilung -- ohne dass
        # etwas fehlschlaegt. Der Lauf heisst dort deshalb
        # "<key>_aufstiegstabelle".
        aufstiegs_key <- paste0(key, "_aufstieg")
        if (!identical(league_views()[[key]]$top$source,
                       .ergebnis_objektname(aufstiegs_key))) {
          aufstiegs_key <- paste0(key, "_aufstiegstabelle")
        }

        if (has_promotion_restriction(liga_ids[[key]])) {
          adj_points <- rep(0, dim(spielplan)[2] - 4)
          for (j in 5:dim(spielplan)[2]) {
            team_short <- names(spielplan)[j]
            if (substr(team_short, nchar(team_short), nchar(team_short)) == "2") {
              adj_points[j - 4] <- -50
            }
          }
          ergebnisse[[aufstiegs_key]] <-
            leagueSimulatorRust(spielplan, n = n, adjPoints = adj_points)
        }

        simulation_executed <- TRUE
      }

      # Regenerate the static site if simulations have been executed OR any
      # render-relevant fixture field changed (issue #154): Rückblick, Live
      # and Ausblick follow the fixture data, not only simulation results.
      render_signature <- paste(
        vapply(fixtures, .fixtures_render_signature, character(1)),
        collapse = "~"
      )
      fixtures_changed <- !identical(render_signature, last_render_signature)

      if ((simulation_executed || fixtures_changed) && length(ergebnisse) > 0) {
        if (simulation_executed) {
          message(sprintf("Loop %d: Regenerating static site with new results", i))
        } else {
          message(sprintf("Loop %d: Fixture data changed, re-rendering static site", i))
        }

        # Phase 4a: build the Ligatabelle/ELO section data per league. Errors
        # (endpoint down, parse failure, ...) are handled inside
        # build_league_page_data(), which returns NULL with a warning; the
        # page then degrades to the Phase-3 layout for that league.
        # Die Namen sind die Registry-Schluessel und zugleich die von
        # league_views(); der Generator indiziert league_data[[key]] damit.
        league_data <- stats::setNames(
          lapply(liga_keys, function(key) {
            build_league_page_data(fixtures[[key]], TeamList)
          }),
          liga_keys
        )

        generate_static_site(output_dir = static_site_dir,
                             league_data = league_data,
                             ergebnisse = ergebnisse)
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
