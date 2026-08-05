# Retire C++ engine, collapse to single Rust simulation seam

**Scope:** `RCode/rust_integration.R`, `RCode/update_all_leagues_loop_rust.R`, and the C++ engine files (`RCode/leagueSimulatorCPP.R`, `RCode/simulationsCPP.R`, `RCode/SaisonSimulierenCPP.R`, `RCode/SpielCPP.R`, `RCode/SpielNichtSimulieren.cpp`, `RCode/cpp_wrappers.R`, `RCode/RcppExports.R`)
**Date:** 2026-05-02
**Source:** architecture-review-prd skill

> **⚠️ Constraint discovered after first draft (2026-05-02):** `RCode/SpielCPP.R` is sourced by `scripts/season_transition.R:65` (in `existing_modules`). The original recommendation to delete the entire C++ engine in one pass was wrong — it would break the season-transition operator workflow described in `docs/SEASON_TRANSITION_UPDATES.md` and tracked by issue #74. This PRD now splits into **two phases**: Phase 1 (in scope here) removes the duplicated fallback wiring in the production loop without deleting the C++ source files; Phase 2 (deferred) decides whether `SpielCPP.R` and friends survive permanently as the season-transition's reference engine, or whether season-transition migrates to the Rust seam too. See "Suggested Phasing" at the bottom.

## Goal

**Phase 1:** `leagueSimulatorRust()` is the only simulation entry point invoked by the production loop, called unconditionally by `update_all_leagues_loop()`. The duplicated fallback logic (loop-level `if (use_rust)` plus per-call check inside `leagueSimulatorRust`) is gone. When the Rust server is unavailable, the scheduler fails fast with a clear error. The C++ source files **remain in the repo** because `scripts/season_transition.R` sources `SpielCPP.R`. The brittle `Rcpp::sourceCpp` build step in `Dockerfile.integrated:101–104` is removed only if the production container has no remaining need for the compiled C++ — which it does not, since the deleted fallback was its only consumer.

## Goal — what changes for the user

The production scheduler stops asking the same "is Rust up?" question in three different places, and stops silently substituting C++ for Rust when the answer is no. Failures surface clearly. The Docker build loses the brittle `Rcpp::sourceCpp()` step that already has a documented failure mode (`Dockerfile.integrated:103` — `|| echo "Warning: C++ compilation failed, will rely on Rust engine"`) — because it was only there to enable the now-deleted fallback. The C++ engine source files remain in the repo for the season-transition workflow's use; deciding their long-term fate is Phase 2.

## Architecture

`update_all_leagues_loop()` (renamed from `_rust`) sources `rust_integration.R` once at the top, asserts Rust availability before entering the loop, and calls `leagueSimulatorRust()` directly. There is no `if (use_rust)` branch, no `use_rust` parameter, no C++ source-on-demand. The Rust REST seam at `localhost:8080` is the only simulation interface; the engine is genuinely external from R's perspective. `rust_integration.R` shrinks: `leagueSimulatorRust()` no longer needs its internal C++ fallback (lines 150–156), because the only caller has already asserted Rust is up.

## Tech Stack

R 4.3.1, `httr` and `jsonlite` for the Rust REST client, the existing Rust crate at `league-simulator-rust/`. No new dependencies. **The `Rcpp` package stays in `packagelist.txt`** because `SpielCPP.R` (used by season-transition) is built on it. Removing Rcpp is deferred to Phase 2.

## The Finding

### Current State

