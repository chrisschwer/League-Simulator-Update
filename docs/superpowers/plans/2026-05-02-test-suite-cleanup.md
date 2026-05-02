# Test Suite Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce `tests/testthat/` to a focused suite that protects the production loop (R scheduler ↔ Rust seam) and the season-transition operator workflow, by removing tests for deleted infrastructure (k8s/microservices/simple-monolithic), redundant CPP wrapper tests already covered by the Rust suite, helpers no surviving test uses, and dangling/orphan documentation.

**Architecture:** Two PRs off `main`. PR-A is mechanical (pure deletion of provably-dead artifacts, no judgment). PR-B is audit-driven (per-file decisions, with one empirical CPP audit using a K-factor mutation, then a dependency-driven helper prune, ending with a sandboxed season-transition smoke test). Each PR uses its own worktree per `superpowers:using-git-worktrees`.

**Tech Stack:** R 4.3.1 + testthat 3.x, Rscript, bash, git, Docker. No new dependencies.

**Reference:** Spec at `docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md`. Prerequisite to GitHub issue #76 (CI rebuild). Coordinated with #81 (`docs/superpowers/specs/2026-05-02-prune-root-clutter-design.md`) — zero file overlap; both edit `CLAUDE.md` in different sections.

**Survivor list — DO NOT TOUCH (kept in BOTH PRs):**

- All of `RCode/` (production source)
- All of `scripts/` (operator workflow)
- `Dockerfile`, `docker-compose.yml`, `docker-start.sh`
- All of `league-simulator-rust/` (Rust crate + Rust tests)
- The "Keep-firm" testthat files: `test-rust-required.R`, `test-prozent.R`, `test-Tabelle.R`, `test-SpielNichtSimulieren.R`, `test-season-processor.R`, `test-season-validation.R`, `test-season-transition-regression.R`, `test-team-count-validation.R`, `test-interactive-prompts.R`, `test-transform_data.R`
- `tests/testthat.R` (the testthat entrypoint)

---

## File Inventory

### PR-A: files deleted (10 paths, all proven non-load-bearing)

| Path | Reason |
|---|---|
| `tests/testthat/test-SaisonSimulierenCPP.R.bak` | `.bak` files don't belong in version control |
| `tests/testthat/temp/` | Empty directory |
| `tests/testthat/tests/` | Accidental `tests/testthat/tests/testthat/` nested-runner artifact |
| `tests/testthat/_snaps/` | Empty directory (no surviving snapshot tests) |
| `tests/testthat/test-schedulers/` | Empty directory |
| `tests/testthat/test-shiny/` | Empty directory |
| `docs/TEST_SUMMARY.md` | Pre-cleanup 8-phase deployment-safety description |
| `docs/TEST_ORGANIZATION.md` | Same era |
| `docs/TEST_SUITE_FINAL.md` | Same era |
| `docs/TEST_SIMPLIFICATION_PLAN.md` | Superseded by this spec |

### PR-A: files modified (2 paths)

| Path | Change |
|---|---|
| `CLAUDE.md` (line 48) | Remove the "Test Suite" status line that points to the missing `docs/TEST_FIX_PLAN.md` |
| `docs/KNOWN_ISSUES.md` (lines 3–10) | Remove the entire "Current Issues" / "Test Suite Failures (In Progress)" block |

### PR-B: files audited

**Single files:**
- `tests/testthat/test-deployment.R`
- `tests/testthat/helper-deployment.R` (co-deleted with `test-deployment.R`)
- `tests/testthat/test-simple-integration.R`
- `tests/testthat/test-integration-e2e.R`
- `tests/testthat/test-e2e-simulation-workflow.R`
- `tests/testthat/test-elo-basic.R`
- `tests/testthat/test-SpielCPP.R` (CPP audit)
- `tests/testthat/test-simulationsCPP.R` (CPP audit)
- `tests/testthat/test-SaisonSimulierenCPP.R` (CPP audit)

**Subdirectories (per-file audit):**
- `tests/testthat/test-edge-cases/` (1 file: `test-extreme-scenarios.R`)
- `tests/testthat/test-api/` (1 file: `test-api-errors.R`)
- `tests/testthat/test-helpers/` (3 files: `api-mock-fixtures.R`, `elo-mock-generator.R`, `season-transition-mocks.R`)
- `tests/testthat/fixtures/` (3 subdirs: `api-responses/`, `rust-required/`, `test-data/` — at least `rust-required/` is referenced by `test-rust-required.R`, so this directory survives but its contents are pruned per-fixture)

**Helpers (Phase 4, dependency-driven prune):**
- `tests/testthat/helper-fixtures.R`
- `tests/testthat/helper-performance-baseline.R`
- `tests/testthat/helper-test-setup.R`

### PR-B: files possibly created

- `tests/testthat/test-season-transition-cpp-contract.R` — only if Phase 2's audit shows `test-season-transition-regression.R` does not catch the K-factor mutation
- `docs/superpowers/notes/test-suite-audit-2026-05-02.md` — temporary verdict table; deleted before PR-B closes

---

## PR-A: Mechanical Cleanup

### Task 0: Worktree + baseline capture

**Goal:** Create the PR-A worktree off `main` and capture the suite baseline so subsequent commits can verify "no behavior change."

**Files:** None modified.

- [ ] **Step 1: Create the worktree (using superpowers:using-git-worktrees)**

From the main checkout's repo root:

```bash
git fetch origin
git worktree add ../League-Simulator-Update.issue-76-mechanical -b feature/issue-76-test-cleanup-mechanical origin/main
cd ../League-Simulator-Update.issue-76-mechanical
git status --short
git branch --show-current
```

Expected: empty status; branch `feature/issue-76-test-cleanup-mechanical`.

- [ ] **Step 2: Capture the test-suite baseline**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tee /tmp/baseline-suite.txt
echo "---SUMMARY---"
grep -E '^\[ FAIL [0-9]+ \| WARN [0-9]+ \| SKIP [0-9]+ \| PASS [0-9]+ \]' /tmp/baseline-suite.txt | tail -1
```

Expected: a single summary line of the form `[ FAIL N | WARN N | SKIP N | PASS N ]`. Record this — every PR-A commit's verification compares against it.

If the suite cannot run at all (e.g., a missing package), do **not** proceed. Investigate, fix the runner (without touching tests), or document the inability and abort PR-A.

- [ ] **Step 3: Confirm spec is reachable from this worktree**

```bash
ls docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md
```

Expected: file exists.

(No commit at the end of Task 0.)

---

### Task 1: Delete the .bak file and the empty/accidental directories

**Files:**
- Delete: `tests/testthat/test-SaisonSimulierenCPP.R.bak`
- Delete: `tests/testthat/temp/`
- Delete: `tests/testthat/tests/`
- Delete: `tests/testthat/_snaps/`
- Delete: `tests/testthat/test-schedulers/`
- Delete: `tests/testthat/test-shiny/`

- [ ] **Step 1: Verify the directories are still empty (or accidentally nested)**

```bash
ls tests/testthat/temp/
ls tests/testthat/_snaps/
ls tests/testthat/test-schedulers/
ls tests/testthat/test-shiny/
ls tests/testthat/tests/
```

Expected:
- `temp/`, `_snaps/`, `test-schedulers/`, `test-shiny/` produce no output (empty).
- `tests/` shows a single `testthat` subdirectory (the accidental nesting).

**Abort condition:** if any of `temp/`, `_snaps/`, `test-schedulers/`, `test-shiny/` is **not** empty, or if `tests/testthat/tests/` contains a real test file (anything beyond an empty `testthat` directory or test-runner artifacts), do **not** delete it. Bump the affected path to PR-B's audit and continue with the remaining deletions.

- [ ] **Step 2: Delete the .bak file**

```bash
git rm tests/testthat/test-SaisonSimulierenCPP.R.bak
```

Expected: `rm 'tests/testthat/test-SaisonSimulierenCPP.R.bak'`.

- [ ] **Step 3: Delete the empty/accidental directories**

```bash
git rm -r tests/testthat/temp tests/testthat/_snaps tests/testthat/test-schedulers tests/testthat/test-shiny tests/testthat/tests
```

Expected: a list of `rm '...'` lines. If a directory was empty (no tracked content), `git rm` will fail — in that case, just `rmdir` it from the working tree:

```bash
for d in tests/testthat/temp tests/testthat/_snaps tests/testthat/test-schedulers tests/testthat/test-shiny tests/testthat/tests; do
  if git ls-files --error-unmatch "$d" >/dev/null 2>&1; then
    : # already handled by git rm
  else
    rmdir "$d" 2>/dev/null || rm -rf "$d"
  fi
