# Prune Root Clutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove 11 stale/tracked files and 3 untracked files from the repo root (saving ~1.5 MB tracked + working-tree clutter), fold the three unique commands from `docs/COMMANDS.md` into `CLAUDE.md`, and add gitignore patterns to prevent regression.

**Architecture:** Pure deletion + small documentation merge. Branch off `main` to `feature/issue-81-prune-root-clutter`. Four commits, one per logical group: (1) stale-architecture artifacts, (2) analysis dumps, (3) build logs + untracked-clutter move + `.gitignore`, (4) `docs/COMMANDS.md` consolidation into `CLAUDE.md`. Zero touches to `RCode/`, `scripts/`, `Dockerfile`, `docker-compose.yml`, `tests/testthat/`, or `.github/workflows/` — preserves merge-parallelism with PR #83 (#77) and the future #76 CI rebuild.

**Tech Stack:** git, plain shell. No code changes. No tests added (this is repo hygiene; verification is via `git ls-files`, `grep`, and `git status`).

**Reference spec:** `docs/superpowers/specs/2026-05-02-prune-root-clutter-design.md`

---

## File Inventory

### Files deleted (`git rm`) — 11 tracked files

| File | Bucket |
|---|---|
| `PRD_ISSUE_1_monolithic_deployment.md` | Stale-architecture artifact |
| `EOD_SUMMARY.md` | Stale-architecture artifact |
| `.github/issues/issue-31.md` | Stale-architecture artifact |
| `DEPENDENCY_ANALYSIS.md` | Analysis dump |
| `FUNCTION_ANALYSIS.md` | Analysis dump |
| `RUST_INTEGRATION.md` | Analysis dump |
| `test_failure_analysis.md` | Analysis dump |
| `TEST_RESULTS_SUMMARY.md` | Analysis dump |
| `api_documentation.md` | Analysis dump |
| `build.log` | Build log (also gets gitignored) |
| `build2.log` | Build log (also gets gitignored) |

### Files moved to `removed/` — 3 untracked files

| File | Currently gitignored? |
|---|---|
| `MATCH_PROCESSING_ANALYSIS.md` | yes |
| `RUST_RNG_FIX_RESULTS.md` | yes |
| `UNIT_TEST_SUMMARY.md` | yes |

### Files modified

| File | Change |
|---|---|
| `.gitignore` | Add `build.log`, `build2.log`, `removed/` |
| `CLAUDE.md` | Add three command blocks (single-file test, install deps, run Shiny); remove `@docs/COMMANDS.md` reference; remove `## Documentation` and `## Note on Documentation` sections (memory entry "CLAUDE.md trim after #75" — naturally folds in here) |
| `docs/README.md` | Drop the `[Commands Reference](COMMANDS.md)` quick-link |

### File deleted (consolidation)

| File | Why |
|---|---|
| `docs/COMMANDS.md` | Three unique blocks folded into `CLAUDE.md`; rest duplicates `CLAUDE.md` Quick Commands, `docs/deployment/quick-start.md`, or `docs/user-guide/season-transition.md` |

### Files explicitly NOT touched

`RCode/*`, `scripts/*`, `Dockerfile`, `docker-compose.yml`, `docker-start.sh`, `tests/testthat/*`, `.github/workflows/*`, `docs/architecture/*`, `docs/deployment/*` (other than reading `quick-start.md` for context), `docs/operations/*`, `docs/troubleshooting/*`, `docs/user-guide/*`, root-level R scripts (`compare_*.R`, `debug_*.R`, `elv_*.R`, `test_api_connection.R`, `test_elo_fix.R`, `run_single_update_2025.R`).

---

## Task 1: Pre-flight verification + worktree baseline

**Goal:** Verify all 14 target files exist with the expected sizes/tracked-status; confirm we're on a clean `main`; create the working branch. Catches state drift before any deletions.

**Files:**
- Read-only verification

- [ ] **Step 1: Confirm clean working tree on main**

```bash
git status -sb
```

