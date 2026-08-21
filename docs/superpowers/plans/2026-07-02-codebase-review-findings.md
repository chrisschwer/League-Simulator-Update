# Codebase Review Findings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all actionable findings from the 2026-07-02 three-dimension codebase review (security, efficiency, usability) in one coherent branch/PR.

**Architecture:** Small, independent fixes across four subsystems: Rust simulation server (input validation, hot-path performance), R orchestration (API-call gating, vectorization, secret handling), Shiny app (graceful degradation, stale-data warning), and infrastructure (Docker hardening + layer caching, CI action pinning, docs). One branch, one PR — the Docker changes (non-root user + new runtime stage) interact and must be CI-validated together.

**Tech Stack:** R 4.3+ (testthat, httr, jsonlite, shiny), Rust (axum 0.8, rayon, statrs), Docker multi-stage builds, GitHub Actions.

## Global Constraints

- Branch: `fix/codebase-review-2026-07` off `main`. One PR at the end. Conventional-commit messages (`fix:`, `perf:`, `docs:`, `chore:`).
- NEVER commit the string `3EBFA2C60C1438DAAA98FE4C0CAEC9AC` in any new file (it is the compromised token being removed). This plan file references it only descriptively.
- R code style: repo has `.lintr`; run `Rscript -e 'lintr::lint("<file>")'` on every touched R file, zero new findings.
- Rust: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` must pass in `league-simulator-rust/` after every Rust task.
- R tests are run per-file: `Rscript -e 'testthat::test_file("tests/testthat/<file>")'` from the repo root.
- Behavior-identical refactors (Tasks 8, 9) need a green run of their existing test file BEFORE and AFTER the change.
- Production simulation behavior (probability outputs) must remain statistically identical; exact RNG-stream equality is NOT required for Task 5/6 (documented there).
- The operator (user) rotates the ShinyApps.io token out-of-band and sets `SHINYAPPS_IO_TOKEN` in `.env`. Code must hard-fail with an actionable message when it is missing.

## Consciously NOT implemented (from review, with reasons)

- `rust_integration.R` lapply serialization & Shiny `apply()` caching — review itself assessed "kein relevanter Effekt".
- `calculate_table` per-call `Vec<TeamStanding>` allocation — 18–20-element alloc; fixing it churns a public API used by lib + tests for negligible gain.
- Poisson binary-search upper bound `lambda*3+20` — obsolete: after Task 5 the binary search only runs for lambda ≥ 10, which never occurs in production (lambda ≈ 0.6–2.5).
- app.R German/English naming consistency — pure style churn, no user-visible effect.

---

### Task 1: Remove hardcoded ShinyApps.io token

**Files:**
- Modify: `RCode/updateShiny.R:26-30`
- Modify: `docker-compose.yml:9`
- Test: `tests/testthat/test-updateShiny-env.R` (create)

**Interfaces:**
- Produces: `updateShiny()` now requires env vars `SHINYAPPS_IO_TOKEN` and `SHINYAPPS_IO_SECRET`; reads optional `SHINYAPPS_IO_NAME` (default `"chrisschwer"`). Task 12 later edits the `appFiles` line in this same file.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-updateShiny-env.R`:

```r
# updateShiny must hard-fail with an actionable message when ShinyApps.io
# credentials are missing from the environment (no hardcoded fallbacks).

source_updateShiny <- function() {
  source(test_path("..", "..", "RCode", "updateShiny.R"), local = TRUE)
  environment()$updateShiny
}

test_that("updateShiny stops when SHINYAPPS_IO_TOKEN is not set", {
  updateShiny <- source_updateShiny()
  withr::local_envvar(c(SHINYAPPS_IO_TOKEN = "", SHINYAPPS_IO_SECRET = "dummy"))
  expect_error(
    updateShiny(NULL, NULL, NULL, directory = tempdir()),
    "SHINYAPPS_IO_TOKEN"
  )
})

test_that("updateShiny stops when SHINYAPPS_IO_SECRET is not set", {
  updateShiny <- source_updateShiny()
  withr::local_envvar(c(SHINYAPPS_IO_TOKEN = "dummy", SHINYAPPS_IO_SECRET = ""))
  expect_error(
    updateShiny(NULL, NULL, NULL, directory = tempdir()),
    "SHINYAPPS_IO_SECRET"
  )
})
```

If `withr` is unavailable in the local test setup, use `old <- Sys.getenv(...); Sys.setenv(...); on.exit(...)` instead — check how existing tests (e.g. `tests/testthat/test-rust-required.R`) manage env vars and follow that pattern.

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-updateShiny-env.R")'`
Expected: FAIL (no error raised for missing token — current code hardcodes it).

- [ ] **Step 3: Implement**

In `RCode/updateShiny.R`, insert env validation as the FIRST statements inside the function body (before the `required_packages` loop, so the check needs no packages), and replace the hardcoded credentials block:

```r
updateShiny <- function(Ergebnis, Ergebnis2, Ergebnis3,
                        Ergebnis3_Aufstieg = Ergebnis3,
                        directory = file.path(
                          "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox-CSDataScience",
                          "Christoph Schwerdtfeger/Coding Projects/LeagueSimulator_Claude",
                          "League-Simulator-Update/ShinyApp"
                        ),
                        forceUpdate = TRUE) {
  account_name <- Sys.getenv("SHINYAPPS_IO_NAME", "chrisschwer")
  account_token <- Sys.getenv("SHINYAPPS_IO_TOKEN")
  account_secret <- Sys.getenv("SHINYAPPS_IO_SECRET")

  if (account_token == "") {
    stop("ERROR: SHINYAPPS_IO_TOKEN environment variable not set")
  }
  if (account_secret == "") {
    stop("ERROR: SHINYAPPS_IO_SECRET environment variable not set")
  }
```

Then DELETE the old lines 26-28 (`account_name <- "chrisschwer"`, the hardcoded `account_token <- "..."`, and the old `account_secret <- Sys.getenv(...)`). The `rsconnect::setAccountInfo(...)` call stays unchanged.

In `docker-compose.yml` line 9, remove the fallback default:

```yaml
      - SHINYAPPS_IO_TOKEN=${SHINYAPPS_IO_TOKEN}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-updateShiny-env.R")'`
Expected: PASS (2 tests).

Also verify the token string is gone from the working tree:
Run: `grep -rn "3EBFA2C60C1438DAAA98FE4C0CAEC9AC" --exclude-dir=.git . || echo CLEAN`
Expected: only this plan file (descriptive mention) — no code/config hits. If the plan file is the sole hit: OK.

- [ ] **Step 5: Commit**

```bash
git add RCode/updateShiny.R docker-compose.yml tests/testthat/test-updateShiny-env.R
git commit -m "fix(security): read ShinyApps.io token from environment, remove hardcoded credential"
```

---

### Task 2: Rust API input validation, iterations cap, body limit

**Files:**
- Modify: `league-simulator-rust/src/api/handlers.rs`
- Modify: `league-simulator-rust/src/api/mod.rs`
- Modify: `league-simulator-rust/Cargo.toml` (remove `tower-http` if unused after CORS removal)
- Test: `league-simulator-rust/src/api/tests.rs`

**Interfaces:**
- Produces: `/simulate` and `/simulate/batch` return `400 Bad Request` with a plain-text body explaining the validation failure. Success responses unchanged. `MAX_ITERATIONS = 100_000`.

- [ ] **Step 1: Read `league-simulator-rust/src/api/tests.rs`** to learn the existing oneshot-test pattern (imports, helper for building requests). Reuse it exactly.

- [ ] **Step 2: Write failing tests** (append to `src/api/tests.rs`, adapting imports to the existing pattern):

