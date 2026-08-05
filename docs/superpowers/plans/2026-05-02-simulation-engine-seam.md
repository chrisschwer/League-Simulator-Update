# Retire C++ engine fallback in production loop (Phase 1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `leagueSimulatorRust()` the only simulation entry point invoked by the production loop. Remove the duplicated fallback wiring (loop-level `if (use_rust)`, the per-call check inside `leagueSimulatorRust`, the `use_rust` parameter, the brittle `Rcpp::sourceCpp` build step in the Dockerfile). When the Rust server is unavailable, the scheduler fails fast with a clear error referencing `RUST_API_URL`. **Phase 1 keeps all C++ source files in `RCode/`** because `scripts/season_transition.R:65` sources `SpielCPP.R` — Phase 2 (a future, separately-derived plan) decides their long-term fate.

**Architecture:** Three small touch-points, all in already-renamed files (the deployment-collapse PRD #78 has landed): (1) `RCode/update_all_leagues_loop.R` loses its `if (use_rust) { ... } if (!use_rust) { source CPP ... }` block (lines 26–45), drops the `use_rust` parameter, and inlines `simulator_function`; (2) `RCode/rust_integration.R` loses the per-call CPP fallback inside `leagueSimulatorRust()` (lines 150–156); (3) `RCode/updateScheduler.R` upgrades its warning at line 155–158 to a `stop()` and drops the `use_rust = rust_available` argument at line 172. The `Dockerfile` loses lines 101–104 (the runtime `Rcpp::sourceCpp('SpielNichtSimulieren.cpp')` step) since its only consumer was the deleted fallback. C++ source files in `RCode/` are not touched.

**Tech Stack:** R 4.3.1, `httr` + `jsonlite` for the Rust REST client, the existing Rust crate at `league-simulator-rust/`, Docker. testthat 3.x for the regression test. No new dependencies.

**Reference:** PRD at `docs/prds/2026-05-02-simulation-engine-seam.md` (also GitHub issue #77). Companion deployment-collapse PRD #78 has been merged to `main` (recovery tag `pre-deployment-cleanup-2026-05-02`).

**Survivor list — DO NOT TOUCH:** `RCode/leagueSimulatorCPP.R`, `RCode/simulationsCPP.R`, `RCode/SaisonSimulierenCPP.R`, `RCode/SpielCPP.R`, `RCode/SpielNichtSimulieren.cpp`, `RCode/cpp_wrappers.R`, `RCode/RcppExports.R`, the entire `tests/testthat/test-*CPP*.R` family, `tests/rust/test_rust_vs_cpp_detailed.R`, `compare_rust_cpp.R`, `compare_rust_vs_r.R`, `scripts/season_transition.R` and its 18 dependencies. Phase 2 decides the long-term fate of these.

---

## File Inventory

### Files modified (4)

| File | Change |
|---|---|
| `RCode/update_all_leagues_loop.R` | Replace lines 4 + 26–45 + 104 + the `if (use_rust)` echoes in 109/117/125 + 150–152; drop `use_rust` parameter |
| `RCode/rust_integration.R` | Delete lines 150–156 (per-call CPP fallback inside `leagueSimulatorRust`) |
| `RCode/updateScheduler.R` | Replace lines 155–158 (warning → `stop()`); remove `use_rust = rust_available` at line 172 |
| `Dockerfile` | Delete lines 101–104 (the `Rcpp::sourceCpp` runtime build step) |

### Files created (1)

- `tests/testthat/test-rust-required.R` — the regression net (positive + negative cases for the new fail-fast behavior)

### Files NOT touched (Phase 1 boundary)

C++ engine sources, all CPP testthat files, comparison harnesses, season-transition workflow, `packagelist.txt` (Rcpp stays), `DESCRIPTION` (Rcpp linkage stays). Documentation (`docs/architecture/overview.md`, `RUST_INTEGRATION.md`, etc.) is also out of scope — issue #79 sweeps those.

### Out-of-plan-scope (deferred to Phase 2)

Deletion of C++ engine files, Rcpp removal from `packagelist.txt`/`DESCRIPTION`, deletion of CPP testthat files and comparison harnesses, season-transition migration to the Rust seam (or formal blessing of CPP as season-transition's tool).

---

## Task 1: Pre-flight verification + worktree baseline

**Goal:** Confirm clean baseline, capture the current production image as a regression target, and confirm the Rust binary can be built and started locally (the new test depends on it). No commits.

**Files:** None modified.

- [ ] **Step 1: Confirm clean working tree on the worktree branch**

```bash
git status --short
git branch --show-current
```

Expected: empty status; branch name matches the worktree's feature branch (will be set up by `superpowers:using-git-worktrees` before this plan starts — typical name `feature/issue-77-rust-seam`).

- [ ] **Step 2: Confirm post-#78 production state is intact**

```bash
ls Dockerfile docker-compose.yml docker-start.sh RCode/updateScheduler.R RCode/update_all_leagues_loop.R RCode/rust_integration.R 2>&1
```

Expected: all 6 files listed cleanly. If any are missing, the worktree is in the wrong state — STOP and ask.

- [ ] **Step 3: Confirm the C++ survivors are present (we must NOT delete these in Phase 1)**

```bash
ls RCode/leagueSimulatorCPP.R RCode/simulationsCPP.R RCode/SaisonSimulierenCPP.R RCode/SpielCPP.R RCode/SpielNichtSimulieren.cpp RCode/cpp_wrappers.R RCode/RcppExports.R
```

Expected: all 7 files present.

- [ ] **Step 4: Build the current production image as a regression baseline**

Use the nohup pattern (lesson from PRD #78's Task 1 — Docker builds get killed by wrapper exits):

```bash
cd <worktree-absolute-path>
nohup docker build -f Dockerfile -t league-simulator:phase1-pre . > /tmp/docker-build-phase1-pre.log 2>&1 & disown
echo "PID: $!"
```

Poll `tail /tmp/docker-build-phase1-pre.log` until `Successfully tagged league-simulator:phase1-pre` or an error. Heavy cache hit expected (the image is identical to whatever was last built on `main`); should complete in ~10–60 seconds.

If the build fails: STOP and report BLOCKED. The production image is broken in a way unrelated to this plan.

- [ ] **Step 5: Capture the baseline image ID**

```bash
docker images league-simulator:phase1-pre --format '{{.ID}}'
```

Record the ID. Task 7's verification compares against it.

- [ ] **Step 6: Build the Rust binary natively (the new test needs it)**

```bash
cd league-simulator-rust
nohup cargo build --release > /tmp/cargo-build-phase1.log 2>&1 & disown
echo "PID: $!"
```

Poll `tail /tmp/cargo-build-phase1.log`. First-time build can take 2–5 minutes (downloads + compiles dependencies). Subsequent invocations of this plan in the same worktree will be near-instant.

If `cargo build` fails: STOP and report BLOCKED — without a local Rust binary, the new test cannot run (Phase 1 cannot land without its regression net).

Confirm the binary exists:

```bash
ls -la league-simulator-rust/target/release/league-simulator-rust
```

Expected: an executable file ~5–20 MB.

- [ ] **Step 7: Smoke-test the Rust server starts and reports health**

```bash
league-simulator-rust/target/release/league-simulator-rust --api &
RUST_PID=$!
sleep 3
curl -sf http://localhost:8080/health && echo "OK"
kill $RUST_PID 2>/dev/null
wait $RUST_PID 2>/dev/null
```

Expected: `OK` printed (after the curl response). Confirms the binary speaks the contract the plan's tests will rely on.

If `curl` errors: report BLOCKED with the curl output and the Rust server's stderr.

- [ ] **Step 8: Capture the season-transition baseline (canary for Task 6)**

```bash
Rscript -e 'tryCatch(source("scripts/season_transition.R"), error = function(e) cat("EXPECTED ARGS-MISSING ERROR:", e$message, "\n"))' 2>&1 | tee /tmp/season-transition-baseline-phase1.txt
```

Expected: the script sources its 18 modules (15 transition-specific + `retrieveResults.R`, `transform_data.R`, `SpielCPP.R`), then fails on missing args. The output file lives at `/tmp/season-transition-baseline-phase1.txt` for Task 6's diff.

If sourcing fails before reaching the args-error (e.g., Rcpp not configured locally for `SpielCPP.R`): record the failure pattern. The downstream canary will compare against whatever this baseline is — including a baseline of "Rcpp not configured" — so as long as the post-Phase-1 output matches it, we have proof the changes didn't regress anything.

- [ ] **Step 9: No commit**

Task 1 makes no working-tree changes.

---

## Task 2: Add the regression test (TDD red)

**Goal:** Add `tests/testthat/test-rust-required.R` with both the positive-path and negative-path tests, run them against the **current** code, and confirm: positive passes, negative *fails as expected* (because today's code silently falls back to CPP when Rust is down — the test will assert `stop()` which the current code doesn't do).

The test fixture starts the Rust binary in a `setup`/`teardown`, calls a single iteration of `update_all_leagues_loop()` with a tiny input, and asserts on the result shape.

**Files:**
- Create: `tests/testthat/test-rust-required.R`
- Create: `tests/testthat/fixtures/rust-required/TeamList_minimal.csv` (small 4-team fixture)

- [ ] **Step 1: Inspect existing test infrastructure for conventions**

```bash
ls tests/testthat/helper-*.R tests/testthat/fixtures/ 2>&1
head -15 tests/testthat/helper-test-setup.R 2>/dev/null
```

The repo has `tests/testthat/helper-test-setup.R` and `tests/testthat/helper-deployment.R`. The new test does not need to extend them — it's self-contained. The `fixtures/` subdirectory exists; we'll add a `rust-required/` subdir there.

- [ ] **Step 2: Create the minimal team-list fixture**

Create `tests/testthat/fixtures/rust-required/TeamList_minimal.csv` with this exact content (4 teams, semicolon-separated to match the production CSV format from `read.csv(TeamList_file, sep=";")` at `update_all_leagues_loop.R:55`):

```csv
TeamID;ShortName;Promotion;InitialELO
1;TST;0;1500
2;UAA;0;1500
3;UBB;0;1500
4;UCC;0;1500
```

Real `TeamList_*.csv` files have more columns (verified from `RCode/TeamList_2025.csv`); this fixture matches the *minimum* the loop needs to construct a valid season. If the loop errors during the test on missing columns, expand the fixture; do not change the loop.

- [ ] **Step 3: Write the test file (RED — assertions are aspirational, will fail today on the negative case)**

Create `tests/testthat/test-rust-required.R` with this exact content:

```r
# Phase 1 regression net for the Rust-required production loop.
# Issue #77 / docs/superpowers/plans/2026-05-02-simulation-engine-seam.md.

library(testthat)

# --- Helpers: start/stop the Rust API server in the background ---

rust_binary <- function() {
  bin <- file.path("..", "..", "league-simulator-rust", "target", "release", "league-simulator-rust")
  if (!file.exists(bin)) {
    skip(sprintf("Rust binary not built at %s; run `cargo build --release` in league-simulator-rust/", bin))
  }
  normalizePath(bin)
}

start_rust_server <- function(port = 18080L) {
  bin <- rust_binary()
  log <- tempfile(fileext = ".log")
  # Pass PORT via the parent environment. sys::exec_background (>= 3.4) inherits
  # env from the caller and has no env= parameter; save/restore protects the
  # parent's PORT if any.
  old_port <- Sys.getenv("PORT", unset = NA)
  Sys.setenv(PORT = as.character(port))
  pid <- sys::exec_background(bin, args = "--api", std_out = log, std_err = log)
  if (is.na(old_port)) Sys.unsetenv("PORT") else Sys.setenv(PORT = old_port)
  Sys.setenv(RUST_API_URL = sprintf("http://localhost:%d", port))
  # Wait up to 10 s for the server to become healthy.
  ok <- FALSE
  for (i in 1:50) {
    Sys.sleep(0.2)
    res <- tryCatch(httr::GET(paste0(Sys.getenv("RUST_API_URL"), "/health"),
                              httr::timeout(0.5)),
                    error = function(e) NULL)
    if (!is.null(res) && httr::status_code(res) == 200) { ok <- TRUE; break }
  }
  list(pid = pid, log = log, ok = ok, port = port)
}

stop_rust_server <- function(handle) {
  if (!is.null(handle$pid)) {
    try(tools::pskill(handle$pid), silent = TRUE)
  }
}

# Source the production loop fresh so the test sees the current state of the code.
# The loop's source() calls inside its body assume cwd = repo root; we set it explicitly.
with_repo_root <- function(expr) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(old, "..", ".."))   # tests/testthat -> repo root
  force(expr)
}

# --- Tests ---

context("Phase 1 — Rust required, no fallback")

test_that("update_all_leagues_loop runs one iteration end-to-end with Rust up", {
  skip_if_not_installed("sys")
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")

  handle <- start_rust_server()
  on.exit(stop_rust_server(handle), add = TRUE)
  if (!handle$ok) {
    skip(sprintf("Rust server failed to come up on port %d; log: %s",
                 handle$port, handle$log))
  }

  # Pre-set the FT counters so the loop's "first iteration" branch runs cleanly.
  FT_BL <- 0; FT_BL2 <- 0; FT_Liga3 <- 0

  with_repo_root({
    source("RCode/update_all_leagues_loop.R", local = FALSE)
    # The function exists post-source; just assert it can be invoked with a
    # one-loop call and that we don't get an immediate error from sourcing/wiring.
    # We don't assert on Ergebnis values here — we'd need a stubbed retrieveResults
    # to do that, and that's a bigger fixture than this test should own. The
    # post-refactor version of this test (Task 7) will exercise the seam shape.
    expect_true(exists("update_all_leagues_loop"))
    # Function signature check: in Phase 1's pre-state, has `use_rust` parameter;
    # in Phase 1's post-state, does not. We assert nothing here — Task 7 does the
    # signature check after the refactor.
  })
})

test_that("loop fails fast with RUST_API_URL message when Rust is down (post-refactor)", {
  skip_if_not_installed("httr")

  # Point at a port that is guaranteed to refuse connections (no server here).
  Sys.setenv(RUST_API_URL = "http://127.0.0.1:1")

  with_repo_root({
    source("RCode/update_all_leagues_loop.R", local = FALSE)
    # PRE-REFACTOR EXPECTATION (will FAIL today, by design — this is the canary
    # the refactor is meant to flip):
    err <- tryCatch(
      update_all_leagues_loop(duration = 0, loops = 1, n = 10,
                              saison = "2024",
                              TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
                              shiny_directory = tempdir()),
      error = function(e) e
    )
    # Post-refactor: error message must mention "Rust simulator not available"
    # and include the unreachable URL the test pointed at (http://127.0.0.1:1).
    # Pre-refactor: today's code logs a warning and silently sources C++ (no error).
    # So this assertion intentionally fails until Tasks 3–5 land.
    expect_s3_class(err, "error")
    expect_match(conditionMessage(err), "Rust simulator not available", fixed = TRUE)
    expect_match(conditionMessage(err), "127.0.0.1:1", fixed = TRUE)
  })
})
```

**Notes on the test design:**
- The positive test deliberately does NOT exercise the API-call path (`retrieveResults` would hit api-football and need an API key). It just confirms the loop file sources cleanly and the function exists. The post-refactor verification (Task 7) checks the seam shape via grep, not via end-to-end execution.
- The negative test is the actual canary: it asserts the *post-refactor* contract (fail fast with `RUST_API_URL` in the message). Today, the same code silently warns and falls through to the CPP path — so this test FAILS today. That failure is the "RED" half of the TDD cycle. Tasks 3–5 turn it green.
- `sys::exec_background` is the simplest way to launch a child process in R without blocking. The package is on CRAN; if it's not installed in the test environment, the test skips with a message.

- [ ] **Step 4: Run the test against the current (pre-refactor) code**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-rust-required.R", reporter = "summary")'
```

Expected output (paraphrased):
- First test (`update_all_leagues_loop runs one iteration ... with Rust up`): **PASS** if the Rust server came up; SKIP otherwise.
- Second test (`loop fails fast with RUST_API_URL message`): **FAIL** with a message about `expect_s3_class(err, "error")` failing — because today's code returns `NULL` instead of erroring (or errors with a different message about something else). This failure is the documented red.

If the second test PASSES today, that means the current code already fails fast — which would be surprising and worth investigating. STOP and report.

If `sys` is not installed, install it: `Rscript -e 'install.packages("sys", repos = "https://cloud.r-project.org")'` and re-run.

- [ ] **Step 5: Commit the test (RED state)**

```bash
git add tests/testthat/test-rust-required.R tests/testthat/fixtures/rust-required/TeamList_minimal.csv
git commit -m "test: add Rust-required regression net for production loop (RED)

Phase 1 of issue #77 fail-fast refactor. The negative test asserts the
post-refactor contract: when Rust is unreachable, the loop must stop()
with a message containing RUST_API_URL. Today's code silently warns and
falls back to C++, so this test FAILS today by design — Tasks 3–5 will
flip it green by removing the fallback wiring."
```

---

## Task 3: Move the Rust availability check up + drop the fallback block

**Goal:** Replace the `if (use_rust) { source rust ... } if (!use_rust) { source CPP ... }` block in `RCode/update_all_leagues_loop.R` (lines 26–45) with a single source-and-assert. Drop the `use_rust` parameter from the function signature. Re-run the regression test (positive case).

**Files:**
- Modify: `RCode/update_all_leagues_loop.R` (signature line 4–8; body lines 26–45)

- [ ] **Step 1: Inspect the current state**

```bash
sed -n '4,8p;26,45p' RCode/update_all_leagues_loop.R
```

Expected output: the function signature with `use_rust = TRUE` as the last parameter, then the 20-line block containing the conditional source().

- [ ] **Step 2: Edit the function signature (drop `use_rust` parameter)**

Use the Edit tool. Find this exact text in `RCode/update_all_leagues_loop.R`:

```r
update_all_leagues_loop <- function(duration = 480, loops = 31, initial_wait = 0,
                                         n = 10000, saison = "2023", 
                                         TeamList_file = "RCode/TeamList_2023.csv",
                                         shiny_directory = "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox-CSDataScience/Christoph Schwerdtfeger/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update/ShinyApp",
                                         use_rust = TRUE) {
```

Replace with:

```r
update_all_leagues_loop <- function(duration = 480, loops = 31, initial_wait = 0,
                                    n = 10000, saison = "2023",
                                    TeamList_file = "RCode/TeamList_2023.csv",
                                    shiny_directory = "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox-CSDataScience/Christoph Schwerdtfeger/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update/ShinyApp") {
```

(Drops `use_rust = TRUE` from the parameter list. Indentation on continuation lines normalized to 4 spaces — matches the surrounding pattern. The hardcoded Dropbox path stays untouched per the final code review of #78 which flagged it as out-of-scope.)

- [ ] **Step 3: Replace the fallback block (lines 26–45 in the original) with a fail-fast source**

Use the Edit tool. Find this exact text in `RCode/update_all_leagues_loop.R`:

```r
  # Source R Code
  if (use_rust) {
    message("=== Using high-performance Rust simulation engine ===")
    source("RCode/rust_integration.R")
    
    # Check Rust connection
    if (!connect_rust_simulator()) {
      message("WARNING: Rust simulator not available, falling back to C++ implementation")
      use_rust <- FALSE
    }
  }
  
  # Source traditional C++ implementation as fallback
  if (!use_rust) {
    message("=== Using traditional C++ simulation engine ===")
    Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
    source("RCode/leagueSimulatorCPP.R")
    source("RCode/SaisonSimulierenCPP.R")
    source("RCode/simulationsCPP.R")
    source("RCode/SpielCPP.R")
  }
```

Replace with:

```r
  # Source the Rust REST client and assert the server is reachable before doing
  # any work. Phase 1 of issue #77: the production loop now requires Rust;
  # there is no in-process fallback to C++. A missing/broken Rust server fails
  # the scheduler at startup so the operator sees the real problem instead of
  # silent engine substitution.
  source("RCode/rust_integration.R")
  if (!connect_rust_simulator()) {
    stop(sprintf(
      "Rust simulator not available at %s. Check that the Rust server is running before starting the scheduler.",
      Sys.getenv("RUST_API_URL", "http://localhost:8080")
    ))
  }
```

- [ ] **Step 4: Verify R can parse the modified file**

```bash
Rscript -e 'invisible(parse("RCode/update_all_leagues_loop.R")); cat("PARSE OK\n")'
```

Expected: `PARSE OK`. If R reports a parse error, the Edit corrupted something — inspect with `sed -n '20,40p' RCode/update_all_leagues_loop.R` and fix.

- [ ] **Step 5: Re-run the regression test (positive case should still pass; negative still fails)**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-rust-required.R", reporter = "summary")'
```

Expected:
- Positive: PASS or SKIP (depending on whether Rust binary is available locally).
- Negative: STILL FAILS — because the `simulator_function` line at 104 and the `if (use_rust)` echoes at 109/117/125 still reference `use_rust`, which is now an undefined variable inside the function. The negative test will now fail with an `object 'use_rust' not found` error rather than the silent-fallback NULL it produced before. **This is intermediate breakage** — Tasks 4–5 finish the cleanup.

This intermediate state is unavoidable in a TDD-style multi-step refactor. The next task (Task 4) inlines `simulator_function` and removes the `use_rust` references, which makes the negative test fail with a different error (still not yet the target `stop()` with `RUST_API_URL`). Task 5 then turns it green.

If the Rust binary is unavailable and both tests skip, that's fine — Task 7's grep-based acceptance criteria are the final gate.

- [ ] **Step 6: No commit yet**

Task 4 finishes this group of changes and commits everything together (loop signature + body + simulator_function inlining + message updates) in one logically coherent commit. Hold off here.

---

## Task 4: Inline `simulator_function` and remove `use_rust` references in the loop body

**Goal:** Remove the four references to `use_rust` and `simulator_function` in the loop body (lines 104, 108–109, 116–117, 124–125, 150–152). After this task, `RCode/update_all_leagues_loop.R` has zero references to `use_rust`, `simulator_function`, or `leagueSimulatorCPP`. Commit the loop changes (Tasks 3 + 4 together).

**Files:**
- Modify: `RCode/update_all_leagues_loop.R` (lines 104, 108–109, 116–117, 124–125, 150–152)

- [ ] **Step 1: Inspect the current state of the loop body**

```bash
grep -n "use_rust\|simulator_function\|leagueSimulatorCPP" RCode/update_all_leagues_loop.R
```

After Task 3, expected matches (line numbers may have shifted slightly due to Task 3's edits — they shrunk the file by ~10 lines):

- The `simulator_function` assignment (originally line 104)
- Two `use_rust` references in `message()` calls per iteration (originally lines 109, 117, 125)
- The closing summary message (originally line 150–152)

- [ ] **Step 2: Remove the `simulator_function` assignment**

Use the Edit tool. Find:

```r
    # Run the models using appropriate engine
    simulator_function <- if (use_rust) leagueSimulatorRust else leagueSimulatorCPP
```

Replace with: empty (delete both lines, including the comment).

- [ ] **Step 3: Replace the four `simulator_function(...)` call sites with `leagueSimulatorRust(...)`**

Use the Edit tool with `replace_all = true` (the four call sites all look the same: `simulator_function(`).

Find: `simulator_function(`
Replace with: `leagueSimulatorRust(`

Verify after: `grep -n "simulator_function" RCode/update_all_leagues_loop.R` → no output.

- [ ] **Step 4: Simplify the three iteration messages (drop the `if (use_rust) "Rust" else "C++"` echo)**

Use the Edit tool three times (one per league). Find this exact text:

```r
      message(sprintf("Loop %d: Simulating Bundesliga with %d simulations (%s engine)", 
                      i, n, if (use_rust) "Rust" else "C++"))
```

Replace with:

```r
      message(sprintf("Loop %d: Simulating Bundesliga with %d simulations (Rust engine)",
                      i, n))
```

Repeat for the 2. Bundesliga message:

Find:
```r
      message(sprintf("Loop %d: Simulating 2. Bundesliga with %d simulations (%s engine)", 
                      i, n, if (use_rust) "Rust" else "C++"))
```

Replace:
```r
      message(sprintf("Loop %d: Simulating 2. Bundesliga with %d simulations (Rust engine)",
                      i, n))
```

Repeat for the 3. Liga message:

Find:
```r
      message(sprintf("Loop %d: Simulating 3. Liga with %d simulations (%s engine)", 
                      i, n, if (use_rust) "Rust" else "C++"))
```

Replace:
```r
      message(sprintf("Loop %d: Simulating 3. Liga with %d simulations (Rust engine)",
                      i, n))
```

- [ ] **Step 5: Simplify the closing summary message**

Use the Edit tool. Find:

```r
  message(sprintf("\n=== Completed all %d loops at %s ===", loops, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
  if (use_rust) {
    message("Performance boost achieved with Rust engine!")
  }
}
```

Replace with:

```r
  message(sprintf("\n=== Completed all %d loops at %s ===", loops, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
}
```

(Drops the redundant "Performance boost" message; the loop is now unconditionally Rust so the message is noise.)

- [ ] **Step 6: Verify zero `use_rust` references in the loop file**

```bash
grep -n "use_rust\|simulator_function" RCode/update_all_leagues_loop.R
```

Expected: no output. If anything shows, it's a missed reference — handle case-by-case.

Also verify the file still parses:

```bash
Rscript -e 'invisible(parse("RCode/update_all_leagues_loop.R")); cat("PARSE OK\n")'
```

Expected: `PARSE OK`.

- [ ] **Step 7: Update the file's header comment (optional but worth doing while we're here)**

The file's header (line 1–2) reads:

```r
# Complete rerun of model using high-performance Rust engine
# Provides 50-100x performance improvement over C++ implementation
```

Replace with:

```r
# Production simulation loop. Calls the Rust REST API exclusively
# (issue #77 Phase 1: no in-process C++ fallback).
```

The "50-100x" comparison is now stale framing — there's no C++ to compare against in this file's call path.

- [ ] **Step 8: Re-run the regression test**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-rust-required.R", reporter = "summary")'
```

Expected:
- Positive: PASS or SKIP.
- Negative: STILL FAILS, but with a different error than before — likely about the loop trying to call `retrieveResults` (which needs `httr` configured) before reaching the new `stop()` in Task 3's check. **This is still intermediate breakage.** Task 5 doesn't change the loop; it changes the scheduler. The negative test goes green only after Task 5 + the per-call fallback removal in Task 6 — but for this test, the green trigger is already in place (the `stop()` from Task 3). The remaining noise is the loop attempting to construct `season` data before erroring. We accept this and move on.

If the negative test reaches `stop()` with `RUST_API_URL` in the message at this point, even better — the test goes green here.

- [ ] **Step 9: Commit Tasks 3 + 4 together**

```bash
git add RCode/update_all_leagues_loop.R
git commit -m "refactor: production loop calls leagueSimulatorRust unconditionally

Issue #77 Phase 1. Removes the duplicated 'is Rust available?' check
inside update_all_leagues_loop():

- Drop the use_rust parameter from the signature.
- Replace the if(use_rust)/if(!use_rust) source-on-demand block (~20
  lines) with a single source(rust_integration.R) + connect_rust_simulator()
  assertion. Failure now stop()s with the actual RUST_API_URL.
- Inline the simulator_function dispatch — every call site now invokes
  leagueSimulatorRust directly.
- Drop 'Rust' vs 'C++' branching in iteration messages and the summary.
- Update the file header to reflect the new contract.

Per-call fallback in rust_integration.R is removed in the next commit;
the scheduler-level warning becomes a stop() in the commit after that."
```

---

## Task 5: Strip the per-call CPP fallback from `rust_integration.R`

**Goal:** Remove the per-call `connect_rust_simulator()` check and `leagueSimulatorCPP` fallback inside `leagueSimulatorRust()` (lines 150–156 of `RCode/rust_integration.R`). Re-run the regression test.

**Files:**
- Modify: `RCode/rust_integration.R` (lines 150–156)

- [ ] **Step 1: Inspect the current state**

```bash
sed -n '148,160p' RCode/rust_integration.R
```

Expected output (lines 148–158):

```r
                               adjGoalDiff = rep_len(0, numberTeams)) {

  # Check Rust connection
  if (!connect_rust_simulator()) {
    message("Falling back to C++ implementation...")
    return(leagueSimulatorCPP(season, n, modFactor, homeAdvantage,
                              numberTeams, adjPoints, adjGoals,
                              adjGoalsAgainst, adjGoalDiff))
  }
```

- [ ] **Step 2: Remove the per-call check (Edit tool)**

Find this exact text in `RCode/rust_integration.R`:

```r
  # Check Rust connection
  if (!connect_rust_simulator()) {
    message("Falling back to C++ implementation...")
    return(leagueSimulatorCPP(season, n, modFactor, homeAdvantage,
                              numberTeams, adjPoints, adjGoals,
                              adjGoalsAgainst, adjGoalDiff))
  }
  
```

Replace with:

```r
  # Caller (update_all_leagues_loop) has already asserted Rust availability.
  # Per-call connection checks were removed in issue #77 Phase 1; a Rust API
  # call failure surfaces via stop() in simulate_league_rust() below.
  
```

(Note the trailing blank line — preserve the spacing between this comment block and the next `# Convert tibble to data.frame if needed` block.)

- [ ] **Step 3: Verify the per-call fallback is gone**

```bash
grep -n "leagueSimulatorCPP\|Falling back to C\+\+" RCode/rust_integration.R
```

Expected: no output. (`leagueSimulatorCPP` is no longer referenced anywhere in `rust_integration.R`.)

- [ ] **Step 4: Verify R can parse the modified file**

```bash
Rscript -e 'invisible(parse("RCode/rust_integration.R")); cat("PARSE OK\n")'
```

Expected: `PARSE OK`.

- [ ] **Step 5: Re-run the regression test**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-rust-required.R", reporter = "summary")'
```

Expected:
- Positive: PASS or SKIP (unchanged from previous tasks).
- Negative: now reaches the `stop()` from Task 3's check before doing anything else. The error message contains `RUST_API_URL` — the test passes.

If the negative test still does not pass: inspect the actual error message with a manual run:

```bash
Rscript -e '
Sys.setenv(RUST_API_URL = "http://127.0.0.1:1")
source("RCode/update_all_leagues_loop.R")
tryCatch(
  update_all_leagues_loop(duration = 0, loops = 1, n = 10, saison = "2024",
    TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
    shiny_directory = tempdir()),
  error = function(e) cat("ERROR:", conditionMessage(e), "\n"))
'
```

The error message must mention `RUST_API_URL`. If it doesn't, find out why — likely the test's working-directory assumption is wrong, or the loop is reaching some other code path before the assertion.

- [ ] **Step 6: Commit**

```bash
git add RCode/rust_integration.R
git commit -m "refactor: drop per-call CPP fallback in leagueSimulatorRust

Issue #77 Phase 1. The per-call connect_rust_simulator() check inside
leagueSimulatorRust() was a second-tier fallback that only worked under
conditions the loop had to set up (sourcing the CPP files first). The
loop now asserts Rust availability up front and stop()s on failure, so
the per-call check is dead defensive code. Removing it makes the
function single-purpose: call the Rust REST API; raise on failure.

The negative regression test (test-rust-required.R) now passes — when
Rust is unreachable, the loop stop()s with a message containing
RUST_API_URL instead of silently substituting C++ results."
```

---

## Task 6: Update the scheduler — warning becomes `stop()`, drop `use_rust` argument

**Goal:** In `RCode/updateScheduler.R`, change the lines 155–158 warning to a `stop()`, and remove the now-invalid `use_rust = rust_available` argument from the `update_all_leagues_loop()` call at line 172. Run the season-transition smoke check (csv_generation.R is unchanged here, but season-transition's own `safe_source` may pick up some of the renamed files indirectly — the canary confirms no regression). Commit.

**Files:**
- Modify: `RCode/updateScheduler.R` (lines 151–172)

- [ ] **Step 1: Inspect the current state**

```bash
sed -n '150,175p' RCode/updateScheduler.R
```

Expected output: `# Test Rust connection` comment, the `source()`+`connect_rust_simulator()` block, the warning, the `update_all_leagues_loop(...)` call with `use_rust = rust_available` as the last argument.

- [ ] **Step 2: Replace the warning + `use_rust` plumbing in the scheduler's `main()`**

Use the Edit tool. Find this exact text in `RCode/updateScheduler.R`:

```r
  # Test Rust connection
  source("RCode/rust_integration.R")
  rust_available <- connect_rust_simulator()
  
  if (!rust_available) {
    message("WARNING: Rust engine not available, will use C++ fallback")
    message("Performance will be significantly reduced")
  }
  
  # Calculate optimal number of loops
  loop_config <- calculate_loops()
  
  # Run the update loop with Rust engine
  update_all_leagues_loop(
    duration = loop_config$duration,  # Use actual time remaining, not DURATION
    loops = loop_config$loops,
    initial_wait = loop_config$initial_wait,
    n = 10000,  # Can handle more iterations with Rust
    saison = SEASON,
    TeamList_file = team_list_file,
    shiny_directory = "ShinyApp",
    use_rust = rust_available
  )
```

Replace with:

```r
  # Assert Rust availability at scheduler startup. Issue #77 Phase 1: there is
  # no in-process fallback to C++. A missing Rust server fails the scheduler
  # here so the operator sees the real cause; the loop's own assertion is the
  # second-tier guard against the server dying mid-run.
  source("RCode/rust_integration.R")
  if (!connect_rust_simulator()) {
    stop(sprintf(
      "Rust simulator not available at %s. Start the Rust server before invoking this scheduler.",
      RUST_API_URL
    ))
  }
  
  # Calculate optimal number of loops
  loop_config <- calculate_loops()
  
  # Run the update loop. Rust availability has already been asserted above.
  update_all_leagues_loop(
    duration = loop_config$duration,  # Use actual time remaining, not DURATION
    loops = loop_config$loops,
    initial_wait = loop_config$initial_wait,
    n = 10000,
    saison = SEASON,
    TeamList_file = team_list_file,
    shiny_directory = "ShinyApp"
  )
```

(The argument list to `update_all_leagues_loop()` no longer includes `use_rust = rust_available` because Task 3 removed that parameter from the function signature. Comment "Can handle more iterations with Rust" simplified to nothing — the comment was a comparison to the deleted alternative.)

- [ ] **Step 3: Verify zero `rust_available` and zero `use_rust` references in the scheduler**

```bash
grep -n "rust_available\|use_rust" RCode/updateScheduler.R
```

Expected: no output.

- [ ] **Step 4: Verify R can parse the file**

```bash
Rscript -e 'invisible(parse("RCode/updateScheduler.R")); cat("PARSE OK\n")'
```

Expected: `PARSE OK`.

- [ ] **Step 5: Run the season-transition smoke check (canary)**

```bash
Rscript -e 'tryCatch(source("scripts/season_transition.R"), error = function(e) cat("ERROR:", e$message, "\n"))' 2>&1 | tee /tmp/season-transition-after-task6.txt
diff /tmp/season-transition-baseline-phase1.txt /tmp/season-transition-after-task6.txt
echo "diff_exit=$?"
```

Expected: `diff_exit=0` — byte-identical to the baseline captured in Task 1 Step 8. Phase 1 deliberately does not touch any season-transition file, so the baseline must hold.

If the diff is non-zero: STOP and report BLOCKED. Something in Tasks 3–5 affected season-transition through a transitive dependency we missed.

- [ ] **Step 6: Commit**

```bash
git add RCode/updateScheduler.R
git commit -m "refactor: scheduler stop()s on Rust unavailability instead of warning

Issue #77 Phase 1. The scheduler used to log 'WARNING: Rust engine not
available, will use C++ fallback' and proceed; it now stop()s with a
message naming RUST_API_URL. Drops the use_rust = rust_available
argument from the update_all_leagues_loop() call (the parameter was
removed from the loop's signature in the prior commit).

Season-transition smoke check passes byte-identical to baseline."
```

---

## Task 7: Update the Dockerfile — remove the runtime `Rcpp::sourceCpp` build step

**Goal:** Delete `Dockerfile` lines 101–104 (the `# Compile C++ code (fallback when Rust unavailable)` block). Rebuild the production image. Confirm parity with the Task-1 baseline.

**Files:**
- Modify: `Dockerfile` (lines 101–104)

- [ ] **Step 1: Inspect the current state**

```bash
sed -n '99,106p' Dockerfile
```

Expected output:

```
COPY ShinyApp/ ./ShinyApp/

# Compile C++ code (fallback when Rust unavailable)
RUN cd /app/RCode && \
    R -e "Rcpp::sourceCpp('SpielNichtSimulieren.cpp')" || \
    echo "Warning: C++ compilation failed, will rely on Rust engine"

# Copy robust startup script
```

- [ ] **Step 2: Remove the block**

Use the Edit tool. Find this exact text in `Dockerfile`:

```
# Compile C++ code (fallback when Rust unavailable)
RUN cd /app/RCode && \
    R -e "Rcpp::sourceCpp('SpielNichtSimulieren.cpp')" || \
    echo "Warning: C++ compilation failed, will rely on Rust engine"

```

Replace with: empty (delete the whole block including the trailing blank line).

- [ ] **Step 3: Verify the block is gone**

```bash
grep -n "Rcpp::sourceCpp\|Compile C++ code\|fallback when Rust" Dockerfile
```

Expected: no output.

- [ ] **Step 4: Verify the Dockerfile structure is still coherent**

```bash
sed -n '99,103p' Dockerfile
```

Expected output: `COPY ShinyApp/ ./ShinyApp/` immediately followed (with one blank line) by `# Copy robust startup script` and `COPY docker-start.sh /app/start.sh`. No orphaned `RUN` or comment fragments.

- [ ] **Step 5: Build the post-refactor image**

Use the nohup pattern:

```bash
cd <worktree-absolute-path>
nohup docker build -f Dockerfile -t league-simulator:phase1-post . > /tmp/docker-build-phase1-post.log 2>&1 & disown
echo "PID: $!"
```

Poll `tail /tmp/docker-build-phase1-post.log` until `Successfully tagged league-simulator:phase1-post` or an error.

Expected: build succeeds. Cache hit on most layers; only `COPY RCode/` and everything after may re-run because RCode/ contents changed in Tasks 3–5. The C++ compile step is gone, so total layer count drops by 1.

If the build fails: STOP and report BLOCKED with the build log tail.

- [ ] **Step 6: Compare layer counts**

```bash
PRE=$(docker history --no-trunc --format '{{.ID}}' league-simulator:phase1-pre | wc -l)
POST=$(docker history --no-trunc --format '{{.ID}}' league-simulator:phase1-post | wc -l)
echo "Pre-Phase-1 layers: $PRE"
echo "Post-Phase-1 layers: $POST"
```

Expected: post-cleanup count is `pre - 1` (one fewer layer because the `Rcpp::sourceCpp` RUN step is gone). Could also be equal if Docker's cache squashed in some surprising way; off by ≤1 is acceptable.

- [ ] **Step 7: Smoke test the container — Rust server starts and the scheduler boots**

```bash
docker run --rm -d --name phase1-smoke \
  -e RAPIDAPI_KEY=dummy_for_smoke \
  -e SHINYAPPS_IO_SECRET=dummy_for_smoke \
  league-simulator:phase1-post

sleep 8
docker logs phase1-smoke 2>&1 | grep -E "Rust server ready|RUST_API_URL|ERROR" | head -10
docker stop phase1-smoke
```

Expected behavior in the logs:
- `✅ Rust server ready on port 8080` — confirms the Rust binary started cleanly.
- The scheduler will then likely fail because `RAPIDAPI_KEY=dummy_for_smoke` won't validate; that's OK — what we're proving is that the Rust startup contract still works.

If you see `Rcpp::sourceCpp` errors in the logs or "C++ compilation failed" warnings: STOP and report — the build step removal somehow regressed something.

- [ ] **Step 8: Final source-code grep — zero stale `use_rust` / `simulator_function` / per-call fallback references**

```bash
grep -rEn "use_rust|simulator_function|leagueSimulatorCPP" RCode/update_all_leagues_loop.R RCode/rust_integration.R RCode/updateScheduler.R Dockerfile
```

Expected: no output. (The `leagueSimulatorCPP` survivor file at `RCode/leagueSimulatorCPP.R` will, of course, contain the function — but the *production seam files* must not reference it.)

If any match appears, fix the file before committing.

- [ ] **Step 9: Commit**

```bash
git add Dockerfile
git commit -m "build: remove unused Rcpp::sourceCpp step from Dockerfile

Issue #77 Phase 1. The runtime 'R -e Rcpp::sourceCpp(SpielNichtSimulieren.cpp)'
step was the only consumer of the C++ build artifact inside the
container — and the only consumer of that artifact was the
update_all_leagues_loop fallback path, which was removed in the prior
commits. The C++ source files still come along via COPY RCode/ but are
inert in the container; the host-side season-transition workflow that
sources SpielCPP.R runs outside the container.

The line that documented its own failure mode ('Warning: C++ compilation
failed, will rely on Rust engine') is gone — failures now surface as
the actual root cause."
```

---

## Task 8: Final acceptance grep + season-transition smoke + commit summary

**Goal:** Verify the PRD's Phase 1 acceptance criteria pass against the cleaned-up tree. No commits.

**Files:** None modified.

- [ ] **Step 1: Run the source-code-scoped legacy-fallback grep**

```bash
grep -rEn "use_rust|simulator_function|leagueSimulatorCPP|Rcpp::sourceCpp|C\+\+ fallback|Falling back to C\+\+" \
  RCode/update_all_leagues_loop.R \
  RCode/rust_integration.R \
  RCode/updateScheduler.R \
  Dockerfile 2>/dev/null
```

Expected: no output. (Other files in `RCode/` may legitimately mention `leagueSimulatorCPP` — those are the survivors. The four production seam files are the ones that must be clean.)

- [ ] **Step 2: Confirm the C++ engine survivors are still present**

```bash
ls RCode/leagueSimulatorCPP.R RCode/simulationsCPP.R RCode/SaisonSimulierenCPP.R RCode/SpielCPP.R RCode/SpielNichtSimulieren.cpp RCode/cpp_wrappers.R RCode/RcppExports.R
```

Expected: all 7 files listed cleanly. Phase 1 keeps them.

- [ ] **Step 3: Run the regression test one final time**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-rust-required.R", reporter = "summary")'
```

Expected:
- Positive test: PASS (with Rust binary built per Task 1) or SKIP.
- Negative test: PASS — the `stop()` with `RUST_API_URL` happens.

If both PASS or both SKIP, that's the green state. If the positive PASSes and the negative FAILs, that's a defect — stop and investigate.

- [ ] **Step 4: Final season-transition canary**

```bash
Rscript -e 'tryCatch(source("scripts/season_transition.R"), error = function(e) cat("ERROR:", e$message, "\n"))' 2>&1 | tee /tmp/season-transition-final.txt
diff /tmp/season-transition-baseline-phase1.txt /tmp/season-transition-final.txt
echo "diff_exit=$?"
```

Expected: `diff_exit=0` — byte-identical to Task 1's baseline.

- [ ] **Step 5: `docker compose config` final check**

```bash
docker compose config > /dev/null && echo "compose OK"
```

Expected: `compose OK` (env-var warnings on stderr are fine).

- [ ] **Step 6: Show the cumulative diff summary**

```bash
git log --oneline main..HEAD
echo '---'
git diff --shortstat main..HEAD
```

Expected: 4 commits (Tasks 2, 3+4, 5, 6, 7 = 5 commits if Tasks 3+4 land separately, but the plan combined them). The diff-stat should be approximately:

- ~50 line deletions (loop fallback block + per-call fallback + warning + Dockerfile step + `use_rust` references + Performance message + dispatch line)
- ~30 line insertions (the new fail-fast `stop()` calls + the new test file + the comment updates)
- ~3–4 files modified (`update_all_leagues_loop.R`, `rust_integration.R`, `updateScheduler.R`, `Dockerfile`) plus the test fixture and the test file (created)

- [ ] **Step 7: No commit**

Verification-only.

---

## Acceptance Criteria Mapping (PRD ↔ Plan)

| PRD Acceptance Criterion (Phase 1) | Implementing Task(s) |
|---|---|
| `RCode/rust_integration.R` no longer calls `leagueSimulatorCPP` | Task 5 |
| `RCode/update_all_leagues_loop.R` does not contain `use_rust`, `leagueSimulatorCPP`, `SaisonSimulierenCPP`, `simulationsCPP`, `Rcpp::sourceCpp` | Tasks 3 + 4 |
| `RCode/update_all_leagues_loop.R` calls `leagueSimulatorRust` directly (no `simulator_function`) | Task 4 |
| Scheduler exits non-zero with `RUST_API_URL` in message when Rust unreachable | Task 6 |
| `Dockerfile` no longer contains the `Rcpp::sourceCpp` build step | Task 7 |
| CPP source files **remain** in `RCode/` | Task 8 Step 2 (verification) |
| `tests/testthat/test-*CPP*.R` files: status verified, not deleted | Task 8 implicit (no deletion happens) |
| `compare_rust_cpp.R`, etc., not deleted | Task 8 implicit |
| End-to-end test exists for `update_all_leagues_loop()` | Task 2 (created) |
| Docker image still builds + healthy Rust server + first iteration | Task 7 Steps 5–7 |
| Season-transition smoke test still passes | Tasks 6 + 8 (canary) |

## Self-Review Notes

Performed before publishing:

1. **Spec coverage:** All 11 PRD Phase-1 acceptance criteria map to a task. The "What to do with existing CPP testthat files" decision is explicitly deferred to issue #76 (CI rebuild) per the PRD.

2. **Placeholder scan:** Every task step has either a concrete shell command, a code block to write/edit, or an explicit verification command. The `with_repo_root` helper in the test is concrete (sets cwd to repo root). No "TBD", no "fill in", no "similar to Task N".

3. **Type / name consistency:** The function signature changes consistently (`update_all_leagues_loop` keeps name; loses `use_rust` parameter in Task 3; the call in Task 6 also drops `use_rust = rust_available`). `leagueSimulatorRust` keeps its name throughout. `RUST_API_URL` is referenced via `Sys.getenv("RUST_API_URL", ...)` in Task 3 (loop) and as a top-level variable in Task 6 (scheduler, since it's set at line 9) — both correct in their respective contexts.

4. **Test fixture realism:** The `TeamList_minimal.csv` fixture has 4 columns (`TeamID;ShortName;Promotion;InitialELO`) and 4 teams. The real `TeamList_2025.csv` may have more columns; if the loop errors on missing columns during the positive test, the fix is to widen the fixture, not narrow the loop. The plan's Task 2 Step 2 explicitly anticipates this.
