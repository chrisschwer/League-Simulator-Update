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

  # Die /league-details-Antworten sind AUFGEZEICHNET (Issue #146, Teil 2).
  #
  # Seit Teil 2 holt der Saisonwechsel die End-ELOs ueber POST
  # /league-details. Der Test braucht dafuer trotzdem KEINEN laufenden
  # Rust-Server: Die Antworten liegen als httptest-Kassetten unter
  # localhost-8080/ neben den api-football-Kassetten.
  #
  # Das ist die bessere Haelfte beider Varianten -- die ELO-Physik bleibt in
  # der geprueften Kette (die Kassetten stammen aus einem echten Lauf gegen
  # die Engine), aber die CI braucht keinen Serverstart. Neu aufzuzeichnen ist
  # nur, wenn sich Payload oder Modellkonstanten aendern; dann schlaegt der
  # Test fehl, weil httptest keine passende Kassette findet.

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
  #
  # R_LIBS must be passed explicitly: in the in-image CI run, test-only
  # packages (httptest, mockery, ...) are installed at runtime into a
  # writable library (e.g. /tmp/Rlib) added to the parent session's
  # .libPaths() — an R-session-level setting that Sys.getenv() cannot see
  # and therefore would not otherwise propagate to this subprocess.
  parent_env <- Sys.getenv()
  test_env <- c(
    parent_env,
    RAPIDAPI_KEY             = "dummy-mock-key-not-real",
    R_LIBS                   = paste(.libPaths(), collapse = .Platform$path.sep)
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
  #
  # Der Lauf schreibt einen ENTWURF, nicht die produktive Datei (ADR 0007,
  # Issue #206): Die TeamList ist gepflegtes Stammdatenblatt, und ein Lauf
  # im --non-interactive-Modus ueberschriebe sie sonst ohne Rueckfrage.
  # Geprueft wird deshalb TeamList_2025_entwurf.csv -- derselbe Inhalt, nur
  # unter dem Namen, unter dem er jetzt entsteht.
  actual_csv <- file.path(csv_dir, "RCode", "TeamList_2025_entwurf.csv")
  expect_true(file.exists(actual_csv),
              info = "subprocess must produce TeamList_2025_entwurf.csv")

  # Und die produktive Datei darf NICHT entstehen. Ohne diese Zeile bliebe
  # der gefaehrliche Pfad unbeobachtet.
  expect_false(file.exists(file.path(csv_dir, "RCode", "TeamList_2025.csv")),
               info = "der Lauf darf die produktive TeamList nicht schreiben")

  actual_bytes   <- readBin(actual_csv,   "raw", file.info(actual_csv)$size)
  expected_bytes <- readBin(expected_csv, "raw", file.info(expected_csv)$size)

  expect_equal(length(actual_bytes), length(expected_bytes),
               info = "CSV byte-count drift; see fixture README to re-record")
  expect_equal(actual_bytes, expected_bytes,
               info = paste("CSV bytes differ from snapshot.",
                            "If the change is intentional, re-record per",
                            "tests/testthat/fixtures/season-transition-2024-to-2025/README.md."))
})

# --- aus test-season-transition-cleanup-wrapper.R ---
# Tests for scripts/season_transition/cleanup.R recovery wrapper.
#
# Strategy: invoke the wrapper via Rscript in a subprocess against a temp dir
# that mimics RCode/. We use Rscript (not source()) because cleanup.R is a CLI
# script with quit() calls — sourcing it directly would terminate the test session.
#
# Note: processx::run is used instead of system2() because the project root
# may contain spaces (e.g. "Coding Projects/"), and system2 word-splits unquoted
# args. processx::run uses exec() directly and is space-safe. processx is a
# dependency of testthat and always available.

# Helper: run cleanup.R in a temp dir, return list(output=..., status=...).
run_cleanup <- function(tmp, season, confirm = FALSE) {
  project_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
  cleanup_script <- file.path(project_root, "scripts", "season_transition", "cleanup.R")
  args <- c(cleanup_script, season)
  if (confirm) args <- c(args, "--confirm")
  p <- processx::run("Rscript", args = args, error_on_status = FALSE,
                     wd = tmp)
  list(
    output = paste(p$stdout, p$stderr, sep = "\n"),
    status = p$status
  )
}

# Helper: create a temp RCode/ with the given files (as relative paths).
setup_rcode <- function(files) {
  tmp <- tempfile("cleanup_test_")
  dir.create(file.path(tmp, "RCode"), recursive = TRUE)
  for (f in files) {
    full <- file.path(tmp, "RCode", f)
    writeLines("dummy", full)
  }
  tmp
}

test_that("cleanup wrapper dry-run leaves files untouched", {
  tmp <- setup_rcode(c(
    "TeamList_2099_League78_temp.csv",
    "TeamList_2099_League79_temp.csv",
    "TeamList_2099_League80_temp.csv"
  ))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  res <- run_cleanup(tmp, "2099", confirm = FALSE)

  expect_equal(res$status, 0L)
  expect_match(res$output, "Would remove 3 files", fixed = TRUE)
  expect_match(res$output, "Use --confirm", fixed = TRUE)
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099_League78_temp.csv")))
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099_League79_temp.csv")))
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099_League80_temp.csv")))
})

test_that("cleanup wrapper --confirm removes matched files", {
  tmp <- setup_rcode(c(
    "TeamList_2099_League78_temp.csv",
    "TeamList_2099_League79_temp.csv",
    "TeamList_2099_League80_temp.csv"
  ))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  res <- run_cleanup(tmp, "2099", confirm = TRUE)

  expect_equal(res$status, 0L)
  expect_match(res$output, "Removed 3 files", fixed = TRUE)
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League78_temp.csv")))
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League79_temp.csv")))
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League80_temp.csv")))
})

test_that("cleanup wrapper does not touch foreign files even with --confirm", {
  tmp <- setup_rcode(c(
    "TeamList_2099_League78_temp.csv",
    "TeamList_2099_League79_temp.csv",
    "TeamList_2099_League80_temp.csv",
    # Foreign files that must NOT be deleted:
    "TeamList_2099.csv",          # final season file
    "TeamList_2099_archive.csv",  # arbitrary non-pipeline name
    "stale.tmp",
    "active.lock",
    "TeamList_2098_League78_temp.csv"  # different season
  ))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  res <- run_cleanup(tmp, "2099", confirm = TRUE)

  expect_equal(res$status, 0L)
  expect_match(res$output, "Removed 3 files", fixed = TRUE)
  # Pipeline-produced files for 2099 are gone:
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League78_temp.csv")))
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League79_temp.csv")))
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League80_temp.csv")))
  # Foreign files survive:
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099.csv")))
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099_archive.csv")))
  expect_true(file.exists(file.path(tmp, "RCode", "stale.tmp")))
  expect_true(file.exists(file.path(tmp, "RCode", "active.lock")))
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2098_League78_temp.csv")))
})

test_that("cleanup wrapper prints explanatory message on zero matches", {
  tmp <- setup_rcode(character(0))  # empty RCode/
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  res <- run_cleanup(tmp, "2099", confirm = FALSE)

  expect_equal(res$status, 0L)
  expect_match(res$output, "No cleanup files found", fixed = TRUE)
  expect_match(res$output, "2099", fixed = TRUE)
})