```rust
#[tokio::test]
async fn simulate_rejects_team_index_zero() {
    // team index 0 previously underflowed to usize::MAX and aborted the process
    let body = serde_json::json!({
        "schedule": [[0, 2, null, null]],
        "elo_values": [1500.0, 1500.0]
    });
    let response = post_json("/simulate", body).await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_null_team_index() {
    let body = serde_json::json!({
        "schedule": [[null, 2, null, null]],
        "elo_values": [1500.0, 1500.0]
    });
    let response = post_json("/simulate", body).await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_out_of_range_team_index() {
    let body = serde_json::json!({
        "schedule": [[1, 3, null, null]],
        "elo_values": [1500.0, 1500.0]
    });
    let response = post_json("/simulate", body).await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_excessive_iterations() {
    let body = serde_json::json!({
        "schedule": [[1, 2, null, null]],
        "elo_values": [1500.0, 1500.0],
        "iterations": 100_000_000
    });
    let response = post_json("/simulate", body).await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_mismatched_adjustment_length() {
    let body = serde_json::json!({
        "schedule": [[1, 2, null, null]],
        "elo_values": [1500.0, 1500.0],
        "adj_points": [0, 0, 0]
    });
    let response = post_json("/simulate", body).await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}
```

If the existing tests have no `post_json` helper, write one following their exact request-building style.

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd league-simulator-rust && cargo test api`
Expected: new tests FAIL (some may abort/panic — that is the bug being fixed).

- [ ] **Step 4: Implement validation in `handlers.rs`**

Add near the top of the file:

```rust
/// Server-side ceiling on Monte Carlo iterations (production uses 10,000).
const MAX_ITERATIONS: usize = 100_000;

fn validate_request(payload: &SimulateRequest) -> Result<(), String> {
    if payload.schedule.is_empty() {
        return Err("schedule must not be empty".to_string());
    }
    let number_teams = payload.elo_values.len();
    if number_teams == 0 {
        return Err("elo_values must not be empty".to_string());
    }
    if let Some(iterations) = payload.iterations {
        if iterations == 0 || iterations > MAX_ITERATIONS {
            return Err(format!(
                "iterations must be between 1 and {}, got {}",
                MAX_ITERATIONS, iterations
            ));
        }
    }
    for (i, row) in payload.schedule.iter().enumerate() {
        for (name, value) in [("team_home", row[0]), ("team_away", row[1])] {
            match value {
                Some(v) if v >= 1 && (v as usize) <= number_teams => {}
                Some(v) => {
                    return Err(format!(
                        "schedule row {}: {} index {} out of range 1..={}",
                        i, name, v, number_teams
                    ))
                }
                None => return Err(format!("schedule row {}: {} must not be null", i, name)),
            }
        }
    }
    for (name, adj) in [
        ("adj_points", &payload.adj_points),
        ("adj_goals", &payload.adj_goals),
        ("adj_goals_against", &payload.adj_goals_against),
        ("adj_goal_diff", &payload.adj_goal_diff),
    ] {
        if let Some(v) = adj {
            if v.len() != number_teams {
                return Err(format!(
                    "{} has length {}, expected {} (one per team)",
                    name,
                    v.len(),
                    number_teams
                ));
            }
        }
    }
    Ok(())
}
```

Change `simulate_league`'s signature and body:

```rust
pub async fn simulate_league(
    Json(payload): Json<SimulateRequest>,
) -> Result<Json<SimulateResponse>, (StatusCode, String)> {
    let start = std::time::Instant::now();

    validate_request(&payload).map_err(|e| (StatusCode::BAD_REQUEST, e))?;

    let number_teams = payload.elo_values.len();
```

Delete the two old ad-hoc checks (empty schedule / zero teams — now inside `validate_request`). The match conversion becomes panic-free because validation guarantees `Some(v)` with `1 <= v <= number_teams`:

```rust
    let matches: Vec<Match> = payload
        .schedule
        .iter()
        .map(|row| Match {
            // Validated above: indices are Some and within 1..=number_teams.
            // R uses 1-indexed, Rust uses 0-indexed.
            team_home: row[0].unwrap() as usize - 1,
            team_away: row[1].unwrap() as usize - 1,
            goals_home: row[2],
            goals_away: row[3],
        })
        .collect();
```

Propagate errors through the batch path — `simulate_league_internal` must no longer swallow failures into empty responses:

```rust
async fn simulate_league_internal(
    request: SimulateRequest,
) -> Result<SimulateResponse, (StatusCode, String)> {
    simulate_league(Json(request)).await.map(|Json(r)| r)
}
```

And in `simulate_batch`, adjust the collection loop:

```rust
    for task in tasks {
        match task.await {
            Ok((name, Ok(response))) => {
                results.push(LeagueResult { name, response });
            }
            Ok((name, Err((status, msg)))) => {
                return Err((status, format!("league '{}': {}", name, msg)));
            }
            Err(_) => {
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "batch task panicked".to_string(),
                ));
            }
        }
    }
```

`simulate_batch`'s signature becomes `Result<Json<BatchSimulateResponse>, (StatusCode, String)>`.

- [ ] **Step 5: Add body limit, drop permissive CORS in `mod.rs`**

CORS is a browser mechanism; the only clients are R/httr and curl, which ignore it — the permissive layer adds attack surface for nothing. Replace `mod.rs` router setup:

```rust
use axum::{
    extract::DefaultBodyLimit,
    routing::{get, post},
    Router,
};

pub fn create_router() -> Router {
    Router::new()
        .route("/health", get(handlers::health_check))
        .route("/simulate", post(handlers::simulate_league))
        .route("/simulate/batch", post(handlers::simulate_batch))
        // Payloads are ~306 fixture rows (<100 KB); 2 MB is generous headroom.
        .layer(DefaultBodyLimit::max(2 * 1024 * 1024))
}
```

Remove the `Method`/`tower_http::cors` imports. Then check whether `tower-http` is still used anywhere: `grep -rn "tower_http" league-simulator-rust/src/`. If this was the only use, remove the `tower-http` dependency line from `Cargo.toml`.

- [ ] **Step 6: Run tests**

Run: `cd league-simulator-rust && cargo test && cargo fmt --check && cargo clippy -- -D warnings`
Expected: all PASS, no warnings. If existing tests asserted plain `StatusCode` error returns, update them to the new `(StatusCode, String)` shape.

- [ ] **Step 7: Commit**

```bash
git add league-simulator-rust
git commit -m "fix(security): validate simulation requests, cap iterations, limit body size

A team index of 0 or null underflowed to usize::MAX and aborted the
whole process (panic=abort) — a one-request remote DoS. Requests are
now validated up front and rejected with 400 + reason. Also removes
the permissive CORS layer (no browser clients exist) and caps request
bodies at 2 MB."
```

---

### Task 3: Bind Rust port to localhost, stop logging API-key prefix

**Files:**
- Modify: `docker-compose.yml:15`
- Modify: `docker-start.sh:102`

- [ ] **Step 1: Implement**

`docker-compose.yml` line 15 (the integrated service; leave the debug-profile `rust-simulator` service's mapping as is, or apply the same binding there too — do both for consistency):

```yaml
    ports:
      - "127.0.0.1:8081:8080"  # Rust API, host-local only (monitoring via curl on the host)
```

`docker-start.sh` line 102 — replace:

```sh
echo "API Key: $(echo $RAPIDAPI_KEY | cut -c1-10)..."
```

with:

```sh
echo "API Key: $([ -n "$RAPIDAPI_KEY" ] && echo "SET" || echo "NOT SET")"
```

- [ ] **Step 2: Verify**

Run: `docker compose config > /dev/null && echo OK` (validates YAML)
Run: `sh -n docker-start.sh && echo OK` (validates shell syntax)
Expected: `OK` twice.

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml docker-start.sh
git commit -m "fix(security): bind Rust API to localhost on host, stop logging API-key prefix"
```

---

