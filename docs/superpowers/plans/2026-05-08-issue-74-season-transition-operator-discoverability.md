# Issue #74 — Season-Transition Operator Discoverability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect existing-but-disconnected season-transition validators to the pipeline (so failures abort instead of being silently warned), delete fully-redundant dead helpers, add automatic intermediate-file cleanup to the happy path, and provide a separate dry-run-default recovery wrapper for when the pipeline crashes mid-run.

**Architecture:** Three-layer separation with three different safety mechanisms. (1) Pipeline layer in `RCode/season_processor.R`: per-iteration `validate_team_count` and end-of-pipeline `validate_season_processing` both escalated to abort on failure. (2) Operator-wrapper layer in `scripts/season_transition.R`: list-based cleanup using `result$files_created` (no globs — *errors out of existence by construction*). (3) Recovery layer at new `scripts/season_transition/cleanup.R`: narrow regex (`^TeamList_<season>_League(78|79|80)\.csv$` only), dry-run default, `--confirm` to delete. Two dead functions (`create_processing_report`, `cleanup_processing_artifacts`) are deleted because they have zero callers and their use cases are already covered (existing log file; the new layer-specific cleanups).

**Tech Stack:** R 4.2+, `testthat` 3.x, plain `Rscript` CLI matching existing `scripts/` convention. No new dependencies. No shared library file.

**Spec:** `docs/prds/2026-05-08-issue-74-season-transition-operator-discoverability.md`

---

## File Structure

| Path | Action | Purpose |
|---|---|---|
| `tests/testthat/test-season-transition-cleanup-wrapper.R` | Create | 4 tests for the new recovery wrapper (dry-run, --confirm, ignores foreign files, zero matches) |
| `tests/testthat/test-season-transition-validators.R` | Create | 2 tests for the validator escalations (loop-iteration validate_team_count fails, end-of-pipeline validate_season_processing fails) |
| `RCode/season_processor.R` | Modify | (a) Line 196: `warning(...)` → `stop(...)` in `process_single_season`. (b) `process_season_transition`: add end-of-loop `validate_season_processing` call before successful return. (c) Delete `create_processing_report` (lines 573–617) and `cleanup_processing_artifacts` (lines 619–653). |
| `scripts/season_transition.R` | Modify | `main()`: after successful `process_season_transition` return, iterate `result$files_created`, remove every entry that is not the final `RCode/TeamList_<target_season>.csv`. ~10 lines added. |
| `scripts/season_transition/cleanup.R` | Create | New recovery wrapper script. Header doc comment, arg-parsing for `<season>` and `--confirm`, narrow regex match in `RCode/`, dry-run by default, three output formats (matches dry-run, matches confirmed, zero matches). |
| `docs/user-guide/season-transition.md` | Modify | (a) New section at end: "Recovery: Cleanup after a failed transition". (b) One-line addition under "Method 1: Automated Interactive Mode". |
| `CLAUDE.md` | Modify | New "Conventions" section before "Current Status" with the operator-helper-wrapping rule. |

---

## Pre-flight: How to run R tests

The test suite is invoked from the repo root:

```bash
Rscript -e 'testthat::test_dir("tests/testthat")'
```

To run a single file:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-cleanup-wrapper.R")'
```

The repo's existing pattern: each test file `source()`s the production code it needs at the top via `../../RCode/<module>.R` paths (relative to `tests/testthat/`). Follow that pattern.

`testthat` is already a project dependency. No `install.packages` needed.

---

## Task 1: Add the failing test file for the cleanup wrapper

Tests are written first so we watch them fail, then watch them pass after the implementation lands. The cleanup wrapper is a fresh file, so all four tests will fail with "file not found"-class errors initially.

**Files:**
- Create: `tests/testthat/test-season-transition-cleanup-wrapper.R`

- [ ] **Step 1: Write the four failing tests**

```r
# Tests for scripts/season_transition/cleanup.R recovery wrapper.
#
# Strategy: invoke the wrapper via Rscript in a subprocess against a temp dir
# that mimics RCode/. We use Rscript (not source()) because cleanup.R is a CLI
# script with quit() calls — sourcing it directly would terminate the test session.

library(testthat)

