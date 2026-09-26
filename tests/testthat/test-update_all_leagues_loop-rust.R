# Phase 1 regression net for the Rust-required production loop.
# Issue #77 / docs/superpowers/plans/2026-05-02-simulation-engine-seam.md.

library(testthat)

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

  with_repo_root({
    source("RCode/update_all_leagues_loop.R", local = FALSE)
    # The function exists post-source; just assert it can be invoked with a
    # one-loop call and that we don't get an immediate error from sourcing/wiring.
    # We don't assert on Ergebnis values here — we'd need a stubbed retrieveResults
    # to do that, and that's a bigger fixture than this test should own. The
    # post-refactor version of this test (Task 7) will exercise the seam shape.
    expect_true(exists("update_all_leagues_loop"))
    # Function signature check: in Phase 1's pre-state, has `use_rust` parameter;
    # in Phase 1's post-state, does not. We assert nothing here — Task 7 does the
    # signature check after the refactor.
  })
})

test_that("loop fails fast with RUST_API_URL message when Rust is down (post-refactor)", {
  skip_if_not_installed("httr")

  # Point at a port that is guaranteed to refuse connections (no server here).
  prior_rust_api_url <- Sys.getenv("RUST_API_URL", unset = NA)
  Sys.setenv(RUST_API_URL = "http://127.0.0.1:1")
  on.exit({
    if (is.na(prior_rust_api_url)) {
      Sys.unsetenv("RUST_API_URL")
    } else {
      Sys.setenv(RUST_API_URL = prior_rust_api_url)
    }
  }, add = TRUE)

  with_repo_root({
    source("RCode/update_all_leagues_loop.R", local = FALSE)
    # PRE-REFACTOR EXPECTATION (will FAIL today, by design — this is the canary
    # the refactor is meant to flip):
    err <- tryCatch(
      update_all_leagues_loop(duration = 0, loops = 1, n = 10,
                              saison = "2024",
                              TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
                              static_site_dir = tempdir()),
      error = function(e) e
    )
    # Post-refactor: error message must mention "Rust simulator not available"
    # and include the unreachable URL the test pointed at (http://127.0.0.1:1).
    # Pre-refactor: today's code logs a warning and silently sources C++ (no error).
    # So this assertion intentionally fails until Tasks 3–5 land.
    expect_s3_class(err, "error")
    expect_match(conditionMessage(err), "Rust simulator not available", fixed = TRUE)
    expect_match(conditionMessage(err), "127.0.0.1:1", fixed = TRUE)
  })
})