### Task 4: Pin GitHub Actions to commit SHAs

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/codeql.yml`

- [ ] **Step 1: Resolve each action tag to its commit SHA**

For every `uses:` entry (`actions/checkout@v7`, `dtolnay/rust-toolchain@stable`, `actions/cache@v6`, `r-lib/actions/setup-r@v2`, `docker/setup-buildx-action@v4`, `docker/login-action@v4`, `docker/build-push-action@v7`, `actions/upload-artifact@v7`, `actions/download-artifact@v8`, `github/codeql-action/init@v4`, `github/codeql-action/analyze@v4`), resolve the SHA:

```bash
gh api repos/actions/checkout/git/ref/tags/v7 --jq '.object.sha'
# If the tag object is annotated, dereference:
gh api repos/actions/checkout/git/tags/<sha-from-above> --jq '.object.sha' 2>/dev/null || true
```

For branch-style refs (`dtolnay/rust-toolchain@stable`): `gh api repos/dtolnay/rust-toolchain/commits/stable --jq '.sha'`.
For subpath actions (`r-lib/actions/setup-r@v2`, `github/codeql-action/init@v4`): resolve the SHA of the REPO (`r-lib/actions`, `github/codeql-action`) at that tag; the subpath stays in the `uses:` string.

- [ ] **Step 2: Rewrite every `uses:` line** to the form:

```yaml
        uses: actions/checkout@<full-40-char-sha>  # v7
```

(keep the human-readable tag as a trailing comment).

- [ ] **Step 3: Document the fork-PR login guard**

Above the `Log in to Docker Hub (read-only for cache)` step in `ci.yml` (line ~94), extend the existing setup with an explicit comment:

```yaml
      # Fork/Dependabot PRs get empty secrets from GitHub, so this step is
      # skipped there by the env guard below — they build without registry
      # login and can only READ the public build cache. Do not remove the guard.
```

- [ ] **Step 4: Verify**

Run: `grep -n "uses:" .github/workflows/ci.yml .github/workflows/codeql.yml`
Expected: every line matches `@[0-9a-f]{40}  # v...` (except none remain on bare tags).
Optionally: `actionlint` if installed; otherwise rely on CI.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/codeql.yml
git commit -m "chore(security): pin GitHub Actions to commit SHAs"
```

---

### Task 5: Fast Poisson quantile in the simulation hot path

**Files:**
- Modify: `league-simulator-rust/src/simulation/match_sim.rs`
- Delete: `league-simulator-rust/src/simulation/match_sim_fixed.rs` (dead code, not even declared in `mod.rs`)

**Interfaces:**
- Produces: `poisson_quantile_direct(p: f64, lambda: f64) -> f64` (public, in `match_sim.rs`). `poisson_quantile` dispatches: direct for `lambda < 10`, binary search otherwise. `simulate_match` / `simulate_match_random` signatures unchanged.

**Note on determinism:** the direct method computes the same qpois semantics (smallest k with `P(X ≤ k) ≥ p`) via iterative summation instead of gamma-function CDFs. Float rounding could theoretically differ at exact CDF boundaries (~1e-15 measure); statistically irrelevant for Monte Carlo. The equivalence test below pins agreement across a dense grid.

- [ ] **Step 1: Write failing tests** (append `#[cfg(test)] mod tests` inside `match_sim.rs`, or extend if one exists):

```rust
#[cfg(test)]
mod poisson_tests {
    use super::*;

    #[test]
    fn direct_quantile_matches_r_qpois() {
        // Expected values computed with R: qpois(p, 1.3218390805)
        let lambda = 1.3218390805;
        let cases = [
            (0.1, 0.0),
            (0.2, 0.0),
            (0.3, 1.0),
            (0.5, 1.0),
            (0.7, 2.0),
            (0.9, 3.0),
        ];
        for (p, expected) in cases {
            assert_eq!(
                poisson_quantile_direct(p, lambda),
                expected,
                "qpois({}, {})",
                p,
                lambda
            );
        }
    }

    #[test]
    fn direct_quantile_agrees_with_binary_search() {
        for &lambda in &[0.1, 0.5, 1.0, 1.3218390805, 2.0, 5.0, 9.9] {
            let mut p = 0.001;
            while p < 0.999 {
                assert_eq!(
                    poisson_quantile_direct(p, lambda),
                    poisson_quantile_statrs(p, lambda),
                    "divergence at p={}, lambda={}",
                    p,
                    lambda
                );
                p += 0.001;
            }
        }
    }

    #[test]
    fn direct_quantile_edge_cases() {
        assert_eq!(poisson_quantile_direct(0.0, 1.5), 0.0);
        assert_eq!(poisson_quantile_direct(-0.1, 1.5), 0.0);
        assert_eq!(poisson_quantile_direct(1.0, 1.5), f64::INFINITY);
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd league-simulator-rust && cargo test poisson`
Expected: COMPILE ERROR — `poisson_quantile_direct` does not exist.

- [ ] **Step 3: Implement in `match_sim.rs`**

Replace the `poisson_quantile` dispatcher and add the direct method:

```rust
/// Calculate the quantile of a Poisson distribution.
/// Matches R's qpois: smallest integer k with P(X <= k) >= p.
fn poisson_quantile(p: f64, lambda: f64) -> f64 {
    // Production lambdas are ~0.6-2.5 (ELO-derived goal averages), so the
    // O(k) direct summation terminates after a handful of multiplications
    // instead of ~5 regularized-gamma CDF evaluations per draw.
    if lambda < 10.0 {
        poisson_quantile_direct(p, lambda)
    } else {
        poisson_quantile_statrs(p, lambda)
    }
}

/// Iterative CDF summation: P(X = k) = P(X = k-1) * lambda / k.
pub fn poisson_quantile_direct(p: f64, lambda: f64) -> f64 {
    if p <= 0.0 {
        return 0.0;
    }
    if p >= 1.0 {
        return f64::INFINITY;
    }
    let mut k: u64 = 0;
    let mut prob = (-lambda).exp(); // P(X = 0)
    let mut cumulative = prob;
    while cumulative < p && k < 1000 {
        k += 1;
        prob *= lambda / (k as f64);
        cumulative += prob;
    }
    k as f64
}
```

Keep `poisson_quantile_statrs` unchanged (still used for lambda ≥ 10 and by the equivalence test).

Delete `league-simulator-rust/src/simulation/match_sim_fixed.rs` (`git rm`). It was never declared in `simulation/mod.rs` — verify with `grep -rn "match_sim_fixed" league-simulator-rust/src/` → only the file itself.

- [ ] **Step 4: Run tests**

Run: `cd league-simulator-rust && cargo test && cargo fmt --check && cargo clippy -- -D warnings`
Expected: all PASS including existing simulation/API tests.

- [ ] **Step 5: Commit**

```bash
git add -A league-simulator-rust/src/simulation
git commit -m "perf: direct Poisson quantile for small lambda, remove dead match_sim_fixed.rs"
```

---

### Task 6: Lock-free Monte Carlo aggregation + per-thread buffer reuse

**Files:**
- Modify: `league-simulator-rust/src/simulation/season.rs`
- Modify: `league-simulator-rust/src/monte_carlo/mod.rs`

**Interfaces:**
- Consumes: `calculate_table` (unchanged).
- Produces: `simulate_season_in_place(matches: &mut [Match], elos: &mut [f64], mod_factor: f64, home_advantage: f64, tore_slope: f64, tore_intercept: f64, rng: &mut R)` in `season.rs`. Existing `simulate_season` / `process_season` keep their signatures (now thin wrappers).

- [ ] **Step 1: Baseline** — run `cd league-simulator-rust && cargo test` → all green (existing determinism/seed tests are the safety net; count aggregation is commutative, so fold/reduce ordering cannot change results).

- [ ] **Step 2: Refactor `season.rs`**

Extract the loop body of `simulate_season` into an in-place variant; `simulate_season` becomes a wrapper:

```rust
/// In-place variant: operates on caller-owned buffers so Monte Carlo
/// iterations can reuse allocations instead of cloning per iteration.
pub fn simulate_season_in_place<R: Rng>(
    matches: &mut [Match],
    elos: &mut [f64],
    mod_factor: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    rng: &mut R,
) {
    for match_data in matches.iter_mut() {
        let team_home = match_data.team_home;
        let team_away = match_data.team_away;

        if match_data.goals_home.is_none() {
            let result = simulate_match_random(
                elos[team_home],
                elos[team_away],
                mod_factor,
                home_advantage,
                tore_slope,
                tore_intercept,
                rng,
            );
            match_data.goals_home = Some(result.goals_home);
            match_data.goals_away = Some(result.goals_away);
            elos[team_home] = result.new_elo_home;
            elos[team_away] = result.new_elo_away;
        } else {
            let params = EloParams {
                elo_home: elos[team_home],
                elo_away: elos[team_away],
                goals_home: match_data.goals_home.unwrap(),
                goals_away: match_data.goals_away.unwrap(),
                mod_factor,
                home_advantage,
            };
            let result = calculate_elo_change(&params);
            elos[team_home] = result.new_elo_home;
            elos[team_away] = result.new_elo_away;
        }
    }
}

pub fn simulate_season<R: Rng>(
    season: &Season,
    mod_factor: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    rng: &mut R,
) -> (Vec<Match>, Vec<f64>) {
    let mut matches = season.matches.clone();
    let mut elos = season.team_elos.clone();
    simulate_season_in_place(
        &mut matches,
        &mut elos,
        mod_factor,
        home_advantage,
        tore_slope,
        tore_intercept,
        rng,
    );
    (matches, elos)
}
```

(Match the generic bounds the current code compiles with — if `simulate_match_random` needs `R: Rng + RngExt`, mirror that.)

- [ ] **Step 3: Rewrite aggregation in `monte_carlo/mod.rs`**

Replace the `Mutex`-based section of `run_monte_carlo_simulation_with_seeds` (keep everything from `// Convert counts to probabilities` onward, adapting it to read from plain `Vec<Vec<usize>>`):

```rust
use crate::simulation::{calculate_table, simulate_season_in_place};

    let n_teams = season.number_teams;

    // Per-thread fold state: reusable simulation buffers + local counts.
    // No locks; rayon reduces the per-thread counts at the end (addition is
    // commutative, so scheduling order cannot affect the result).
    struct IterState {
        matches: Vec<crate::models::Match>,
        elos: Vec<f64>,
        counts: Vec<Vec<usize>>,
    }

    let position_counts: Vec<Vec<usize>> = seeds
        .par_iter()
        .fold(
            || IterState {
                matches: Vec::with_capacity(season.matches.len()),
                elos: Vec::with_capacity(n_teams),
                counts: vec![vec![0usize; n_teams]; n_teams],
            },
            |mut state, &seed| {
                let mut rng = StdRng::seed_from_u64(seed);

                state.matches.clear();
                state.matches.extend_from_slice(&season.matches);
                state.elos.clear();
                state.elos.extend_from_slice(&season.team_elos);

                simulate_season_in_place(
                    &mut state.matches,
                    &mut state.elos,
                    params.mod_factor,
                    params.home_advantage,
                    params.tore_slope,
                    params.tore_intercept,
                    &mut rng,
                );

                let table = calculate_table(
                    &state.matches,
                    n_teams,
                    params.adj_points.as_deref(),
                    params.adj_goals.as_deref(),
                    params.adj_goals_against.as_deref(),
                    params.adj_goal_diff.as_deref(),
                );

                for standing in &table.standings {
                    state.counts[standing.team_id][standing.position - 1] += 1;
                }
                state
            },
        )
        .map(|state| state.counts)
        .reduce(
            || vec![vec![0usize; n_teams]; n_teams],
            |mut a, b| {
                for (row_a, row_b) in a.iter_mut().zip(b) {
                    for (cell_a, cell_b) in row_a.iter_mut().zip(row_b) {
                        *cell_a += cell_b;
                    }
                }
                a
            },
        );
```

Remove `use std::sync::Mutex;` and `use crate::simulation::process_season;` if no longer referenced (`process_season` stays in `season.rs` for external callers/tests — check `grep -rn "process_season" league-simulator-rust/src/` before removing the import only). Requires `Match: Clone` (check `models`; derive `Clone` if missing). Adjust the probability-conversion loop to index `position_counts[team_id][position]` directly without locking.

- [ ] **Step 4: Run tests**

Run: `cd league-simulator-rust && cargo test && cargo fmt --check && cargo clippy -- -D warnings`
Expected: all PASS — especially the seeded-determinism test in `monte_carlo/tests.rs`.

- [ ] **Step 5: Commit**

```bash
git add league-simulator-rust/src
git commit -m "perf: lock-free rayon fold/reduce aggregation and buffer reuse in Monte Carlo loop"
```

---

### Task 7: Dockerfile — dependency-layer caching, slim runtime stage, non-root user

**Files:**
- Modify: `Dockerfile`

**Interfaces:**
- Consumes: `docker-start.sh` (unchanged), Rust binary path `/usr/local/bin/league-simulator-rust`.
- Produces: final image runs as user `appuser` (uid 1001); R site-library at `/usr/local/lib/R/site-library` copied into a toolchain-free runtime stage.

- [ ] **Step 1: Rewrite `Dockerfile`**

```dockerfile
# Integrated League Simulator with Rust Engine
# Stage 1: Rust binary | Stage 2: R build (compilers) | Stage 3: slim runtime

# ---- Stage 1: Build Rust binary ----
FROM rust:1.96-alpine AS rust-builder

RUN apk add --no-cache musl-dev

WORKDIR /build

# Dependency layer: build with a dummy main so crate compilation is cached
# and re-runs only when Cargo.toml/Cargo.lock change, not on every code edit.
COPY league-simulator-rust/Cargo.toml league-simulator-rust/Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs \
    && cargo build --release \
    && rm -rf src target/release/league-simulator-rust* target/release/deps/league_simulator_rust*

COPY league-simulator-rust/src/ ./src/
COPY league-simulator-rust/test_data/ ./test_data/
RUN cargo build --release && strip target/release/league-simulator-rust

# ---- Stage 2: Build R library (needs compilers for source packages) ----
FROM rocker/r-ver:4.6.1 AS r-builder

RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    tzdata \
    build-essential \
    cmake \
    libuv1-dev \
    libfontconfig1-dev \
    libcairo2-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*
```

Keep the three existing `RUN R --slave ...` package-install blocks and the `COPY packagelist.txt /tmp/` EXACTLY as they are today (they run in this stage unchanged).

Then add the runtime stage:

```dockerfile
# ---- Stage 3: Runtime (no compilers, non-root) ----
FROM rocker/r-ver:4.6.1

# Runtime (non -dev) libraries for the compiled R packages + curl for healthchecks
RUN apt-get update && apt-get install -y \
    libcurl4 \
    libssl3 \
    libxml2 \
    curl \
    tzdata \
    libuv1 \
    libfontconfig1 \
    libcairo2 \
    libfreetype6 \
    libpng16-16 \
    libtiff6 \
    libjpeg62-turbo \
    && rm -rf /var/lib/apt/lists/*

# Compiled R packages from the build stage
COPY --from=r-builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

# Rust binary
COPY --from=rust-builder /build/target/release/league-simulator-rust /usr/local/bin/league-simulator-rust

WORKDIR /app
RUN mkdir -p /app/RCode /app/ShinyApp/data

COPY RCode/ ./RCode/
COPY ShinyApp/ ./ShinyApp/
COPY docker-start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Run as non-root; scheduler writes ShinyApp/data and rsconnect config in $HOME
RUN useradd --system --create-home --uid 1001 appuser \
    && chown -R appuser:appuser /app
USER appuser

ENV RUST_API_URL=http://localhost:8080
ENV SEASON=2025

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/app/start.sh"]
```

Notes for the implementer:
- If `league-simulator-rust/Cargo.lock` is not committed (`ls league-simulator-rust/Cargo.lock`), generate it (`cd league-simulator-rust && cargo generate-lockfile`) and commit it — reproducible builds need it anyway.
- Runtime lib names (`libssl3`, `libtiff6`, `libjpeg62-turbo`, `libpng16-16`) must match the Debian release under `rocker/r-ver:4.6.1`. Verify inside the image: `docker run --rm rocker/r-ver:4.6.1 bash -c "apt-cache policy libssl3 libtiff6 libjpeg62-turbo libpng16-16 libuv1"` and adjust names if the release differs (e.g. `libtiff5` on older Debian).

