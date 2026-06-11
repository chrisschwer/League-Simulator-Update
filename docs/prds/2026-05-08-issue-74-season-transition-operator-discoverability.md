# Issue #74 — Season-Transition Operator Discoverability

**Scope:** `RCode/season_processor.R`, `RCode/input_validation.R`, `scripts/season_transition.R`, `scripts/season_transition/cleanup.R` (new), `docs/user-guide/season-transition.md`, `CLAUDE.md`, plus tests under `tests/testthat/`.
**Date:** 2026-05-08
**Source:** Iterative refinement of the 2026-05-02 architecture-review-prd output through a *Philosophy of Software Design* (Ousterhout) lens, in dialogue with the operator.
**Replaces:** the 2026-05-02 draft (lived only in the GitHub issue, no file in repo to delete).

## Goal

The season-transition operator runs **one command** for the happy path. That command auto-validates and auto-cleans on success. A separate **recovery wrapper** exists for the rare case the main command crashes mid-run and leaves intermediate league files behind. No operator-facing helper lives "discoverable only by reading the source."

## Architectural Diagnosis (PoSD)

The 2026-05-02 PRD framed `validate_season_processing`, `create_processing_report`, and `cleanup_processing_artifacts` as three deep functions that needed wrapper scripts to be discoverable. A reality check (Section: *Findings*) revealed a different problem: these are not **invisible** modules — two of them are partially or fully **disconnected** from the call graph despite being correct in spirit.

- `validate_season_processing` is never called. The pipeline has *no* end-of-run validation.
- `create_processing_report` is never called either. Its information is fully covered by the existing `processing_<from>_to_<to>.log` (which the pipeline does write).
- `cleanup_processing_artifacts` is never called. Its glob is broader than the files the pipeline produces, so even the operator can't safely invoke it.
- A *fourth* validator (`validate_team_count`) is called inside the loop, but its failure produces only a `warning()` — silently swallowed in non-interactive mode. **Validation that has no consequence is worse than no validation.**

The PoSD reframe: the problem is not "make tools discoverable" but **"connect tools to the pipeline correctly, eliminate the redundant one, and provide one explicit recovery surface for when the pipeline aborts."** Different layers, different abstractions:

- **Pipeline layer** (production code in `RCode/`): produces correct seasons. Owns its own validation and its own cleanup. Errors out of existence by per-iteration validation that fails loudly.
- **Operator-wrapper layer** (`scripts/season_transition.R`): orchestrates one happy-path command. After successful pipeline, removes intermediate league CSVs the pipeline produced (using `result$files_created`, no globs).
- **Recovery layer** (`scripts/season_transition/cleanup.R`, new): manual safety net. Glob-restricted to exactly the intermediate files the pipeline can produce. Dry-run by default. Requires `--confirm` to delete.

Each layer has its own safety mechanism: pipeline (loud-fail validation), wrapper (list-based deletion — *errors out of existence by construction*), recovery (dry-run + `--confirm`). They don't share cleanup logic — each layer's safety mechanism matches the trust level of its caller.

## Findings — Reality Check

The 2026-05-02 PRD assumed all three functions were defined-but-unused. A code-and-history check (2026-05-08) shows:

- **`validate_season_processing`** (`RCode/season_processor.R:490`): zero callers. Never invoked.
- **`create_processing_report`** (`RCode/season_processor.R:573`): zero callers. Never invoked. The user expectation ("write a report when something goes wrong, for debugging") is *already met* by `create_processing_log` (`RCode/logging.R:195`), which the main script *does* call (`scripts/season_transition.R:208`). The log writes a `processing_<from>_to_<to>.log` with full event history including errors.
- **`cleanup_processing_artifacts`** (`RCode/season_processor.R:619`): zero callers. Never invoked. Its globs include broad patterns (`.*_backup_.*\.csv`, `.*\.tmp`, `.*\.lock`) that the pipeline does not produce — the function is a foreign-debris cleaner, not a pipeline-debris cleaner. Single Responsibility violation.
- **`validate_team_count`** (`RCode/input_validation.R:4`): called once inside `process_single_season:194` after merging league files. Failure produces a `warning()`. In `--non-interactive` mode this is invisible — a silent validation failure that allows the pipeline to declare success on a broken CSV.
- **`process_season_transition`** error path: only emits `cat()` output and returns `success=FALSE`. No structured artifact preserved (which is fine, given that the log file already captures the run).