- **Public entry point:** `leagueSimulatorRust(season, n, modFactor, homeAdvantage, numberTeams, adjPoints, adjGoals, adjGoalsAgainst, adjGoalDiff)` at `RCode/rust_integration.R:142`. Documented as a "Drop-in Replacement" for `leagueSimulatorCPP`.
- **Orchestrator:** `update_all_leagues_loop_rust(duration, loops, initial_wait, n, saison, TeamList_file, shiny_directory, use_rust = TRUE)` at `RCode/update_all_leagues_loop_rust.R:4`. Loops over Bundesliga / 2.Bundesliga / 3.Liga; selects the simulator function via `simulator_function <- if (use_rust) leagueSimulatorRust else leagueSimulatorCPP` (line 104).
- **C++ implementation:** `leagueSimulatorCPP()` at `RCode/leagueSimulatorCPP.R`, plus `simulationsCPP.R`, `SaisonSimulierenCPP.R`, `SpielCPP.R`, and the C++ source `SpielNichtSimulieren.cpp` (compiled at runtime via `Rcpp::sourceCpp`). `cpp_wrappers.R` and `RcppExports.R` are the Rcpp glue.
- **Two layers of fallback for the same condition:**
  1. `update_all_leagues_loop_rust.R:30–34` — if `connect_rust_simulator()` returns `FALSE`, set `use_rust <- FALSE` and source the C++ files instead.
  2. `rust_integration.R:151–156` — `leagueSimulatorRust()` itself calls `connect_rust_simulator()` at the start of *every* call, and falls back to `leagueSimulatorCPP()` per-call if Rust is down.
- **Production callers:** `RCode/updateSchedulerRust.R:48` (sources `update_all_leagues_loop_rust.R`) and `:152` (sources `rust_integration.R`). The scheduler also calls `connect_rust_simulator()` at line 153 before invoking the loop.
- **Test callers of CPP files:** `tests/testthat/test-SaisonSimulierenCPP.R`, `test-simulationsCPP.R`, `test-SpielCPP.R`, `test-SpielNichtSimulieren.R` (per the grep in Phase 2). Plus comparison harnesses: `tests/rust/test_rust_vs_cpp_detailed.R`, `tests/rust/test_match_order_verification.R`, `tests/rust/test_rust_elo.R`, `compare_rust_cpp.R`, `compare_rust_vs_r.R` in repo root.
- **Operator-facing docs that mention the CPP engine:** `docs/architecture/overview.md` ("Rcpp Integration: 100x speedup for critical paths"), `RUST_INTEGRATION.md`, `RUST_RNG_FIX_RESULTS.md`, `Dockerfile.integrated:101–104` ("Compile C++ code (fallback when Rust unavailable)").
- **Season-transition caller of `SpielCPP.R`:** `scripts/season_transition.R:65` lists `SpielCPP.R` in `existing_modules` (alongside `retrieveResults.R` and `transform_data.R`). The transition workflow is operator-invoked outside the Docker container; per `docs/SEASON_TRANSITION_UPDATES.md` it produces fresh `RCode/TeamList_<year>.csv` files between seasons. **This is the single concrete reason the C++ files cannot be deleted in Phase 1.** Whether `SpielCPP.R` is still actually *needed* by the transition (vs. inherited from when it was the only engine) is the question Phase 2 must answer.
- **Test coverage today:** Per `CLAUDE.md` and `docs/TEST_FIX_PLAN.md`, "38 tests failing — repair in progress." Specific Rust integration tests exist (`tests/test_rust_integration.R`, `tests/rust/`) but the broader suite is broken. The CPP-specific testthat files presumably worked when the CPP engine was canonical; their status today is unverified.

### Why this is a problem

There are three separate places where "is Rust available?" is asked: `updateSchedulerRust.R:153`, `update_all_leagues_loop_rust.R:31`, and `rust_integration.R:151`. The third one runs *inside every league simulation call*, on every loop iteration, even though the answer was already established at scheduler startup. The fallback path it offers — `leagueSimulatorCPP()` at `rust_integration.R:153` — only works if the C++ files have been sourced, which only happens if `update_all_leagues_loop_rust.R:38` already detected Rust was down. So if Rust dies *between* the loop's check (line 31) and the per-call check (line 151), the fallback fails on a missing function rather than gracefully degrading. The fallback code runs in the wrong place to do its job.

That's the leaky-interface lens: callers must understand a non-obvious ordering (loop-level check sources CPP files; per-call check assumes they're sourced) for the fallback to actually fall back. The deletion test: removing `leagueSimulatorCPP()` and the loop's `if (use_rust)` branch bundles the "which engine?" question to one place — scheduler startup — and lets every downstream call assume the answer.