- [ ] **Step 2: Build and verify (slow, ~20 min)**

```bash
docker build -t league-simulator:review-test .
# Non-root?
docker run --rm league-simulator:review-test id -u        # expected: 1001
# All runtime-critical R packages load without compilers?
docker run --rm league-simulator:review-test Rscript -e \
  'for (p in c("httr","jsonlite","dplyr","tidyr","shiny","rsconnect","httpuv")) library(p, character.only = TRUE); cat("ALL OK\n")'
# Rust binary starts and answers?
docker run --rm -d --name ls-test league-simulator:review-test /usr/local/bin/league-simulator-rust --api
sleep 3 && docker exec ls-test curl -sf http://localhost:8080/health && docker rm -f ls-test
# Size comparison (informational):
docker images league-simulator:review-test
```

Expected: `1001`, `ALL OK`, health JSON. If any R package fails to load with a missing-`.so` error, add the corresponding runtime lib to stage 3.

- [ ] **Step 3: Commit**

```bash
git add Dockerfile league-simulator-rust/Cargo.lock
git commit -m "perf(docker): cache Rust dependency layer, add slim non-root runtime stage"
```

---

### Task 8: Vectorize transform_data

**Files:**
- Modify: `RCode/transform_data.R:34-39,55-67`
- Test: `tests/testthat/test-transform_data.R` (existing — characterization safety net)

- [ ] **Step 1: Baseline** — `Rscript -e 'testthat::test_file("tests/testthat/test-transform_data.R")'` → all green. If any test fails BEFORE the change, stop and report.

- [ ] **Step 2: Replace the goals-to-NA loop (lines 34-39)**

```r
  # set goals to NA unless game is finished
  # (FT = full time, AET = after extra time, PEN = decided on penalties)
  unfinished <- !df_final$fixture_status_short %in% c("FT", "AET", "PEN")
  df_final$ToreHeim[unfinished] <- NA
  df_final$ToreGast[unfinished] <- NA
```

- [ ] **Step 3: Replace the nested ELO-propagation loop (lines 55-67)**

The old loop finds a team's (constant) ELO among its rows — capped at row 50, silently wrong for teams first appearing later, and inheriting the previous column's ELO if none found. New version scans ALL rows and yields NA for a team with no appearance (more correct):

```r
  # Each team column carries the team's InitialELO in every row where the
  # team plays. Keep it only in the first line; all other lines become NA.
  for (i in 5:ncol(df_final)) {
    col_values <- df_final[[i]]
    first_elo <- col_values[which(!is.na(col_values))[1]]
    df_final[[i]] <- c(first_elo, rep(NA_real_, nrow(df_final) - 1))
  }
```

Also delete the now-unused `temp_ELO <- 0` at the top of the function.

- [ ] **Step 4: Run tests + lint**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-transform_data.R")'`
Expected: PASS (same results as baseline).
Run: `Rscript -e 'lintr::lint("RCode/transform_data.R")'` → no new findings.

- [ ] **Step 5: Commit**

```bash
git add RCode/transform_data.R
git commit -m "perf: vectorize transform_data, remove hardcoded 50-row ELO scan cap"
```

---

### Task 9: Vectorize Tabelle_presentation W/D/L counting

**Files:**
- Modify: `RCode/Tabelle_presentation.R:77-116`
- Test: `tests/testthat/test-Tabelle.R` (existing)

- [ ] **Step 1: Baseline** — `Rscript -e 'testthat::test_file("tests/testthat/test-Tabelle.R")'` → all green.

- [ ] **Step 2: Replace the per-game loop** (keep the `wins/draws/losses/games_played` initializations above):

```r
  if (numberGames > 0 && nrow(season) > 0) {
    played <- !is.na(season[, 3]) & !is.na(season[, 4])
    s <- season[played, , drop = FALSE]
    if (nrow(s) > 0) {
      games_played <- tabulate(s[, 1], nbins = numberTeams) +
        tabulate(s[, 2], nbins = numberTeams)
      home_win <- s[, 3] > s[, 4]
      away_win <- s[, 3] < s[, 4]
      draw <- s[, 3] == s[, 4]
      wins <- tabulate(s[home_win, 1], nbins = numberTeams) +
        tabulate(s[away_win, 2], nbins = numberTeams)
      losses <- tabulate(s[away_win, 1], nbins = numberTeams) +
        tabulate(s[home_win, 2], nbins = numberTeams)
      draws <- tabulate(s[draw, 1], nbins = numberTeams) +
        tabulate(s[draw, 2], nbins = numberTeams)
    }
  }
```

- [ ] **Step 3: Run tests + lint**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-Tabelle.R")'` → PASS.
Run: `Rscript -e 'lintr::lint("RCode/Tabelle_presentation.R")'` → no new findings.

- [ ] **Step 4: Commit**

```bash
git add RCode/Tabelle_presentation.R
git commit -m "perf: vectorize W/D/L counting in Tabelle_presentation"
```

---

### Task 10: Rate-limit header reuse + remove debug payload logging

**Files:**
- Modify: `RCode/retrieveResults.R`
- Modify: `RCode/checkAPILimits.R`
- Modify: `RCode/rust_integration.R:90-92`

**Interfaces:**
- Produces: environment `.api_rate_limit` (defined in `retrieveResults.R`) with fields `remaining`, `limit`, `as_of`; populated by every successful `retrieveResults()`/`retrieveLiveFixtures()` call. `checkAPILimits()` consumes it when fresh (< 10 min) instead of spending an extra request. Task 11 consumes `.api_rate_limit` too.

- [ ] **Step 1: In `retrieveResults.R`**, add at top level (above the function):

```r
# Last-seen API-Football rate-limit headers, shared across callers so
# checkAPILimits() can avoid spending a request just to read them.
.api_rate_limit <- new.env(parent = emptyenv())

.record_rate_limit_headers <- function(response) {
  hdrs <- httr::headers(response)
  remaining <- suppressWarnings(as.numeric(hdrs[["x-ratelimit-requests-remaining"]]))
  if (!is.na(remaining)) {
    .api_rate_limit$remaining <- remaining
    .api_rate_limit$limit <- suppressWarnings(as.numeric(hdrs[["x-ratelimit-requests-limit"]]))
    .api_rate_limit$as_of <- Sys.time()
  }
  invisible(NULL)
}
```

Inside `retrieveResults()`, directly after the `status_code(response) != 200` early return, add:

```r
  .record_rate_limit_headers(response)
```

- [ ] **Step 2: In `checkAPILimits.R`**, after the api_key check and before making the HTTP call, add:

```r
  # Reuse rate-limit headers captured by a recent retrieveResults() call
  # instead of spending a request on a dedicated probe.
  if (exists(".api_rate_limit") &&
    !is.null(.api_rate_limit$remaining) &&
    difftime(Sys.time(), .api_rate_limit$as_of, units = "mins") < 10) {
    remaining <- .api_rate_limit$remaining
    limit <- .api_rate_limit$limit
    message(sprintf(
      "API Rate Limit (cached): %d/%d requests remaining",
      remaining, limit
    ))
    safe_loops <- floor((remaining * safety_margin) / avg_calls_per_loop)
    return(min(ideal_loops, safe_loops))
  }
```

Rename the parameter `num_leagues = 3` to `avg_calls_per_loop = 2` (Task 11 reduces steady-state cost to ~1 live call/loop plus occasional full fetches; 2 is the conservative planning average) and update the formula comment plus the `safe_loops` division accordingly. Callers in `updateScheduler.R` pass only `ideal_loops`, so no call-site change is needed.

- [ ] **Step 3: In `rust_integration.R`**, delete lines 90-92:

```r
  # Debug JSON payload
  json_body <- toJSON(payload, auto_unbox = TRUE, null = "null")
  message("DEBUG: First schedule entry JSON: ", substr(json_body, 1, 200))
```

becomes:

```r
  json_body <- toJSON(payload, auto_unbox = TRUE, null = "null")
```

(The DEBUG block in the error path at lines 104-109 stays — it only runs on failure and is genuinely useful.)

- [ ] **Step 4: Verify**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-rust-required.R")'` → PASS.
Run: `Rscript -e 'lintr::lint("RCode/retrieveResults.R")' && Rscript -e 'lintr::lint("RCode/checkAPILimits.R")' && Rscript -e 'lintr::lint("RCode/rust_integration.R")'` → no new findings.

- [ ] **Step 5: Commit**

```bash
git add RCode/retrieveResults.R RCode/checkAPILimits.R RCode/rust_integration.R
git commit -m "perf: reuse cached rate-limit headers, drop per-call debug payload log"
```

---

### Task 11: Gate full fixture fetches behind a cheap live-fixtures poll

**Files:**
- Modify: `RCode/retrieveResults.R` (add `retrieveLiveFixtures`)
- Modify: `RCode/update_all_leagues_loop.R`
- Test: `tests/testthat/test-update-loop-gating.R` (create)

**Interfaces:**
- Consumes: `.record_rate_limit_headers` from Task 10.
- Produces: `retrieveLiveFixtures(league_ids = c("78", "79", "80"))` → integer vector of live fixture IDs, `integer(0)` when none, `NULL` on API error (callers must treat NULL as "unknown → do the full fetch"). New `update_all_leagues_loop()` parameter `full_fetch_every = 30`.

**Design:** A match can only newly reach FT if it was live at the previous poll. So: poll the live endpoint (1 request for all three leagues); do the full 3-request fetch only when (a) first iteration, (b) a previously-live fixture is no longer live (it likely finished), (c) the live poll errored, or (d) `full_fetch_every` loops have passed since the last full fetch (safety net for administratively awarded/postponed results). Steady-state cost drops from 3 requests/loop to ~1.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-update-loop-gating.R`:

```r
# The production loop must not do a full 3-league fixture fetch on every
# iteration: it polls the cheap live endpoint and fetches fully only when
# a live fixture disappeared (finished), on the first iteration, or on the
# periodic safety net.

test_that("full fetch happens only on loop 1 and when a live fixture ends", {
  # Stub network + heavy dependencies before sourcing the loop
  full_fetch_leagues <- character()
  live_poll_count <- 0
  live_sequence <- list(
    c(101L, 102L), # loop 2: two matches live -> no full fetch
    c(101L, 102L), # loop 3: unchanged        -> no full fetch
    c(102L),       # loop 4: 101 finished     -> full fetch
    integer(0)     # loop 5: 102 finished     -> full fetch
  )

  fake_fixtures <- readRDS(test_path("fixtures", "sample_fixtures.rds"))

  local_mocked_bindings(
    retrieveResults = function(league, season) {
      full_fetch_leagues <<- c(full_fetch_leagues, league)
      fake_fixtures
    },
    retrieveLiveFixtures = function(...) {
      live_poll_count <<- live_poll_count + 1
      live_sequence[[min(live_poll_count, length(live_sequence))]]
    },
    leagueSimulatorRust = function(...) matrix(1 / 18, nrow = 18, ncol = 18),
    updateShiny = function(...) invisible(NULL),
    connect_rust_simulator = function() TRUE,
    transform_data = function(...) readRDS(test_path("fixtures", "sample_transformed.rds")),
    .env = globalenv()
  )

  update_all_leagues_loop(
    duration = 0, loops = 5, initial_wait = 0, n = 10,
    saison = "2024", TeamList_file = test_path("fixtures", "sample_teamlist.csv"),
    shiny_directory = tempdir(), full_fetch_every = 30
  )

  # Full fetches: loop 1 (always), loop 4 and loop 5 (fixture left live set)
  # -> 3 full fetches x 3 leagues = 9 retrieveResults calls
  expect_length(full_fetch_leagues, 9)
  expect_equal(live_poll_count, 4) # loops 2-5
})
```

**Implementer notes for this test:** inspect `tests/testthat/fixtures/` and `helper-fixtures.R` first — reuse whatever canned fixture objects already exist for `transform_data`/loop tests instead of the `sample_*.rds` names above; adapt names/paths to what is actually there. If no suitable canned fixtures exist, build a minimal in-memory substitute: `transform_data` is mocked anyway, so `retrieveResults` can return any list with `fixture$status$short` (e.g. `list(fixture = list(status = list(short = c("FT", "NS"))))`) and the mocked `transform_data` can return a small tibble with 4+18 columns matching what `leagueSimulatorRust` (also mocked) receives. The point under test is ONLY the call-counting logic. If `local_mocked_bindings` on `globalenv()` proves unreliable for `source()`d functions, source `update_all_leagues_loop.R` into a dedicated environment and mock there.

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-update-loop-gating.R")'`
Expected: FAIL — `retrieveLiveFixtures` doesn't exist / `full_fetch_every` unknown argument / 15 full fetches instead of 9.

- [ ] **Step 3: Add `retrieveLiveFixtures` to `RCode/retrieveResults.R`**

```r
retrieveLiveFixtures <- function(league_ids = c("78", "79", "80")) {
  require(httr)
  require(jsonlite)

  RAPIDAPI_KEY <- Sys.getenv("RAPIDAPI_KEY")

  # One request covering all leagues: fixtures currently in play
  response <- VERB("GET", "https://api-football-v1.p.rapidapi.com/v3/fixtures",
    query = list(live = paste(league_ids, collapse = "-")),
    add_headers(
      "X-RapidAPI-Key" = RAPIDAPI_KEY,
      "X-RapidAPI-Host" = "api-football-v1.p.rapidapi.com"
    ),
    content_type("application/octet-stream")
  )

  if (status_code(response) != 200) {
    warning(paste("Live fixtures request failed with status:", status_code(response)))
    return(NULL) # NULL = unknown; caller must fall back to a full fetch
  }

  .record_rate_limit_headers(response)

  parsed <- fromJSON(content(response, "text", encoding = "UTF-8"))
  if (is.null(parsed$response) || length(parsed$response) == 0) {
    return(integer(0)) # nothing live right now
  }
  as.integer(parsed$response$fixture$id)
}
```

- [ ] **Step 4: Rework `RCode/update_all_leagues_loop.R`**

Signature gains `full_fetch_every = 30`. After the `FT_*` initializations add:

```r
  # Live-poll gating state: a fixture can only newly reach FT if it was live
  # at the previous poll, so a cheap 1-request live check replaces the full
  # 3-request fetch on most iterations. full_fetch_every is the safety net
  # for status changes that bypass "live" (awarded/postponed results).
  prev_live_ids <- NULL # NULL = unknown (no live poll yet)
  last_full_fetch_loop <- 0
```

Inside the `for (i in 1:loops)` loop, insert the gate between the `simulation_executed <- FALSE` line and the fixture fetching, and wrap the existing fetch/transform/simulate/deploy body in `if (need_full_fetch) { ... }`:

```r
    # Decide whether the full 3-league fetch is needed this iteration
    need_full_fetch <- TRUE
    if (i > 1) {
      live_ids <- retrieveLiveFixtures()
      if (is.null(live_ids)) {
        message(sprintf("Loop %d: live poll failed, falling back to full fetch", i))
      } else {
        finished_since_last <- !is.null(prev_live_ids) &&
          length(setdiff(prev_live_ids, live_ids)) > 0
        due_safety_fetch <- (i - last_full_fetch_loop) >= full_fetch_every
        if (!finished_since_last && !due_safety_fetch) {
          need_full_fetch <- FALSE
        }
        prev_live_ids <- live_ids
      }
    }

    if (need_full_fetch) {
      last_full_fetch_loop <- i

      # ... ENTIRE existing body: retrieveResults x3, NULL check,
      #     FT counts, transform_data x3, Liga3 penalty loop,
      #     the three simulation blocks, and the updateShiny block ...
    } else {
      message(sprintf(
        "Loop %d: %d fixture(s) live, none finished since last poll - skipping full fetch",
        i, length(prev_live_ids)
      ))
    }

    # Wait if not last iteration  (existing code, stays OUTSIDE the gate)
```