`RCode/` currently has no files matching the cleanup globs — only the three final `TeamList_<season>.csv` files. So no immediate damage from the existing function; the harm is purely latent.

`README.md:36` already points to `docs/user-guide/season-transition.md`. **No README change needed.**

The parallel plan `docs/superpowers/plans/2026-05-03-season-transition-test-coverage.md` does not modify `season-transition.md`. **No conflict.**

## The New Architecture

### Pipeline (`RCode/season_processor.R`)

`process_single_season` (the per-season loop body): change line 197's `warning(team_count_validation$message)` to `stop(...)`. Loop iteration with bad team count now aborts the pipeline.

`process_season_transition` (the orchestrator): after the loop completes successfully, before returning `success=TRUE`, call `validate_season_processing(target_season)`. On `valid=FALSE`, abort with the validation message.

Delete `create_processing_report` and `cleanup_processing_artifacts` from `RCode/season_processor.R`. Both have zero callers; the redundancy/wrong-glob analysis is in *Findings*.

### Operator wrapper (`scripts/season_transition.R`)

`main()` continues to call `process_season_transition` and capture `result`. After a successful return, before printing the completion message, iterate `result$files_created` and remove every entry **except** `RCode/TeamList_<target_season>.csv`. ~10 lines, inline. No globs — only files the pipeline reported as created. Deletion failures log a warning but do not break the run (the work is done; cleanup is courtesy).

### Recovery wrapper (`scripts/season_transition/cleanup.R` — new)

Standalone Rscript. Removes intermediate league CSVs from `RCode/` for a given season — only when something went wrong and `season_transition.R` did not get to its own cleanup step.

Restrictions (PoSD: "errors out of existence" + Single Responsibility):

- **Only matches** the regex `^TeamList_<season>_League(78|79|80)\.csv$` in `RCode/`. These are the exact filenames `process_single_season` produces via `generate_league_csv`.
- **Never touches**: the final `TeamList_<season>.csv`, `*.tmp`, `*.lock`, anything outside `RCode/`, anything in subdirectories. The pipeline does not produce those — they are not this tool's responsibility.

Behavior:

- Dry-run by default. Shows the matched files (including paths) and a re-run hint.
- `--confirm` flag deletes the matched files; prints the actual deletion list.
- On zero matches, prints an explanatory line — not silence — so the operator distinguishes "nothing to do" from "tool broken."

Header (from PRD-design Q18, variant b):

```r
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
```

Output (dry-run):

```
Cleanup dry-run for season 2025
Pattern: TeamList_2025_League(78|79|80).csv in RCode/
Would remove 3 files:
  RCode/TeamList_2025_League78.csv
  RCode/TeamList_2025_League79.csv
  RCode/TeamList_2025_League80.csv
Use --confirm to actually delete.
```

Output (`--confirm`):

```
Cleanup for season 2025
Removed 3 files:
  RCode/TeamList_2025_League78.csv
  RCode/TeamList_2025_League79.csv
  RCode/TeamList_2025_League80.csv
```

Output (zero matches):

```
No cleanup files found for season 2025.
(Searched RCode/ for TeamList_2025_League(78|79|80).csv)
```

## Tech Stack

R 4.2+, `Rscript`-based CLI matching the existing `scripts/season_transition.R` pattern. No new dependencies. No shared library file (the recovery wrapper is small enough to inline its handful of utility lines; "rule of three" not yet met).

## Interface — Before / After

```
# BEFORE — operator workflow
$ Rscript scripts/season_transition.R 2024 2025
# (silent if validate_team_count warns; intermediate files remain in RCode/)

# AFTER, happy path
$ Rscript scripts/season_transition.R 2024 2025
  # → pipeline runs, validates per-season, validates final season,
  #   removes intermediate league CSVs automatically.
  # → exit 0 on success; exit 1 on any validation failure with a clear message.

# AFTER, failure recovery
$ Rscript scripts/season_transition.R 2024 2025
  # → aborts with error message; intermediate files may remain.
$ Rscript scripts/season_transition/cleanup.R 2025
  # → dry-run, lists files that would be removed.
$ Rscript scripts/season_transition/cleanup.R 2025 --confirm
  # → removes them.
```

