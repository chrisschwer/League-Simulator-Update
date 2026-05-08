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

library(testthat)

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
    "TeamList_2099_League78.csv",
    "TeamList_2099_League79.csv",
    "TeamList_2099_League80.csv"
  ))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  res <- run_cleanup(tmp, "2099", confirm = FALSE)

  expect_equal(res$status, 0L)
  expect_match(res$output, "Would remove 3 files", fixed = TRUE)
  expect_match(res$output, "Use --confirm", fixed = TRUE)
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099_League78.csv")))
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099_League79.csv")))
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099_League80.csv")))
})

test_that("cleanup wrapper --confirm removes matched files", {
  tmp <- setup_rcode(c(
    "TeamList_2099_League78.csv",
    "TeamList_2099_League79.csv",
    "TeamList_2099_League80.csv"
  ))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  res <- run_cleanup(tmp, "2099", confirm = TRUE)

  expect_equal(res$status, 0L)
  expect_match(res$output, "Removed 3 files", fixed = TRUE)
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League78.csv")))
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League79.csv")))
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League80.csv")))
})

test_that("cleanup wrapper does not touch foreign files even with --confirm", {
  tmp <- setup_rcode(c(
    "TeamList_2099_League78.csv",
    "TeamList_2099_League79.csv",
    "TeamList_2099_League80.csv",
    # Foreign files that must NOT be deleted:
    "TeamList_2099.csv",          # final season file
    "TeamList_2099_archive.csv",  # arbitrary non-pipeline name
    "stale.tmp",
    "active.lock",
    "TeamList_2098_League78.csv"  # different season
  ))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  res <- run_cleanup(tmp, "2099", confirm = TRUE)

  expect_equal(res$status, 0L)
  expect_match(res$output, "Removed 3 files", fixed = TRUE)
  # Pipeline-produced files for 2099 are gone:
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League78.csv")))
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League79.csv")))
  expect_false(file.exists(file.path(tmp, "RCode", "TeamList_2099_League80.csv")))
  # Foreign files survive:
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099.csv")))
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2099_archive.csv")))
  expect_true(file.exists(file.path(tmp, "RCode", "stale.tmp")))
  expect_true(file.exists(file.path(tmp, "RCode", "active.lock")))
  expect_true(file.exists(file.path(tmp, "RCode", "TeamList_2098_League78.csv")))
})

test_that("cleanup wrapper prints explanatory message on zero matches", {
  tmp <- setup_rcode(character(0))  # empty RCode/
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  res <- run_cleanup(tmp, "2099", confirm = FALSE)

  expect_equal(res$status, 0L)
  expect_match(res$output, "No cleanup files found", fixed = TRUE)
  expect_match(res$output, "2099", fixed = TRUE)
})