Expected: `## main...origin/main` (or similar), no staged or modified files. Untracked files from the deferred plans (`docs/superpowers/plans/2026-05-02-deployment-surface-collapse.md`, `2026-05-02-simulation-engine-seam.md`, `docs/prds/`, `.claude/scheduled_tasks.lock`) are present and acceptable — they are the in-flight work for issues #77 and #78 and must not be touched here.

If the tree shows unexpected modifications: STOP and ask the user. Do not proceed.

- [ ] **Step 2: Verify all 11 tracked deletion targets are tracked**

```bash
for f in PRD_ISSUE_1_monolithic_deployment.md EOD_SUMMARY.md .github/issues/issue-31.md DEPENDENCY_ANALYSIS.md FUNCTION_ANALYSIS.md RUST_INTEGRATION.md test_failure_analysis.md TEST_RESULTS_SUMMARY.md api_documentation.md build.log build2.log; do
  printf "%s\t" "$f"
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && echo TRACKED || echo MISSING
done
```

Expected: all 11 print `TRACKED`. If any prints `MISSING`, STOP — the inventory is stale.

- [ ] **Step 3: Verify the 3 untracked files exist on disk**

```bash
for f in MATCH_PROCESSING_ANALYSIS.md RUST_RNG_FIX_RESULTS.md UNIT_TEST_SUMMARY.md; do
  printf "%s\t" "$f"
  test -f "$f" && echo PRESENT || echo MISSING
done
```

Expected: all 3 print `PRESENT`. If any are `MISSING`, that file is already gone — note it and skip the corresponding `mv` in Task 4.

- [ ] **Step 4: Verify `docs/COMMANDS.md` exists**

```bash
test -f docs/COMMANDS.md && echo PRESENT || echo MISSING
```

Expected: `PRESENT`.

- [ ] **Step 5: Create the working branch**

```bash
git checkout -b feature/issue-81-prune-root-clutter
git status -sb
```

Expected: `## feature/issue-81-prune-root-clutter` and the same untracked-file set as Step 1.

---

## Task 2: Commit 1 — remove stale-architecture artifacts

**Goal:** Delete the three files that contradict the current single-container deployment architecture.

**Files:**
- Delete: `PRD_ISSUE_1_monolithic_deployment.md`
- Delete: `EOD_SUMMARY.md`
- Delete: `.github/issues/issue-31.md`

- [ ] **Step 1: Remove the three files via `git rm`**

```bash
git rm PRD_ISSUE_1_monolithic_deployment.md EOD_SUMMARY.md .github/issues/issue-31.md
```

Expected: three `rm` lines printed.

- [ ] **Step 2: Verify the index has the deletions staged**

```bash
git status -s | grep -E '^D '
```

