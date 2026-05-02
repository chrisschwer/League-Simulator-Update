# Docs cleanup — remove references to deleted Dockerfiles and microservices stack

**Issue:** [#79](https://github.com/chrisschwer/League-Simulator-Update/issues/79)
**Date:** 2026-05-02
**Status:** design approved, awaiting implementation plan

## Goal

Eliminate documentation that contradicts the post-#78 single-container deployment. After this work, a six-month-old you (or a new contributor) can clone the repo, follow the docs, and successfully deploy or run locally without finding references to deleted Dockerfiles, the rejected k8s/microservices design, or scheduler variants that no longer exist. Doc surface around deployment drops from ~2,800 lines to ~450 lines of operationally-real content.

## Non-goals

- **Out of scope:** any change inside `RCode/`, `scripts/`, `Dockerfile`, `docker-compose.yml`, `docker-start.sh`, `tests/testthat/`, `.github/workflows/`, or the Rust crate.
- **Out of scope:** authoring a new CI workflow (issue #76).
- **Out of scope:** triaging `docs/DOCUMENTATION_KUBERNETES.md` and `docs/DOCUMENTATION_DOCKER.md`. They aren't in #79's grep and aren't directly stale; they describe technologies, not the project's specific deployment. Flagged here so a future cleanup remembers them.
- **Out of scope:** the four repo-root historical PRDs (`PRD_ISSUE_1_*`, `EOD_SUMMARY.md`, etc.) — already handled by #81.
- **Out of scope:** `docs/architecture/microservices.md`, `docs/architecture/pod-lifecycle-management.md`, `docs/operations/ci-monitoring.md`. These are also stale but the user chose scope **B** (issue body + repo-root README), not **C** (everything stale). Track for a future pass.

## Coordination with other in-flight work

- **Test-suite cleanup (parallel session):** zero file overlap. Test-cleanup touches `tests/testthat/`; this issue touches `tests/docker/`, `tests/REVISED_TEST_SPECIFICATIONS.md`, `tests/container-league.yaml` — different subdirectories of `tests/`.
- **#76 (CI rebuild, blocked):** complementary. Deleting `ci-cd-guide.md` here means #76 can write fresh CI documentation from scratch instead of editing a stale one.
- **#73 (refactor `process_league_teams`):** zero overlap.

## Decisions (with rationale)

| Decision | Choice | Rationale |
|---|---|---|
| Strategy across the 11 candidate surfaces | Aggressive deletion + rewrite of the 4 operationally-essential docs (option A from brainstorm) | Deletes documentation that's wrong; preserves what an operator with a 6-month memory gap needs. |
| Hobbyist project = thin docs? | No — hobbyist + memory-gap argues for *correct* operational docs, not no docs | The user explicitly course-corrected: "I have to be able to deploy it if I forget how it works." |
| Rewrite content sourcing | Inference for high-confidence files; `[YOUR INPUT]` placeholders for habit-dependent files (option C from brainstorm) | High-confidence files derive from `docs/deployment/README.md`. Habit-dependent files (`local-development.md`, repo `README.md`) need the user's actual workflow. |
| Branch shape | One branch, ~7 commits, one PR | Each commit is independently revertable. Five commits are pure deletions or low-decision rewrites; two commits (5 and 6) pause for `[YOUR INPUT]`. |
| Doc index updates | In scope — `docs/README.md` link updates ride with the deletion commits | The deletions create dangling links; fixing them is the same edit. |

## Inventory

### Pure deletions (8 files + 1 directory)

| Path | Lines / Size | Why delete |
|---|---|---|
| `docs/deployment/detailed-guide.md` | 324 | Comprehensive multi-stack deploy guide; replaced by `docs/deployment/README.md` + `quick-start.md` |
| `docs/deployment/production.md` | 573 | "Enterprise-grade" HA/DR/security content for a one-container hobbyist deploy — fictional |
| `docs/deployment/simplified-microservices.md` | 260 | Describes the rejected two-service architecture |
| `docs/deployment/ci-cd-guide.md` | 418 | Describes a CI/CD pipeline that doesn't exist (all workflows are `*.disabled`); #76 will write a fresh one |
| `tests/REVISED_TEST_SPECIFICATIONS.md` | ~21 KB | Revised testing approach for the deleted multi-Dockerfile world |
| `tests/container-league.yaml` | ~1.7 KB | k8s manifest fragment; the `k8s/` directory it served is gone (deleted in #78) |
| `tests/docker/` (8 files) | ~32 KB | Tests for `Dockerfile.league.optimized`, `Dockerfile.shiny`, etc. — all deleted in #78 |

`tests/docker/` contents:
- `container-structure-test-packages.yaml`
- `container-structure-test-security.yaml`
- `run_all_tests.sh`
- `test_docker_optimization.md`
- `test_image_size.sh`
- `test_multistage_build.sh`
- `test_results.md`
- `verify_implementation.sh`

### Rewrites (4 files)

| Path | Current size | Target size | Confidence | Notes |
|---|---|---|---|---|
| `docs/deployment/quick-start.md` | 90 lines | ~50–80 lines | High | Inference from `docs/deployment/README.md`. New content: clone, set `.env`, `docker-compose up -d`, verify via `localhost:8081/health`. |
| `docs/deployment/rollback.md` | 451 lines | ~50–70 lines | High | Inference + the `pre-deployment-cleanup-2026-05-02` git tag. New content: `docker-compose down`, pull/checkout previous tag, `docker-compose up -d`. |
| `docs/deployment/local-development.md` | 447 lines | ~150 lines | Medium | Habit-dependent: pauses execution to ask the user 3 specific questions before drafting. |
| `README.md` (repo root) | 9.2 KB | ~80–120 lines | Medium | Habit-dependent: pauses execution to ask about ShinyApps URL inclusion, blog mention, screenshot/badge. |

### Untouched

- `docs/deployment/README.md` — already canonical, accurate, 67 lines
- `docs/README.md` — modified only to drop dangling links from deleted files (covered as part of bucket-1 deletion commits)

### `[YOUR INPUT]` resolution points

During execution, the brainstorm pauses to ask:

**For `local-development.md`:**
1. Do you typically run the scheduler outside Docker for local dev (`Rscript RCode/updateScheduler.R`), or only the simulation engine and Shiny app?
2. Do you build the Rust binary locally (`cargo build` in `league-simulator-rust/`) or rely on the Docker image's stage 1?
3. Anything else about your local-dev workflow worth documenting?

**For repo-root `README.md`:**
1. Should it link to the live ShinyApps.io URL? If yes, what URL?
2. Should it mention the blog *30 Punkte*? If yes, with what link?
3. Do you want a screenshot/CI-badge/Docker-pulls badge, or keep it minimal?

These are asked during the corresponding commit, not before, so the user is staring at a draft when answering rather than answering in the abstract.

## Design

### Branch + commit shape

Branch: `feature/issue-79-docs-cleanup` off `main` via `superpowers:using-git-worktrees`.

Seven commits:

1. **`chore(#79): delete fictional deployment docs`**
   `git rm docs/deployment/{detailed-guide,production,simplified-microservices,ci-cd-guide}.md`

2. **`chore(#79): delete tests/docker/ and stale k8s manifests`**
   `git rm -r tests/docker/`
   `git rm tests/REVISED_TEST_SPECIFICATIONS.md tests/container-league.yaml`

3. **`docs(#79): update docs/README.md links`**
   Edit `docs/README.md`'s `## 🚀 Deployment` section to drop `detailed-guide.md`, `production.md`, `simplified-microservices.md` links. Keep links to `quick-start.md`, `local-development.md`, `rollback.md`. Add `README.md` (post-#78) as primary entry.

4. **`docs(#79): rewrite quick-start guide for single-container stack`**
   Replace `docs/deployment/quick-start.md` with ~50–80 lines describing the actual deploy: prereqs, clone, `.env` template, `docker-compose up -d`, verify, troubleshooting quick-fixes pointing at `docker-compose logs`.

5. **`docs(#79): rewrite rollback guide for current stack`**
   Replace `docs/deployment/rollback.md` with ~50–70 lines describing real rollback: `docker-compose down`, choose previous image tag or git ref, `docker-compose up -d`. Reference the `pre-deployment-cleanup-2026-05-02` tag for the pre-cleanup tree.

6. **`docs(#79): rewrite local-development guide`** *(pauses for `[YOUR INPUT]`)*
   Resolve the 3 local-dev questions, then rewrite `docs/deployment/local-development.md` to ~150 lines: install R + system deps, install packages from `packagelist.txt`, run testthat, run Shiny via `shiny::runApp("ShinyApp/app.R")`, run scheduler outside Docker (or note "use Docker locally"), where Rust fits in.

7. **`docs(#79): rewrite repo-root README`** *(pauses for `[YOUR INPUT]`)*
   Resolve the 3 README questions, then rewrite `README.md` to ~80–120 lines: project description, what the system does, how it works (3-bullet architecture), deploy via link to `docs/deployment/README.md`, operate via link to `CLAUDE.md` Quick Commands, season-transition via link to `docs/user-guide/season-transition.md`. Optional: ShinyApps link, blog link, screenshot.

PR closes #79.

### File-by-file pre-execution skim

Before commit 1 lands, the worktree skims each delete target for a 30-second judgment of "is there a section worth saving?" Specifically:

- **`production.md`** — contains an "Environment Variables" section. Cross-check against `docs/deployment/README.md`'s env table. If `production.md` has any env var the canonical doc doesn't list, add an extra commit between commits 1 and 2 (`docs(#79): backfill env vars into deployment/README.md`) that patches `docs/deployment/README.md`. If everything's already there, delete clean and the commit count stays at 7.
- **`detailed-guide.md`** — likely has a "System Requirements" section. Same check: if requirements aren't elsewhere, capture them.
- **`local-development.md`** (before rewrite, not delete) — read in full so the rewrite preserves any genuinely operationally-real bits (e.g., a debug invocation that's useful but undocumented elsewhere).
- **`rollback.md`** (same) — read in full before rewrite.

This skim doesn't add a commit; findings ride into the appropriate existing commit.

## Verification

After the branch lands, all of these must hold:

```bash
# (1) Canonical inbound-reference grep returns no actionable hits
grep -rEn "Dockerfile\.(simple|league|shiny|optimized|integrated|test)|docker-compose\.(simple|integrated)|updateSchedulerRust|updateSchedulerSimple|update_all_leagues_loop_rust|docker-integrated-start" \
  --include="*.md" --include="*.yml" --include="*.yaml" --include="*.sh" . 2>/dev/null \
  | grep -v "^./.git/" \
  | grep -v "^./.worktrees/" \
  | grep -v "^./removed/" \
  | grep -vE "^./docs/(prds|superpowers/(plans|specs))/"
# Expect: no output. Hits inside docs/prds/, docs/superpowers/plans/, docs/superpowers/specs/ are intentionally filtered (historical records).

# (2) Deleted files/directory are gone
ls docs/deployment/detailed-guide.md docs/deployment/production.md docs/deployment/simplified-microservices.md docs/deployment/ci-cd-guide.md tests/docker tests/REVISED_TEST_SPECIFICATIONS.md tests/container-league.yaml 2>&1
# Expect: every line says 'No such file or directory'

# (3) Surviving + rewritten docs are clean
for f in docs/deployment/README.md docs/deployment/quick-start.md docs/deployment/local-development.md docs/deployment/rollback.md README.md; do
  echo "=== $f ==="
  grep -nE "Dockerfile\.(simple|league|shiny|optimized|integrated|test)|docker-compose\.(simple|integrated)" "$f" && echo "FAIL" || echo "  clean"
done
# Expect: each file reports 'clean'

# (4) docs/README.md links to the survivors only
grep -nE '\[.*\]\(deployment/' docs/README.md
# Expect: links pointing only to README.md, quick-start.md, local-development.md, rollback.md (and possibly external URLs in the same line)

# (5) Sanity — production source still parses
Rscript -e 'invisible(parse("RCode/updateScheduler.R")); cat("OK\n")'
# Expect: OK
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Deleted doc held unique knowledge | Medium | Pre-execution skim of each delete target; bump file from delete → rewrite if a section is genuinely useful. |
| Rewrite of `local-development.md` misses your actual workflow | Medium | `[YOUR INPUT]` pause — three concrete questions before drafting |
| `README.md` rewrite loses tone or content you valued | Low–Medium | Same `[YOUR INPUT]` mechanism + spec/draft review gates |
| Merge conflict with parallel test-cleanup session | Low | Different subdirectories of `tests/` |
| Stale link from outside the repo (someone bookmarked a deleted doc) | Low | Hobbyist project; few external readers; `git log` recovers content |
| `docs/deployment/README.md` env-var table is incomplete | Low | Pre-execution skim of `production.md` env section catches gaps |

## Recovery

| Action | Recovery path |
|---|---|
| Single deleted doc regretted | `git revert <delete-commit>` (commits 1 or 2) |
| Single rewritten doc regretted | `git log` shows previous version; `git revert` if wholesale, manual port if partial |
| Whole PR regretted | `git revert <merge-commit>` |
| Pre-cleanup state needed | `git checkout pre-deployment-cleanup-2026-05-02` (tag from #78) |

## Estimated effort

- **Commits 1, 2, 3 (deletions + index update):** 30–45 min including the pre-execution skim
- **Commits 4, 5 (`quick-start`, `rollback` rewrites):** 45–60 min
- **Commit 6 (`local-development.md` rewrite, with `[YOUR INPUT]` pause):** 30–45 min once the user's answers arrive
- **Commit 7 (`README.md` rewrite, with `[YOUR INPUT]` pause):** 30–45 min once the user's answers arrive
- **Total:** 2.5–3.5 hours of execution work, plus user response time on the two pauses

## Definition of done

1. PR merged into `main`.
2. Verification check (1) above returns zero hits.
3. Verification check (2) above confirms all 4 deletions + 1 directory + 2 misc files are gone.
4. Verification checks (3), (4), (5) all pass.
5. Six surviving docs (`docs/deployment/README.md`, `quick-start.md`, `local-development.md`, `rollback.md`, repo-root `README.md`, `docs/README.md`) describe only the current single-container stack — no references to `Dockerfile.simple`, `Dockerfile.league`, `Dockerfile.shiny`, `Dockerfile.optimized`, `Dockerfile.integrated`, the k8s/microservices design, `updateSchedulerRust`, or `updateSchedulerSimple`.