## Acceptance Criteria

### Functional

- [ ] `process_single_season` (`RCode/season_processor.R:194`-area): `validate_team_count` failure aborts via `stop(...)`, no longer just `warning(...)`.
- [ ] `process_season_transition` (`RCode/season_processor.R`): after the per-season loop, calls `validate_season_processing(target_season)`. On `valid=FALSE`, returns `list(success = FALSE, error = <validation message>)`.
- [ ] `main()` in `scripts/season_transition.R`: after a successful `process_season_transition` return, deletes every entry in `result$files_created` *except* `RCode/TeamList_<target_season>.csv`. Failures during this cleanup log a warning, do not abort the run.
- [ ] `scripts/season_transition/cleanup.R` exists. Takes `<season>` as positional arg. Dry-run by default. Accepts `--confirm` to actually delete. Matches only the regex `^TeamList_<season>_League(78|79|80)\.csv$` in `RCode/`.
- [ ] `cleanup.R` outputs match the formats above for the three cases (dry-run with matches, `--confirm`, zero matches).
- [ ] `RCode/season_processor.R` no longer contains `create_processing_report` nor `cleanup_processing_artifacts`. (Functions deleted, callers verified zero before removal.)

### Tests

- [ ] New: dry-run leaves files untouched. Setup: create three matching files in a temp `RCode/`, run cleanup without `--confirm`, assert all three still exist.
- [ ] New: `--confirm` removes all matched files. Same setup, run with `--confirm`, assert files gone.
- [ ] New: cleanup ignores foreign files. Setup: create matched files plus distractors (`TeamList_2025_archive.csv`, a `.tmp`, a `.lock`, and the final `TeamList_2025.csv`), run with `--confirm`, assert distractors and the final file untouched.
- [ ] New: zero matches prints the explanatory message (output captured via `system2(stdout=TRUE)`).
- [ ] New: `validate_team_count` failure in `process_single_season` aborts the loop. Setup: mock `validate_team_count` to return `valid=FALSE`, call into the pipeline, assert it errors.
- [ ] New: `validate_season_processing` failure at end-of-pipeline produces `success=FALSE`. Setup: run `process_season_transition` and induce final-CSV corruption (e.g., remove a required column), assert returned list has `success=FALSE` and a non-empty `error`.
- [ ] **Regression:** existing test suite passes without re-recording any snapshot. Specifically: `tests/testthat/test-team-count-validation.R` (six tests for `validate_team_count`) and the season-transition snapshot test continue green. **The repo's overall test status before the change must equal the test status after.**

### Documentation

- [ ] `docs/user-guide/season-transition.md`: new section at the end titled **"Recovery: Cleanup after a failed transition"** documenting the wrapper, its dry-run behavior, the `--confirm` flag, and the explicit "does NOT touch" list.
- [ ] `docs/user-guide/season-transition.md`: in **"Method 1: Automated Interactive Mode"** (after the existing prompt list), add one line: "On success, the script validates the produced TeamList_<target>.csv and removes intermediate league files automatically."
- [ ] `CLAUDE.md`: new section **"Conventions"** before "Current Status", containing one line: *"When adding helper functions in `RCode/` that operators run outside the production call graph: provide a `scripts/` wrapper, document it in `docs/user-guide/`, default destructive operations to dry-run with explicit `--confirm`."*

### Out of Scope (tracked elsewhere)

- API key in `debug_indices.R` and repo history — separate post-#74 PR (memorialised in `memory/project_followups_after_74.md`).
- Repo-root scratch files (`debug_indices.R`, `extract_test_data.R`, `final_quality_check.R`) — separate follow-up issue. Not the same problem as #74; they are one-off investigation files, lifecycle answer is "delete or archive," not "wrap."

## Test Strategy

**Existing snapshot test is the regression baseline.** It calls `process_season_transition` directly (not via `main`), so the new auto-cleanup in `main` doesn't affect it. The new validators only fire on validation *failures*; the snapshot's happy-path data passes them. Net: snapshot stays green without re-recording.

