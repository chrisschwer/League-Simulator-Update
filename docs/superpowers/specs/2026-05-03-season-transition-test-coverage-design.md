# Season-transition test-coverage gap fill

**Date:** 2026-05-03
**Source:** superpowers:brainstorming
**Status:** Spec — awaiting writing-plans
**Related:** `docs/prds/2026-05-03-simulation-engine-seam-phase-2.md` (this spec is the prerequisite regression net for that PRD), issue #76 (CI rebuild — execution gating only applies to the Phase-2 PRD, not to this spec; tests are non-destructive and safe to add now)

## Goal

Add a regression net for the season-transition workflow that pins three currently-untested invariants:

1. Which ELO engine path runs when `update_elos_for_match` is called (gap #1).
2. The byte-exact `RCode/TeamList_<year>.csv` output of a full `Rscript scripts/season_transition.R --non-interactive` run (gap #2).
3. Which entry points cause `Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")` to make `SpielNichtSimulieren` available at runtime (gap #3).

The net tests **current behavior**, not intended behavior — its job is to make the Phase-2 refactor at `docs/prds/2026-05-03-simulation-engine-seam-phase-2.md` safe to execute by surfacing any output drift the refactor introduces.

## Non-goals

- No re-architecture of `api_service.R` for testability (`httptest2` works at the `httr::GET` layer).
- No new orchestration tests for `process_season_transition` (the existing 10 tests in `test-season-transition-regression.R` already cover structural assertions).
- No tests of the C++ R-wrapper layer (`SpielCPP.R`, `simulationsCPP.R`, `SaisonSimulierenCPP.R`, `leagueSimulatorCPP.R`, `cpp_wrappers.R`) — those are scheduled for deletion in Phase 2; testing them is wasted work.
- No fixing of the silent-fallback architecture itself. That's Phase 2's job. This spec only **measures** the current behavior so the fix is safe.

## Architecture

Three new test artifacts, one one-line production-code touch. No new runtime dependencies. One new test dependency (`httptest2`).

### Artifact 1 — `tests/testthat/test-elo-aggregation-engine-selection.R`

Pure unit test against `update_elos_for_match` from `RCode/elo_aggregation.R`. No fixtures, no subprocess, no API stubs. Three `test_that` blocks:

- **C++-path test.** Source `RCode/SpielNichtSimulieren.cpp` via `Rcpp::sourceCpp` at test setup so `SpielNichtSimulieren` is defined. Source `RCode/elo_aggregation.R`. Build a fixed `match` record (home_id=1, away_id=2, goals 2-0) and a fixed `current_elos` data frame (both teams at ELO 1500). Call `update_elos_for_match`. Assert the returned ELO matches a hand-computed value derived from the C++ formula at `SpielNichtSimulieren.cpp:18-32` (`ELOProb`, `goalMod`, `ELOModificator` arithmetic). Pin both home and away ELO outputs.

- **R-fallback path test.** In a fresh local environment (use `local()` or a child env, then `rm("SpielNichtSimulieren", envir = ...)` if the helper sourced it), call `update_elos_for_match` against the same fixed inputs. Assert the returned ELO matches the R fallback's output (`calculate_elo_update` from `elo_aggregation.R:252+`). Computed once and pinned as a literal in the test (do not re-derive at test runtime — that would just test the function against itself).

- **Agreement test.** Call both paths against a small parameter sweep (3-5 fixed match records covering wins, draws, losses, asymmetric ELOs). For each, compare the C++ and R results. The assertion is *whichever the truth is today*: if every C++/R pair is `expect_equal` within numerical tolerance, the test asserts equality; if any pair diverges, the test asserts the divergence with a comment recording the magnitude. The test author runs the comparison once, sees the answer, and writes the assertion to match. This pins reality and turns any future drift into a failure.

The agreement test's verdict is the load-bearing input to the Phase-2 PRD's Option A vs Option B branch.

### Artifact 2 — `tests/testthat/fixtures/season-transition-2024-to-2025/`

Recorded api-football response set, captured via `httptest2::with_mock_dir()` on a one-time live run against the real api-football API. Contains:

- One sub-directory per host (per `httptest2` convention).
- JSON cassette files for every HTTP GET the script issues during a 2024→2025 transition: source-season completion check, league standings (Bundesliga / 2. Bundesliga / 3. Liga), team rosters per league.
- The expected output CSV at `tests/testthat/fixtures/season-transition-2024-to-2025/TeamList_2025.csv.snapshot`, captured from the same one-time run.

Total size estimate: 50–500 KB across ~10–15 files. Committed verbatim. Re-recording procedure documented in a `README.md` at the fixture root: set `HTTPTEST2_RECORD=true` and re-run the snapshot test once with valid `RAPIDAPI_KEY`.

`httptest2` is added as a single new line to `test_packagelist.txt`.

### Artifact 3 — `tests/testthat/test-season-transition-csv-snapshot.R`

End-to-end snapshot test. One `test_that` block:

```r
test_that("season_transition.R 2024 -> 2025 produces byte-identical CSV", {
  probe_path <- tempfile(fileext = ".txt")
  csv_dir <- tempfile()
  dir.create(csv_dir)
  on.exit(unlink(c(probe_path, csv_dir), recursive = TRUE), add = TRUE)

  # The fixture directory and snapshot live alongside this test file.
  fixture_dir <- test_path("fixtures", "season-transition-2024-to-2025")
  expected_csv <- file.path(fixture_dir, "TeamList_2025.csv.snapshot")

  # Resolve actual output path during writing-plans (see Open Questions). Either:
  #   (a) script honors RCODE_OUTPUT_DIR env var → CSV at file.path(csv_dir, "TeamList_2025.csv")
  #   (b) script writes to RCode/ in cwd → wrap system2 in withr::with_dir(csv_dir, { ... })
  #       and read CSV at file.path(csv_dir, "RCode", "TeamList_2025.csv")
  # Pseudocode below assumes (a); plan picks (a) or (b) once verified.
  httptest2::with_mock_dir(fixture_dir, {
    result <- system2(
      "Rscript",
      args = c("scripts/season_transition.R", "2024", "2025", "--non-interactive"),
      env = c(
        sprintf("SEASON_TRANSITION_ENGINE_PROBE=%s", probe_path),
        sprintf("RCODE_OUTPUT_DIR=%s", csv_dir)
      ),
      stdout = TRUE, stderr = TRUE
    )
    expect_equal(attr(result, "status") %||% 0L, 0L)
  })

  # Gap #3: probe file written by the production-code probe at elo_aggregation.R:225
  expect_true(file.exists(probe_path))
  engine_available <- readLines(probe_path)[1]
  expect_true(engine_available %in% c("TRUE", "FALSE"))
  # Document the current truth in the test message so a future reader sees it without
  # running the test. Literal value pinned during initial cassette capture (step 4).
  expect_equal(engine_available, "FALSE",
    info = "Recorded current truth: scripts/season_transition.R does not source the .cpp.")

  # Gap #2: byte-identical CSV
  actual_csv <- file.path(csv_dir, "TeamList_2025.csv")  # adjust per (a)/(b) above
  expect_true(file.exists(actual_csv))
  expect_equal(
    readBin(actual_csv, "raw", file.info(actual_csv)$size),
    readBin(expected_csv, "raw", file.info(expected_csv)$size)
  )
})
```

The `expect_equal(engine_available, "FALSE", ...)` line pins whichever value the one-time recording captures. If the recording shows `TRUE` (script does source the `.cpp` somehow), flip the literal. The test author writes the truth, not the wish.

### Production-code touch — `RCode/elo_aggregation.R:225`

Exactly one line added immediately above the existing `if (exists("SpielNichtSimulieren")) {` guard:

```r
update_elos_for_match <- function(current_elos, match) {
  # ... existing code through line 224 ...

  # Test probe: when SEASON_TRANSITION_ENGINE_PROBE is set, write whether the C++
  # primitive is available to that file path. Off by default; production unaffected.
  # Removed during Phase-2 refactor (see docs/prds/2026-05-03-simulation-engine-seam-phase-2.md).
  if (Sys.getenv("SEASON_TRANSITION_ENGINE_PROBE") != "") {
    writeLines(as.character(exists("SpielNichtSimulieren")),
               Sys.getenv("SEASON_TRANSITION_ENGINE_PROBE"))
  }

  if (exists("SpielNichtSimulieren")) {
    # ... existing code unchanged ...
```

Behavior in production: env var unset → `Sys.getenv` returns `""` → conditional false → no-op. Zero blast radius.

The probe and the surrounding `exists()` guard are both deleted in the Phase-2 refactor (PRD acceptance criterion: "no longer contains the `if (exists("SpielNichtSimulieren"))` guard at line 225"), so this is genuinely temporary scaffolding.

### Optional fallback if the script can't redirect output dir

If `scripts/season_transition.R` writes `RCode/TeamList_2025.csv` only to a hard-coded `RCode/` path with no env-var override, the test does one of:
1. `setwd()` into a temp dir, copy `RCode/` to it first, run the script, read the resulting `RCode/TeamList_2025.csv` from the temp `RCode/`. Reset cwd in `on.exit`.
2. Wrap the `system2` call in a `withr::with_dir` block.

Decided during writing-plans based on a quick read of the script's output-path handling. Either works; the test design above doesn't depend on which.

## Data flow

```
test-elo-aggregation-engine-selection.R   (no fixtures, no subprocess)
    └─ source RCode/SpielNichtSimulieren.cpp + RCode/elo_aggregation.R
       call update_elos_for_match in two controlled environments
       compare and pin the answers

test-season-transition-csv-snapshot.R
    │
    ├─ httptest2::with_mock_dir(fixtures/season-transition-2024-to-2025/)
    │       (intercepts httr::GET, serves cassette files)
    │
    ├─ system2("Rscript", scripts/season_transition.R 2024 2025 --non-interactive)
    │       env: SEASON_TRANSITION_ENGINE_PROBE=/tmp/probe-XXX.txt
    │
    │   └─ subprocess:
    │       sources modules per scripts/season_transition.R
    │       hits stubbed httr::GET → reads JSON cassettes
    │       calls elo_aggregation.R update_elos_for_match
    │           └─ probe writes "TRUE" or "FALSE" to probe file
    │       writes RCode/TeamList_2025.csv to (temp) RCode/
    │
    ├─ assert: probe file contains the recorded value (gap #3)
    ├─ assert: probe file value equals the documented current truth
    ├─ assert: TeamList_2025.csv bytes match snapshot (gap #2)
    └─ assert: subprocess exit code == 0
```

## Components

| Component | Path | Purpose |
|---|---|---|
| Engine-selection unit test | `tests/testthat/test-elo-aggregation-engine-selection.R` | Gap #1. Pin C++-path output, R-fallback output, and whether they agree. |
| API cassette directory | `tests/testthat/fixtures/season-transition-2024-to-2025/` | Recorded api-football responses + expected CSV snapshot + re-record README. |
| End-to-end snapshot test | `tests/testthat/test-season-transition-csv-snapshot.R` | Gap #2 + gap #3 (via probe). Run real script, assert byte-identical CSV and recorded engine availability. |
| Probe injection | `RCode/elo_aggregation.R` (one line above the existing line 225 guard) | Gap #3 mechanism. Off by default. |
| Test dependency | `test_packagelist.txt` (one new line: `httptest2`) | Cassette playback. |

## Error handling

- **Cassette miss** (`httptest2` can't find a fixture for a request the script makes) → `httptest2` raises by default; the test fails with a clear message naming the missing URL. Recovery: re-record cassettes with `HTTPTEST2_RECORD=true`.
- **Subprocess crash** (`system2` returns non-zero status) → `expect_equal(attr(result, "status") %||% 0L, 0L)` fails with the captured stderr in the diagnostic.
- **Missing `RAPIDAPI_KEY` during re-record** → the re-record README documents this; the test in normal run mode never needs the key (cassettes are pre-recorded).
- **Snapshot drift** (CSV bytes differ) → the assertion fails with `readBin` raw-vector diff. The test message points the reader at the re-record procedure and the snapshot path so they can diff manually.
- **Probe file not written** (env var passed but probe never reached, e.g., `update_elos_for_match` not called during the transition) → `expect_true(file.exists(probe_path))` fails. This is a meaningful regression signal: it would mean the transition no longer calls the ELO update path, which is itself a bug.

## Test strategy

This spec *is* the test strategy for the season-transition workflow. The tests added by this spec themselves don't need meta-tests, with one exception:

- The C++-path expected ELO values in `test-elo-aggregation-engine-selection.R` are hand-derived from `SpielNichtSimulieren.cpp:18-32`. They are cross-checked against `tests/testthat/test-SpielNichtSimulieren.R`'s existing 11 tests, which pin the same primitive at a lower level. If the hand-derivation drifts from `test-SpielNichtSimulieren.R`'s assertions, both sets fail and the discrepancy is loud.

## Migration / sequencing

1. Add `httptest2` to `test_packagelist.txt`. Install locally (`install.packages("httptest2")`).
2. Write `test-elo-aggregation-engine-selection.R`. Run. Discover whether C++ and R formulas agree. Write the agreement assertion to match. Commit.
3. Add the one-line probe to `RCode/elo_aggregation.R`. Verify production paths still work (`Rscript -e 'invisible(parse("RCode/elo_aggregation.R")); cat("OK\n")'`).
4. Capture the cassettes: with `HTTPTEST2_RECORD=true` and a valid `RAPIDAPI_KEY`, run the snapshot test against `Rscript scripts/season_transition.R 2024 2025 --non-interactive` once. Inspect the captured CSV by hand against current production CSV; if they match, save as `TeamList_2025.csv.snapshot`. If they differ, investigate before committing — the recording itself may have hit a different code path than production.
5. Write `test-season-transition-csv-snapshot.R`. Run with cassettes. Confirm green. Commit.
6. Suggested commit split: (a) `test: add httptest2 dep + engine-selection unit test`, (b) `test: add season-transition probe + cassette + CSV snapshot test`.

## Risks

- **Risk:** `httptest2` cassette format becomes incompatible across versions, breaking the test in CI under a different package version.
  - **Mitigation:** Pin `httptest2` version in `test_packagelist.txt` if necessary. Cassettes are plain JSON files written by `httptest2` — readable and re-recordable, not a brittle binary format.

- **Risk:** The recorded cassettes contain api-football response data that includes IDs, names, or values that we don't want in the public repo (e.g., something the API marks as restricted).
  - **Mitigation:** Inspect cassette contents before committing. api-football team data is public-by-design (rosters, ELOs are derived not transmitted). No PII concern for football fixture data. If anything sensitive surfaces, scrub it before commit.

- **Risk:** The `RAPIDAPI_KEY` accidentally leaks into a cassette (e.g., recorded as a request header).
  - **Mitigation:** `httptest2` does not record request headers by default. Verify before commit by grepping the cassette directory for the key value.

- **Risk:** The snapshot CSV is fragile because of locale-dependent number formatting in R (`,` vs `.` decimal, line endings).
  - **Mitigation:** Lock the test environment: set `Sys.setlocale("LC_NUMERIC", "C")` at the top of the test, normalize line endings if needed in the comparison. The known-issues doc has a precedent here (issue #53 on locale-dependent ConfigMap tests).

- **Risk:** The probe pattern (env-var-gated write) is novel for this codebase and a future maintainer removes it without realizing the test depends on it.
  - **Mitigation:** Inline comment at the probe site explicitly names the test file and the Phase-2 PRD. Probe is removed by Phase-2 anyway, so its lifespan is bounded.

- **Risk:** `system2` invocation of `Rscript` doesn't find the right working directory or `RCode/` path on different machines (Christoph's macOS vs CI Linux container).
  - **Mitigation:** `setwd(rprojroot::find_root(...))` or use `here::here()` (already a dependency at `packagelist.txt:19`) inside the test to resolve paths from the project root. Test should pass on both.

## Open questions

- **Does `scripts/season_transition.R` honor an `RCODE_OUTPUT_DIR` env var, or is `RCode/TeamList_2025.csv` hard-coded?** If hard-coded, use the `setwd()` fallback in the snapshot test (described above). Determined during writing-plans by reading `season_processor.R` and `csv_generation.R`'s file-write paths.
- **What does `--non-interactive` actually default to for new teams' `ShortText`?** The snapshot pins whatever it does; if the default is randomized (e.g., a UUID or timestamp), the snapshot is non-deterministic and the spec needs adjustment (seed the RNG or stub the prompt). Determined when capturing the cassettes.
- **Is the `tests/testthat/test-spielcpp-contract.R` file (added by `4698a58`) duplicating any of the engine-selection coverage?** Read its 3 tests during writing-plans; if there's overlap and the file is being deleted in Phase 2 anyway, no action — let Phase 2 delete it. If a useful test there isn't duplicated, port the assertion to the new test file.
- **Should the snapshot test be marked as a slow test (skipped in fast CI)?** Subprocess + cassette playback is probably 5-30s. Acceptable for the full suite but may want a `skip_on_cran()`-style gate. Decided when CI is rebuilt under #76.

## Adjacent observations

- The probe pattern is one-shot scaffolding for this PRD's Phase 2. If the codebase grows other "is X loaded right now?" questions, a small `RCode/test_probes.R` helper module (env-var-gated writes, only active when probe paths are set) could generalize it. Out of scope here; flag for future review only.
- The fact that the silent-fallback exists at all is the actual architectural smell. This spec doesn't fix it — Phase 2 does. But this spec makes it visible and measurable, which is the precondition for fixing it safely.
