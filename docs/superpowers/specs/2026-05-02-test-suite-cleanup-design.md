# Test suite cleanup — review, prune, and align with post-cleanup architecture

**Issue:** prerequisite to [#76](https://github.com/chrisschwer/League-Simulator-Update/issues/76) (CI rebuild)
**Date:** 2026-05-02
**Status:** design approved, awaiting implementation plan

## Goal

Reduce `tests/testthat/` to a focused suite that protects exactly two workflows:

1. **Production loop** — the R scheduler ↔ Rust seam that runs in the Docker container at 14:45 Berlin time (`RCode/updateScheduler.R` → `RCode/update_all_leagues_loop.R` → `RCode/rust_integration.R::leagueSimulatorRust()` → Rust HTTP API).
2. **Season-transition operator workflow** — `scripts/season_transition.R` and the 18 `RCode/` modules it sources.

Remove tests that target deleted infrastructure (k8s, multi-Dockerfile microservices, the simple-monolithic loop), redundant tests for the C++ engine where the Rust suite already covers the same conceptual edge case, and helper files no surviving test uses. The result becomes the foundation for issue #76's CI rebuild — a CI pipeline against a bloated, partially-broken suite would just lock in the bloat.

## Non-goals

- **Out of scope:** CI rebuild itself (issue #76, the follow-up).
- **Out of scope:** any change inside `RCode/`, `scripts/`, `Dockerfile`, `docker-compose.yml`, or the Rust crate.
- **Out of scope:** the disabled CI workflows in `.github/workflows/*.disabled` and `*.bak`.
- **Out of scope:** new test coverage *beyond* what the audit identifies as a real gap. The bar for adding a test is "the audit proved an existing keep test is too coarse to catch a regression in surviving production code."

## Coordination with other in-flight specs

**Issue #81** (`docs/superpowers/specs/2026-05-02-prune-root-clutter-design.md`): zero file overlap with this spec. Both touch `CLAUDE.md` in different sections — #81 modifies the `## Quick Commands` block and removes the `@docs/COMMANDS.md` reference; this spec removes the `Test Suite` status line at `CLAUDE.md:48` that points to the missing `docs/TEST_FIX_PLAN.md`. Recommended merge order is #81 → this spec, but either order works (textual diffs do not collide). PR-A's commit message records the dependency state at execution time.

## Decisions (with rationale)

| Decision | Choice | Rationale |
|---|---|---|
| Scope of "what to protect" | Production loop + season-transition operator workflow | These are the two workflows the repo actually runs. A hobbyist project doesn't need broader coverage. |
| C++ engine wrapper tests (`test-SpielCPP.R`, `test-simulationsCPP.R`, `test-SaisonSimulierenCPP.R`) | Delete after empirical CPP audit | Rust suite (~20 tests) covers every conceptual edge case the R wrappers hit. `test-SpielNichtSimulieren.R` stays — it's the only test that exercises the `.cpp` directly. |
| C++ engine via season-transition (`SpielCPP.R` is sourced by `scripts/season_transition.R:65`) | Trust `test-season-transition-regression.R` if it actually catches changes; else add one targeted TDD test | The audit (Phase 2 below) is the only honest way to know. |
| Deprecated-stack tests (k8s/microservices/simple-monolithic) | Per-file audit, default action delete, port only when an isolated test protects a real surviving code path | One read per file (~7 files). Audit is cheap; deletion is decisive. |
| Named subdirectories of `tests/testthat/` (`test-api/`, `test-helpers/`, `test-schedulers/`, `test-shiny/`, `test-edge-cases/`) | Per-file audit — see Phase 3 | User chose strict per-file over wholesale-by-directory. |
| Unnamed/accidental subdirectories (`tests/testthat/temp/`, `tests/testthat/tests/`) | Mechanical delete in PR-A (after confirming contents are accidental) | These look like test runner artifacts or accidental nesting, not intentional test groupings. |
| Helper files (`helper-deployment.R`, `helper-fixtures.R`, `helper-performance-baseline.R`, `helper-test-setup.R`) | Dependency-driven: a helper survives only if a kept test calls it | Rigorous, not "looks useful." Done after the keep set is frozen. |
| Doc cleanup | Half-in-scope: kill the two dangling `TEST_FIX_PLAN.md` references and delete the four orphan `docs/TEST_*.md` files. No new overview doc. | Test files and `CLAUDE.md` are enough. New docs rot when nobody reads them. |
| TDD policy for any new/ported tests | Strict — RED first against a behavior-changing mutation, then revert, GREEN | The audit produces a precise gap statement. Adding a test that closes the gap *is* TDD. |
| Execution shape | Two PRs — mechanical first, audit-driven second | PR-A is trivially reviewable (pure deletion of provably-dead artifacts). PR-B isolates the judgment work and is independently revertable. |

## Inventory

### Files in scope (current state of `tests/testthat/`)

**Keep-firm** (production loop or season-transition, no overlap):

| File | Protects |
|---|---|
| `test-rust-required.R` | Production loop ↔ Rust contract (landed in #83) |
| `test-prozent.R` | `RCode/prozent.R` math |
| `test-Tabelle.R` | Table/standings logic — used by both workflows |
| `test-SpielNichtSimulieren.R` | `RCode/SpielNichtSimulieren.cpp` directly (the only test that does so) |
| `test-season-processor.R` | Season-transition: per-season processing |
| `test-season-validation.R` | Season-transition: input validation |
| `test-season-transition-regression.R` | Season-transition: end-to-end CSV contract |
| `test-team-count-validation.R` | Season-transition: team-count rules |
| `test-interactive-prompts.R` | Season-transition: input handling |
| `test-transform_data.R` | Season-transition: data transformation |

**Keep-pending CPP audit** (will be deleted after Phase 2 of PR-B confirms the regression test catches `SpielCPP.R` changes; or after a new targeted test is added if it does not):

- `test-SpielCPP.R` (10 `test_that()` blocks)
- `test-simulationsCPP.R` (8 `test_that()` blocks)
- `test-SaisonSimulierenCPP.R` (10 `test_that()` blocks)

**Audit-then-delete-or-port** (deprecated-stack, mock-heavy, or unknown):

- `test-deployment.R`, `helper-deployment.R` (k8s configmap world)
- `test-simple-integration.R`, `test-integration-e2e.R`, `test-e2e-simulation-workflow.R` (deleted simple-monolithic loop)
- `test-edge-cases/` (directory)
- `test-elo-basic.R` (mock-heavy ELO re-implementation)
- `test-api/`, `test-helpers/`, `test-schedulers/`, `test-shiny/` (subdirectories — audit per file)
- `helper-fixtures.R`, `helper-performance-baseline.R`, `helper-test-setup.R` (audited after keep set is frozen — Phase 4)

**Mechanical deletes (PR-A, no judgment):**

- `tests/testthat/test-SaisonSimulierenCPP.R.bak` — `.bak` files don't belong in version control.
- `tests/testthat/temp/` — directory.
- `tests/testthat/tests/` — accidental nested directory (confirm contents are accidental during execution; abort to PR-B audit if not).

### Doc cleanup (in scope)

**Files deleted (4 — describe the pre-cleanup test world):**

- `docs/TEST_SUMMARY.md` (8-phase deployment-safety infrastructure description)
- `docs/TEST_ORGANIZATION.md`
- `docs/TEST_SUITE_FINAL.md`
- `docs/TEST_SIMPLIFICATION_PLAN.md` (superseded by this spec)

**Files modified (2 — remove dangling references to the missing `docs/TEST_FIX_PLAN.md`):**

- `CLAUDE.md` line 48 — remove the `Test Suite` status line.
- `docs/KNOWN_ISSUES.md` lines 5–8 — remove the `Test Suite Failures (In Progress)` block.

### Eligible-for-PR-A-iff-orphaned

- `tests/testthat/_snaps/` — PR-A deletes only if no surviving test references it.
- `tests/testthat/fixtures/` — same condition. Otherwise routes to PR-B audit.

## Design

### PR-A — Mechanical cleanup (one branch, ~3 commits)

**Branch:** `feature/issue-76-test-cleanup-mechanical`, off `main` via `superpowers:using-git-worktrees`.

**Commits:**

1. `chore(#76): delete .bak and accidental nested test directories`
   - `tests/testthat/test-SaisonSimulierenCPP.R.bak`
   - `tests/testthat/temp/`
   - `tests/testthat/tests/` (after confirming contents are accidental — abort to PR-B if not)
   - `tests/testthat/_snaps/` and `tests/testthat/fixtures/` *iff* provably orphaned (no surviving test references them)

2. `chore(#76): delete pre-cleanup TEST_*.md planning docs`
   - `docs/TEST_SUMMARY.md`, `docs/TEST_ORGANIZATION.md`, `docs/TEST_SUITE_FINAL.md`, `docs/TEST_SIMPLIFICATION_PLAN.md`

3. `docs(#76): remove dangling TEST_FIX_PLAN.md references`
   - `CLAUDE.md:48`
   - `docs/KNOWN_ISSUES.md:5-8`

**Baseline capture (before commit 1):** Run `Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tee /tmp/baseline-suite.txt` and record pass/fail/skip counts. This is the regression target.

**After each commit:** Re-run the suite and compare counts against `/tmp/baseline-suite.txt`. PR-A introduces zero behavior change — it only removes things nothing reads. Pass count must be identical (or, after the `.bak` deletion, off by exactly the count of `test_that()` blocks in the deleted `.bak` file *if* testthat had been picking it up — confirm before claiming PR-A regressed).

**Abort condition:** if any deletion turns out to be non-obvious (i.e., something *does* reference it), it gets bumped from PR-A to PR-B's audit. PR-A's strict rule is "if there's any judgment, it's not PR-A."

### PR-B — Audit-driven cleanup (one branch, ~10–25 commits)

**Branch:** `feature/issue-76-test-cleanup-audit`, off `main` *after* PR-A merges (not off PR-A's branch — keeps PR-B reviewable in isolation).

#### Phase 1 — Verdict table (1 commit)

`docs(#76): test suite audit verdict table`

Adds `docs/superpowers/notes/test-suite-audit-2026-05-02.md` with one line per file in `tests/testthat/`: `path | keep-firm | delete | port | <one-line justification naming the protected code path or the reason>`. Reviewers can disagree before deletions land.

This file is **temporary**. It is deleted in Phase 5 (final commit of PR-B). The verdict table also goes in the PR-B description so the historical record survives in the merged PR.

#### Phase 2 — CPP audit (2 commits)

**Pre-picked mutation for the audit:** in `RCode/SpielCPP.R`, locate the K-factor (or equivalent rating-delta scaling constant) using `grep -nE 'modFaktor|kFactor|k_factor|delta.*factor|rating.*\* ' RCode/SpielCPP.R` and divide its value by 2. Properties: (a) reversible in one `git checkout RCode/SpielCPP.R`; (b) guaranteed to alter observable ELO output for any non-zero match; (c) doesn't break the function signature, so the regression test runs to completion rather than erroring out. The exact line is pinned at execution time when the worker reads the current `SpielCPP.R` — do **not** mutate anything that affects the function signature or causes a load-time error, because that turns the audit into a "did the test load" check rather than a "did the test catch a behavior change" check.

Commit 1 — `test(#76): CPP audit — confirm season-transition regression test catches SpielCPP.R changes`:

1. Run `test-season-transition-regression.R` against current `main`. Confirm pass.
2. Apply the K-factor mutation. Re-run `test-season-transition-regression.R`.
3. **If it fails (mutation caught):** revert mutation. Record outcome in commit message. No new test.
4. **If it passes (regression test too coarse):** revert mutation. Write `test-season-transition-cpp-contract.R` via TDD — RED first (with mutation reapplied → fails as expected), then revert mutation, then GREEN. Record outcome in commit message.

Commit 2 — `test(#76): delete redundant CPP wrapper tests`:

- Remove `test-SpielCPP.R`, `test-simulationsCPP.R`, `test-SaisonSimulierenCPP.R`.
- Keep `test-SpielNichtSimulieren.R` (the only test that exercises the `.cpp` directly).

#### Phase 3 — Deprecated-stack and subdirectory audit (~5–15 commits)

For each file: open it, decide one of:

- **Delete (default):** test references deleted code, mocks reality, or duplicates a kept test.
- **Port:** contains one or two tests that protect a real surviving code path nothing else covers — port those into the appropriate keep file via TDD (RED with mutation, GREEN after revert), delete the rest of the file.

Files in the audit pass: `test-deployment.R`, `helper-deployment.R` (helper, but tied to `test-deployment.R`'s lifetime — co-deleted), `test-simple-integration.R`, `test-integration-e2e.R`, `test-e2e-simulation-workflow.R`, `test-edge-cases/`, `test-elo-basic.R`, `test-api/`, `test-helpers/`, `test-schedulers/`, `test-shiny/`.

One commit per file or cohesive group: `test(#76): delete <path> — <one-line audit verdict>` (or `test(#76): port <which tests> from <path>, delete remainder` for the port case).

#### Phase 4 — Helper prune (1+ commits)

After Phases 2–3 freeze the keep set:

1. For each surviving test file, list every helper function/object it actually calls. Grep for direct function calls *and* testthat's auto-source side effects (`setup(`, `teardown(`, on-load expressions).
2. For each `helper-*.R`, mark as "used" if any surviving test calls anything it defines.
3. Delete unused helpers wholesale. For partially-used helpers, delete the unused functions only.
4. Re-run the suite — must stay green. Any failure unwinds the helper deletion in question.

#### Phase 5 — Final verification (1 commit)

`test(#76): final verification — suite green, smoke test clean`

Records the following in the commit message:

- testthat output: pass count, zero failures, no skips that hide a deletion candidate.
- Sandboxed season-transition smoke-test exit code and post-restore `git status` output (see Verification section below for the exact snippet).
- `docker build -t league-simulator:test .` exit code (confirms no test-only file was being COPY'd into the image).

Also deletes `docs/superpowers/notes/test-suite-audit-2026-05-02.md` (the temporary verdict table from Phase 1).

## Verification

### Sandboxed season-transition smoke test (Phase 5)

The script writes `TeamList_<season>.csv` files into `RCode/` (default) — see `RCode/csv_generation.R:55`. Sandbox approach uses `git stash --include-untracked` so any new file is also captured:

```bash
# (1) Snapshot any tracked-but-dirty or untracked CSVs under RCode/ before the smoke test.
git stash push --include-untracked -m "season-transition smoke test snapshot" -- RCode/

# (2) Run season-transition non-interactively. Capture exit code and output.
RAPIDAPI_KEY="${RAPIDAPI_KEY:-}" Rscript scripts/season_transition.R 2024 2025 --non-interactive
ST_EXIT=$?

# (3) Restore the snapshot. If stash was empty (nothing to snapshot), that's fine.
git stash pop 2>/dev/null || true

# (4) Verify no tracked file is dirty after restore.
git status --porcelain RCode/

# (5) Pass criteria: ST_EXIT == 0 AND step (4) shows no output.
```

**Skip vs. fail:** per `docs/KNOWN_ISSUES.md`, `season_transition.R` without a valid `RAPIDAPI_KEY` exits 0 but produces a no-op (existing ELO values pass through unchanged) — meaning the smoke test's pass criteria above would *silently pass* without exercising the workflow. The Phase 5 commit message must therefore record one of two explicit states:

- **`smoke=ran`** — `RAPIDAPI_KEY` was set, the script reported non-trivial work (ELO updates in stdout), exit code was 0, post-restore `git status` was clean.
- **`smoke=skipped (no API key)`** — `RAPIDAPI_KEY` was empty or invalid; the smoke test was not run. This is acceptable; do not mark it as a pass.

A passing-but-no-op run does not satisfy the smoke-test gate.

### Suite verification (after each phase)

```bash
Rscript -e 'testthat::test_dir("tests/testthat")'
# Expect: 0 failures. Pass count must monotonically decrease from baseline (deletions only).
```

### Image-build sanity (Phase 5 only)

```bash
docker build -t league-simulator:test .
# Expect: success. Confirms no test-only file was being COPY'd into the image.
```

### Doc-reference cleanup (after PR-A merges)

```bash
grep -F 'TEST_FIX_PLAN.md' CLAUDE.md docs/KNOWN_ISSUES.md
# Expect: no output

ls docs/TEST_SUMMARY.md docs/TEST_ORGANIZATION.md docs/TEST_SUITE_FINAL.md docs/TEST_SIMPLIFICATION_PLAN.md 2>/dev/null
# Expect: no output (all four deleted)
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| PR-A's "obvious garbage" turns out not to be garbage | Low | `git log --diff-filter=A -- <path>` for each deletion; non-obvious deletions get bumped to PR-B audit (PR-A abort condition) |
| CPP audit's mutation passes through `test-season-transition-regression.R` (regression test too coarse) | Medium | Expected branch — Phase 2 step 4 writes a new TDD test. No spec-level risk. |
| A keep-firm test secretly relies on a helper deleted in Phase 4 | Low | Phase 4 ends with re-running the suite; any failure unwinds the helper deletion |
| Smoke test mutates a CSV not in the snapshot | Low | `git stash --include-untracked` covers any new file; post-restore `git status` check catches misses |
| A test we delete was the *only* test catching a regression in some `RCode/` helper used by both workflows but not directly tested elsewhere | Medium | Phase 1 verdict table forces a "what protects this code path" answer for every keep, which surfaces the inverse for every delete. Reviewer has the verdict table before any deletion lands. |
| Merge conflict with #81 (`prune-root-clutter`) on `CLAUDE.md` | Low | Different sections — #81 edits `## Quick Commands`, this spec edits `Test Suite` line at `:48`. Diffs do not collide. |
| Merge conflict with #76's eventual CI rebuild | None | This spec is the prerequisite to #76; CI rebuild builds against the cleaned suite. |

## Recovery paths

| Action | Recovery |
|---|---|
| PR-A merged, regret about a deletion | `git revert <merge-commit>` — pure deletions, no side effects |
| PR-B Phase 2 deletion (CPP wrappers) regretted | `git revert <single-commit>` — Phase 2 is two commits, deletion is its own |
| PR-B Phase 3 file deletion regretted | `git revert <single-commit>` — one commit per file or cohesive group |
| PR-B Phase 4 helper deletion regretted | `git revert <single-commit>` |
| Whole PR-B regretted | `git revert <merge-commit>`; or restore from `pre-deployment-cleanup-2026-05-02` tag for pre-#78 baseline |

## Estimated effort

- **PR-A:** 30–60 min.
- **PR-B:** 4–8 hours of audit work spread across ~15 commits. The Phase 2 mutation test is the only step that risks ballooning if the regression test turns out to need a real new TDD test.

## Definition of done

1. PR-A merged: dangling refs gone, four orphan TEST_*.md docs deleted, `.bak` and accidental nested directories removed.
2. PR-B merged: every surviving file in `tests/testthat/` is on the keep list, every keep file passes against current `main`, and the CPP audit's mutation test confirms `test-season-transition-regression.R` (or a new targeted test) catches `SpielCPP.R` regressions.
3. `Rscript -e 'testthat::test_dir("tests/testthat")'` runs green locally — 0 failures, no skips that hide deletion candidates.
4. Sandboxed season-transition smoke test recorded as `smoke=ran` (preferred) or `smoke=skipped (no API key)` in the Phase 5 commit message. A no-op pass does not satisfy this gate.
5. `docker build` succeeds.
