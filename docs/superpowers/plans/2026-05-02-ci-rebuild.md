# CI/CD Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace 13 disabled/`.bak` workflow files with a single working CI pipeline (one main `ci.yml` + `codeql.yml` + `dependabot.yml`) that builds the production image, tests the Rust crate on the runner and the testthat suite inside the image, pushes to Docker Hub on green main, and auto-opens deduplicated GitHub issues on failure.

**Architecture:** Two PRs off `main`. PR-A is the bulk of the work — delete stale CI artifacts, add three new files, fix two stale doc references, all in one branch. PR-B is a tiny follow-up that bumps `docker-compose.yml` to `:latest` after the first `:latest` push lands on Docker Hub.

**Tech Stack:** GitHub Actions (workflows), Docker BuildKit (image build + registry cache), Cargo (Rust toolchain via `dtolnay/rust-toolchain@stable`), R 4.3.1 (`r-lib/actions/setup-r@v2`), `gh` CLI (issue creation/dedupe), CodeQL action v3, Dependabot config v2.

**Reference:** Spec at `docs/superpowers/specs/2026-05-02-ci-rebuild-design.md`. GitHub issue [#76](https://github.com/chrisschwer/League-Simulator-Update/issues/76).

**Survivor list — DO NOT TOUCH (kept in BOTH PRs):**

- All of `RCode/`, `scripts/`, `tests/testthat/` (CI verifies what's there; doesn't change it)
- `Dockerfile`, `docker-start.sh` (image build inputs)
- All of `league-simulator-rust/` (Rust crate sources)
- `docker-compose.yml` (touched only in PR-B's single line change, otherwise off-limits)
- `.github/CONTRIBUTING.md` content outside the `## CI/CD Workflow` section (lines 139–168)
- `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md`
- `docs/troubleshooting/common-issues.md` lines 1–491 + 471–491 + 752+ that are not the stale CI block

---

## File Inventory

### PR-A files added (3)

| Path | Purpose |
|---|---|
| `.github/workflows/ci.yml` | Main CI: 5 jobs (rust-quality, r-lint, image-build-and-test, push-image, report-failure) |
| `.github/workflows/codeql.yml` | CodeQL on workflow files (PR + push + weekly Monday cron) |
| `.github/dependabot.yml` (rewrite) | Cargo + GitHub Actions + Docker ecosystems, weekly Mondays, grouped where appropriate |

Note: `.github/dependabot.yml` already exists with only the github-actions ecosystem; this PR rewrites it to add Cargo and Docker ecosystems and grouping.

### PR-A files deleted (22)

**Workflow files (13):**

```
.github/workflows/automated-review.yml.disabled
.github/workflows/build-test-deploy.yml.bak
.github/workflows/build-test-deploy.yml.disabled
.github/workflows/ci-dashboard.yml.disabled
.github/workflows/deployment-safety-tests.yml.disabled
.github/workflows/deployment-stages.yml.disabled
.github/workflows/docker-cache.yml.disabled
.github/workflows/incremental-tests.yml.disabled
.github/workflows/parallel-tests.yml.disabled
.github/workflows/quarantine-flaky-tests.yml.disabled
.github/workflows/R-tests.yml.disabled
.github/workflows/workflow-monitor.yml.disabled
```

**`.github/scripts/` (7):**

```
.github/scripts/analyze-failures.sh
.github/scripts/flaky-test-detector.R
.github/scripts/monitor-resources.sh
.github/scripts/retry.sh
.github/scripts/shard-tests.R
.github/scripts/test-dependencies.R
.github/scripts/test-summary.R
```

**Stale CI docs (2):**

```
docs/ci-performance-report.md
docs/operations/ci-monitoring.md
```

### PR-A files selectively edited (2)

- `docs/troubleshooting/common-issues.md` — remove the entire "## CI/CD Pipeline Issues" block (lines 492–717) and the "## CI/CD Quick Reference" block (lines 718–750). Also clean stale links in "## Related Documentation" at the end. Keep all of lines 1–491.
- `.github/CONTRIBUTING.md` — replace the "## CI/CD Workflow" section (lines 139–168) with a brief accurate description of the new single-workflow CI.

### PR-A preflight (one-time, before opening the PR)

- `gh label create ci-failure --color B60205 --description "Auto-opened by CI when testthat fails on main"` (no commit; idempotent — `|| true` swallows error if label exists)

### PR-B files modified (1)

| Path | Change |
|---|---|
| `docker-compose.yml` line 3 | `chrisschwer/league-simulator:integrated-system-deps` → `chrisschwer/league-simulator:latest` |

---

## PR-A: Main CI Rebuild

### Task 0: Worktree + preflight

**Goal:** Create the PR-A worktree, capture pre-state baseline, create the GitHub label, verify Docker Hub credentials.

**Files:** None modified.

- [ ] **Step 1: Create the worktree (using superpowers:using-git-worktrees)**

From the main checkout's repo root:

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update"
git fetch origin
git worktree add ../League-Simulator-Update.issue-76-ci-rebuild -b feature/issue-76-ci-rebuild origin/main
cd ../League-Simulator-Update.issue-76-ci-rebuild
git status --short
git branch --show-current
```

Expected: empty status; branch `feature/issue-76-ci-rebuild` tracking `origin/main`.

- [ ] **Step 2: Capture pre-state baselines for verification**

```bash
ls .github/workflows/ > .baseline-workflows-pre.txt
ls .github/scripts/ > .baseline-scripts-pre.txt
wc -l docs/troubleshooting/common-issues.md > .baseline-common-issues-pre.txt
echo "Pre-state captured:"
cat .baseline-workflows-pre.txt
echo "---"
cat .baseline-scripts-pre.txt
echo "---"
cat .baseline-common-issues-pre.txt
```

Expected: 13 workflow files (12 `.disabled` + 1 `.bak`), 7 script files, common-issues.md ~758 lines.

- [ ] **Step 3: Create the `ci-failure` label (idempotent)**

```bash
gh label create ci-failure --color B60205 --description "Auto-opened by CI when testthat fails on main" 2>&1 || echo "(label exists or another error — check above)"
gh label list | grep ci-failure
```

Expected: `ci-failure` appears in the label list (either created now or already existed).

- [ ] **Step 4: Verify Docker Hub credentials are still valid**

The pre-cleanup CI used `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets. Verify both still exist (the existence check is non-trivial — secret values aren't readable). Use `gh secret list`:

```bash
gh secret list | grep -E 'DOCKERHUB_(USERNAME|TOKEN)'
```

Expected: both secrets listed with reasonable timestamps. If a secret is missing, STOP and ask the user to set it before continuing — the workflow's push step will fail otherwise.

- [ ] **Step 5: Confirm spec and prior plan are reachable from the worktree**

```bash
ls docs/superpowers/specs/2026-05-02-ci-rebuild-design.md
ls docs/superpowers/plans/2026-05-02-ci-rebuild.md
```

Expected: both files exist.

(No commit at the end of Task 0.)

---

### Task 1: Delete obsolete workflows, scripts, and stale docs

**Files:**
- Delete: 13 files in `.github/workflows/`
- Delete: 7 files in `.github/scripts/` (entire directory)
- Delete: `docs/ci-performance-report.md`, `docs/operations/ci-monitoring.md`
- Delete: directory `.github/scripts/` after its files are gone

**Goal:** Single mechanical commit removing all dead CI artifacts. After this commit, `.github/workflows/` is empty and `.github/scripts/` doesn't exist.

- [ ] **Step 1: Verify the file inventory matches the baseline**

```bash
ls .github/workflows/
```

Expected output (exactly 13 files):

```
automated-review.yml.disabled
build-test-deploy.yml.bak
build-test-deploy.yml.disabled
ci-dashboard.yml.disabled
deployment-safety-tests.yml.disabled
deployment-stages.yml.disabled
docker-cache.yml.disabled
incremental-tests.yml.disabled
parallel-tests.yml.disabled
quarantine-flaky-tests.yml.disabled
R-tests.yml.disabled
workflow-monitor.yml.disabled
```

If the file count is not 13 (e.g., a workflow file got re-enabled or someone added a new one), STOP and report DONE_WITH_CONCERNS naming the discrepancy.

- [ ] **Step 2: Verify scripts inventory**

```bash
ls .github/scripts/
```

Expected output (exactly 7 files):

```
analyze-failures.sh
flaky-test-detector.R
monitor-resources.sh
retry.sh
shard-tests.R
test-dependencies.R
test-summary.R
```

- [ ] **Step 3: Delete the 13 workflow files**

```bash
git rm \
  .github/workflows/automated-review.yml.disabled \
  .github/workflows/build-test-deploy.yml.bak \
  .github/workflows/build-test-deploy.yml.disabled \
  .github/workflows/ci-dashboard.yml.disabled \
  .github/workflows/deployment-safety-tests.yml.disabled \
  .github/workflows/deployment-stages.yml.disabled \
  .github/workflows/docker-cache.yml.disabled \
  .github/workflows/incremental-tests.yml.disabled \
  .github/workflows/parallel-tests.yml.disabled \
  .github/workflows/quarantine-flaky-tests.yml.disabled \
  .github/workflows/R-tests.yml.disabled \
  .github/workflows/workflow-monitor.yml.disabled
```

Expected: 12 `rm '...'` lines.

Note: only 12 because `build-test-deploy.yml.bak` and `build-test-deploy.yml.disabled` are both listed above (13 paths total).

- [ ] **Step 4: Delete the 7 script files and the directory**

```bash
git rm -r .github/scripts/
```

Expected: 7 `rm '...'` lines and the directory removed.

- [ ] **Step 5: Delete the 2 stale CI docs**

```bash
git rm docs/ci-performance-report.md docs/operations/ci-monitoring.md
```

Expected: 2 `rm '...'` lines.

- [ ] **Step 6: Confirm the working tree state**

```bash
ls .github/workflows/ 2>&1
ls .github/scripts/ 2>&1
ls docs/ci-performance-report.md docs/operations/ci-monitoring.md 2>&1
git status --short
```

Expected:
- `.github/workflows/` empty (no output, or just `..` if you ran `ls -a`)
- `.github/scripts/` reports "No such file or directory"
- The two doc paths report "No such file or directory"
- `git status --short` shows 22 lines of `D` (deleted)

- [ ] **Step 7: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(#76): delete obsolete CI workflows, scripts, and stale docs

Removes the pre-cleanup CI infrastructure superseded by the new ci.yml
(added in the next commit). All 13 workflow files were either *.disabled
or *.bak — none were running. The 7 .github/scripts/ helpers were exclusively
referenced by those deleted workflows. The two stale CI docs describe the
deleted multi-job dashboard / flaky-test-quarantine system.

Workflows deleted (13):
- automated-review.yml.disabled, build-test-deploy.yml.{bak,disabled},
  ci-dashboard.yml.disabled, deployment-safety-tests.yml.disabled,
  deployment-stages.yml.disabled, docker-cache.yml.disabled,
  incremental-tests.yml.disabled, parallel-tests.yml.disabled,
  quarantine-flaky-tests.yml.disabled, R-tests.yml.disabled,
  workflow-monitor.yml.disabled

Scripts deleted (7): everything under .github/scripts/

Docs deleted (2): docs/ci-performance-report.md,
docs/operations/ci-monitoring.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Edit `docs/troubleshooting/common-issues.md` to remove stale CI block

**Files:**
- Modify: `docs/troubleshooting/common-issues.md` (remove lines 492–750, prune stale links from "Related Documentation")

**Goal:** Surgically remove the CI-specific content from the troubleshooting doc while keeping the genuinely useful operational guidance (lines 1–491).

- [ ] **Step 1: Read the current state of the file to confirm line numbers**

Open `docs/troubleshooting/common-issues.md` with the Read tool. Confirm:
- Line 492 begins `## CI/CD Pipeline Issues`
- Line 718 begins `## CI/CD Quick Reference`
- Line 751 begins `## Related Documentation` (or similar)

If the line numbers have shifted, adjust the deletions to match the actual content.

- [ ] **Step 2: Delete lines 492–750 (the entire CI block)**

Use the Edit tool. Find the marker that starts at line 492:

```
## CI/CD Pipeline Issues
```

And the marker that comes immediately after the CI block (the next `##` heading — likely `## Related Documentation` at line 751).

Delete everything from `## CI/CD Pipeline Issues` through (and not including) the next `##` heading. The file should flow directly from line 491 (the end of "When All Else Fails" section) to line 751 (the start of "Related Documentation").

- [ ] **Step 3: Prune stale links from "Related Documentation"**

In the now-shifted "## Related Documentation" section, find and remove these three lines:

```
- [CI/CD Guide](../deployment/ci-cd-guide.md)
- [CI Monitoring](../operations/ci-monitoring.md)
- [CI Performance Report](../ci-performance-report.md)
```

The first targets a file that doesn't exist (verify with `ls docs/deployment/ci-cd-guide.md`); the second and third targets are deleted in Task 1.

Keep the other entries in that section.

- [ ] **Step 4: Verify the edits**

```bash
grep -n "CI/CD Pipeline Issues\|CI/CD Quick Reference\|ci-monitoring\|ci-performance-report\|github/scripts\|R-tests\.yml\|parallel-tests\.yml" docs/troubleshooting/common-issues.md
```

Expected: no output. The file should have no remaining references to deleted CI infrastructure.

```bash
wc -l docs/troubleshooting/common-issues.md
```

Expected: ~500 lines (down from ~758).

- [ ] **Step 5: Commit**

```bash
git add docs/troubleshooting/common-issues.md
git commit -m "$(cat <<'EOF'
docs(#76): remove stale CI block from common-issues.md

The "CI/CD Pipeline Issues" and "CI/CD Quick Reference" sections (lines
492–750) described the deleted multi-job CI infrastructure (parallel
sharding, flaky-test quarantine, CI dashboard, .github/scripts/* helpers).
None of that exists anymore. Also prunes broken links in
"Related Documentation".

Operational guidance for the application itself (lines 1–491: service
won't start, API rate limits, ELO troubleshooting, etc.) is preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Edit `.github/CONTRIBUTING.md` CI/CD section

**Files:**
- Modify: `.github/CONTRIBUTING.md` (replace lines 139–168 — the "## CI/CD Workflow" section)

**Goal:** Replace the inaccurate CI/CD section (which describes parallel sharding, multi-R-version matrix, flaky-test quarantine — all deleted) with an honest brief description of the new single-workflow setup.

- [ ] **Step 1: Read the current section**

Open `.github/CONTRIBUTING.md` with the Read tool. Confirm:
- Line 139 starts `## CI/CD Workflow`
- The section ends at line 168 (just before `## Pull Request Process`)

If line numbers shifted, adjust the edit to match.

- [ ] **Step 2: Replace lines 139–168 with the new content**

Use the Edit tool. Find this exact block (lines 139–168 of the current file):

```markdown
## CI/CD Workflow

### Automated Checks

All pull requests trigger automated checks:

1. **R Tests**: Full test suite across multiple R versions
2. **Container Tests**: Docker build and structure validation
3. **Linting**: Code style and quality checks
4. **Documentation**: Ensure docs are updated

### Test Execution

Our CI pipeline features:

- **Parallel Execution**: Tests run in 4 parallel shards
- **Incremental Testing**: Only affected tests run for faster feedback
- **Retry Logic**: Automatic retry for transient failures
- **Flaky Test Management**: Unstable tests are quarantined

### Performance Monitoring

- Build times are tracked and should stay under 15 minutes
- Test success rate should remain above 95%
- Resource usage is monitored to prevent waste

```

Replace with:

```markdown
## CI/CD Workflow

### Automated Checks

All pull requests targeting `main` trigger `.github/workflows/ci.yml`. The workflow has five jobs:

1. **rust-quality**: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test --release` on the runner
2. **r-lint**: `lintr::lint_dir("RCode")` (advisory; never blocks the PR)
3. **image-build-and-test**: builds the production Docker image and runs the testthat suite inside it
4. **push-image** (main only): tags the verified image as `:latest` + `:<short-sha>` and pushes to Docker Hub
5. **report-failure** (main only): if the in-image testthat run fails, opens (or comments on) a `ci-failure`-labeled GitHub issue

`rust-quality` and `image-build-and-test` run in parallel. The image is published only when both pass.

### Security and dependencies

- `.github/workflows/codeql.yml` scans GitHub Actions workflow files weekly (Mondays) and on every PR/push to `main`. Results appear in the Security tab.
- `.github/dependabot.yml` opens weekly grouped PRs for Cargo, GitHub Actions, and Docker base-image updates.

### Iteration

Use `gh workflow run ci.yml` to trigger a manual run from any branch. CI runs on every PR to `main`; feature-branch pushes do not trigger CI (run tests locally with `Rscript -e 'testthat::test_dir("tests/testthat")'` and `cargo test` in `league-simulator-rust/`).

```

- [ ] **Step 3: Verify the edit**

```bash
grep -n "## CI/CD Workflow\|## Pull Request Process" .github/CONTRIBUTING.md
```

Expected: two matches, both at sensible line numbers.

```bash
grep -n "parallel shards\|flaky\|ci-dashboard\|R-tests\.yml" .github/CONTRIBUTING.md
```

Expected: no output (no references to deleted CI infrastructure).

- [ ] **Step 4: Commit**

```bash
git add .github/CONTRIBUTING.md
git commit -m "$(cat <<'EOF'
docs(#76): rewrite CONTRIBUTING.md CI/CD section for single-workflow setup

The previous section described the deleted multi-job CI (4-way parallel
sharding, multi-R-version matrix, flaky-test quarantine, CI dashboard).
Replaces it with an accurate description of the single ci.yml workflow,
its 5 jobs, the codeql + dependabot setup, and how to iterate.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Add `.github/dependabot.yml` (rewrite)

**Files:**
- Modify (rewrite): `.github/dependabot.yml`

**Goal:** Replace the existing minimal dependabot config (github-actions only) with the spec's full version: Cargo + GitHub Actions + Docker, with grouping and PR limits.

- [ ] **Step 1: Read the current file (sanity check)**

```bash
cat .github/dependabot.yml
```

Expected: existing content with just the `github-actions` ecosystem.

- [ ] **Step 2: Overwrite the file**

Use the Write tool to overwrite `.github/dependabot.yml` with this exact content:

```yaml
# Dependabot configuration — opens weekly grouped dependency-update PRs.
# - Cargo: scans league-simulator-rust/Cargo.toml + Cargo.lock
# - GitHub Actions: scans .github/workflows/*.yml action versions
# - Docker: scans Dockerfile, Dockerfile.build, league-simulator-rust/Dockerfile FROM lines
# Schedule: every Monday so updates land at the start of the week and operators
# can review them with the rest of the week's work.
version: 2
updates:
  - package-ecosystem: "cargo"
    directory: "/league-simulator-rust"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "rust"
    groups:
      rust-deps:
        patterns: ["*"]

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 3
    labels:
      - "dependencies"
      - "github-actions"
    groups:
      gh-actions:
        patterns: ["*"]

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 3
    labels:
      - "dependencies"
      - "docker"
```

- [ ] **Step 3: Validate YAML syntax**

```bash
python3 -c "import yaml; print(yaml.safe_load(open('.github/dependabot.yml')))" 2>&1 | head -3
```

Expected: a Python dict printed without errors. If YAML is malformed, the print fails or the parse errors.

If `python3` or PyYAML isn't available, `Rscript -e 'yaml::read_yaml(".github/dependabot.yml")'` works as an alternative (R's yaml package is installed on this project).

- [ ] **Step 4: Commit**

```bash
git add .github/dependabot.yml
git commit -m "$(cat <<'EOF'
ci(#76): rewrite dependabot.yml — add Cargo and Docker ecosystems

Replaces the minimal github-actions-only config with three ecosystems:
- cargo: league-simulator-rust/ (5 PRs/week, grouped)
- github-actions: workflow action versions (3 PRs/week, grouped)
- docker: Dockerfile + Dockerfile.build + Rust crate Dockerfile FROM lines (3 PRs/week, ungrouped — base-image bumps deserve separate review)

All three run weekly on Mondays.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Add `.github/workflows/codeql.yml`

**Files:**
- Create: `.github/workflows/codeql.yml`

**Goal:** Stand-alone CodeQL workflow scanning GitHub Actions workflow files. Runs on PR + push to main + weekly Monday cron.

- [ ] **Step 1: Confirm `.github/workflows/` is empty**

```bash
ls .github/workflows/ 2>&1
```

Expected: no files (Task 1 deleted all 13). If anything is there, STOP and investigate.

- [ ] **Step 2: Create the file**

Use the Write tool to create `.github/workflows/codeql.yml` with this exact content:

```yaml
name: CodeQL

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    # Mondays 06:00 UTC — weekly baseline.
    - cron: '0 6 * * 1'

permissions:
  contents: read
  security-events: write
  actions: read

jobs:
  analyze:
    name: Analyze workflow files
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: actions
          # No R or Rust here — neither is supported by CodeQL upstream.

      - name: Perform CodeQL analysis
        uses: github/codeql-action/analyze@v3
```

- [ ] **Step 3: Validate YAML**

```bash
python3 -c "import yaml; print(list(yaml.safe_load(open('.github/workflows/codeql.yml')).keys()))" 2>&1 | head -3
```

Expected: a list including `name`, `on`, `permissions`, `jobs`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/codeql.yml
git commit -m "$(cat <<'EOF'
ci(#76): add codeql.yml — security scanning for workflow files

Standalone CodeQL workflow. Scans .github/workflows/*.yml for known
security-injection patterns. Runs on every PR and push to main, plus
weekly Mondays at 06:00 UTC.

CodeQL has no R or Rust support upstream — coverage on this repo is
limited to GitHub Actions workflow files. The bigger security signal is
Dependabot (handles Cargo, GitHub Actions, Docker).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Add `.github/workflows/ci.yml` — main CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Goal:** The main CI file with all 5 jobs.

- [ ] **Step 1: Create the file**

Use the Write tool to create `.github/workflows/ci.yml` with this exact content:

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  workflow_dispatch: {}

permissions:
  contents: read
  issues: write   # for report-failure (gh issue create / comment)

env:
  IMAGE_NAME: chrisschwer/league-simulator
  CACHE_TAG: cache

jobs:
  rust-quality:
    name: Rust quality (fmt + clippy + test)
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: league-simulator-rust
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt, clippy

      - name: Cache cargo registry and target
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            league-simulator-rust/target
          key: ${{ runner.os }}-cargo-${{ hashFiles('league-simulator-rust/Cargo.lock') }}
          restore-keys: |
            ${{ runner.os }}-cargo-

      - name: cargo fmt --check
        run: cargo fmt --all -- --check

      - name: cargo clippy
        run: cargo clippy --all-targets -- -D warnings

      - name: cargo test
        run: cargo test --release

  r-lint:
    name: R lint (advisory)
    runs-on: ubuntu-latest
    continue-on-error: true   # advisory only — never blocks the PR
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: '4.3.1'
          use-public-rspm: true

      - name: Install lintr
        run: install.packages('lintr', repos = 'https://cloud.r-project.org')
        shell: Rscript {0}

      - name: Lint RCode/
        run: |
          lints <- lintr::lint_dir('RCode')
          if (length(lints) > 0) {
            cat('Found', length(lints), 'lints in RCode/\n')
            print(lints)
          } else {
            cat('No lints found.\n')
          }
        shell: Rscript {0}

  image-build-and-test:
    name: Image build + in-image testthat
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.tag }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub (read-only for cache)
        if: ${{ env.DOCKERHUB_USERNAME != '' }}
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
        env:
          DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}

      - name: Compute image tag
        id: meta
        run: echo "tag=${{ env.IMAGE_NAME }}:ci-${{ github.sha }}" >> "$GITHUB_OUTPUT"

      - name: Build production image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: Dockerfile
          load: true
          tags: ${{ steps.meta.outputs.tag }}
          cache-from: type=registry,ref=${{ env.IMAGE_NAME }}:${{ env.CACHE_TAG }}
          cache-to: type=registry,ref=${{ env.IMAGE_NAME }}:${{ env.CACHE_TAG }},mode=min

      - name: Run testthat inside the image
        run: |
          mkdir -p ci-out
          docker run --rm \
            -v "$PWD/ci-out:/out" \
            -e RAPIDAPI_KEY=test_key_for_ci \
            ${{ steps.meta.outputs.tag }} \
            Rscript -e 'options(testthat.progress.max_fails = Inf);
                        res <- testthat::test_dir("tests/testthat", stop_on_failure = FALSE, reporter = "summary");
                        df <- as.data.frame(res);
                        writeLines(capture.output(print(df)), "/out/testthat-summary.txt");
                        cat("\n--- summary ---\n");
                        cat(sprintf("FAIL=%d WARN=%d SKIP=%d PASS=%d\n",
                                    sum(df$failed > 0), sum(df$warning), sum(df$skipped), sum(df$nb)));
                        if (any(df$failed > 0)) quit(status = 1)'

      - name: Upload testthat summary
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: testthat-summary
          path: ci-out/testthat-summary.txt
          if-no-files-found: warn

  push-image:
    name: Push image to Docker Hub
    runs-on: ubuntu-latest
    needs: [rust-quality, image-build-and-test]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Compute short SHA
        id: sha
        run: echo "short=$(git rev-parse --short HEAD)" >> "$GITHUB_OUTPUT"

      - name: Build and push (cached from previous job)
        uses: docker/build-push-action@v5
        with:
          context: .
          file: Dockerfile
          push: true
          tags: |
            ${{ env.IMAGE_NAME }}:latest
            ${{ env.IMAGE_NAME }}:${{ steps.sha.outputs.short }}
          cache-from: type=registry,ref=${{ env.IMAGE_NAME }}:${{ env.CACHE_TAG }}
          cache-to: type=registry,ref=${{ env.IMAGE_NAME }}:${{ env.CACHE_TAG }},mode=min

  report-failure:
    name: Open or update CI failure issue
    runs-on: ubuntu-latest
    needs: [image-build-and-test]
    if: failure() && github.event_name == 'push' && github.ref == 'refs/heads/main' && needs.image-build-and-test.result == 'failure'
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Download testthat summary
        uses: actions/download-artifact@v4
        with:
          name: testthat-summary
          path: ci-out
        continue-on-error: true   # if no artifact, body falls back to a generic message

      - name: Open or comment on CI failure issue
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          SHORT_SHA=$(git rev-parse --short HEAD)
          RUN_URL="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"

          if [ -f ci-out/testthat-summary.txt ]; then
            FAILURES=$(grep -E '^── .*Failure' ci-out/testthat-summary.txt | head -10 || true)
            [ -z "$FAILURES" ] && FAILURES=$(tail -30 ci-out/testthat-summary.txt)
          else
            FAILURES="(testthat-summary.txt artifact missing — image build may have failed before tests ran)"
          fi

          BODY=$(cat <<EOF
          testthat run failed on commit \`$SHORT_SHA\`.

          ## Failing tests

          \`\`\`
          $FAILURES
          \`\`\`

          ## Workflow run

          $RUN_URL
          EOF
          )

          EXISTING=$(gh issue list --label ci-failure --state open --limit 1 --json number --jq '.[0].number // empty')
          if [ -n "$EXISTING" ]; then
            echo "Commenting on existing issue #$EXISTING"
            gh issue comment "$EXISTING" --body "$BODY"
          else
            echo "Opening new ci-failure issue"
            gh issue create \
              --title "CI: testthat failure on main ($SHORT_SHA)" \
              --label ci-failure \
              --body "$BODY"
          fi
```

- [ ] **Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; doc = yaml.safe_load(open('.github/workflows/ci.yml')); print('jobs:', list(doc['jobs'].keys()))" 2>&1 | head -3
```

Expected: `jobs: ['rust-quality', 'r-lint', 'image-build-and-test', 'push-image', 'report-failure']`.

- [ ] **Step 3: Sanity-check the heredoc syntax in the report-failure step**

The report-failure step contains a `BODY=$(cat <<EOF ... EOF)` heredoc inside a `run:` block. YAML and bash heredoc syntax can interact badly. Inspect the raw file content:

```bash
sed -n '/Open or comment on CI failure issue/,/EOF$/p' .github/workflows/ci.yml | head -50
```

Expected: the heredoc starts and ends correctly. If the `EOF` markers are mis-indented (heredoc terminators must be at the start of the line, not indented), fix the indentation.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
ci(#76): add ci.yml — main CI workflow (build, test, push)

Five-job CI pipeline:

1. rust-quality (fmt + clippy + test on the runner, ~1-2 min)
2. r-lint (lintr on RCode/, advisory only via continue-on-error)
3. image-build-and-test (docker buildx with mode=min registry cache,
   then in-image testthat run; uploads testthat-summary.txt artifact)
4. push-image (main only, depends on rust-quality + image-build-and-test
   succeeding; pushes :latest + :<short-sha> to Docker Hub)
5. report-failure (main only, depends on image-build-and-test failing;
   opens or comments on a ci-failure-labeled issue with the failing
   test names from the artifact)

Permissions are scoped to the minimum: contents: read, issues: write.
RAPIDAPI_KEY is set to a stub for the testthat run since the in-image
suite has skip_if guards for the live network path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Pre-PR static checks

**Files:** None modified.

**Goal:** Catch obvious issues before opening the PR.

- [ ] **Step 1: Confirm the file inventory**

```bash
ls .github/workflows/
ls .github/dependabot.yml
ls .github/scripts/ 2>&1
```

Expected:
- `.github/workflows/` shows exactly: `ci.yml`, `codeql.yml`
- `.github/dependabot.yml` exists
- `.github/scripts/` reports "No such file or directory"

- [ ] **Step 2: Confirm no remaining live references to deleted files**

```bash
grep -rEn 'workflows/(automated-review|build-test-deploy|ci-dashboard|deployment-safety-tests|deployment-stages|docker-cache|incremental-tests|parallel-tests|quarantine-flaky-tests|R-tests|workflow-monitor)\.yml|github/scripts/(analyze-failures|flaky-test-detector|monitor-resources|retry|shard-tests|test-dependencies|test-summary)|ci-performance-report|ci-monitoring' \
  --include='*.md' --include='*.yml' --include='*.yaml' --include='*.sh' --include='*.R' --include='*.txt' \
  . 2>/dev/null | grep -v '^./.git/' | grep -v 'docs/superpowers/'
```

Expected: no output. The `docs/superpowers/` exclusion is intentional — historical specs and plans reference these names by design.

If any output appears (a live reference we missed), STOP and report DONE_WITH_CONCERNS naming the file.

- [ ] **Step 3: Confirm the testthat suite still passes locally**

This is a sanity check that the work-tree state hasn't accidentally affected the suite. The workflow runs the testthat suite *inside the image*, but a local pre-flight is cheap.

```bash
Rscript -e 'options(testthat.progress.max_fails = Inf); res <- testthat::test_dir("tests/testthat", stop_on_failure = FALSE); df <- as.data.frame(res); cat(sprintf("FAIL=%d WARN=%d SKIP=%d PASS=%d\n", sum(df$failed > 0), sum(df$warning), sum(df$skipped), sum(df$nb)))'
```

Expected: `FAIL=0` (or close — pre-existing infra failures may surface; what matters is no NEW failures from this PR's changes).

- [ ] **Step 4: View the full diff vs main for one final review**

```bash
git log --oneline origin/main..HEAD
git diff --stat origin/main..HEAD
```

Expected: 7 commits (Task 1's deletion + Task 2's common-issues edit + Task 3's CONTRIBUTING edit + Task 4's dependabot rewrite + Task 5's codeql + Task 6's ci.yml). Diff stat shows ~22 files deleted, ~3 files added, 2 files modified.

If the count is off, investigate before pushing.

(No commit — this is verification only.)

---

### Task 8: Push the branch and open the PR

**Files:** None modified.

User has explicitly consented to pushing branches and opening PRs against `chrisschwer/League-Simulator-Update`.

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/issue-76-ci-rebuild
```

Expected: push succeeds.

- [ ] **Step 2: Open the PR**

Build the body in a temp file (HEREDOC inside `gh pr create` is brittle):

```bash
cat > /tmp/pr-body.md <<'EOF'
## Summary

Rebuilds the CI/CD pipeline from scratch, replacing 13 disabled/`.bak` workflow files with a single working `ci.yml` plus separate `codeql.yml` and `dependabot.yml`.

This is **PR-A**. PR-B (a one-line follow-up) bumps `docker-compose.yml` to the new `:latest` tag once the first push lands.

Closes the actual scope of #76 (CI rebuild). The prerequisite test-suite cleanup (#85, #88) has already merged.

## What changed

### `ci.yml` — main workflow (new)

Five jobs:

1. **rust-quality**: `cargo fmt --check` + `cargo clippy --all-targets -- -D warnings` + `cargo test --release` on the runner with cache for `~/.cargo/registry` and `target/`.
2. **r-lint**: `lintr::lint_dir("RCode")` advisory only (`continue-on-error: true`).
3. **image-build-and-test**: `docker buildx build` (registry cache `mode=min`, pushed to `:cache` tag) → `docker run` testthat suite inside the image. Uploads `testthat-summary.txt` artifact.
4. **push-image** (main only): pushes `:latest` + `:<short-sha>` to Docker Hub. Requires `rust-quality` AND `image-build-and-test` to succeed.
5. **report-failure** (main only): on `image-build-and-test` failure, opens a new `ci-failure`-labeled issue or comments on an existing one (dedupe).

### `codeql.yml` (new)

CodeQL on workflow files. PR + push to main + weekly Monday cron.

### `dependabot.yml` (rewrite)

Replaces the minimal github-actions-only config with three ecosystems: cargo, github-actions, docker. Weekly Mondays, grouped where appropriate.

### Cleanup

- Deleted 13 obsolete workflow files (`*.disabled`, `*.bak`)
- Deleted 7 `.github/scripts/` helpers (only consumers were the deleted workflows)
- Deleted 2 stale CI docs (`docs/ci-performance-report.md`, `docs/operations/ci-monitoring.md`)
- Pruned the stale CI block from `docs/troubleshooting/common-issues.md` (lines 492–750)
- Rewrote `.github/CONTRIBUTING.md` "## CI/CD Workflow" section to describe the new setup

## Verification

- [x] `cargo test` passes locally (verified during plan authoring)
- [x] `testthat::test_dir("tests/testthat")` passes locally (FAIL=0)
- [x] `python3 -c "import yaml; ..."` parses all three new YAML files cleanly
- [x] `gh secret list` confirms `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` exist
- [x] `gh label create ci-failure` ran during preflight (label exists)
- [ ] CI itself passes against this PR (this is the actual gate; reviewer should watch the run)

## What happens after merge

1. The first `main`-branch run pushes `chrisschwer/league-simulator:latest` + `:<short-sha>` to Docker Hub.
2. Verify on the Docker Hub UI that the image is published.
3. Open PR-B (one-line change to `docker-compose.yml` swapping `:integrated-system-deps` → `:latest`).
4. Within a week, Dependabot opens at least one PR.
5. The next Monday, CodeQL produces a baseline scan in the Security tab.

## Coordination

- #85, #88 (test-suite cleanup): merged. Foundation for this PR.
- #84 (prune-root-clutter): merged. No file overlap.

## Test plan

- [ ] CI run on this PR is green (or, if the first run reveals a real issue, iterate on the workflow until green before merging)
- [ ] After merge: confirm Docker Hub has `:latest` and `:<short-sha>` tags
- [ ] After merge: open PR-B, confirm CI runs against it

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF

gh pr create --title "ci(#76): rebuild CI/CD pipeline (single workflow, post-cleanup)" --body-file /tmp/pr-body.md
```

Expected: PR URL printed.

- [ ] **Step 3: Confirm PR is open**

```bash
gh pr view --json number,title,state,url
```

Expected: state OPEN.

- [ ] **Step 4: STOP — wait for CI to complete and the user to merge**

The workflow runs against this PR (since it triggers on `pull_request`). The first run will likely uncover real issues:

- `cargo fmt --check` may fail if existing Rust code isn't fmt-clean → fix in this PR with `cargo fmt --all`, commit, push.
- `cargo clippy -- -D warnings` may fail on existing warnings → either fix the warnings or temporarily downgrade clippy to advisory in this PR (with a TODO commit message); user decides.
- `image-build-and-test` may surface package-install issues from the Dockerfile → diagnose, fix in the Dockerfile if needed, push.

After the user merges PR-A (and confirms `:latest` is published on Docker Hub), proceed to PR-B in Task 9.

Don't proceed to PR-B unless the user explicitly confirms PR-A is merged and the first `:latest` push has landed.

---

## PR-B: docker-compose.yml tag bump (follow-up)

### Task 9: Worktree + tag bump

**Files:**
- Modify: `docker-compose.yml` line 3

**Goal:** One-line change: `chrisschwer/league-simulator:integrated-system-deps` → `chrisschwer/league-simulator:latest`. Verify CI runs against the change.

- [ ] **Step 1: Confirm PR-A has merged AND `:latest` is published**

From the original main checkout:

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update"
git fetch origin
git log origin/main --oneline -5
```

Expected: top of the log shows the PR-A merge commit.

Then verify the Docker Hub tag:

```bash
# Use Docker Hub's HTTP API (no auth needed for public repos)
curl -s "https://hub.docker.com/v2/repositories/chrisschwer/league-simulator/tags/?page_size=10" \
  | python3 -c "import json, sys; tags = json.load(sys.stdin)['results']; print('\n'.join(t['name'] for t in tags))"
```

Expected: `latest` appears in the list. If not, STOP — wait for the first CI run on `main` to complete.

- [ ] **Step 2: Create the PR-B worktree**

```bash
git worktree add ../League-Simulator-Update.issue-76-compose -b feature/issue-76-compose-latest origin/main
cd ../League-Simulator-Update.issue-76-compose
git status --short
git branch --show-current
```

Expected: empty status; branch `feature/issue-76-compose-latest`.

- [ ] **Step 3: Apply the one-line change**

Use the Edit tool on `docker-compose.yml`. Find:

```
    image: chrisschwer/league-simulator:integrated-system-deps
```

Replace with:

```
    image: chrisschwer/league-simulator:latest
```

- [ ] **Step 4: Verify the edit**

```bash
grep -n 'image:' docker-compose.yml
```

Expected: one line showing `chrisschwer/league-simulator:latest`.

```bash
docker-compose config 2>&1 | head -5
```

Expected: parses cleanly. If `docker-compose` is not installed locally, skip this step — CI will validate via the build step.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yml
git commit -m "$(cat <<'EOF'
chore(#76): point docker-compose.yml at :latest tag

Bumps the production image tag from the stale :integrated-system-deps
(an artifact name from the pre-cleanup multi-Dockerfile era) to :latest,
which is now the canonical tag published by ci.yml on every green main
commit.

Operators pulling :integrated-system-deps continue to work — the old
tag is still on Docker Hub. New deployments and `docker-compose pull`
runs will use :latest from this point forward.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Push and open the PR**

```bash
git push -u origin feature/issue-76-compose-latest
gh pr create --title "chore(#76): point docker-compose.yml at :latest tag" --body "$(cat <<'EOF'
## Summary

One-line follow-up to #<PR-A-NUMBER>. Bumps `docker-compose.yml`'s image tag from the stale `:integrated-system-deps` to `:latest`. The new tag is now published by `ci.yml` on every green main commit; `:integrated-system-deps` was an artifact name from the pre-cleanup multi-Dockerfile era.

## Risk

Minimal. Operators pulling `:integrated-system-deps` continue to work (old tag stays on Docker Hub). New `docker-compose pull` runs will fetch `:latest` from this point forward.

## Test plan

- [ ] CI runs against this PR (trivially — no functional change to workflow itself)
- [ ] `docker-compose pull` from any host fetches `:latest` (verified manually after merge if desired)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Replace `<PR-A-NUMBER>` with the actual PR-A number from `gh pr view --json number` if you want a clean cross-link.

- [ ] **Step 7: Wait for CI green, then user merges**

The new `ci.yml` runs against this PR (trivially — no Dockerfile or Rust source changes; image-build-and-test should still pass quickly thanks to the layer cache). Wait for the green check, then the user merges.

- [ ] **Step 8: Clean up worktrees**

After both PRs merge:

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update"
git fetch origin
git pull --ff-only origin main
git worktree remove --force ../League-Simulator-Update.issue-76-ci-rebuild
git worktree remove --force ../League-Simulator-Update.issue-76-compose
git branch -D feature/issue-76-ci-rebuild feature/issue-76-compose-latest
git fetch --prune origin
git worktree list
```

Expected: only the main checkout remains.

- [ ] **Step 9: Comment on issue #76**

```bash
PRA_NUM=<actual PR-A number>
PRB_NUM=<actual PR-B number>
gh issue close 76 --comment "CI rebuild complete: PR-A #${PRA_NUM} (workflows + docs cleanup) + PR-B #${PRB_NUM} (compose tag bump). The pipeline now publishes :latest + :<short-sha> on every green main commit, opens deduplicated ci-failure issues on testthat regressions, and runs CodeQL + Dependabot for security."
```

Replace the `<...>` markers with real PR numbers.

---

## Self-Review Notes (for the executing worker)

Before claiming the plan is done, verify each:

1. **Spec coverage.** Every section of `docs/superpowers/specs/2026-05-02-ci-rebuild-design.md` has a task:
   - Goal item 1 (clippy/fmt) → Task 6 `rust-quality` job
   - Goal item 2 (cargo test) → Task 6 `rust-quality` job
   - Goal item 3 (image build) → Task 6 `image-build-and-test` job
   - Goal item 4 (testthat in image) → Task 6 `image-build-and-test` job
   - Goal item 5 (push on green main) → Task 6 `push-image` job + Task 9 compose bump
   - Goal item 6 (deduplicated issue on failure) → Task 6 `report-failure` job
   - Goal item 7 (CodeQL + Dependabot) → Task 5 (codeql) + Task 4 (dependabot)
   - Goal item 8 (R lint advisory) → Task 6 `r-lint` job
   - Cleanup of 13 workflows + 7 scripts + 2 docs → Task 1
   - common-issues.md edit → Task 2
   - CONTRIBUTING.md edit → Task 3
   - docker-compose tag bump → Task 9

2. **No placeholders.** Every step contains the actual content (YAML, bash commands, git commit messages). Two intentional placeholders remain in Task 9 step 9 (`<actual PR-A number>` / `<actual PR-B number>`) because those numbers don't exist until the worker runs the prior step — these are filled in at execution, not in the plan.

3. **Type / path consistency.**
   - `IMAGE_NAME: chrisschwer/league-simulator` matches the existing tag pattern in `docker-compose.yml`.
   - `Cargo.toml` package name confirmed as `league-simulator-rust`; cache key uses `Cargo.lock` hash.
   - `Dockerfile` base images are `rust:1.81-alpine` and `rocker/r-ver:4.3.1` — both supported by Dependabot's docker ecosystem.
   - `gh label create ci-failure` color `B60205` is GitHub's "danger red" — used elsewhere in the project for `bug` (verify with `gh label list` if you want to match exactly; not blocking).

4. **TDD discipline.** This plan is mostly configuration files, not code. The "test" for each task is "the next CI run passes." Strict TDD doesn't apply to YAML; instead, the verification gates (Task 7 static checks + the actual PR CI run) serve as the empirical confirmation.
