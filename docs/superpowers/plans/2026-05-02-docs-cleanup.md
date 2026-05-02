# Docs Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete 8 files + 1 directory of stale deployment docs and tests, rewrite 4 docs (`docs/deployment/quick-start.md`, `docs/deployment/rollback.md`, `docs/deployment/local-development.md`, repo-root `README.md`) to describe the post-#78 single-container stack, update `docs/README.md` to remove dangling links from this PR's deletions, and verify no source-of-truth doc still references deleted Dockerfiles or the rejected k8s/microservices design.

**Architecture:** One feature branch off `main` via `superpowers:using-git-worktrees`. Eight tasks: pre-flight verification → 7 commits (deletions, doc-index update, four rewrites). Two of the rewrites pause execution to ask the user habit-dependent questions before drafting. Pure documentation work — zero touches to `RCode/`, `scripts/`, `Dockerfile`, `docker-compose.yml`, `tests/testthat/`, or the Rust crate.

**Tech Stack:** git, Markdown editing only. No code, no tests, no R, no Docker run.

**Reference spec:** `docs/superpowers/specs/2026-05-02-docs-cleanup-design.md`

**Coordinates with:** parallel test-cleanup session (zero file overlap — different `tests/` subdirectories), #76 (this work doesn't touch `.github/workflows/`), #73 (no overlap).

---

## File Inventory

### Files deleted (8 + 1 directory)

| Path | Lines / Size |
|---|---|
| `docs/deployment/detailed-guide.md` | 324 |
| `docs/deployment/production.md` | 573 |
| `docs/deployment/simplified-microservices.md` | 260 |
| `docs/deployment/ci-cd-guide.md` | 418 |
| `tests/REVISED_TEST_SPECIFICATIONS.md` | ~21 KB |
| `tests/container-league.yaml` | ~1.7 KB |
| `tests/docker/` (directory, 8 files) | ~32 KB |

### Files rewritten (4)

| Path | Approach |
|---|---|
| `docs/deployment/quick-start.md` | High confidence — full draft below |
| `docs/deployment/rollback.md` | High confidence — full draft below |
| `docs/deployment/local-development.md` | Habit-dependent — pause for `[YOUR INPUT]` then draft |
| `README.md` (repo root) | Habit-dependent — pause for `[YOUR INPUT]` then draft |

### Files modified (1, no rewrite)

| Path | Change |
|---|---|
| `docs/README.md` | Update `## 🚀 Deployment` section to drop links to deleted files; add link to `docs/deployment/README.md` |

### Files NOT touched

