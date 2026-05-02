# Prune Local Claude Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the home-grown 11-stage GitHub-issue workflow that lives in `.claude/` and is referenced from `CLAUDE.md`, `docs/COMMANDS.md`, and `.github/ISSUE_TEMPLATE/`. The `superpowers:*` plugin (writing-plans, executing-plans, brainstorming, …) plus the project-specific `architecture-review-prd` skill now cover the same territory better. Also prune the user-level `~/.claude/` leftovers and leave a written record of which shell aliases the user should remove from their zsh rc.

**Architecture:** Pure documentation/tooling cleanup. No source code changes — `RCode/`, `tests/`, `Dockerfile`, `docker-compose.yml`, `scripts/`, the Rust crate are **untouched**. The work has four sweeps: (1) repo-level `.claude/` workflow tooling, (2) `CLAUDE.md` and other repo docs that reference it, (3) `.github/` issue templates and stale issue artifacts that hardcode the workflow's labels, (4) user-level `~/.claude/` plus a shell-alias-removal note. Every deletion is preceded by a backup copy, so the work is reversible. The repo-level `architecture-review-prd` skill at `.claude/skills/architecture-review-prd/` is kept — it's the active skill that produced the PRDs at `docs/prds/`. Session notes from July 2025 (`.claude/session_notes/2025-07-*.md`) are kept too — they're a historical record, not workflow infrastructure. The agent at `.claude/agents/github-actions-issue-manager.md` is kept as a useful standalone CI/CD analysis agent that does not depend on the workflow.

**Tech Stack:** zsh, `git`, `gh`. No language runtimes, no build steps, no tests required.

---

## Pre-flight observations (from full inventory done while writing this plan)

### What gets removed (repo-level)

All of the following are tracked in git and depend on the 11-stage workflow:

- `.claude/workflow.md` — the workflow spec itself (388 lines).
- `.claude/CLAUDE.md` — duplicate older copy of the same workflow spec.
- `.claude/development_workflow.md` — sibling guide that duplicates and predates the 11-stage description.
- `.claude/project_context.md` — describes the project as having a "microservices architecture" and "Kubernetes deployment", which contradicts the post-#78-merge reality (single integrated container, see `docs/deployment/README.md`). Delete; the canonical project context is `CLAUDE.md` + `docs/architecture/overview.md` + `docs/deployment/README.md`.
- `.claude/testing_and_build.md` — describes test infrastructure inconsistently with `docs/TEST_ORGANIZATION.md` and `CLAUDE.md`. Delete; canonical source is `docs/TEST_ORGANIZATION.md`.
- `.claude/commands/` — all 19 files (`analyze.md`, `approve_issue.md`, `branch-status.md`, `cleanup-branches.md`, `commit-progress.md`, `createpr.md`, `eod.md`, `implement.md`, `list_human_todo.md`, `makeprogress.md`, `meta-plan.md`, `newissue.md`, `parallel.md`, `plan.md`, `reject_issue.md`, `review.md`, `setup-board.md`, `setup-environment.md`, `writetest.md`).

### What stays (repo-level)

- `.claude/skills/architecture-review-prd/` — the skill that produced the recent PRDs (`docs/prds/2026-05-02-*.md`). Listed by the system as currently available. **Keep.**
- `.claude/agents/github-actions-issue-manager.md` — a generic CI/CD analysis agent. Not workflow-dependent. **Keep.**
- `.claude/session_notes/` — historical July 2025 notes. Not infrastructure; just a paper trail. **Keep.**
- `.claude/settings.local.json` — Claude Code permissions config. Some entries reference the workflow (`Bash(claude /setup-board)`, `Bash(./scripts/board-automation.sh:*)`, `Bash(./scripts/set-stage.sh:*)`, `Bash(./scripts/validate-setup.sh:*)`). Those scripts don't exist in `scripts/` — the permissions are for tooling that was already gone. The permissions are dead but harmless; we leave the file alone because re-curating settings is a separate concern (the `update-config` skill exists for that). Document in the result file as a known leftover.

### What gets edited (repo-level)

- `CLAUDE.md` — remove the entire `## Workflow` section (lines 46–55) which @-mentions `.claude/workflow.md` and lists `/newissue`, `/makeprogress`, `/list_human_todo`.
- `docs/COMMANDS.md` — remove the `## Workflow Commands` section at the tail (lines 63–70) which references `.claude/workflow.md` and the workflow commands.
- `.github/ISSUE_TEMPLATE/feature_request.md` — remove `status:new` from the labels frontmatter; remove "Priority Assessment" boilerplate that hardcodes the P0–P3 labels (kept generic acceptance-criteria sections — those are useful).
- `.github/ISSUE_TEMPLATE/bug_report.md` — same as feature_request: remove `status:new` label, remove P0–P3 boilerplate.
- `.github/ISSUE_TEMPLATE/prd_template.md` — full delete (the new flow is `architecture-review-prd` skill → `docs/prds/` → `superpowers:writing-plans`; an issue-template PRD is now redundant *and* misleading).

### What gets removed (user-level, outside repo)

- `~/.claude/commands/eod.md` — older variant, never aligned with the now-deleted repo workflow either.
- `~/.claude/commands/getissues.md` — only if no other project on this machine references it (verified at task time).
- `~/.claude/agents/` — does not exist; no action.
- `~/.claude/skills/schwerdtfeger-design/` — **keep** (per issue body, unique personal design system).

### What gets created (record + future cleanup)

