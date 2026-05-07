# Retire C++ Simulation Engine (Issue #102, Option B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the entire C++ simulation engine (5 R wrappers, 1 `.cpp` primitive, 1 generated `RcppExports.R`, plus the `Rcpp` build dependency) and consolidate season-transition ELO calculations on the pure-R `calculate_elo_update` path. The Rust seam at `localhost:8080` is then the only simulation engine and `calculate_elo_update` is the only ELO-update primitive.

**Architecture:** The PRD at `docs/prds/2026-05-03-simulation-engine-seam-phase-2.md` originally recommended Option A (keep `.cpp` as the ELO primitive). Issue #102 supersedes that recommendation: the regression net merged in PR #100 (`tests/testthat/test-elo-aggregation-engine-selection.R`, scenario sweep) empirically proved that `SpielNichtSimulieren.cpp` and `calculate_elo_update` produce byte-identical ELOs across 5 scenarios. The C++ primitive and its Rcpp dependency therefore add zero observable value. This plan executes Option B: keep `calculate_elo_update`, drop everything Rcpp-related, and remove the silent-fallback `if (exists("SpielNichtSimulieren"))` guard in `RCode/elo_aggregation.R` so engine selection is no longer correctness-by-coincidence. The `update_league.R` orphan file is deleted alongside the wrappers it depends on (it is the only remaining caller of `leagueSimulatorCPP` and is already in the #86 deletion pile; co-deleting avoids a deliberately-broken intermediate state).

**Tech Stack:** R 4.3.1, testthat 3.x, no new dependencies. `Rcpp` removed from `packagelist.txt` and `Dockerfile`. The Rust crate at `league-simulator-rust/` is unchanged.

---

## File Structure

**Delete (10 R files + 1 cpp + 7 test/tooling + 2 manifests = 20 files):**

```
RCode/SpielCPP.R                              # wrapper tower
RCode/simulationsCPP.R                        # wrapper tower
RCode/SaisonSimulierenCPP.R                   # wrapper tower
RCode/leagueSimulatorCPP.R                    # wrapper tower entry point
RCode/cpp_wrappers.R                          # output reshapers (no callers)
RCode/RcppExports.R                           # auto-generated Rcpp glue
RCode/SpielNichtSimulieren.cpp                # C++ ELO primitive (Option B drops it)
RCode/update_league.R                         # orphan microservices file, only caller of leagueSimulatorCPP
tests/testthat/test-spielcpp-contract.R       # contract test for soon-deleted SpielCPP
tests/testthat/test-SpielNichtSimulieren.R    # 11 tests against the soon-deleted .cpp
tests/rust/test_rust_vs_cpp_detailed.R        # comparison harness
tests/rust/calculate_matrix_differences.R     # comparison harness
compare_rust_cpp.R                            # comparison harness
compare_rust_vs_r.R                           # comparison harness
compare_working.R                             # comparison harness
tests/single_match_test.R                     # tooling, sources SpielCPP.R
tests/test_rust_integration.R                 # tooling, sources the wrapper tower
tests/verify_parameters.R                     # tooling, sources SpielCPP.R
tests/check_played_matches.R                  # tooling
tests/verify_home_advantage.R                 # tooling, references SpielCPP commentary only
RCode/deployment_files_league.txt             # manifest for already-deleted Dockerfile.league
RCode/deployment_files_shiny.txt              # manifest for already-deleted Dockerfile.shiny
```

**Modify:**

```
RCode/elo_aggregation.R                       # remove exists() guard, probe block, C++ branch
scripts/season_transition.R                   # remove "SpielCPP.R" from existing_modules
scripts/install_test_packages.R               # remove sourceCpp("RCode/SpielNichtSimulieren.cpp") verify step
tests/testthat/test-elo-aggregation-engine-selection.R   # collapse to R-only assertions
tests/testthat/test-season-transition-csv-snapshot.R     # remove probe assertion, keep CSV byte check
tests/testthat/helper-test-setup.R            # remove compile_cpp_files() block
packagelist.txt                               # remove "Rcpp"
Dockerfile                                    # remove 'Rcpp' from core_pkgs and already_installed
docs/prds/2026-05-03-simulation-engine-seam-phase-2.md   # add note: Option B was chosen, link to this plan
```

**Manifest deletions (`deployment_files_*.txt`)** are folded into this plan because they reference the wrapper tower files we're deleting; they would otherwise become stale pointers. Issue #86 lists them too — co-deleting here means #86 has nothing left to do for these two files.

---

## Pre-flight Verification (no commits, just reads)

### Task 0: Verify the empirical baseline still holds

**Why:** This plan's safety hinges on PR #100's finding that C++ and R formulas produce byte-identical ELOs. Re-confirm before any deletion. Also confirms that the season-transition CSV snapshot in PR #100 was captured with the R fallback path (probe = `FALSE`) — meaning Option B does not change observable behavior, it just removes the unused C++ branch.

