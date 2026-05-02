# CI/CD pipeline rebuild — single workflow, post-cleanup

**Issue:** [#76](https://github.com/chrisschwer/League-Simulator-Update/issues/76)
**Date:** 2026-05-02
**Status:** design approved, awaiting implementation plan

## Goal

Replace the 13 disabled/`.bak` workflow files in `.github/workflows/` with a single working CI pipeline that protects `main` and gives PR reviewers a real pass/fail signal. The new pipeline must:

1. Keep the Rust crate clippy-clean and formatted (`cargo fmt --check`, `cargo clippy -- -D warnings`).
2. Test the Rust crate in isolation (`cargo test --release`).
3. Build the production Docker image.
4. Run the cleaned testthat suite *inside* that image.
5. Push the image to Docker Hub on every green `main` commit (`:latest` + `:<short-sha>`).
6. Auto-open a deduplicated GitHub issue when an in-image testthat run fails on `main`.
7. Run passive security scanning (CodeQL on workflow files, Dependabot on Cargo + GitHub Actions + Docker).
8. Run R lint as a non-blocking advisory job.

The pipeline is the prerequisite that issue #76 was originally filed for. The test-suite cleanup that issue #76's body insisted on as a precondition has already shipped (PRs #85 + #88).

## Non-goals

- Deployment automation to ShinyApps.io or to the production host. The container is operator-deployed; CI only validates and publishes the image.
- Any change to `RCode/`, `scripts/`, `tests/testthat/`, `Dockerfile`, the Rust crate sources, or the Shiny app. CI verifies what's there; it doesn't change it.
- Performance benchmarking automation (`cargo bench` exists in the Rust crate but its noise level on shared runners makes it a poor CI gate).
- Multi-Dockerfile matrix builds (there is exactly one Dockerfile).

## Decisions (with rationale)

| Decision | Choice | Rationale |
|---|---|---|
| Where do tests run? | **C — Hybrid.** `cargo test` on the runner; testthat inside the production Docker image. | Rust crate is independently testable on the runner (~30 sec) for fast feedback. R tests need C++ toolchain, the Rust binary, and system deps that the Dockerfile already painstakingly assembles — reusing the image is worth the slower iteration than maintaining a parallel R-test runner. |
| When does the workflow run? | **C — PRs to `main` + pushes to `main` + manual `workflow_dispatch`.** | PR-time and main-time gating is the actual point. Per-commit feedback on feature branches eats Actions minutes for marginal value (developers running tests locally is faster). `workflow_dispatch` costs nothing and unblocks rerun-on-flake. |
| Docker Hub push policy? | **A — Push on every successful `main` run** (`:latest` + `:<short-sha>`). PR builds verify but never push. | Hobbyist project; no release branches; "what's on main is what's deployable" matches operator workflow. Short-SHA tag gives a rollback path. Docker Hub free tier supports unlimited public pushes. GitHub Actions free tier on public repos has unlimited minutes. |
| Reaction to failing testthat run on `main`? | **B — Block the push, plus auto-open a GitHub issue** with the failing test names. Deduplicated by searching for an open `ci-failure`-labeled issue first; comment instead of duplicate. | Lossless notification of real failures without inbox flooding when `main` stays broken across multiple commits. PR-context failures don't open issues — reviewers see them directly. |
| Caching? | **B + C combined.** GHA cache for the runner-side `cargo test` (Cargo registry + `target/`). BuildKit registry cache for the Docker image build, pushed to `chrisschwer/league-simulator:cache` with `mode=min`. | Two different surfaces, two different mechanisms. Combined: typical run ≈ 1–2 min when nothing changed, ≈ 5 min on a real change. `mode=min` exports only final-stage layers — smaller cache, slightly slower hits, acceptable tradeoff against image bloat. |
| Lint and security? | **C+ — full coverage.** R lint non-blocking; Rust `cargo clippy --all-targets -- -D warnings` and `cargo fmt --all -- --check` blocking; CodeQL passive (workflow files only — no R/Rust support upstream); Dependabot on Cargo + GitHub Actions + Docker ecosystems. | Rust crate is small; clippy is cheap to keep clean. R `lintr` produces stylistic noise, so non-blocking. CodeQL + Dependabot are free and notify out-of-band; they don't muddy the main CI. |
| Workflow file structure? | **Hybrid Approach 2.** One `ci.yml` (multi-job, parallel where possible). Separate `codeql.yml` (different cadence). Separate `dependabot.yml` (config, not a workflow). | Three files total, each does exactly one thing. Approach 3's `workflow_run` cross-workflow trigger has footguns (always runs against default-branch workflow definition, can't be tested in PR). Approach 1's single-job sequential structure wastes time on slow steps. |
| Old workflow + script cleanup scope? | **In scope.** Delete the 13 workflow files, the 7 `.github/scripts/` files, and 2 stale operation docs. Selectively edit one mixed-content doc. | The 13 workflows reference deleted infrastructure. The 7 scripts only feed those workflows. The two pure-CI docs (`ci-performance-report.md`, `operations/ci-monitoring.md`) describe the old dashboards. Leaving any of these around would mislead future-readers. |
| `docker-compose.yml` tag update? | **Staged.** Step 5 of the rollout sequence — separate tiny PR after the first `:latest` push lands on Docker Hub. | Avoids a window where `docker-compose pull` fails because `:latest` doesn't exist yet. |