- `docs/REMOVE_SHELL_ALIASES.md` — instructions listing the 11 zsh aliases the user should remove from their shell rc (`cni`, `cmp`, `cht`, `cap`, `crj`, `cplan`, `ceod`, `cpar`, `cws`, `cwc`, `cwn`) plus the corresponding shell functions (`claude_worktree_create`, `claude_worktree_status`, `claude_worktree_cleanup`). The user removes them at their own pace; the repo just hosts the checklist.
- `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md` — inventory + decisions record.

### Stale artifacts that contradict / mask superpowers and the current architecture

These were found during the inventory sweep and are flagged here so the user can decide whether to delete them. They are **not** in the deletion list of this plan because they aren't directly workflow-related — they're a separate "repo root hygiene" concern. The plan adds a single follow-up issue at the end rather than expanding scope mid-flight.

- **Root-level workflow leftovers (tracked):** `EOD_SUMMARY.md` (output from the deleted `/eod` command), `PRD_ISSUE_1_monolithic_deployment.md` (a one-off PRD that proposed the now-rejected microservices design — directly contradicts `docs/deployment/README.md`), `.github/issues/issue-31.md` (a snapshot of a workflow-stage tracker for a closed issue, has labels like `status:plan_written`, `tests:approved`).
- **Root-level analysis dumps (tracked or untracked):** `DEPENDENCY_ANALYSIS.md`, `FUNCTION_ANALYSIS.md`, `MATCH_PROCESSING_ANALYSIS.md`, `RUST_INTEGRATION.md`, `RUST_RNG_FIX_RESULTS.md`, `test_failure_analysis.md`, `TEST_RESULTS_SUMMARY.md`, `UNIT_TEST_SUMMARY.md`, `api_documentation.md`. Same class as the `compare_*.R`, `debug_*.R`, `elv_*.R` clutter flagged in the deployment-surface PRD.
- **Build logs (tracked!):** `build.log` (700 KB), `build2.log` (850 KB). Should not be in git.
- **`docs/COMMANDS.md`** itself partly duplicates `CLAUDE.md`'s Quick Commands and the actual command sources (`docker-compose.yml`, `scripts/season_transition.R`'s `--help`). After Task 5 strips the Workflow Commands section, what remains is mostly a thin shadow of canonical sources — flag for a future merge into `CLAUDE.md`.

The follow-up issue (Task 11) captures all of this.

---

## File Structure

This plan touches the `.claude/` directory, three `CLAUDE.md`-adjacent docs, three `.github/` files, and writes two new files. No source code under `RCode/`, `tests/`, `scripts/`, or `Dockerfile` is touched.

**Created:**
- `~/.claude/backups/prune-2026-05-02/` — full mirror of every file removed (preserves repo-relative and home-relative subpaths).
- `docs/REMOVE_SHELL_ALIASES.md` — the alias-removal checklist.
- `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md` — inventory + decisions record.

**Deleted (repo-level):**
- `.claude/workflow.md`
- `.claude/CLAUDE.md`
- `.claude/development_workflow.md`
- `.claude/project_context.md`
- `.claude/testing_and_build.md`
- `.claude/commands/` (entire directory: 19 files)
- `.github/ISSUE_TEMPLATE/prd_template.md`

**Modified (repo-level):**
- `CLAUDE.md` — remove `## Workflow` section.
- `docs/COMMANDS.md` — remove `## Workflow Commands` section.
- `.github/ISSUE_TEMPLATE/feature_request.md` — remove `status:new` label and P0–P3 boilerplate.
- `.github/ISSUE_TEMPLATE/bug_report.md` — remove `status:new` label and P0–P3 boilerplate.

**Deleted (user-level):**
- `~/.claude/commands/eod.md`
- `~/.claude/commands/getissues.md` (conditional)

**Untouched in repo (kept):**
- `.claude/skills/architecture-review-prd/` (active skill)
- `.claude/agents/github-actions-issue-manager.md` (standalone agent)
- `.claude/session_notes/` (historical notes)
- `.claude/settings.local.json` (Claude Code config; dead workflow-script permissions noted in result doc but left alone)
- All of `docs/` except `COMMANDS.md` (one section) and the two new files
- `.github/CONTRIBUTING.md` (no workflow refs in it; verified)

---

### Task 1: Inventory snapshot and create the result document

**Files:**
- Create: `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md`

The decisions need to be written down *before* deletion so a reviewer can sanity-check the list. This task produces the document; subsequent tasks act on it and append findings.

- [ ] **Step 1: Capture the inventory**

```bash
git ls-files .claude/ > /tmp/prune-claude-tracked.txt
ls -la ~/.claude/skills/ ~/.claude/commands/ 2>&1 > /tmp/prune-user-level.txt
ls -la ~/.claude/agents/ 2>&1 >> /tmp/prune-user-level.txt
cat /tmp/prune-claude-tracked.txt
echo "---"
cat /tmp/prune-user-level.txt
```

Expected: 32 tracked files in `.claude/`, of which 2 (`.claude/skills/architecture-review-prd/SKILL.md` and `.claude/skills/architecture-review-prd/references/PRD-TEMPLATE.md`) are kept and 30 are deletion candidates. User-level: `~/.claude/skills/` has only `schwerdtfeger-design`; `~/.claude/commands/` has `eod.md` and `getissues.md`; `~/.claude/agents/` does not exist.

- [ ] **Step 2: Write the result document**

Create `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md` with the following content. Replace the placeholder counts in `[brackets]` with the actual values from Step 1:

```markdown
# Local Claude Tooling Prune — Result Record

**Date:** 2026-05-02
**Issue:** #75 (scope expanded mid-plan to include repo-level workflow tooling)
**Plan:** docs/superpowers/plans/2026-05-02-prune-local-claude-tooling.md

## Background

The repo-level `.claude/` directory hosted a home-grown 11-stage GitHub-issue workflow (`/newissue`, `/makeprogress`, `/list_human_todo`, etc.) that predated the `superpowers:*` plugin. The plugin now covers the same territory (brainstorming, writing-plans, executing-plans, code review, debugging) more cleanly. The user has asked for the home-grown workflow to be removed.

## Repo-level deletions

### Workflow docs (5 files)
- `.claude/workflow.md` — DELETED
- `.claude/CLAUDE.md` — DELETED (duplicate of workflow.md)
- `.claude/development_workflow.md` — DELETED
- `.claude/project_context.md` — DELETED (described pre-collapse microservices architecture; outdated)
- `.claude/testing_and_build.md` — DELETED (canonical source: docs/TEST_ORGANIZATION.md)

### Workflow commands (19 files)
All of `.claude/commands/`: `analyze.md`, `approve_issue.md`, `branch-status.md`, `cleanup-branches.md`, `commit-progress.md`, `createpr.md`, `eod.md`, `implement.md`, `list_human_todo.md`, `makeprogress.md`, `meta-plan.md`, `newissue.md`, `parallel.md`, `plan.md`, `reject_issue.md`, `review.md`, `setup-board.md`, `setup-environment.md`, `writetest.md` — ALL DELETED. Directory removed.

### Issue template (1 file)
- `.github/ISSUE_TEMPLATE/prd_template.md` — DELETED (PRD flow now goes via `architecture-review-prd` skill → `docs/prds/`)

## Repo-level edits

- `CLAUDE.md` — removed `## Workflow` section (lines 46–55).
- `docs/COMMANDS.md` — removed `## Workflow Commands` section (lines 63–70).
- `.github/ISSUE_TEMPLATE/feature_request.md` — removed `status:new` label and P0–P3 boilerplate.
- `.github/ISSUE_TEMPLATE/bug_report.md` — removed `status:new` label and P0–P3 boilerplate.

## Repo-level kept

- `.claude/skills/architecture-review-prd/` — active skill, source of recent PRDs at `docs/prds/`.
- `.claude/agents/github-actions-issue-manager.md` — standalone CI/CD analysis agent, no workflow dependency.
- `.claude/session_notes/` — historical July 2025 notes (not infrastructure).
- `.claude/settings.local.json` — Claude Code config. Contains permissions for now-dead scripts (`./scripts/board-automation.sh`, `./scripts/set-stage.sh`, `./scripts/validate-setup.sh`) that were never present in the repo. Permissions are dead but harmless; left alone (re-curating settings is a separate concern handled by the `update-config` skill).

## User-level deletions

- `~/.claude/commands/eod.md` — DELETED (older variant, predated even the repo workflow).
- `~/.claude/commands/getissues.md` — [DELETED / KEPT] (decision recorded after Task 9 verification).
- `~/.claude/agents/` — did not exist; no action.
- `~/.claude/skills/schwerdtfeger-design/` — KEPT (per issue body).

## Backup location

`~/.claude/backups/prune-2026-05-02/` — full copy of every deleted file. Restore with:

```bash
# Restore everything (repo files):
cp -a ~/.claude/backups/prune-2026-05-02/repo/.claude .
cp -a ~/.claude/backups/prune-2026-05-02/repo/.github .
cp ~/.claude/backups/prune-2026-05-02/repo/CLAUDE.md ./CLAUDE.md
cp ~/.claude/backups/prune-2026-05-02/repo/docs/COMMANDS.md docs/COMMANDS.md

# Restore user-level:
cp -a ~/.claude/backups/prune-2026-05-02/user/. ~/.claude/
```

## Stale artifacts flagged for follow-up (NOT deleted in this plan)

These contradict the current architecture or are unrelated clutter; they need their own issue rather than expanding this one mid-flight:

- Root-level: `EOD_SUMMARY.md`, `PRD_ISSUE_1_monolithic_deployment.md`, `.github/issues/issue-31.md`
- Root-level analysis dumps: `DEPENDENCY_ANALYSIS.md`, `FUNCTION_ANALYSIS.md`, `MATCH_PROCESSING_ANALYSIS.md`, `RUST_INTEGRATION.md`, `RUST_RNG_FIX_RESULTS.md`, `test_failure_analysis.md`, `TEST_RESULTS_SUMMARY.md`, `UNIT_TEST_SUMMARY.md`, `api_documentation.md`
- Tracked build logs: `build.log` (700KB), `build2.log` (850KB)
- `docs/COMMANDS.md` after the Workflow section is removed: mostly duplicates `CLAUDE.md` Quick Commands; consider merging.