done
git status --short
```

Expected: a `D` (deleted) line for each removed path that was tracked.

- [ ] **Step 4: Run the suite and compare to baseline**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: the summary line. Compare to baseline — pass/fail counts must be identical (the deleted artifacts contained no live test code).

If the count differs, the deletion broke something. Stop and investigate — do **not** commit until counts match.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(#76): delete .bak and accidental nested test directories

Removes:
- tests/testthat/test-SaisonSimulierenCPP.R.bak (.bak files don't belong in VCS)
- tests/testthat/temp/ (empty)
- tests/testthat/_snaps/ (empty, no surviving snapshot tests)
- tests/testthat/test-schedulers/ (empty)
- tests/testthat/test-shiny/ (empty)
- tests/testthat/tests/ (accidental tests/testthat/tests/testthat/ nesting)

Test suite pass/fail counts identical to main baseline.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Delete the four orphan TEST_*.md planning docs

**Files:**
- Delete: `docs/TEST_SUMMARY.md`
- Delete: `docs/TEST_ORGANIZATION.md`
- Delete: `docs/TEST_SUITE_FINAL.md`
- Delete: `docs/TEST_SIMPLIFICATION_PLAN.md`

- [ ] **Step 1: Confirm the files exist and are tracked**

```bash
git ls-files docs/TEST_SUMMARY.md docs/TEST_ORGANIZATION.md docs/TEST_SUITE_FINAL.md docs/TEST_SIMPLIFICATION_PLAN.md
```

Expected: all four paths listed.

- [ ] **Step 2: Verify no live source references them**

```bash
grep -rEn 'TEST_SUMMARY\.md|TEST_ORGANIZATION\.md|TEST_SUITE_FINAL\.md|TEST_SIMPLIFICATION_PLAN\.md' \
  --include='*.R' --include='*.yml' --include='*.yaml' --include='*.sh' \
  --include='Dockerfile*' --include='docker-compose*' . 2>/dev/null
```

Expected: no output (no live source references the four docs).

It is OK if `*.md` files reference them — those are historical PRDs/plans and stay. We are checking that **executable** code does not depend on them.

- [ ] **Step 3: Delete the four files**

```bash
git rm docs/TEST_SUMMARY.md docs/TEST_ORGANIZATION.md docs/TEST_SUITE_FINAL.md docs/TEST_SIMPLIFICATION_PLAN.md
```

Expected: four `rm '...'` lines.

- [ ] **Step 4: Re-run the suite (sanity)**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: identical to baseline. (Doc deletions don't touch tests, but verifying is cheap.)

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(#76): delete pre-cleanup TEST_*.md planning docs

These four docs describe the pre-cleanup test world (8-phase deployment-safety
infrastructure, the 640→150 simplification proposal). Superseded by
docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md.

- docs/TEST_SUMMARY.md
- docs/TEST_ORGANIZATION.md
- docs/TEST_SUITE_FINAL.md
- docs/TEST_SIMPLIFICATION_PLAN.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Remove dangling TEST_FIX_PLAN.md references

**Files:**
- Modify: `CLAUDE.md` (line 48)
- Modify: `docs/KNOWN_ISSUES.md` (lines 3–10)

- [ ] **Step 1: Confirm the references are exactly as expected**

```bash
grep -n 'TEST_FIX_PLAN\.md' CLAUDE.md docs/KNOWN_ISSUES.md
```

Expected:

```
CLAUDE.md:48:- **Test Suite**: 🚧 38 tests failing - repair in progress (see @docs/TEST_FIX_PLAN.md)
docs/KNOWN_ISSUES.md:7:**Tracking**: See [Test Fix Plan](TEST_FIX_PLAN.md) for detailed progress
```

If the line numbers or text differ, adjust the edits below to match the actual current content. Do not blindly apply if the file has shifted.

- [ ] **Step 2: Edit `CLAUDE.md` — remove the Test Suite status line**

Use the Edit tool to replace:

```
- **Test Suite**: 🚧 38 tests failing - repair in progress (see @docs/TEST_FIX_PLAN.md)
- **Season**: 2024-2025
```

with:

```
- **Season**: 2024-2025
```

Verify with:

```bash
grep -n 'TEST_FIX\|Test Suite' CLAUDE.md
```

Expected: no output.

- [ ] **Step 3: Edit `docs/KNOWN_ISSUES.md` — remove the entire "Test Suite Failures" block**

The current block at lines 3–8:

```
## Current Issues

### Test Suite Failures (In Progress)
**Status**: 🚧 38 tests failing - systematic repair in progress  
**Tracking**: See [Test Fix Plan](TEST_FIX_PLAN.md) for detailed progress  
**Temporary Note**: This will be removed once all tests pass

## Resolved Issues
```

Replace with:

```
## Resolved Issues
```

(Removes the entire `## Current Issues` section because there are no other current issues. If a different live issue has been added in the meantime, leave the `## Current Issues` heading and remove only the `### Test Suite Failures` subsection plus its three lines.)

Verify with:

```bash
grep -n 'TEST_FIX\|Test Suite Failures' docs/KNOWN_ISSUES.md
```

Expected: no output.