## Coordination with other in-flight work

- **PR #85, #88 (issue #76 prerequisite — test-suite cleanup):** merged. The cleaned suite is the foundation this CI runs against.
- **PR #84 (issue #81 — prune root clutter):** merged. No file overlap.
- **No other in-flight work touches `.github/`.**

## Inventory

### Files added (3)

| Path | Purpose |
|---|---|
| `.github/workflows/ci.yml` | Main CI: Rust quality, R lint, image build + in-image testthat, push, failure-reporter |
| `.github/workflows/codeql.yml` | CodeQL on workflow files (PR + push + weekly Monday cron) |
| `.github/dependabot.yml` | Cargo + GitHub Actions + Docker ecosystem updates, weekly Mondays |

### Files modified (1)

| Path | Change |
|---|---|
| `docker-compose.yml` | `:integrated-system-deps` tag → `:latest`. Lands as a separate follow-up PR after first `:latest` push. |

### Files deleted (22)

**Workflow files (13):**

`automated-review.yml.disabled`, `build-test-deploy.yml.bak`, `build-test-deploy.yml.disabled`, `ci-dashboard.yml.disabled`, `deployment-safety-tests.yml.disabled`, `deployment-stages.yml.disabled`, `docker-cache.yml.disabled`, `incremental-tests.yml.disabled`, `parallel-tests.yml.disabled`, `quarantine-flaky-tests.yml.disabled`, `R-tests.yml.disabled`, `workflow-monitor.yml.disabled` (and the `.bak` of `build-test-deploy`).

**`.github/scripts/` (7):** `analyze-failures.sh`, `flaky-test-detector.R`, `monitor-resources.sh`, `retry.sh`, `shard-tests.R`, `test-dependencies.R`, `test-summary.R`. All seven are exclusively referenced by the deleted workflows.

**Stale CI docs (2):** `docs/ci-performance-report.md`, `docs/operations/ci-monitoring.md`. Both describe deleted CI infrastructure (the multi-job dashboard, the flaky-test quarantine system, the parallel-test sharding).

### Files selectively edited (1)

`docs/troubleshooting/common-issues.md` (758 lines) — likely a mix of stale CI content and useful operational guidance. Implementation plan will identify which sections reference the deleted scripts/workflows and prune those only. The non-CI portions stay.

## Design

### `ci.yml` — Multi-job workflow

**Triggers:**

```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  workflow_dispatch: {}
```

**Permissions** (least-privilege):

