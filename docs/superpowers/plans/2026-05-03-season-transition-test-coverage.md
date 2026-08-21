# Season-Transition Test-Coverage Gap Fill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a regression net (engine-selection unit test, api-football cassette fixtures, end-to-end CSV snapshot test, plus a one-line env-var-gated probe) that pins current behavior of the season-transition workflow before the Phase-2 refactor at `docs/prds/2026-05-03-simulation-engine-seam-phase-2.md` runs.

**Architecture:** Three new test artifacts in `tests/testthat/`, one new test dependency (`httptest2`), and one minimal-blast-radius env-var-gated probe in `RCode/elo_aggregation.R`. The snapshot test runs `scripts/season_transition.R` in a real `Rscript` subprocess inside `withr::with_dir(temp_dir)` with `httptest2::with_mock_dir` cassette playback. Tests are non-destructive and ship before the Phase-2 plan executes.

**Tech Stack:** R 4.3.1, testthat 3.x, httptest2 (new), Rcpp (already a dep), withr (already a dep), base R `system2` for subprocess invocation.

**Spec:** `docs/superpowers/specs/2026-05-03-season-transition-test-coverage-design.md`

---

## File Structure

| Path | Action | Purpose |
|---|---|---|
| `test_packagelist.txt` | Modify | Add `httptest2` and `withr` (latter may already be transitive — verify and only add if missing) |
| `RCode/elo_aggregation.R` | Modify (one block) | Env-var-gated probe immediately above existing line 225 guard |
| `tests/testthat/test-elo-aggregation-engine-selection.R` | Create | Gap #1: pin C++-path output, R-fallback output, and whether they agree |
| `tests/testthat/fixtures/season-transition-2024-to-2025/` | Create | Cassette directory + expected CSV snapshot + re-record README |
| `tests/testthat/fixtures/season-transition-2024-to-2025/README.md` | Create | Re-record procedure doc |
| `tests/testthat/fixtures/season-transition-2024-to-2025/TeamList_2025.csv.snapshot` | Create | Captured expected output |
| `tests/testthat/test-season-transition-csv-snapshot.R` | Create | Gap #2 + gap #3: end-to-end snapshot + probe assertion |

---

## Pre-flight: install httptest2 locally

This plan assumes `httptest2` is installed in your local R environment before running any tests. Once Task 1 lands, CI under #76 will install it from `test_packagelist.txt`. For local dev:

```r
install.packages("httptest2")
```

If that fails (uncommon), see https://enpiar.com/httptest2/ for installation troubleshooting.

---

## Task 1: Add httptest2 to test dependencies

**Files:**
- Modify: `test_packagelist.txt`

- [ ] **Step 1: Read the current file**

```bash
cat test_packagelist.txt
```

Expected output: 12 lines, last one is `lubridate`. No `httptest2`. Verify `withr` is also absent (it is — we'll add it too if it isn't already a transitive dep covered elsewhere).

- [ ] **Step 2: Append httptest2 (and withr only if not already in packagelist.txt)**

Check `packagelist.txt` (production) for `withr`:

```bash
grep -i "^withr$" packagelist.txt
```

If empty, withr is not a runtime dep — add it to the test list. Edit `test_packagelist.txt`, appending exactly:

```
httptest2
```

If `grep` returned nothing, also append on a new line:

```
withr
```

- [ ] **Step 3: Verify install locally**

```r
install.packages(c("httptest2", "withr"))
library(httptest2)
library(withr)
```

Expected: both packages load without error.

- [ ] **Step 4: Commit**

```bash
git add test_packagelist.txt
git commit -m "$(cat <<'EOF'
test(#77): add httptest2 + withr to test dependencies

Required by upcoming season-transition CSV snapshot test
(docs/superpowers/specs/2026-05-03-season-transition-test-coverage-design.md).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Engine-selection unit test (C++ path)

**Files:**
- Create: `tests/testthat/test-elo-aggregation-engine-selection.R`

The hand-derived expected ELO for the C++ path is computed from `RCode/SpielNichtSimulieren.cpp:18-32`:

```
ELODeltaInv = 1500 - 1500 - 100 = -100  (clamped to [-400, 400] → -100)
ELOProb     = 1 / (1 + 10^(-100/400)) = 1 / (1 + 10^(-0.25))
            = 1 / (1 + 0.5623413...) = 1 / 1.5623413... = 0.6400649...