- [ ] **Step 4: Re-run the suite (sanity)**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: identical to baseline.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs(#76): remove dangling TEST_FIX_PLAN.md references

The referenced docs/TEST_FIX_PLAN.md does not exist. Removes:
- CLAUDE.md "Test Suite" status line (line 48)
- docs/KNOWN_ISSUES.md "Test Suite Failures (In Progress)" block

Real test-suite cleanup tracked by issue #76 prerequisite spec at
docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md.

Coordinates with #81 (prune-root-clutter): different sections of CLAUDE.md,
no textual conflict.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Push PR-A and open the pull request

**Files:** None modified.

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/issue-76-test-cleanup-mechanical
```

Expected: branch pushed; PR URL suggestion in stderr.

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "chore(#76): mechanical test-suite cleanup (PR-A of 2)" --body "$(cat <<'EOF'
## Summary

Mechanical cleanup of `tests/testthat/` and orphan test docs. Pure deletion of provably-dead artifacts, no judgment calls. Prerequisite to issue #76 (CI rebuild).

This is **PR-A of 2**. PR-B (audit-driven cleanup, branched off main after this merges) handles the per-file audits.

## What's deleted

**`tests/testthat/`:**
- `test-SaisonSimulierenCPP.R.bak` (`.bak` files don't belong in VCS)
- `temp/`, `_snaps/`, `test-schedulers/`, `test-shiny/` (empty directories)
- `tests/` (accidental `tests/testthat/tests/testthat/` nesting)

**`docs/`:**
- `TEST_SUMMARY.md`, `TEST_ORGANIZATION.md`, `TEST_SUITE_FINAL.md`, `TEST_SIMPLIFICATION_PLAN.md` — describe the pre-cleanup 8-phase deployment-safety test infrastructure that no longer exists.

## What's modified

- `CLAUDE.md` line 48 — drop the "Test Suite" status line that points to the missing `docs/TEST_FIX_PLAN.md`.
- `docs/KNOWN_ISSUES.md` — drop the "Test Suite Failures (In Progress)" block (also points to the missing file).

## Coordination with #81

Both this PR and #81 (`prune-root-clutter`) edit `CLAUDE.md`. Different sections — #81 modifies `## Quick Commands`, this PR drops a line in `## Current Status`. No textual conflict.

## Verification

`Rscript -e 'testthat::test_dir("tests/testthat")'` produces identical pass/fail/skip counts as `main`.

## Test plan

- [ ] CI run is green (or "no CI" — issue #76 is the rebuild)
- [ ] `git diff main..HEAD --stat` shows only deletions and the two doc edits
- [ ] No surviving file in `tests/testthat/` or `docs/` references any deleted path

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed.

- [ ] **Step 3: Mark PR-A done; wait for merge before starting PR-B**

PR-B branches off `main` (not this PR). It cannot start until PR-A merges.

---

## PR-B: Audit-Driven Cleanup

### Task 5: Worktree + baseline capture for PR-B

**Goal:** Create the PR-B worktree off the post-PR-A `main` and capture a fresh baseline.

**Files:** None modified.

- [ ] **Step 1: Confirm PR-A has merged to main**

From the original checkout:

```bash
git fetch origin
git log origin/main --oneline -10
```

Expected: top of the log shows the PR-A merge commit.

- [ ] **Step 2: Create the PR-B worktree**

```bash
git worktree add ../League-Simulator-Update.issue-76-audit -b feature/issue-76-test-cleanup-audit origin/main
cd ../League-Simulator-Update.issue-76-audit
git status --short
git branch --show-current
```

Expected: empty status; branch `feature/issue-76-test-cleanup-audit`.

Confirm PR-A's deletions are present:

```bash
ls tests/testthat/test-SaisonSimulierenCPP.R.bak 2>&1 | grep -q 'No such' && echo "PR-A merged OK"
```

Expected: `PR-A merged OK`.

- [ ] **Step 3: Capture fresh baseline**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tee /tmp/baseline-suite-prb.txt
grep -E '^\[ FAIL' /tmp/baseline-suite-prb.txt | tail -1
```

Expected: the summary line. Record it. Every audit step compares against this.

(No commit at the end of Task 5.)

---

### Task 6: Phase 1 — Write the verdict table

**Goal:** Decide every audit verdict before any deletion lands. Reviewers see the plan before the diffs.

**Files:**
- Create: `docs/superpowers/notes/test-suite-audit-2026-05-02.md`

- [ ] **Step 1: Inventory every remaining file in `tests/testthat/`**

```bash
mkdir -p docs/superpowers/notes
find tests/testthat -type f -name '*.R' | sort
echo "---directories---"
find tests/testthat -type d | sort
echo "---fixtures---"
find tests/testthat/fixtures -type f 2>/dev/null | sort
```

Record the output. Every file that appears here needs a verdict in the next step.

- [ ] **Step 2: Audit each file by reading it and classifying**

For every file from Step 1's output, open it and classify into one of:

- **keep-firm** — protects the production loop or season-transition workflow with no overlap. Justify by naming the production code path.
- **keep-pending-cpp-audit** — only `test-SpielCPP.R`, `test-simulationsCPP.R`, `test-SaisonSimulierenCPP.R` (resolved in Task 7).
- **delete** — references deleted code, mocks reality without exercising it, or duplicates a kept test. Justify by naming what makes it dead.
- **port** — contains 1–2 tests that protect a real surviving code path nothing else covers; rest of file is delete-worthy. Justify by naming which tests to port and where.

The keep-firm initial set (these may NOT be re-classified without explicit justification):

- `test-rust-required.R` (production loop ↔ Rust contract)
- `test-prozent.R` (`RCode/prozent.R` math)
- `test-Tabelle.R` (table/standings logic, both workflows)
- `test-SpielNichtSimulieren.R` (only test that exercises `RCode/SpielNichtSimulieren.cpp` directly)
- `test-season-processor.R`, `test-season-validation.R`, `test-season-transition-regression.R`, `test-team-count-validation.R`, `test-interactive-prompts.R`, `test-transform_data.R` (season-transition operator workflow)

- [ ] **Step 3: Write the verdict table**

Create `docs/superpowers/notes/test-suite-audit-2026-05-02.md` with this structure:

```markdown
# Test suite audit verdict table — 2026-05-02

Temporary working document for PR-B (issue #76 prerequisite). Deleted in
the final commit of PR-B; captured in the merged PR description for the
historical record.

## Verdicts

| Path | Verdict | Justification |
|---|---|---|
| tests/testthat/test-rust-required.R | keep-firm | Production loop ↔ Rust contract (#83) |
| tests/testthat/test-prozent.R | keep-firm | RCode/prozent.R math |
| tests/testthat/test-Tabelle.R | keep-firm | Table/standings logic (both workflows) |
| tests/testthat/test-SpielNichtSimulieren.R | keep-firm | Only test exercising RCode/SpielNichtSimulieren.cpp directly |
| tests/testthat/test-season-processor.R | keep-firm | Season-transition: per-season processing |
| tests/testthat/test-season-validation.R | keep-firm | Season-transition: input validation |
| tests/testthat/test-season-transition-regression.R | keep-firm | Season-transition: end-to-end CSV contract |
| tests/testthat/test-team-count-validation.R | keep-firm | Season-transition: team-count rules |
| tests/testthat/test-interactive-prompts.R | keep-firm | Season-transition: input handling |
| tests/testthat/test-transform_data.R | keep-firm | Season-transition: data transformation |
| tests/testthat/test-SpielCPP.R | keep-pending-cpp-audit | Resolved in Task 7 |
| tests/testthat/test-simulationsCPP.R | keep-pending-cpp-audit | Resolved in Task 7 |
| tests/testthat/test-SaisonSimulierenCPP.R | keep-pending-cpp-audit | Resolved in Task 7 |
| tests/testthat/test-deployment.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/helper-deployment.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/test-simple-integration.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/test-integration-e2e.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/test-e2e-simulation-workflow.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/test-elo-basic.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/test-edge-cases/test-extreme-scenarios.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/test-api/test-api-errors.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/test-helpers/api-mock-fixtures.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/test-helpers/elo-mock-generator.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/test-helpers/season-transition-mocks.R | <FILL IN> | <FILL IN after reading> |
| tests/testthat/helper-fixtures.R | (decided in Phase 4) | Dependency-driven |
| tests/testthat/helper-performance-baseline.R | (decided in Phase 4) | Dependency-driven |
| tests/testthat/helper-test-setup.R | (decided in Phase 4) | Dependency-driven |
| tests/testthat/fixtures/api-responses/* | (decided per-fixture during audit) | Keep iff a kept test references it |
| tests/testthat/fixtures/rust-required/* | keep | Referenced by test-rust-required.R |
| tests/testthat/fixtures/test-data/* | (decided per-fixture during audit) | Keep iff a kept test references it |

## Audit method

For each <FILL IN>, the worker opens the file, reads its `test_that()` blocks,
and writes the verdict + a one-sentence justification. The justification must
name either (a) the deleted code path the test references, (b) the kept test
that already covers the same concern, or (c) the surviving code path that the
test protects (in which case it's a port candidate, not a delete).
```

Replace every `<FILL IN>` after auditing the file. The worker MUST NOT skip files; if a verdict is ambiguous, write `delete` and add the ambiguity to the justification — the goal is a complete table.

- [ ] **Step 4: Verify the verdict table covers every file**

```bash
# Every file under tests/testthat/ should appear in the verdict table OR be a kept-firm file already on the table.
find tests/testthat -type f -name '*.R' | sort > /tmp/files-on-disk.txt
grep -oE 'tests/testthat/[^ ]*\.R' docs/superpowers/notes/test-suite-audit-2026-05-02.md | sort -u > /tmp/files-in-table.txt
diff /tmp/files-on-disk.txt /tmp/files-in-table.txt
```

Expected: no output (every file on disk is also in the verdict table). If files are missing, add their verdict before continuing.

- [ ] **Step 5: Commit the verdict table**

```bash
git add docs/superpowers/notes/test-suite-audit-2026-05-02.md
git commit -m "$(cat <<'EOF'
docs(#76): test suite audit verdict table

Temporary working document for PR-B. Lists every remaining file under
tests/testthat/ with a verdict (keep-firm | delete | port | resolved-later)
and one-sentence justification. Reviewers can disagree before deletions land.

This file is deleted in the final commit of PR-B; the table is captured in
the merged PR description for the historical record.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Phase 2 — CPP audit (mutation test)

**Goal:** Decide whether `test-season-transition-regression.R` catches a behavior change in `RCode/SpielCPP.R`. If yes: delete the three CPP wrapper tests outright. If no: write a TDD test that catches the mutation, then delete the three wrappers.

**Files:**
- Read-only: `RCode/SpielCPP.R` (mutated and reverted, never committed in mutated state)
- Possibly create: `tests/testthat/test-season-transition-cpp-contract.R`
- (Wrapper deletion happens in Task 8.)

- [ ] **Step 1: Locate the K-factor in `RCode/SpielCPP.R`**

```bash
grep -nE 'ModFaktor|kFactor|k_factor' RCode/SpielCPP.R
```

Expected: line 17 (signature default) — `ModFaktor = 20`.

If the value is something other than `20`, or if `ModFaktor` is no longer the K-factor name, halt and read the file end-to-end before mutating. The mutation only works if (a) it changes observable behavior and (b) it doesn't break the function signature.

- [ ] **Step 2: Confirm `test-season-transition-regression.R` passes against the unmodified code**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-regression.R")' 2>&1 | tail -20
```

Expected: zero failures.

If it fails on `main` already, that's a separate bug — record it, fix it (or skip the affected test_that blocks), then re-run before proceeding.

- [ ] **Step 3: Apply the K-factor mutation**

Use the Edit tool on `RCode/SpielCPP.R`:

Old (line 17):
```
                ModFaktor = 20, Heimvorteil = 65, 
```

New:
```
                ModFaktor = 10, Heimvorteil = 65, 
```

Verify:
```bash
grep -n 'ModFaktor = ' RCode/SpielCPP.R
```

Expected: `ModFaktor = 10` on line 17.

- [ ] **Step 4: Re-run the regression test against the mutated code**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-regression.R")' 2>&1 | tail -20
```

Two possible outcomes:
- **(A) The test fails** — `test-season-transition-regression.R` is sensitive enough. Skip Step 6.
- **(B) The test passes** — the regression test does not catch a 50% K-factor change. Proceed to Step 6.

Record which outcome you got — it goes in the commit message.

- [ ] **Step 5: Revert the mutation**

```bash
git checkout -- RCode/SpielCPP.R
grep -n 'ModFaktor = ' RCode/SpielCPP.R
```

Expected: `ModFaktor = 20` on line 17. The mutation is gone — confirm with `git diff RCode/SpielCPP.R` (must be empty).

- [ ] **Step 6: (Outcome B only) Write a TDD test that catches the mutation**

If Step 4 outcome was (A), skip to Step 7.

Create `tests/testthat/test-season-transition-cpp-contract.R`:

```r
# Phase 2 audit follow-up (issue #76):
# test-season-transition-regression.R does not catch K-factor changes in
# RCode/SpielCPP.R. This file pins the SpielCPP -> SpielNichtSimulieren contract
# at the level the production loop and season-transition both depend on:
# halving the K-factor (ModFaktor) must change the post-match ELO of both teams.

library(testthat)

source("../../RCode/SpielCPP.R")
source("../../RCode/cpp_wrappers.R")  # needed iff SpielCPP uses cpp_wrappers helpers
# Compile the cpp dependency once so SpielNichtSimulieren is callable.
Rcpp::sourceCpp("../../RCode/SpielNichtSimulieren.cpp")

test_that("SpielCPP K-factor of 20 produces a larger ELO change than K-factor of 10", {
  # Two equal teams, home wins 2-0. ELO change should be positive for home, negative for away.
  result_k20 <- SpielCPP(
    ELOHeim = 1500, ELOGast = 1500,
    ToreHeim = 2, ToreGast = 0,
    ZufallHeim = 0.5, ZufallGast = 0.5,
    ModFaktor = 20, Heimvorteil = 65,
    Simulieren = FALSE
  )
  result_k10 <- SpielCPP(
    ELOHeim = 1500, ELOGast = 1500,
    ToreHeim = 2, ToreGast = 0,
    ZufallHeim = 0.5, ZufallGast = 0.5,
    ModFaktor = 10, Heimvorteil = 65,
    Simulieren = FALSE
  )
  # The home team's ELO gain at K=20 must be roughly double that at K=10.
  delta_k20 <- result_k20[1] - 1500
  delta_k10 <- result_k10[1] - 1500
  expect_gt(delta_k20, delta_k10)
  expect_gt(delta_k20, 0)
  expect_gt(delta_k10, 0)
})
```

Adjust `source()` paths and the `result_k20[1]` index based on the actual return shape of `SpielCPP` (it returns a vector — index `[1]` is the home team's new ELO; verify this by reading `RCode/SpielCPP.R` and `RCode/SpielNichtSimulieren.cpp`).

- [ ] **Step 7: (Outcome B only) Run the new test — it must PASS against unmutated code**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-cpp-contract.R")' 2>&1 | tail -20
```

Expected: zero failures. (The test asserts that K=20 produces a larger ELO change than K=10 — true by construction.)

- [ ] **Step 8: (Outcome B only) Re-apply the mutation and confirm the new test FAILS**

This is the RED phase of TDD applied retroactively to validate the test catches the regression it was written for.

```bash
# Re-apply mutation on RCode/SpielCPP.R (ModFaktor = 20 -> ModFaktor = 10) using Edit.
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-cpp-contract.R")' 2>&1 | tail -20
```

Expected: at least one failure. (The test compares K=20 to K=10; if both calls now use the mutated default, the comparison is between explicit K=20 and explicit K=10 — it should still pass. Check whether the test exercises the *default*, not explicit K. Adjust to assert against the default if needed.)

If the test passes despite the mutation, the test is too weak. Rewrite it so that *changing the default ModFaktor in `RCode/SpielCPP.R` causes the test to fail*. Example: call `SpielCPP(...)` without specifying `ModFaktor`, then compare to a call that explicitly passes `ModFaktor = 20`.

- [ ] **Step 9: (Outcome B only) Revert the mutation, re-confirm the test passes**

```bash
git checkout -- RCode/SpielCPP.R
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-cpp-contract.R")' 2>&1 | tail -20
```

Expected: zero failures.

- [ ] **Step 10: Run the full suite (sanity)**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: same pass count as PR-B baseline, OR baseline + the count of test_that blocks in the new contract test (if Outcome B).

- [ ] **Step 11: Commit the audit result**

If Outcome A (no new test):

```bash
git commit --allow-empty -m "$(cat <<'EOF'
test(#76): CPP audit — regression test catches SpielCPP.R changes

Mutation: RCode/SpielCPP.R line 17 default ModFaktor 20 -> 10 (halved K-factor).
Result: tests/testthat/test-season-transition-regression.R FAILED with the
mutation applied. The regression test is sensitive enough to catch K-factor
changes; no new contract test needed.

Mutation reverted; no source changes in this commit. Empty commit records
the audit decision in git history.

Phase 2 of PR-B per docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If Outcome B (new test added):

```bash
git add tests/testthat/test-season-transition-cpp-contract.R
git commit -m "$(cat <<'EOF'
test(#76): CPP audit — add SpielCPP K-factor contract test

Mutation: RCode/SpielCPP.R line 17 default ModFaktor 20 -> 10 (halved K-factor).
Result: tests/testthat/test-season-transition-regression.R PASSED with the
mutation applied — too coarse. Adds test-season-transition-cpp-contract.R
which compares ELO deltas at the default K vs. an explicit K, making the
default value load-bearing and protected.

TDD: test passes against unmutated code, fails against mutated code, passes
again after revert.

Phase 2 of PR-B per docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Delete the three CPP wrapper tests

**Files:**
- Delete: `tests/testthat/test-SpielCPP.R`
- Delete: `tests/testthat/test-simulationsCPP.R`
- Delete: `tests/testthat/test-SaisonSimulierenCPP.R`

- [ ] **Step 1: Confirm the three files exist**

```bash
ls tests/testthat/test-SpielCPP.R tests/testthat/test-simulationsCPP.R tests/testthat/test-SaisonSimulierenCPP.R
```

Expected: all three listed.

- [ ] **Step 2: Confirm `test-SpielNichtSimulieren.R` survives**

```bash
ls tests/testthat/test-SpielNichtSimulieren.R
```

Expected: file exists. (This is the only `.cpp`-targeting test we keep.)

- [ ] **Step 3: Delete the three files**

```bash
git rm tests/testthat/test-SpielCPP.R tests/testthat/test-simulationsCPP.R tests/testthat/test-SaisonSimulierenCPP.R
```

Expected: three `rm '...'` lines.

- [ ] **Step 4: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures. Pass count = (PR-B baseline) − (test_that blocks in the three deleted files) + (1 if Outcome B added a new test).

If failures appear, something in the kept tests *depended on* the deleted CPP wrapper tests (e.g., shared setup). Investigate before continuing.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): delete redundant CPP wrapper tests

Phase 2 of PR-B. The Rust test suite (~20 tests in league-simulator-rust/)
covers every conceptual edge case these R wrappers tested:
- ELO deltas: elo/tests.rs (R-parity, conservation, draw, underdog, home advantage, goal diff)
- Season simulation: simulation/tests.rs::test_season_simulation
- Monte Carlo: monte_carlo/tests.rs (5 tests, incl. parallel + adjustments)
- Determinism: simulation/tests.rs::test_deterministic_simulation
- Poisson quantile: simulation/tests.rs::test_poisson_quantile

The CPP path's only remaining live consumer (scripts/season_transition.R
sourcing SpielCPP.R) is protected by test-season-transition-regression.R
(plus test-season-transition-cpp-contract.R if Phase 2 added it).

Deleted:
- tests/testthat/test-SpielCPP.R
- tests/testthat/test-simulationsCPP.R
- tests/testthat/test-SaisonSimulierenCPP.R

Kept:
- tests/testthat/test-SpielNichtSimulieren.R (only test exercising the .cpp directly)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Phase 3 — Audit and delete `test-deployment.R` + `helper-deployment.R`

**Files:**
- Read: `tests/testthat/test-deployment.R`, `tests/testthat/helper-deployment.R`
- Delete (default): both files

- [ ] **Step 1: Read both files end to end**

```bash
wc -l tests/testthat/test-deployment.R tests/testthat/helper-deployment.R
```

Then open each with the Read tool and skim every `test_that()` block.

For each `test_that()` block, ask: "does this protect a code path that the production loop or season-transition workflow exercises *and* that no kept-firm test already covers?" The default answer is no — these tests target the deleted k8s/microservices stack.

- [ ] **Step 2: Decide verdict for each file and update the verdict table**

Update `docs/superpowers/notes/test-suite-audit-2026-05-02.md` with the verdict and justification for both files.

The expected verdict for both is `delete`. If you find a single test_that block that protects a real surviving code path, switch that file's verdict to `port` and identify which kept-firm file receives the ported test. (Porting work is in Step 5.)

- [ ] **Step 3: (default path — delete) Remove both files**

```bash
git rm tests/testthat/test-deployment.R tests/testthat/helper-deployment.R
```

Expected: two `rm '...'` lines.

- [ ] **Step 4: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures. Pass count = previous count − (test_that blocks in the deleted files).

- [ ] **Step 5: (port path only) Move the surviving tests**

If a test was worth porting:

1. Identify the destination kept-firm file (e.g., `test-season-validation.R`).
2. Use the Edit tool to add the test_that block to the destination file. Use TDD: pick a mutation in the production code that the test should catch, apply it, run the test (must FAIL), revert mutation, run the test (must PASS).
3. Re-run the full suite — must stay green.
4. Then delete the source files as in Step 3.

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): delete test-deployment.R + helper-deployment.R — k8s configmap world

Phase 3 of PR-B audit. Both files target the deleted k8s/microservices
deployment surface (configmaps, multi-Dockerfile variants, deployment-stage
testing). The surviving deployment is one Dockerfile + docker-compose +
docker-start.sh, exercised by the production loop tests.

No tests ported — no surviving code path was covered only by these files.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

(If tests were ported, the commit message reflects which tests went where and the TDD evidence.)

---

### Task 10: Audit and delete `test-simple-integration.R`

**Files:**
- Read: `tests/testthat/test-simple-integration.R`
- Delete (default): the file

- [ ] **Step 1: Read the file**

Open with the Read tool. The file targets the deleted `update_all_leagues_loop_simple` path (collapsed in PR #80, issue #78). The default verdict is `delete`.

- [ ] **Step 2: Update the verdict table**

Record the verdict and justification.

- [ ] **Step 3: Delete the file (default) or port + delete**

```bash
git rm tests/testthat/test-simple-integration.R
```

(If a port is needed, follow Task 9 Step 5's pattern.)

- [ ] **Step 4: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): delete test-simple-integration.R — deleted simple-monolithic loop

Phase 3 of PR-B audit. Targets update_all_leagues_loop_simple, which was
collapsed in PR #80 (issue #78 deployment surface collapse). Production loop
coverage is in test-rust-required.R.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Audit and delete `test-integration-e2e.R`

**Files:**
- Read: `tests/testthat/test-integration-e2e.R`
- Delete (default): the file

- [ ] **Step 1: Read the file**

Open with the Read tool. Look for two failure modes: (a) does it test the deleted simple/microservices stack? (b) does it mock the engine and the API to such a degree that it doesn't exercise real code?

- [ ] **Step 2: Update the verdict table** with verdict + justification.

- [ ] **Step 3: Delete the file (default) or port + delete**

```bash
git rm tests/testthat/test-integration-e2e.R
```

- [ ] **Step 4: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): delete test-integration-e2e.R — <one-line audit verdict>

<2-3 sentences naming what the file targeted and why nothing surviving needs
the coverage.>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

(Replace `<...>` with the verdict from the audit.)

---

### Task 12: Audit and delete `test-e2e-simulation-workflow.R`

**Files:**
- Read: `tests/testthat/test-e2e-simulation-workflow.R`
- Delete (default): the file

- [ ] **Step 1: Read the file**

Known signal from initial exploration: this file contains comments like `# In real test, this would call leagueSimulatorCPP` — i.e., it is a mock, not an actual integration test. Default verdict: `delete`.

- [ ] **Step 2: Update the verdict table** with verdict + justification.

- [ ] **Step 3: Delete the file**

```bash
git rm tests/testthat/test-e2e-simulation-workflow.R
```

- [ ] **Step 4: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): delete test-e2e-simulation-workflow.R — mock, not integration

Phase 3 of PR-B audit. The file is a mock that re-implements the
simulation flow in R rather than exercising the production engine
(comments like 'In real test, this would call leagueSimulatorCPP').
Real production-loop coverage lives in test-rust-required.R, which
exercises the actual Rust HTTP API.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Audit and delete `test-elo-basic.R`

**Files:**
- Read: `tests/testthat/test-elo-basic.R`
- Delete (default): the file

- [ ] **Step 1: Read the file**

Known signal from initial exploration: this file is a mock-heavy hand-rolled ELO re-implementation in R, not a test of the real engine. Default verdict: `delete` — `RCode/SpielNichtSimulieren.cpp` is exercised by `test-SpielNichtSimulieren.R`, and the Rust suite covers the engine's behavior end-to-end.

- [ ] **Step 2: Update the verdict table** with verdict + justification.

- [ ] **Step 3: Delete the file**

```bash
git rm tests/testthat/test-elo-basic.R
```

- [ ] **Step 4: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): delete test-elo-basic.R — mock ELO re-implementation in R

Phase 3 of PR-B audit. The file re-implements ELO math in R for testing
purposes, mocking the real engine. Real ELO coverage:
- test-SpielNichtSimulieren.R (the .cpp directly)
- league-simulator-rust/src/elo/tests.rs (R-parity + conservation + edge cases)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Audit and delete `test-edge-cases/test-extreme-scenarios.R`

**Files:**
- Read: `tests/testthat/test-edge-cases/test-extreme-scenarios.R`
- Delete or port: the file
- Possibly delete: the empty `test-edge-cases/` directory

- [ ] **Step 1: Read the file**

Look for edge cases that protect surviving code paths. Examples worth porting: an extreme-ELO test that catches an overflow in `RCode/Tabelle.R`. Examples to delete: anything that tests the deleted simple/microservices stack or anything covered by Rust's `elo/tests.rs`.

- [ ] **Step 2: Update the verdict table** with verdict + justification per surviving test_that block.

- [ ] **Step 3: (port path) Move surviving tests with TDD**

For each ported test:

1. Pick the destination kept-firm file (likely `test-Tabelle.R` or `test-SpielNichtSimulieren.R`).
2. Edit the destination file to add the test_that block.
3. RED: pick a small mutation in the production code that the test should catch (e.g., flip a comparison operator in `RCode/Tabelle.R`). Run the test — it MUST FAIL.
4. Revert the mutation. Run the test — it MUST PASS.
5. Record the mutation choice + RED/GREEN evidence in the commit message.

- [ ] **Step 4: Delete the file**

```bash
git rm tests/testthat/test-edge-cases/test-extreme-scenarios.R
# Then remove the empty directory if no other files remain.
rmdir tests/testthat/test-edge-cases 2>/dev/null && git add -A tests/testthat/test-edge-cases || true
```

- [ ] **Step 5: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures.

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): delete test-edge-cases/test-extreme-scenarios.R — <verdict>

<2-3 sentences: which tests were deleted, which were ported (if any), where
they went, and the RED/GREEN mutation evidence for each port.>

Phase 3 of PR-B audit per docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: Audit and delete `test-api/test-api-errors.R`

**Files:**
- Read: `tests/testthat/test-api/test-api-errors.R`
- Decide: keep + move to `tests/testthat/test-api-errors.R` (flatten), port, or delete
- Possibly delete: the empty `test-api/` directory

- [ ] **Step 1: Read the file**

This is the only file in `test-api/`. It likely tests `RCode/api_service.R` and `RCode/api_helpers.R` error handling — both are sourced by `scripts/season_transition.R` (the season-transition workflow we're protecting).

If the tests exercise real error-handling logic in surviving code: **keep**, but move the file to `tests/testthat/` (flatten the directory — there's no need for a one-file subdirectory) and add the moved file's verdict to the keep-firm list.

If the tests mock the API entirely without exercising real code: **delete**.

- [ ] **Step 2: Update the verdict table** with verdict + justification.

- [ ] **Step 3: (keep path — recommended if real) Flatten the directory**

```bash
git mv tests/testthat/test-api/test-api-errors.R tests/testthat/test-api-errors.R
rmdir tests/testthat/test-api
```

- [ ] **Step 4: (delete path) Delete the file and empty directory**

```bash
git rm tests/testthat/test-api/test-api-errors.R
rmdir tests/testthat/test-api
```

- [ ] **Step 5: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures (path move) or zero failures with reduced count (delete path).

- [ ] **Step 6: Commit**

For the keep-and-flatten path:

```bash
git commit -m "$(cat <<'EOF'
test(#76): flatten test-api/ — keep test-api-errors.R for season-transition

Phase 3 of PR-B audit. test-api-errors.R exercises real error handling in
RCode/api_service.R and RCode/api_helpers.R, both consumed by
scripts/season_transition.R. Moved to tests/testthat/ root and removed the
one-file subdirectory.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

For the delete path, write a commit message naming the specific reason the tests were judged dead.

---

### Task 16: Audit `test-helpers/` (3 mock files)

**Files:**
- Read: `tests/testthat/test-helpers/api-mock-fixtures.R`, `tests/testthat/test-helpers/elo-mock-generator.R`, `tests/testthat/test-helpers/season-transition-mocks.R`
- Decide each: keep (move to root or to `helper-*.R`) or delete
- Possibly delete: the empty `test-helpers/` directory

- [ ] **Step 1: Find every reference to these files from kept-firm tests**

```bash
grep -rln 'api-mock-fixtures\|elo-mock-generator\|season-transition-mocks' tests/testthat 2>/dev/null
```

Record which kept-firm tests reference any of the three. A reference means the helper is alive and must survive (or be inlined into the test).

- [ ] **Step 2: Read each file**

Open each. Even if `find -name '*.R'` and the grep above show no references, testthat auto-sources `helper-*.R` (note: these are NOT named `helper-*.R`; they're under `test-helpers/`, which testthat does NOT auto-source unless explicitly loaded). Confirm whether anything `source()`s them.

```bash
grep -rn 'test-helpers' tests/testthat 2>/dev/null
```

Expected: a small number of explicit `source("test-helpers/...")` calls (or none).

- [ ] **Step 3: Update the verdict table** with one verdict per file:

- **delete** (default): the file is unreferenced by any kept-firm test.
- **keep + rename**: the file IS referenced. Move it to `tests/testthat/helper-<name>.R` so testthat auto-sources it; remove the explicit `source()` calls from the dependent tests.

- [ ] **Step 4: Apply the verdicts**

For deletes:
```bash
git rm tests/testthat/test-helpers/<file>.R
```

For keep + rename:
```bash
git mv tests/testthat/test-helpers/<file>.R tests/testthat/helper-<file>.R
# Then Edit each dependent test file to remove the now-redundant source() call.
```

If all three are deleted:
```bash
rmdir tests/testthat/test-helpers
```

- [ ] **Step 5: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures.

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): audit test-helpers/ — <verdict summary>

<3-5 lines naming which helpers were deleted (and why nothing referenced
them) vs. which were kept and renamed to helper-*.R for auto-sourcing.>

Phase 3 of PR-B audit per docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: Audit `tests/testthat/fixtures/` (per-fixture)

**Files:**
- Read: every file under `tests/testthat/fixtures/api-responses/`, `tests/testthat/fixtures/rust-required/`, `tests/testthat/fixtures/test-data/`
- Delete: each fixture not referenced by a surviving test

- [ ] **Step 1: List every fixture**

```bash
find tests/testthat/fixtures -type f | sort
```

Record the full list.

- [ ] **Step 2: For each fixture, find referencing tests**

```bash
for f in $(find tests/testthat/fixtures -type f); do
  base=$(basename "$f")
  refs=$(grep -rln "$base" tests/testthat 2>/dev/null | grep -v "^$f$" | head -3)
  if [ -z "$refs" ]; then
    echo "ORPHAN: $f"
  else
    echo "USED:   $f -> $refs"
  fi
done
```

Record each fixture as `USED` or `ORPHAN`.

- [ ] **Step 3: Update the verdict table** with one row per fixture (or per fixture-subdir if uniformly orphaned).

- [ ] **Step 4: Delete orphan fixtures**

```bash
# For each ORPHAN line above:
git rm <path>
# Then if a subdirectory becomes empty:
rmdir tests/testthat/fixtures/<subdir> 2>/dev/null || true
```

- [ ] **Step 5: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures (orphan fixtures had no consumers, so deletion is safe).

If a test fails because a fixture it actually needed was marked orphan, the grep in Step 2 was wrong — investigate the test's loading path (it may build the fixture path dynamically, e.g., `file.path("fixtures", paste0(name, ".json"))`). Restore the fixture and refine the verdict.

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): prune orphan fixtures from tests/testthat/fixtures/

Phase 3 of PR-B audit. Removes <N> fixture files that no surviving test
references. fixtures/rust-required/ kept (referenced by test-rust-required.R).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 18: Phase 4 — Helper prune

**Goal:** Delete every `helper-*.R` (or function within one) that no surviving test depends on.

**Files:**
- Read: `tests/testthat/helper-fixtures.R`, `tests/testthat/helper-performance-baseline.R`, `tests/testthat/helper-test-setup.R`, plus any helpers added in Task 16
- Delete or trim: any helper not referenced by a kept test

- [ ] **Step 1: List every function/object defined in each helper**

```bash
for h in tests/testthat/helper-*.R; do
  echo "=== $h ==="
  grep -nE '^[a-zA-Z_][a-zA-Z0-9_.]* *(<-|=) *function' "$h"
  grep -nE '^setup\(|^teardown\(' "$h"
done
```

Record the function names per helper.

- [ ] **Step 2: For each function, find referencing tests**

```bash
# Replace <fname> with each function name from Step 1.
grep -rln '<fname>' tests/testthat --include='test-*.R' 2>/dev/null
```

A function is **used** if any kept test (after Tasks 6–17) references it. A function is **dead** if no kept test does.

Special case: `setup()` and `teardown()` blocks at the top level of a helper auto-execute on load. They're "used" iff their side effects are needed by a kept test. Verify by reading the body and checking what they touch.

- [ ] **Step 3: Update the verdict table** with one row per helper (and per function for partially-used helpers).

- [ ] **Step 4: Delete fully-dead helpers**

```bash
# For each helper where all functions are dead and no setup()/teardown() side effects matter:
git rm tests/testthat/<helper>.R
```

For partially-used helpers, use the Edit tool to delete only the dead functions; keep the live ones.

- [ ] **Step 5: Run the suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures. If a kept test fails because of a deleted helper function or side effect, the grep in Step 2 missed a reference (e.g., the function is called via `do.call()` or a string-built name). Restore the helper, refine the verdict, retry.

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): prune unused helpers (Phase 4)

After freezing the keep set in Phases 1-3, each helper-*.R was checked
for actual dependency by a surviving test. Deletes:
- <helper-foo.R> — no surviving test calls <fn1>(), <fn2>()
- <helper-bar.R> — no surviving test triggers its setup() side effects
Trims:
- <helper-baz.R> — keeps <fn1>(), removes <fn2>(), <fn3>()

Suite remains green.

Phase 4 of PR-B per docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 19: Phase 5 — Final verification + delete the verdict table

**Goal:** Run the full suite, the sandboxed season-transition smoke test, and `docker build`. Delete the temporary verdict table.

**Files:**
- Delete: `docs/superpowers/notes/test-suite-audit-2026-05-02.md`

- [ ] **Step 1: Run the full suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tee /tmp/final-suite.txt
grep -E '^\[ FAIL' /tmp/final-suite.txt
```

Expected: zero failures, zero unexpected skips. Record the final pass count.

- [ ] **Step 2: Run the sandboxed season-transition smoke test**

If `RAPIDAPI_KEY` is not set in your environment, **skip this step** and record `smoke=skipped (no API key)` in the Phase 5 commit message. Per `docs/KNOWN_ISSUES.md`, season-transition without a valid key produces a no-op (existing ELO values pass through unchanged), which silently exits 0 — that does NOT satisfy the smoke gate.

If `RAPIDAPI_KEY` is set:

```bash
# (1) Snapshot any tracked-but-dirty or untracked CSVs under RCode/.
git stash push --include-untracked -m "season-transition smoke test snapshot" -- RCode/

# (2) Run season-transition non-interactively. Capture exit code and full output.
Rscript scripts/season_transition.R 2024 2025 --non-interactive 2>&1 | tee /tmp/smoke-output.txt
ST_EXIT=${PIPESTATUS[0]}
echo "Exit code: $ST_EXIT"

# (3) Restore the snapshot. If the stash was empty (no snapshot taken), that's fine.
git stash pop 2>/dev/null || true

# (4) Verify no tracked file is dirty after restore.
git status --porcelain RCode/

# (5) Verify the script reported actual ELO updates (not a no-op).
grep -E 'ELO change:.*[+-][1-9]' /tmp/smoke-output.txt | head -5
```

Pass criteria:
- `ST_EXIT == 0`
- Step 4 produces no output (RCode/ is clean)
- Step 5 shows at least one ELO change line with a non-zero delta (proves the workflow ran, not a no-op)

If any criterion fails: **do not** proceed. Either fix the cause or record the failure mode in the commit message and abort PR-B for human review.

- [ ] **Step 3: Run `docker build` (sanity)**

```bash
docker build -t league-simulator:test . 2>&1 | tail -20
echo "Exit: $?"
```

Expected: exit 0. Confirms no test-only file was being COPY'd into the image (it shouldn't be, but `docker build` is the authoritative check).

- [ ] **Step 4: Delete the verdict table**

```bash
git rm docs/superpowers/notes/test-suite-audit-2026-05-02.md
```

(The verdict table will be captured in the PR description in the next task.)

- [ ] **Step 5: Re-run the suite (sanity)**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | grep -E '^\[ FAIL'
```

Expected: zero failures.

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(#76): final verification — suite green, smoke test <ran|skipped>, image builds

Phase 5 of PR-B.

Test suite: <PASS_COUNT> tests, 0 failures, <N> skips (all expected).

Season-transition smoke test: smoke=ran|skipped (no API key)
- (if ran) Exit code: 0; RCode/ clean after stash pop; observed ELO changes:
  <paste 1-2 lines of "ELO change:" output>
- (if skipped) RAPIDAPI_KEY not set; per KNOWN_ISSUES.md, no-op runs would
  silently pass — not exercised.

Docker build: exit 0.

Also deletes the temporary verdict table at
docs/superpowers/notes/test-suite-audit-2026-05-02.md (captured in the
PR description).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Replace `<PASS_COUNT>`, `<N>`, the smoke status, and the ELO change snippet with the real values from Steps 1–3.

---

### Task 20: Push PR-B and open the pull request

**Files:** None modified.

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/issue-76-test-cleanup-audit
```

- [ ] **Step 2: Capture the verdict table for the PR description**

The verdict table was deleted in Task 19. Recover it from the PR-B git history for the PR description:

```bash
git show feature/issue-76-test-cleanup-audit:docs/superpowers/notes/test-suite-audit-2026-05-02.md 2>/dev/null \
  || git log --all --diff-filter=D -- docs/superpowers/notes/test-suite-audit-2026-05-02.md --format=%H -1 \
     | xargs -I{} git show {}^:docs/superpowers/notes/test-suite-audit-2026-05-02.md
```

Save the output for the PR body.

- [ ] **Step 3: Open the PR**

```bash
gh pr create --title "test(#76): audit-driven test-suite cleanup (PR-B of 2)" --body "$(cat <<'EOF'
## Summary

Audit-driven cleanup of `tests/testthat/`, completing the prerequisite to issue #76's CI rebuild.

This is **PR-B of 2**. PR-A (mechanical cleanup, #<PR-A-NUMBER>) merged first.

## What changed

**Phase 2 — CPP audit:** Deleted `test-SpielCPP.R`, `test-simulationsCPP.R`, `test-SaisonSimulierenCPP.R`. Mutation evidence: <Outcome A: regression test caught the K-factor mutation> | <Outcome B: added `test-season-transition-cpp-contract.R` to close the gap>.

**Phase 3 — Per-file audit:** <list each file's verdict in 1-2 lines, linked to the verdict-table commit>.

**Phase 4 — Helper prune:** <list deleted/trimmed helpers>.

**Phase 5 — Final verification:**
- testthat: `<PASS_COUNT>` passing, 0 failures, `<N>` expected skips.
- Season-transition smoke test: `smoke=<ran|skipped>`. <If ran: confirmed non-noop with ELO change evidence.>
- `docker build`: exit 0.

## Verdict table

<paste the verdict table contents recovered from git history>

## Coordination

- #81 (`prune-root-clutter`): zero overlap.
- #76 (CI rebuild): this PR is the prerequisite. CI workflows untouched.

## Rollback

Each commit is independently revertable. To undo a single phase, revert that phase's commits (one per file or cohesive group). To undo the whole PR, revert the merge commit.

## Test plan

- [ ] `Rscript -e 'testthat::test_dir("tests/testthat")'` runs green
- [ ] `docker build .` succeeds
- [ ] `git diff main..HEAD --stat` shows only test/doc changes (no `RCode/`, `scripts/`, `Dockerfile`)
- [ ] No `tests/testthat/` file references a deleted helper or fixture

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Mark issue #76 prerequisites complete**

```bash
gh issue comment 76 --body "Prerequisite test-suite cleanup landed (PR-A #<A> + PR-B #<B>). The cleaned suite is now the foundation for the CI rebuild. Reopening this issue's scope to focus on CI workflow design."
```

- [ ] **Step 5: Clean up worktrees**

After both PRs merge:

```bash
cd /path/to/main/checkout
git worktree remove ../League-Simulator-Update.issue-76-mechanical
git worktree remove ../League-Simulator-Update.issue-76-audit
git fetch origin --prune
git branch -D feature/issue-76-test-cleanup-mechanical feature/issue-76-test-cleanup-audit 2>/dev/null || true
```

---

## Self-Review Notes (for the executing worker)

Before claiming the plan is done, verify each of these:

1. **Spec coverage.** Every section of `docs/superpowers/specs/2026-05-02-test-suite-cleanup-design.md` is implemented:
   - PR-A mechanical deletions → Tasks 1–3
   - PR-A `CLAUDE.md` + `KNOWN_ISSUES.md` edits → Task 3
   - PR-B verdict table → Task 6
   - PR-B CPP audit + mutation → Task 7
   - PR-B CPP wrapper deletion → Task 8
   - PR-B per-file deprecated-stack audit → Tasks 9–13
   - PR-B subdirectory audit → Tasks 14–16
   - PR-B fixtures audit → Task 17
   - PR-B helper prune → Task 18
   - PR-B final verification (suite + smoke + docker) → Task 19
   - PR-B verdict table deletion + capture in PR body → Tasks 19–20

2. **No placeholders that the worker is expected to fill in without an audit.** Several `<FILL IN>` markers exist in the verdict table; those are intentional — the audit is the work. Commit messages with `<verdict>` placeholders are filled in based on what the audit found, also intentional.

3. **Type/path consistency.**
   - `RCode/SpielCPP.R` line 17 default `ModFaktor = 20` — confirmed.
   - `RCode/SpielNichtSimulieren.cpp` — sourced from `RCode/`, confirmed.
   - `tests/testthat/fixtures/rust-required/` — referenced by `test-rust-required.R`, confirmed.
   - `scripts/season_transition.R` — exists, confirmed.

4. **TDD discipline.** Strict TDD applies to:
   - Task 7 (Outcome B) — new contract test goes RED → GREEN
   - Task 9 / 10 / 11 / 14 (port path) — every ported test goes RED → GREEN
   - Tasks where the default is "delete" do NOT require TDD; deletion is justified by the audit, not by a failing test.