```yaml
permissions:
  contents: read           # checkout
  issues: write            # for the failure-reporter (gh issue create / comment)
```

`packages: write` is intentionally omitted — we publish to Docker Hub (external registry, authenticated via secrets), not GHCR. If GHCR is ever added, this permission gets added in the same change.

**Jobs:**

| Job | Purpose | Depends on | Cache |
|---|---|---|---|
| `rust-quality` | `cargo fmt --check` + `cargo clippy --all-targets -- -D warnings` + `cargo test --release` | (nothing) | `~/.cargo/registry`, `league-simulator-rust/target` keyed on `Cargo.lock` hash |
| `r-lint` | `lintr::lint_dir("RCode")`, **non-blocking** (`continue-on-error: true`) | (nothing) | R package library keyed on `test_packagelist.txt` hash |
| `image-build-and-test` | `docker buildx build` (registry-cache `cache-from`/`cache-to`, `mode=min`) → `docker run --rm <image>` testthat suite | (nothing — runs in parallel with above) | BuildKit registry cache pushed to `chrisschwer/league-simulator:cache` |
| `push-image` | `docker push :latest` + `:<short-sha>` to Docker Hub | `image-build-and-test` AND `rust-quality` | (none — uses the loaded image from the build job) |
| `report-failure` | `gh issue create` (or comment if open `ci-failure` issue exists) | `image-build-and-test` failed | (none) |

**Conditional execution:**

- `push-image`: `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`
- `report-failure`: `if: failure() && github.event_name == 'push' && github.ref == 'refs/heads/main' && needs.image-build-and-test.result == 'failure'`

**testthat invocation inside the image** (run from the `image-build-and-test` job):

```bash
docker run --rm \
  -v "$PWD/ci-out:/out" \
  league-simulator:ci-test \
  Rscript -e 'options(testthat.progress.max_fails = Inf);
              res <- testthat::test_dir("tests/testthat", stop_on_failure = FALSE, reporter = "summary");
              df <- as.data.frame(res);
              writeLines(capture.output(print(df)), "/out/testthat-summary.txt");
              if (any(df$failed > 0)) quit(status = 1)'
```