`RCode/*`, `scripts/*`, `Dockerfile`, `docker-compose.yml`, `docker-start.sh`, `tests/testthat/*`, `.github/workflows/*`, `docs/architecture/*`, `docs/operations/*`, `docs/troubleshooting/*` (broken links there are pre-existing, out of #79 scope), `docs/user-guide/*`, `docs/DOCUMENTATION_*.md`, `CLAUDE.md`, `docs/deployment/README.md` (already canonical).

---

## Task 1: Pre-flight verification + worktree

**Goal:** Confirm clean tree on `main`, all delete targets present, all rewrite targets present. Create the working branch via `superpowers:using-git-worktrees` (the worktree skill).

**Files:**
- Read-only

- [ ] **Step 1: Confirm clean tree on `main`**

```bash
git status -sb
```

Expected: `## main...origin/main` (or "ahead/behind" if local diverged from origin in benign ways), no staged or modified files. Untracked entries from in-flight planning (`docs/superpowers/plans/...`, `.claude/scheduled_tasks.lock`) are acceptable.

If the tree shows unexpected modifications: STOP and ask the user.

- [ ] **Step 2: Verify all delete targets exist**

```bash
for f in docs/deployment/detailed-guide.md docs/deployment/production.md docs/deployment/simplified-microservices.md docs/deployment/ci-cd-guide.md tests/REVISED_TEST_SPECIFICATIONS.md tests/container-league.yaml; do
  printf "%s\t" "$f"
  test -f "$f" && echo PRESENT || echo MISSING
done
echo "---tests/docker/---"
ls tests/docker/ 2>&1 | head
```

Expected: all 6 files print `PRESENT`. `tests/docker/` lists 8 entries.

- [ ] **Step 3: Verify all rewrite targets exist**

```bash
for f in docs/deployment/quick-start.md docs/deployment/rollback.md docs/deployment/local-development.md README.md docs/README.md docs/deployment/README.md; do
  printf "%s\t" "$f"
  test -f "$f" && echo PRESENT || echo MISSING
done
```

Expected: all 6 print `PRESENT`.

- [ ] **Step 4: Set up worktree via the using-git-worktrees skill**

Invoke `superpowers:using-git-worktrees`. The skill will:
- Find existing `.worktrees/` directory (created during the #81 PR; it's already gitignored).
- Create worktree at `.worktrees/issue-79-docs-cleanup` on new branch `feature/issue-79-docs-cleanup` off `main`.
- Skip the dependency-install + baseline-test step: this is a docs-only PR, no R/Docker code is touched, and the testthat suite has 39 known-failing tests (all in files the parallel test-cleanup branch will delete) that would produce noise rather than signal.

After worktree creation, confirm:

```bash
pwd
git status -sb
```

Expected: working directory ends with `.worktrees/issue-79-docs-cleanup`, branch is `feature/issue-79-docs-cleanup`, clean tree.

---

## Task 2: Pre-execution skim — capture salvageable content from delete targets

**Goal:** Before deleting 4 deployment docs, skim each for sections that contain operationally-real knowledge not duplicated in `docs/deployment/README.md`. The most likely candidate is an env-var listed in `production.md` but not in the canonical doc.

**Files:**
- Read-only (`docs/deployment/production.md`, `docs/deployment/detailed-guide.md`, `docs/deployment/ci-cd-guide.md`, `docs/deployment/simplified-microservices.md`, `docs/deployment/README.md`)

- [ ] **Step 1: Read `docs/deployment/README.md` to refresh the canonical env-var list**

Use the Read tool. Note the exact list of env vars in the table at lines 18–29: `RAPIDAPI_KEY`, `SHINYAPPS_IO_SECRET`, `SHINYAPPS_IO_NAME`, `SHINYAPPS_IO_TOKEN`, `SEASON`, `DURATION`, `RUST_API_URL`, `TZ`. (8 total.)

- [ ] **Step 2: Skim `docs/deployment/production.md` for env vars**

```bash
grep -nE '^\s*-\s*`[A-Z_]+`|^\s*\|\s*`[A-Z_]+`' docs/deployment/production.md
```

If the grep returns env-var names not in the canonical list, copy the variable + purpose into a notes file at `/tmp/issue-79-env-backfill.md`. If it returns nothing or only canonical vars, write `none` into that file.

- [ ] **Step 3: Skim `docs/deployment/detailed-guide.md` similarly**

```bash
grep -nE '^\s*-\s*`[A-Z_]+`|^\s*\|\s*`[A-Z_]+`' docs/deployment/detailed-guide.md
```

Same rule — append any new vars to `/tmp/issue-79-env-backfill.md`.

- [ ] **Step 4: Skim `docs/deployment/ci-cd-guide.md` and `docs/deployment/simplified-microservices.md`**

These are about CI/CD and the rejected microservices design respectively. Env-vars there (`MAX_DAILY_CALLS`, `UPDATE_INTERVAL`, `LEAGUE`) are for code paths that no longer run in production. **Do not backfill them** — they belong to the orphaned microservices scripts in `RCode/` (e.g., `update_league.R`, `league_scheduler.R`) that are out of #79's scope.

- [ ] **Step 5: Decide whether commit 1.5 (env-backfill) is needed**

```bash
cat /tmp/issue-79-env-backfill.md
```

If the file is empty or says `none`: **skip** the conditional commit between commits 1 and 2. The plan's commit count stays at 7.

If the file lists any new vars: between Task 3's commit and Task 4's commit, add an extra commit `docs(#79): backfill env vars into deployment/README.md` that patches `docs/deployment/README.md`'s env table. Use the Edit tool. The plan's commit count becomes 8.

(Most likely outcome: `none`. The canonical doc was hand-written in #78 to be complete.)

---

## Task 3: Commit 1 — delete fictional deployment docs

**Goal:** Remove 4 stale deployment docs.

**Files:**
- Delete: `docs/deployment/detailed-guide.md`
- Delete: `docs/deployment/production.md`
- Delete: `docs/deployment/simplified-microservices.md`
- Delete: `docs/deployment/ci-cd-guide.md`

- [ ] **Step 1: Remove the four files via `git rm`**

```bash
git rm docs/deployment/detailed-guide.md docs/deployment/production.md docs/deployment/simplified-microservices.md docs/deployment/ci-cd-guide.md
```

Expected: four `rm` lines printed.

- [ ] **Step 2: Verify staged deletions**

```bash
git status -s | grep -c '^D '
```

Expected: `4`.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(#79): delete fictional deployment docs

Four docs from July 2025 that describe deployment paths that no longer
exist (multi-Dockerfile, k8s/microservices, blue-green, HA/DR/security
hardening). The single-container production path is documented
canonically in docs/deployment/README.md (added in #78). The replacement
quick-start and rollback rewrites land in subsequent commits.

- detailed-guide.md (324 lines): comprehensive multi-stack guide
- production.md (573 lines): enterprise HA/DR for a one-container deploy
- simplified-microservices.md (260 lines): rejected two-service design
- ci-cd-guide.md (418 lines): describes a CI pipeline that no longer
  exists; #76 will write a fresh one

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Verify the commit landed**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: top commit is `chore(#79): delete fictional deployment docs`, four files deleted with 0 insertions.

---

## Task 4: Commit 2 — delete tests/docker/ and stale k8s manifests

**Goal:** Remove the entire `tests/docker/` directory plus two stale individual files in `tests/`.

**Files:**
- Delete: `tests/docker/` (directory with 8 files)
- Delete: `tests/REVISED_TEST_SPECIFICATIONS.md`
- Delete: `tests/container-league.yaml`

- [ ] **Step 1: Remove `tests/docker/` recursively via `git rm -r`**

```bash
git rm -r tests/docker
```

Expected: 8 `rm` lines (one per file inside the directory).

- [ ] **Step 2: Remove the two individual stale files**

```bash
git rm tests/REVISED_TEST_SPECIFICATIONS.md tests/container-league.yaml
```

Expected: two `rm` lines.

- [ ] **Step 3: Verify staged deletions**

```bash
git status -s | grep -c '^D '
```

Expected: `10` (8 from `tests/docker/` + 2 individual).

- [ ] **Step 4: Verify `tests/testthat/` is untouched**

```bash
ls tests/testthat/ | head
```

Expected: the testthat suite contents (helper-*.R, test-*.R files). This is the parallel session's territory; we must not have stepped on it.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(#79): delete tests/docker/ and stale k8s manifests

tests/docker/ contained tests for Dockerfile.league.optimized,
Dockerfile.shiny, Dockerfile.league, and a multi-stage-build
verification harness — all of which were deleted in #78. The tests
were therefore testing files that no longer exist.

tests/REVISED_TEST_SPECIFICATIONS.md described a revised testing
approach for the deleted multi-Dockerfile world. tests/container-league.yaml
was a k8s manifest fragment for a deployment that no longer exists.

The testthat suite at tests/testthat/ is untouched (parallel cleanup
work in another session).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Verify the commit landed**

```bash
git log --oneline -1
git show --stat HEAD | head -15
```

Expected: top commit is `chore(#79): delete tests/docker/ and stale k8s manifests`. 10 files deleted.

---

## Task 5: Commit 3 — update `docs/README.md` to drop dangling links

**Goal:** Update the `## 🚀 Deployment` section of `docs/README.md` to remove links to the four files just deleted, and add `docs/deployment/README.md` (the post-#78 canonical doc) as the primary entry. Other broken links elsewhere in `docs/README.md` (e.g., `troubleshooting/*`) are pre-existing — out of scope.

**Files:**
- Modify: `docs/README.md` (lines 16–22, the `### 🚀 Deployment` section)

- [ ] **Step 1: Read `docs/README.md` to confirm current state**

Use the Read tool. Lines 16–22 should currently read:

```markdown
### 🚀 Deployment
- [Quick Start](deployment/quick-start.md) - 5-minute deployment guide
- [Detailed Guide](deployment/detailed-guide.md) - Comprehensive deployment
- [Local Development](deployment/local-development.md) - Developer setup
- [Production](deployment/production.md) - Production best practices
- [Rollback](deployment/rollback.md) - Recovery procedures
```

If it doesn't match, STOP and report drift.

- [ ] **Step 2: Replace the deployment section**

Use the Edit tool. Find this exact text:

```markdown
### 🚀 Deployment
- [Quick Start](deployment/quick-start.md) - 5-minute deployment guide
- [Detailed Guide](deployment/detailed-guide.md) - Comprehensive deployment
- [Local Development](deployment/local-development.md) - Developer setup
- [Production](deployment/production.md) - Production best practices
- [Rollback](deployment/rollback.md) - Recovery procedures
```

Replace with:

```markdown
### 🚀 Deployment
- [Deployment Overview](deployment/README.md) - The single-container production stack
- [Quick Start](deployment/quick-start.md) - 5-minute deployment guide
- [Local Development](deployment/local-development.md) - Run the simulator outside Docker
- [Rollback](deployment/rollback.md) - Roll back to a previous image or git tag
```

- [ ] **Step 3: Verify the index update**

```bash
grep -nE '\[.*\]\(deployment/' docs/README.md
```

Expected: 4 lines, in this order:
- `(deployment/README.md)`
- `(deployment/quick-start.md)`
- `(deployment/local-development.md)`
- `(deployment/rollback.md)`

No `(deployment/detailed-guide.md)`, `(deployment/production.md)`, or `(deployment/simplified-microservices.md)`.

- [ ] **Step 4: Stage and commit**

```bash
git add docs/README.md
git commit -m "$(cat <<'EOF'
docs(#79): update docs/README.md links to drop deleted files

The Deployment section pointed to four files just deleted in this PR
(detailed-guide.md, production.md) or already deleted in earlier work
(simplified-microservices.md was scheduled for deletion). Replaces the
five-link list with the four files that survive: README.md (the new
canonical overview from #78), quick-start.md (rewritten in a later
commit), local-development.md (rewritten), rollback.md (rewritten).

Other broken links in docs/README.md (troubleshooting/*, operations/*)
are pre-existing and out of #79's scope.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Verify**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: top commit is `docs(#79): update docs/README.md links to drop deleted files`, 1 file changed.

---

## Task 6: Commit 4 — rewrite `docs/deployment/quick-start.md`

**Goal:** Replace the current 90-line quick-start (which references `docker-compose build` against the old multi-image stack) with a focused ~70-line guide for the single-container post-#78 stack. High confidence — full draft below.

**Files:**
- Modify (full rewrite): `docs/deployment/quick-start.md`

- [ ] **Step 1: Replace the file content using the Write tool**

Use the Write tool to overwrite `docs/deployment/quick-start.md` with this exact content:

```markdown
# Quick Start

Deploy the League Simulator in 5 minutes.

> The single-container production stack is described in detail in [Deployment Overview](README.md). This page is the fast path.

## Prerequisites

- Docker and Docker Compose installed
- A RapidAPI key for [api-football](https://rapidapi.com/api-sports/api/api-football)
- (Optional) ShinyApps.io credentials if you want the dashboard live on the public web

## 1. Clone and configure

```bash
git clone https://github.com/chrisschwer/League-Simulator-Update.git
cd League-Simulator-Update

cat > .env <<'EOF'
RAPIDAPI_KEY=your_rapidapi_key_here
SHINYAPPS_IO_SECRET=your_shiny_secret_here
# Optional — see deployment/README.md for the full list:
# SHINYAPPS_IO_NAME=chrisschwer
# SHINYAPPS_IO_TOKEN=your_shiny_token
# SEASON=2025
# DURATION=480
EOF
```

## 2. Build and run

```bash
docker-compose up -d --build
```

`docker-compose.yml` defines a single service `league-simulator-integrated` that runs the Rust simulation server on container port 8080 (mapped to host 8081) and the R scheduler in the same container.

## 3. Verify

```bash
# Container is up
docker-compose ps

# Rust health endpoint
curl http://localhost:8081/health

# R scheduler logs (tails until you Ctrl-C)
docker-compose logs -f league-simulator-integrated
```

The R scheduler wakes at 14:45 Berlin time, polls api-football every 2 minutes through 22:45, calls the in-process Rust server when new fixtures arrive, then pushes results to ShinyApps.io.

## Common operations

```bash
# Stop
docker-compose down

# Rebuild after a code change
docker-compose up -d --build

# Run the season-transition script (operator workflow — see docs/user-guide/season-transition.md)
docker-compose exec league-simulator-integrated \
  Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

## Troubleshooting

| Symptom | Where to look |
|---|---|
| Container exits immediately | `docker-compose logs league-simulator-integrated` — usually a missing required env var |
| `curl localhost:8081/health` hangs | Rust server didn't start — check container logs for cargo/build errors |
| No simulation results landing in ShinyApps.io | Check `SHINYAPPS_IO_SECRET` and the deploy step in the scheduler logs |
| Empty `.env` | Required vars are `RAPIDAPI_KEY` and `SHINYAPPS_IO_SECRET`; everything else has defaults |

## Next steps

- [Deployment Overview](README.md) — full env-var table and stack details
- [Local Development](local-development.md) — run the simulator outside Docker
- [Rollback](rollback.md) — roll back to a previous image or git tag
- [`CLAUDE.md`](../../CLAUDE.md) — common commands cheat-sheet
```

- [ ] **Step 2: Sanity-check the file**

```bash
wc -l docs/deployment/quick-start.md
grep -nE 'Dockerfile\.(simple|league|shiny|optimized|integrated|test)|docker-compose\.(simple|integrated)' docs/deployment/quick-start.md && echo FAIL || echo OK
```

Expected: line count ~75–85; the grep prints `OK`.

- [ ] **Step 3: Stage and commit**

```bash
git add docs/deployment/quick-start.md
git commit -m "$(cat <<'EOF'
docs(#79): rewrite quick-start guide for single-container stack

Previous version referenced `docker-compose build` against a multi-image
stack that no longer exists. New version describes the actual deploy
path: clone, .env with RAPIDAPI_KEY + SHINYAPPS_IO_SECRET,
docker-compose up -d --build, verify via localhost:8081/health.

Drops mentions of /logs/ directory, ShinyApp/data/ inspection, and
test_api_connection.R (which is the kind of repo-root debug script
flagged for future cleanup). Adds a pointer to docs/deployment/README.md
for the full env-var table and to docs/user-guide/season-transition.md
for the operator workflow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Verify**

```bash
git log --oneline -1
```

Expected: `docs(#79): rewrite quick-start guide for single-container stack`.

---

## Task 7: Commit 5 — rewrite `docs/deployment/rollback.md`

**Goal:** Replace the current 451-line rollback guide (which describes k8s rollback, helm rollback, blue-green deployments, and database schema migrations — none of which apply to this stack) with a focused ~60-line guide that describes the actual rollback procedure: previous Docker image tag or previous git ref + rebuild. High confidence — full draft below.

**Files:**
- Modify (full rewrite): `docs/deployment/rollback.md`

- [ ] **Step 1: Replace the file content using the Write tool**

Use the Write tool to overwrite `docs/deployment/rollback.md` with this exact content:

```markdown
# Rollback

Roll back to a previous version of the League Simulator.

> The League Simulator runs as a single Docker container with no database. Rollback is "stop the current container, run a previous image, restart" — no schema migrations, no blue-green, no traffic-shifting.

## Decide what to roll back

| Symptom | What to roll back |
|---|---|
| Container won't start, `curl localhost:8081/health` fails | The Docker image (Section A) |
| Container is up but produces wrong simulation results | The Docker image (Section A) |
| Container is up but the schedule or env config is wrong | `.env` and/or `docker-compose.yml` (Section B) |
| You want to compare against the pre-#78 deployment surface (multi-Dockerfile, k8s) | The git tag (Section C) |

## A. Roll back the Docker image

If you tag your images at deploy time (recommended), you have a previous tag to roll back to.

```bash
# 1. Stop the running container.
docker-compose down

# 2. Pin docker-compose.yml to the previous image tag.
#    (Edit the `image:` line under `league-simulator-integrated`.)
$EDITOR docker-compose.yml

# 3. Bring the previous version up.
docker-compose up -d

# 4. Verify.
docker-compose ps
curl http://localhost:8081/health
docker-compose logs -f league-simulator-integrated
```

If you don't tag images and just rebuild from `main`, you're rolling back code, not images — see Section C below.

## B. Roll back configuration only

```bash
# Inspect the previous .env from git history.
git log -p .env

# Restore an earlier version (or hand-edit .env to match).
git checkout HEAD~1 -- .env  # or a specific commit

# Restart with the new config — no rebuild needed.
docker-compose down
docker-compose up -d
```

## C. Roll back to a previous git tag and rebuild

This is the path when you don't have versioned Docker images and need to run the code as it was at a previous commit.

```bash
# Inspect tags.
git tag -l

# Check out the tag.
git checkout <tag-name>

# Rebuild and run.
docker-compose up -d --build

# When you're done debugging, return to main.
git checkout main
docker-compose up -d --build
```

### Reference tag

The repo has one annotated tag preserving the pre-cleanup deployment surface:

```bash
git checkout pre-deployment-cleanup-2026-05-02
```

This tag captures the multi-Dockerfile + `k8s/` tree as of 2026-05-02, before the deployment-collapse work in #78. You will *not* be able to `docker-compose up` directly from that tag (the file layout is different); use it for reference reading only.

## After rolling back

Watch the logs for one full simulation cycle:

```bash
docker-compose logs -f league-simulator-integrated
```

If the rollback was driven by a real bug, file an issue describing what you observed before and after, and consider whether the bug needs a regression test before re-deploying `main`.
```

- [ ] **Step 2: Sanity-check the file**

```bash
wc -l docs/deployment/rollback.md
grep -nE 'kubectl|helm |blue-green|schema_versions|pg_dump|Dockerfile\.(simple|league|shiny|optimized|integrated|test)' docs/deployment/rollback.md && echo FAIL || echo OK
```

Expected: line count ~60–75; the grep prints `OK`. (The single mention of `pre-deployment-cleanup-2026-05-02` is fine — it's a tag name, not a Dockerfile reference.)

- [ ] **Step 3: Stage and commit**

```bash
git add docs/deployment/rollback.md
git commit -m "$(cat <<'EOF'
docs(#79): rewrite rollback guide for current stack

Previous version (451 lines) described k8s rollback, helm rollback,
blue-green deployments, and database schema migrations — none of which
apply to this stack. Replaces with a 60-line guide covering the three
actual rollback paths: previous Docker image tag, configuration-only,
or previous git ref + rebuild. Points at the
pre-deployment-cleanup-2026-05-02 tag for pre-#78 reference reading.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Commit 6 — rewrite `docs/deployment/local-development.md` *(pauses for `[YOUR INPUT]`)*

**Goal:** Replace the 447-line current guide with a focused ~150-line guide. This is habit-dependent — the executor must ask the user three questions before drafting, then use the answers to fill in the right code blocks.

**Files:**
- Modify (full rewrite): `docs/deployment/local-development.md`

- [ ] **Step 1: Pause execution and ask the user**

Send this message to the user:

> "About to rewrite `docs/deployment/local-development.md`. Three habit questions so the rewrite matches what you actually do:
>
> 1. **Do you typically run the scheduler outside Docker locally** (`Rscript RCode/updateScheduler.R`), or only the simulation engine and Shiny app outside Docker, with the scheduler living in Docker? Or do you run *everything* in Docker for local dev too?
>
> 2. **Do you build the Rust binary locally** with `cargo build` in `league-simulator-rust/`, or do you rely on the Docker image's stage 1 to compile it?
>
> 3. **Anything else worth documenting** about your local-dev workflow — e.g., a debug invocation, a quick-iteration loop, an environment quirk on macOS, a way you reset state between runs?"

Wait for the user's reply.

- [ ] **Step 2: Capture the answers in the executor's notes**

Save the user's answers to `/tmp/issue-79-localdev-answers.md` for reference during the draft. The three answers map to:
- Q1 → which "running" subsection(s) the doc has
- Q2 → whether the "Rust binary" subsection covers `cargo build` in detail or just says "the Docker image builds it; you don't need to"
- Q3 → optional "Tips" section at the end

- [ ] **Step 3: Read the current file to preserve any genuinely useful content**

Use the Read tool on `docs/deployment/local-development.md`. Skim for sections worth keeping (e.g., a specific debugger invocation, a real macOS-specific gotcha). Most of the 447 lines describe a multi-Dockerfile / k8s setup and are pure deletion candidates.

- [ ] **Step 4: Draft and write the new file using the Write tool**

The skeleton (the executor fills in the `[FROM Q1/Q2/Q3]` markers based on the user's answers, then writes the file):

```markdown
# Local Development

Run and iterate on the League Simulator outside Docker.

> If you only need to deploy, see [Deployment Overview](README.md) and [Quick Start](quick-start.md). This page is for editing R scripts, the Rust simulator, or the Shiny app and seeing the result without rebuilding the container.

## Prerequisites

- R 4.3.x (the production container uses 4.3.1 via `rocker/r-ver:4.3.1`)
- Rust 1.81+ (for building the simulator binary)
- A RapidAPI key in the environment as `RAPIDAPI_KEY` if you'll exercise the api-football integration

## 1. Install R dependencies

```r
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])
```

This installs every package the production container installs at build time. It's idempotent; running it again is cheap.

## 2. [FROM Q2: Rust binary subsection]

[If Q2 = "I build it locally":]
```bash
cd league-simulator-rust
cargo build --release
# The binary is at league-simulator-rust/target/release/league-simulator-server
```

[If Q2 = "I rely on Docker stage 1":]
The production container compiles the Rust binary in stage 1 of `Dockerfile`. For local Rust development, run `cargo build` (or `cargo run`) inside `league-simulator-rust/`; the crate is self-contained.

## 3. Run the test suite

```r
testthat::test_dir("tests/testthat")
```

Some tests target deleted infrastructure; the suite is being cleaned up in a separate effort. Look for failures in the files that are explicitly part of the production loop or the season-transition workflow — those are the signal-bearing ones.

## 4. Run the Shiny app locally

```r
shiny::runApp("ShinyApp/app.R")
```

Opens at `http://localhost:<random-port>` (or pin it with `shiny::runApp("ShinyApp/app.R", port = 3838)`). The app reads `ShinyApp/data/Ergebnis.Rds`, which is what the production scheduler writes to ShinyApps.io.

## 5. [FROM Q1: Running the scheduler]

[If Q1 = "I run scheduler outside Docker":]
```bash
RAPIDAPI_KEY=your_key Rscript RCode/updateScheduler.R
```

This runs the production scheduler against the live api-football endpoint. It enforces the same 14:45–22:45 Berlin time window the container does.

[If Q1 = "Docker for the scheduler, R for everything else":]
The scheduler is the part of the system that's most coupled to its container environment (timezone, Rust server availability, retry logic in `docker-start.sh`). For local iteration, run individual modules instead:
- `Rscript RCode/update_all_leagues_loop.R` for one simulation pass
- `Rscript RCode/leagueSimulatorRust.R` for a single league against a running Rust server

[If Q1 = "everything in Docker":]
Local-dev for this project means rebuilding the container: `docker-compose up -d --build`. Code changes in `RCode/`, `scripts/`, or `ShinyApp/` are picked up by the next rebuild because the `Dockerfile` runs `COPY .` (or equivalent) at the top of stage 2.

## Environment variables

The full table is in [Deployment Overview](README.md#required-environment-variables). For local dev, you typically need:

- `RAPIDAPI_KEY` — required if you're hitting api-football
- `SHINYAPPS_IO_SECRET` — only if you're testing the deploy step
- `RUST_API_URL=http://localhost:8080` — only if you're running the Rust server outside Docker

## [FROM Q3: Tips section, optional]

[If user provided tips in Q3, list them here. If Q3 was empty, omit this section.]

## Related

- [Quick Start](quick-start.md) — get a deployed container running
- [Deployment Overview](README.md) — what runs in production
- [`CLAUDE.md`](../../CLAUDE.md) — common commands cheat-sheet
```

- [ ] **Step 5: Sanity-check**

```bash
wc -l docs/deployment/local-development.md
grep -nE 'Dockerfile\.(simple|league|shiny|optimized|integrated|test)|docker-compose\.(simple|integrated)|kubectl|helm |k8s/' docs/deployment/local-development.md && echo FAIL || echo OK
```

Expected: line count ~120–180; the grep prints `OK`.

- [ ] **Step 6: Stage and commit**

```bash
git add docs/deployment/local-development.md
git commit -m "$(cat <<'EOF'
docs(#79): rewrite local-development guide

Previous version (447 lines) described setup for the multi-Dockerfile
and k8s stacks. New version (~150 lines) covers the path that actually
matches the current single-container architecture, with content
informed by the user's actual local-dev workflow.

Sections: install R deps from packagelist.txt, Rust binary, testthat,
Shiny app locally, running the scheduler (or alternatives), env vars.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Commit 7 — rewrite repo-root `README.md` *(pauses for `[YOUR INPUT]`)*

**Goal:** Replace the 262-line repo-root `README.md` (which describes 4 deployment modes, only 1 of which exists) with a focused ~100-line README. Habit-dependent.

**Files:**
- Modify (full rewrite): `README.md`

- [ ] **Step 1: Pause execution and ask the user**

Send this message:

> "About to rewrite the repo-root `README.md`. Three style/content questions:
>
> 1. **Public ShinyApps.io URL:** should the README link to the live dashboard? If yes, what's the URL?
>
> 2. **Your blog *30 Punkte*:** should the README mention/link it as a related project? If yes, with what URL?
>
> 3. **Visuals:** do you want a screenshot of the Shiny dashboard, a CI/Docker badge, or both? Or keep it text-only and minimal?"

Wait for the user's reply.

- [ ] **Step 2: Capture answers**

Save to `/tmp/issue-79-readme-answers.md`. Map answers:
- Q1 → conditional "Live dashboard" link in the header
- Q2 → conditional "Related" section near the bottom
- Q3 → conditional badge row at the top and/or screenshot block under "What it does"

- [ ] **Step 3: Read the current `README.md` once to confirm there's nothing surprising worth preserving**

Specifically check that the "Scheduling and Time Windows" detail (lines ~217–238 in the current README) is not the only place those windows are documented. If so, capture them into the new README under "What it does." Spoiler: those time windows were for the deleted microservices scheduler; the production scheduler uses the simpler 14:45–22:45 window documented in `docs/deployment/README.md`. Don't carry forward microservices-mode windows.

- [ ] **Step 4: Draft and write the new `README.md` using the Write tool**

Skeleton:

```markdown
# League Simulator

[FROM Q3: optional badge row]

A Monte Carlo simulator that predicts final standings for the three German football leagues (Bundesliga, 2. Bundesliga, 3. Liga). The simulator combines an ELO rating model with a Rust simulation engine and runs the predictions on a fixed daily schedule, surfacing the results through a Shiny dashboard.

[FROM Q1: Live dashboard link, optional]

## What it does

- Pulls match results from [api-football](https://rapidapi.com/api-sports/api/api-football) at 14:45 Berlin time, every 2 minutes through 22:45.
- For each match-day update, runs 10,000 Monte Carlo simulations through the rest of the season for each of the three leagues.
- Produces a probability matrix per league (each team × each final position) and pushes it to a Shiny dashboard.
- Re-runs ELO updates after every match.

[FROM Q3: optional screenshot]

## How it works

Three pieces:

1. **Rust simulation engine** (`league-simulator-rust/`) — high-performance Monte Carlo runner over a season's remaining fixtures.
2. **R scheduler** (`RCode/`) — wakes during the active window, polls api-football, calls the in-process Rust server when new fixtures arrive, and pushes results to ShinyApps.io.
3. **Shiny app** (`ShinyApp/`) — renders the probability matrices as heatmaps.

All three run in a single Docker container; the scheduler talks to the Rust server over `localhost`.

## Deploy

The deployment is one Docker container.

```bash
docker-compose up -d --build
```

See [docs/deployment/README.md](docs/deployment/README.md) for the full setup, env-var table, and verification steps. The fast path is in [docs/deployment/quick-start.md](docs/deployment/quick-start.md).

## Operate

Common operator tasks:

- **Season transition** (run before each new season starts): [`docs/user-guide/season-transition.md`](docs/user-guide/season-transition.md).
- **Roll back to a previous version:** [`docs/deployment/rollback.md`](docs/deployment/rollback.md).
- **Local development without Docker:** [`docs/deployment/local-development.md`](docs/deployment/local-development.md).
- **Common commands:** [`CLAUDE.md`](CLAUDE.md) Quick Commands section.

## Project layout

```
.
├── league-simulator-rust/   # Rust simulation engine
├── RCode/                   # R scheduler + ELO + table calculations
├── ShinyApp/                # Shiny dashboard
├── scripts/                 # Operator scripts (season transition)
├── tests/testthat/          # R test suite
├── docs/                    # Documentation
├── Dockerfile               # Single multi-stage build
└── docker-compose.yml       # Single-service deployment
```

[FROM Q2: optional Related section]

## License

[FROM Q3 or current README: keep whatever license line was there. If none was there and the user didn't specify, omit the section.]
```

- [ ] **Step 5: Sanity-check**

```bash
wc -l README.md
grep -nE 'Dockerfile\.(simple|league|shiny|optimized|integrated|test)|docker-compose\.(simple|integrated)|kubectl|k8s/|microservices' README.md && echo FAIL || echo OK
```

Expected: line count ~80–130; the grep prints `OK`.

- [ ] **Step 6: Stage and commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs(#79): rewrite repo-root README

Previous version (262 lines) described four deployment modes — three of
which (Simple Monolithic, Original Monolithic, k8s Microservices) no
longer exist after #78. New version (~100 lines) describes only the
single-container production stack, points at docs/deployment/README.md
as the canonical deploy reference, and links the operator workflows in
docs/user-guide/.

Drops mentions of Dockerfile.simple, Dockerfile.league, Dockerfile.shiny,
docker-compose.simple.yml, docker-compose.integrated.yml,
updateSchedulerSimple.R (file no longer exists), and the microservices
mode time windows (which were for the deleted league_scheduler.R path).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Acceptance verification

**Goal:** Run the full verification battery from the spec. Every check must pass before pushing.

**Files:**
- Read-only

- [ ] **Step 1: Canonical inbound-reference grep**

```bash
grep -rEn "Dockerfile\.(simple|league|shiny|optimized|integrated|test)|docker-compose\.(simple|integrated)|updateSchedulerRust|updateSchedulerSimple|update_all_leagues_loop_rust|docker-integrated-start" \
  --include="*.md" --include="*.yml" --include="*.yaml" --include="*.sh" . 2>/dev/null \
  | grep -v "^./.git/" \
  | grep -v "^./.worktrees/" \
  | grep -v "^./removed/" \
  | grep -vE "^./docs/(prds|superpowers/(plans|specs))/"
```

Expected: no output. Hits inside `docs/prds/`, `docs/superpowers/plans/`, `docs/superpowers/specs/` are intentionally filtered (historical PRD/spec/plan records).

- [ ] **Step 2: Confirm all delete targets are gone**

```bash
ls docs/deployment/detailed-guide.md docs/deployment/production.md docs/deployment/simplified-microservices.md docs/deployment/ci-cd-guide.md tests/docker tests/REVISED_TEST_SPECIFICATIONS.md tests/container-league.yaml 2>&1
```

Expected: every line says `No such file or directory`.

- [ ] **Step 3: Surviving + rewritten docs are clean**

```bash
for f in docs/deployment/README.md docs/deployment/quick-start.md docs/deployment/local-development.md docs/deployment/rollback.md README.md; do
  echo "=== $f ==="
  grep -nE 'Dockerfile\.(simple|league|shiny|optimized|integrated|test)|docker-compose\.(simple|integrated)' "$f" && echo "FAIL: $f" || echo "  clean"
done
```

Expected: each file reports `clean`.

- [ ] **Step 4: `docs/README.md` links are valid**

```bash
grep -nE '\[.*\]\(deployment/' docs/README.md
```

Expected: 4 lines, pointing only to `deployment/README.md`, `deployment/quick-start.md`, `deployment/local-development.md`, `deployment/rollback.md`. No `detailed-guide.md`, `production.md`, or `simplified-microservices.md`.

- [ ] **Step 5: Sanity — production R sources still parse**

```bash
Rscript -e 'invisible(parse("RCode/updateScheduler.R")); cat("OK\n")'
Rscript -e 'invisible(parse("RCode/update_all_leagues_loop.R")); cat("OK\n")'
```

Expected: `OK` printed twice. (We did not touch these; cheap belt-and-braces.)

- [ ] **Step 6: Confirm commit shape**

```bash
git log --oneline main..HEAD
```

Expected: 7 commits (or 8 if Task 2 Step 5 added the env-backfill commit). Newest first:
1. `docs(#79): rewrite repo-root README`
2. `docs(#79): rewrite local-development guide`
3. `docs(#79): rewrite rollback guide for current stack`
4. `docs(#79): rewrite quick-start guide for single-container stack`
5. `docs(#79): update docs/README.md links to drop deleted files`
6. `chore(#79): delete tests/docker/ and stale k8s manifests`
7. `chore(#79): delete fictional deployment docs`
   *(8. optionally `docs(#79): backfill env vars into deployment/README.md`)*

If different, STOP and reconcile.

- [ ] **Step 7: Total file delta**

```bash
git diff --stat main..HEAD | tail -5
```

Expected summary: **19 files changed** — 14 deletions (4 deployment docs + 8 in `tests/docker/` + `tests/REVISED_TEST_SPECIFICATIONS.md` + `tests/container-league.yaml`) + 5 modifications (the 4 rewrites + `docs/README.md`). Large negative line count from the deletions (~2,400 lines removed) plus moderate insertions from the rewrites.

---

## Task 11: Push and open PR

**Goal:** Push the branch and open the PR that closes #79.

**Files:**
- Read-only

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/issue-79-docs-cleanup
```

Expected: push confirmation + GitHub "Create a pull request" URL.

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "docs(#79): clean stale deployment docs and rewrite the four operator-essential ones" --body "$(cat <<'EOF'
## Summary

Removes 8 files + 1 directory of documentation that contradicts the post-#78 single-container deployment, and rewrites the four docs an operator with a 6-month memory gap actually needs. Doc surface around deployment drops from ~2,800 lines to ~450 lines.

### Deletions (12 files total)

- `docs/deployment/detailed-guide.md`, `production.md`, `simplified-microservices.md`, `ci-cd-guide.md` — described deployment paths that no longer exist (multi-Dockerfile, k8s, blue-green, HA/DR/security hardening for a one-container deploy, a CI pipeline that's `*.disabled` on disk).
- `tests/docker/*` (8 files) — tests for `Dockerfile.league.optimized` and friends, all of which were deleted in #78.
- `tests/REVISED_TEST_SPECIFICATIONS.md`, `tests/container-league.yaml` — k8s/multi-Dockerfile test artifacts.

### Rewrites (4 files)

- `docs/deployment/quick-start.md` — focused 5-minute deploy guide for the actual stack.
- `docs/deployment/rollback.md` — three real rollback paths (image tag, config-only, git ref + rebuild). Drops k8s/helm/blue-green/database-schema fiction.
- `docs/deployment/local-development.md` — drafted with input from the maintainer's actual local-dev workflow.
- `README.md` (repo root) — the project's front door, rewritten to describe only the current single-container architecture.

### Doc index

- `docs/README.md` Deployment section updated to link the four survivors (and add `deployment/README.md` from #78 as the primary entry).

Closes #79.

Spec: `docs/superpowers/specs/2026-05-02-docs-cleanup-design.md`
Plan: `docs/superpowers/plans/2026-05-02-docs-cleanup.md`

## Scope guardrails

Zero changes to `RCode/`, `scripts/`, `Dockerfile`, `docker-compose.yml`, `tests/testthat/`, or `.github/workflows/` — preserves merge-parallelism with the in-flight test-cleanup work and unblocks #76 (CI rebuild) cleanly.

## Test plan

- [x] Canonical inbound-reference grep returns zero hits outside historical PRD/spec/plan files
- [x] All 4 deleted deployment docs are gone
- [x] `tests/docker/`, `tests/REVISED_TEST_SPECIFICATIONS.md`, `tests/container-league.yaml` are gone
- [x] Surviving + rewritten docs contain no references to deleted Dockerfiles or `docker-compose.{simple,integrated}.yml`
- [x] `docs/README.md` links only the four surviving deployment docs
- [x] `Rscript -e 'parse(...)'` on `RCode/updateScheduler.R` and `RCode/update_all_leagues_loop.R` prints OK (sanity — no R was touched)
- [x] Commit history is 7 (or 8) clean conventional commits

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: `https://github.com/chrisschwer/League-Simulator-Update/pull/<N>` URL printed.

- [ ] **Step 3: Print the PR URL for the user**

```bash
gh pr view --json url --jq .url
```

---

## Done

The branch is on `origin`, the PR is open, #79 is closed when it merges. After merge: clean up the worktree via the `superpowers:finishing-a-development-branch` skill (Option 2 path keeps the worktree until merge; remove afterward).