The deeper finding is about ownership of the engine choice. `b4fbb96` ("Switch to Rust simulation engine in production") and `b11f068` ("Successfully integrate Rust simulation engine in production") committed in August 2025 made the decision. The fallback code is therefore not a runtime safety net — it's an unfinished migration. The cost of keeping it: the brittle `Rcpp::sourceCpp` step at Docker build time (which already documents itself as a possible failure: `Dockerfile.integrated:104`), ~400 lines of C++ glue code in active sources, and the cognitive load of understanding two engines instead of one.

This is also a production stability issue, not just code hygiene. A silent fallback to C++ on every Rust hiccup hides the real problem (Rust server died). Failing fast surfaces it.

## Interface — Before / After

```r
# BEFORE (RCode/update_all_leagues_loop_rust.R)
update_all_leagues_loop_rust <- function(duration = 480, loops = 31, initial_wait = 0,
                                         n = 10000, saison = "2023",
                                         TeamList_file = "RCode/TeamList_2023.csv",
                                         shiny_directory = "...",
                                         use_rust = TRUE) {
  # ...
  if (use_rust) {
    source("RCode/rust_integration.R")
    if (!connect_rust_simulator()) {
      use_rust <- FALSE
    }
  }
  if (!use_rust) {
    Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
    source("RCode/leagueSimulatorCPP.R")
    source("RCode/SaisonSimulierenCPP.R")
    source("RCode/simulationsCPP.R")
    source("RCode/SpielCPP.R")
  }
  # ...
  simulator_function <- if (use_rust) leagueSimulatorRust else leagueSimulatorCPP
  # ...
}

# BEFORE (RCode/rust_integration.R:142)
leagueSimulatorRust <- function(season, n = 10000, ...) {
  if (!connect_rust_simulator()) {
    message("Falling back to C++ implementation...")
    return(leagueSimulatorCPP(season, n, ...))    # only works if CPP files were sourced
  }
  # ...
}

# AFTER (RCode/update_all_leagues_loop.R)   # renamed; see deployment-surface PRD
update_all_leagues_loop <- function(duration = 480, loops = 31, initial_wait = 0,
                                    n = 10000, saison = "2023",
                                    TeamList_file = "RCode/TeamList_2023.csv",
                                    shiny_directory = "...") {
  # ...
  source("RCode/rust_integration.R")
  if (!connect_rust_simulator()) {
    stop("Rust simulator not available at ", RUST_API_URL,
         ". Check that the Rust server is running before starting the scheduler.")
  }
  # ...
  source("RCode/prozent.R")
  source("RCode/retrieveResults.R")
  source("RCode/Tabelle.R")
  source("RCode/transform_data.R")
  source("RCode/updateShiny.R")
  # ...
  Ergebnis  <- leagueSimulatorRust(BL,    n = n)
  Ergebnis2 <- leagueSimulatorRust(BL2,   n = n)
  Ergebnis3 <- leagueSimulatorRust(Liga3, n = n)
  Ergebnis3_Aufstieg <- leagueSimulatorRust(Liga3, n = n, adjPoints = adjPoints_Liga3_Aufstieg)
  # ...
}

# AFTER (RCode/rust_integration.R:142)
leagueSimulatorRust <- function(season, n = 10000, ...) {
  # No connect check, no fallback — caller has already asserted availability.
  # Rust API call failures still raise via stop() in simulate_league_rust().
  # ...
}
```

**Renames:** the `_rust` qualifier on `update_all_leagues_loop_rust.R` and `update_all_leagues_loop_rust()` becomes meaningless once there's only one engine. The deployment-surface PRD already specifies the file rename to `update_all_leagues_loop.R`; this PRD adds the function rename to `update_all_leagues_loop()`. The exported simulator function `leagueSimulatorRust()` keeps its name — the `Rust` is informative (it tells you where the work happens), unlike `_rust` on the orchestrator (which only existed to distinguish from the dead alternative).

## Design Options Considered

### Option A — Delete C++ entirely, fail fast on Rust outage *(recommended)*