**Files:**
- Read: `tests/testthat/test-elo-aggregation-engine-selection.R` (the cross-engine sweep)
- Read: `tests/testthat/test-season-transition-csv-snapshot.R` (the byte-identical CSV pin)
- Read: `tests/testthat/fixtures/season-transition-2024-to-2025/TeamList_2025.csv.snapshot` (what's pinned)

- [ ] **Step 1: Run the engine-selection regression suite from the worktree root**

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update.issue-102-retire-cpp"
Rscript -e 'testthat::test_file("tests/testthat/test-elo-aggregation-engine-selection.R")'
```

Expected output: 5 PASS (or 3 PASS + 2 SKIP if `Rcpp` cannot compile in this environment — that itself is informative). The third test ("C++ and R fallback engines produce equivalent ELO updates across a parameter sweep") must pass to validate Option B.

- [ ] **Step 2: Run the season-transition CSV snapshot test**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")'
```

Expected: PASS. Probe value is `FALSE` (the subprocess does not source `.cpp`). CSV bytes match the pinned snapshot.

- [ ] **Step 3: Decision gate**

If both runs are green, Option B is safe to execute. Continue to Task 1.

If either fails, **stop and report**. Either the empirical baseline has drifted, or the test environment is broken; both invalidate this plan's assumptions and require a different approach (likely Option A — keep the `.cpp`).

No commit in this task.

---

## Phase 1: Make engine selection explicit (no behavior change yet)

### Task 1: Remove the `exists()` silent fallback from `RCode/elo_aggregation.R`

**Why:** Today `update_elos_for_match` silently chooses between C++ and R based on whether `SpielNichtSimulieren` happens to be in scope. After this task, R is the only path and it is the path *every* caller already gets. No file deletion yet — we land the load-bearing correctness improvement first, in isolation.

**Files:**
- Modify: `RCode/elo_aggregation.R:206-260` (function body of `update_elos_for_match`)
- Modify: `tests/testthat/test-elo-aggregation-engine-selection.R` (remove probe tests, simplify to R-path only)
- Modify: `tests/testthat/test-season-transition-csv-snapshot.R` (remove probe assertion block)

- [ ] **Step 1: Write the new test for `update_elos_for_match`**

Replace the entire content of `tests/testthat/test-elo-aggregation-engine-selection.R` with this. The five existing tests (C++ path, R-path, sweep, probe-set, probe-unset) become two: a happy-path R assertion, and a confirmation that no Rcpp dependency is reachable.

```r
# Engine-selection regression net for update_elos_for_match.
#
# Phase-2 Option B (issue #102) collapsed elo_aggregation.R onto the pure-R
# calculate_elo_update path. This file used to pin the C++/R cross-engine
# equivalence (PR #100); after the C++ engine deletion it pins only the R path.
#
# The original engine-equivalence sweep is preserved in git history at the
# pre-deletion commit; rerun it before reintroducing any non-R ELO engine.

library(testthat)

fixture_match <- function() {
  data.frame(
    teams_home_id = 1L,
    teams_away_id = 2L,
    goals_home = 2,
    goals_away = 0,
    stringsAsFactors = FALSE
  )
}

fixture_elos <- function() {
  data.frame(
    TeamID = c(1L, 2L),
    CurrentELO = c(1500, 1500),
    stringsAsFactors = FALSE
  )
}

test_that("update_elos_for_match returns expected ELOs via the R primitive", {
  result <- update_elos_for_match(fixture_elos(), fixture_match())

  # Hand-computed from calculate_elo_update with k_factor=20, home_advantage=100,
  # ELOs (1500, 1500), goals (2, 0):
  #   elo_diff       = 1500 - 1500 - 100 = -100, clamped to [-400,400] = -100
  #   expected_prob  = 1 / (1 + 10^(-100/400)) = 0.6400649...
  #   goal_diff      = 2 - 0 = 2
  #   actual_result  = (sign(2) + 1) / 2 = 1.0
  #   goal_modifier  = sqrt(max(abs(2),1)) = sqrt(2) = 1.41421356...
  #   elo_change     = (1.0 - 0.6400649) * 1.41421356 * 20 = 10.18028...
  expected_home <- 1500 + 10.18028
  expected_away <- 1500 - 10.18028

  expect_equal(result$CurrentELO[result$TeamID == 1L], expected_home, tolerance = 1e-4)
  expect_equal(result$CurrentELO[result$TeamID == 2L], expected_away, tolerance = 1e-4)
})

test_that("calculate_elo_update is the only ELO primitive in scope", {
  # After issue #102 / Option B, no compiled C++ ELO function should be
  # reachable. SpielNichtSimulieren must NOT exist — if a future change
  # reintroduces it, this test surfaces it.
  expect_false(exists("SpielNichtSimulieren"),
               info = "SpielNichtSimulieren was deleted in #102 / Option B")
  expect_true(exists("calculate_elo_update"),
              info = "calculate_elo_update is the load-bearing ELO primitive")
})
```

- [ ] **Step 2: Run the test — it should fail because the old probe code still exists**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-elo-aggregation-engine-selection.R")'
```

Expected: First test passes (R path is correct). Second test FAILS because either `SpielNichtSimulieren` got loaded by `helper-test-setup.R` or `RcppExports.R` declared it. This is the expected red.

- [ ] **Step 3: Edit `RCode/elo_aggregation.R` to remove the probe and the C++ branch**

Replace the body of `update_elos_for_match` (currently at lines 206–260, a 55-line function with `if (exists(...))` and a probe block) with this minimal version:

```r
update_elos_for_match <- function(current_elos, match) {
  # Update ELO ratings based on a single match result.
  # Calls calculate_elo_update, the only ELO primitive after issue #102.

  home_team_id <- match$teams_home_id
  away_team_id <- match$teams_away_id
  goals_home <- match$goals_home
  goals_away <- match$goals_away

  home_elo <- current_elos$CurrentELO[current_elos$TeamID == home_team_id]
  away_elo <- current_elos$CurrentELO[current_elos$TeamID == away_team_id]

  if (length(home_elo) == 0 || length(away_elo) == 0) {
    warning(paste("Team not found in ELO data for match:", home_team_id, "vs", away_team_id))
    return(current_elos)
  }

  new_elos <- calculate_elo_update(home_elo[1], away_elo[1], goals_home, goals_away)

  current_elos$CurrentELO[current_elos$TeamID == home_team_id] <- new_elos$home_elo
  current_elos$CurrentELO[current_elos$TeamID == away_team_id] <- new_elos$away_elo

  return(current_elos)
}
```

The `calculate_elo_update` function below (lines 262–290) stays unchanged — it is the load-bearing primitive now.

- [ ] **Step 4: Edit `tests/testthat/test-season-transition-csv-snapshot.R` to remove the probe assertion block**

Find this block (around lines 80–93):

```r
  # Gap #3: probe assertion. Subprocess does NOT load SpielNichtSimulieren.cpp
  # (the script's module list does not include the .cpp source). This pins
  # current truth — Phase-2 must take this into account.
  expect_true(file.exists(probe_path),
              info = "probe file should be written by elo_aggregation.R")
  engine_available <- readLines(probe_path)[1]
  expect_true(engine_available %in% c("TRUE", "FALSE"),
              info = "probe value must be TRUE or FALSE")
  expect_equal(engine_available, "FALSE",
    info = paste("Recorded current truth: scripts/season_transition.R does NOT",
                 "source SpielNichtSimulieren.cpp, so the C++ primitive is",
                 "unavailable in the script's process. If this changed, the",
                 "Phase-2 PRD's plan must be revisited."))
```

Delete the entire block (the three `expect_*` calls and the comment). Also delete the lines that set up the probe:

```r
  probe_path <- tempfile(fileext = ".txt")
```

```r
    SEASON_TRANSITION_ENGINE_PROBE = probe_path
```

```r
    unlink(probe_path)
```

```r
  args    = c(runner_path, project_root, csv_dir, probe_path, fixture_dir),
```

The runner argument list shrinks by one. Change it to:

```r
  args    = c(runner_path, project_root, csv_dir, fixture_dir),
```

Open `tests/testthat/helpers/season-transition-snapshot-runner.R` and adjust its argument parsing accordingly — it will be one positional arg shorter. (Read the file first; if the probe arg has any other use, document it. If unused after the runner just passes it through, simply drop the parameter.)

- [ ] **Step 5: Run both engine-selection and CSV snapshot tests to confirm green**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-elo-aggregation-engine-selection.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")'
```

Expected: All assertions pass. The CSV snapshot test continues to pass byte-identical because the path the subprocess took before was already pure-R (probe was `FALSE`); after this commit it's still pure-R, just no longer hidden behind a guard.

- [ ] **Step 6: Run the full testthat suite to catch any other dependents**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -30
```

Expected: `test-spielcpp-contract.R` and `test-SpielNichtSimulieren.R` still pass for now (they source the to-be-deleted files directly; that gets handled in Phase 2). All other tests are green.

- [ ] **Step 7: Commit**

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update.issue-102-retire-cpp"
git add RCode/elo_aggregation.R \
        tests/testthat/test-elo-aggregation-engine-selection.R \
        tests/testthat/test-season-transition-csv-snapshot.R \
        tests/testthat/helpers/season-transition-snapshot-runner.R
git commit -m "$(cat <<'EOF'
refactor(#102): remove silent C++/R fallback in update_elos_for_match

Collapses elo_aggregation.R onto the pure-R calculate_elo_update path.
The cross-engine equivalence test from PR #100 (5-scenario sweep) showed
SpielNichtSimulieren.cpp and calculate_elo_update produce byte-identical
ELOs, making the if (exists()) guard correctness-by-coincidence rather
than a meaningful runtime choice.

The probe block at elo_aggregation.R:225 (added by PR #100 to record the
current engine selection) is removed alongside the guard; its job is done.

The CSV snapshot test continues to pin byte-identical output — the
subprocess path was already R-only (probe = FALSE), so observable behavior
is unchanged.

Phase 1 of issue #102. Phase 2 deletes the unreachable C++ files.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: Delete the C++ engine and its test surface

### Task 2: Delete the C++ R-wrapper tower and the `.cpp` primitive

**Why:** After Task 1, no R code in the repo calls `SpielNichtSimulieren`, `SpielCPP`, `SaisonSimulierenCPP`, `simulationsCPP`, or `leagueSimulatorCPP`. The wrapper tower and the C++ source are dead code. Delete them in one commit so the diff is "remove unreachable engine" rather than scattered cleanup.

**Files:**
- Delete: `RCode/SpielCPP.R`
- Delete: `RCode/simulationsCPP.R`
- Delete: `RCode/SaisonSimulierenCPP.R`
- Delete: `RCode/leagueSimulatorCPP.R`
- Delete: `RCode/cpp_wrappers.R`
- Delete: `RCode/RcppExports.R`
- Delete: `RCode/SpielNichtSimulieren.cpp`
- Delete: `RCode/update_league.R`
- Modify: `scripts/season_transition.R:68-72`

- [ ] **Step 1: Confirm `update_league.R` is still orphan**

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update.issue-102-retire-cpp"
grep -rn "update_league\.R\|update_league(" RCode/ scripts/ tests/testthat/ Dockerfile* docker-compose* 2>/dev/null | grep -v "deployment_files_league.txt"
```

Expected output: only `RCode/league_scheduler.R` references. `league_scheduler.R` is also orphan (per issue #86) and will be deleted in #86, not here. No production caller.

If anything else surfaces, **stop** and reconcile before proceeding.

- [ ] **Step 2: Delete the eight files**

```bash
git rm RCode/SpielCPP.R \
       RCode/simulationsCPP.R \
       RCode/SaisonSimulierenCPP.R \
       RCode/leagueSimulatorCPP.R \
       RCode/cpp_wrappers.R \
       RCode/RcppExports.R \
       RCode/SpielNichtSimulieren.cpp \
       RCode/update_league.R
```

- [ ] **Step 3: Edit `scripts/season_transition.R` to drop `SpielCPP.R` from `existing_modules`**

Find the block at lines 67–72:

```r
# Source existing modules that we'll use
existing_modules <- c(
  "retrieveResults.R",
  "transform_data.R",
  "SpielCPP.R"
)
```

Replace with:

```r
# Source existing modules that we'll use
existing_modules <- c(
  "retrieveResults.R",
  "transform_data.R"
)
```

- [ ] **Step 4: Run the full testthat suite — expect specific failures**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -50
```

Expected failures (these get cleaned up in Task 3):
- `test-SpielNichtSimulieren.R` — sourceCpp on a file that no longer exists
- `test-spielcpp-contract.R` — source on `SpielCPP.R` that no longer exists
- Any test relying on `helper-test-setup.R`'s `compile_cpp_files` step finding no `.cpp` to compile (this should be a warning, not a fail; helper handles missing file gracefully)

The engine-selection test from Task 1 should still pass (it has no `Rcpp` dependency now).
The CSV snapshot test should still pass (the script doesn't source any of the deleted modules — the subprocess only loads what it needs).

- [ ] **Step 5: Run the season-transition CSV snapshot in isolation as the load-bearing check**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")'
```

Expected: PASS, byte-identical CSV.

If this fails, **stop**. The subprocess produced different output than the snapshot — investigate before continuing. Most likely cause: `season_transition.R` had an indirect dependency on something we deleted. Read its actual module list and what each module imports.

- [ ] **Step 6: Commit**

```bash
git add scripts/season_transition.R
git commit -m "$(cat <<'EOF'
chore(#102): delete C++ simulation engine and orphan wrapper tower

Removes the eight-file C++ tower that has no live callers after Phase 1
(elo_aggregation.R no longer dispatches to SpielNichtSimulieren) and after
the production loop's switch to the Rust seam in commit b4fbb96.

Files deleted:
- RCode/SpielCPP.R, simulationsCPP.R, SaisonSimulierenCPP.R,
  leagueSimulatorCPP.R, cpp_wrappers.R         # R-wrapper tower
- RCode/RcppExports.R                          # auto-generated Rcpp glue
- RCode/SpielNichtSimulieren.cpp               # C++ ELO primitive
- RCode/update_league.R                        # only remaining caller of
                                               # leagueSimulatorCPP; orphan
                                               # microservices file flagged
                                               # for deletion in #86 anyway

Also drops "SpielCPP.R" from scripts/season_transition.R's existing_modules
list — it was sourced but never invoked by any season-transition module.

Tests against the deleted files (test-SpielNichtSimulieren.R,
test-spielcpp-contract.R, comparison harnesses) are removed in the next
commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Delete tests for deleted code and the orphan tooling files

**Why:** After Task 2 the test suite has loaders that point at non-existent files. Delete them. Also delete the loose `tests/*.R` scratch files and the `compare_*.R` harnesses at the repo root — they are tooling, not part of the test suite, and they exist to validate Rust against C++. Their job ended when Phase 1 made Rust unconditional.

**Files:**
- Delete: `tests/testthat/test-spielcpp-contract.R`
- Delete: `tests/testthat/test-SpielNichtSimulieren.R`
- Delete: `tests/rust/test_rust_vs_cpp_detailed.R`
- Delete: `tests/rust/calculate_matrix_differences.R`
- Delete: `compare_rust_cpp.R` (repo root)
- Delete: `compare_rust_vs_r.R` (repo root)
- Delete: `compare_working.R` (repo root)
- Delete: `tests/single_match_test.R`
- Delete: `tests/test_rust_integration.R`
- Delete: `tests/verify_parameters.R`
- Delete: `tests/check_played_matches.R`
- Delete: `tests/verify_home_advantage.R`
- Delete: `RCode/deployment_files_league.txt`
- Delete: `RCode/deployment_files_shiny.txt`
- Modify: `tests/testthat/helper-test-setup.R` (drop the `compile_cpp_files()` block)

- [ ] **Step 1: Verify each deletion candidate has no inbound references that would break**

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update.issue-102-retire-cpp"
for f in test-spielcpp-contract test-SpielNichtSimulieren single_match_test test_rust_integration verify_parameters check_played_matches verify_home_advantage compare_rust_cpp compare_rust_vs_r compare_working calculate_matrix_differences test_rust_vs_cpp_detailed deployment_files_league deployment_files_shiny; do
  echo "===== $f ====="
  grep -rn "$f" tests/ scripts/ RCode/ docs/ Dockerfile docker-compose.yml docker-start.sh 2>/dev/null | grep -v "Binary file"
done
```

Expected: each file is referenced only by itself or by `tests/TEST_SUITE_STATUS_*.md` (a status doc, not active code). If any file is sourced by a *surviving* module, **stop and reconcile** — likely it's a tooling helper someone uses; either keep it and update its sources, or note the deletion in the commit body.

- [ ] **Step 2: Delete the test files and tooling**

```bash
git rm tests/testthat/test-spielcpp-contract.R \
       tests/testthat/test-SpielNichtSimulieren.R \
       tests/rust/test_rust_vs_cpp_detailed.R \
       tests/rust/calculate_matrix_differences.R \
       compare_rust_cpp.R \
       compare_rust_vs_r.R \
       compare_working.R \
       tests/single_match_test.R \
       tests/test_rust_integration.R \
       tests/verify_parameters.R \
       tests/check_played_matches.R \
       tests/verify_home_advantage.R \
       RCode/deployment_files_league.txt \
       RCode/deployment_files_shiny.txt
```

- [ ] **Step 3: Edit `tests/testthat/helper-test-setup.R` to remove the `compile_cpp_files()` block**

Find the function definition (around lines 109–145) and the call to it in the setup block (around line 178 area, in the `tryCatch` body). Open the file and read it first. Then:

(a) Delete the entire `compile_cpp_files <- function() { ... }` block (the function definition and its body, lines ~109–145).

(b) Find the line that calls `compile_cpp_files()` in the setup block at the bottom of the file and delete it. The exact line number depends on what else is there — read first, then edit.

- [ ] **Step 4: Run the full testthat suite — expect green**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -30
```

Expected: All remaining tests pass. No errors about missing `.cpp` files, no errors about `compile_cpp_files` undefined.

If any test still fails because it transitively sourced one of the deleted files, **read that test file and either remove the dead source line or delete the test** (if it tests soon-to-be-irrelevant functionality). Document the decision in the commit body.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/helper-test-setup.R
git commit -m "$(cat <<'EOF'
test(#102): remove tests for deleted C++ engine and comparison harnesses

Deletes the test surface that pointed at the C++ engine removed in the
previous commit:

- tests/testthat/test-SpielNichtSimulieren.R     # 11 tests vs. deleted .cpp
- tests/testthat/test-spielcpp-contract.R        # contract test vs. deleted SpielCPP

Deletes Rust-vs-C++ comparison harnesses whose purpose ended when Phase 1
made Rust the unconditional production engine:

- tests/rust/test_rust_vs_cpp_detailed.R
- tests/rust/calculate_matrix_differences.R
- compare_rust_cpp.R, compare_rust_vs_r.R, compare_working.R   # repo root

Deletes loose tooling files in tests/ root that sourced the deleted
wrappers (these were never part of the testthat suite — scratch tooling
left over from the Rust migration):

- tests/single_match_test.R, test_rust_integration.R, verify_parameters.R,
  check_played_matches.R, verify_home_advantage.R

Deletes deployment-file manifests for the multi-Dockerfile world that was
collapsed in #78:

- RCode/deployment_files_league.txt, deployment_files_shiny.txt

Drops the compile_cpp_files() block from helper-test-setup.R (no .cpp files
remain to compile).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Drop the `Rcpp` build dependency

### Task 4: Remove `Rcpp` from packagelist, Dockerfile, and the install verification script

**Why:** After Tasks 2 and 3 nothing in the repo loads or compiles C++. Carrying `Rcpp` in `packagelist.txt` and the Dockerfile is pure overhead — slower image build, larger image, plus a non-zero chance of an Rcpp ABI break causing a CI failure for code we no longer use.

**Files:**
- Modify: `packagelist.txt:16`
- Modify: `Dockerfile:44, :78`
- Modify: `scripts/install_test_packages.R:49-53`

- [ ] **Step 1: Edit `packagelist.txt` to remove the `Rcpp` line**

Open `packagelist.txt`. Line 16 is `Rcpp`. Delete that single line.

- [ ] **Step 2: Edit `Dockerfile`**

Find this line (around line 44):

```dockerfile
    core_pkgs <- c('Rcpp', 'httr', 'jsonlite', 'dplyr', 'tidyr', 'magrittr'); \
```

Replace with:

```dockerfile
    core_pkgs <- c('httr', 'jsonlite', 'dplyr', 'tidyr', 'magrittr'); \
```

Find this line (around line 78):

```dockerfile
    already_installed <- c('Rcpp', 'httr', 'jsonlite', 'dplyr', 'tidyr', 'magrittr', 'htmltools', 'httpuv', 'promises', 'shiny', 'rsconnect'); \
```

Replace with:

```dockerfile
    already_installed <- c('httr', 'jsonlite', 'dplyr', 'tidyr', 'magrittr', 'htmltools', 'httpuv', 'promises', 'shiny', 'rsconnect'); \
```

- [ ] **Step 3: Edit `scripts/install_test_packages.R` to remove the Rcpp verify block**

Find lines 49–53:

```r
  # Verify Rcpp compilation works
  cat("\nVerifying Rcpp compilation...\n")
  library(Rcpp)
  sourceCpp("RCode/SpielNichtSimulieren.cpp")
  cat("✅ Rcpp compilation successful!\n")
```

Delete those five lines entirely.

- [ ] **Step 4: Verify nothing else in the repo references `Rcpp`**

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update.issue-102-retire-cpp"
grep -rn "Rcpp\|sourceCpp" --include='*.R' --include='*.Rmd' --include='Dockerfile*' --include='*.txt' --include='*.yml' --include='*.yaml' . 2>/dev/null | grep -v "^\./\.git"
```

Expected output: only documentation hits in `docs/` (e.g., `docs/architecture/overview.md` mentions "Rcpp Integration: 100x speedup"), `docs/prds/`, the just-edited PRD, or this plan. **No live code path mentions Rcpp.**

If a code reference survives, read the file and decide: delete the reference (if dead), or pull it into this commit (if a missed call site).

- [ ] **Step 5: Run the full testthat suite — expect green**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -20
```

Expected: All tests pass. The R session may still have `Rcpp` installed locally — this commit doesn't uninstall it from a developer machine, only from the Docker build and the install-test-packages script.

- [ ] **Step 6: Commit**

```bash
git add packagelist.txt Dockerfile scripts/install_test_packages.R
git commit -m "$(cat <<'EOF'
build(#102): drop Rcpp from R deps and Docker base image

After deleting the C++ engine (previous two commits), Rcpp has no consumer
in the repo. Remove it from:

- packagelist.txt        # the production dependency list
- Dockerfile             # both core_pkgs and already_installed lists
- scripts/install_test_packages.R  # the post-install Rcpp verification step

Closes the build-time C++ surface entirely. Slightly smaller image,
slightly faster builds, and one fewer ABI source for CI failures.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4: Documentation and PRD reconciliation

### Task 5: Update the PRD to record that Option B was chosen

**Why:** The PRD recommended Option A. Issue #102 superseded that based on PR #100's empirical finding. Future readers landing on the PRD via search need a one-line pointer to "what actually happened."

**Files:**
- Modify: `docs/prds/2026-05-03-simulation-engine-seam-phase-2.md` (add a note at the top)

- [ ] **Step 1: Read the PRD's current top section**

```bash
head -10 docs/prds/2026-05-03-simulation-engine-seam-phase-2.md
```

- [ ] **Step 2: Insert an "Outcome" admonition at the top of the PRD**

After the metadata block (after the line starting with `**Source:**`) and before the existing `>` blockquote about Phase-1, add this block:

```markdown
> **Outcome (2026-05-06):** Executed as **Option B** (delete the C++ engine in full), not the recommended Option A. PR #100's regression net (`tests/testthat/test-elo-aggregation-engine-selection.R` scenario sweep) proved C++ and R formulas produce byte-identical ELOs across 5 fixture scenarios, eliminating Option B's "divergence risk" trade-off and making the smaller-surface choice strictly better. See execution plan at `docs/superpowers/plans/2026-05-06-issue-102-retire-cpp-engine.md` and issue #102.
```

- [ ] **Step 3: Commit (no test run needed for docs)**

```bash
git add docs/prds/2026-05-03-simulation-engine-seam-phase-2.md
git commit -m "$(cat <<'EOF'
docs(#102): record Option B as the executed Phase-2 outcome

PR #100's cross-engine equivalence sweep proved C++ and R ELO formulas
produce byte-identical results, eliminating the divergence risk that
made Option A preferred. The smaller-surface Option B (delete the C++
engine outright) is strictly better and was executed.

Adds an admonition at the top of the PRD pointing readers to the
execution plan; PRD body is otherwise preserved as historical context.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5: Final verification

### Task 6: Sweep, smoke test, push

**Why:** Confirm nothing was missed before the PR. The PRD's acceptance criteria become assertions in this task.

**Files:**
- None modified — verification only.

- [ ] **Step 1: Confirm all named files are absent**

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update.issue-102-retire-cpp"
for f in RCode/SpielCPP.R RCode/simulationsCPP.R RCode/SaisonSimulierenCPP.R \
         RCode/leagueSimulatorCPP.R RCode/cpp_wrappers.R RCode/RcppExports.R \
         RCode/SpielNichtSimulieren.cpp RCode/update_league.R \
         tests/testthat/test-spielcpp-contract.R tests/testthat/test-SpielNichtSimulieren.R; do
  if [ -e "$f" ]; then echo "STILL PRESENT: $f"; else echo "OK absent: $f"; fi
done
```

Expected: every line says "OK absent". Any "STILL PRESENT" means a deletion was missed.

- [ ] **Step 2: Confirm the surviving production scheduler still parses**

```bash
Rscript -e 'invisible(parse("RCode/updateScheduler.R")); cat("OK\n")'
Rscript -e 'invisible(parse("RCode/update_all_leagues_loop.R")); cat("OK\n")'
Rscript -e 'invisible(parse("RCode/elo_aggregation.R")); cat("OK\n")'
Rscript -e 'invisible(parse("scripts/season_transition.R")); cat("OK\n")'
```

Expected: all four print `OK`.

- [ ] **Step 3: Run the full testthat suite end-to-end**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tee /tmp/issue-102-testthat.log | tail -30
```

Expected: green. Look for "Failures: 0" or "[ FAIL 0 ]" in the summary line.

- [ ] **Step 4: Sanity-check the engine-selection and CSV-snapshot tests one more time in isolation**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-elo-aggregation-engine-selection.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")'
```

Expected: both green. The CSV byte-count is the load-bearing acceptance criterion from the PRD.

- [ ] **Step 5: Confirm no stray `Rcpp` references remain in active code paths**

```bash
grep -rn "Rcpp\|sourceCpp" --include='*.R' --include='Dockerfile*' --include='*.txt' --include='*.yml' --include='*.yaml' . 2>/dev/null | grep -v "^\./\.git" | grep -v "^\./docs/"
```

Expected: empty (or only false positives in plan/PRD/CHANGELOG markdown). Any other hit means a missed reference.

- [ ] **Step 6: Look at the cumulative diff against `main`**

```bash
git log --oneline main..HEAD
git diff --stat main..HEAD
```

Expected: 5 commits (one per task that touched code), ~20 deletions in stat, modest additions in test-elo-aggregation-engine-selection.R rewrite.

- [ ] **Step 7: Push the branch and open a draft PR**

```bash
git push -u origin feature/issue-102-retire-cpp
gh pr create --draft --title "refactor(#102): retire C++ simulation engine (Phase 2, Option B)" --body "$(cat <<'EOF'
## Summary

Closes #102. Executes Phase-2 of the simulation-engine seam refactor as Option B: deletes the C++ engine in full and consolidates ELO calculations on the pure-R `calculate_elo_update` primitive.

- 8 files removed under `RCode/` (5-file wrapper tower + `RcppExports.R` + `SpielNichtSimulieren.cpp` + orphan `update_league.R`)
- 12 test/tooling files removed (contract test, .cpp test, comparison harnesses, root-level scratch tooling, deployment manifests)
- `Rcpp` removed from `packagelist.txt`, `Dockerfile`, and `scripts/install_test_packages.R`
- `if (exists("SpielNichtSimulieren"))` silent-fallback guard removed from `RCode/elo_aggregation.R`
- PRD at `docs/prds/2026-05-03-simulation-engine-seam-phase-2.md` annotated with the Option-B outcome

The decision to take Option B (instead of the PRD's original Option-A recommendation) is grounded in PR #100's empirical proof that C++ and R formulas produce byte-identical ELOs.

## Test plan

- [x] `tests/testthat/test-elo-aggregation-engine-selection.R` passes (R-only, post-refactor)
- [x] `tests/testthat/test-season-transition-csv-snapshot.R` passes byte-identically against the snapshot pinned in PR #100
- [x] Full `testthat::test_dir("tests/testthat")` is green
- [x] `Rscript -e 'invisible(parse(...))'` succeeds on `updateScheduler.R`, `update_all_leagues_loop.R`, `elo_aggregation.R`, `scripts/season_transition.R`
- [x] No `Rcpp`/`sourceCpp` references survive outside `docs/` and this plan/PRD
- [ ] CI is green on the PR

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed; CI starts. Watch the CI run; if anything red, return to the relevant task.

- [ ] **Step 8: Mark PR ready for review once CI is green**

```bash
gh pr ready
```

---

## Risks and Recovery

- **Risk:** A surviving caller of one of the deleted files surfaces only at runtime (not parse time). Mitigation: Task 6 Step 3 runs the full testthat suite, which exercises every production module's source path. If something escapes the test suite, the `pre-deletion` git tag preserved at the merge-base of this branch lets `git revert` reverse any commit. **Add the tag manually before pushing if it does not exist:** `git tag pre-issue-102-retire-cpp main && git push origin pre-issue-102-retire-cpp`.

- **Risk:** A developer's local machine has `Rcpp` cached and tests pass locally even though CI fails (because CI does a clean install). Mitigation: Task 4 Step 5's full suite is a local check; CI in Task 6 Step 7 is the ground truth.

- **Risk:** The CSV snapshot in `tests/testthat/fixtures/season-transition-2024-to-2025/TeamList_2025.csv.snapshot` was captured under conditions that differ from this branch's environment (e.g., R version, locale). Mitigation: Task 0 verified the snapshot matches *before* any deletion; Task 6 verifies it matches *after*. If both pass, the deletions did not change observable behavior.

- **Risk:** Issue #86 lands first and removes `update_league.R` — then Task 2's `git rm RCode/update_league.R` fails because it's already gone. Mitigation: trivial. Drop that one path from the `git rm` command; the rest still applies.

---

## Self-Review

**Spec coverage** (vs PRD acceptance criteria + issue #102 scope list):

- ✅ "Files deleted: SpielCPP.R, simulationsCPP.R, SaisonSimulierenCPP.R, leagueSimulatorCPP.R, cpp_wrappers.R" → Task 2 Step 2
- ✅ "RcppExports.R either deleted or kept" → Task 2 (deleted, in same `git rm` line)
- ✅ "SpielNichtSimulieren.cpp present and unchanged" — *deviation: Option B deletes it.* Documented in PRD update (Task 5) and PR body. Issue #102 explicitly recommended Option B.
- ✅ "scripts/season_transition.R no longer lists SpielCPP.R" → Task 2 Step 3
- ✅ "scripts/season_transition.R sources SpielNichtSimulieren.cpp" — *N/A under Option B.*
- ✅ "RCode/elo_aggregation.R no longer contains the if (exists()) guard … pure-R fallback deleted" — *partial deviation: guard removed (Task 1 Step 3); `calculate_elo_update` retained as the only path, not deleted as the PRD's Option A suggested.* This is the correct Option B reading.
- ✅ "tests/testthat/test-spielcpp-contract.R deleted" → Task 3 Step 2
- ✅ "Comparison harnesses deleted" → Task 3 Step 2
- ✅ "test-SpielNichtSimulieren.R runs green" — *N/A under Option B; file deleted.*
- ✅ "test-elo-aggregation*.R exercises update_elos_for_match" → Task 1 Step 1
- ✅ "season_transition.R produces byte-identical TeamList_2025.csv" → Task 6 Step 4
- ✅ "CI runs green" → Task 6 Step 7
- ✅ "Rcpp remains in packagelist.txt and Dockerfile core_pkgs" — *deviation: Option B removes it.* Task 4. Documented in PRD update.
- ✅ Probe code at elo_aggregation.R:225 removed → Task 1 Step 3
- ✅ exists() guard removed → Task 1 Step 3

**Placeholder scan:** No "TBD", "implement later", "appropriate error handling", or "similar to Task N" patterns. Every step has either an exact command or a complete code block.

**Type/name consistency:** `update_elos_for_match`, `calculate_elo_update`, `existing_modules`, `compile_cpp_files`, `SpielNichtSimulieren`, `season_transition.R` — all spellings match across tasks. Probe variable name `SEASON_TRANSITION_ENGINE_PROBE` consistent in Task 1 Steps 4 and the deleted lines.

**Spec deviations** (and why each is correct):
1. PRD's Option-A acceptance criteria assumed `.cpp` survives; Option B (per #102 + PR #100 finding) deletes it. Plan executes B; PRD gets an admonition (Task 5).
2. PRD's "test-SpielNichtSimulieren.R runs green against the unchanged .cpp" is replaced by "tests for deleted code are deleted" (Task 3). The C++ primitive's behavior is no longer pinned because no production code depends on it.
3. PRD lists `update_league.R` as out-of-scope (deferred to #86). This plan deletes it because it's the only remaining caller of `leagueSimulatorCPP` and would leave an intentionally-broken file otherwise. Co-deleting is cleaner than a sequencing dance with #86. Documented in Task 2's commit body.

---

## Plan complete

**Saved to:** `docs/superpowers/plans/2026-05-06-issue-102-retire-cpp-engine.md` in the `feature/issue-102-retire-cpp` worktree.

Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

Which approach?