Take care: the existing `next` on API failure (line 77) stays inside the gated block and still works (it skips the wait — pre-existing behavior, leave as is).

- [ ] **Step 5: Run tests**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-update-loop-gating.R")'` → PASS.
Run: `Rscript -e 'testthat::test_file("tests/testthat/test-rust-required.R")'` → still PASS.
Run: `Rscript -e 'lintr::lint("RCode/update_all_leagues_loop.R")' ; Rscript -e 'lintr::lint("RCode/retrieveResults.R")'` → no new findings.

- [ ] **Step 6: Commit**

```bash
git add RCode/retrieveResults.R RCode/update_all_leagues_loop.R tests/testthat/test-update-loop-gating.R
git commit -m "perf: gate full fixture fetches behind 1-request live poll (API budget)"
```

---

### Task 12: Shiny app — graceful missing-data handling, stale-data banner, Liga3 consistency

**Files:**
- Create: `ShinyApp/app_helpers.R`
- Modify: `ShinyApp/app.R`
- Modify: `RCode/updateShiny.R` (deploy `app_helpers.R`)
- Test: `tests/testthat/test-shiny-app-helpers.R` (create)

**Interfaces:**
- Produces: `app_helpers.R` with `load_results(path)` → TRUE/FALSE (loads into caller-supplied env), `data_age_hours(mtime, now)` → numeric, `stale_warning_text(age_hours, threshold_hours)` → string or NULL.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-shiny-app-helpers.R`:

```r
helpers_path <- test_path("..", "..", "ShinyApp", "app_helpers.R")

test_that("load_results returns FALSE for missing or corrupt file", {
  source(helpers_path, local = TRUE)
  expect_false(load_results(file.path(tempdir(), "does_not_exist.Rds"), new.env()))
  corrupt <- tempfile(fileext = ".Rds")
  writeLines("not an rds", corrupt)
  expect_false(load_results(corrupt, new.env()))
})

test_that("load_results loads a valid results file", {
  source(helpers_path, local = TRUE)
  Ergebnis <- matrix(1 / 18, 18, 18)
  f <- tempfile(fileext = ".Rds")
  save(Ergebnis, file = f)
  env <- new.env()
  expect_true(load_results(f, env))
  expect_true(exists("Ergebnis", envir = env))
})

test_that("data_age_hours computes hours between mtime and now", {
  source(helpers_path, local = TRUE)
  now <- as.POSIXct("2026-07-02 18:00:00", tz = "Europe/Berlin")
  mtime <- as.POSIXct("2026-07-01 18:00:00", tz = "Europe/Berlin")
  expect_equal(data_age_hours(mtime, now), 24)
})

