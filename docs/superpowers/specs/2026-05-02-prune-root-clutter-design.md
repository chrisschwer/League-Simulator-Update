# Prune stale repo-root analysis dumps and tracked build logs

**Issue:** [#81](https://github.com/chrisschwer/League-Simulator-Update/issues/81)
**Date:** 2026-05-02
**Status:** design approved, awaiting implementation plan

## Goal

Remove repo-root clutter that survived issue #75's workflow-tooling cleanup: stale architectural artifacts that contradict the current single-container deployment, one-off analysis dumps from July–August 2025, and ~1.5 MB of tracked build logs. Fold the three genuinely-unique commands from the now-thin `docs/COMMANDS.md` into `CLAUDE.md` and remove the file.

## Non-goals

- **Out of scope:** any change inside `RCode/`, `scripts/`, `Dockerfile`, `docker-compose.yml`, or `tests/testthat/`. This preserves merge-parallelism with issue #77 (in flight, PR #83) and the eventual issue #76 (CI rebuild).
- **Out of scope:** the documentation sweep across `docs/deployment/*.md`, `docs/architecture/overview.md`, `tests/REVISED_TEST_SPECIFICATIONS.md`, `tests/container-league.yaml`, `tests/docker/*` — those belong to issue #79.
- **Out of scope:** the repo-root R-script clutter (`compare_*.R`, `debug_*.R`, `elv_*.R`, `test_api_connection.R`, `test_elo_fix.R`, `run_single_update_2025.R`). Flagged in `docs/prds/2026-05-02-deployment-surface-collapse.md:225` for a future review.

## Inventory

### Tracked files to delete (`git rm`) — 11 files

**Stale-architecture artifacts:**

| File | Size | Why delete |
|---|---|---|
| `PRD_ISSUE_1_monolithic_deployment.md` | 3.2 KB | Proposes the rejected microservices design; `docs/deployment/README.md` is canonical |
| `EOD_SUMMARY.md` | 6.3 KB | Output from the deleted `/eod` command (#75 retired the workflow tooling) |
| `.github/issues/issue-31.md` | 12.7 KB | Frozen workflow-stage snapshot for closed issue; dead labels (`status:plan_written`, `tests:approved`) |

**One-off analysis dumps:**

| File | Size | Why delete |
|---|---|---|
| `DEPENDENCY_ANALYSIS.md` | 6.2 KB | Investigation artifact, July 2025 |
| `FUNCTION_ANALYSIS.md` | 7.8 KB | Investigation artifact, July 2025 |
| `RUST_INTEGRATION.md` | 7.1 KB | Duplicates `docs/architecture/overview.md`'s Rust section |
| `test_failure_analysis.md` | 8.6 KB | Investigation artifact, July 2025 |
| `TEST_RESULTS_SUMMARY.md` | 6.2 KB | Investigation artifact, July 2025 |
| `api_documentation.md` | 5.3 KB | Investigation artifact, July 2025 |

**Build logs (should never have been tracked):**

| File | Size | Why delete |
|---|---|---|
| `build.log` | 715 KB | Tracked build output, August 2025 |
| `build2.log` | 853 KB | Tracked build output, August 2025 |

### Untracked files to move to `removed/` — 3 files

These are gitignored but still on disk. Moving (not deleting) preserves a recovery window for files git history cannot recover:

| File | Currently in `.gitignore`? |
|---|---|
| `MATCH_PROCESSING_ANALYSIS.md` | yes |
| `RUST_RNG_FIX_RESULTS.md` | yes |
| `UNIT_TEST_SUMMARY.md` | yes |

### Documentation consolidation — `docs/COMMANDS.md`

`docs/COMMANDS.md` (1374 bytes, ~50 lines) became thin after #75 stripped its biggest section. Most of its content duplicates `CLAUDE.md`'s `## Quick Commands` block, `docs/deployment/quick-start.md`, or `docs/user-guide/season-transition.md`. Three blocks are genuinely unique:

1. **Single-file test syntax** — `testthat::test_file("tests/testthat/test-prozent.R")`
2. **Install dependencies from `packagelist.txt`** — the two-line R block at lines 46–48
3. **Run Shiny app locally** — `shiny::runApp("ShinyApp/app.R")`

Action: fold these three blocks into `CLAUDE.md`'s `## Quick Commands` section, remove the `@docs/COMMANDS.md` reference from `CLAUDE.md`, `git rm docs/COMMANDS.md`, and update `docs/README.md` to drop the `[Commands Reference](COMMANDS.md)` quick-link.

## Design

### `removed/` folder approach

A new directory `removed/` at repo root, gitignored, holds the three untracked files. Rationale: untracked file deletion is final (no git history to recover from), and these files contain analysis output the user may want to consult during the next month. The folder is gitignored so it never enters version control.

Trade-off accepted: the folder may persist longer than intended. The user has chosen this over deleting outright; revisit during a future repo-hygiene pass.

### `.gitignore` additions

Three patterns to add — none are currently present:

```
build.log
build2.log
removed/
```

`MATCH_PROCESSING_ANALYSIS.md`, `RUST_RNG_FIX_RESULTS.md`, and `UNIT_TEST_SUMMARY.md` are already gitignored.

No blanket `*.log` rule — too broad, would match `logs/` content that may be wanted later.

### Inbound-reference verification (already done)

Search across `*.md`, `*.R`, `*.yml`, `*.yaml`, `*.sh`, `*.txt`, `Dockerfile*` for references to the deletion targets. All hits are confined to:

- `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling*.md` — historical record of the #75 cleanup that flagged these files
- `docs/superpowers/plans/2026-05-02-simulation-engine-seam.md` — the #77 plan, mentions `RUST_INTEGRATION.md` as out-of-scope
- `docs/prds/2026-05-02-deployment-surface-collapse.md` — historical record of #78
- One inbound mention inside `.github/issues/issue-31.md:273` to `api_documentation.md` — both files are being deleted together

These references are historical and **should remain** — they document what was removed and why. No live code, no operator docs, no CI references.

### Recovery paths

| File class | Recovery path if needed later |
|---|---|
| Tracked deletions | `git log --all --diff-filter=D -- <path>`, `git revert`, or check out the `pre-deployment-cleanup-2026-05-02` tag (which preserves the pre-#78 tree) |
| Untracked moves | `removed/<filename>` for one month, then user discretion |
| `docs/COMMANDS.md` | Git history; the unique commands are now in `CLAUDE.md` |

## Implementation outline

Branch off `main` to `feature/issue-81-prune-root-clutter`. Four commits, one per logical group:

1. **`chore(#81): remove stale-architecture artifacts`** — `git rm` of `PRD_ISSUE_1_monolithic_deployment.md`, `EOD_SUMMARY.md`, `.github/issues/issue-31.md`
2. **`chore(#81): remove repo-root analysis dumps`** — `git rm` of `DEPENDENCY_ANALYSIS.md`, `FUNCTION_ANALYSIS.md`, `RUST_INTEGRATION.md`, `test_failure_analysis.md`, `TEST_RESULTS_SUMMARY.md`, `api_documentation.md`
3. **`chore(#81): untrack build logs, move untracked clutter, update .gitignore`** — `git rm build.log build2.log`; `mkdir removed/`; `mv MATCH_PROCESSING_ANALYSIS.md RUST_RNG_FIX_RESULTS.md UNIT_TEST_SUMMARY.md removed/`; add `build.log`, `build2.log`, and `removed/` to `.gitignore`. The `mv` operations are working-tree-only (the source files are gitignored and `removed/` is gitignored); only the `git rm` of the build logs and the `.gitignore` change appear in this commit's diff.
4. **`docs(#81): fold COMMANDS.md unique commands into CLAUDE.md`** — `CLAUDE.md` updated with the three unique blocks and the `@docs/COMMANDS.md` reference removed; `docs/README.md` updated to drop the quick-link; `git rm docs/COMMANDS.md`

PR closes #81.

## Verification

After the branch lands locally, all of these must hold:

```bash
# (1) None of the tracked deletions remain in the index
git ls-files | grep -E '^(PRD_ISSUE_1_monolithic_deployment|EOD_SUMMARY|DEPENDENCY_ANALYSIS|FUNCTION_ANALYSIS|RUST_INTEGRATION|test_failure_analysis|TEST_RESULTS_SUMMARY|api_documentation|build|build2)\.(md|log)$|^\.github/issues/issue-31\.md$|^docs/COMMANDS\.md$'
# Expect: no output

# (2) Working tree is clean (no orphans, no surprise residuals)
git status --porcelain
# Expect: empty (or only `removed/` if files weren't moved yet — check before claiming done)

# (3) Untracked files moved successfully
ls removed/ 2>/dev/null
# Expect: MATCH_PROCESSING_ANALYSIS.md, RUST_RNG_FIX_RESULTS.md, UNIT_TEST_SUMMARY.md (all three)

# (4) .gitignore updated
grep -E '^(build\.log|build2\.log|removed/)$' .gitignore
# Expect: three matching lines

# (5) CLAUDE.md has the three unique blocks; @docs/COMMANDS.md reference is gone
grep -F 'testthat::test_file' CLAUDE.md            # Expect: 1 hit
grep -F 'packagelist.txt' CLAUDE.md                 # Expect: 1 hit
grep -F 'shiny::runApp' CLAUDE.md                   # Expect: 1 hit
grep -F '@docs/COMMANDS.md' CLAUDE.md               # Expect: no output

# (6) docs/README.md no longer links to docs/COMMANDS.md
grep -F 'COMMANDS.md' docs/README.md                # Expect: no output

# (7) No live references to the deleted files outside historical PRDs
grep -rEn 'RUST_INTEGRATION\.md|MATCH_PROCESSING_ANALYSIS\.md|RUST_RNG_FIX_RESULTS\.md|FUNCTION_ANALYSIS\.md|DEPENDENCY_ANALYSIS\.md|api_documentation\.md|EOD_SUMMARY\.md|PRD_ISSUE_1_monolithic_deployment\.md|test_failure_analysis\.md|TEST_RESULTS_SUMMARY\.md|UNIT_TEST_SUMMARY\.md' \
  --include='*.md' --include='*.R' --include='*.yml' --include='*.yaml' --include='*.sh' --include='*.txt' \
  --include='Dockerfile*' . 2>/dev/null \
  | grep -v '^./.git/' \
  | grep -vE '^./docs/(superpowers/plans|prds)/'
# Expect: no output (or only references inside the new spec file itself)

# (8) Sanity — production R sources still parse (we did not touch them, but cheap to confirm)
Rscript -e 'invisible(parse("RCode/updateScheduler.R")); cat("OK\n")'
# Expect: OK
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Deleted file held unique knowledge not duplicated elsewhere | Low | Spot-check the four largest deletions during implementation (`build.log`/`build2.log` are pure noise; `.github/issues/issue-31.md` and `test_failure_analysis.md` warrant a 30-second skim) |
| `CLAUDE.md` consolidation drops a command someone uses | Low | Three blocks merged in, none removed from elsewhere |
| `removed/` folder lingers indefinitely | Medium (accepted) | Trade-off chosen explicitly by user; revisit in a future hygiene pass |
| Re-tracked `build.log` later | Low | `.gitignore` update prevents re-track |
| Merge conflict with PR #83 (#77) | Low | Zero file overlap — verified |
| Conflict with future #76 (CI rebuild) | Low | Issue #81 stays out of `.github/workflows/` and `tests/testthat/` |
