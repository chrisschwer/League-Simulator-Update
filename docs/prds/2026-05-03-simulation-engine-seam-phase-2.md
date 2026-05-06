# Retire C++ R-wrapper engine; keep `SpielNichtSimulieren.cpp` as ELO primitive

**Scope:** `RCode/SpielCPP.R`, `RCode/simulationsCPP.R`, `RCode/SaisonSimulierenCPP.R`, `RCode/leagueSimulatorCPP.R`, `RCode/cpp_wrappers.R`, `RCode/RcppExports.R`, `RCode/SpielNichtSimulieren.cpp`, `RCode/elo_aggregation.R`, `scripts/season_transition.R`. Direct callers explicitly considered: `RCode/update_all_leagues_loop.R` (production loop), `RCode/update_league.R` (orphan, scheduled for deletion in #86). Test surface considered: `tests/testthat/test-spielcpp-contract.R`, `tests/testthat/test-SpielNichtSimulieren.R`, `tests/rust/test_rust_vs_cpp_detailed.R`, `compare_rust_cpp.R`, `compare_rust_vs_r.R`.
**Date:** 2026-05-03
**Source:** architecture-review-prd skill

> **Phase-1 framing was wrong in detail.** The Phase-1 PRD (`docs/prds/2026-05-02-simulation-engine-seam.md`) posed a binary open question: does season-transition use `SpielCPP.R` or not? Concrete grep against the post-Phase-1 tree shows the truth is layered. `SpielCPP.R` *is sourced* by `scripts/season_transition.R:71` but *never invoked* by any season-transition module. The function that the season-transition does call is `SpielNichtSimulieren` (the Rcpp-compiled C++ primitive in `SpielNichtSimulieren.cpp`), invoked from `RCode/elo_aggregation.R:231`. So Phase 2 is not "C++ engine: keep or delete?" — it is "delete the unused R-wrapper layer; keep the C++ primitive as the ELO calculation engine for season-transition."

## Goal

The repo contains exactly one production simulation engine (Rust, via `rust_integration.R`) and exactly one ELO-update primitive used by the season-transition operator workflow (`SpielNichtSimulieren.cpp`, called via Rcpp). The five R wrappers around that primitive (`SpielCPP.R`, `simulationsCPP.R`, `SaisonSimulierenCPP.R`, `leagueSimulatorCPP.R`, `cpp_wrappers.R`) and the auto-generated `RcppExports.R` are gone. The dead source line at `scripts/season_transition.R:71` is gone. The season-transition workflow continues to produce identical `RCode/TeamList_<year>.csv` output.

## Architecture

Two boundary changes, no new files.

1. **Drop the R-wrapper layer.** `SpielCPP.R` and the four files above it in the call chain (`simulationsCPP.R`, `SaisonSimulierenCPP.R`, `leagueSimulatorCPP.R`, `cpp_wrappers.R`) form a self-contained tower with one external entry point: `leagueSimulatorCPP()`. That entry point is called only from `RCode/update_league.R` (in the orphan microservices set already targeted by #86) and from comparison harnesses. After #86 lands and the harnesses are removed, nothing in the production or operator paths calls into this tower. Delete it.

2. **Make the season-transition C++ dependency explicit.** `RCode/elo_aggregation.R:225` guards its C++ call with `if (exists("SpielNichtSimulieren"))` and silently falls back to a pure-R `calculate_elo_update`. Today `scripts/season_transition.R` does not source `SpielNichtSimulieren.cpp` — meaning the operator workflow has been silently using the R fallback all along. Phase 2 makes this an intentional choice: either **(A)** the season-transition explicitly calls `Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")` and uses the C++ primitive for byte-identical results to historical runs, or **(B)** `elo_aggregation.R` drops the silent fallback, the `.cpp` file is deleted with the rest, and the pure-R `calculate_elo_update` becomes the only path.

The `SpielCPP.R` source line at `scripts/season_transition.R:71` is removed in either case — it sources a function that nothing in the season-transition module set ever calls.

## Tech Stack

R 4.3.1, Rcpp 1.x (only if Option A is chosen — see below), testthat 3.x. No new dependencies. The Rust crate at `league-simulator-rust/` is unchanged. Files live in flat `RCode/` per existing convention.

## The Finding

### Current State

**The CPP R-wrapper tower (5 files, ~250 lines total):**

```
leagueSimulatorCPP.R    # public-ish entry point; called by update_league.R only
└─ simulationsCPP.R     # Monte Carlo loop
   └─ SaisonSimulierenCPP.R  # one-season simulation
      └─ SpielCPP.R     # one-match wrapper around SpielNichtSimulieren
         └─ SpielNichtSimulieren.cpp  # the actual ELO primitive (.cpp)
cpp_wrappers.R          # adapters that re-shape simulationsCPP / SpielCPP / SpielNichtSimulieren outputs
RcppExports.R           # auto-generated from .cpp; declares SpielNichtSimulieren()
```

**Callers of `leagueSimulatorCPP` across the entire repo (post-Phase-1):**

```
RCode/update_league.R:87         # orphan microservices file (in #86 deletion pile)
RCode/update_league.R:88         # orphan
RCode/update_league.R:100        # orphan
RCode/rust_integration.R:128     # comment ("drop-in replacement for leagueSimulatorCPP")
RCode/rust_integration.R:209     # comment
```

Zero production callers. Zero season-transition callers. Three caller lines, all in `update_league.R`, which the open issue #86 already deletes. After #86: zero callers.

**Callers of `SpielCPP` (the function, not the file) across the repo:**

```
RCode/SaisonSimulierenCPP.R:50,59   # internal to the CPP tower
tests/single_match_test.R:58         # tooling, not production
tests/test_rust_integration.R        # comparison test
tests/verify_parameters.R:29         # tooling
tests/rust/calculate_matrix_differences.R:20   # comparison
tests/rust/test_rust_vs_cpp_detailed.R:20      # comparison
tests/performance/measure-baselines.R:178      # benchmark
tests/performance/run-baseline-measurements.R  # benchmark
tests/testthat/test-spielcpp-contract.R        # contract test added by #76 prep
```

Zero production callers. Zero season-transition callers. The `test-spielcpp-contract.R` file's own header claims it pins "the contract that R-side code (season-transition operator workflow) depends on" — but that claim is false: no season-transition module imports `SpielCPP`. The test was added in commit `4698a58` under the Phase-1 PRD's mistaken assumption.

**The genuinely-needed C++ primitive — callers of `SpielNichtSimulieren`:**

```
RCode/elo_aggregation.R:225,231     # season-transition module set, behind exists() guard
RCode/SpielCPP.R:37                 # internal to the CPP tower (about to be deleted)
tests/check_played_matches.R:48     # tooling
tests/single_match_test.R           # tooling
tests/verify_parameters.R           # tooling
tests/test_rust_integration.R       # comparison test
tests/testthat/test-SpielNichtSimulieren.R    # ELO primitive contract (11 tests)
```

The single load-bearing call is `elo_aggregation.R:231`. Everything else is tooling, comparison harnesses, or about-to-be-deleted.

**`scripts/season_transition.R:65–73`:**

```r
existing_modules <- c(
  "retrieveResults.R",
  "transform_data.R",
  "SpielCPP.R"
)
```

`SpielCPP.R` is sourced; `SpielNichtSimulieren.cpp` is not. So the operator workflow currently has `SpielCPP` defined in scope but never called, and `SpielNichtSimulieren` *not* defined in scope when `elo_aggregation.R` runs — which means the `exists()` guard at line 225 falls through to the R fallback `calculate_elo_update` at line 252 every time.

**Test coverage today:**

- `tests/testthat/test-SpielNichtSimulieren.R` — 11 tests against the C++ primitive directly. These pin the ELO arithmetic.
- `tests/testthat/test-spielcpp-contract.R` — 3 tests against `SpielCPP`. The header claims it's the season-transition contract; it is not.
- `tests/testthat/test-elo-aggregation*.R` (if present) — would cover the `update_elos_for_match` path that *actually runs* during season-transition. Worth checking during Phase-2 step 1.
- The comparison harnesses in `tests/rust/`, `compare_rust_cpp.R`, etc. — exist to validate Rust matches C++. Their job ends with this PRD.

### Why this is a problem

Apply the deletion test to the CPP R-wrapper tower: delete `leagueSimulatorCPP.R`, `simulationsCPP.R`, `SaisonSimulierenCPP.R`, `SpielCPP.R`, `cpp_wrappers.R`. After #86 lands (deleting `update_league.R`), nothing in the production or operator paths breaks. The tests that break are the comparison harnesses and `test-spielcpp-contract.R`, all of which exist *to test code that has no live callers*. This is the textbook shallow-module problem at module-cluster scale: five files of interface-and-implementation that wrap one C++ function the rest of the codebase doesn't reach through them anyway. Their continued existence imposes maintenance cost (the brittle `Rcpp::sourceCpp` build step in older Dockerfiles, the `Rcpp` dependency in `packagelist.txt:16`, the test suite drag) for no observable benefit.

The deeper problem is the **silent-fallback architecture** in `elo_aggregation.R:225`. Today, whether the season-transition uses the C++ primitive or the R fallback depends on whether some upstream caller happened to have sourced the `.cpp`. Production code paths source it (the production loop also sources `SpielNichtSimulieren.cpp` somewhere — verify in step 1), but `scripts/season_transition.R` does not. Two callers, two different ELO calculation engines, no error in either case. That's a correctness-by-coincidence shape, and per `docs/KNOWN_ISSUES.md` ("ELO Calculation Issues, Resolved July 2025") this codebase has historical pain with exactly this class of bug — calculations that diverge silently because the engine selection is implicit.

Phase 2 forces the choice into the open. After this PRD lands, either the season-transition explicitly compiles and uses the C++ primitive (Option A), or it explicitly uses pure R (Option B), but never both depending on which file happened to be sourced.

## Interface — Before / After

```r
# BEFORE (RCode/, post-Phase-1 state)
RCode/SpielCPP.R                  # ~45 lines, only-internal callers
RCode/simulationsCPP.R            # ~80 lines, only-internal callers
RCode/SaisonSimulierenCPP.R       # ~70 lines, only-internal callers
RCode/leagueSimulatorCPP.R        # ~50 lines, called by update_league.R (orphan)
RCode/cpp_wrappers.R              # ~80 lines, no live callers
RCode/RcppExports.R               # auto-generated, declares SpielNichtSimulieren
RCode/SpielNichtSimulieren.cpp    # the ELO primitive
RCode/elo_aggregation.R          # uses SpielNichtSimulieren behind exists() guard

# scripts/season_transition.R
existing_modules <- c("retrieveResults.R", "transform_data.R", "SpielCPP.R")  # last entry vestigial

# AFTER — Option A (recommended): keep .cpp as the ELO primitive
RCode/SpielNichtSimulieren.cpp    # the only C++ artifact
RCode/RcppExports.R               # kept; auto-generated declaration

# RCode/elo_aggregation.R
update_elos_for_match <- function(current_elos, match) { ... }
# Drop the exists() guard at line 225. Always call SpielNichtSimulieren.
# Delete the calculate_elo_update fallback at line 252 (no longer reachable).

# scripts/season_transition.R
existing_modules <- c("retrieveResults.R", "transform_data.R")  # SpielCPP.R removed
# Add at top of script (or in a sourced helper): Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")

# AFTER — Option B (alternative): pure-R season-transition
# All files above (.cpp included) deleted.
# RCode/elo_aggregation.R inlines the R fallback as the only implementation:
update_elos_for_match <- function(current_elos, match) { ... }   # uses calculate_elo_update directly
# Rcpp removed from packagelist.txt. RcppExports.R deleted. Build step in Dockerfile simplifies.
```

## Design Options Considered

### Option A — Keep `.cpp` as ELO primitive, delete the R-wrapper tower *(recommended)*

> **Sketch.** Delete the five R wrappers and `RcppExports.R` only if it has no other consumer (it's auto-generated; safe to drop and regenerate if needed). Keep `SpielNichtSimulieren.cpp` and the existing call from `elo_aggregation.R:231`. Make the C++ load explicit in `scripts/season_transition.R` (add `Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")` early in the script, before `elo_aggregation.R` is sourced). Remove the `exists()` guard and the R fallback in `elo_aggregation.R`.
>
> **Trade-off.** Best continuity with historical season-transition runs (those that did source the `.cpp`, e.g., via the production loop's path) — same ELO arithmetic, byte-identical CSVs. Cost: keeps one C++ file plus Rcpp in the build, which is not zero maintenance but is well-contained (one `.cpp`, ~25 lines of arithmetic, no R-side wrapper layer to maintain).
>
> **Migration cost.** Low-medium. Five `git rm`s in `RCode/`. One line removed from `scripts/season_transition.R:71`, one line added (the `sourceCpp`). One `if (exists(...))` removed from `elo_aggregation.R`, plus deletion of the unreachable `calculate_elo_update` fallback. Comparison harnesses in `tests/rust/`, `compare_rust_cpp.R`, `compare_rust_vs_r.R` deleted. `test-spielcpp-contract.R` deleted. `test-SpielNichtSimulieren.R` kept (still pins the primitive). `Rcpp::sourceCpp` ELO test in `tests/testthat/test-SpielNichtSimulieren.R` already loads the `.cpp`, so contract is preserved.

### Option B — Delete the entire C++ engine, including `.cpp`; pure-R season-transition

> **Sketch.** Delete everything in Option A *plus* `SpielNichtSimulieren.cpp` and `RcppExports.R`. Inline `calculate_elo_update` (already in `elo_aggregation.R:252`) as the only implementation — drop the `if (exists())` branch entirely. Remove `Rcpp` from `packagelist.txt:16`. Confirm `Dockerfile:44` no longer needs `Rcpp` in `core_pkgs`.
>
> **Trade-off.** Maximally clean — one fewer language in the operator surface, no Rcpp build dependency, simpler Docker layer. Cost: introduces a behavioral question. Are the C++ and R ELO formulas byte-identical? `RCode/SpielNichtSimulieren.cpp` lines 18–32 implement: `ELOProb = 1/(1 + 10^(ELODeltaInv/400))`, `goalMod = sqrt(max(|goalDiff|, 1))`, `ELOModificator = (result - ELOProb) * goalMod * modFactor`, with `ELODeltaInv` clamped to `[-400, 400]`. `RCode/elo_aggregation.R:252` implements `calculate_elo_update` — the formulas need to be diffed before this option is safe. If they differ, Option B silently changes the season-transition's ELO output starting next season.
>
> **Migration cost.** Medium-high. The deletion is mechanical, but the *correctness verification* requires running the season-transition both ways (with `.cpp` and without) against a fixture and confirming the resulting CSVs are byte-identical. If they are not, Option B requires either (b1) accepting the divergence as a one-time recalibration, or (b2) updating the R formula to match the C++ exactly.

### Option C — Migrate season-transition to call the Rust seam

> **Sketch.** Add a `/elo-update` REST endpoint to the Rust binary that takes `(home_elo, away_elo, goals_home, goals_away, mod_factor, home_advantage)` and returns the updated ELOs. Replace the C++ primitive call in `elo_aggregation.R` with an HTTP call to that endpoint. Delete `.cpp`, `.R` wrappers, Rcpp dependency.
>
> **Trade-off.** Engine consolidation — one calculation engine across the entire codebase. Cost: adds a Rust API endpoint that doesn't exist yet, plus an HTTP-call dependency to a workflow that today runs entirely locally without a Rust server. The season-transition operator would now need to start the Rust server before running the script. That breaks the "manual local script" mental model and adds a setup step to the operator workflow per `docs/user-guide/season-transition.md`.
>
> **Migration cost.** High. Rust crate change + endpoint test + R-side HTTP client + operator-doc update + integration test for the new endpoint. Pure overhead unless engine consolidation is itself a goal.

### Recommendation

**Option A.** It deletes the five-file shallow-module cluster (the actual architectural finding) without disturbing the operator workflow's calculation engine. The `.cpp` file is small, isolated, well-tested by `test-SpielNichtSimulieren.R`, and depended on by exactly one production-relevant function (`update_elos_for_match`). Keeping it is a much smaller maintenance burden than the wrapper tower it currently sits under. The exists()-guard removal is the load-bearing correctness improvement: it converts a silent fallback into an explicit dependency declaration, eliminating the engine-selection-by-coincidence shape that historically caused the July 2025 ELO regression.

Option B becomes attractive only if the formulas turn out to be byte-identical (a fact-check that should be done in step 1 regardless — see Open Questions). If they are, Option A and Option B converge in observed behavior, and Option B's smaller surface wins. If they differ, Option A is correct.

Option C is YAGNI today. Engine consolidation is real architectural value but the Rust seam is a production-loop optimization concern, and forcing the operator to run a server for a manual procedure is a regression in operability. Revisit if the Rust binary becomes a developer-machine standard for other reasons.

## Acceptance Criteria

- [ ] Files deleted: `RCode/SpielCPP.R`, `RCode/simulationsCPP.R`, `RCode/SaisonSimulierenCPP.R`, `RCode/leagueSimulatorCPP.R`, `RCode/cpp_wrappers.R`. (Verify these are absent in the merge commit.)
- [ ] `RCode/RcppExports.R` either deleted (if no consumer remains) or kept and unchanged. Decided in step 1; documented in the commit message.
- [ ] `RCode/SpielNichtSimulieren.cpp` is present and unchanged.
- [ ] `scripts/season_transition.R` no longer lists `"SpielCPP.R"` in `existing_modules`.
- [ ] `scripts/season_transition.R` (or a helper it sources) explicitly calls `Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")` before `elo_aggregation.R` is sourced.
- [ ] `RCode/elo_aggregation.R` no longer contains the `if (exists("SpielNichtSimulieren"))` guard at line 225. The C++ call is unconditional. The pure-R fallback `calculate_elo_update` is deleted.
- [ ] `tests/testthat/test-spielcpp-contract.R` deleted.
- [ ] Comparison harnesses deleted: `tests/rust/test_rust_vs_cpp_detailed.R`, `tests/rust/calculate_matrix_differences.R`, `tests/rust/test_match_order_verification.R` (verify still relevant), `compare_rust_cpp.R`, `compare_rust_vs_r.R`, `compare_working.R`. Tooling-only test files in `tests/` root that source the deleted wrappers (`tests/single_match_test.R`, `tests/verify_parameters.R`, `tests/test_rust_integration.R`, `tests/check_played_matches.R`) — kept or deleted per step 4 decision; default delete (these are scratch tooling, not test suite).
- [ ] `tests/testthat/test-SpielNichtSimulieren.R` runs green against the unchanged `.cpp`.
- [ ] A new (or extended) test in `tests/testthat/test-elo-aggregation*.R` exercises `update_elos_for_match` with a known fixture and asserts the C++ path is taken (no silent fallback).
- [ ] `Rscript scripts/season_transition.R 2024 2025 --non-interactive` against a fixture produces byte-identical `RCode/TeamList_2025.csv` to a baseline captured before the refactor. (See Test Strategy "pin current behavior".)
- [ ] CI (rebuilt under issue #76) runs the testthat suite green.
- [ ] `Rcpp` remains in `packagelist.txt:16` and `Dockerfile:44`'s `core_pkgs`. Unchanged.

## Test Strategy

### Pin current behavior (regression net, written first)

The big risk in this PRD is that `elo_aggregation.R`'s silent-fallback today means we don't know which engine the season-transition is *currently* using under any given operator setup. Step 1 of the migration must answer this empirically before any deletion.

- **`tests/testthat/test-elo-aggregation-engine-selection.R`** *(new file, written before any deletion)*. Two tests:
  1. With `SpielNichtSimulieren` defined in the global env, call `update_elos_for_match` against a fixture match and snapshot the returned ELO. Assert the result matches the C++ formula's expected output (computed from `SpielNichtSimulieren.cpp` lines 18–32 by hand or via direct call).
  2. With `SpielNichtSimulieren` *not* defined (rm it before the call), call `update_elos_for_match` against the same fixture. Snapshot the R-fallback result. Assert the two paths differ (or equal — whichever is the truth; the test pins the answer so the refactor can't accidentally flip it).
  This test is the rumour-and-evidence step that decides between Option A and Option B and protects either choice.
- **`tests/regression/season-transition-csv-snapshot.R`** *(new harness, can live outside `testthat/`)*. Run `Rscript scripts/season_transition.R 2024 2025 --non-interactive` against a fixture, capture the resulting `RCode/TeamList_2025.csv`, store as a snapshot. Re-run after the refactor. Assert byte-identical (Option A) or document the diff (Option B). Regenerate the snapshot only with explicit operator review.

### Prove the new shape (post-refactor tests)

- **`tests/testthat/test-SpielNichtSimulieren.R`** — already exists, kept unchanged. The 11 tests there pin the C++ primitive's ELO arithmetic and continue to do so.
- **`tests/testthat/test-elo-aggregation-engine-selection.R`** — after the refactor, the second test (R-fallback path) is updated to assert that the fallback path *does not exist* — calling `update_elos_for_match` without the `.cpp` loaded must raise an error, not silently return a different result. This is the converted version of the engine-selection test that pins the new explicit-dependency contract.
- **No new wrapper-layer tests.** The deleted wrapper layer's only tests (`test-spielcpp-contract.R`) are deleted with it.

## Migration Steps

1. **Establish ground truth on the silent fallback.** Write `test-elo-aggregation-engine-selection.R` against the *current* code. Run it. Record which engine the season-transition is using today (almost certainly the R fallback, given `scripts/season_transition.R` doesn't source the `.cpp`). Record whether C++ and R formulas produce identical results. Decide A vs B based on what you find. This is the only step that *might* change the recommendation; the rest assume Option A.
2. **Capture the season-transition CSV snapshot** (regression harness from Test Strategy).
3. **Make the C++ load explicit.** Add `Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")` to `scripts/season_transition.R` (before `elo_aggregation.R` is sourced) or to a small helper module at the top of `existing_modules`. Re-run the snapshot harness. Confirm: either CSVs are still identical (formulas match — both A and B viable), or CSVs differ (A is correct, B would change behavior).
4. **Remove the silent fallback.** Edit `RCode/elo_aggregation.R` to call `SpielNichtSimulieren` unconditionally. Delete the `if (exists(...))` guard and the unreachable `calculate_elo_update` function. Run the testthat suite. Run the snapshot harness.
5. **Delete the wrapper tower.** `git rm RCode/SpielCPP.R RCode/simulationsCPP.R RCode/SaisonSimulierenCPP.R RCode/leagueSimulatorCPP.R RCode/cpp_wrappers.R`. Decide on `RcppExports.R` (delete unless something still consumes it; it's auto-generated and easy to recreate). Remove `"SpielCPP.R"` from `scripts/season_transition.R:71`. Run testthat — expect breakage in `test-spielcpp-contract.R` and the comparison harnesses.
6. **Delete the orphaned tests.** `git rm tests/testthat/test-spielcpp-contract.R tests/rust/test_rust_vs_cpp_detailed.R tests/rust/calculate_matrix_differences.R compare_rust_cpp.R compare_rust_vs_r.R compare_working.R`. Decide on the loose `tests/*.R` scratch files (`single_match_test.R`, `verify_parameters.R`, `test_rust_integration.R`, `check_played_matches.R`, `verify_home_advantage.R`) — default to deleting any that source the now-gone wrappers; if they only touch the `.cpp`, keep but verify they still run.
7. **Run the full testthat suite + snapshot harness one more time.** Confirm green. Confirm CSV output unchanged from step 2's baseline.
8. **Commit.** Suggested split: (a) "test: pin elo-aggregation engine selection and season-transition CSV output", (b) "refactor(#77): make C++ ELO primitive an explicit dependency in season-transition", (c) "chore(#77): delete unused C++ R-wrapper tower and orphan comparison harnesses".

## Risks

- **Risk:** Production loop relies on `Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")` being loaded for the same `exists()` guard in `elo_aggregation.R` to take the C++ path during ELO updates between fixture polls.
  - **Mitigation:** Step 1's engine-selection test runs in production-loop conditions too. Verify by grepping which file in the production loop's source chain (`update_all_leagues_loop.R` → `prozent.R`, `retrieveResults.R`, `Tabelle.R`, `transform_data.R`, `updateShiny.R`, `rust_integration.R`) sources the `.cpp`. If none of them does, the production loop has been using the R fallback too, and the silent-fallback removal in step 4 needs a parallel `Rcpp::sourceCpp` in the production loop's startup.
- **Risk:** `RcppExports.R` is sourced somewhere we missed and deleting it breaks a load.
  - **Mitigation:** `grep -rn "RcppExports" RCode/ scripts/ tests/ Dockerfile` before deletion. If anything survives, keep `RcppExports.R`; the file is small and auto-generatable, so its retention is not a maintenance burden.
- **Risk:** Step 1 reveals C++ and R formulas produce *different* ELO outputs, and the season-transition has historically been using the R fallback. Then step 3 (load the `.cpp` explicitly) silently changes the operator workflow's output.
  - **Mitigation:** This is exactly the question Phase 2 must answer. If the formulas differ, the PRD chooses Option B (formalize R as the engine; delete the `.cpp`) instead of Option A. Or, if Option A is preferred for engine-correctness reasons, the operator must accept a one-time ELO recalibration and the snapshot baseline is regenerated with explicit ack.
- **Risk:** Tooling-only test files (`tests/single_match_test.R` et al.) are someone's investigation aid that they expect to keep working.
  - **Mitigation:** Christoph confirmed in #79 brainstorm that scratch R files at `tests/` root are tooling, not test suite. Default to delete; if a specific one is wanted, keep it but ensure it's updated to source the surviving primitive only.

## Open Questions

- **Are the C++ and R ELO formulas byte-identical?** This is the load-bearing question. `SpielNichtSimulieren.cpp:18-32` and `elo_aggregation.R:252+` need to be diffed in step 1, and the engine-selection test must record whether they produce equal output for fixture inputs. The whole A-vs-B branch hinges on this.
- **Does the production loop currently load the `.cpp`?** Grep `update_all_leagues_loop.R` and everything it sources for `Rcpp::sourceCpp`. If it doesn't, the silent-fallback shape is *already* causing both production and operator paths to use the R fallback, and the C++ engine has been dead code under a guard since Phase 1 landed. That changes nothing in the recommendation but does mean step 4's removal of the fallback affects production behavior, not just operator behavior.
- **Is `RcppExports.R` still needed if no `R/` wrappers consume it?** It's auto-generated by `Rcpp::compileAttributes()` and declares `SpielNichtSimulieren` as an R-callable function, but with `sourceCpp()` doing the same thing at runtime, the static declaration may be redundant. Verify in step 5; default-delete unless a specific load fails.
- **Are the `tests/rust/test_match_order_verification.R` and `tests/rust/test_rust_elo.R` files comparison harnesses (deletable with the rest), or are they validation tests for the Rust seam itself (must survive)?** Read them in step 6 before deciding.

## Suggested Phasing

This PRD as a single TDD cycle is borderline — 7 files deleted, 2 files edited, 1–2 test files added/updated, plus a CSV regression harness. The migration steps above sequence it into discrete commits that each pass tests, so it can ship as one PR with three commits. No further sub-phasing needed.

**Gating note:** Per Christoph's policy on 2026-05-03, no execution of this plan starts before issue #76 (CI rebuild) lands. The new CI will run `test-SpielNichtSimulieren.R`, the engine-selection test, and the testthat suite — without that gate, the byte-identical-CSV claim in the acceptance criteria is unverified.

## Adjacent Observations

- **`RCode/elo_aggregation.R`'s `if (exists(...))`-with-fallback shape appears in at least one other place in the codebase** (the C++/Rust seam itself had this pattern pre-Phase-1). It's worth a one-time grep across `RCode/` for `if (exists(` to find any remaining silent-fallback architectures. Out of scope here; candidate for a separate review.
- **The comparison harnesses in `tests/rust/` and at the repo root** were the artifacts of the Rust migration's correctness validation. Their job ended when Phase 1 made Rust the unconditional production engine. They've been kept around for ~6 months past their useful life. Deleting them with this PRD is correct, but the broader pattern — temporary validation harnesses outlive their purpose — is worth flagging in operator/contributor docs.
- **`scripts/install_test_packages.R:51-52`** also calls `sourceCpp("RCode/SpielNichtSimulieren.cpp")`. This is a test-environment setup script. It will continue to work after this PRD as long as the `.cpp` survives (Option A). Under Option B it must also be updated.
- **`tests/testthat/helper-test-setup.R`** may or may not source the `.cpp`. Verify in step 1; if it does, the helper's behavior changes from "set up CPP for tests that need it" to "set up the only ELO primitive" — same effect, clearer name.
