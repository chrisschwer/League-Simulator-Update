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
- `~/.claude/commands/getissues.md` — DELETED. Cross-project usage check (Task 9) found 23 hits in `~/.claude/projects/` (read-only session histories, not active usage) and zero hits in any other project's source tree under `~/Library/CloudStorage/Dropbox/Coding Projects/`.
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

## Sweep verification (Task 8)

After Tasks 3–7, ran the recursive grep for the old workflow's vocabulary across the repo. Hits in non-excluded files:

- `DEPENDENCY_ANALYSIS.md:11` — references `tests:approved, plan:approved` in a status note about issue #31. Already in scope of the follow-up issue (analysis-dump pile), so left alone.
- `.github/issues/issue-31.md` — frozen workflow-stage tracker for closed issue #31; already in scope of the follow-up issue. Left alone.
- `.claude/session_notes/2025-07-15.md`, `2025-07-16.md`, `2025-07-18.md` — historical notes describing live workflow runs at the time. Plan explicitly keeps `.claude/session_notes/`; legitimate historical record.

No live references to the deleted workflow remain in code, docs, or templates. Every hit is either an intentional historical record or already captured in the follow-up issue.

## Stale artifacts flagged for follow-up (NOT deleted in this plan)

These contradict the current architecture or are unrelated clutter; they need their own issue rather than expanding this one mid-flight:

- Root-level: `EOD_SUMMARY.md`, `PRD_ISSUE_1_monolithic_deployment.md`, `.github/issues/issue-31.md`
- Root-level analysis dumps: `DEPENDENCY_ANALYSIS.md`, `FUNCTION_ANALYSIS.md`, `MATCH_PROCESSING_ANALYSIS.md`, `RUST_INTEGRATION.md`, `RUST_RNG_FIX_RESULTS.md`, `test_failure_analysis.md`, `TEST_RESULTS_SUMMARY.md`, `UNIT_TEST_SUMMARY.md`, `api_documentation.md`
- Tracked build logs: `build.log` (700KB), `build2.log` (850KB)
- `docs/COMMANDS.md` after the Workflow section is removed: mostly duplicates `CLAUDE.md` Quick Commands; consider merging.

Captured as follow-up issue **#81** (https://github.com/chrisschwer/League-Simulator-Update/issues/81).

## Operational note

Claude Code loads the available skills/commands at session start. After this prune, the deleted commands (`/newissue`, `/makeprogress`, `/eod`, etc.) will continue to appear in the current session's skill list until the session restarts. They are deleted from disk and will not be re-loaded. Open a new session to see the cleaned list.