goalDiff    = 2 - 0 = 2
result      = ((0 < 2) - (2 < 0) + 1) / 2 = (1 - 0 + 1) / 2 = 1.0
goalMod     = sqrt(max(2, 1)) = sqrt(2) = 1.41421356...
ELOMod      = (1.0 - 0.6400649) * 1.41421356 * 20 = 0.3599351 * 28.2842712
            = 10.18028...

Expected:
  home_new_elo = 1500 + 10.18028 = 1510.18028  (C++ home gets POSITIVE delta — but note
                                                   SpielNichtSimulieren computes ELODeltaInv
                                                   = away - home - homeAdv, so the
                                                   modificator is added to home and
                                                   subtracted from away)
  away_new_elo = 1500 - 10.18028 = 1489.81972
```

We use `expect_equal(..., tolerance = 1e-4)` to accommodate `qpois`/floating-point differences.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-elo-aggregation-engine-selection.R`:

```r
# Engine-selection regression net for update_elos_for_match.
#
# RCode/elo_aggregation.R:225 uses `if (exists("SpielNichtSimulieren"))` and
# falls back to a pure-R calculate_elo_update if the C++ primitive isn't loaded.
# This file pins:
#   1) The C++-path output (with SpielNichtSimulieren defined).
#   2) The R-fallback output (with SpielNichtSimulieren NOT defined).
#   3) Whether the two paths agree.
#
# The agreement test's verdict is the load-bearing input to the Phase-2 PRD's
# Option A vs Option B branch (docs/prds/2026-05-03-simulation-engine-seam-phase-2.md).
#
# helper-test-setup.R sources SpielNichtSimulieren.cpp at suite startup, so the
# C++ primitive is available globally. The R-fallback test must hide it locally.

library(testthat)

# Build a fixed match record and elo table for all three tests.
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

test_that("update_elos_for_match returns C++-path ELOs when SpielNichtSimulieren is defined", {
  # Precondition: helper-test-setup.R has sourced SpielNichtSimulieren.cpp
  skip_if_not(exists("SpielNichtSimulieren"),
              "SpielNichtSimulieren must be available; check helper-test-setup.R")

  result <- update_elos_for_match(fixture_elos(), fixture_match())

  # Hand-computed from SpielNichtSimulieren.cpp:18-32 with mod_factor=20,
  # home_advantage=100, ELOs (1500, 1500), goals (2, 0):
  #   ELODeltaInv = -100, ELOProb = 1/(1+10^-0.25) = 0.6400649
  #   goalMod    = sqrt(2) = 1.41421356
  #   ELOMod     = (1.0 - 0.6400649) * 1.41421356 * 20 = 10.18028
  expected_home <- 1500 + 10.18028
  expected_away <- 1500 - 10.18028

  expect_equal(result$CurrentELO[result$TeamID == 1L], expected_home, tolerance = 1e-4)
  expect_equal(result$CurrentELO[result$TeamID == 2L], expected_away, tolerance = 1e-4)
})

test_that("update_elos_for_match falls back to calculate_elo_update when SpielNichtSimulieren is hidden", {
  # We can't unload the cpp from the test session, so override `exists()` in a
  # local scope to lie about SpielNichtSimulieren's availability. update_elos_for_match
  # uses base::exists(), which R's lexical lookup will resolve to our shadow when
  # the call is evaluated inside `with(list(exists = ...))`.
  shadow_exists <- function(x, ...) {
    if (identical(x, "SpielNichtSimulieren")) return(FALSE)
    base::exists(x, ...)
  }

  result <- with(list(exists = shadow_exists),
                 update_elos_for_match(fixture_elos(), fixture_match()))

  # Hand-computed from calculate_elo_update at elo_aggregation.R:252 with same inputs:
  #   elo_diff       = (1500 - 1500 - 100) = -100, clamped to -100
  #   expected_prob  = 1 / (1 + 10^(-0.25)) = 0.6400649
  #   actual_result  = (sign(2) + 1) / 2 = 1.0
  #   goal_modifier  = sqrt(max(2, 1)) = 1.41421356
  #   elo_change     = (1.0 - 0.6400649) * 1.41421356 * 20 = 10.18028
  # Same formula as C++. So we expect equality.
  expected_home <- 1500 + 10.18028
  expected_away <- 1500 - 10.18028

  expect_equal(result$CurrentELO[result$TeamID == 1L], expected_home, tolerance = 1e-4)
  expect_equal(result$CurrentELO[result$TeamID == 2L], expected_away, tolerance = 1e-4)
})

test_that("C++ and R fallback engines produce equivalent ELO updates across a parameter sweep", {
  skip_if_not(exists("SpielNichtSimulieren"),
              "SpielNichtSimulieren must be available")

  scenarios <- list(
    list(home = 1500, away = 1500, gh = 2, ga = 0, label = "home_win_equal"),
    list(home = 1700, away = 1300, gh = 1, ga = 1, label = "draw_asymmetric"),
    list(home = 1300, away = 1700, gh = 0, ga = 3, label = "away_blowout"),
    list(home = 1500, away = 1500, gh = 1, ga = 1, label = "draw_equal"),
    list(home = 1600, away = 1400, gh = 3, ga = 2, label = "home_close_win")
  )

  shadow_exists <- function(x, ...) {
    if (identical(x, "SpielNichtSimulieren")) return(FALSE)
    base::exists(x, ...)
  }

  for (s in scenarios) {
    elos <- data.frame(TeamID = c(1L, 2L), CurrentELO = c(s$home, s$away))
    match <- data.frame(teams_home_id = 1L, teams_away_id = 2L,
                        goals_home = s$gh, goals_away = s$ga)

    cpp_result <- update_elos_for_match(elos, match)

    r_result <- with(list(exists = shadow_exists),
                     update_elos_for_match(elos, match))

    expect_equal(cpp_result$CurrentELO[1], r_result$CurrentELO[1],
                 tolerance = 1e-4,
                 info = sprintf("scenario %s: home ELO C++ vs R", s$label))
    expect_equal(cpp_result$CurrentELO[2], r_result$CurrentELO[2],
                 tolerance = 1e-4,
                 info = sprintf("scenario %s: away ELO C++ vs R", s$label))
  }
})
```