# Resolve project root from tests/testthat/ working dir.
project_root <- normalizePath(file.path("..", ".."), mustWork = TRUE)
cleanup_script <- file.path(project_root, "scripts", "season_transition", "cleanup.R")

# Helper: run cleanup.R in a temp dir, capture stdout.
run_cleanup <- function(tmp, season, confirm = FALSE) {
  args <- c(cleanup_script, season)
  if (confirm) args <- c(args, "--confirm")
  withr::with_dir(tmp, {
    output <- system2("Rscript", args, stdout = TRUE, stderr = TRUE)
  })
  paste(output, collapse = "\n")
}

# Helper: create a temp RCode/ with the given files (as relative paths).
setup_rcode <- function(files) {
  tmp <- tempfile("cleanup_test_")
  dir.create(file.path(tmp, "RCode"), recursive = TRUE)
  for (f in files) {
    full <- file.path(tmp, "RCode", f)
    file.create(full)
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

  output <- run_cleanup(tmp, "2099", confirm = FALSE)

  expect_match(output, "Would remove 3 files", fixed = TRUE)
  expect_match(output, "Use --confirm", fixed = TRUE)
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

  output <- run_cleanup(tmp, "2099", confirm = TRUE)

  expect_match(output, "Removed 3 files", fixed = TRUE)
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

  output <- run_cleanup(tmp, "2099", confirm = TRUE)

  expect_match(output, "Removed 3 files", fixed = TRUE)
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

  output <- run_cleanup(tmp, "2099", confirm = FALSE)

  expect_match(output, "No cleanup files found", fixed = TRUE)
  expect_match(output, "2099", fixed = TRUE)
})
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-cleanup-wrapper.R")'
```

Expected: 4 failures. The exact error mode will be one of:
- `system2` returning non-zero / stderr containing "cannot open file" (because `scripts/season_transition/cleanup.R` does not exist yet), or
- `expect_match` failing because the output is empty / contains an Rscript error message.

Either is acceptable as a "fail" — the point is they are not passing.

- [ ] **Step 3: Commit the failing tests**

```bash
git add tests/testthat/test-season-transition-cleanup-wrapper.R
git commit -m "$(cat <<'EOF'
test(#74): add failing tests for season-transition cleanup recovery wrapper

Covers dry-run default, --confirm deletion, foreign-file restriction,
and zero-matches explanatory message. The wrapper script does not exist
yet — these tests will be made to pass in a later task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add the failing test file for the validator escalations

These tests verify that `validate_team_count` failure inside `process_single_season` causes the function to return `success=FALSE` (instead of silently warning and returning success), and that `validate_season_processing` failure at the end of `process_season_transition` causes the orchestrator to return `success=FALSE`.

We use `mockery` for stubbing because the existing `test-season-processor.R` already uses it (`library(mockery)`).

**Files:**
- Create: `tests/testthat/test-season-transition-validators.R`

- [ ] **Step 1: Write the two failing tests**

```r
# Tests for the season-transition validator escalations introduced by issue #74.
#
# 1. process_single_season: validate_team_count failure must abort (return
#    success=FALSE), no longer just warn and return success=TRUE.
# 2. process_season_transition: validate_season_processing failure at end of
#    pipeline must produce success=FALSE.

library(testthat)
library(mockery)

source("../../RCode/season_processor.R")
source("../../RCode/input_validation.R")

test_that("process_single_season fails when validate_team_count rejects merged file", {
  # Stub all the network-and-CSV-touching helpers process_single_season calls
  # before validate_team_count. We only care that, when validate_team_count
  # returns valid=FALSE, the function returns success=FALSE.
  stub(process_single_season, "validate_season_completion", TRUE)
  stub(process_single_season, "load_previous_team_list", data.frame())
  stub(process_single_season, "calculate_final_elos", data.frame())
  stub(process_single_season, "calculate_liga3_relegation_baseline", 1100)
  stub(process_single_season, "fetch_all_leagues_teams", list("78" = list(list(id = 1))))
  stub(process_single_season, "process_league_teams", list(list(id = 1)))
  stub(process_single_season, "generate_league_csv", "RCode/TeamList_2099_League78.csv")
  stub(process_single_season, "merge_league_files", "RCode/TeamList_2099.csv")
  stub(process_single_season, "get_league_name", "Bundesliga")
  stub(process_single_season, "validate_team_count", list(
    valid = FALSE,
    message = "Too few teams: 5 - expected at least 56"
  ))

  result <- process_single_season("2099", "2098")

  expect_false(result$success)
  expect_match(result$error, "Too few teams", fixed = TRUE)
})

test_that("process_season_transition fails when end-of-pipeline validate_season_processing rejects target season", {
  # Stub the inner pipeline so the loop succeeds, but make the new end-of-pipeline
  # validate_season_processing call return valid=FALSE.
  stub(process_season_transition, "display_welcome_message", invisible(NULL))
  stub(process_season_transition, "validate_season_range", invisible(NULL))
  stub(process_season_transition, "validate_api_access", TRUE)
  stub(process_season_transition, "get_seasons_to_process", "2099")
  stub(process_season_transition, "process_single_season", list(
    success = TRUE,
    teams_processed = 60,
    files_created = c("RCode/TeamList_2099.csv")
  ))
  stub(process_season_transition, "display_progress", invisible(NULL))
  stub(process_season_transition, "display_season_summary", invisible(NULL))
  stub(process_season_transition, "display_completion_message", invisible(NULL))
  stub(process_season_transition, "validate_season_processing", list(
    valid = FALSE,
    message = "Duplicate team IDs found"
  ))

  result <- process_season_transition("2098", "2099")

  expect_false(result$success)
  expect_match(result$error, "Duplicate team IDs", fixed = TRUE)
})
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-validators.R")'
```

Expected: 2 failures. The current code:
- For test 1: `process_single_season` only calls `warning(...)` on `validate_team_count` failure and continues to `return(list(success = TRUE, ...))`. Test expects `success = FALSE` — fails.
- For test 2: `process_season_transition` does not call `validate_season_processing` at all. The stubbed `validate_season_processing` is never invoked, so the function returns `success = TRUE` from the loop's natural completion. Test expects `success = FALSE` — fails.

- [ ] **Step 3: Commit the failing tests**

```bash
git add tests/testthat/test-season-transition-validators.R
git commit -m "$(cat <<'EOF'
test(#74): add failing tests for pipeline validator escalations

Pins the new behavior: validate_team_count failure must abort
process_single_season (instead of silent warning), and an end-of-pipeline
validate_season_processing failure must abort process_season_transition.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Escalate `validate_team_count` warning to stop in `process_single_season`

The smallest implementation step: change exactly one line. The outer `tryCatch` in `process_single_season` (line 208) catches the `stop()` and converts it to `list(success = FALSE, error = ...)` — which is exactly what test 1 from Task 2 expects.

**Files:**
- Modify: `RCode/season_processor.R:194-197`

- [ ] **Step 1: Read the current code to confirm exact text**

The exact block to replace is at lines 194–197:

```r
      # Validate team count
      team_count_validation <- validate_team_count(merged_file)
      if (!team_count_validation$valid) {
        warning(team_count_validation$message)
      }
```

- [ ] **Step 2: Replace `warning` with `stop`**

```r
      # Validate team count
      team_count_validation <- validate_team_count(merged_file)
      if (!team_count_validation$valid) {
        stop(team_count_validation$message)
      }
```

The semantic difference: `stop` propagates as an error condition. The outer `tryCatch(... error = function(e) { return(list(success = FALSE, error = e$message)) })` at line 208 catches it and converts it to a structured failure return. No R session crash, just `success = FALSE` with a meaningful error message.

- [ ] **Step 3: Run the validator tests**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-validators.R")'
```

Expected: test 1 passes ("process_single_season fails when validate_team_count rejects merged file"), test 2 still fails. 1/2 tests green.

- [ ] **Step 4: Run the existing team-count-validation tests as a regression check**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-team-count-validation.R")'
```

Expected: all 6 tests pass. We did not change `validate_team_count` itself — only how its result is consumed.

- [ ] **Step 5: Commit**

```bash
git add RCode/season_processor.R
git commit -m "$(cat <<'EOF'
fix(#74): escalate validate_team_count failure to stop

A failed team-count check inside process_single_season previously emitted
only warning(), which is invisible in --non-interactive mode and let the
pipeline declare success on a broken merged CSV. Replacing with stop()
lets the outer tryCatch convert the failure to success=FALSE in the
returned list, matching the structured-failure pattern already in use.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add end-of-pipeline `validate_season_processing` call in `process_season_transition`

Inside `process_season_transition`, after the for-loop completes successfully, before `display_completion_message`. We add a call to `validate_season_processing(target_season)`. On `valid=FALSE`, we abort the function via `stop()` so the outer `tryCatch` at line 95 converts it to a failure return.

**Files:**
- Modify: `RCode/season_processor.R` — `process_season_transition` (around line 86)

- [ ] **Step 1: Read the current code to confirm exact text**

Lines 84–93 currently read:

```r
    }
    
    # Display completion message
    display_completion_message(seasons_processed, files_created)
    
    return(list(
      success = TRUE,
      seasons_processed = seasons_processed,
      files_created = files_created
    ))
```

Note: this block is inside the outer `tryCatch` of `process_season_transition` (the one whose error handler is at line 95–101 — `cat("Season transition failed:", ...)` and `return(list(success = FALSE, error = e$message))`).

- [ ] **Step 2: Insert the end-of-pipeline validation**

Replace those lines with:

```r
    }
    
    # End-of-pipeline validation: assert the produced target season is well-formed
    final_validation <- validate_season_processing(target_season)
    if (!final_validation$valid) {
      stop(final_validation$message)
    }
    
    # Display completion message
    display_completion_message(seasons_processed, files_created)
    
    return(list(
      success = TRUE,
      seasons_processed = seasons_processed,
      files_created = files_created
    ))
```

- [ ] **Step 3: Run the validator tests**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-validators.R")'
```

Expected: both tests pass. 2/2 green.

- [ ] **Step 4: Run the existing snapshot test as a regression check**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")'
```

Expected: passes. The snapshot's recorded run produces a valid `TeamList_2025.csv`, so `validate_season_processing("2025")` returns `valid=TRUE` and our new `stop()` is not triggered. (If this fails, the new validator is rejecting a legitimately-valid CSV — investigate before continuing.)

- [ ] **Step 5: Commit**

```bash
git add RCode/season_processor.R
git commit -m "$(cat <<'EOF'
feat(#74): validate target season at end of process_season_transition

After the per-season loop completes, before declaring success, run
validate_season_processing against the target season. On failure, abort
via stop() so the outer tryCatch returns success=FALSE structurally.
This wires up an existing-but-uncalled validator into the success path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Delete the two dead functions from `season_processor.R`

`create_processing_report` (lines 573–617) and `cleanup_processing_artifacts` (lines 619–653) have zero callers across `RCode/`, `scripts/`, and `tests/`. Their use cases are covered elsewhere (the existing `processing_<from>_to_<to>.log` written by `create_processing_log`; the new layer-specific cleanup paths from this PRD). Deleting them removes dead code that imposes maintenance cost without value.

**Files:**
- Modify: `RCode/season_processor.R:573-653`

- [ ] **Step 1: Verify zero callers one more time before deletion**

```bash
grep -rn "create_processing_report\|cleanup_processing_artifacts" RCode/ scripts/ tests/
```

Expected output: only the two function definitions themselves at `RCode/season_processor.R:573` and `RCode/season_processor.R:619`. No callers.

If any caller appears: STOP and reassess. Do not proceed with deletion.

- [ ] **Step 2: Read lines 570–660 to confirm exact extent**

The block to remove is exactly:

- Line 573 starts with `create_processing_report <- function(...)`
- The function ends at line 617 with the closing `}`
- Line 618 is blank
- Line 619 starts with `cleanup_processing_artifacts <- function(...)`
- The function ends at line 653 with the closing `}`
- Line 654 is the file's EOF or a trailing newline

Use Read to confirm before editing.

- [ ] **Step 3: Delete both functions and their separator blank line**

Use Edit to remove the block from `create_processing_report <- function(source_season, target_season, processing_results) {` through the closing `}` of `cleanup_processing_artifacts`. The file should end after the closing `}` of `validate_season_processing` (line 571).

- [ ] **Step 4: Run the full test suite as a regression check**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: all tests pass that were passing before. No new failures.

- [ ] **Step 5: Commit**

```bash
git add RCode/season_processor.R
git commit -m "$(cat <<'EOF'
refactor(#74): delete dead season_processor helpers

create_processing_report and cleanup_processing_artifacts have zero
callers and their use cases are covered elsewhere: the existing
processing_<from>_to_<to>.log written by create_processing_log captures
the same information as the JSON report would have, and the broad-glob
cleanup is being replaced by layer-specific cleanups (auto-cleanup in
the operator wrapper for the happy path; a narrow recovery wrapper at
scripts/season_transition/cleanup.R for the failure path).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add automatic intermediate-file cleanup to `scripts/season_transition.R::main`

After a successful `process_season_transition` return, iterate `result$files_created`, remove every entry that is not the final `RCode/TeamList_<target_season>.csv`. Cleanup failures log a warning but do not abort the run (the work is done; tidying up is courtesy).

**Files:**
- Modify: `scripts/season_transition.R` — inside the `tryCatch` block of `main()` (around lines 219–223)

- [ ] **Step 1: Read the current success branch of `main`**

Lines 219–225 currently read:

```r
    if (result$success) {
      cat("\n=== Season Transition Complete ===\n")
      cat("Seasons processed:", result$seasons_processed, "\n")
      cat("Files created:", length(result$files_created), "\n")
      cat("All team lists have been generated successfully.\n")
    } else {
      stop(paste("Season transition failed:", result$error))
    }
```

- [ ] **Step 2: Add cleanup before the completion banner**

Replace the success branch with:

```r
    if (result$success) {
      # Auto-cleanup of intermediate league CSVs. The final TeamList is kept;
      # everything else in result$files_created is removed. List-based deletion:
      # we only touch files the pipeline reports as having created — no globs.
      final_file <- file.path("RCode", paste0("TeamList_", target_season, ".csv"))
      intermediates <- setdiff(result$files_created, final_file)
      removed <- 0
      for (f in intermediates) {
        if (file.exists(f)) {
          if (file.remove(f)) {
            removed <- removed + 1
          } else {
            warning(paste("Could not remove intermediate file:", f))
          }
        }
      }
      
      cat("\n=== Season Transition Complete ===\n")
      cat("Seasons processed:", result$seasons_processed, "\n")
      cat("Files created:", length(result$files_created), "\n")
      cat("Intermediate files removed:", removed, "\n")
      cat("All team lists have been generated successfully.\n")
    } else {
      stop(paste("Season transition failed:", result$error))
    }
```

- [ ] **Step 3: Run the snapshot test as a regression check**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")'
```

Expected: passes. The snapshot test calls `process_season_transition` directly, not via `main`, so this change is invisible to it.

- [ ] **Step 4: Run the full test suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: all tests pass. The two new validator tests (Task 2) and the four cleanup-wrapper tests (Task 1) — those still fail because cleanup.R doesn't exist yet (Task 7) — but the validator tests should be green from Tasks 3-4.

If a previously-passing test now fails: investigate before committing.

- [ ] **Step 5: Commit**

```bash
git add scripts/season_transition.R
git commit -m "$(cat <<'EOF'
feat(#74): auto-clean intermediate league CSVs after successful transition

After process_season_transition returns success, main() now removes every
file in result\$files_created except the final TeamList_<target>.csv. The
deletion is list-based — only files the pipeline declared as having
created — so it is bounded by construction and cannot remove unrelated
files. Cleanup failures warn but do not abort.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Create the recovery wrapper `scripts/season_transition/cleanup.R`

The new file. Self-contained. Implements: arg-parsing for `<season>` and `--confirm`, narrow regex match in `RCode/`, dry-run by default, three output formats (matches dry-run, matches confirmed, zero matches).

**Files:**
- Create: `scripts/season_transition/cleanup.R`

- [ ] **Step 1: Verify the parent directory does not yet exist**

```bash
ls scripts/season_transition/ 2>&1
```

Expected: `No such file or directory`. The directory will be created implicitly when we Write the file at this nested path.

- [ ] **Step 2: Write the wrapper**

```r
#!/usr/bin/env Rscript

# Cleanup-Wrapper for incomplete season transitions.
#
# Removes intermediate league CSVs (TeamList_<season>_League<78|79|80>.csv)
# left behind when scripts/season_transition.R aborts before merging.
#
# When to use: only after a failed season transition. The successful path
# cleans up automatically — running this manually is a recovery tool.
#
# Does NOT touch: TeamList_<season>.csv (final), .tmp, .lock, or any file
# outside RCode/.
#
# Usage:
#   Rscript scripts/season_transition/cleanup.R 2025          # dry-run
#   Rscript scripts/season_transition/cleanup.R 2025 --confirm

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  cat("Usage: Rscript scripts/season_transition/cleanup.R <season> [--confirm]\n")
  quit(status = 1)
}

season <- args[1]
confirm <- "--confirm" %in% args[-1]

if (!grepl("^[0-9]{4}$", season)) {
  cat("Error: season must be a 4-digit year (e.g., 2025)\n")
  quit(status = 1)
}

# Narrow regex: match exactly the intermediate files the pipeline produces
# via generate_league_csv for leagues 78 (Bundesliga), 79 (2. Bundesliga),
# 80 (3. Liga). The final TeamList_<season>.csv is intentionally NOT matched.
pattern <- paste0("^TeamList_", season, "_League(78|79|80)\\.csv$")
search_dir <- "RCode"

matches <- list.files(search_dir, pattern = pattern, full.names = TRUE)

if (length(matches) == 0) {
  cat("No cleanup files found for season ", season, ".\n", sep = "")
  cat("(Searched ", search_dir, "/ for TeamList_", season,
      "_League(78|79|80).csv)\n", sep = "")
  quit(status = 0)
}

if (!confirm) {
  cat("Cleanup dry-run for season ", season, "\n", sep = "")
  cat("Pattern: TeamList_", season, "_League(78|79|80).csv in ",
      search_dir, "/\n", sep = "")
  cat("Would remove ", length(matches), " files:\n", sep = "")
  for (f in matches) cat("  ", f, "\n", sep = "")
  cat("Use --confirm to actually delete.\n")
  quit(status = 0)
}

# Confirmed: delete and report.
cat("Cleanup for season ", season, "\n", sep = "")
removed <- character(0)
for (f in matches) {
  if (file.remove(f)) {
    removed <- c(removed, f)
  } else {
    warning(paste("Could not remove:", f))
  }
}
cat("Removed ", length(removed), " files:\n", sep = "")
for (f in removed) cat("  ", f, "\n", sep = "")
quit(status = 0)
```

- [ ] **Step 3: Run the cleanup-wrapper tests**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-cleanup-wrapper.R")'
```

Expected: all 4 tests pass.

If a test fails: read the test's expected output strings and the wrapper's actual output side-by-side. Common pitfalls:
- `expect_match(..., fixed = TRUE)` is strict about whitespace. The output strings must match exactly.
- `system2(stdout = TRUE, stderr = TRUE)` captures both streams; if `Rscript` itself errors before our code runs, the captured text is the R interpreter error message.

- [ ] **Step 4: Run the full test suite as a regression check**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: all tests pass. Test status delta from start of plan: +6 (the four wrapper tests, the two validator tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/season_transition/cleanup.R
git commit -m "$(cat <<'EOF'
feat(#74): add recovery wrapper for incomplete season transitions

scripts/season_transition/cleanup.R is the manual safety net for the
case where scripts/season_transition.R aborts before its own auto-cleanup
runs. Restrictions match the PRD: narrow regex
(TeamList_<season>_League(78|79|80).csv only, in RCode/), dry-run
default, --confirm to actually delete, explanatory zero-matches output
so silence is never confused for a tool failure.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Update `docs/user-guide/season-transition.md`

Two changes: a one-line note added to "Method 1: Automated Interactive Mode" and a new "Recovery: Cleanup after a failed transition" section appended at the end of the document.

**Files:**
- Modify: `docs/user-guide/season-transition.md`

- [ ] **Step 1: Read the current "Method 1" section to locate insertion point**

Lines 32–45 read:

```markdown
### Method 1: Automated Interactive Mode

Best for: Administrators who can respond to prompts

```bash
# Run interactively
docker-compose exec -it league-simulator \
  Rscript scripts/season_transition.R 2024 2025

# You will be prompted for:
# - Confirmation to proceed
# - New team information
# - Validation of changes
```

```

- [ ] **Step 2: Add the one-line auto-cleanup/auto-validation note at the end of the Method 1 code block**

After the closing `` ``` `` of the code block (after line 45), add a new line:

```markdown
On success, the script validates the produced `TeamList_<target>.csv` and removes intermediate league files automatically.
```

The Method 1 section then reads:

```markdown
### Method 1: Automated Interactive Mode

Best for: Administrators who can respond to prompts

```bash
# Run interactively
docker-compose exec -it league-simulator \
  Rscript scripts/season_transition.R 2024 2025

# You will be prompted for:
# - Confirmation to proceed
# - New team information
# - Validation of changes
```

On success, the script validates the produced `TeamList_<target>.csv` and removes intermediate league files automatically.
```

- [ ] **Step 3: Append the new "Recovery" section at the end of the file**

Append (with a blank line separator before it) the following section at the very end of `docs/user-guide/season-transition.md`:

```markdown

## Recovery: Cleanup after a failed transition

If `scripts/season_transition.R` aborts mid-run (network failure, validation rejection, manual interrupt), intermediate per-league CSV files may remain in `RCode/`. Use the recovery wrapper to remove them:

```bash
# Dry-run (default): list files that would be removed, do not delete
Rscript scripts/season_transition/cleanup.R 2025

# Actually delete
Rscript scripts/season_transition/cleanup.R 2025 --confirm
```

The wrapper only matches files of the form `TeamList_<season>_League(78|79|80).csv` in `RCode/`. It does **not** touch:

- `RCode/TeamList_<season>.csv` (the final season file)
- Any `.tmp` or `.lock` files
- Anything outside `RCode/`
- Files for other seasons

You normally do not need to run this manually — the main script auto-cleans intermediate files on successful runs. This wrapper exists for the failure-recovery case.
```

- [ ] **Step 4: Sanity-check the document renders**

There is no doc-build step in this repo, so the verification is to read the modified file and confirm:
- The Method 1 addition is on its own line directly after the closing `` ``` `` of the code block, with no extra blank lines confusing the section structure.
- The Recovery section appears at the very end, has its own `##` heading (matching the document's existing heading hierarchy — `##` is used for top-level sections), and the code blocks have correct triple-backtick fencing.

```bash
tail -40 docs/user-guide/season-transition.md
```

Eyeball the output for correctness.

- [ ] **Step 5: Commit**

```bash
git add docs/user-guide/season-transition.md
git commit -m "$(cat <<'EOF'
docs(#74): document auto-cleanup and add recovery wrapper section

Method 1 now mentions the auto-validation and auto-cleanup that happens
on a successful run. A new "Recovery: Cleanup after a failed transition"
section at the end of the guide documents
scripts/season_transition/cleanup.R, its dry-run default and --confirm
flag, and the explicit list of files it does not touch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Add the "Conventions" section to `CLAUDE.md`

A single-rule section, inserted before the existing "Current Status" section, capturing the structural lesson from this issue so the next time someone adds an operator-facing helper they wire it up correctly from the start.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read the current end of `CLAUDE.md` to locate insertion point**

The current "Current Status" section (final non-empty section in the file) reads:

```markdown
## Current Status

- **Season**: 2024-2025
- **API**: api-football via RapidAPI
```

We insert the new section directly above this.

- [ ] **Step 2: Insert the new "Conventions" section**

Use Edit to replace:

```markdown
## Current Status

- **Season**: 2024-2025
- **API**: api-football via RapidAPI
```

with:

```markdown
## Conventions

When adding helper functions in `RCode/` that operators run outside the production call graph: provide a `scripts/` wrapper, document it in `docs/user-guide/`, default destructive operations to dry-run with explicit `--confirm`.

## Current Status

- **Season**: 2024-2025
- **API**: api-football via RapidAPI
```

- [ ] **Step 3: Sanity-check**

```bash
tail -15 CLAUDE.md
```

Confirm the new section is present and the section order is "Conventions" → "Current Status".

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(#74): add Conventions section for operator-helper wrapping

Future helper functions in RCode/ that operators run outside the
production call graph need a scripts/ wrapper, documentation in
docs/user-guide/, and dry-run-default for destructive operations. This
captures the structural lesson from issue #74 so the next maintainer
does not rediscover it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Final verification — full regression and manual smoke test

The PRD's headline acceptance criterion: **test status before == test status after**, plus the six new tests passing.

**Files:** none (verification only)

- [ ] **Step 1: Full test suite green**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: all tests pass. Six tests are new (4 cleanup-wrapper, 2 validator). The existing snapshot test, `validate_team_count` tests, and everything else remain green.

- [ ] **Step 2: Confirm no new test failures relative to the pre-#74 baseline**

```bash
git stash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -10 > /tmp/before.txt
git stash pop
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -10 > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
```

Expected: the diff shows only the six new tests in the after-output, no previously-passing test now failing. (If `git stash` and `git stash pop` round-trip leaves the working tree dirty for some reason, abort this step and inspect manually.)

- [ ] **Step 3: Manual smoke test of the recovery wrapper against fake data**

```bash
# Create three fake intermediate files in a season we don't use:
mkdir -p /tmp/cleanup-smoke/RCode
cd /tmp/cleanup-smoke
touch RCode/TeamList_2099_League78.csv
touch RCode/TeamList_2099_League79.csv
touch RCode/TeamList_2099_League80.csv
touch RCode/TeamList_2099.csv   # final-season decoy that must NOT be deleted
touch RCode/random.tmp          # foreign-file decoy
ls RCode/

# Dry-run:
Rscript "$OLDPWD/scripts/season_transition/cleanup.R" 2099
ls RCode/
# Expected: all 5 files still present; output lists 3 matches.

# --confirm:
Rscript "$OLDPWD/scripts/season_transition/cleanup.R" 2099 --confirm
ls RCode/
# Expected: only TeamList_2099.csv and random.tmp remain.

# Zero-matches re-run:
Rscript "$OLDPWD/scripts/season_transition/cleanup.R" 2099
# Expected: "No cleanup files found for season 2099." plus search-pattern hint.

cd "$OLDPWD"
rm -rf /tmp/cleanup-smoke
```

- [ ] **Step 4: Verify the deleted dead functions are gone**

```bash
grep -n "create_processing_report\|cleanup_processing_artifacts" RCode/season_processor.R
```

Expected: empty output. Both functions are gone.

- [ ] **Step 5: Verify the `Conventions` section made it into `CLAUDE.md`**

```bash
grep -A 2 "^## Conventions" CLAUDE.md
```

Expected: the heading and the rule line.

- [ ] **Step 6: Final report — no commit**

This task is verification only; everything actionable was committed in earlier tasks. State done.

---

## What did not change

For the next reviewer's benefit, this is the explicit "we considered but did not touch" list:

- `RCode/input_validation.R::validate_team_count` — unchanged. We changed how `process_single_season` *reacts* to its result (warning → stop), not the function itself. Its existing six tests in `test-team-count-validation.R` still apply unchanged.
- `RCode/season_processor.R::validate_season_processing` — unchanged. We added a *call* from `process_season_transition`. The function body is untouched.
- `RCode/logging.R` — unchanged. The decision to delete `create_processing_report` rests on the existing `create_processing_log` already covering the same use case (operator debugging after a failed run).
- `README.md` — unchanged. The existing pointer at line 36 to `docs/user-guide/season-transition.md` already directs operators to the right place.
- `scripts/season_transition.R::main` arg-parsing and module-loading — unchanged. The only addition is the post-success cleanup block.
- The existing snapshot test (`test-season-transition-csv-snapshot.R`, fixture under `tests/testthat/fixtures/season-transition-2024-to-2025/`) — unchanged. It calls `process_season_transition` directly, bypassing `main`, so the auto-cleanup is invisible to it. The end-of-pipeline `validate_season_processing` runs against the snapshot's recorded data and passes, so no re-recording is needed.