test_that("stale_warning_text triggers only past the threshold", {
  source(helpers_path, local = TRUE)
  expect_null(stale_warning_text(3, threshold_hours = 24))
  msg <- stale_warning_text(49.6, threshold_hours = 24)
  expect_match(msg, "50 Stunden")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-shiny-app-helpers.R")'`
Expected: FAIL — `app_helpers.R` does not exist.

- [ ] **Step 3: Create `ShinyApp/app_helpers.R`**

```r
# Helper functions for the Shiny app. Kept in a separate file so they are
# unit-testable; deployed alongside app.R (see updateShiny.R appFiles).

load_results <- function(path, envir) {
  tryCatch(
    {
      load(path, envir = envir)
      TRUE
    },
    error = function(e) FALSE,
    warning = function(w) FALSE
  )
}

data_age_hours <- function(mtime, now = Sys.time()) {
  as.numeric(difftime(now, mtime, units = "hours"))
}

stale_warning_text <- function(age_hours, threshold_hours = 24) {
  if (is.na(age_hours) || age_hours <= threshold_hours) {
    return(NULL)
  }
  sprintf(
    "Achtung: Diese Prognosen sind %.0f Stunden alt und werden derzeit nicht aktualisiert.",
    age_hours
  )
}
```

- [ ] **Step 4: Rework `ShinyApp/app.R`**

Replace lines 17-18 (`load(...)` / `updatetime <- ...`) with:

```r
source("app_helpers.R", local = TRUE)

data_loaded <- load_results("data/Ergebnis.Rds", environment())
updatetime <- if (data_loaded) {
  as.POSIXlt(file.mtime("data/Ergebnis.Rds"), tz = "Europe/Berlin")
} else {
  NULL
}
stale_message <- if (data_loaded) {
  stale_warning_text(data_age_hours(updatetime))
} else {
  NULL
}
```

Replace the `ui <- shinyUI(...)` block with a conditional UI (existing widgets unchanged, plus the banner):

```r
ui <- shinyUI(fluidPage(

   # Application title
   titlePanel("Fußball-Prognosen von 30Punkte"),

   if (!data_loaded) {
     mainPanel(
       h3("Noch keine Prognosedaten verfügbar"),
       p("Die Simulationsergebnisse wurden noch nicht erzeugt oder konnten",
         "nicht geladen werden. Bitte versuchen Sie es später erneut."),
       helpText("Nähere Infos unter ",
                a("30punkte.wordpress.com",
                  href = "http://30punkte.wordpress.com", target = "blank_"))
     )
   } else {
     verticalLayout(
       mainPanel(
         if (!is.null(stale_message)) {
           div(
             style = paste(
               "background-color:#f8d7da; color:#721c24;",
               "padding:10px; border-radius:4px; margin-bottom:12px;"
             ),
             stale_message
           )
         },
         selectInput(inputId = "Liga",
                     choices = c("Bundesliga", "2. Bundesliga", "Dritte Liga"),
                     label = "Welche Liga soll dargestellt werden?",
                     selected = "Bundesliga"),
         plotOutput(outputId = "Plot"),
         tableOutput(outputId = "Oben"),
         tableOutput(outputId = "Unten"),
         helpText("Alle Prognosen als Wahrscheinlichkeiten in Prozent angegeben. Nähere Infos unter ",
                  a("30punkte.wordpress.com", href = "http://30punkte.wordpress.com", target = "blank_"),
                  paste("Letztes Update: ",
                        format(updatetime, "%d.%m.%Y %H:%M"),
                        " ",
                        # isdst: >0 = DST (MESZ), 0 = standard (MEZ), <0 = unknown -> falls through to MEZ
                        if (updatetime$isdst > 0) "MESZ" else "MEZ",
                        sep = "")
         )
       )
     )
   }
))
```

In the server function, guard every render with `req(data_loaded)` as first line, e.g.:

```r
    output$Oben <- renderTable({
    req(data_loaded)
    if (input$Liga == "Bundesliga") {
```

(same for `output$Unten` and `output$Plot`).

Unify the Liga3 relegation table (line 177) with the `groupResultsDF` pattern used everywhere else:

```r
      apply (groupResultsDF (Ergebnis3[rowSums(Ergebnis3[,17:20])>=0.01,],
                             labels = c("Abstieg"),
                             groups = cbind (c(17,20))),
             c (1,2), prozent)
```

- [ ] **Step 5: Deploy the helper file — `RCode/updateShiny.R`**

```r
  deployApp(
    appFiles = c("app.R", "app_helpers.R", "data/Ergebnis.Rds"),
    appName = "FussballPrognosen", forceUpdate = forceUpdate
  )
```

- [ ] **Step 6: Run tests**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-shiny-app-helpers.R")'` → PASS.
Run: `Rscript -e 'testthat::test_file("tests/testthat/test-shiny-footer-timezone.R")'` → PASS (this test parses app.R; if it fails, adapt it to the new structure — the footer logic itself is unchanged).
Smoke-run the app headless:
`Rscript -e 'setwd("ShinyApp"); app <- shiny::shinyAppFile("app.R"); cat("APP PARSES OK\n")'` → `APP PARSES OK` (works even without data/Ergebnis.Rds — that is the point).

- [ ] **Step 7: Commit**

```bash
git add ShinyApp/app_helpers.R ShinyApp/app.R RCode/updateShiny.R tests/testthat/test-shiny-app-helpers.R
git commit -m "fix(ux): graceful Shiny fallback without data, stale-data banner, consistent Liga3 table"
```

---

### Task 13: Remove dead health_endpoints.R

**Files:**
- Delete: `ShinyApp/health_endpoints.R`
- Delete: its test (locate via `grep -rln "health_endpoints\|perform_health_check" tests/`) — expected: `tests/deployment/pre-deployment/test_health_checks.R`
- Modify: `docs/deployment/README.md` (only if it references the R health file — check with `grep -n "health_endpoints" docs/deployment/README.md`)

Rationale: verified dead code — never sourced by app.R, scheduler, or Docker entrypoint; the real health endpoint is the Rust server's `/health`. Its only useful idea (stale-data detection) is now live in the app via Task 12.

- [ ] **Step 1: Verify deadness once more**

Run: `grep -rn "health_endpoints" --include="*.R" --include="*.sh" --include="Dockerfile*" . | grep -v tests/ | grep -v "^Binary"`
Expected: only `ShinyApp/health_endpoints.R` itself. If ANY production reference appears, STOP and report instead of deleting.

- [ ] **Step 2: Delete**

```bash
git rm ShinyApp/health_endpoints.R
git rm tests/deployment/pre-deployment/test_health_checks.R   # adjust path per grep
```

If `docs/deployment/README.md` mentions the file, remove/replace that mention (the Rust `/health` docs stay).

- [ ] **Step 3: Verify nothing breaks**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-shiny-app-helpers.R")'` → PASS.
Run: `grep -rn "health_endpoints" . --exclude-dir=.git || echo CLEAN` → `CLEAN` (this plan file excepted).

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: remove dead ShinyApp health_endpoints.R (superseded by Rust /health + in-app stale banner)"
```

---

### Task 14: Fix season-transition docs and argument-error echo

**Files:**
- Modify: `docs/user-guide/season-transition.md`
- Modify: `scripts/season_transition.R` (arg-error message + usage output)

- [ ] **Step 1: Doc fixes in `docs/user-guide/season-transition.md`** (verified against the actual code):

1. **Container name** — replace every `docker-compose exec` target `league-simulator` with `league-simulator-integrated` (lines 38, 55, 87, 97, 136→deleted below, 147, 161, 241→deleted below, 368, 373, 382). Global check afterwards: `grep -n "exec.*league-simulator \\\\" docs/user-guide/season-transition.md` → no hits.
2. **Line 104** — `./scripts/backup_season.sh 2024` does not exist. Replace with:
   ```bash
   # Backup current data
   tar -czf "backup_season_2024_$(date +%Y%m%d).tar.gz" RCode/TeamList_2024.csv
   ```
3. **Lines 134-141** (`search_team(...)` block) — the function does not exist. Replace the whole code block with:
   ```markdown
   Team IDs can be looked up in the API-Football dashboard
   (<https://dashboard.api-football.com>) or via the `/teams?search=<name>`
   endpoint documented at <https://www.api-football.com/documentation-v3>.
   ```
4. **Lines 239-246** (`get_final_standings` block) — the file does not exist. Replace the code block with:
   ```markdown
   Verify the final standings against an official source (e.g. kicker.de or
   the API-Football dashboard) before re-running the transition with a
   corrected configuration file.
   ```
5. **Automation Script section (lines 347-401)** — fix the two `league-simulator` exec targets to `league-simulator-integrated`, and DELETE step 4 ("Test simulation", lines 380-394) entirely — it sources `RCode/leagueSimulatorCPP.R`, which was removed with the Rust migration. Renumber step 5 → 4.
6. **Debug section (lines 405-415)** — check `grep -rn "SEASON_TRANSITION_DEBUG" scripts/ RCode/`. If the variable is not referenced anywhere, delete the "Debug Mode" subsection.
7. **Related Documentation links (lines 465-470)** — verify each target exists (`ls docs/user-guide/team-management.md docs/operations/backup-recovery.md docs/troubleshooting/common-issues.md`). Remove list entries whose files don't exist.

- [ ] **Step 2: Argument echo in `scripts/season_transition.R`**

Replace (in `parse_arguments`):

```r
  if (length(season_args) != 2) {
    return(list(valid = FALSE, error = "Two season arguments required"))
  }
```

with:

```r
  if (length(season_args) != 2) {
    received <- if (length(season_args) == 0) {
      "none"
    } else {
      paste(shQuote(season_args), collapse = ", ")
    }
    return(list(valid = FALSE, error = sprintf(
      "Two season arguments required, got %d (%s)",
      length(season_args), received
    )))
  }
```

And in `main()`, print the specific error before the usage block:

```r
  if (!parsed_args$valid) {
    cat("Error:", parsed_args$error, "\n\n")
    cat("Usage: Rscript season_transition.R <source_season> <target_season> [options]\n")
```

- [ ] **Step 3: Verify**

Run: `Rscript scripts/season_transition.R 2024 2025 2026 --non-interactive 2>&1 | head -5`
Expected: first line contains `got 3 ('2024', '2025', '2026')`.
Run: `Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-validators.R")'` → PASS.

- [ ] **Step 4: Commit**

```bash
git add docs/user-guide/season-transition.md scripts/season_transition.R
git commit -m "docs: align season-transition guide with actual code; echo bad CLI args"
```

---

### Task 15: Final verification and PR

- [ ] **Step 1: Full local test sweep**

```bash
cd league-simulator-rust && cargo test && cargo fmt --check && cargo clippy -- -D warnings && cd ..
Rscript -e 'options(testthat.progress.max_fails = Inf); testthat::test_dir("tests/testthat", stop_on_failure = TRUE, reporter = "summary")'
```

Expected: Rust all green; R suite green (some tests may skip without RAPIDAPI_KEY — same as CI). If R packages are missing locally, fall back to per-file runs of every test file touched in this plan and note that CI runs the full suite in-image.

- [ ] **Step 2: Push and open PR**

```bash
git push -u origin fix/codebase-review-2026-07
gh pr create --title "Implement codebase review findings (security, efficiency, usability)" --body "$(cat <<'EOF'
## Summary
Implements all actionable findings from the 2026-07-02 codebase review.

**Security**
- Remove hardcoded ShinyApps.io token (env-only + hard fail); drop compose fallback default — token must be rotated, see deployment note below
- Validate Rust simulation requests (team indices, iterations cap 100k, adjustment lengths) — fixes one-request remote DoS via integer underflow + panic=abort
- Bind Rust API host port to 127.0.0.1; drop permissive CORS; 2 MB body limit
- Non-root container user; stop logging RAPIDAPI_KEY prefix; pin GitHub Actions to SHAs

**Efficiency**
- Gate full fixture fetches behind a 1-request live poll (~3x fewer API calls)
- Direct Poisson quantile for small lambda (hot path); lock-free rayon fold/reduce aggregation; per-thread buffer reuse
- Dockerfile: cached Rust dependency layer + slim runtime stage without build toolchain
- Vectorized transform_data and Tabelle_presentation; cached rate-limit headers

**Usability**
- Shiny app: friendly fallback when no data, stale-data banner (>24h), consistent Liga3 table
- season-transition guide aligned with actual code (container name, removed references to non-existent scripts)
- Removed dead ShinyApp/health_endpoints.R; season_transition.R echoes bad CLI args

## Deployment note (breaking)
`SHINYAPPS_IO_TOKEN` must now be set in `.env` — the compose fallback default is gone. Rotate the exposed token at shinyapps.io before deploying.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Watch CI** (`gh pr checks --watch`) and fix anything red.
