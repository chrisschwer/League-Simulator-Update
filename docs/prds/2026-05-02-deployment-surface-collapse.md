# Collapse deployment surface to one production stack

**Scope:** repository root (Dockerfiles, docker-compose files, `docker/`, `k8s/`, `scripts/` deployment helpers) and `.github/workflows/` (inventory only). **Out of scope but must continue to work:** the season-transition operator workflow (`scripts/season_transition.R` and the 15 `RCode/` modules it depends on, per `docs/SEASON_TRANSITION_UPDATES.md` and issue #74).
**Date:** 2026-05-02
**Source:** architecture-review-prd skill

## Goal

The repo contains exactly one production deployment stack — `Dockerfile.integrated` + `docker-compose.integrated.yml` + `docker-integrated-start.sh` + `RCode/updateSchedulerRust.R` — and a new operator README that documents it as the only path. All previous deployment experiments (simple/league/shiny/optimized Dockerfiles, the legacy `DOCKERFILE`, the `k8s/` directory, the unused schedulers) are removed from the working tree. **The season-transition operator workflow continues to work unchanged**: `Rscript scripts/season_transition.R 2024 2025` produces a valid `RCode/TeamList_2025.csv` after the cleanup, and the operator-tool wrappers from issue #74 still resolve their dependencies.

## Architecture

A single Docker image, built from `Dockerfile.integrated`, runs both the Rust simulation server (on `localhost:8080` inside the container) and the R scheduler (`updateSchedulerRust.R`) under `docker-integrated-start.sh`. The scheduler wakes at 14:45 Berlin time, polls the api-football endpoint for new fixtures, calls the in-process Rust server for Monte Carlo simulations when new results arrive (or on first run), and pushes updated probability matrices to ShinyApps.io. `docker-compose.integrated.yml` is the only orchestrator file. Everything else is deleted.

## Tech Stack

R 4.3.1 (rocker/r-ver:4.3.1), Rust 1.81 (alpine builder stage), Docker + docker-compose v2/v3 syntax, ShinyApps.io as the publication target. No new dependencies. Tests use testthat 3.x but are out of scope for this PRD (see `2026-05-02-ci-rebuild.md` reminder issue).

## The Finding

### Current State

- **Dockerfiles in repo root (7):**
  - `Dockerfile.integrated` — production (last touched `b11f068`, 2025-08-15)
  - `Dockerfile.simple` — superseded monolithic experiment (`79d82f6`, 2025-08-03)
  - `Dockerfile.league` — microservices split, league pod (`b078c84`, 2025-07-29)
  - `Dockerfile.shiny` — microservices split, shiny pod (`b078c84`, 2025-07-29)
  - `Dockerfile.optimized` — size-optimization experiment (`852922c`, 2025-07-19)
  - `DOCKERFILE` — original 2024 build (`b458a84`, 2024-05-30)
  - `Dockerfile.test` — disabled CI image (`1b23909`, 2025-07-19)
- **Compose files (2):** `docker-compose.integrated.yml` (production), `docker-compose.simple.yml` (superseded)
- **Schedulers in `RCode/` (4):** `updateSchedulerRust.R` (production, sourced by `docker-integrated-start.sh:70`), `updateScheduler.R`, `updateSchedulerSimple.R`, `updateSchedulerSimple_local.R` (all unreferenced from production)
- **Loop orchestrators (2):** `update_all_leagues_loop_rust.R` (sourced by `updateSchedulerRust.R:48`), `update_all_leagues_loop.R` (only sourced by the dead simple-schedulers)
- **`k8s/` directory:** microservices manifests from refactor `e52f182` ("Refactoring into microservices") — no longer referenced by any production path
- **`docker/` directory:** `healthcheck-league.R` and `healthcheck-shiny.R`, only used by `Dockerfile.league` / `Dockerfile.shiny`
- **`scripts/` deployment helpers:** `deploy_pod_lifecycle.sh`, `generate_cronjobs.sh`, `calculate_cronjob_schedules.sh`, `activate_lifecycle.sh`, `emergency_rollback.sh`, `docker_build_all.sh`, `deploy-local.sh`, `status.sh` — all assume the multi-pod k8s architecture
- **`.github/workflows/`:** 13 disabled files (`*.disabled` and `.bak`); no active workflow
- **Operator-facing docs claiming production status:**
  - `docs/deployment/simple-monolithic.md` — describes the *deleted-by-this-PRD* simple stack as "Recommended"
  - `CLAUDE.md` line 11: "**Simple Deployment** (Recommended): @docs/deployment/simple-monolithic.md"
  - `docs/deployment/quick-start.md` — references generic `docker-compose build`, doesn't name a file

**Callers of the production scheduler:** `docker-integrated-start.sh:70` is the only caller of `updateSchedulerRust.R`. No other entry point invokes it.

**Second operator entry point (must survive):** `scripts/season_transition.R` is invoked manually before each season rollover (per `docs/SEASON_TRANSITION_UPDATES.md` and the `--non-interactive` flag for Docker/CI use). It sources 15 transition-specific `RCode/` modules plus three reused ones (`retrieveResults.R`, `transform_data.R`, `SpielCPP.R`). It is **not** in the production Docker container's runtime path — it runs locally before a container rebuild — but the files it sources must remain present in the repo. Issue #74 also tracks an enhancement to make the validation/report/cleanup helpers in `season_processor.R` discoverable; this PRD must not break that.

**Test coverage today:** No tests exercise the deployment surface directly. `tests/testthat/test-deployment.R` exists but its scope is unclear and tied to disabled CI (out of scope here).

### Why this is a problem

Six dead Dockerfiles plus a dead k8s directory plus contradictory docs ("Simple Deployment is Recommended") force every contributor — and you, six months from now — to figure out which path is real before changing anything. That's a high tax on every operation. The deletion test: removing `Dockerfile.simple`, `Dockerfile.league`, `Dockerfile.shiny`, `Dockerfile.optimized`, the bare `DOCKERFILE`, `Dockerfile.test`, `docker-compose.simple.yml`, the three dead schedulers, the legacy loop, and the entire `k8s/` directory bundles the deployment-truth complexity from "scattered across 15+ files plus contradictory docs" to "one Dockerfile + one compose + one shell script + one README section." That is a deeper module — smaller interface, same implementation. The current state is also a documentation hazard: `CLAUDE.md` actively misdirects to `simple-monolithic.md`, and a future you will follow that pointer and rebuild the wrong image.

This isn't a refactor of working code — it is a deletion of unused code that's actively confusing. Low risk, high clarity gain.

**The season-transition workflow is the one operator path that looks dead from a code-grep but isn't.** Per `docs/SEASON_TRANSITION_UPDATES.md` and issue #74, `scripts/season_transition.R` is invoked manually between seasons to produce fresh `RCode/TeamList_<year>.csv` files that are then bundled into a new container build. The 15 transition-specific `RCode/` modules and the three reused ones (`retrieveResults.R`, `transform_data.R`, `SpielCPP.R`) are all live. Listed explicitly in the "Files that must survive" subsection below so they can't be swept up in the deletion pass by accident.

### Files that must survive (season-transition operator workflow)

The deletion pass must not touch any of these. They are referenced directly or transitively by `scripts/season_transition.R`. Verified via grep on `source()` calls in the transition entry point and each of its dependencies.

**Entry point:**
- `scripts/season_transition.R`

**Transition-specific `RCode/` modules (15):**
- `season_validation.R`, `elo_aggregation.R`, `api_service.R`, `api_helpers.R`, `interactive_prompts.R`, `input_validation.R`, `csv_generation.R`, `file_operations.R`, `season_processor.R`, `league_processor.R`, `error_handling.R`, `logging.R`, `input_handler.R`, `team_config_loader.R`, `team_data_carryover.R`

**Reused by both production and transition (3):**
- `retrieveResults.R`, `transform_data.R`, **`SpielCPP.R`** ← see note below

**Operator docs that must continue to be accurate:**
- `docs/SEASON_TRANSITION_UPDATES.md`, `docs/user-guide/season-transition.md` (per issue #74 wrapper-script work)

**Note on `SpielCPP.R`:** This file is sourced by `scripts/season_transition.R:65` (in `existing_modules`). The companion PRD `2026-05-02-simulation-engine-seam.md` originally listed it for deletion as part of retiring the C++ engine — that was incorrect and has been amended. Either `SpielCPP.R` and its transitive Rcpp dependencies survive (decision to make: which?), **or** the season-transition workflow needs to be migrated to use the Rust seam first. The simulation-engine PRD now defers the C++ deletion until that question is answered. For *this* PRD, treat `SpielCPP.R` as a survivor.

**Optional dependency to investigate:** `RCode/csv_generation.R:97–98` conditionally sources a `configmap_generator` script (likely `RCode/configmap_deployment.R`) if found, for k8s ConfigMap generation. This is a soft dependency on the k8s-era code that *this* PRD deletes. Two options: (a) delete `configmap_deployment.R` along with `k8s/` and remove the optional `source()` block from `csv_generation.R` lines 87–106; (b) keep `configmap_deployment.R` if you ever want ConfigMap generation as a future option. **Recommendation: (a).** The k8s deployment is gone; the ConfigMap generator has no consumer. The conditional source code becomes dead weight inside `csv_generation.R`.

## Interface — Before / After

```
# BEFORE (repo root, deployment-relevant)
Dockerfile.integrated                # production
Dockerfile.simple                    # superseded
Dockerfile.league                    # superseded
Dockerfile.shiny                     # superseded
Dockerfile.optimized                 # superseded
DOCKERFILE                           # legacy (2024)
Dockerfile.test                      # disabled CI
docker-compose.integrated.yml        # production
docker-compose.simple.yml            # superseded
docker-integrated-start.sh           # production
docker/healthcheck-league.R          # only used by Dockerfile.league
docker/healthcheck-shiny.R           # only used by Dockerfile.shiny
k8s/                                 # microservices experiment, unreferenced
scripts/deploy_pod_lifecycle.sh      # k8s-era
scripts/generate_cronjobs.sh         # k8s-era
scripts/calculate_cronjob_schedules.sh  # k8s-era
scripts/activate_lifecycle.sh        # k8s-era
scripts/emergency_rollback.sh        # k8s-era
scripts/docker_build_all.sh          # k8s-era (builds all 4 images)
scripts/deploy-local.sh              # k8s-era
scripts/status.sh                    # k8s-era

# RCode/ (scheduler-relevant)
RCode/updateSchedulerRust.R          # production (sourced by docker-integrated-start.sh:70)
RCode/updateScheduler.R              # superseded
RCode/updateSchedulerSimple.R        # superseded
RCode/updateSchedulerSimple_local.R  # superseded (and contains a hardcoded local path)
RCode/update_all_leagues_loop_rust.R # production (sourced by updateSchedulerRust.R:48)
RCode/update_all_leagues_loop.R      # only sourced by dead schedulers

# AFTER (repo root, deployment-relevant)
Dockerfile                           # renamed from Dockerfile.integrated
docker-compose.yml                   # renamed from docker-compose.integrated.yml
docker-start.sh                      # renamed from docker-integrated-start.sh
# docker/ directory deleted
# k8s/ directory deleted
# All k8s-era scripts/ helpers deleted

# RCode/ (scheduler-relevant)
RCode/updateScheduler.R              # renamed from updateSchedulerRust.R (the only one left)
RCode/update_all_leagues_loop.R      # renamed from update_all_leagues_loop_rust.R (the only one left)
```

**Renames are intentional.** Once there's only one of each, the `Rust` and `integrated` qualifiers are noise — they only made sense when there were alternatives. After the deletion, the unqualified name is the truthful one.

## Design Options Considered

### Option A — Delete dead files in-tree, rename survivors *(recommended)*

> Sketch: Remove the six dead Dockerfiles, the dead compose, the dead `k8s/` and `docker/` directories, the dead scheduler/loop files, the dead `scripts/*.sh` deployment helpers. Rename `Dockerfile.integrated` → `Dockerfile`, compose → `docker-compose.yml`, scheduler → `updateScheduler.R`, loop → `update_all_leagues_loop.R`, start script → `docker-start.sh`. Update `docker-integrated-start.sh` line 70 + `Dockerfile` `CMD` + the new `docker-compose.yml` to reference the new names. Replace `docs/deployment/simple-monolithic.md` and the `CLAUDE.md` pointer with one new operator README that names the single stack.
> Trade-off: Best clarity gain. Worst short-term risk: a rename can break a script you haven't found yet. Mitigation is grep before merging.
> Migration cost: ~1–2 hours. Mostly deletion plus 5 small edits to wire renames.

### Option B — Move dead files to `archive/`, no renames

> Sketch: `git mv` the dead files to an `archive/` subdirectory, leave production names alone. Update `CLAUDE.md` to say "production = `Dockerfile.integrated`."
> Trade-off: Reversible (you could restore an experiment), but leaves the cognitive load nearly intact — the `archive/` directory is still in the tree, still indexed, still searched. Future-you still has to know to ignore it. The `_rust` and `_integrated` qualifiers also persist, perpetuating the false implication that there's a non-Rust, non-integrated path.
> Migration cost: ~30 minutes. But the value is small.

### Option C — Tag a "pre-cleanup" git ref and delete with renames

> Sketch: Same as Option A, but first create an annotated tag `pre-deployment-cleanup` so the dead files are recoverable from history without polluting the tree.
> Trade-off: Same clarity gain as A, with explicit recoverability. The cost is one extra git command. This is what I'd actually do.
> Migration cost: ~1–2 hours plus one tag.

### Recommendation

**Option C** (Option A + a recovery tag). The repo's git history already preserves everything, but an annotated tag `pre-deployment-cleanup-2026-05-02` makes it trivially obvious how to find the experiments later if you ever want to compare approaches. Beyond that, Option A's deletion-with-renames is the right call: the qualifiers (`_rust`, `_integrated`, `_simple`) only meant something when there was a choice. After this PRD, there is no choice, and the qualifiers become misleading. If you change your mind later and want to revive an experiment, the tag is one `git checkout` away.

The trade-off only flips if you genuinely expect to A/B between the simple and integrated stacks again. From your description ("the architecture I currently actually have running in production"), you don't.

## Acceptance Criteria

- [ ] Annotated tag `pre-deployment-cleanup-2026-05-02` exists at the pre-deletion HEAD.
- [ ] Repo root contains exactly one Dockerfile (`Dockerfile`), one compose file (`docker-compose.yml`), and one start script (`docker-start.sh`).
- [ ] `RCode/` contains exactly one scheduler file (`updateScheduler.R`) and one loop orchestrator (`update_all_leagues_loop.R`).
- [ ] `docker/` and `k8s/` directories no longer exist.
- [ ] All k8s-era helpers in `scripts/` no longer exist (`deploy_pod_lifecycle.sh`, `generate_cronjobs.sh`, `calculate_cronjob_schedules.sh`, `activate_lifecycle.sh`, `emergency_rollback.sh`, `docker_build_all.sh`, `deploy-local.sh`, `status.sh`).
- [ ] `docker build -f Dockerfile -t league-simulator:test .` succeeds against the renamed `Dockerfile`.
- [ ] `docker-compose config` against the renamed `docker-compose.yml` parses cleanly and references the new image / start-script names.
- [ ] `grep -rn "Dockerfile\.\(simple\|league\|shiny\|optimized\|integrated\|test\)\|docker-compose\.\(simple\|integrated\)\|updateSchedulerRust\|updateSchedulerSimple\|update_all_leagues_loop_rust\|docker-integrated-start" .` returns zero matches.
- [ ] `docs/deployment/simple-monolithic.md` is deleted; a new `docs/deployment/README.md` documents the single stack including the 14:45 Berlin schedule and the Rust + R + Shiny flow.
- [ ] `CLAUDE.md` line 11 ("Simple Deployment (Recommended)") is replaced with a pointer to the new `docs/deployment/README.md`.
- [ ] `docs/architecture/overview.md` no longer describes a microservices future as primary architecture (or is footnoted as historical context, not roadmap).
- [ ] **Season-transition smoke test passes after the cleanup:** `Rscript scripts/season_transition.R 2024 2025 --non-interactive` (against a sandbox with a valid `RAPIDAPI_KEY` or with API mocked) sources all 18 required modules without error and produces a `RCode/TeamList_2025.csv` of the expected shape. *Or* — if running the full transition is impractical — the lighter check `Rscript -e 'source("scripts/season_transition.R")'` aborts on the missing-args check rather than on a `source()` failure (i.e., the file resolves all its dependencies before reaching the args parser).
- [ ] `RCode/configmap_deployment.R` is deleted and the optional `source()` block in `RCode/csv_generation.R` (lines 87–106) is removed. Re-run the season-transition smoke test to confirm CSV generation still works without the ConfigMap branch.

## Test Strategy

There is no behavioral change here — only deletion and renames. The "test" is that the production image still builds and runs.

### Pin current behavior (regression net, written first)

- **Build the current production image and tag it locally:** `docker build -f Dockerfile.integrated -t league-simulator:pre-cleanup .` Capture the image ID. This is the baseline.
- **Optional smoke run:** `docker run --rm -e RAPIDAPI_KEY=$RAPIDAPI_KEY -e SHINYAPPS_IO_SECRET=dummy league-simulator:pre-cleanup /app/start.sh` for 30 seconds; confirm Rust server health-check passes (the script logs `✅ Rust server ready on port 8080`). Kill it.
- **Capture the season-transition baseline:** Run `Rscript scripts/season_transition.R --help` (or with no args, depending on its behavior) and record the output. After the cleanup, the output must be identical — proves no required `source()` was severed. If a real transition fixture is available, run it end-to-end against the pre-cleanup tree and snapshot the resulting CSV.

### Prove the new shape (post-cleanup)

- **Build the renamed image:** `docker build -f Dockerfile -t league-simulator:post-cleanup .` Confirm exit code 0.
- **`docker-compose config`:** parses the new `docker-compose.yml` without warnings about missing files.
- **Image diff:** `docker history league-simulator:pre-cleanup` vs `docker history league-simulator:post-cleanup` should differ only in trivial layer hashes (because COPY paths are unchanged) — same number of layers, same package set, same final size ± noise.
- **Grep test:** the grep in the acceptance criteria returns zero matches — encoded as a CI step or one-line bash check.
- **Repo-walk test:** `git ls-files | wc -l` decreases by the expected count (the deleted files), and `git status` is clean after the rename commits.
- **Season-transition smoke test:** rerun the transition baseline command from the pre-cleanup capture; output must match. If a fixture-based end-to-end run is available, the resulting CSV must equal the pre-cleanup snapshot byte-for-byte (or row-for-row if timestamps differ).
- **Survivor-list grep:** `grep -rln "season_validation\|elo_aggregation\|api_service\|api_helpers\|interactive_prompts\|input_validation\|csv_generation\|file_operations\|season_processor\|league_processor\|error_handling\|input_handler\|team_config_loader\|team_data_carryover\|SpielCPP" RCode/ scripts/` returns the same set of files post-cleanup as pre-cleanup minus the intentionally deleted `configmap_deployment.R` reference and minus any of the dead scheduler files that happened to mention them in passing.

No new testthat tests are needed. This is a deployment cleanup, not a code change.

## Migration Steps

1. **Tag the pre-cleanup state.** `git tag -a pre-deployment-cleanup-2026-05-02 -m "Snapshot before collapsing deployment surface to one stack"`
2. **Build the current production image as a regression baseline.** Capture the image ID; optionally smoke-run for 30 seconds. **Also capture the season-transition baseline** (run `scripts/season_transition.R` against a known fixture or capture its `--help` / arg-parsing output for byte-comparison later).
3. **Rename in place (one commit).** `Dockerfile.integrated` → `Dockerfile`, `docker-compose.integrated.yml` → `docker-compose.yml`, `docker-integrated-start.sh` → `docker-start.sh`, `RCode/updateSchedulerRust.R` → `RCode/updateScheduler.R`, `RCode/update_all_leagues_loop_rust.R` → `RCode/update_all_leagues_loop.R`. Update internal references: `Dockerfile` `CMD ["/app/start.sh"]` line, `Dockerfile` `COPY docker-integrated-start.sh /app/start.sh` line, `docker-compose.yml` image/build references, `docker-start.sh` line 70 (`Rscript RCode/updateSchedulerRust.R` → `Rscript RCode/updateScheduler.R`), `RCode/updateScheduler.R` line 48 (the `source()` of the loop file). Build the renamed image; confirm parity with baseline.
4. **Delete the dead deployment surface (one commit).** Remove `Dockerfile.simple`, `Dockerfile.league`, `Dockerfile.shiny`, `Dockerfile.optimized`, `DOCKERFILE`, `Dockerfile.test`, `docker-compose.simple.yml`, `docker/`, `k8s/`, and the eight k8s-era scripts in `scripts/`. **Also delete `RCode/configmap_deployment.R`** (sole consumer was the k8s ConfigMap workflow; see "Files that must survive" note) and remove the optional `source()` block in `RCode/csv_generation.R` lines 87–106 that referenced it. Re-build to confirm no path was load-bearing. **Re-run the season-transition smoke test** to confirm CSV generation still works without the ConfigMap branch.
5. **Delete the dead schedulers and loop (one commit).** By step 3, the old `updateScheduler.R` is gone (overwritten by the rename) and the survivors to delete here are `RCode/updateSchedulerSimple.R`, `RCode/updateSchedulerSimple_local.R`, and the now-orphaned `RCode/update_all_leagues_loop.R` *(the old non-rust one — also overwritten by the rename in step 3)*. Net: this step deletes the two `Simple` schedulers only. **Confirm none of these were sourced by `scripts/season_transition.R` or its dependencies** (grep before deleting). Re-run the season-transition smoke test.
6. **Replace operator docs (one commit).** Delete `docs/deployment/simple-monolithic.md`. Write `docs/deployment/README.md` describing: the single Dockerfile + compose, the 14:45 Berlin schedule, the Rust + R + Shiny flow, the env vars (`RAPIDAPI_KEY`, `SHINYAPPS_IO_SECRET`, `SHINYAPPS_IO_NAME`, `SHINYAPPS_IO_TOKEN`, `SEASON`, `DURATION`), and how to build and run. **Add a section pointing at `docs/SEASON_TRANSITION_UPDATES.md` and `docs/user-guide/season-transition.md`** so the operator-side workflow is signposted from the deployment README. Update `CLAUDE.md` line 11 to point at the new doc.
7. **Run the grep acceptance checks.** Confirm zero matches for the legacy filenames *and* confirm the survivor-list grep still returns the expected season-transition modules.
8. **Commit and push.** Optionally, build and push the renamed image to Docker Hub under a new tag if your registry workflow expects it.

## Risks

- **Risk:** A `scripts/` shell helper or markdown doc references a deleted Dockerfile or scheduler by name, and you find out only the next time you try to deploy.
  - **Mitigation:** Step 7's grep covers source-code references. Also grep `docs/`, `README.md`, and `.claude/` for `Dockerfile.simple`, `updateSchedulerRust`, `k8s/`, etc. before merging.
- **Risk:** The rename of `updateSchedulerRust.R` → `updateScheduler.R` collides with the *deleted* `updateScheduler.R` in git's view, producing a confusing diff or merge conflict if you have local branches.
  - **Mitigation:** Do the deletion in step 5 *after* the rename in step 3 has landed on a clean tree. If you have outstanding branches that touch `updateScheduler.R`, rebase them after step 3.
- **Risk:** `docs/architecture/overview.md` describes a microservices roadmap that is no longer accurate. Future-you reads it and re-introduces complexity.
  - **Mitigation:** Either update the doc to mark the microservices section as "considered and rejected, see git tag `pre-deployment-cleanup-2026-05-02`" or delete the section. Out of scope for this PRD's acceptance criteria but mentioned in the operator README handoff.
- **Risk:** ShinyApps.io deployment uses a hardcoded image tag (`chrisschwer/league-simulator:integrated-system-deps` per `docker-compose.integrated.yml:3`) that you'd want to rename too.
  - **Mitigation:** This is a registry concern, not a repo concern. Either keep the image tag stable (the compose file just references whatever Docker Hub serves) or push under a new tag and update line 3. Decide during step 3.
- **Risk:** A file in the survivor list ("Files that must survive" subsection) gets caught in the deletion pass because it shares a naming pattern with a dead file (e.g., a future contributor sees `season_processor.R` next to `updateSchedulerSimple.R` and assumes both are equally suspect).
  - **Mitigation:** The explicit survivor list in this PRD is the contract. The acceptance-criteria smoke test (`Rscript scripts/season_transition.R 2024 2025 --non-interactive`) catches any accidental deletion before merge. Run it after step 4 *and* step 5.
- **Risk:** The optional `source()` block in `csv_generation.R:87–106` for `configmap_deployment.R` turns out to be load-bearing for some operator workflow we haven't identified.
  - **Mitigation:** It's already in an `if` branch with a "ConfigMap generation is optional" comment (line 102), so removing it should be safe. If the smoke test in step 4 passes, the path is dead.

## Open Questions

- Do you want to keep the `Dockerfile.integrated` → `Dockerfile` rename, or leave it as `Dockerfile.integrated` so the existing Docker Hub image tag (`chrisschwer/league-simulator:integrated-system-deps`) keeps making sense? My read is rename — the qualifier is no longer meaningful — but you might prefer continuity for the registry side.
- The ELO data in `RCode/TeamList_2023.csv`, `TeamList_2024.csv`, `TeamList_2025.csv` is committed alongside code. Out of scope for this cleanup, but flag for the next architecture review: data and code probably shouldn't share a directory.
- `tests/testthat/test-deployment.R` exists. Is it currently green when run locally, or is it part of the disabled-CI fallout? If it asserts things about the deleted Dockerfiles, it'll fail post-cleanup. Decide in step 4 whether to update or delete.
- The companion PRD `2026-05-02-simulation-engine-seam.md` originally proposed deleting `RCode/SpielCPP.R` and the rest of the C++ engine. Because `scripts/season_transition.R` sources `SpielCPP.R`, that PRD now defers C++ deletion until either (a) `SpielCPP.R` is confirmed safe to delete after a season-transition refactor, or (b) the season-transition workflow is migrated to use the Rust seam. Decision point: should season-transition simulation logic also move to Rust, or should the C++ engine survive specifically as the season-transition's tool? Likely a separate architecture review.

## Adjacent Observations

- The repo root contains ~25 ad-hoc R scripts (`debug_*.R`, `elv_*.R`, `compare_*.R`, `test_*.R`, plus markdown analyses like `MATCH_PROCESSING_ANALYSIS.md`, `RUST_RNG_FIX_RESULTS.md`, `EOD_SUMMARY.md`). They're not deployment-related so they're out of scope here, but they're the same class of clutter and would benefit from the same treatment in a future review.
- `RCode/retrieveResults_broken.R` is in the production code tree. The naming suggests it should not be there.
- `.github/workflows/` has 13 disabled files. Those are addressed in the CI rebuild reminder issue, not here.