> Sketch: Remove all CPP files. Move the Rust-availability check to the scheduler layer (it's already there at `updateSchedulerRust.R:153`) and the loop entry. On failure, `stop()` instead of falling back. `leagueSimulatorRust()` no longer checks per-call.
> Trade-off: Loses the safety net entirely. Wins on simplicity, build reliability, and on actually-surfacing Rust outages instead of masking them. The "safety net" is largely illusory anyway because the per-call fallback only works under conditions the surrounding code has to set up.
> Migration cost: ~2–3 hours. Delete 7 files, edit 2, update tests that reference CPP entry points, decide what to do with `tests/testthat/test-*CPP*.R` (likely delete since the engine is gone), update `Dockerfile.integrated` to remove the `Rcpp::sourceCpp` step.

### Option B — Keep C++ as an isolated alternative implementation, no in-process fallback

> Sketch: Keep CPP files in `RCode/`, source them only in the test suite (for engine-equivalence regression tests), but never in production. Production code calls only `leagueSimulatorRust()`. The seam stays clean; CPP becomes a test-only reference implementation.
> Trade-off: Preserves the cross-engine equivalence test (which is genuinely valuable — `compare_rust_cpp.R` exists for a reason). Costs you the build-time `Rcpp::sourceCpp` step in Docker (still needed for tests if tests run in CI, though the next-PRD CI rebuild may not include CPP tests). Higher cognitive load than A: contributors still see CPP files in the source tree and may wonder when they're called.
> Migration cost: ~3 hours. Same deletions of fallback wiring as A, but keeps the CPP files. Need to clearly mark them as test-only (a header comment, a directory move to `RCode/legacy/` or `tests/reference-engine/`).

### Option C — Configurable engine via env var, runtime-pluggable

> Sketch: `SIMULATION_ENGINE=rust|cpp` env var; a small dispatch function returns the right `leagueSimulator*`. No fallback — fail fast on whichever engine is configured.
> Trade-off: Maximum flexibility, lowest commitment. But you've already committed (per `b4fbb96`); flexibility you don't use is just complexity. The dispatch indirection is the kind of "premature seam" that lives in the codebase forever.
> Migration cost: ~3–4 hours. Net negative because it preserves both engines plus adds a config layer.

### Recommendation

**Option A.** You've already validated equivalence (`RUST_RNG_FIX_RESULTS.md`, `compare_rust_cpp.R`) and made the production decision. The fallback is the unfinished tail of that migration, not a working safety net. Removing it forces clear failure modes (Rust down → loud error → fix Rust) instead of silent ones (Rust down → CPP fallback maybe works, results silently differ). Option B has appeal for the equivalence tests, but those tests served their purpose during the migration and don't need to keep running once the migration is done. If you want to revisit equivalence later (e.g., comparing Rust against a future engine), the git tag `pre-deployment-cleanup-2026-05-02` from the deployment-surface PRD already preserves the CPP code.

The trade-off would flip if Rust were unstable in production. From the integration commits and the fact you're calling Rust the production engine, it isn't.

## Acceptance Criteria (Phase 1)

- [ ] `RCode/rust_integration.R` no longer calls `leagueSimulatorCPP` (lines 151–156 of the current file are removed).
- [ ] `RCode/update_all_leagues_loop.R` (renamed by deployment-surface PRD) does not contain the strings `use_rust`, `leagueSimulatorCPP`, `SaisonSimulierenCPP`, `simulationsCPP`, `Rcpp::sourceCpp`. **(`SpielCPP` and `SpielNichtSimulieren` may still appear elsewhere in the repo — they survive in `RCode/` for season-transition.)**
- [ ] `RCode/update_all_leagues_loop.R` calls `leagueSimulatorRust` directly, not via a `simulator_function` variable.
- [ ] When the Rust server is unreachable at startup, the scheduler exits with a non-zero status and a message naming `RUST_API_URL`. (Replace silent fallback with loud failure.)
- [ ] `Dockerfile` no longer contains the `Rcpp::sourceCpp('SpielNichtSimulieren.cpp')` build step (lines 101–104 of `Dockerfile.integrated`). (The container's R runtime never needed it post-fallback-removal — the source files come along via `COPY RCode/`, but they're only used by host-side season-transition runs.)
- [ ] CPP source files **remain** in `RCode/`: `leagueSimulatorCPP.R`, `simulationsCPP.R`, `SaisonSimulierenCPP.R`, `SpielCPP.R`, `SpielNichtSimulieren.cpp`, `cpp_wrappers.R`, `RcppExports.R`. **Do not delete in Phase 1.**
- [ ] `tests/testthat/test-*CPP*.R` files: status is verified (run them, see what passes). They may continue to exist as engine tests for the C++ code that backs season-transition. No deletions in Phase 1; CI rebuild (issue #76) is the right place to decide their fate.
- [ ] `compare_rust_cpp.R`, `compare_rust_vs_r.R`, `tests/rust/test_rust_vs_cpp_detailed.R` are *not* deleted in Phase 1 (originally proposed for deletion; keep until Phase 2 since they exercise the C++ engine that survives).
- [ ] One end-to-end test exists that runs a single iteration of `update_all_leagues_loop()` against a stubbed or real Rust server and asserts the Shiny output is produced. (This may already exist as `tests/testthat/test-e2e-simulation-workflow.R` — verify and adapt.)
- [ ] Docker image still builds and the smoke run from the deployment-surface PRD still produces a healthy Rust server + a successful first loop iteration.
- [ ] **Season-transition smoke test** from the deployment-surface PRD still passes after Phase 1 lands: `Rscript scripts/season_transition.R 2024 2025 --non-interactive` resolves all `source()` calls including `SpielCPP.R`.

## Test Strategy

### Pin current behavior (regression net, written first)

The behavioral contract of `leagueSimulatorRust()` is unchanged — you're only removing fallback code, not simulation code. So the regression net targets the loop, not the simulator.

- `tests/testthat/test-loop-rust-required.R` — start the Rust server, run one iteration of `update_all_leagues_loop_rust()` (current name) against a small fixture league, capture the resulting `Ergebnis` matrix to a snapshot. After the refactor, `update_all_leagues_loop()` (new name) must produce a byte-equivalent `Ergebnis` for the same input. (The Rust engine is deterministic given a fixed seed; if the Rust binary doesn't expose a seed, this becomes a structural assertion — same shape, same column sums to 1 — instead of byte-equality.)
- **Negative test:** stop the Rust server, invoke `update_all_leagues_loop_rust(use_rust = TRUE)`, assert it currently *silently falls back to CPP and succeeds* (documenting the bad behavior the refactor will change).

### Prove the new shape (post-refactor tests)

- `tests/testthat/test-loop-rust-required.R` — same as above, but with the renamed function. Snapshot must match the pre-refactor capture.
- **Negative test (updated):** stop the Rust server, invoke `update_all_leagues_loop()`, assert it now `stop()`s with a message containing `RUST_API_URL`. (This test inverts the pre-refactor behavior, which is the point.)
- `tests/testthat/test-rust-integration-no-fallback.R` — call `leagueSimulatorRust()` directly with the Rust server up, assert it returns the expected matrix shape. Stop the Rust server, call again, assert the API failure surfaces as a `stop()` from `simulate_league_rust` rather than a fallback to CPP.

### What to do with the existing CPP testthat files

`test-SaisonSimulierenCPP.R`, `test-simulationsCPP.R`, `test-SpielCPP.R`, `test-SpielNichtSimulieren.R` exercise functions that **continue to exist in Phase 1** because `SpielCPP.R` is needed by season-transition. Phase 1 does not change them. The CI rebuild (issue #76) is the right time to decide whether they pass against the current code, whether they're worth running in CI, and whether they should migrate or be deleted in Phase 2.

## Migration Steps (Phase 1)

This refactor depends on the deployment-surface PRD landing first (or at least the rename steps from it). If the rename hasn't happened yet, do this PRD's work against the `_rust`-suffixed names, and the deployment-surface rename will sweep through cleanly afterward.

1. **Add the regression snapshot test** described in "Pin current behavior." Run it against the current code; capture the snapshot. Run the negative test; confirm it documents the silent-fallback behavior.
2. **Move the Rust availability check up.** In `update_all_leagues_loop_rust.R`, replace the `if (use_rust) { ... } if (!use_rust) { source CPP ... }` block (lines 26–45) with a single `source("RCode/rust_integration.R"); if (!connect_rust_simulator()) stop(...)`. Remove the `use_rust` parameter from the function signature. Re-run the regression test (positive case, with Rust up).
3. **Inline `simulator_function`.** Replace `simulator_function <- if (use_rust) leagueSimulatorRust else leagueSimulatorCPP` and its 4 call sites with direct calls to `leagueSimulatorRust`. Re-run.
4. **Strip the per-call fallback in `rust_integration.R`.** Delete lines 150–156 of `leagueSimulatorRust()`. Re-run.
5. **Update the scheduler.** `RCode/updateSchedulerRust.R` already calls `connect_rust_simulator()` at line 153, but logs a warning rather than stopping. Change the warning to a `stop()` so a missing Rust server fails the scheduler at startup, not at first simulation call. Remove the `use_rust = rust_available` argument from the `update_all_leagues_loop_rust()` call (line 172) since the parameter is gone.
6. **Update the negative regression test** to assert the new fail-fast behavior (it will currently fail because the old code silently fell back). Confirm green.
7. **Update the Dockerfile.** Remove lines 101–104 of `Dockerfile.integrated` (the `Rcpp::sourceCpp` build step) — the production container no longer needs the compiled C++ object since the fallback is gone. The C++ source files still get COPY-ed via `COPY RCode/`, which is fine; they're just inert in the container. Rebuild the image; confirm it succeeds without the build-time C++ compilation step.
8. **Smoke test the full container** as in the deployment-surface PRD: build, run, watch the Rust server come up, watch one loop iteration succeed.
9. **Smoke test the season-transition workflow.** `Rscript scripts/season_transition.R 2024 2025 --non-interactive` (against a fixture or with API mocked) — confirm `SpielCPP.R` still resolves and the transition succeeds. **This is the canary that proves Phase 1 didn't break the operator workflow.**
10. **Commit and push.**

**Steps 7–11 of the original plan (delete C++ source files, delete CPP testthat files, delete comparison harnesses) are deferred to Phase 2.** Do not run them in Phase 1.

## Risks

- **Risk:** The Rust binary is compiled in stage 1 of `Dockerfile.integrated` and copied into stage 2. If the Rust build fails for any reason, the integrated image now has no fallback — the scheduler will fail-fast.
  - **Mitigation:** This is the desired behavior, not a bug. Rust build failures should fail the Docker build, not be papered over by a CPP fallback. Add a Rust-build check to the (eventual) CI pipeline (issue #76).
- **Risk:** A future Rust server outage (network blip, OOM kill, deploy mishap) now produces a hard scheduler failure instead of degraded operation.
  - **Mitigation:** This is a feature trade-off, not a bug. The current "silent fallback" hides outages and produces results from the wrong engine. Loud failures are a better signal. The retry logic in `docker-integrated-start.sh:48–94` (`MAX_RETRIES=5`, `RETRY_DELAY=30`) already restarts the scheduler — and now the Rust server too if `kill -0 $RUST_PID` shows it's dead. So the operational effect of a single Rust crash is the same as today: the wrapper restarts both. The change is at the *single-loop-iteration* layer, where you get a clear error instead of a silent engine swap.
- **Risk:** Removing the `Rcpp::sourceCpp` step from the Dockerfile (step 7) leaves the C++ source files in `RCode/` un-compiled inside the container. If anything *inside* the container ever invokes `SpielCPP.R` (e.g., a debugging exec into the running container), it will fail.
  - **Mitigation:** Nothing in the production runtime invokes `SpielCPP.R` after the fallback removal. Season-transition runs on the host, not in the container. If a future workflow requires in-container C++ compilation, re-add the build step then. Phase 1 simply stops paying the build-time cost for an unused artifact.
- **Risk:** Step 9's season-transition smoke test fails because some other dependency was inadvertently affected — e.g., `SpielCPP.R` itself depends on `SpielNichtSimulieren.cpp` being compiled, and the host environment doesn't have `Rcpp` configured.
  - **Mitigation:** This is a real concern. Before step 7, run the smoke test on a clean checkout to confirm it passes today (proving the host environment can build the C++ code). If it doesn't pass *today* either, season-transition is already broken locally, which is a separate problem to surface (not caused by this PRD). If it passes today and fails after step 7, something is wrong with the changes — investigate before merging.

## Open Questions

- Does the Rust binary expose a deterministic-seed flag? If yes, the regression-snapshot test (step 1) can use byte-equality. If no, the test asserts only structural properties (matrix shape, row sums = 1, ranking order stable across runs with high probability). Worth checking the Rust crate's CLI help during step 1.
- `tests/testthat/test-e2e-simulation-workflow.R` may already cover the loop end-to-end. Read it during step 1 to decide whether the new `test-loop-rust-required.R` duplicates it; if so, extend the existing test instead of adding a new file.
- **Phase 2 question:** Does `scripts/season_transition.R` actually *use* `SpielCPP.R`, or did it inherit the source line from when C++ was the only engine? Quick test: comment out the `SpielCPP.R` source in `existing_modules` and run a transition. If it still works, `SpielCPP.R` was vestigial and can join the C++ deletion in Phase 2. If it fails, the season-transition workflow has a real C++ dependency and Phase 2 must either (a) keep the C++ engine indefinitely as season-transition's tool, or (b) migrate season-transition to call the Rust seam.

## Suggested Phasing

This refactor splits cleanly along the production/operator boundary.

**Phase 1 (this PRD).** Remove duplicated fallback wiring, fail fast on Rust unavailability, drop the unnecessary Docker build step. C++ source files remain. Production code calls Rust unconditionally; season-transition continues to source `SpielCPP.R` as before. Smallest valuable, shippable slice. Addresses the immediate architectural smell (three fallback checks, brittle Docker step) without breaking the operator workflow.

**Phase 2 (re-derive after Phase 1 lands and you've verified the production path is stable).** Decide the long-term fate of the C++ engine, given what season-transition actually needs. Concrete questions to answer at that point:
- Does season-transition genuinely call into `SpielCPP.R`, or just source it without invocation? (See Open Questions above.)
- If genuinely needed: is "C++ engine permanently survives as season-transition's tool" the right answer (acceptable maintenance burden, clear ownership), or should season-transition migrate to the Rust seam (more invasive but consolidates the engine to one)?
- If not genuinely needed: delete `SpielCPP.R` and the rest of the C++ engine, the Rcpp dependency from `packagelist.txt`/`DESCRIPTION`, the CPP testthat files, and the comparison harnesses — exactly the deletions originally proposed in the first draft of this PRD.

**Don't pre-plan Phase 2 in detail now.** The post-Phase-1 codebase will look different (no more fallback wiring, possibly some additional discoveries about `SpielCPP.R`'s actual usage), and re-running `architecture-review-prd` against that state will produce a sharper PRD than guessing now would.

## Adjacent Observations

- `compare_rust_cpp.R`, `compare_rust_vs_r.R`, and `compare_working.R` are in the repo root. They're tooling, not production. Same class as the `debug_*.R` and `elv_*.R` clutter flagged in the deployment-surface PRD. Out of scope here, in scope for a "repo root hygiene" review later.
- `RCode/retrieveResults_broken.R` lives next to `retrieveResults.R`. The naming is itself a smell — broken code shouldn't be in the production source tree, even with a `_broken` suffix. Out of scope for this PRD; flag for a future cleanup pass.
- `Dockerfile.integrated:42–88` does R package installation in three stages (core / shiny / rest) with retry-and-fallback logic for binary vs source builds. That's a separate fragility worth a future review — likely related to whatever broke CI originally.
- The Rust-available check is currently *also* duplicated between `updateSchedulerRust.R:153` and (post-refactor) `update_all_leagues_loop.R`. After this PRD lands, consider: should the loop trust the scheduler's check, or check independently for defense-in-depth? The current PRD keeps both for safety; if you want one, drop the loop's check (the scheduler is the entry point).
- The season-transition's reliance on `SpielCPP.R` (discovered while patching this PRD) is itself an architectural observation worth recording: the operator workflow embeds an engine choice that the production workflow has already moved past. If season-transition were to migrate to the Rust seam, it would also gain the Rust engine's performance characteristics — relevant if a transition's simulation step is slow today.