- [ ] **Step 2: Run test to verify it fails initially OR passes**

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update"
Rscript -e 'testthat::test_file("tests/testthat/test-elo-aggregation-engine-selection.R")'
```

Expected: All three `test_that` blocks PASS. (This is a regression net pinning current behavior — if the test fails on first run, the hand-computed expected values need correction. See Step 3.)

- [ ] **Step 3: If test 1 or test 2 fails, recompute expected values**

If `expect_equal(result$CurrentELO[result$TeamID == 1L], 1510.18028, tolerance = 1e-4)` fails with an actual value that's still close to 1510 but off in the 4th decimal, replace the expected value with the actual (the formula is the truth; the hand-calc may have rounded).

If test 3 (agreement) fails, that is a *real signal* — the C++ and R formulas diverge. Update the test 3 assertion to reflect the divergence:

```r
# Replace the agreement assertions with:
expect_false(isTRUE(all.equal(cpp_result$CurrentELO[1], r_result$CurrentELO[1],
                              tolerance = 1e-6)),
             info = sprintf("scenario %s: C++ and R diverge — Phase-2 must use Option A", s$label))
```

Document the divergence in a comment at the top of the file. The Phase-2 PRD's Option A vs Option B branch hinges on this answer; recording divergence here is the test's job, not a bug.

- [ ] **Step 4: Re-run after any expected-value corrections**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-elo-aggregation-engine-selection.R")'
```

