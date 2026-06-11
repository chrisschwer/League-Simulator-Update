# End-to-end CSV snapshot regression test for the season-transition workflow.
#
# Runs the season-transition pipeline in a fresh R subprocess (via
# tests/testthat/helpers/season-transition-snapshot-runner.R), with httptest
# replaying the api-football cassettes captured in
# tests/testthat/fixtures/season-transition-2024-to-2025/, and asserts:
#   (gap #2) the resulting RCode/TeamList_2025.csv matches the snapshot
#
# The engine-availability probe (gap #3) was retired alongside the silent
# C++/R fallback in issue #102 / Option B; only the byte-identity check
# remains as the load-bearing acceptance criterion.
#
# Note: processx::run is used instead of system2() because the project root
# path contains spaces ("Coding Projects/"), and system2() runs a shell that
# word-splits unquoted args. processx::run uses exec() directly and is
# space-safe. processx is a dependency of testthat and always available.
#
# Spec: docs/superpowers/specs/2026-05-03-season-transition-test-coverage-design.md

library(testthat)

test_that("season_transition pipeline produces byte-identical CSV from cassettes", {
  # normalizePath() is required: test_path() returns a relative path when running
  # inside testthat::test_file(), and httptest's with_mock_dir() resolves cassettes
  # relative to the cwd at time of each HTTP request (which changes to csv_dir
  # inside the subprocess). An absolute path avoids this pitfall.
  fixture_dir <- normalizePath(testthat::test_path("fixtures", "season-transition-2024-to-2025"))
  expected_csv <- file.path(fixture_dir, "TeamList_2025.csv.snapshot")
  skip_if_not(file.exists(expected_csv),
              "Snapshot fixture missing. Run _record.R to capture it.")

  # Resolve project root. testthat sets cwd to tests/testthat/ during test_file,
  # so we walk up two levels.
  project_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
  runner_path  <- file.path(project_root, "tests", "testthat", "helpers",
                             "season-transition-snapshot-runner.R")
  source_csv   <- file.path(project_root, "RCode", "TeamList_2024.csv")

  skip_if_not(file.exists(runner_path),
              "Subprocess runner missing.")
  skip_if_not(file.exists(source_csv),
              "RCode/TeamList_2024.csv missing — required as script input.")

  # Stage a temp dir with a copy of RCode/TeamList_2024.csv (script's input)
  csv_dir <- tempfile("season-transition-snapshot-")
  dir.create(file.path(csv_dir, "RCode"), recursive = TRUE)
  file.copy(source_csv, file.path(csv_dir, "RCode", "TeamList_2024.csv"))

  on.exit({
    unlink(csv_dir, recursive = TRUE)
  }, add = TRUE)

  # Build env for subprocess: merge parent env so R library paths are inherited,
  # then override with test-specific vars.
  # processx::run uses exec() (no shell) so spaces in arg values are safe.
  # Dummy RAPIDAPI_KEY satisfies the script's pre-flight check; httptest
  # intercepts before the key is ever sent.
  parent_env <- Sys.getenv()
  test_env <- c(
    parent_env,
    RAPIDAPI_KEY             = "dummy-mock-key-not-real"
  )

  rscript <- file.path(R.home("bin"), "Rscript")

  p <- processx::run(
    rscript,
    args    = c(runner_path, project_root, csv_dir, fixture_dir),
    env     = test_env,
    echo    = FALSE,
    error_on_status = FALSE
  )

  expect_equal(p$status, 0L,
               info = paste("Subprocess output:", paste(tail(strsplit(p$stdout, "\n")[[1]], 20), collapse = "\n"),
                            "\nStderr:", paste(tail(strsplit(p$stderr, "\n")[[1]], 10), collapse = "\n")))

  # Gap #2: byte-identical CSV.
  actual_csv <- file.path(csv_dir, "RCode", "TeamList_2025.csv")
  expect_true(file.exists(actual_csv),
              info = "subprocess must produce TeamList_2025.csv")

  actual_bytes   <- readBin(actual_csv,   "raw", file.info(actual_csv)$size)
  expected_bytes <- readBin(expected_csv, "raw", file.info(expected_csv)$size)

  expect_equal(length(actual_bytes), length(expected_bytes),
               info = "CSV byte-count drift; see fixture README to re-record")
  expect_equal(actual_bytes, expected_bytes,
               info = paste("CSV bytes differ from snapshot.",
                            "If the change is intentional, re-record per",
                            "tests/testthat/fixtures/season-transition-2024-to-2025/README.md."))
})
