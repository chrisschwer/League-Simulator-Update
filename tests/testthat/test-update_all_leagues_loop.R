# Phase 4a: Der Produktionsloop baut je Liga die Seitendaten
# (build_league_page_data) und reicht sie als league_data an
# generate_static_site() weiter. Fehlt eine Liga (Endpoint-Fehler ->
# NULL), wird trotzdem gerendert — Degradation statt Abbruch.
#
# Mocking wie in test-update_all_leagues_loop-gating.R: mockery::stub() gegen die
# Funktionsumgebung von update_all_leagues_loop(), Aufruf unter Repo-Root.

library(testthat)
library(mockery)

source("../../RCode/update_all_leagues_loop.R", local = TRUE)

# Nur fixture$status$short -- schmaler als fake_fixtures() aus
# helper-fixtures.R (ohne id, date, goals). fake_transformed() steht dort.
fake_fixtures_nur_status <- function(statuses) {
  list(fixture = list(status = list(short = statuses)))
}

run_one_loop <- function(build_stub, capture_env) {
  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    capture_env$fetched_leagues <- c(capture_env$fetched_leagues, league)
    fake_fixtures_nur_status(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust",
       function(..., eligibilityMasks = NULL) {
         m <- matrix(1 / 18, nrow = 18, ncol = 18)
         # Mit Maske liefert die Engine zusaetzlich den Rang unter den
         # Berechtigten (ADR 0009); der Loop legt ihn als Aufstiegstabelle ab.
         if (!is.null(eligibilityMasks)) attr(m, "eligible_rank_probabilities") <- list(m)
         m
       })
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
      static_site_dir = tempdir()
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
  # Je aktive Liga ein Aufruf, mit der eingelesenen TeamList als zweitem Argument
  aktiv <- local({
    e <- new.env()
    source(file.path("..", "..", "RCode", "league_registry.R"), local = e)
    e$active_league_keys()
  })
  expect_length(capture$build_calls, length(aktiv))
  expect_true(all(vapply(capture$build_calls,
                         function(x) "TeamID" %in% names(x$teams), logical(1))))

  # league_data ist nach den league_views()-Schlüsseln benannt und trägt die
  # drei Ergebnisse in Liga-Reihenfolge (BL, BL2, Liga3)
  expect_equal(names(capture$league_data), aktiv)
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

# --- aus test-n-ligen-entflechtung.R ---
# --- Update-Loop: n Ligen statt drei Variablen ------------------------------

fake_fixtures_min <- function(statuses = c("FT", "NS"), ids = c(1L, 2L)) {
  list(
    fixture = list(
      id = ids,
      date = rep("2026-08-01T13:00:00+00:00", length(ids)),
      status = list(short = statuses, elapsed = rep(NA, length(ids)))
    ),
    goals = list(home = rep(0L, length(ids)), away = rep(0L, length(ids)))
  )
}

fake_transformed_min <- function() {
  data.frame(
    TeamHeim = "AAA", TeamGast = "BBB", ToreHeim = 1, ToreGast = 0,
    AAA = 1500, BBB = 1500
  )
}

#' Führt einen Loop-Durchlauf aus und protokolliert die Kollaborateur-Aufrufe.
run_loop_capturing <- function() {
  cap <- new.env()
  cap$fetched <- character()
  cap$sim_frames <- 0L
  cap$league_data <- NULL
  cap$ergebnisse <- NULL

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    cap$fetched <- c(cap$fetched, league)
    fake_fixtures_min()
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed_min())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(..., eligibilityMasks = NULL) {
    cap$sim_frames <- cap$sim_frames + 1L
    m <- matrix(1 / 18, nrow = 18, ncol = 18)
    if (!is.null(eligibilityMasks)) attr(m, "eligible_rank_probabilities") <- list(m)
    m
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    args <- list(...)
    cap$league_data <- args$league_data
    cap$ergebnisse <- args$ergebnisse
    invisible(NULL)
  })

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10, saison = "2024",
      TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir()
    )
  })
  cap
}

test_that("der Loop holt die Ligen aus der Registry, in Registry-Reihenfolge", {
  # Vorher standen die drei retrieveResults-Aufrufe einzeln im Code. Jetzt
  # iteriert der Loop -- die Reihenfolge muss dieselbe bleiben, weil
  # diese Datei sie über SENTINEL-1/2/3 pinnt.
  cap <- run_loop_capturing()

  reg <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = reg)
  expect_equal(cap$fetched, reg$league_ids())
})

test_that("der Loop uebergibt die Ergebnisse als benannte Liste", {
  # Die neue Form. Der Aufstiegslauf der 3. Liga hat einen eigenen Schlüssel.
  cap <- run_loop_capturing()

  expect_type(cap$ergebnisse, "list")
  # Je aktive Liga ein Eintrag, plus eine Aufstiegstabelle je Liga, aus der
  # Zweitvertretungen nicht aufsteigen duerfen (Rang unter den Berechtigten).
  #
  # ANGEPASST in Phase 5 und wieder mit #291: Der Lauf heisst "<key>_aufstieg"
  # -- dort liest die View das obere Panel. Den Ausweichnamen
  # "<key>_aufstiegstabelle" fuer die Regionalligen gibt es nicht mehr, seit
  # sie keinen Malus-Lauf haben.
  reg <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = reg)
  source(test_path("..", "..", "RCode", "league_views.R"), local = reg)
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = reg)

  mit_lauf <- Filter(
    function(k) reg$has_promotion_restriction(reg$league_registry()[[k]]$api_id),
    reg$active_league_keys()
  )
  # Harness-Probe: Die View jeder Liga mit Lauf liest ihn unter diesem Namen.
  for (k in mit_lauf) {
    expect_identical(reg$league_views()[[k]]$top$source,
                     reg$.ergebnis_objektname(paste0(k, "_aufstieg")), info = k)
  }
  erwartet <- c(reg$active_league_keys(), paste0(mit_lauf, "_aufstieg"))

  expect_setequal(names(cap$ergebnisse), erwartet)
  expect_false(any(vapply(cap$ergebnisse, is.null, logical(1))))
})

test_that("league_data behaelt seine Schluessel und Reihenfolge", {
  # Der Generator indiziert league_data[[key]] mit den league_views()-
  # Schlüsseln. Weicht die Benennung ab, bekommt jede Liga stillschweigend
  # keine Tabellendaten -- die Seite degradiert, ohne zu scheitern.
  cap <- run_loop_capturing()

  reg <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = reg)
  expect_equal(names(cap$league_data), reg$active_league_keys())
})

test_that("Loop 1 simuliert jede Liga genau einmal", {
  # Je Liga eine Simulation. Die Aufstiegstabelle der Ligen mit
  # Aufstiegssperre kommt aus einer Maske im selben Lauf, nicht mehr aus einem
  # zweiten (ADR 0009). Die Zahl folgt der Registry, nicht einer festen
  # Annahme.
  cap <- run_loop_capturing()

  reg <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = reg)
  ids <- reg$league_ids()
  erwartet <- length(ids)

  expect_equal(cap$sim_frames, erwartet)
})