Captured as follow-up issue (see Task 11).
```

- [ ] **Step 3: Commit the result document**

```bash
git add docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md
git commit -m "docs(#75): pre-prune inventory of .claude/ workflow tooling"
```

---

### Task 2: Stage the backups (repo-level + user-level scaffolding)

**Files:**
- Create: `~/.claude/backups/prune-2026-05-02/repo/`
- Create: `~/.claude/backups/prune-2026-05-02/user/commands/`

Mirror the directory structure now so subsequent tasks can `cp -a` into a known location instead of re-creating dirs each time.

- [ ] **Step 1: Create backup directory tree**

```bash
mkdir -p ~/.claude/backups/prune-2026-05-02/repo/.claude/commands
mkdir -p ~/.claude/backups/prune-2026-05-02/repo/.claude/agents
mkdir -p ~/.claude/backups/prune-2026-05-02/repo/.claude/session_notes
mkdir -p ~/.claude/backups/prune-2026-05-02/repo/.github/ISSUE_TEMPLATE
mkdir -p ~/.claude/backups/prune-2026-05-02/repo/docs
mkdir -p ~/.claude/backups/prune-2026-05-02/user/commands
```

Run: `find ~/.claude/backups/prune-2026-05-02 -type d`
Expected: shows the six directories plus the parent.

---

### Task 3: Back up and delete `.claude/workflow.md`, `.claude/CLAUDE.md`, `.claude/development_workflow.md`, `.claude/project_context.md`, `.claude/testing_and_build.md`

**Files:**
- Backup → `~/.claude/backups/prune-2026-05-02/repo/.claude/`
- Delete: `.claude/workflow.md`, `.claude/CLAUDE.md`, `.claude/development_workflow.md`, `.claude/project_context.md`, `.claude/testing_and_build.md`

- [ ] **Step 1: Copy the five files to the backup**

```bash
cp -a .claude/workflow.md .claude/CLAUDE.md .claude/development_workflow.md .claude/project_context.md .claude/testing_and_build.md ~/.claude/backups/prune-2026-05-02/repo/.claude/
```

Run: `ls ~/.claude/backups/prune-2026-05-02/repo/.claude/`
Expected: all five filenames present.

- [ ] **Step 2: Verify the backup matches the originals**

```bash
diff -q .claude/workflow.md ~/.claude/backups/prune-2026-05-02/repo/.claude/workflow.md
diff -q .claude/CLAUDE.md ~/.claude/backups/prune-2026-05-02/repo/.claude/CLAUDE.md
diff -q .claude/development_workflow.md ~/.claude/backups/prune-2026-05-02/repo/.claude/development_workflow.md
diff -q .claude/project_context.md ~/.claude/backups/prune-2026-05-02/repo/.claude/project_context.md
diff -q .claude/testing_and_build.md ~/.claude/backups/prune-2026-05-02/repo/.claude/testing_and_build.md
```

Expected: no output for any of the five (files identical).

- [ ] **Step 3: Delete via git**

```bash
git rm .claude/workflow.md .claude/CLAUDE.md .claude/development_workflow.md .claude/project_context.md .claude/testing_and_build.md
```

Expected: git reports 5 files removed.

- [ ] **Step 4: Verify the kept items are untouched**

```bash
ls .claude/
```

Expected output (order may vary): `agents`, `commands`, `scheduled_tasks.lock`, `session_notes`, `settings.local.json`, `skills`. **No** `CLAUDE.md`, `development_workflow.md`, `project_context.md`, `testing_and_build.md`, `workflow.md`.

- [ ] **Step 5: Commit**

```bash
git commit -m "chore(#75): retire home-grown workflow docs in .claude/

Removes .claude/workflow.md, .claude/CLAUDE.md (duplicate workflow spec),
.claude/development_workflow.md, .claude/project_context.md (outdated
microservices architecture description), and .claude/testing_and_build.md
(superseded by docs/TEST_ORGANIZATION.md). The superpowers:* plugin and the
architecture-review-prd skill cover the same territory."
```

---

### Task 4: Back up and delete the entire `.claude/commands/` directory

**Files:**
- Backup → `~/.claude/backups/prune-2026-05-02/repo/.claude/commands/`
- Delete: `.claude/commands/` (19 files + directory)

- [ ] **Step 1: Copy the directory to the backup**

```bash
cp -a .claude/commands/. ~/.claude/backups/prune-2026-05-02/repo/.claude/commands/
```

Run: `ls ~/.claude/backups/prune-2026-05-02/repo/.claude/commands/ | wc -l`
Expected: `19`.

- [ ] **Step 2: Verify a couple of the backed-up files match**

```bash
diff -q .claude/commands/makeprogress.md ~/.claude/backups/prune-2026-05-02/repo/.claude/commands/makeprogress.md
diff -q .claude/commands/newissue.md ~/.claude/backups/prune-2026-05-02/repo/.claude/commands/newissue.md
```

Expected: no output for either.

- [ ] **Step 3: Remove via git**

```bash
git rm -r .claude/commands
```

Expected: git reports 19 files removed.

- [ ] **Step 4: Verify the directory is gone**

Run: `ls .claude/commands/ 2>&1`
Expected: `ls: .claude/commands/: No such file or directory`

- [ ] **Step 5: Commit**

```bash
git commit -m "chore(#75): remove .claude/commands/ — workflow command set

Deletes the 19 home-grown workflow commands (/newissue, /makeprogress,
/eod, /list_human_todo, /approve_issue, /reject_issue, /analyze, /plan,
/implement, /review, /createpr, /writetest, /meta-plan, /setup-board,
/setup-environment, /cleanup-branches, /branch-status, /commit-progress,
/parallel). Replaced by superpowers:* plugin commands."
```

---

### Task 5: Edit `CLAUDE.md` to remove the Workflow section

**Files:**
- Backup → `~/.claude/backups/prune-2026-05-02/repo/CLAUDE.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Back up the file**

```bash
cp -a CLAUDE.md ~/.claude/backups/prune-2026-05-02/repo/CLAUDE.md
diff -q CLAUDE.md ~/.claude/backups/prune-2026-05-02/repo/CLAUDE.md
```

Expected: no output.

- [ ] **Step 2: Remove the Workflow section**

