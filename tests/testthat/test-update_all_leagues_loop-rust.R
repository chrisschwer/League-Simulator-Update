# Phase 1 regression net for the Rust-required production loop.
# Issue #77 / docs/superpowers/plans/2026-05-02-simulation-engine-seam.md.

library(testthat)
library(mockery)

source("../../RCode/update_all_leagues_loop.R")

# --- Tests ---

context("Phase 1 — Rust required, no fallback")

test_that("update_all_leagues_loop runs one iteration end-to-end with Rust up", {
  skip_if_not_installed("sys")
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")

  handle <- start_rust_server()
  on.exit(stop_rust_server(handle), add = TRUE)
  if (!handle$ok) {
    skip(sprintf("Rust server failed to come up on port %d; log: %s",
                 handle$port, handle$log))
  }

  # Pre-set the FT counters so the loop's "first iteration" branch runs cleanly.
  FT_BL <- 0; FT_BL2 <- 0; FT_Liga3 <- 0

  # Stubs nur fuer die Aussenwelt. NICHT gestubbt: connect_rust_simulator()
  # und leagueSimulatorRust() -- dieser Block ist der einzige, der den Loop
  # wirklich gegen das laufende Rust-Binary faehrt (alle anderen
  # Loop-Tests stubben leagueSimulatorRust() weg, siehe
  # test-update_all_leagues_loop.R).
  capture <- new.env()
  capture$site_calls <- 0
  capture$ergebnisse <- NULL

  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    capture$site_calls <- capture$site_calls + 1
    capture$ergebnisse <- list(...)$ergebnisse
    invisible(character(0))
  })

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 50,
      saison = "2024",
      TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = withr::local_tempdir()
    )
  })

  expect_equal(capture$site_calls, 1)

  aktiv <- local({
    e <- new.env()
    source(file.path("..", "..", "RCode", "league_registry.R"), local = e)
    e$active_league_keys()
  })
  expect_true(all(aktiv %in% names(capture$ergebnisse)))

  # Je Liga: rownames AAA/BBB (fake_transformed()) und eine echte
  # Wahrscheinlichkeitsmatrix -- Zeilensummen 1 -- aus dem laufenden Server.
  expect_true(all(vapply(aktiv, function(key) {
    identical(rownames(capture$ergebnisse[[key]]), c("AAA", "BBB"))
  }, logical(1))))
  expect_true(all(vapply(aktiv, function(key) {
    isTRUE(all.equal(unname(rowSums(capture$ergebnisse[[key]])), c(1, 1),
                     tolerance = 1e-9))
  }, logical(1))))
})

test_that("loop fails fast with RUST_API_URL message when Rust is down (post-refactor)", {
  skip_if_not_installed("httr")

  # Point at a port that is guaranteed to refuse connections (no server here).
  withr::local_envvar(RUST_API_URL = "http://127.0.0.1:1")

  with_repo_root({
    source("RCode/update_all_leagues_loop.R", local = FALSE)
    # Ohne erreichbaren Server bricht der Loop sofort ab und nennt die URL
    # (#77, kein Fallback).
    err <- tryCatch(
      update_all_leagues_loop(duration = 0, loops = 1, n = 10,
                              saison = "2024",
                              TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
                              static_site_dir = tempdir()),
      error = function(e) e
    )
    # Die Fehlermeldung muss "Rust simulator not available" enthalten und die
    # unerreichbare URL nennen (http://127.0.0.1:1).
    expect_s3_class(err, "error")
    expect_match(conditionMessage(err), "Rust simulator not available", fixed = TRUE)
    expect_match(conditionMessage(err), "127.0.0.1:1", fixed = TRUE)
  })
})
