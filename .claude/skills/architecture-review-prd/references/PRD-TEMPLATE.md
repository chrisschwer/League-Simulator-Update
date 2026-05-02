# PRD Output Template

This is the schema for PRDs produced by the `architecture-review-prd` skill. The shape is chosen so `superpowers:writing-plans` can consume it directly: `Goal`, `Architecture`, and `Tech Stack` map to the `writing-plans` plan header; `Acceptance Criteria` and `Test Strategy` seed the per-task TDD steps; `Interface — Before / After` tells `writing-plans` what to refactor toward.

Do not rename or reorder the top-level sections without a reason. Optional sections are marked.

---

```markdown
# [Short title — what changes, in 5–8 words]

**Scope:** `path/to/module-or-directory` (and any direct callers explicitly considered)
**Date:** YYYY-MM-DD
**Source:** architecture-review-prd skill

## Goal

One sentence. What is true after this lands that wasn't true before? Phrase as an outcome, not a task list.

> Example: "`process_season_transition` becomes a 20-line orchestrator that delegates I/O, validation, and CSV generation to dedicated units, each independently testable."

## Architecture

2–4 sentences. The shape of the change. Name the new boundaries and what crosses them. No code yet.

> Example: "Split `season_processor.R` into three units: `season_orchestrator.R` (the pipeline), `season_io.R` (CSV read/write/merge), and `season_validation.R` (the count and shape checks). The orchestrator depends on the other two; they don't depend on each other. The existing public entry point `process_season_transition()` keeps its signature."

## Tech Stack

The language(s), test framework, and any framework-specific tools the plan will use. Detected from the repo, not invented.

> Example: "R 4.2+, testthat 3.x, existing helper `tests/testthat/helper-test-setup.R`. No new dependencies."

## The Finding

What the architectural problem actually is. Be concrete: name the file, the function, the lines.

### Current State

- **Interface(s):** the public surface today (signatures, exports, entry points). Quote them.
- **Implementation shape:** what the unit currently does, in 3–6 bullets. Mention the responsibilities that are mixed.
- **Callers:** who calls this, and what they assume. List them.
- **Test coverage today:** what tests exist, what they cover, what they miss. Reference test file paths.

### Why this is a problem

2–4 sentences. Apply the deletion test or the deep-modules lens explicitly. *Why* is this shallow / leaky / coupled? What concrete cost does the current shape impose (bug class, change-amplification, test brittleness)?

If you can name a past incident from `KNOWN_ISSUES.md`, git log, or the user's chat, cite it. Concrete pain beats abstract critique.

## Interface — Before / After

Show the public surface, before and after. Use real signatures in the repo's language, not pseudocode. If the change is multi-file, show one block per file.

```
# BEFORE (RCode/season_processor.R)
process_season_transition <- function(source_season, target_season) { ... }   # ~90 lines, mixed concerns
generate_league_csv       <- function(teams, league_id, season) { ... }
validate_season_processing<- function(season, team_count_expected = 60) { ... }

# AFTER (RCode/season_orchestrator.R)
process_season_transition <- function(source_season, target_season) { ... }   # ~20 lines, delegates only

# AFTER (RCode/season_io.R)
write_league_csv          <- function(teams, league_id, season) { ... }
read_team_list            <- function(season) { ... }

# AFTER (RCode/season_validation.R)
validate_season           <- function(season, expected_counts) { ... }
```

If a name changes, say so explicitly here so `writing-plans` and the executing agent don't drift.

## Design Options Considered

At least two. Each gets:

- **Sketch:** the alternate interface in 2–4 lines.
- **Trade-off:** what it's better at, what it's worse at.
- **Migration cost:** rough sense of cutover scope.

### Option A — [name] *(recommended)*

> Sketch …
> Trade-off …
> Migration cost …

### Option B — [name]

> Sketch …
> Trade-off …
> Migration cost …

### Recommendation

One paragraph. Why A wins on the trade-off that matters most *for this codebase, right now*. If the answer would change under different constraints (smaller team, hotter deadline, no test coverage), say so — that's a useful future signal.

## Acceptance Criteria

Testable, observable. Each criterion should map to at least one test in the Test Strategy below. Use checkboxes — `writing-plans` and humans both like them.

- [ ] `process_season_transition()` is ≤ 30 lines and contains no direct file I/O.
- [ ] All existing tests in `tests/testthat/test-season-processor.R` pass unchanged.
- [ ] New unit tests cover `season_io.R` and `season_validation.R` independently of the orchestrator.
- [ ] No caller outside the scope changes.
- [ ] `KNOWN_ISSUES.md` ELO regression scenario is reproducible as a regression test before the refactor and passes after.

## Test Strategy

Two layers. Both use the test framework detected from the repo (no introducing a new framework here — that's a separate PRD).

### Pin current behavior (regression net, written first)

List the tests that must exist *before* you start moving code. Each one: file path, what it asserts, what it would catch.

- `tests/testthat/test-season-orchestrator-regression.R` — invokes `process_season_transition(2023, 2024)` against a fixture and snapshots the resulting CSVs. Catches behavioral drift during the split.

### Prove the new shape (post-refactor tests)

Tests against the new units, written as the refactor lands. Each unit gets its own test file.

- `tests/testthat/test-season-io.R` — round-trip a known team list through `write_league_csv` / `read_team_list`. No network, no orchestrator.
- `tests/testthat/test-season-validation.R` — feed valid and invalid team-count vectors; assert the right errors.

## Migration Steps

High-level, not task-level. `writing-plans` will turn these into bite-sized tasks. Aim for 4–8 ordered steps.

1. Add regression tests against current `process_season_transition` behavior. Run, confirm green.
2. Extract `season_io.R` (move functions, no signature changes). Re-run all tests.
3. Extract `season_validation.R`. Re-run.
4. Reduce `process_season_transition` to delegation only. Re-run.
5. Add per-unit tests for the new modules.
6. Delete the regression-net snapshot tests if they duplicate the new unit tests; keep one end-to-end test.

## Risks

- **Risk:** Hidden caller in a script outside `RCode/` (e.g., `scripts/season_transition.R`) breaks because of an internal-helper rename.
  - **Mitigation:** Grep for every renamed name across the whole repo before merging Step 4.
- **Risk:** CSV byte-for-byte output changes because of an extraction subtlety.
  - **Mitigation:** Snapshot test in Step 1 catches this; if it triggers, decide whether the diff is intentional before proceeding.

## Open Questions

Things you don't know that the implementer will need to decide. Don't pretend they're decided.

- Should `season_io.R` own the choice of output directory, or should the orchestrator pass it in? (Argues for testability vs. caller convenience.)
- Is the `previous_team_list` parameter on `process_league_teams` still used by any caller? If not, drop it during the split.

## Suggested Phasing *(include only if the refactor is too big for one TDD cycle)*

If the migration steps above span > ~5 files or > 1 changing public interface, name Phase 1 here as the smallest shippable slice, and note: "Phases 2+ should be derived by re-running `architecture-review-prd` on the post-Phase-1 state. The codebase will look different by then; don't pre-plan."

## Adjacent Observations *(optional)*

Things noticed during the review that are *out of scope* but worth recording for a future review. Do not turn these into tasks here.

- `RCode/csv_generation.R` shows similar mixed-responsibility patterns; candidate for a separate review.
```