The summary file `ci-out/testthat-summary.txt` is uploaded as a job artifact at the end of the `image-build-and-test` job (via `actions/upload-artifact@v4`, with `if: always()` so it's available on failure). The `report-failure` job downloads it via `actions/download-artifact@v4` before invoking `gh`.

**Architectural choices worth flagging:**

1. **`image-build-and-test` does not depend on `rust-quality`.** The image build internally runs `cargo build --release` to bake the Rust binary into the image. Running `cargo build` twice (once on the runner, once in the image) is accepted: the runner-side path provides fast feedback (~1–2 min) for clippy/fmt/unit tests; the image build is the slower path that runs alongside. **`push-image` requires both** so a clippy regression blocks publication.
2. **The image is loaded into Docker via `--load` in the build job, not pushed there.** The `push-image` job does the push. This separation lets `report-failure` distinguish *test* failures (code problem, opens issue) from *build* failures (infrastructure problem, doesn't open issue).

**Failure-reporter dedupe logic:**

```bash
# Pseudocode for the report-failure job
EXISTING_ISSUE=$(gh issue list --label ci-failure --state open --limit 1 --json number,title --jq '.[0].number')
TITLE_LINE="CI: testthat failure on main ($(git rev-parse --short HEAD))"
BODY=$(cat <<EOF
testthat run failed on commit $(git rev-parse --short HEAD).

Failing tests (from \`ci-out/testthat-summary.txt\`):

\`\`\`
$(grep -E '^── .*Failure' ci-out/testthat-summary.txt || cat ci-out/testthat-summary.txt | tail -30)
\`\`\`

Workflow run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
EOF
)

if [ -n "$EXISTING_ISSUE" ]; then
  gh issue comment "$EXISTING_ISSUE" --body "$BODY"
else
  gh issue create --title "$TITLE_LINE" --body "$BODY" --label ci-failure
fi
```

**Label creation:** GitHub does not auto-create labels — `gh issue create --label ci-failure` fails if the label doesn't exist. The plan creates the label manually as a one-line preflight step (`gh label create ci-failure --color B60205 --description "Auto-opened by CI when testthat fails on main"`) before the first run, so the workflow doesn't need to handle the bootstrap case.

### `codeql.yml` — Security scanning

**Triggers:**

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'   # Mondays 06:00 UTC
```

**Permissions:**

```yaml
permissions:
  contents: read
  security-events: write
  actions: read
```

**Single job using `github/codeql-action`:**

| Step | What |
|---|---|
| `actions/checkout@v4` | Standard |
| `github/codeql-action/init@v3` | Languages: `actions` (workflow files). No `r` or `rust` — CodeQL doesn't support those. |
| `github/codeql-action/analyze@v3` | Posts findings to Security tab |

**Honest scope statement:** CodeQL's coverage on this repo is limited to GitHub Actions workflow files. R and Rust are not supported upstream. The bigger security signal is Dependabot (next).

### `dependabot.yml` — Dependency updates

```yaml
version: 2
updates:
  - package-ecosystem: "cargo"
    directory: "/league-simulator-rust"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 5
    groups:
      rust-deps:
        patterns: ["*"]

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 3
    groups:
      gh-actions:
        patterns: ["*"]

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 3
```

**Three deliberate choices:**

1. **No R ecosystem.** Dependabot doesn't support R. Broken R deps will surface at CI time when the image build's `install.packages(...)` step fails.
2. **Grouping** for Cargo and GitHub Actions (one PR per ecosystem per week) but not for Docker (only 2 base images; updates to `rocker/r-ver` and `rust:alpine` deserve separate review — different blast radii).
3. **PR limit caps** prevent flood when many updates land at once.

**Note on the Docker ecosystem:** Dependabot will scan `Dockerfile`, `Dockerfile.build`, and `league-simulator-rust/Dockerfile`. Only the root `Dockerfile` is used by production CI; the others may produce noise. Acceptable — they're easy to close.

## Rollout sequence

This is one PR for steps 1–4, plus a follow-up PR for step 5.

**Branch:** `feature/issue-76-ci-rebuild` (off `main` via `superpowers:using-git-worktrees`).

| Step | Commit | What |
|---|---|---|
| 1 | `chore(#76): delete obsolete CI workflows, scripts, and docs` | Delete 13 workflow files, 7 `.github/scripts/` files, 2 stale CI docs, selectively edit `docs/troubleshooting/common-issues.md` to remove references to deleted scripts |
| 2 | `ci(#76): add ci.yml — main CI workflow (build, test, push)` | Add `.github/workflows/ci.yml` with all five jobs |
| 3 | `ci(#76): add codeql.yml — security scanning` | Add `.github/workflows/codeql.yml` |
| 4 | `ci(#76): add dependabot.yml — dependency updates` | Add `.github/dependabot.yml` |
| **(open PR with steps 1–4)** | | PR triggers `ci.yml` against itself; must go green before merge |
| (after merge) | | First `main` run pushes `:latest` to Docker Hub; verify on Docker Hub UI |
| 5 | `chore(#76): point docker-compose.yml at :latest tag` | Tiny follow-up PR. CI runs against itself; merges once green. |

**Verification gates:**

- After commit 1: `find .github -type f` shows only the new files (or empty if commits 2–4 haven't happened yet); no `*.disabled` or `*.bak`.
- After commit 4 (PR open): `ci.yml` runs against the PR. All jobs except `push-image` and `report-failure` execute (those are main-only). Must end green.
- After PR merge: `main` push triggers `ci.yml`. `push-image` runs and publishes. Verify `chrisschwer/league-simulator:latest` exists on Docker Hub with the expected SHA tag.
- After step 5 PR merge: `docker-compose pull` from any host successfully fetches `:latest`.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| First `ci.yml` run fails because the image build or testthat-in-image surfaces a previously-hidden problem (e.g., a missing R package, stale Rust toolchain) | Medium | The `image-build-and-test` job runs against the PR; we iterate on the workflow until green before merging. Failure modes are isolated by job (rust-quality fails fast in ~1 min; image build separately). |
| `cargo clippy` finds warnings in current code that need fixing before the workflow can merge | Medium | If found, fix is in scope of the same PR (small change to Rust source) or filed as a tiny follow-up issue with the workflow temporarily set to `continue-on-error: true` for clippy. The user's preference is "blocking" for clippy — we'll honor it once main is green. |
| `cargo fmt --check` fails because current Rust source isn't fmt-clean | Medium | Same as above; if found, a single `cargo fmt --all` run produces the fix in one commit. |
| Docker Hub push fails (auth issue, rate limit, name collision) | Low | Existing secrets `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN` were used by the pre-cleanup CI; should still work. If they've expired, regenerate before merging the PR (verify by running `docker login` locally with the token value). |
| `docker-compose.yml` change in step 5 breaks something an operator depends on | Low | The change is one line; the new tag (`:latest`) is what CI will produce on every main commit. Old `:integrated-system-deps` tag stays in Docker Hub forever (we don't delete it), so any operator still pulling that tag continues to work — they just won't get updates. |
| CodeQL workflow consumes Actions minutes for limited coverage | Low (accepted) | Public repos have unlimited minutes. The weekly Monday run is the only ongoing cost. If R/Rust ever land in CodeQL upstream, the workflow already exists and only needs language additions. |
| Dependabot floods PR queue | Low | PR limits (5/3/3) cap weekly volume. Grouping further reduces it. If still too much, lower limits or change schedule to monthly. |
| Failure-reporter creates issues spuriously (e.g., infrastructure flake misclassified as test failure) | Low | The reporter only triggers on the `image-build-and-test` job result. Build failures (infrastructure) and test failures (code) are isolated by job — only the test failure path opens an issue. Dedupe logic prevents flood when main stays broken. |

## Recovery paths

| Action | Recovery |
|---|---|
| First `:latest` push to Docker Hub is broken | Revert the docker-compose change (step 5) or operator manually pulls a known-good `:<short-sha>` tag |
| `ci.yml` itself becomes broken on `main` | `git revert` the relevant commit; CI itself can run on the revert PR to verify |
| Need to roll back to pre-cleanup CI | The 13 deleted workflows are recoverable via `git log --diff-filter=D --oneline` and `git show <sha>:<path>`. Tag `pre-deployment-cleanup-2026-05-02` predates them. |
| Dependabot creates a bad update PR | Standard PR review — close it without merging. CI will run against any merge to confirm. |

## Estimated effort

- **Steps 1–4 (one PR):** 2–4 hours of work spread across ~6 commits, plus iteration time on the first PR run (1–2 cycles likely needed to get the workflow green — image-build CI debugging is iterative).
- **Step 5 (follow-up PR):** 15 minutes once `:latest` is verified on Docker Hub.

## Definition of done

1. New `ci.yml`, `codeql.yml`, `dependabot.yml` are merged to `main`.
2. All 13 old workflow files, 7 old scripts, and 2 stale CI docs are deleted.
3. A PR-triggered `ci.yml` run produces green checks (verified by opening the actual PR for steps 1–4).
4. A `main`-triggered `ci.yml` run publishes `chrisschwer/league-simulator:latest` and `:<short-sha>` to Docker Hub (verified on Docker Hub UI).
5. A deliberate broken-test PR (e.g., add `expect_true(FALSE)` and revert before merging) confirms the gating + issue-creation behavior.
6. CodeQL workflow runs at least once on `main` and produces a baseline scan visible in the Security tab.
7. Dependabot opens at least one PR within a week of merge.
8. `docker-compose.yml` is updated to pull `:latest` (in the follow-up PR after step 5).