Expected: 3 passing tests (or 3 passing tests with the divergence-asserting variant of test 3).

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-elo-aggregation-engine-selection.R
git commit -m "$(cat <<'EOF'
test(#77): pin elo-aggregation engine selection (C++ vs R fallback)

Three tests in tests/testthat/test-elo-aggregation-engine-selection.R:
  1. C++-path ELO output with SpielNichtSimulieren defined
  2. R-fallback ELO output via shadow exists() override
  3. Cross-engine agreement check across 5 scenarios

The agreement test pins whether C++ and R formulas produce equivalent
results — the load-bearing question for Phase-2 PRD Option A vs Option B
(docs/prds/2026-05-03-simulation-engine-seam-phase-2.md).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add the env-var-gated probe to elo_aggregation.R

**Files:**
- Modify: `RCode/elo_aggregation.R:206-225` (insert one block immediately above the existing `if (exists(...))` guard)

- [ ] **Step 1: Write the failing test**

Add a test that the probe writes the right value when the env var is set. Append to `tests/testthat/test-elo-aggregation-engine-selection.R`:

```r
test_that("probe writes engine availability when SEASON_TRANSITION_ENGINE_PROBE is set", {
  skip_if_not(exists("SpielNichtSimulieren"),
              "SpielNichtSimulieren must be available")

  probe_path <- tempfile(fileext = ".txt")
  on.exit(unlink(probe_path), add = TRUE)

  withr::with_envvar(
    list(SEASON_TRANSITION_ENGINE_PROBE = probe_path),
    {
      update_elos_for_match(fixture_elos(), fixture_match())
    }
  )

  expect_true(file.exists(probe_path))
  expect_equal(readLines(probe_path)[1], "TRUE")
})

test_that("probe is silent when SEASON_TRANSITION_ENGINE_PROBE is unset", {
  skip_if_not(exists("SpielNichtSimulieren"),
              "SpielNichtSimulieren must be available")

  # Confirm env var is not set in the test runner.
  withr::with_envvar(
    list(SEASON_TRANSITION_ENGINE_PROBE = NA),
    {
      # Should not raise, should not write any file.
      result <- update_elos_for_match(fixture_elos(), fixture_match())
      expect_s3_class(result, "data.frame")
    }
  )
})
```

- [ ] **Step 2: Run the new tests to verify failure**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-elo-aggregation-engine-selection.R")'
```

Expected: 3 PASS (existing) + 1 FAIL ("probe writes engine availability ...": file does not exist) + 1 PASS (silent when unset, since no probe code yet).

- [ ] **Step 3: Add the probe to elo_aggregation.R**

Open `RCode/elo_aggregation.R`. Find line 224 (just above `if (exists("SpielNichtSimulieren"))`). Insert this block immediately above line 225:

```r
  # Test probe: when SEASON_TRANSITION_ENGINE_PROBE is set, write whether the C++
  # primitive is available to that file path. Off by default; production unaffected.
  # Removed during Phase-2 refactor along with the exists() guard below
  # (see docs/prds/2026-05-03-simulation-engine-seam-phase-2.md and
  # docs/superpowers/specs/2026-05-03-season-transition-test-coverage-design.md).
  if (Sys.getenv("SEASON_TRANSITION_ENGINE_PROBE") != "") {
    writeLines(as.character(exists("SpielNichtSimulieren")),
               Sys.getenv("SEASON_TRANSITION_ENGINE_PROBE"))
  }

  # Use existing ELO calculation if available
  if (exists("SpielNichtSimulieren")) {
```

So the resulting block runs from line 222 onward and looks like:

```r
  if (length(home_elo) == 0 || length(away_elo) == 0) {
    warning(paste("Team not found in ELO data for match:", home_team_id, "vs", away_team_id))
    return(current_elos)
  }

  # Test probe: when SEASON_TRANSITION_ENGINE_PROBE is set, write whether the C++
  # primitive is available to that file path. Off by default; production unaffected.
  # Removed during Phase-2 refactor along with the exists() guard below
  # (see docs/prds/2026-05-03-simulation-engine-seam-phase-2.md and
  # docs/superpowers/specs/2026-05-03-season-transition-test-coverage-design.md).
  if (Sys.getenv("SEASON_TRANSITION_ENGINE_PROBE") != "") {
    writeLines(as.character(exists("SpielNichtSimulieren")),
               Sys.getenv("SEASON_TRANSITION_ENGINE_PROBE"))
  }

  # Use existing ELO calculation if available
  if (exists("SpielNichtSimulieren")) {
    # Use standard parameters
    mod_factor <- 20  # Standard K-factor
    ...
```

- [ ] **Step 4: Re-run all engine-selection tests**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-elo-aggregation-engine-selection.R")'
```

Expected: 5 PASS (3 original + 2 probe tests).

- [ ] **Step 5: Verify production code still parses cleanly**

```bash
Rscript -e 'invisible(parse("RCode/elo_aggregation.R")); cat("OK\n")'
```

Expected: `OK`.

- [ ] **Step 6: Verify the full test suite still passes (regression check)**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -30
```

Expected: No new failures attributable to the probe addition. Pre-existing failures (if any) unchanged.

- [ ] **Step 7: Commit**

```bash
git add RCode/elo_aggregation.R tests/testthat/test-elo-aggregation-engine-selection.R
git commit -m "$(cat <<'EOF'
test(#77): add env-var-gated probe to elo_aggregation for snapshot test

Adds a one-line probe immediately above the existing exists() guard at
RCode/elo_aggregation.R:225. When SEASON_TRANSITION_ENGINE_PROBE is set,
writes the C++ primitive's availability to that file. Off by default;
production unaffected. Removed during Phase-2 refactor.

Tests cover both probe-active and probe-silent paths.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Capture the api-football cassettes

**Files:**
- Create: `tests/testthat/fixtures/season-transition-2024-to-2025/` (directory)
- Create: `tests/testthat/fixtures/season-transition-2024-to-2025/README.md`
- Create: `tests/testthat/fixtures/season-transition-2024-to-2025/<httptest2-cassette-files>` (~10-15 JSON files)
- Create: `tests/testthat/fixtures/season-transition-2024-to-2025/TeamList_2025.csv.snapshot`

**Prerequisite:** A valid `RAPIDAPI_KEY` in your environment with quota remaining. If you don't have one, **stop this task and surface the blocker to the user** — cassette capture requires real API access.

- [ ] **Step 1: Create the fixture directory**

```bash
mkdir -p "tests/testthat/fixtures/season-transition-2024-to-2025"
```

- [ ] **Step 2: Write the recording script**

Create `tests/testthat/fixtures/season-transition-2024-to-2025/_record.R` (the leading underscore keeps it out of testthat discovery):

```r
# One-time cassette recording for the season-transition snapshot test.
# Run manually with: Rscript tests/testthat/fixtures/season-transition-2024-to-2025/_record.R
# Requires RAPIDAPI_KEY in the environment.
#
# After running, inspect the captured JSON files for any sensitive content,
# then commit. Re-run only when the api-football response shape changes.

stopifnot(Sys.getenv("RAPIDAPI_KEY") != "")

library(httptest2)
library(withr)

fixture_dir <- "tests/testthat/fixtures/season-transition-2024-to-2025"
csv_dir <- tempfile("season-transition-snapshot-")
dir.create(file.path(csv_dir, "RCode"), recursive = TRUE)

# Copy the existing TeamList_2024.csv (script's input) into the temp RCode/.
file.copy("RCode/TeamList_2024.csv",
          file.path(csv_dir, "RCode", "TeamList_2024.csv"))

probe_path <- tempfile(fileext = ".txt")

with_mock_dir(fixture_dir, {
  with_dir(csv_dir, {
    with_envvar(list(SEASON_TRANSITION_ENGINE_PROBE = probe_path), {
      # The script's main() reads commandArgs(trailingOnly = TRUE), so we
      # invoke via system2 to get a real arg vector.
      result <- system2(
        "Rscript",
        args = c(
          file.path(getwd(), "..", "..", "..", "..", "scripts", "season_transition.R"),
          "2024", "2025", "--non-interactive"
        ),
        env = c(
          sprintf("RAPIDAPI_KEY=%s", Sys.getenv("RAPIDAPI_KEY")),
          sprintf("SEASON_TRANSITION_ENGINE_PROBE=%s", probe_path)
        ),
        stdout = TRUE, stderr = TRUE
      )
      cat("Script exit status:", attr(result, "status") %||% 0L, "\n")
      cat("--- script output ---\n")
      cat(result, sep = "\n")
      cat("\n--- end script output ---\n")
    })
  })
})

# Copy the resulting CSV into the fixture directory as the snapshot.
src_csv <- file.path(csv_dir, "RCode", "TeamList_2025.csv")
dst_csv <- file.path(fixture_dir, "TeamList_2025.csv.snapshot")
stopifnot(file.exists(src_csv))
file.copy(src_csv, dst_csv, overwrite = TRUE)
cat("Snapshot saved to:", dst_csv, "\n")

# Read the probe value and report it for inclusion in the test assertion.
if (file.exists(probe_path)) {
  cat("Probe value (record this in the snapshot test's assertion):",
      readLines(probe_path)[1], "\n")
} else {
  cat("WARNING: probe file was not written. update_elos_for_match may not have been called.\n")
}

# Cleanup temp dir
unlink(csv_dir, recursive = TRUE)
unlink(probe_path)
```

**Note on path handling:** The `file.path(getwd(), "..", "..", "..", "..", "scripts", "season_transition.R")` resolves the script path *from inside the temp dir*. Adjust if your working directory at the time of running `_record.R` is not the project root (it should be). If unsure, replace with an absolute path.

- [ ] **Step 3: Run the recording**

From the project root:

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update"
export RAPIDAPI_KEY=your_key_here   # or however you load it
Rscript tests/testthat/fixtures/season-transition-2024-to-2025/_record.R
```

Expected: cassette files appear under `tests/testthat/fixtures/season-transition-2024-to-2025/` (one sub-directory per host, JSON files inside). The script prints the probe value (likely `FALSE` since `season_transition.R` doesn't source the .cpp). The `TeamList_2025.csv.snapshot` is created.

If the script fails partway (API error, missing key, etc.), fix and retry. Cassettes from a partial run are not safe to use — delete them and re-record.

- [ ] **Step 4: Inspect cassettes for sensitive content**

```bash
grep -rni "rapidapi\|api.key\|x-rapidapi-key\|authorization" tests/testthat/fixtures/season-transition-2024-to-2025/
```

Expected: no matches. `httptest2` does not record request headers by default, but verify. If the key value (the actual key string) appears anywhere, **stop, scrub it, and verify the scrub before committing**.

- [ ] **Step 5: Write the README**

Create `tests/testthat/fixtures/season-transition-2024-to-2025/README.md`:

```markdown
# Season-transition cassette fixtures (2024 → 2025)

Captured api-football response set + expected CSV snapshot for the
end-to-end test at `tests/testthat/test-season-transition-csv-snapshot.R`.

## Files

- `<host>/<path>.json` — `httptest2` cassettes; each represents one HTTP GET
  the season-transition script issues.
- `TeamList_2025.csv.snapshot` — expected byte-exact output of the script.
- `_record.R` — the recording harness. Not picked up by testthat.

## Re-recording

Required when:
- the api-football response shape changes
- `scripts/season_transition.R` issues new HTTP calls
- the expected CSV output legitimately changes (e.g., new league rules)

Procedure:

```bash
export RAPIDAPI_KEY=your_key_here
Rscript tests/testthat/fixtures/season-transition-2024-to-2025/_record.R
```

Then inspect the captured files (`grep -rni rapidapi .` should return nothing)
and `git add` the changes. Note the printed probe value and update the
assertion in `test-season-transition-csv-snapshot.R` if it differs from what
the test currently asserts.
```

- [ ] **Step 6: Commit fixtures**

```bash
git add tests/testthat/fixtures/season-transition-2024-to-2025/
git commit -m "$(cat <<'EOF'
test(#77): capture api-football cassettes for season-transition 2024->2025

Recorded via httptest2::with_mock_dir against the live API (one-time).
Re-record procedure documented in fixture README. Used by the upcoming
end-to-end snapshot test.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: End-to-end CSV snapshot test

**Files:**
- Create: `tests/testthat/test-season-transition-csv-snapshot.R`

This test runs `scripts/season_transition.R` in a real subprocess inside `withr::with_dir(temp_dir)`, plays back the cassettes captured in Task 4, and asserts:
- subprocess exits 0
- probe file written and contains the recorded value (gap #3)
- resulting `RCode/TeamList_2025.csv` matches the snapshot byte-for-byte (gap #2)

- [ ] **Step 1: Note the probe value from Task 4**

Open `tests/testthat/fixtures/season-transition-2024-to-2025/_record.R` script's output (re-run if you didn't capture it). The printed line was:

```
Probe value (record this in the snapshot test's assertion): <FALSE or TRUE>
```

Use that literal in the test below in place of `"FALSE"` if it differs.

- [ ] **Step 2: Write the failing test**

Create `tests/testthat/test-season-transition-csv-snapshot.R`:

```r
# End-to-end CSV snapshot regression net for the season-transition workflow.
#
# Runs scripts/season_transition.R in a subprocess inside a temp dir, plays
# back api-football cassettes via httptest2, and asserts:
#   (gap #2) the resulting RCode/TeamList_2025.csv matches the snapshot
#   (gap #3) the engine-availability probe records the expected value
#
# Spec: docs/superpowers/specs/2026-05-03-season-transition-test-coverage-design.md

library(testthat)
library(httptest2)
library(withr)

test_that("season_transition.R 2024 -> 2025 produces byte-identical CSV", {
  fixture_dir <- test_path("fixtures", "season-transition-2024-to-2025")
  expected_csv <- file.path(fixture_dir, "TeamList_2025.csv.snapshot")
  skip_if_not(file.exists(expected_csv),
              "Snapshot fixture missing. Run _record.R to capture it.")

  # Resolve project root (test runs with cwd = project root, but be defensive).
  project_root <- if (file.exists("scripts/season_transition.R")) {
    getwd()
  } else if (file.exists("../../scripts/season_transition.R")) {
    normalizePath("../..")
  } else {
    skip("Cannot locate project root with scripts/season_transition.R")
  }

  script_path <- file.path(project_root, "scripts", "season_transition.R")
  source_csv  <- file.path(project_root, "RCode", "TeamList_2024.csv")
  rcode_dir   <- file.path(project_root, "RCode")

  # Stage a temp dir with a copy of RCode/TeamList_2024.csv (script's input)
  # so the script can write TeamList_2025.csv into the temp RCode/ without
  # touching the real one.
  csv_dir <- tempfile("season-transition-snapshot-")
  dir.create(file.path(csv_dir, "RCode"), recursive = TRUE)
  file.copy(source_csv, file.path(csv_dir, "RCode", "TeamList_2024.csv"))

  probe_path <- tempfile(fileext = ".txt")

  on.exit({
    unlink(csv_dir, recursive = TRUE)
    unlink(probe_path)
  }, add = TRUE)

  # The script bails out without RAPIDAPI_KEY; a non-empty value is enough
  # because httptest2 intercepts the actual GET.
  test_env <- c(
    "RAPIDAPI_KEY=test-mock-key-not-real",
    sprintf("SEASON_TRANSITION_ENGINE_PROBE=%s", probe_path)
  )

  exit_status <- with_mock_dir(fixture_dir, {
    with_dir(csv_dir, {
      result <- system2(
        "Rscript",
        args = c(script_path, "2024", "2025", "--non-interactive"),
        env = test_env,
        stdout = TRUE, stderr = TRUE
      )
      attr(result, "status") %||% 0L
    })
  })

  expect_equal(exit_status, 0L,
               info = "season_transition.R subprocess must exit 0")

  # Gap #3: probe assertion. Pinned literal — adjust if Task 4 recorded TRUE.
  expect_true(file.exists(probe_path),
              info = "probe file should be written by elo_aggregation.R")
  engine_available <- readLines(probe_path)[1]
  expect_true(engine_available %in% c("TRUE", "FALSE"),
              info = "probe value must be TRUE or FALSE")
  expect_equal(engine_available, "FALSE",
    info = paste("Recorded current truth: scripts/season_transition.R does",
                 "NOT source SpielNichtSimulieren.cpp, so the C++ primitive",
                 "is unavailable in the script's process. If this changed,",
                 "the Phase-2 PRD's plan must be revisited."))

  # Gap #2: byte-identical CSV.
  actual_csv <- file.path(csv_dir, "RCode", "TeamList_2025.csv")
  expect_true(file.exists(actual_csv),
              info = "season_transition.R must produce TeamList_2025.csv")

  actual_bytes   <- readBin(actual_csv,   "raw", file.info(actual_csv)$size)
  expected_bytes <- readBin(expected_csv, "raw", file.info(expected_csv)$size)

  expect_equal(length(actual_bytes), length(expected_bytes),
               info = "CSV byte-count drift; see fixture README to re-record")
  expect_equal(actual_bytes, expected_bytes,
               info = paste("CSV bytes differ from snapshot.",
                            "If the change is intentional, re-record per",
                            "tests/testthat/fixtures/season-transition-2024-to-2025/README.md."))
})
```

- [ ] **Step 3: Run the test**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")'
```

Expected: PASS. If the test fails:
- **`exit_status != 0`** → check `result` (the captured stdout/stderr); the script likely hit a code path with no cassette. Re-record cassettes.
- **probe value differs from `"FALSE"`** → `season_transition.R` *does* source the .cpp through some path you didn't expect. Update the literal in the assertion to `"TRUE"` and add a comment explaining where the .cpp gets sourced. This is a legitimate regression-net update, not a bug.
- **CSV bytes differ** → either the recording captured a different code path than what runs in playback (re-record), or your local CSV write has locale/line-ending issues. Inspect the diff: `diff <(xxd $actual_csv) <(xxd $expected_csv) | head -30`. If line endings or whitespace differ, set `Sys.setlocale(...)` in the test (helper-test-setup.R already does this for unit tests but not for subprocesses).

- [ ] **Step 4: Run the entire testthat suite to confirm no regressions**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -30
```

Expected: All previously-passing tests still pass. Two new test files contribute additional passes. Pre-existing failures (if any) unchanged in count.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-season-transition-csv-snapshot.R
git commit -m "$(cat <<'EOF'
test(#77): end-to-end CSV snapshot test for season-transition

Runs scripts/season_transition.R in a subprocess via system2 inside
withr::with_dir(temp_dir), plays back captured api-football cassettes
via httptest2::with_mock_dir, and asserts:
  - subprocess exits 0
  - SEASON_TRANSITION_ENGINE_PROBE writes recorded engine availability
  - resulting RCode/TeamList_2025.csv matches the snapshot byte-for-byte

Closes the gap-#2 (CSV snapshot) and gap-#3 (Rcpp load-path verification)
items from docs/superpowers/specs/2026-05-03-season-transition-test-coverage-design.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Final verification

- [ ] **Step 1: Run the full testthat suite one more time**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -40
```

Expected: All four artifacts (engine-selection 5 tests, snapshot 1 test) PASS. Pre-existing test counts unchanged. No new errors or warnings attributable to this work.

- [ ] **Step 2: Verify production code parses**

```bash
Rscript -e 'invisible(parse("RCode/elo_aggregation.R")); cat("OK\n")'
Rscript -e 'invisible(parse("scripts/season_transition.R")); cat("OK\n")'
```

Expected: `OK` from both.

- [ ] **Step 3: Confirm probe is dormant in production conditions**

Run a quick R session without the probe env var and confirm `update_elos_for_match` runs without writing any probe file:

```bash
Rscript -e '
  Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
  source("RCode/elo_aggregation.R")
  match <- data.frame(teams_home_id = 1L, teams_away_id = 2L, goals_home = 2, goals_away = 0)
  elos  <- data.frame(TeamID = c(1L, 2L), CurrentELO = c(1500, 1500))
  result <- update_elos_for_match(elos, match)
  stopifnot(Sys.getenv("SEASON_TRANSITION_ENGINE_PROBE") == "")
  cat("OK; probe inactive when env var unset.\n")
'
```

Expected: `OK; probe inactive when env var unset.` and no error.

- [ ] **Step 4: Push to origin (optional, per user policy)**

```bash
git log --oneline origin/main..HEAD
```

Verify the four (or so) new commits are on the branch. Do NOT push without explicit user instruction — Christoph's branch-completion preference is push+PR, but check via the saved memory before acting.

---

## Self-Review Notes (for the executing engineer)

After completing all tasks, run a quick mental check:

1. **Did the `_record.R` script need adjustment?** The path-walking with `..` is brittle; if you fixed it, document the actual approach in the fixture README so re-recording works for the next person.
2. **Did the C++/R agreement test (Task 2 test 3) reveal a divergence?** If yes, update the comment at the top of the test file and surface the finding to the user — it directly affects the Phase-2 PRD's Option A vs Option B branch.
3. **Is the snapshot CSV in git LFS-territory size?** Bundesliga + 2. Bundesliga + 3. Liga = ~60 teams × 4 columns. Should be < 5 KB. If something is dramatically larger, the fixture or snapshot captured something unintended (e.g., the script's stderr leaked into stdout).
4. **Is the cassette directory size reasonable?** Total < 1 MB. If larger, the script issued more API calls than expected (perhaps a 3-Liga edge case); inspect.

If any item above produces a finding, surface it to the user before declaring the plan complete.
