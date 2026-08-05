# Collapse Deployment Surface to One Production Stack — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the repo to exactly one production deployment stack — `Dockerfile` + `docker-compose.yml` + `docker-start.sh` + `RCode/updateScheduler.R` — by deleting six dead Dockerfiles, the dead compose, the `k8s/` and `docker/` directories, eight k8s-era shell scripts, three dead R schedulers, the legacy loop file, and `RCode/configmap_deployment.R`. Rename surviving production files to drop the now-misleading `_rust` / `_integrated` qualifiers. The season-transition operator workflow (`scripts/season_transition.R`) must continue to work.

**Architecture:** Pure deletion + rename. No behavioral changes. Each task produces a single git commit. Tasks are ordered so the production Docker image stays buildable at every commit, and the season-transition smoke test passes after every deletion task. The "tests" here are not testthat tests — they are command-level checks (`docker build`, `docker-compose config`, `Rscript -e 'source(...)'`) that prove no required file was severed.

**Tech Stack:** Docker, docker-compose v2/v3, R 4.3.1 + Rscript, bash. No new dependencies.

**Reference:** PRD at `docs/prds/2026-05-02-deployment-surface-collapse.md` (also GitHub issue #78). Companion PRD `docs/prds/2026-05-02-simulation-engine-seam.md` (issue #77) is independent — do not interleave.

**Doc-cleanup is out of scope.** Many docs in `docs/deployment/` (and a few in `tests/`, `RUST_INTEGRATION.md`, `PRD_ISSUE_1_monolithic_deployment.md`, `.claude/`) reference the old layout. The acceptance grep in this plan is **scoped to source code only** (`RCode/`, `scripts/`, `tests/testthat/`, root-level `Dockerfile*`/`docker-compose*`/`*.sh`). A separate follow-up GitHub issue tracks doc cleanup. Do not expand scope mid-plan.

**Survivor list — DO NOT DELETE:** `scripts/season_transition.R`, plus the 15 `RCode/` modules it sources (`season_validation.R`, `elo_aggregation.R`, `api_service.R`, `api_helpers.R`, `interactive_prompts.R`, `input_validation.R`, `csv_generation.R`, `file_operations.R`, `season_processor.R`, `league_processor.R`, `error_handling.R`, `logging.R`, `input_handler.R`, `team_config_loader.R`, `team_data_carryover.R`), plus `retrieveResults.R`, `transform_data.R`, **`SpielCPP.R`**, and the rest of the C++ engine (`leagueSimulatorCPP.R`, `simulationsCPP.R`, `SaisonSimulierenCPP.R`, `SpielNichtSimulieren.cpp`, `cpp_wrappers.R`, `RcppExports.R`). The companion PRD #77 will decide the C++ engine's long-term fate; this plan touches none of it.

---

## File Inventory

### Files renamed (5)

| Before | After |
|---|---|
| `Dockerfile.integrated` | `Dockerfile` |
| `docker-compose.integrated.yml` | `docker-compose.yml` |
| `docker-integrated-start.sh` | `docker-start.sh` |
| `RCode/updateSchedulerRust.R` | `RCode/updateScheduler.R` |
| `RCode/update_all_leagues_loop_rust.R` | `RCode/update_all_leagues_loop.R` |

### Files modified to follow renames (5)

- `Dockerfile` (line 107: `COPY docker-integrated-start.sh /app/start.sh` → `COPY docker-start.sh /app/start.sh`)
- `docker-start.sh` (line 70: `Rscript RCode/updateSchedulerRust.R` → `Rscript RCode/updateScheduler.R`)
- `RCode/updateScheduler.R` (line 48: `source("RCode/update_all_leagues_loop_rust.R")` → `source("RCode/update_all_leagues_loop.R")`; line 164: function call `update_all_leagues_loop_rust(` → `update_all_leagues_loop(`)
- `RCode/update_all_leagues_loop.R` (line 4: function definition `update_all_leagues_loop_rust <- function(` → `update_all_leagues_loop <- function(`)
- `CLAUDE.md` (lines 19, 20: change `Dockerfile.simple` / `docker-compose.simple.yml` → `Dockerfile` / `docker-compose.yml`; line 70: replace `simple-monolithic.md` pointer with `README.md` pointer)

### Files deleted (24)

**Dockerfiles (6):** `Dockerfile.simple`, `Dockerfile.league`, `Dockerfile.shiny`, `Dockerfile.optimized`, `DOCKERFILE`, `Dockerfile.test`

**Compose (1):** `docker-compose.simple.yml`

**Directories (2):** `docker/` (contains `healthcheck-league.R`, `healthcheck-shiny.R`), `k8s/` (microservices manifests)

**Scripts (8):** `scripts/deploy_pod_lifecycle.sh`, `scripts/generate_cronjobs.sh`, `scripts/calculate_cronjob_schedules.sh`, `scripts/activate_lifecycle.sh`, `scripts/emergency_rollback.sh`, `scripts/docker_build_all.sh`, `scripts/deploy-local.sh`, `scripts/status.sh`

**R files (4):** `RCode/updateSchedulerSimple.R`, `RCode/updateSchedulerSimple_local.R`, `RCode/configmap_deployment.R`, `RCode/test_scheduler_now.R` *(this last one is a test utility for the dead simple scheduler; verify in Task 7)*

**Docs (1):** `docs/deployment/simple-monolithic.md`

### Files created (1)

- `docs/deployment/README.md` (new operator README documenting the single stack)

### Files modified beyond the rename follow-ups (1)

- `RCode/csv_generation.R` (lines 79–109: remove the optional `tryCatch` block that conditionally sources `k8s/templates/configmap-generator.R`)

---

## Task 1: Pre-flight Verification + Recovery Tag

**Goal:** Capture a recoverable git ref and confirm the production stack builds *before* any change. Establishes the baseline that subsequent tasks will be measured against.

**Files:**
- No file changes. This task is git + docker-only.

- [ ] **Step 1: Confirm clean working tree**

```bash
git status --short
```

Expected output: empty (or only the two PRDs already on disk in `docs/prds/`). If anything else is present, stop and ask before continuing.

- [ ] **Step 2: Confirm we're on `main` and up to date**

```bash
git branch --show-current
git fetch origin
git status -uno
```

Expected: `main`; `Your branch is up to date with 'origin/main'.` If not, ask before continuing.

- [ ] **Step 3: Create the recovery tag**

```bash
git tag -a pre-deployment-cleanup-2026-05-02 -m "Snapshot before collapsing deployment surface to one stack (issue #78)"
```

- [ ] **Step 4: Verify the tag exists locally**

```bash
git tag -l pre-deployment-cleanup-2026-05-02
```

Expected output: `pre-deployment-cleanup-2026-05-02`

- [ ] **Step 5: Push the tag to the remote**

```bash
git push origin pre-deployment-cleanup-2026-05-02
```

Expected: `* [new tag]         pre-deployment-cleanup-2026-05-02 -> pre-deployment-cleanup-2026-05-02`

- [ ] **Step 6: Build the current production image as a baseline**

```bash
docker build -f Dockerfile.integrated -t league-simulator:pre-cleanup .
```

Expected: build succeeds, ends with a line like `Successfully tagged league-simulator:pre-cleanup`. **This may take 5–10 minutes** — the Dockerfile installs the full R package list. If the build fails, stop and report the failure; the production image is broken in a way unrelated to this plan, and that is a blocker.

- [ ] **Step 7: Capture the baseline image ID**

```bash
docker images league-simulator:pre-cleanup --format '{{.ID}}'
```

Record the ID (e.g., `sha256:abc123...`). You'll compare against this in Task 8.

- [ ] **Step 8: Capture the season-transition baseline**

```bash
Rscript -e 'tryCatch(source("scripts/season_transition.R"), error = function(e) cat("EXPECTED ARGS-MISSING ERROR:", e$message, "\n"))' 2>&1 | tee /tmp/season-transition-baseline.txt
```

Expected: the script sources its 18 required modules (15 transition-specific + `retrieveResults.R`, `transform_data.R`, `SpielCPP.R`), then fails with an args-related error like `Error: usage: Rscript season_transition.R <source_season> <target_season>` *or similar* (it will not have any required-module-not-found warnings). The output goes to `/tmp/season-transition-baseline.txt` for later comparison. Note: if your environment lacks `Rcpp` or can't compile `SpielCPP.R`, this baseline may legitimately fail; if so, document that and skip the season-transition smoke checks in later tasks (the plan's deletions don't touch any season-transition file).

- [ ] **Step 9: No commit needed**

This task only created a git tag (no working-tree change). No commit.

---

## Task 2: Rename `Dockerfile.integrated` → `Dockerfile` and update internal references

**Goal:** Rename the production Dockerfile to its unqualified name. Update the `COPY` line that still references the old start-script name (which we'll rename in Task 3). After this task, the build still works because the start script hasn't been renamed yet — both the new `Dockerfile` and the old `docker-integrated-start.sh` co-exist.

**Files:**
- Delete: `DOCKERFILE` (legacy all-caps file, pulled forward from Task 6 to resolve case-insensitive-filesystem collision)
- Rename: `Dockerfile.integrated` → `Dockerfile`
- Modify: `Dockerfile` line 107

- [ ] **Step 0: Delete the legacy `DOCKERFILE` first (case-insensitive filesystem workaround)**

On macOS APFS (case-insensitive by default), `git mv Dockerfile.integrated Dockerfile` fails because the OS sees the existing `DOCKERFILE` (all-caps) at the same path. The legacy `DOCKERFILE` was already slated for deletion in Task 6; pulling it forward here unblocks the rename without any change in semantics.

```bash
git rm DOCKERFILE
```

Verify with `ls -la | grep -i ^dockerfile` — `DOCKERFILE` should be gone; only the `Dockerfile.X` family should remain.

- [ ] **Step 1: Rename the Dockerfile**

```bash
git mv Dockerfile.integrated Dockerfile
```

- [ ] **Step 2: Verify the rename**

```bash
ls Dockerfile Dockerfile.integrated 2>&1
```

Expected: `Dockerfile` exists; `ls: Dockerfile.integrated: No such file or directory`.

- [ ] **Step 3: Inspect the unchanged content (sanity check)**

```bash
sed -n '105,120p' Dockerfile
```

Expected: lines 107 (`COPY docker-integrated-start.sh /app/start.sh`), 108 (`RUN chmod +x /app/start.sh`), 119 (`CMD ["/app/start.sh"]`). The `CMD` already uses the in-container path `/app/start.sh` and does not need to change. Only the `COPY` line at 107 names the host file we'll rename in Task 3 — but **leave it alone for now** so the build still works.

- [ ] **Step 4: Build with the new name to confirm parity**

```bash
docker build -f Dockerfile -t league-simulator:rename-test-1 .
```

Expected: build succeeds. Cache should make this fast (seconds, not minutes) since the Dockerfile content is byte-identical.

- [ ] **Step 5: Commit (single commit covers both the legacy-DOCKERFILE deletion and the rename)**

```bash
git commit -m "refactor: rename Dockerfile.integrated to Dockerfile

Part of deployment surface collapse (issue #78). The 'integrated' qualifier
only made sense when there were alternative Dockerfiles. After the cleanup,
Dockerfile is the only one.

Also delete the legacy uppercase DOCKERFILE (a 2024 single-stage build
superseded by the multi-stage Dockerfile.integrated). It was already
slated for deletion in Task 6; pulled forward here to resolve a
case-insensitive-filesystem collision with the rename target on macOS APFS."
```

Note: `git rm DOCKERFILE` (Step 0) and `git mv` (Step 1) already staged the deletion and the rename, so a single `git commit` (no `git add`) captures both.

---

## Task 3: Rename `docker-integrated-start.sh` → `docker-start.sh` and update Dockerfile

**Goal:** Rename the start script and fix the `COPY` reference in the new `Dockerfile` so the build keeps working.

**Files:**
- Rename: `docker-integrated-start.sh` → `docker-start.sh`
- Modify: `Dockerfile` line 107

- [ ] **Step 1: Rename the script**

```bash
git mv docker-integrated-start.sh docker-start.sh
```

- [ ] **Step 2: Update the `COPY` line in `Dockerfile`**

Edit `Dockerfile` line 107 to replace the old script name. Use `sed` for precision:

```bash
sed -i.bak 's|COPY docker-integrated-start.sh /app/start.sh|COPY docker-start.sh /app/start.sh|' Dockerfile && rm Dockerfile.bak
```

- [ ] **Step 3: Verify the edit**

```bash
grep -n "docker.*start" Dockerfile
```

Expected output (one line):
```
107:COPY docker-start.sh /app/start.sh
```

- [ ] **Step 4: Build to confirm the renamed script still gets copied**

```bash
docker build -f Dockerfile -t league-simulator:rename-test-2 .
```

Expected: build succeeds. The `COPY` step will re-run because its source filename changed (cache invalidated), but later steps should cache.

- [ ] **Step 5: Verify the script is in the image**

```bash
docker run --rm --entrypoint sh league-simulator:rename-test-2 -c "ls -la /app/start.sh"
```

Expected: `-rwxr-xr-x ... /app/start.sh`

- [ ] **Step 6: Commit**

```bash
git add Dockerfile docker-start.sh
git commit -m "refactor: rename docker-integrated-start.sh to docker-start.sh

Update COPY reference in Dockerfile to match. The 'integrated' qualifier
was only meaningful when there were other start scripts; now there's
only one. (issue #78)"
```

---

## Task 4: Rename the Rust scheduler and loop files (and the loop function)

**Goal:** Rename `updateSchedulerRust.R` → `updateScheduler.R` and `update_all_leagues_loop_rust.R` → `update_all_leagues_loop.R`. **Also rename the function `update_all_leagues_loop_rust` to `update_all_leagues_loop`** in both its definition and its call site. Update `docker-start.sh` line 70 to invoke the renamed scheduler.

**Files:**
- Rename: `RCode/updateSchedulerRust.R` → `RCode/updateScheduler.R`
- Rename: `RCode/update_all_leagues_loop_rust.R` → `RCode/update_all_leagues_loop.R`
- Modify: `RCode/updateScheduler.R` (line 48: `source` call; line 164: function call)
- Modify: `RCode/update_all_leagues_loop.R` (line 4: function definition)
- Modify: `docker-start.sh` (line 70: `Rscript` invocation)

- [ ] **Step 1: Rename the scheduler file**

```bash
git mv RCode/updateSchedulerRust.R RCode/updateScheduler.R
```

- [ ] **Step 2: Rename the loop file**

```bash
git mv RCode/update_all_leagues_loop_rust.R RCode/update_all_leagues_loop.R
```

- [ ] **Step 3: Update the `source()` call in the renamed scheduler (line 48)**

```bash
sed -i.bak 's|source("RCode/update_all_leagues_loop_rust.R")|source("RCode/update_all_leagues_loop.R")|' RCode/updateScheduler.R && rm RCode/updateScheduler.R.bak
```

- [ ] **Step 4: Update the function call in the renamed scheduler (line 164)**

```bash
sed -i.bak 's|update_all_leagues_loop_rust(|update_all_leagues_loop(|' RCode/updateScheduler.R && rm RCode/updateScheduler.R.bak
```

- [ ] **Step 5: Update the function definition in the renamed loop (line 4)**

```bash
sed -i.bak 's|^update_all_leagues_loop_rust <- function|update_all_leagues_loop <- function|' RCode/update_all_leagues_loop.R && rm RCode/update_all_leagues_loop.R.bak
```

- [ ] **Step 6: Update the `Rscript` invocation in `docker-start.sh` (line 70)**

```bash
sed -i.bak 's|Rscript RCode/updateSchedulerRust.R|Rscript RCode/updateScheduler.R|' docker-start.sh && rm docker-start.sh.bak
```

- [ ] **Step 7: Verify all five edits landed**

```bash
grep -n "update_all_leagues_loop\|updateScheduler" RCode/updateScheduler.R RCode/update_all_leagues_loop.R docker-start.sh
```

Expected output (no occurrences of `_rust` should appear, and the function name should be the unqualified `update_all_leagues_loop`):

```
RCode/updateScheduler.R:48:source("RCode/update_all_leagues_loop.R")
RCode/updateScheduler.R:164:  update_all_leagues_loop(
RCode/update_all_leagues_loop.R:4:update_all_leagues_loop <- function(duration = 480, loops = 31, initial_wait = 0,
docker-start.sh:70:        Rscript RCode/updateScheduler.R
```

If any line still contains `_rust`, fix it before continuing.

- [ ] **Step 8: Verify R can parse the renamed scheduler (syntax check)**

```bash
Rscript -e 'parse("RCode/updateScheduler.R"); parse("RCode/update_all_leagues_loop.R"); cat("OK\n")'
```

Expected output: `OK`. If R reports a parse error, the `sed` edit corrupted something — inspect and fix.

- [ ] **Step 9: Build the Docker image to confirm the renamed files still work end-to-end**

```bash
docker build -f Dockerfile -t league-simulator:rename-test-3 .
```

Expected: build succeeds.

- [ ] **Step 10: Verify the renamed scheduler is the one in the image**

```bash
docker run --rm --entrypoint sh league-simulator:rename-test-3 -c "ls /app/RCode/updateScheduler*.R /app/RCode/update_all_leagues_loop*.R"
```

Expected: shows `updateScheduler.R`, `updateSchedulerSimple.R`, `updateSchedulerSimple_local.R`, `update_all_leagues_loop.R`, `update_all_leagues_loop_rust.R` — wait, the `_rust` versions should be gone. **Re-check Step 1 and Step 2 if they still appear.** The original `update_all_leagues_loop.R` (the dead non-rust one) will also appear in this listing — that's expected, it gets deleted in Task 6. Important: do not see `updateSchedulerRust.R` or `update_all_leagues_loop_rust.R`.

- [ ] **Step 11: Commit**

```bash
git add RCode/updateScheduler.R RCode/update_all_leagues_loop.R docker-start.sh
git commit -m "refactor: rename Rust scheduler and loop to unqualified names

- updateSchedulerRust.R -> updateScheduler.R
- update_all_leagues_loop_rust.R -> update_all_leagues_loop.R
- Rename the loop function update_all_leagues_loop_rust() to update_all_leagues_loop()
- Update source() and function-call references
- Update docker-start.sh to invoke the renamed scheduler

The '_rust' qualifier only made sense when there was a non-Rust path. After
the cleanup that path is gone. (issue #78)"
```

---

## Task 5: Rename `docker-compose.integrated.yml` → `docker-compose.yml`

**Goal:** Rename the production compose file. The compose file references the image by tag (`chrisschwer/league-simulator:integrated-system-deps`), not by Dockerfile path, so no internal edit is needed.

**Files:**
- Rename: `docker-compose.integrated.yml` → `docker-compose.yml`

- [ ] **Step 1: Inspect the compose file for any Dockerfile path references that need updating**

```bash
grep -n "Dockerfile\|dockerfile" docker-compose.integrated.yml
```

Expected: one match in the optional `rust-simulator` service block (line ~36: `dockerfile: Dockerfile`) — that's a relative reference inside `league-simulator-rust/`, unrelated to the rename. No edit needed.

- [ ] **Step 2: Rename**

```bash
git mv docker-compose.integrated.yml docker-compose.yml
```

- [ ] **Step 3: Validate the renamed compose file parses**

```bash
docker-compose -f docker-compose.yml config > /dev/null
```

Expected: exit code 0. (You can drop the `-f docker-compose.yml` since `docker-compose` defaults to that filename, but being explicit makes the intent obvious.)

- [ ] **Step 4: Verify with the default filename**

```bash
docker-compose config > /dev/null
```

Expected: exit code 0. Now docker-compose finds it without `-f`.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yml
git commit -m "refactor: rename docker-compose.integrated.yml to docker-compose.yml

Production now uses the default compose filename. (issue #78)"
```

---

## Task 6: Delete dead Dockerfiles, dead compose, dead R schedulers, and dead loop

**Goal:** Remove the six superseded Dockerfiles, the superseded compose, and the four dead R files (two `Simple` schedulers, the original `updateScheduler.R` overwritten in Task 4 — wait, that one was overwritten by `git mv`, so it's already gone — and the dead non-rust `update_all_leagues_loop.R` overwritten in Task 4). Verify nothing the production stack or season-transition needs is being deleted.

**Files:**
- Delete: `Dockerfile.simple`, `Dockerfile.league`, `Dockerfile.shiny`, `Dockerfile.optimized`, `Dockerfile.test`  *(`DOCKERFILE` was pulled forward to Task 2 due to case-insensitive-filesystem collision)*
- Delete: `docker-compose.simple.yml`
- Delete: `RCode/updateSchedulerSimple.R`, `RCode/updateSchedulerSimple_local.R`

> **Note on the original `RCode/updateScheduler.R` and `RCode/update_all_leagues_loop.R`:** Both were overwritten by the `git mv` operations in Task 4 (because the renames pointed to filenames that already existed as dead files). Git treats this as "rename + delete" in one step. So there is nothing to delete here for those two files — they're already gone.

- [ ] **Step 1: Confirm the survivor list before deleting anything**

```bash
grep -E "season_validation|elo_aggregation|api_service|api_helpers|interactive_prompts|input_validation|csv_generation|file_operations|season_processor|league_processor|error_handling|input_handler|team_config_loader|team_data_carryover|SpielCPP" Dockerfile.simple Dockerfile.league Dockerfile.shiny Dockerfile.optimized DOCKERFILE Dockerfile.test docker-compose.simple.yml RCode/updateSchedulerSimple.R RCode/updateSchedulerSimple_local.R 2>/dev/null
```

Expected: zero matches (or only matches that are clearly not source-import statements). If any of these dead files import a survivor module by name, stop and investigate — the survivor may have a hidden second consumer.

- [ ] **Step 2: Delete the five remaining dead Dockerfiles** *(legacy `DOCKERFILE` already deleted in Task 2)*

```bash
git rm Dockerfile.simple Dockerfile.league Dockerfile.shiny Dockerfile.optimized Dockerfile.test
```

Expected output: five `rm 'Dockerfile.…'` lines.

- [ ] **Step 3: Delete the dead compose file**

```bash
git rm docker-compose.simple.yml
```

- [ ] **Step 4: Delete the two `Simple` schedulers**

```bash
git rm RCode/updateSchedulerSimple.R RCode/updateSchedulerSimple_local.R
```

- [ ] **Step 5: Verify no Dockerfile-related files remain except `Dockerfile`**

```bash
ls -1 | grep -i "^dockerfile\|^docker-compose"
```

Expected output (exactly two lines):
```
Dockerfile
docker-compose.yml
```

- [ ] **Step 6: Verify the production scheduler/loop are the only ones in `RCode/`**

```bash
ls RCode/updateScheduler*.R RCode/update_all_leagues_loop*.R
```

Expected output (exactly two files):
```
RCode/updateScheduler.R
RCode/update_all_leagues_loop.R
```

- [ ] **Step 7: Rebuild the production image to confirm nothing load-bearing was deleted**

```bash
docker build -f Dockerfile -t league-simulator:after-deletes-1 .
```

Expected: build succeeds.

- [ ] **Step 8: Run the season-transition smoke check**

```bash
Rscript -e 'tryCatch(source("scripts/season_transition.R"), error = function(e) cat("ERROR:", e$message, "\n"))' 2>&1 | tee /tmp/season-transition-after-task-6.txt
```

Expected: same error message as the baseline captured in Task 1, Step 8 (`/tmp/season-transition-baseline.txt`). The script must reach the args-parsing failure, **not** fail on a missing `source()`. Diff for sanity:

```bash
diff /tmp/season-transition-baseline.txt /tmp/season-transition-after-task-6.txt
```

Expected: no meaningful diff (timestamps in messages may differ; module-load lines should be identical).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: delete dead Dockerfiles, compose, and Simple schedulers

Removed:
- Dockerfile.simple, Dockerfile.league, Dockerfile.shiny,
  Dockerfile.optimized, DOCKERFILE, Dockerfile.test
- docker-compose.simple.yml
- RCode/updateSchedulerSimple.R, RCode/updateSchedulerSimple_local.R

The original RCode/updateScheduler.R and RCode/update_all_leagues_loop.R
were overwritten by the renames in the previous task (git treated them
as rename targets), so they're already gone.

Recovery available via tag pre-deployment-cleanup-2026-05-02. (issue #78)"
```

---

## Task 7: Delete `docker/`, `k8s/`, and the eight k8s-era scripts

**Goal:** Remove the microservices artifacts. Confirm by grep that no surviving file references them, then delete and re-verify the production build.

**Files:**
- Delete directory: `docker/`
- Delete directory: `k8s/`
- Delete: `scripts/deploy_pod_lifecycle.sh`, `scripts/generate_cronjobs.sh`, `scripts/calculate_cronjob_schedules.sh`, `scripts/activate_lifecycle.sh`, `scripts/emergency_rollback.sh`, `scripts/docker_build_all.sh`, `scripts/deploy-local.sh`, `scripts/status.sh`

- [ ] **Step 1: Verify nothing surviving references `docker/`'s healthcheck scripts**

```bash
grep -rln "docker/healthcheck-league\|docker/healthcheck-shiny" RCode/ scripts/ tests/testthat/ Dockerfile docker-compose.yml docker-start.sh 2>/dev/null
```

Expected: no output.

- [ ] **Step 2: Verify nothing surviving references `k8s/` paths from R or shell**

```bash
grep -rln "k8s/" RCode/ scripts/ tests/testthat/ Dockerfile docker-compose.yml docker-start.sh 2>/dev/null
```

Expected output: only `RCode/csv_generation.R` (the conditional `configmap-generator.R` block — handled in Task 9). If anything else appears, stop and investigate.

- [ ] **Step 3: Verify nothing surviving sources the eight k8s-era scripts**

```bash
grep -rln "deploy_pod_lifecycle\|generate_cronjobs\|calculate_cronjob_schedules\|activate_lifecycle\|emergency_rollback\|docker_build_all\|deploy-local\|status\.sh" RCode/ scripts/season_transition.R scripts/install_test_packages.R Dockerfile docker-compose.yml docker-start.sh 2>/dev/null
```

Expected: no output. (We exclude the eight scripts themselves from the search by being explicit about what we *do* search.)

- [ ] **Step 4: Delete the `docker/` directory**

```bash
git rm -r docker/
```

Expected output: `rm 'docker/healthcheck-league.R'`, `rm 'docker/healthcheck-shiny.R'`.

- [ ] **Step 5: Delete the `k8s/` directory**

```bash
git rm -r k8s/
```

Expected output: many `rm` lines (manifests, cronjobs, configmaps, monitoring, rbac, scripts, templates).

- [ ] **Step 6: Delete the eight k8s-era shell scripts**

```bash
git rm scripts/deploy_pod_lifecycle.sh scripts/generate_cronjobs.sh scripts/calculate_cronjob_schedules.sh scripts/activate_lifecycle.sh scripts/emergency_rollback.sh scripts/docker_build_all.sh scripts/deploy-local.sh scripts/status.sh
```

- [ ] **Step 7: Verify what's left in `scripts/`**

```bash
ls scripts/
```

Expected output (exactly):
```
install_test_packages.R
season_transition.R
```

- [ ] **Step 8: Check for `RCode/test_scheduler_now.R`**

This file appears to be a test utility for the dead `updateSchedulerSimple.R`. Read it to confirm:

```bash
head -10 RCode/test_scheduler_now.R
```

If it sources or references `updateSchedulerSimple` or `updateScheduler.R` (the old one) in a way that's no longer meaningful, delete it:

```bash
git rm RCode/test_scheduler_now.R
```

If you can't tell whether it's dead, leave it for a follow-up — do not delete on uncertainty.

- [ ] **Step 9: Rebuild production image**

```bash
docker build -f Dockerfile -t league-simulator:after-deletes-2 .
```

Expected: build succeeds.

- [ ] **Step 10: Re-run the season-transition smoke check**

```bash
Rscript -e 'tryCatch(source("scripts/season_transition.R"), error = function(e) cat("ERROR:", e$message, "\n"))' 2>&1 | tee /tmp/season-transition-after-task-7.txt
diff /tmp/season-transition-baseline.txt /tmp/season-transition-after-task-7.txt
```

Expected: same error as baseline; no meaningful diff.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "chore: delete docker/, k8s/, and k8s-era scripts/ helpers

Removed:
- docker/ (healthcheck scripts, only used by deleted Dockerfile.league/shiny)
- k8s/ (microservices manifests, refactor e52f182 reverted in practice)
- scripts/{deploy_pod_lifecycle,generate_cronjobs,calculate_cronjob_schedules,
  activate_lifecycle,emergency_rollback,docker_build_all,deploy-local,status}.sh

scripts/ now contains only install_test_packages.R and season_transition.R.
Recovery available via tag pre-deployment-cleanup-2026-05-02. (issue #78)"
```

---

## Task 8: Delete `RCode/configmap_deployment.R` and the orphan ConfigMap source block in `csv_generation.R`

**Goal:** With `k8s/` gone, the optional `configmap-generator.R` source block in `csv_generation.R:79–109` can never find its target. Delete the block and the standalone `configmap_deployment.R` file. This is the only behavioral change in the entire plan, and it's a strict subtraction (one optional code path removed).

**Files:**
- Delete: `RCode/configmap_deployment.R`
- Modify: `RCode/csv_generation.R` (remove lines 79–109, the `tryCatch` block)

- [ ] **Step 1: Confirm `configmap_deployment.R` has no R callers**

```bash
grep -rln "configmap_deployment\|verify_configmap_deployment" RCode/ scripts/ tests/testthat/ 2>/dev/null
```

Expected output: only `RCode/configmap_deployment.R` itself (the file that defines the function). If `csv_generation.R` shows up here with a `verify_configmap_deployment` call, stop — there's a coupling we missed.

- [ ] **Step 2: Confirm the `configmap-generator.R` source block is the only consumer of the `k8s/templates/` path inside `csv_generation.R`**

```bash
grep -n "configmap\|k8s/" RCode/csv_generation.R
```

Expected output (matches the PRD's identification of the block):
```
83:            "k8s/templates/configmap-generator.R",
84:            file.path("..", "k8s", "templates", "configmap-generator.R"),
85:            file.path("..", "..", "k8s", "templates", "configmap-generator.R"),
86:            file.path(getwd(), "k8s", "templates", "configmap-generator.R")
89:        configmap_generator_path <- NULL
92:                configmap_generator_path <- path
97:        if (!is.null(configmap_generator_path)) {
98:            source(configmap_generator_path)
99:            yaml_file <- generate_configmap_yaml(file_path, season, version = "1.0.0")
100:            cat("✓ Generated ConfigMap YAML:", yaml_file, "\n")
104:                cat("ConfigMap generator not found, skipping YAML generation\n")
108:        cat("Warning: Could not generate ConfigMap YAML:", e$message, "\n")
```

- [ ] **Step 3: Read the surrounding context to find the precise extent of the block to remove**

```bash
sed -n '75,115p' RCode/csv_generation.R
```

The block starts at the line containing `# Generate corresponding ConfigMap YAML if ConfigMap generator is available` (around line 79) and ends at the closing `})` of the outer `tryCatch` (around line 109). Read these lines carefully so the next step removes exactly the right range.

- [ ] **Step 4: Remove the ConfigMap block from `csv_generation.R`**

Use the Edit tool (not `sed`, since the block contains parentheses and special characters that are easy to miscount). Find this exact block in `RCode/csv_generation.R`:

```r
    # Generate corresponding ConfigMap YAML if ConfigMap generator is available
    tryCatch({
        # Try multiple paths for the configmap generator
        possible_paths <- c(
            "k8s/templates/configmap-generator.R",
            file.path("..", "k8s", "templates", "configmap-generator.R"),
            file.path("..", "..", "k8s", "templates", "configmap-generator.R"),
            file.path(getwd(), "k8s", "templates", "configmap-generator.R")
        )
        
        configmap_generator_path <- NULL
        for (path in possible_paths) {
            if (file.exists(path)) {
                configmap_generator_path <- path
                break
            }
        }
        
        if (!is.null(configmap_generator_path)) {
            source(configmap_generator_path)
            yaml_file <- generate_configmap_yaml(file_path, season, version = "1.0.0")
            cat("✓ Generated ConfigMap YAML:", yaml_file, "\n")
        } else {
            # This is not an error - ConfigMap generation is optional
            if (interactive() || getOption("verbose", FALSE)) {
                cat("ConfigMap generator not found, skipping YAML generation\n")
            }
        }
    }, error = function(e) {
        cat("Warning: Could not generate ConfigMap YAML:", e$message, "\n")
    })
    
```

Replace it with nothing (delete the block, including the trailing blank line). The surrounding lines (the `cat("Team list CSV created successfully:", ...)` block above and the `return(file_path)` below) stay unchanged.

- [ ] **Step 5: Verify the block is gone**

```bash
grep -n "configmap\|k8s/" RCode/csv_generation.R
```

Expected: no output.

- [ ] **Step 6: Verify R can still parse the modified file**

```bash
Rscript -e 'parse("RCode/csv_generation.R"); cat("OK\n")'
```

Expected: `OK`.

- [ ] **Step 7: Delete `RCode/configmap_deployment.R`**

```bash
git rm RCode/configmap_deployment.R
```

- [ ] **Step 8: Re-run the season-transition smoke check (this task touched a season-transition module)**

```bash
Rscript -e 'tryCatch(source("scripts/season_transition.R"), error = function(e) cat("ERROR:", e$message, "\n"))' 2>&1 | tee /tmp/season-transition-after-task-8.txt
diff /tmp/season-transition-baseline.txt /tmp/season-transition-after-task-8.txt
```

Expected: same error as baseline; no meaningful diff. **This is the critical canary** — `csv_generation.R` is part of the season-transition workflow, and we just edited it.

- [ ] **Step 9: Rebuild the Docker image**

```bash
docker build -f Dockerfile -t league-simulator:after-deletes-3 .
```

Expected: build succeeds.

- [ ] **Step 10: Commit**

```bash
git add RCode/csv_generation.R RCode/configmap_deployment.R
git commit -m "chore: remove orphan ConfigMap generation from csv_generation.R

Deleted RCode/configmap_deployment.R and the optional tryCatch block in
RCode/csv_generation.R that conditionally sourced
k8s/templates/configmap-generator.R. With k8s/ deleted, the path could
never be found and the block was strictly dead weight.

Season-transition smoke check still passes. (issue #78)"
```

---

## Task 9: Update `CLAUDE.md` to remove dead Dockerfile references and fix the Simple Deployment pointer

**Goal:** `CLAUDE.md` has three lines that reference deleted files: lines 19 and 20 in the Quick Commands block (`Dockerfile.simple`, `docker-compose.simple.yml`) and line 70 (the Simple Deployment doc pointer). Update all three.

**Files:**
- Modify: `CLAUDE.md` (lines 19, 20, and 70)

- [ ] **Step 1: Inspect the current state**

```bash
grep -n "Dockerfile\.simple\|docker-compose\.simple\|Simple Deployment\|simple-monolithic" CLAUDE.md
```

Expected output (three lines):
```
19:docker build -f Dockerfile.simple -t league-simulator:simple .
20:docker-compose -f docker-compose.simple.yml up -d
70:  - **Simple Deployment** (Recommended): @docs/deployment/simple-monolithic.md
```

- [ ] **Step 2: Update the Quick Commands block (lines 19–20)**

Use the Edit tool to find this exact text in `CLAUDE.md`:

```markdown
# Build and run Docker (simple version)
docker build -f Dockerfile.simple -t league-simulator:simple .
docker-compose -f docker-compose.simple.yml up -d
```

Replace with:

```markdown
# Build and run the production Docker stack
docker build -t league-simulator:latest .
docker-compose up -d
```

(Drops `-f` flags since `Dockerfile` and `docker-compose.yml` are now the defaults.)

- [ ] **Step 3: Update the Simple Deployment pointer (line 70)**

Find this exact text in `CLAUDE.md`:

```markdown
  - **Simple Deployment** (Recommended): @docs/deployment/simple-monolithic.md
```

Replace with:

```markdown
  - **Production Deployment**: @docs/deployment/README.md
```

- [ ] **Step 4: Verify all three references are gone**

```bash
grep -n "Dockerfile\.simple\|docker-compose\.simple\|Simple Deployment\|simple-monolithic" CLAUDE.md
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md to reference renamed Dockerfile and new README

Replaced:
- Dockerfile.simple / docker-compose.simple.yml -> default Dockerfile / docker-compose.yml
- 'Simple Deployment (Recommended)' pointer -> 'Production Deployment' pointing to docs/deployment/README.md (created in next task)

(issue #78)"
```

---

## Task 10: Replace `docs/deployment/simple-monolithic.md` with a new `docs/deployment/README.md`

**Goal:** Delete the misleading `simple-monolithic.md` (which described the now-deleted simple stack as "Recommended") and write a new `docs/deployment/README.md` that documents the actual production stack.

**Files:**
- Delete: `docs/deployment/simple-monolithic.md`
- Create: `docs/deployment/README.md`

- [ ] **Step 1: Delete the misleading doc**

```bash
git rm docs/deployment/simple-monolithic.md
```

- [ ] **Step 2: Create the new operator README**

Create `docs/deployment/README.md` with this exact content:

````markdown
# Deployment

The League Simulator runs as a single Docker container that combines the Rust simulation engine and the R scheduler. This is the only production deployment path.

## Stack

- **`Dockerfile`** — multi-stage build: Rust 1.81 (alpine) compiles the simulation binary in stage 1; `rocker/r-ver:4.3.1` runs the R scheduler in stage 2.
- **`docker-compose.yml`** — single service `league-simulator-integrated`, exposes port 8081 → container port 8080 (Rust API for monitoring).
- **`docker-start.sh`** — container entrypoint. Starts the Rust server on `localhost:8080`, waits for it to be healthy, then runs `Rscript RCode/updateScheduler.R` with retry logic.
- **`RCode/updateScheduler.R`** — the R scheduler. Wakes at 14:45 Berlin time, polls api-football, calls the in-process Rust server when new fixtures arrive, pushes results to ShinyApps.io.

## Schedule

- **Active hours:** 14:45 – 22:45 Berlin time (`updateScheduler.R` enforces both bounds).
- **Loop frequency:** every 2 minutes inside the active window (Rust engine is fast enough to allow this).
- **Outside the window:** the scheduler sleeps until the next 14:45.

## Required environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `RAPIDAPI_KEY` | yes | — | api-football access via RapidAPI |
| `SHINYAPPS_IO_SECRET` | yes | — | ShinyApps.io deployment auth |
| `SHINYAPPS_IO_NAME` | no | `chrisschwer` | ShinyApps.io account name |
| `SHINYAPPS_IO_TOKEN` | no | (set in compose) | ShinyApps.io token |
| `SEASON` | no | auto-detect | Season year (e.g., `2025`); auto-detects from current month if unset |
| `DURATION` | no | `480` | Cap on scheduler runtime in minutes |
| `RUST_API_URL` | no | `http://localhost:8080` | Rust server endpoint inside the container |
| `TZ` | no | `Europe/Berlin` | Container timezone |

## Build and run

```bash
# Build
docker build -t league-simulator:latest .

# Run via docker-compose (recommended)
docker-compose up -d

# Inspect logs
docker-compose logs -f league-simulator-integrated

# Stop
docker-compose down
```

## Health check

The container exposes `http://localhost:8081/health` (the Rust server's health endpoint). Docker's `HEALTHCHECK` directive in the Dockerfile polls this every 30 seconds.

## Recovery

If you need to compare against the pre-cleanup deployment surface (which had multiple Dockerfiles, a `k8s/` directory, and several scheduler variants), check out the annotated tag:

```bash
git checkout pre-deployment-cleanup-2026-05-02
```

That tag captures the full pre-cleanup tree.

## Operator-side workflows (not covered here)

The season-transition workflow is a separate, locally-invoked operator procedure that runs **before** a container rebuild to produce fresh `RCode/TeamList_<year>.csv` files. It does not run inside the production container.

- **Operator guide:** [`docs/user-guide/season-transition.md`](../user-guide/season-transition.md)
- **Recent changes:** [`docs/SEASON_TRANSITION_UPDATES.md`](../SEASON_TRANSITION_UPDATES.md)
- **Discoverability for validation/report/cleanup helpers:** GitHub issue #74
````

- [ ] **Step 3: Sanity-check the new README**

```bash
test -f docs/deployment/README.md && echo "OK" || echo "MISSING"
wc -l docs/deployment/README.md
```

Expected: `OK`, ~70 lines.

- [ ] **Step 4: Verify `CLAUDE.md`'s pointer (set in Task 9) resolves**

```bash
grep "docs/deployment/README.md" CLAUDE.md
```

Expected: at least one match.

- [ ] **Step 5: Commit**

```bash
git add docs/deployment/simple-monolithic.md docs/deployment/README.md
git commit -m "docs: replace simple-monolithic.md with deployment/README.md

The old doc described a stack (Dockerfile.simple + docker-compose.simple.yml)
that was deleted in this PRD. The new README documents the actual production
stack (single Dockerfile + docker-compose.yml + docker-start.sh +
RCode/updateScheduler.R) and points operators to the season-transition
workflow docs. (issue #78)"
```

---

## Task 11: Footnote the microservices section in `docs/architecture/overview.md`

**Goal:** The architecture overview has a "Microservices Migration" section (line 332) describing the now-deleted microservices design as the future direction. Mark it as historical context, not roadmap, so future readers don't reintroduce the complexity.

**Files:**
- Modify: `docs/architecture/overview.md` (insert a note before the "Microservices Migration" subsection at line 332)

- [ ] **Step 1: Inspect the current section header and surrounding context**

```bash
sed -n '328,345p' docs/architecture/overview.md
```

Expected: shows the section heading `### Microservices Migration` near line 332 inside a larger "Future Architecture Considerations" or similar parent section.

- [ ] **Step 2: Insert a historical-context note immediately after the section heading**

Use the Edit tool. Find this exact text in `docs/architecture/overview.md`:

```markdown
### Microservices Migration
```

Replace with:

```markdown
### Microservices Migration

> **Historical context (2026-05-02):** A microservices split was attempted (see git tag `pre-deployment-cleanup-2026-05-02` for the full multi-Dockerfile + `k8s/` tree) and reverted in favor of a single integrated container that runs the Rust simulation engine and the R scheduler in one process group. The diagram below documents the rejected design; it is **not** the current or planned architecture. See `docs/deployment/README.md` for what's actually deployed.
```

- [ ] **Step 3: Verify the note landed**

```bash
grep -A1 "Historical context (2026-05-02)" docs/architecture/overview.md | head -3
```

Expected: shows the note text.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/overview.md
git commit -m "docs: footnote microservices section as historical, not roadmap

The 'Microservices Migration' section described a design that was
attempted and reverted. Mark it explicitly so future readers don't
mistake it for the current direction. (issue #78)"
```

---

## Task 12: Run the acceptance grep and final smoke tests

**Goal:** Verify the PRD's acceptance criteria pass against the cleaned-up tree (within the source-code scope this plan committed to). Build the final image, compare against the pre-cleanup baseline, and confirm everything is green.

**Files:**
- No file changes. This task is verification-only.

- [ ] **Step 1: Run the source-code-scoped legacy-name grep**

```bash
grep -rEn "Dockerfile\.(simple|league|shiny|optimized|integrated|test)|docker-compose\.(simple|integrated)|updateSchedulerRust|updateSchedulerSimple|update_all_leagues_loop_rust|docker-integrated-start|configmap_deployment|configmap-generator" RCode/ scripts/ tests/testthat/ Dockerfile docker-compose.yml docker-start.sh CLAUDE.md docs/deployment/README.md 2>/dev/null
```

Expected: **no output**. If any line appears, it identifies a stale reference inside the source-code scope; fix before continuing.

- [ ] **Step 2: Run the survivor-list grep**

```bash
grep -rEn "season_validation|elo_aggregation|api_service|api_helpers|interactive_prompts|input_validation|csv_generation|file_operations|season_processor|league_processor|error_handling|input_handler|team_config_loader|team_data_carryover|SpielCPP" scripts/season_transition.R | head -20
```

Expected: shows ~18 lines (`source()` and `safe_source()` calls in `scripts/season_transition.R`) — the season-transition modules are still there and still referenced. If this comes back empty, the survivor list has been broken and we have a regression.

- [ ] **Step 3: Build the post-cleanup image**

```bash
docker build -f Dockerfile -t league-simulator:post-cleanup .
```

Expected: build succeeds.

- [ ] **Step 4: Compare image layer counts**

```bash
PRE=$(docker history --no-trunc --format '{{.ID}}' league-simulator:pre-cleanup | wc -l)
POST=$(docker history --no-trunc --format '{{.ID}}' league-simulator:post-cleanup | wc -l)
echo "Pre-cleanup layers: $PRE"
echo "Post-cleanup layers: $POST"
```

Expected: identical (or off by ≤1 if one of the renames changed cache-key boundaries). The build steps are byte-identical apart from the renamed `COPY docker-start.sh` line.

- [ ] **Step 5: `docker-compose config` final check**

```bash
docker-compose config > /dev/null && echo "compose OK"
```

Expected: `compose OK`.

- [ ] **Step 6: Final season-transition smoke check**

```bash
Rscript -e 'tryCatch(source("scripts/season_transition.R"), error = function(e) cat("ERROR:", e$message, "\n"))' 2>&1 | tee /tmp/season-transition-final.txt
diff /tmp/season-transition-baseline.txt /tmp/season-transition-final.txt
```

Expected: same baseline error; no meaningful diff.

- [ ] **Step 7: Show the final repo-root and `RCode/` Dockerfile/scheduler shape**

```bash
ls -1 | grep -i "^dockerfile\|^docker-compose\|^docker-start"
echo '---'
ls RCode/updateScheduler*.R RCode/update_all_leagues_loop*.R RCode/configmap_deployment.R 2>&1
echo '---'
ls scripts/
```

Expected:
```
docker-compose.yml
docker-start.sh
Dockerfile
---
RCode/updateScheduler.R
RCode/update_all_leagues_loop.R
ls: RCode/configmap_deployment.R: No such file or directory
---
install_test_packages.R
season_transition.R
```

- [ ] **Step 8: Show `git log` of the cleanup commits for the record**

```bash
git log --oneline pre-deployment-cleanup-2026-05-02..HEAD
```

Expected: 10 commits (Tasks 2 through 11; Task 1 made no commit, Task 12 makes none).

- [ ] **Step 9: No commit needed**

This task only ran checks. If everything is green, the plan is complete and ready to merge to `main` (or push to a feature branch and open a PR, per your normal workflow).

---

## Acceptance Criteria Mapping (PRD ↔ Plan)

This is the self-review check the writing-plans skill requires. Each PRD acceptance criterion maps to one or more tasks:

| PRD Acceptance Criterion | Implementing Task(s) |
|---|---|
| Annotated tag `pre-deployment-cleanup-2026-05-02` exists | Task 1, Steps 3–5 |
| Repo root has exactly one Dockerfile, one compose, one start script | Tasks 2, 3, 5 (renames) + Task 6, Step 5 (verification) |
| `RCode/` has exactly one scheduler and one loop | Task 4 (renames overwrite duplicates) + Task 6, Step 6 (verification) |
| `docker/` and `k8s/` no longer exist | Task 7, Steps 4–5 |
| All k8s-era helpers in `scripts/` no longer exist | Task 7, Step 6 + Step 7 (verification) |
| `docker build -f Dockerfile -t league-simulator:test .` succeeds | Tasks 2, 3, 4, 6, 7, 8, 12 (all rebuild after each change) |
| `docker-compose config` parses cleanly | Task 5, Step 4 + Task 12, Step 5 |
| Source-code-scoped legacy-name grep returns zero matches | Task 12, Step 1 |
| `simple-monolithic.md` deleted; new `README.md` documents the stack | Task 10 |
| `CLAUDE.md` Simple Deployment pointer replaced | Task 9 |
| `docs/architecture/overview.md` microservices section footnoted | Task 11 |
| Season-transition smoke test passes after cleanup | Task 6, Step 8; Task 7, Step 10; Task 8, Step 8; Task 12, Step 6 |
| `RCode/configmap_deployment.R` deleted; `csv_generation.R` block removed | Task 8 |

**Out-of-plan-scope (per Option 1 decision):** Doc cleanup across `docs/deployment/{detailed-guide,local-development,production,rollback,simplified-microservices,quick-start,ci-cd-guide}.md`, `tests/REVISED_TEST_SPECIFICATIONS.md`, `tests/container-league.yaml`, `tests/docker/`, `RUST_INTEGRATION.md`, `PRD_ISSUE_1_monolithic_deployment.md`, `.claude/development_workflow.md`, `.claude/testing_and_build.md`. A separate GitHub issue tracks this.

## Self-Review Notes

Performed before publishing:

1. **Spec coverage:** All 12 PRD acceptance criteria map to a concrete task and step. The PRD's 8-step migration plan corresponds to Tasks 1–11 (split for granularity). The PRD's "Files that must survive" subsection drives the survivor-list grep in Task 12, Step 2.

2. **Placeholder scan:** No `TBD`, `TODO`, `implement later`, or `add appropriate X` placeholders. Every code block is the literal text the engineer should produce. The one judgment call (Task 7 Step 8: whether to delete `RCode/test_scheduler_now.R`) is explicit about its uncertainty.

3. **Type / name consistency:** The renamed function is `update_all_leagues_loop` (no qualifier) in both its definition (Task 4 Step 5) and its call site (Task 4 Step 4). The renamed scheduler is `updateScheduler.R` everywhere. The renamed start script is `docker-start.sh` everywhere. The new doc is `docs/deployment/README.md` everywhere.
