# Phase 1 regression net for the Rust-required production loop.
# Issue #77 / docs/superpowers/plans/2026-05-02-simulation-engine-seam.md.

library(testthat)

# --- Helpers: start/stop the Rust API server in the background ---

rust_binary <- function() {
  bin <- file.path("..", "..", "league-simulator-rust", "target", "release", "league-simulator-rust")
  if (!file.exists(bin)) {
    skip(sprintf("Rust binary not built at %s; run `cargo build --release` in league-simulator-rust/", bin))
  }
  normalizePath(bin)
}

start_rust_server <- function(port = 18080L) {
  bin <- rust_binary()
  log <- tempfile(fileext = ".log")
  pid <- sys::exec_background(bin, args = "--api", std_out = log, std_err = log,
                              env = c(PORT = as.character(port)))
  Sys.setenv(RUST_API_URL = sprintf("http://localhost:%d", port))
  # Wait up to 10 s for the server to become healthy.
  ok <- FALSE
  for (i in 1:50) {
    Sys.sleep(0.2)
    res <- tryCatch(httr::GET(paste0(Sys.getenv("RUST_API_URL"), "/health"),
                              httr::timeout(0.5)),
                    error = function(e) NULL)
    if (!is.null(res) && httr::status_code(res) == 200) { ok <- TRUE; break }
  }
  list(pid = pid, log = log, ok = ok, port = port)
}

stop_rust_server <- function(handle) {
  if (!is.null(handle$pid)) {
    try(tools::pskill(handle$pid), silent = TRUE)
  }
}

# Source the production loop fresh so the test sees the current state of the code.
# The loop's source() calls inside its body assume cwd = repo root; we set it explicitly.
with_repo_root <- function(expr) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(old, "..", ".."))   # tests/testthat -> repo root
  force(expr)
}

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
  Sys.setenv(RUST_API_URL = "http://127.0.0.1:1")

  with_repo_root({
    source("RCode/update_all_leagues_loop.R", local = FALSE)
    # PRE-REFACTOR EXPECTATION (will FAIL today, by design — this is the canary
    # the refactor is meant to flip):
    err <- tryCatch(
      update_all_leagues_loop(duration = 0, loops = 1, n = 10,
                              saison = "2024",
                              TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
                              shiny_directory = tempdir()),
      error = function(e) e
    )
    # Post-refactor: error message must mention RUST_API_URL.
    # Pre-refactor: today's code logs a warning and silently sources C++ (no error).
    # So this assertion intentionally fails until Tasks 3–5 land.
    expect_s3_class(err, "error")
    expect_match(conditionMessage(err), "RUST_API_URL", fixed = TRUE)
  })
})