**Six new tests** target the *new* behaviors (cleanup wrapper restrictions, validator escalations). The cleanup tests use temp directories to avoid touching real `RCode/` files. The validator tests use mocks to inject failure conditions.

**Manual smoke test sequence** (operator-side, before declaring the change shipped):

1. Run a real season transition non-interactively, confirm `result$files_created` cleanup leaves only the final `TeamList_<season>.csv`.
2. Create three fake `TeamList_2099_League78.csv` etc. files. Run `cleanup.R 2099` (dry-run). Verify output. Run with `--confirm`. Verify deletion.
3. Run `cleanup.R 2099` again on the now-empty state. Verify the zero-matches message.

## Migration Steps (for the implementation plan)

The implementation order matters because some changes depend on others' tests passing:

1. **Tests first.** Add the six new tests, watch them fail (TDD). The validator tests will fail because the changes aren't in yet; the cleanup-wrapper tests will fail because the file doesn't exist yet.
2. **Pipeline validators.** Edit `process_single_season` (`warning` → `stop`). Edit `process_season_transition` (add end-of-run `validate_season_processing` call). Two new tests turn green. Existing snapshot test still green.
3. **Delete dead functions.** Remove `create_processing_report` and `cleanup_processing_artifacts` from `RCode/season_processor.R`. Run full test suite — confirm nothing breaks (no callers, no test should reference them).
4. **Operator-wrapper auto-cleanup.** Edit `scripts/season_transition.R::main` to delete `result$files_created` minus the final file after successful return.
5. **Recovery wrapper.** Create `scripts/season_transition/cleanup.R`. The four cleanup-wrapper tests turn green.
6. **Documentation.** New section in `docs/user-guide/season-transition.md`; new line in Method 1; new "Conventions" section in `CLAUDE.md`.
7. **Final verification.** Full test suite green. Manual smoke test sequence. Test status delta: zero (new tests pass; nothing previously passing now fails).

## Risks

- **Risk:** `validate_season_processing` is too strict and rejects valid seasons. Its team-count threshold is `team_count_expected * 0.8` (default 60 → minimum 48). The current pipeline produces 56–62 teams. Margin is comfortable. Mitigation: if a real season pulls fewer than 48 teams, that's a real signal the pipeline produced something wrong — preferable to silent success.
- **Risk:** `validate_team_count` failure inside the loop now aborts the pipeline mid-run, leaving partial intermediate files. The operator runs the recovery wrapper (which is exactly what it's for). The recovery wrapper's dry-run-default protects them.
- **Risk:** The recovery wrapper's regex misses an intermediate file the pipeline produces under some new naming convention. Mitigation: the regex matches what `generate_league_csv` produces today; if that function changes its output filename pattern, this PRD's tests don't catch it. Adding a smoke-test fixture or a contract test between `generate_league_csv` and `cleanup.R` is a candidate for a follow-up if the team list of leagues ever changes (currently `78`, `79`, `80` — Bundesliga, 2. Bundesliga, 3. Liga). Acceptable risk for now.
- **Risk:** A future maintainer adds a fourth helper to `RCode/season_processor.R` and again forgets to wire it in. Mitigation: the new "Conventions" section in `CLAUDE.md` makes the expectation explicit. Not bulletproof — but as Ousterhout puts it, conventions are the cheapest form of system-wide consistency.

## Why This Is Better Than the 2026-05-02 PRD

The original PRD's recommendation (three wrapper scripts in `scripts/` for three independently-runnable tools) would have:

- *kept* `create_processing_report` despite its full redundancy with the existing log,
- *kept* `cleanup_processing_artifacts`'s broad globs as a feature ("operator can clean up any debris"),
- *not* fixed the silent `validate_team_count` warning,
- created two parallel cleanup paths (Glob-based wrapper plus a possible future inline cleanup) with implicit responsibilities.

The new architecture is **smaller** (one new file instead of three; one new section instead of one full-page tool inventory), **safer** (list-based deletion in the happy path is unconditionally constrained; recovery wrapper has narrow regex + dry-run + confirm), and **PoSD-aligned**: each layer has its own abstraction and its own appropriate safety mechanism, not a one-size-fits-all wrapper convention. Information that the operator needs lives in docs; information that the code can express lives in code; information that the *next* maintainer needs lives in CLAUDE.md.