Expected: three lines, one per deleted file:
```
D  .github/issues/issue-31.md
D  EOD_SUMMARY.md
D  PRD_ISSUE_1_monolithic_deployment.md
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(#81): remove stale-architecture artifacts

PRD_ISSUE_1_monolithic_deployment.md proposed the rejected
microservices design; docs/deployment/README.md is the canonical
deployment doc. EOD_SUMMARY.md was output from the deleted /eod
command (retired in #75). .github/issues/issue-31.md is a frozen
workflow-stage snapshot for a closed issue with dead labels
(status:plan_written, tests:approved).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Verify the commit landed**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: top commit is `chore(#81): remove stale-architecture artifacts`, with three files deleted and 0 insertions.

---

## Task 3: Commit 2 — remove repo-root analysis dumps

**Goal:** Delete the six one-off analysis Markdown files that documented investigations from July 2025.

**Files:**
- Delete: `DEPENDENCY_ANALYSIS.md`
- Delete: `FUNCTION_ANALYSIS.md`
- Delete: `RUST_INTEGRATION.md`
- Delete: `test_failure_analysis.md`
- Delete: `TEST_RESULTS_SUMMARY.md`
- Delete: `api_documentation.md`

- [ ] **Step 1: Remove the six files via `git rm`**

```bash
git rm DEPENDENCY_ANALYSIS.md FUNCTION_ANALYSIS.md RUST_INTEGRATION.md test_failure_analysis.md TEST_RESULTS_SUMMARY.md api_documentation.md
```

Expected: six `rm` lines printed.

- [ ] **Step 2: Verify the index has six deletions staged**

```bash
git status -s | grep -c '^D '
```

Expected: `6`.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(#81): remove repo-root analysis dumps

Six one-off Markdown analysis dumps from July 2025 investigations:
DEPENDENCY_ANALYSIS, FUNCTION_ANALYSIS, RUST_INTEGRATION,
test_failure_analysis, TEST_RESULTS_SUMMARY, api_documentation.
RUST_INTEGRATION duplicates content in docs/architecture/overview.md;
the rest are point-in-time investigation artifacts whose underlying
code is in RCode/ and whose insights have either landed in production
or in the canonical docs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Verify the commit landed**

```bash
git log --oneline -1
git show --stat HEAD | tail -10
```

Expected: top commit is `chore(#81): remove repo-root analysis dumps`, six files deleted.

---

## Task 4: Commit 3 — untrack build logs, set up `removed/`, update `.gitignore`

**Goal:** Stop tracking the two build logs (~1.5 MB), move the three untracked clutter files to `removed/` for a recovery window, and add three `.gitignore` patterns to prevent regression.

**Files:**
- Delete (untrack): `build.log`, `build2.log`
- Move (working tree only): `MATCH_PROCESSING_ANALYSIS.md`, `RUST_RNG_FIX_RESULTS.md`, `UNIT_TEST_SUMMARY.md` → `removed/`
- Modify: `.gitignore` (add three patterns)
- Create: `removed/` directory

- [ ] **Step 1: Untrack the two build logs**

```bash
git rm build.log build2.log
```

Expected: two `rm` lines.

- [ ] **Step 2: Confirm working-tree files are gone (they shouldn't be — `git rm` deletes them too unless `--cached`)**

Decision: we want them gone from the working tree as well, because they should never have existed. `git rm` (not `--cached`) is correct. Verify:

```bash
ls build.log build2.log 2>&1 || echo "logs are gone — OK"
```

Expected: `ls: build.log: No such file or directory` (or similar), and the `OK` message.

- [ ] **Step 3: Create the `removed/` directory**

```bash
mkdir -p removed
ls -ld removed
```

Expected: `drwxr-xr-x` (or similar) line for `removed`.

- [ ] **Step 4: Move the three untracked clutter files into `removed/`**

```bash
mv MATCH_PROCESSING_ANALYSIS.md RUST_RNG_FIX_RESULTS.md UNIT_TEST_SUMMARY.md removed/ 2>&1
```

Expected: silent success. If any of the three was missing per Task 1 Step 3, `mv` will print "No such file or directory" for that one — that's fine; the others still move.

- [ ] **Step 5: Verify the moves**

```bash
ls removed/
```

Expected: at least `MATCH_PROCESSING_ANALYSIS.md`, `RUST_RNG_FIX_RESULTS.md`, `UNIT_TEST_SUMMARY.md` (modulo any that were missing in Task 1 Step 3).

- [ ] **Step 6: Confirm the moves left no working-tree changes for git to see** (because the source files are gitignored and `removed/` will be gitignored)

```bash
git status -s
```

Expected: only the staged `D build.log` and `D build2.log` from Step 1, plus the same pre-existing untracked files from Task 1 Step 1 (`docs/superpowers/plans/2026-05-02-deployment-surface-collapse.md`, etc.). No new entries for `MATCH_PROCESSING_ANALYSIS.md` or its siblings.

- [ ] **Step 7: Add three `.gitignore` patterns**

Use the Edit tool to modify `.gitignore`. Find this exact text:

```
# Test artifacts and analysis files
tests/rust/
MATCH_PROCESSING_ANALYSIS.md
RUST_RNG_FIX_RESULTS.md
UNIT_TEST_SUMMARY.md
```

Replace with:

```
# Test artifacts and analysis files
tests/rust/
MATCH_PROCESSING_ANALYSIS.md
RUST_RNG_FIX_RESULTS.md
UNIT_TEST_SUMMARY.md

# Build logs (issue #81)
build.log
build2.log

# Recovery folder for working-tree-only deletions (issue #81)
removed/
```

- [ ] **Step 8: Verify `.gitignore` is correctly updated**

```bash
grep -nE '^(build\.log|build2\.log|removed/)$' .gitignore
```

Expected: three lines, e.g.:
```
35:build.log
36:build2.log
39:removed/
```
(Line numbers may differ.)

- [ ] **Step 9: Verify `removed/` is now gitignored**

```bash
git check-ignore -v removed/foo
```

Expected: a line like `.gitignore:39:removed/    removed/foo` confirming the rule matches. (The path `removed/foo` doesn't need to exist; `check-ignore` only inspects rules.)

- [ ] **Step 10: Stage `.gitignore` and confirm the full diff**

```bash
git add .gitignore
git diff --cached
```

Expected: the `.gitignore` change (3 lines added) plus the two `D build.log` / `D build2.log` deletions from Step 1.

- [ ] **Step 11: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(#81): untrack build logs, gitignore them and removed/

Remove the two tracked Docker build log dumps (~1.5 MB combined) and
add three .gitignore rules so they cannot return: build.log, build2.log,
and removed/. The removed/ folder holds three working-tree files
(MATCH_PROCESSING_ANALYSIS.md, RUST_RNG_FIX_RESULTS.md,
UNIT_TEST_SUMMARY.md) that were already gitignored and are now moved
out of the repo root for clarity, with a recovery window for the user.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 12: Verify the commit landed**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: top commit is `chore(#81): untrack build logs, gitignore them and removed/`, three files changed: `.gitignore` (+3 lines), `build.log` deleted, `build2.log` deleted.

---

## Task 5: Commit 4 — fold `docs/COMMANDS.md` into `CLAUDE.md`, drop the doc

**Goal:** Move the three genuinely-unique command blocks into `CLAUDE.md`, remove all references to `docs/COMMANDS.md` (and the now-redundant `## Documentation` and `## Note on Documentation` sections), update `docs/README.md`, then `git rm docs/COMMANDS.md`.

**Files:**
- Modify: `CLAUDE.md` (add 3 command blocks; remove 3 sections/references)
- Modify: `docs/README.md` (drop one quick-link)
- Delete: `docs/COMMANDS.md`

- [ ] **Step 1: Read the current state of `CLAUDE.md`**

Use the Read tool to read `CLAUDE.md`. Confirm it matches what the spec describes (line 26 has `For complete command reference, see @docs/COMMANDS.md`; lines 52–66 have `## Documentation` and `## Note on Documentation` sections; line 56 has `**Commands**: @docs/COMMANDS.md`). If it doesn't match, STOP and report drift.

- [ ] **Step 2: Replace the `## Quick Commands` section with the expanded version**

Use the Edit tool. Find this exact text in `CLAUDE.md`:

```markdown
## Quick Commands

```bash
# Run tests
source("tests/testthat.R")

# Run single update
Rscript run_single_update_2025.R

# Build and run the production Docker stack
docker build -t league-simulator:latest .
docker-compose up -d

# Season transition
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

For complete command reference, see @docs/COMMANDS.md
```

Replace with:

```markdown
## Quick Commands

```r
# Run all tests
source("tests/testthat.R")

# Run a single test file
testthat::test_file("tests/testthat/test-prozent.R")

# Install R dependencies from packagelist.txt
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])

# Run the Shiny app locally
shiny::runApp("ShinyApp/app.R")
```

```bash
# Run a single update
Rscript run_single_update_2025.R

# Build and run the production Docker stack
docker build -t league-simulator:latest .
docker-compose up -d

# Season transition
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```
```

Note the structure: R commands (testthat, packagelist, shiny) are in an `r` fence; bash commands (Rscript, docker, season transition) are in a `bash` fence. The `For complete command reference, see @docs/COMMANDS.md` line is removed.

- [ ] **Step 3: Remove the `## Documentation` and `## Note on Documentation` sections**

Use the Edit tool. Find this exact text in `CLAUDE.md`:

```markdown
## Documentation

- **Documentation Index**: @docs/README.md
- **Known Issues**: @docs/KNOWN_ISSUES.md
- **Commands**: @docs/COMMANDS.md
- **Architecture**: @docs/architecture/
- **Deployment**: @docs/deployment/
  - **Production Deployment**: @docs/deployment/README.md
  - **Quick Start**: @docs/deployment/quick-start.md
- **Operations**: @docs/operations/
- **Troubleshooting**: @docs/troubleshooting/

## Note on Documentation

This file is intentionally concise. Detailed information is lazy-loaded via @mentions from the docs/ directory to improve Claude Code performance and context management.
```

Replace with: (empty string — delete both sections entirely)

The rationale for removing both: (a) they duplicate `docs/README.md` (the doc index, which they themselves @mention), and (b) the `## Note on Documentation` paragraph is meta-commentary about a lazy-loading pattern that no longer needs to be highlighted at this volume after #75 trimmed the file. Memory entry "CLAUDE.md trim after #75" tracked this work explicitly.

- [ ] **Step 4: Verify `CLAUDE.md` has zero remaining `COMMANDS.md` references**

```bash
grep -nF 'COMMANDS.md' CLAUDE.md
```

Expected: no output.

- [ ] **Step 5: Verify the three unique blocks landed**

```bash
grep -F 'testthat::test_file' CLAUDE.md
grep -F 'packagelist.txt' CLAUDE.md
grep -F 'shiny::runApp' CLAUDE.md
```

Expected: each grep returns exactly one matching line.

- [ ] **Step 6: Verify `## Documentation` and `## Note on Documentation` are gone**

```bash
grep -nE '^## (Documentation|Note on Documentation)$' CLAUDE.md
```

Expected: no output.

- [ ] **Step 7: Sanity — confirm `CLAUDE.md` still has the other essential sections**

```bash
grep -nE '^## (Project Overview|Quick Commands|Architecture|Required Environment|Current Status)$' CLAUDE.md
```

Expected: five matches, in that order.

- [ ] **Step 8: Update `docs/README.md` to drop the COMMANDS.md quick-link**

Use the Edit tool. Find this exact text in `docs/README.md`:

```markdown
## Quick Links
- [Commands Reference](COMMANDS.md) - All available commands
- [Known Issues](KNOWN_ISSUES.md) - Current and resolved issues
- [Quick Start](deployment/quick-start.md) - Get up and running in 5 minutes
```

Replace with:

```markdown
## Quick Links
- [Known Issues](KNOWN_ISSUES.md) - Current and resolved issues
- [Quick Start](deployment/quick-start.md) - Get up and running in 5 minutes
```

- [ ] **Step 9: Verify `docs/README.md` no longer references COMMANDS.md**

```bash
grep -nF 'COMMANDS.md' docs/README.md
```

Expected: no output.

- [ ] **Step 10: Delete `docs/COMMANDS.md`**

```bash
git rm docs/COMMANDS.md
```

Expected: `rm 'docs/COMMANDS.md'`.

- [ ] **Step 11: Stage the two modified files**

```bash
git add CLAUDE.md docs/README.md
git diff --cached --stat
```

Expected: three files in the diff:
- `CLAUDE.md` — both insertions (3 new command blocks) and deletions (`## Documentation`, `## Note on Documentation`, the redundant Quick Commands suffix)
- `docs/COMMANDS.md` — deleted
- `docs/README.md` — 1 line removed

- [ ] **Step 12: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs(#81): fold COMMANDS.md into CLAUDE.md and drop the file

docs/COMMANDS.md became thin after #75 retired the workflow tooling.
Three blocks were genuinely unique: single-file testthat invocation,
installing R dependencies from packagelist.txt, and running the Shiny
app locally. Those move into CLAUDE.md's Quick Commands section.

Also removes the now-redundant `## Documentation` section (it just
duplicates docs/README.md) and `## Note on Documentation`
(meta-commentary that no longer pulls its weight at this file volume).
This completes the CLAUDE.md trim flagged for after #75.

docs/README.md drops the Commands Reference quick-link.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 13: Verify the commit landed**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: top commit is `docs(#81): fold COMMANDS.md into CLAUDE.md and drop the file`, three files changed.

---

## Task 6: Acceptance verification

**Goal:** Run the full verification checklist from the spec. Every check must pass before pushing.

**Files:**
- Read-only verification

- [ ] **Step 1: Confirm none of the tracked deletions remain in the index**

```bash
git ls-files | grep -E '^(PRD_ISSUE_1_monolithic_deployment|EOD_SUMMARY|DEPENDENCY_ANALYSIS|FUNCTION_ANALYSIS|RUST_INTEGRATION|test_failure_analysis|TEST_RESULTS_SUMMARY|api_documentation|build|build2)\.(md|log)$|^\.github/issues/issue-31\.md$|^docs/COMMANDS\.md$'
```

Expected: no output.

- [ ] **Step 2: Confirm working tree is clean**

```bash
git status -s
```

Expected: only the pre-existing untracked entries from Task 1 Step 1 (`docs/superpowers/plans/2026-05-02-deployment-surface-collapse.md`, `docs/superpowers/plans/2026-05-02-simulation-engine-seam.md`, `docs/prds/`, `.claude/scheduled_tasks.lock`). No staged changes, no new modifications, no entries for the moved files in `removed/`.

- [ ] **Step 3: Confirm untracked files moved successfully**

```bash
ls removed/ 2>/dev/null
```

Expected: `MATCH_PROCESSING_ANALYSIS.md`, `RUST_RNG_FIX_RESULTS.md`, `UNIT_TEST_SUMMARY.md` (all three, modulo any that were missing per Task 1 Step 3).

- [ ] **Step 4: Confirm `.gitignore` updated**

```bash
grep -E '^(build\.log|build2\.log|removed/)$' .gitignore
```

Expected: three matching lines (one per pattern).

- [ ] **Step 5: Confirm `CLAUDE.md` consolidation is correct**

```bash
grep -F 'testthat::test_file' CLAUDE.md            # Expect: 1 hit
grep -F 'packagelist.txt' CLAUDE.md                 # Expect: 1 hit
grep -F 'shiny::runApp' CLAUDE.md                   # Expect: 1 hit
grep -F 'COMMANDS.md' CLAUDE.md                     # Expect: no output
grep -nE '^## (Documentation|Note on Documentation)$' CLAUDE.md  # Expect: no output
```

- [ ] **Step 6: Confirm `docs/README.md` no longer links to COMMANDS.md**

```bash
grep -F 'COMMANDS.md' docs/README.md
```

Expected: no output.

- [ ] **Step 7: Confirm no live references to deleted files outside historical PRDs and the spec/plan files**

```bash
grep -rEn 'RUST_INTEGRATION\.md|MATCH_PROCESSING_ANALYSIS\.md|RUST_RNG_FIX_RESULTS\.md|FUNCTION_ANALYSIS\.md|DEPENDENCY_ANALYSIS\.md|api_documentation\.md|EOD_SUMMARY\.md|PRD_ISSUE_1_monolithic_deployment\.md|test_failure_analysis\.md|TEST_RESULTS_SUMMARY\.md|UNIT_TEST_SUMMARY\.md' \
  --include='*.md' --include='*.R' --include='*.yml' --include='*.yaml' --include='*.sh' --include='*.txt' \
  --include='Dockerfile*' . 2>/dev/null \
  | grep -v '^./.git/' \
  | grep -vE '^./docs/(superpowers/(plans|specs)|prds)/' \
  | grep -v '^./removed/'
```

Expected: no output. Hits inside `docs/superpowers/plans/`, `docs/superpowers/specs/`, `docs/prds/`, and `removed/` are intentionally filtered: planning/PRD/spec records document the cleanup itself; `removed/` files contain self-references that don't matter.

- [ ] **Step 8: Sanity — production R sources still parse**

```bash
Rscript -e 'invisible(parse("RCode/updateScheduler.R")); cat("OK\n")'
Rscript -e 'invisible(parse("RCode/update_all_leagues_loop.R")); cat("OK\n")'
```

Expected: `OK` printed twice. (We did not touch these files; this is a cheap belt-and-braces check.)

- [ ] **Step 9: Confirm the four-commit shape**

```bash
git log --oneline main..HEAD
```

Expected: exactly 4 commits, in order (newest first):
1. `docs(#81): fold COMMANDS.md into CLAUDE.md and drop the file`
2. `chore(#81): untrack build logs, gitignore them and removed/`
3. `chore(#81): remove repo-root analysis dumps`
4. `chore(#81): remove stale-architecture artifacts`

If there are more or fewer, STOP and reconcile before pushing.

- [ ] **Step 10: Total file delta**

```bash
git diff --stat main..HEAD
```

Expected: **15 unique files** in the stat output — 12 deletions (`PRD_ISSUE_1_monolithic_deployment.md`, `EOD_SUMMARY.md`, `.github/issues/issue-31.md`, `DEPENDENCY_ANALYSIS.md`, `FUNCTION_ANALYSIS.md`, `RUST_INTEGRATION.md`, `test_failure_analysis.md`, `TEST_RESULTS_SUMMARY.md`, `api_documentation.md`, `build.log`, `build2.log`, `docs/COMMANDS.md`) + 3 modifications (`.gitignore`, `CLAUDE.md`, `docs/README.md`). Net: ~1.5 MB removed from tracked content.

---

## Task 7: Push and open PR

**Goal:** Push the branch and open the PR that closes #81. Per the user's "Branch completion default" memory, default to push+PR (Option 2) without asking.

**Files:**
- Read-only

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/issue-81-prune-root-clutter
```

Expected: a push confirmation with a `Create a pull request` URL printed by GitHub.

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "chore(#81): prune stale repo-root analysis dumps and tracked build logs" --body "$(cat <<'EOF'
## Summary
- Removes 11 tracked files from the repo root (~1.5 MB): three stale-architecture artifacts (PRD_ISSUE_1, EOD_SUMMARY, .github/issues/issue-31.md), six analysis dumps (DEPENDENCY/FUNCTION/RUST_INTEGRATION/test_failure/TEST_RESULTS/api_documentation), and two tracked Docker build logs.
- Moves three already-gitignored working-tree files (MATCH_PROCESSING_ANALYSIS, RUST_RNG_FIX_RESULTS, UNIT_TEST_SUMMARY) into a new gitignored `removed/` folder so deletion is reversible.
- Adds `build.log`, `build2.log`, and `removed/` to `.gitignore`.
- Folds the three unique commands from `docs/COMMANDS.md` into `CLAUDE.md`'s Quick Commands; drops the file. Also removes `CLAUDE.md`'s redundant `## Documentation` and `## Note on Documentation` sections (memory entry "CLAUDE.md trim after #75" — naturally folds in here). Updates `docs/README.md` to drop the orphaned quick-link.

Closes #81.

Spec: `docs/superpowers/specs/2026-05-02-prune-root-clutter-design.md`
Plan: `docs/superpowers/plans/2026-05-02-prune-root-clutter.md`

## Scope guardrails
Zero changes to `RCode/`, `scripts/`, `Dockerfile`, `docker-compose.yml`, `tests/testthat/`, or `.github/workflows/` — preserves merge-parallelism with PR #83 (issue #77, Rust simulation seam) and the upcoming #76 (CI rebuild).

## Test plan
- [ ] `git ls-files` returns zero hits for any of the 12 deleted files
- [ ] `ls removed/` shows the three moved files
- [ ] `grep -F 'COMMANDS.md' CLAUDE.md docs/README.md` returns no output
- [ ] `grep -F 'testthat::test_file' CLAUDE.md` and friends each return 1 hit
- [ ] `Rscript -e 'invisible(parse("RCode/updateScheduler.R")); cat("OK\n")'` prints `OK` (sanity — no R was touched)
- [ ] PR diff has exactly 4 commits

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: a `https://github.com/chrisschwer/League-Simulator-Update/pull/<N>` URL printed.

- [ ] **Step 3: Print the PR URL for the user**

```bash
gh pr view --json url --jq .url
```

Expected: the PR URL.

---

## Done

The branch is on `origin`, the PR is open, and #81 is closed when it merges.