Use the Edit tool to replace the following block with an empty string (i.e., delete it). Match exactly, including the leading and trailing blank line context to keep the surrounding `## Current Status` heading anchored:

`old_string`:
```
## Workflow

This project uses the Claude Code development workflow with human approval gates.

Key commands:
- `/newissue` - Create GitHub issue
- `/makeprogress` - Advance issue through workflow
- `/list_human_todo` - Show issues awaiting review

For complete workflow documentation, see @.claude/workflow.md

## Current Status
```

`new_string`:
```
## Current Status
```

- [ ] **Step 3: Verify**

```bash
grep -c "Workflow\|/makeprogress\|workflow.md" CLAUDE.md
```

Expected: `0` (no remaining workflow references).

```bash
grep -c "## Current Status\|## Architecture" CLAUDE.md
```

Expected: `2` (both surrounding sections still present).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(#75): remove Workflow section from CLAUDE.md

The home-grown 11-stage workflow has been retired; superpowers:* covers
the same territory."
```

---

### Task 6: Edit `docs/COMMANDS.md` to remove the Workflow Commands section

**Files:**
- Backup → `~/.claude/backups/prune-2026-05-02/repo/docs/COMMANDS.md`
- Modify: `docs/COMMANDS.md`

- [ ] **Step 1: Back up the file**

```bash
cp -a docs/COMMANDS.md ~/.claude/backups/prune-2026-05-02/repo/docs/COMMANDS.md
diff -q docs/COMMANDS.md ~/.claude/backups/prune-2026-05-02/repo/docs/COMMANDS.md
```

Expected: no output.

- [ ] **Step 2: Remove the Workflow Commands section**

Use the Edit tool. Match starting from `## Workflow Commands` to end of file. Replace with empty string. The exact text to match (verify line numbers with `tail -10 docs/COMMANDS.md` first if needed):

`old_string`:
```
## Workflow Commands

For detailed workflow commands, see `.claude/workflow.md`. Key commands:
- `/newissue` - Create GitHub issue
- `/makeprogress` - Advance issue through workflow
- `/analyze` - Technical analysis
- `/plan` - Implementation planning
- `/implement` - Code implementation
```

`new_string`: (empty string — section removed)

- [ ] **Step 3: Verify**

```bash
grep -c "Workflow Commands\|/makeprogress\|workflow.md" docs/COMMANDS.md
```

Expected: `0`.

```bash
tail -5 docs/COMMANDS.md
```

Expected: shows the season-transition non-interactive command, not the deleted workflow section.

- [ ] **Step 4: Commit**

```bash
git add docs/COMMANDS.md
git commit -m "docs(#75): remove Workflow Commands section from COMMANDS.md"
```

---

### Task 7: Clean `.github/ISSUE_TEMPLATE/`

**Files:**
- Backup → `~/.claude/backups/prune-2026-05-02/repo/.github/ISSUE_TEMPLATE/`
- Delete: `.github/ISSUE_TEMPLATE/prd_template.md`
- Modify: `.github/ISSUE_TEMPLATE/feature_request.md`, `.github/ISSUE_TEMPLATE/bug_report.md`

- [ ] **Step 1: Back up all three templates**

```bash
cp -a .github/ISSUE_TEMPLATE/. ~/.claude/backups/prune-2026-05-02/repo/.github/ISSUE_TEMPLATE/
ls ~/.claude/backups/prune-2026-05-02/repo/.github/ISSUE_TEMPLATE/
```

Expected: `bug_report.md`, `feature_request.md`, `prd_template.md`.

- [ ] **Step 2: Delete `prd_template.md`**

```bash
git rm .github/ISSUE_TEMPLATE/prd_template.md
```

Expected: git reports 1 file removed.

- [ ] **Step 3: Strip workflow labels and P0–P3 boilerplate from `feature_request.md`**

Use the Edit tool on `.github/ISSUE_TEMPLATE/feature_request.md`. Two replacements:

**Replacement 3a** — frontmatter labels:

`old_string`:
```
labels: 'type:feature, status:new'
```

`new_string`:
```
labels: 'enhancement'
```

**Replacement 3b** — Priority Assessment block:

`old_string`:
```
## Priority Assessment
<!-- Select ONE priority label to add to this issue:
- P0-Critical: System down, data loss risk, or security vulnerability
- P1-High: Major functionality broken, significant user impact  
- P2-Medium: Important features or bugs affecting subset of users
- P3-Low: Nice-to-have improvements, minor issues
-->

## Feature Description
```

`new_string`:
```
## Feature Description
```

- [ ] **Step 4: Same edits on `bug_report.md`**

**Replacement 4a** — frontmatter labels:

`old_string`:
```
labels: 'type:bug, status:new'
```

`new_string`:
```
labels: 'bug'
```

**Replacement 4b** — Priority Assessment block. First read the file to capture the exact wording (the bug template's Priority Assessment block may end with a different heading than the feature template's). Then run:

```bash
grep -A 8 "Priority Assessment" .github/ISSUE_TEMPLATE/bug_report.md
```

Capture the exact text including the heading immediately after the closing `-->`. Then use the Edit tool to delete from `## Priority Assessment` through the closing `-->` and the blank line following, leaving the next heading intact.

- [ ] **Step 5: Verify**

```bash
grep -c "status:\|P0-Critical\|P1-High\|P2-Medium\|P3-Low" .github/ISSUE_TEMPLATE/feature_request.md .github/ISSUE_TEMPLATE/bug_report.md
```

Expected: both files report `0`.

```bash
ls .github/ISSUE_TEMPLATE/
```

Expected: `bug_report.md`, `feature_request.md` (no `prd_template.md`).

- [ ] **Step 6: Commit**

```bash
git add .github/ISSUE_TEMPLATE/
git commit -m "docs(#75): clean issue templates of dead workflow labels

- Delete prd_template.md (PRD flow is now architecture-review-prd skill)
- Remove status:new and P0-P3 boilerplate from feature_request and bug_report
- Replace type:feature/type:bug labels with the standard enhancement/bug"
```

---

### Task 8: Sweep for any remaining repo references to the deleted workflow

**Files:** none (verification only); may re-open Tasks 5/6/7 if hits found.

- [ ] **Step 1: Run a recursive grep**

```bash
grep -rln "workflow\.md\|/makeprogress\|/newissue\|/list_human_todo\|/approve_issue\|/reject_issue\|/setup-board\|/setup-environment\|/meta-plan\|/createpr\|/writetest\|/cleanup-branches\|/branch-status\|/commit-progress\|status:tests_written\|status:plan_written\|tests:approved\|plan:approved\|status:in_depth_analysis\|claude_worktree\|11-column GitHub Projects" . 2>/dev/null \
  | grep -v "^./.git/" \
  | grep -v "^./.claude/plugins/" \
  | grep -v "^./.claude/skills/architecture-review-prd/" \
  | grep -v "^./docs/superpowers/plans/2026-05-02-prune-local-claude-tooling" \
  | grep -v "^./.claude/session_notes/" \
  | grep -v "^./.claude/settings.local.json" \
  | grep -v "/memory/"
```

Expected: empty output. The exclusions above cover:
- The skill we keep (architecture-review-prd's PRD-TEMPLATE references workflow concepts in instructional text — that's fine).
- The plan and result documents (they describe what was removed; references are intentional).
- Session notes (historical, kept).
- `settings.local.json` (left alone per pre-flight observations).
- The `/memory/` directory (auto-memory, contains references to old conversation context).

If the grep returns hits, decide per-file: do we still need that reference? Most likely candidates: `EOD_SUMMARY.md` (root-level workflow output — flagged for follow-up issue, leave alone in this plan), `.github/issues/issue-31.md` (workflow-stage snapshot for closed issue — flagged for follow-up, leave alone), `.github/CONTRIBUTING.md` (already verified workflow-free).

- [ ] **Step 2: Confirm `.github/CONTRIBUTING.md` has no workflow refs**

```bash
grep -n "workflow.md\|/makeprogress\|/newissue\|status:new\|tests:approved\|claude_worktree" .github/CONTRIBUTING.md 2>&1
```

Expected: empty (already verified during inventory; this is a sanity check).

- [ ] **Step 3: Update the result document**

Edit `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md`. Add a new section before "Stale artifacts flagged for follow-up":

```markdown
## Sweep verification

After Tasks 3–7, the recursive grep for the old workflow's vocabulary returned [N hits / no hits] in non-excluded files. [List any hits found and whether they were addressed in an extra commit, or deferred to the follow-up issue.]
```

No commit yet — this section gets committed together with the user-level results in Task 10.

---

### Task 9: User-level prune (`~/.claude/commands/`)

**Files:**
- Backup → `~/.claude/backups/prune-2026-05-02/user/commands/`
- Delete: `~/.claude/commands/eod.md`
- Delete (conditional): `~/.claude/commands/getissues.md`

- [ ] **Step 1: Back up both files**

```bash
cp -a ~/.claude/commands/eod.md ~/.claude/backups/prune-2026-05-02/user/commands/eod.md
cp -a ~/.claude/commands/getissues.md ~/.claude/backups/prune-2026-05-02/user/commands/getissues.md
diff -q ~/.claude/commands/eod.md ~/.claude/backups/prune-2026-05-02/user/commands/eod.md
diff -q ~/.claude/commands/getissues.md ~/.claude/backups/prune-2026-05-02/user/commands/getissues.md
```

Expected: no diff output for either.

- [ ] **Step 2: Delete the user-level `eod.md`**

```bash
rm ~/.claude/commands/eod.md
ls ~/.claude/commands/eod.md 2>&1
```

Expected: `ls: ...: No such file or directory`.

- [ ] **Step 3: Check whether `getissues.md` is referenced by other projects**

```bash
grep -rl "/getissues" ~/.claude/projects 2>/dev/null | head -10
grep -rl "getissues" ~/Library/CloudStorage/Dropbox/Coding\ Projects 2>/dev/null \
  | grep -v "/League-Simulator-Update/" \
  | grep -v "\.claude/projects" \
  | head -10
```

Expected: probably empty. Hits in `~/.claude/projects/` are session-history logs and don't count as "in use." Hits in another project's source tree (e.g., a `.claude/commands/getissues.md` in a sibling repo) **do** count and should block deletion.

- [ ] **Step 4: Decide and act**

If Step 3 returned no real users:

```bash
rm ~/.claude/commands/getissues.md
ls ~/.claude/commands/ 2>&1
```

Expected: empty directory or "No such file or directory" if zsh removes empty dirs (it doesn't by default — empty dir is fine).

If Step 3 returned a real user, leave the file. Either way, update `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md` under "User-level deletions" with the actual decision.

- [ ] **Step 5: Verify the kept items are untouched**

```bash
ls ~/.claude/skills/
ls -la ~/.claude/agents/ 2>&1
```

Expected:
- `~/.claude/skills/` shows `schwerdtfeger-design`.
- `~/.claude/agents/` does not exist (or is empty).

---

### Task 10: Write `docs/REMOVE_SHELL_ALIASES.md`

**Files:**
- Create: `docs/REMOVE_SHELL_ALIASES.md`

This file does not delete the aliases — only documents what to remove and where to look. The user has asked for the document, not the action; the action lives in their shell rc which they will edit themselves.

- [ ] **Step 1: Write the file**

Use the Write tool to create `docs/REMOVE_SHELL_ALIASES.md` with this content:

```markdown
# Shell aliases to remove

The retired `.claude/` workflow installed a set of zsh aliases (per the now-deleted `.claude/workflow.md`). They are still in your shell rc and now point to commands that no longer exist.

## What to remove

Look for these in `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.bashrc`, or any sourced file:

### Aliases (11)

```sh
alias cni="claude /newissue"
alias cmp="claude /makeprogress"
alias cht="claude /list_human_todo"
alias cap="claude /approve_issue"
alias crj="claude /reject_issue"
alias cplan="claude /meta-plan"
alias ceod="claude /eod"
alias cpar="claude /parallel"
alias cws="claude_worktree_status"
alias cwc="claude_worktree_cleanup"
alias cwn="claude_worktree_create"
```

### Functions (typically named, defined in the same file)

- `claude_worktree_create`
- `claude_worktree_status`
- `claude_worktree_cleanup`

### Setup-script artifact

If a previous setup ran a `claude-code-setup` install script, look in:
- `~/.claude-code-setup/` (if the directory exists, review and remove)
- Any sourced shell-rc snippet referencing `claude-code-setup`

## How to find them

```bash
grep -nE "claude_worktree|claude /(newissue|makeprogress|list_human_todo|approve_issue|reject_issue|meta-plan|eod|parallel)|alias c(ni|mp|ht|ap|rj|plan|eod|par|ws|wc|wn)=" ~/.zshrc ~/.zshenv ~/.zprofile ~/.bashrc 2>/dev/null
```

## How to remove them

Edit each rc file by hand, delete the matching lines, save, then `source ~/.zshrc` (or open a new shell) to confirm the aliases are gone:

```bash
type cni 2>&1
# expected: "cni not found"
```

## Why this is a manual step

The repo can't safely edit your shell rc — too many ways to corrupt a profile. This doc is the checklist; the edit is yours.

## Related

- Issue #75 — the removal of the in-repo workflow tooling these aliases were paired with.
- The result record at `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md` lists everything else that was removed.
```

- [ ] **Step 2: Append the user-level results to the result document**

Edit `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md`:
- Update the "User-level deletions" section so `getissues.md` shows the actual final decision (DELETED or KEPT, with reason).
- Update the "Backup location" section if Step 4 of Task 9 left `getissues.md` in place — note "(only `eod.md` removed)".
- Confirm the "Sweep verification" subsection from Task 8 is filled in.

- [ ] **Step 3: Commit**

```bash
git add docs/REMOVE_SHELL_ALIASES.md docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md
git commit -m "docs(#75): add shell-alias removal checklist + final prune record"
```

---

### Task 11: Open a follow-up issue for the stale-artifact backlog

**Files:** none (uses `gh`).

The pre-flight observations and Task 8's sweep flagged repo-root clutter that contradicts the current architecture but is not workflow-related. Capturing it as a fresh issue keeps this plan's scope honest.

- [ ] **Step 1: Open the follow-up issue**

```bash
gh issue create --title "Cleanup: prune stale repo-root analysis dumps and tracked build logs" --body "$(cat <<'EOF'
**Reminder issue from the workflow-tooling cleanup (#75).**

While auditing `.claude/` for #75, the following root-level files surfaced as candidates for removal — they're not workflow-related, so they were left out of #75's scope.

## Tracked artifacts that contradict current architecture
- `PRD_ISSUE_1_monolithic_deployment.md` — proposes the rejected microservices design; directly contradicts `docs/deployment/README.md` (which is the canonical deployment doc).
- `EOD_SUMMARY.md` — output from the now-deleted `/eod` command; describes events from January 2025.
- `.github/issues/issue-31.md` — frozen snapshot of a closed issue's workflow-stage tracking with dead labels (`status:plan_written`, `tests:approved`).

## Tracked analysis dumps (consider deleting or moving to docs/archive/)
- `DEPENDENCY_ANALYSIS.md`
- `FUNCTION_ANALYSIS.md`
- `MATCH_PROCESSING_ANALYSIS.md`
- `RUST_INTEGRATION.md`
- `RUST_RNG_FIX_RESULTS.md`
- `test_failure_analysis.md`
- `TEST_RESULTS_SUMMARY.md`
- `UNIT_TEST_SUMMARY.md`
- `api_documentation.md`

## Tracked build logs (should not be in git)
- `build.log` (~700 KB)
- `build2.log` (~850 KB)

## Documentation that became thin after #75
- `docs/COMMANDS.md` after the Workflow Commands section was removed (#75 Task 6) is mostly a thin shadow of canonical sources (`CLAUDE.md` Quick Commands, `scripts/season_transition.R --help`, `docker-compose.yml`). Consider merging into `CLAUDE.md` and deleting.

## Why later
This is repo hygiene. None of it blocks production. Tracked separately so #75 stays focused on the workflow tooling.
EOF
)"
```

Expected: `gh` returns the new issue URL. Note the issue number in the result document.

- [ ] **Step 2: Note the follow-up in the result document**

Edit `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md`. Replace the parenthetical at the end of "Stale artifacts flagged for follow-up" with the actual issue number from Step 1: `Captured as follow-up issue #N.`

- [ ] **Step 3: Commit and push**

```bash
git add docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md
git commit -m "docs(#75): record follow-up issue for repo-root clutter"
git push
```

---

### Task 12: Final verification and issue close

**Files:** verification only.

- [ ] **Step 1: Confirm `.claude/` matches expectations**

```bash
git ls-files .claude/
```

Expected output (exact):
```
.claude/agents/github-actions-issue-manager.md
.claude/session_notes/.gitkeep
.claude/session_notes/2025-07-15.md
.claude/session_notes/2025-07-16.md
.claude/session_notes/2025-07-18.md
.claude/session_notes/2025-07-19.md
.claude/skills/architecture-review-prd/SKILL.md
.claude/skills/architecture-review-prd/references/PRD-TEMPLATE.md
```

Plus `.claude/settings.local.json` (untracked — verify with `ls .claude/settings.local.json`).

If extra files appear, investigate before closing.

- [ ] **Step 2: Confirm `.github/ISSUE_TEMPLATE/` is clean**

```bash
ls .github/ISSUE_TEMPLATE/
grep -c "status:\|P0-Critical\|P1-High\|P2-Medium\|P3-Low" .github/ISSUE_TEMPLATE/*.md
```

Expected: two files (`bug_report.md`, `feature_request.md`); grep returns `0` for each (or `0` total if the shell concatenates).

- [ ] **Step 3: Confirm CLAUDE.md and docs/COMMANDS.md are clean**

```bash
grep -c "Workflow\|/makeprogress\|workflow.md" CLAUDE.md docs/COMMANDS.md
```

Expected: both files report `0`.

- [ ] **Step 4: Confirm user-level state**

```bash
ls ~/.claude/skills/ ~/.claude/commands/
```

Expected: skills dir contains `schwerdtfeger-design` only; commands dir is empty (or contains only `getissues.md` if Task 9 kept it).

- [ ] **Step 5: Confirm backup is intact and complete**

```bash
find ~/.claude/backups/prune-2026-05-02 -type f | sort
```

Expected: contains all 30 deleted/edited files (5 workflow docs + 19 commands + 1 prd_template + originals of CLAUDE.md, docs/COMMANDS.md, both modified ISSUE_TEMPLATE files + 1 or 2 user-level files).

- [ ] **Step 6: Close the issue with a summary comment**

```bash
gh issue comment 75 --body "$(cat <<'EOF'
Cleanup complete. Scope evolved during execution: the original issue targeted user-level `~/.claude/` tooling, but the work expanded (with confirmation) to also retire the home-grown 11-stage workflow at the repo level. Replaced by `superpowers:*` plus the `architecture-review-prd` skill.

## Repo-level
- Deleted: `.claude/workflow.md`, `.claude/CLAUDE.md`, `.claude/development_workflow.md`, `.claude/project_context.md`, `.claude/testing_and_build.md`, the entire `.claude/commands/` directory (19 files), `.github/ISSUE_TEMPLATE/prd_template.md`
- Edited: `CLAUDE.md` (removed Workflow section), `docs/COMMANDS.md` (removed Workflow Commands section), `.github/ISSUE_TEMPLATE/feature_request.md` and `.github/ISSUE_TEMPLATE/bug_report.md` (removed dead labels and P0–P3 boilerplate)
- Kept: `.claude/skills/architecture-review-prd/`, `.claude/agents/github-actions-issue-manager.md`, `.claude/session_notes/`, `.claude/settings.local.json`

## User-level
- Deleted: `~/.claude/commands/eod.md` (always), `~/.claude/commands/getissues.md` (if no other project depended on it)
- Kept: `~/.claude/skills/schwerdtfeger-design/`

## Shell aliases
A checklist for the user to remove the 11 zsh aliases and 3 helper functions lives at `docs/REMOVE_SHELL_ALIASES.md`.

## Backup
`~/.claude/backups/prune-2026-05-02/` — full mirror of every removed file.

## Follow-up
Issue [#N from Task 11] tracks the remaining root-level analysis-dump and build-log clutter.

Full record: `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md`
EOF
)"
gh issue close 75
```

Expected: comment posted, issue moved to Closed.

---

## Self-review

- **Spec coverage.** The original issue (#75) listed: `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/commands/`, `.claude/commands/` (repo). Plus user expansion: retire `.claude/workflow.md` and dependents; remove from `CLAUDE.md`; analyse repo for further superpowers-contradicting artifacts; document shell-alias removal. Tasks 1–12 cover every item. The "must keep" items (architecture-review-prd skill, schwerdtfeger-design skill, superpowers plugin) are explicitly preserved by Tasks 8/12 verification.

- **Placeholder scan.** Every step has either a literal command, a literal `old_string`/`new_string` for an edit, or a literal grep with expected output. Task 7 Step 4b deliberately requires reading the file at execution time before editing because the bug template's exact wording wasn't captured during plan-writing — that's not a placeholder, it's a real "verify-then-edit" pattern.

- **Type/path consistency.** The backup root `~/.claude/backups/prune-2026-05-02/` is referenced consistently across Tasks 2–10 and the result-doc template. Repo files mirror under `repo/` and user-level under `user/`. The result document is `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md` everywhere.

- **One asymmetry to flag for the operator.** Task 8's exclusion list includes `/memory/` because the auto-memory directory may contain references to old conversation context that mention deleted commands; that's expected and not a hit worth chasing. Likewise `.claude/session_notes/` is excluded because the July 2025 notes legitimately describe the workflow as it was at the time.
