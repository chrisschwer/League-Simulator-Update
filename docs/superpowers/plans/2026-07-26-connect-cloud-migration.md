# Connect Cloud Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the unattended Shiny deployment path work against Posit Connect Cloud before the 2027-03-31 forced migration, without breaking the shinyapps.io path that serves production today.

**Architecture:** Introduce a deployment-backend seam in `RCode/updateShiny.R` selected by `SHINY_DEPLOY_TARGET`. Two authenticator functions (`authenticate_shinyapps`, `authenticate_connectcloud`) sit behind a `switch()`; everything after authentication — save results, `deployApp()` — stays identical. Both backends remain live so cutover and rollback are environment-variable flips.

**Tech Stack:** R 4.6, `rsconnect` (>= 1.10.0), `testthat` 3.2.3, `withr` 3.0.2, Docker.

## Global Constraints

- **rsconnect >= 1.10.0** is required — `connectCloudClientCredentials()` was introduced there. Locally installed is 1.5.0; CRAN latest is 1.10.1.
- **Default backend stays `shinyapps`** through every task. No task may change production behaviour when `SHINY_DEPLOY_TARGET` is unset.
- Existing shinyapps.io credential hard-fail behaviour must keep working (regression-protected by `tests/testthat/test-updateShiny-env.R`).
- Connect Cloud env vars: `CONNECT_CLOUD_CLIENT_ID`, `CONNECT_CLOUD_CLIENT_SECRET`, `CONNECT_CLOUD_ACCOUNT` (default `chrisschwer`).
- Run the full suite with `Rscript -e 'source("tests/testthat.R")'`; single file with `Rscript -e 'testthat::test_file("tests/testthat/<file>.R")'`.
- All credential checks must fire **before** any network call, so tests need no rsconnect mocking (pass `directory = tempdir()`).
- Account is on the **Starter plan** → maps to Connect Cloud **Basic**, price frozen until 2029. Deadline **2027-03-31**.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `RCode/updateShiny.R` | Backend seam, both authenticators, save + deploy | Modify (61 lines today) |
| `RCode/updateScheduler.R` | Startup preflight for the selected backend | Modify lines 6, 16-18 |
| `tests/testthat/test-updateShiny-env.R` | Credential + backend-selection tests | Extend |
| `packagelist.txt` | Pin `rsconnect (>= 1.10.0)` | Modify line 14 |
| `.env.example` | Document Connect Cloud vars | Modify |
| `docs/deployment/README.md` | Env-var reference table | Modify |
| `docs/deployment/connect-cloud-migration.md` | Operator runbook for cutover | Create |

---

### Task 1: Deployment backend seam with both authenticators

Replaces the single hardcoded `setAccountInfo()` call with a selectable backend. Also fixes the two correctness defects in this file (unsafe CWD restore, non-existent default path) because they are in the lines being touched and are exactly the failure class a migration provokes.

**Files:**
- Modify: `RCode/updateShiny.R:1-60` (whole file)
- Test: `tests/testthat/test-updateShiny-env.R`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `resolve_deploy_backend()` → character, one of `"shinyapps"` / `"connectcloud"`; stops on any other value.
  - `authenticate_shinyapps()` → invisible NULL; stops if `SHINYAPPS_IO_TOKEN` or `SHINYAPPS_IO_SECRET` is empty.
  - `authenticate_connectcloud()` → invisible NULL; stops if `CONNECT_CLOUD_CLIENT_ID` or `CONNECT_CLOUD_CLIENT_SECRET` is empty.
  - `updateShiny(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg, directory, forceUpdate)` — signature unchanged except the `directory` default.

- [ ] **Step 1: Write the failing tests for backend selection and Connect Cloud credentials**

Append to `tests/testthat/test-updateShiny-env.R`:

```r
# --- Backend selection -------------------------------------------------------

test_that("updateShiny defaults to the shinyapps backend when SHINY_DEPLOY_TARGET is unset", {
  updateShiny <- source_updateShiny()
  withr::local_envvar(c(
    SHINY_DEPLOY_TARGET = NA,
    SHINYAPPS_IO_TOKEN = "", SHINYAPPS_IO_SECRET = "dummy"
  ))
  # Falling through to the shinyapps credential check proves shinyapps is the default.
  expect_error(
    updateShiny(NULL, NULL, NULL, directory = tempdir()),
    "SHINYAPPS_IO_TOKEN"
  )
})

test_that("updateShiny rejects an unknown SHINY_DEPLOY_TARGET with an actionable message", {
  updateShiny <- source_updateShiny()
  withr::local_envvar(c(SHINY_DEPLOY_TARGET = "heroku"))
  expect_error(
    updateShiny(NULL, NULL, NULL, directory = tempdir()),
    "SHINY_DEPLOY_TARGET"
  )
})

# --- Connect Cloud credentials ----------------------------------------------

test_that("connectcloud backend stops when CONNECT_CLOUD_CLIENT_ID is not set", {
  updateShiny <- source_updateShiny()
  withr::local_envvar(c(
    SHINY_DEPLOY_TARGET = "connectcloud",
    CONNECT_CLOUD_CLIENT_ID = "", CONNECT_CLOUD_CLIENT_SECRET = "dummy"
  ))
  expect_error(
    updateShiny(NULL, NULL, NULL, directory = tempdir()),
    "CONNECT_CLOUD_CLIENT_ID"
  )
})

test_that("connectcloud backend stops when CONNECT_CLOUD_CLIENT_SECRET is not set", {
  updateShiny <- source_updateShiny()
  withr::local_envvar(c(
    SHINY_DEPLOY_TARGET = "connectcloud",
    CONNECT_CLOUD_CLIENT_ID = "dummy", CONNECT_CLOUD_CLIENT_SECRET = ""
  ))
  expect_error(
    updateShiny(NULL, NULL, NULL, directory = tempdir()),
    "CONNECT_CLOUD_CLIENT_SECRET"
  )
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-updateShiny-env.R")'`

Expected: the two pre-existing shinyapps tests PASS; the four new tests FAIL. The unknown-target test fails because no `SHINY_DEPLOY_TARGET` handling exists; the Connect Cloud tests fail because `updateShiny` still reads `SHINYAPPS_IO_*` unconditionally and errors with `"SHINYAPPS_IO_TOKEN"` instead of the expected message.

- [ ] **Step 3: Rewrite `RCode/updateShiny.R` with the seam**

Replace the entire file:

```r
# Shiny deployment.
#
# Two deployment backends are supported, selected by SHINY_DEPLOY_TARGET:
#   shinyapps    (default) - legacy shinyapps.io, static token/secret
#   connectcloud           - Posit Connect Cloud, OAuth2 client credentials
#
# shinyapps.io is being retired by Posit; paid accounts are force-migrated on
# 2027-03-31. See docs/deployment/connect-cloud-migration.md for the cutover.

resolve_deploy_backend <- function() {
  target <- tolower(trimws(Sys.getenv("SHINY_DEPLOY_TARGET", "shinyapps")))
  if (target == "") {
    target <- "shinyapps"
  }
  if (!target %in% c("shinyapps", "connectcloud")) {
    stop(sprintf(
      paste0(
        "ERROR: unsupported SHINY_DEPLOY_TARGET '%s'. ",
        "Expected 'shinyapps' or 'connectcloud'."
      ),
      target
    ))
  }
  target
}

authenticate_shinyapps <- function() {
  account_name <- Sys.getenv("SHINYAPPS_IO_NAME", "chrisschwer")
  account_token <- Sys.getenv("SHINYAPPS_IO_TOKEN")
  account_secret <- Sys.getenv("SHINYAPPS_IO_SECRET")

  if (account_token == "") {
    stop("ERROR: SHINYAPPS_IO_TOKEN environment variable not set")
  }
  if (account_secret == "") {
    stop("ERROR: SHINYAPPS_IO_SECRET environment variable not set")
  }

  message(sprintf("Authenticating to shinyapps.io as '%s'", account_name))
  rsconnect::setAccountInfo(
    name = account_name,
    token = account_token,
    secret = account_secret
  )
  invisible(NULL)
}

authenticate_connectcloud <- function() {
  account_name <- Sys.getenv("CONNECT_CLOUD_ACCOUNT", "chrisschwer")
  client_id <- Sys.getenv("CONNECT_CLOUD_CLIENT_ID")
  client_secret <- Sys.getenv("CONNECT_CLOUD_CLIENT_SECRET")

  if (client_id == "") {
    stop("ERROR: CONNECT_CLOUD_CLIENT_ID environment variable not set")
  }
  if (client_secret == "") {
    stop("ERROR: CONNECT_CLOUD_CLIENT_SECRET environment variable not set")
  }

  if (!exists("connectCloudClientCredentials", where = asNamespace("rsconnect"))) {
    stop(paste(
      "ERROR: installed rsconnect lacks connectCloudClientCredentials().",
      "Connect Cloud deployment requires rsconnect >= 1.10.0; installed:",
      as.character(utils::packageVersion("rsconnect"))
    ))
  }

  message(sprintf("Authenticating to Posit Connect Cloud as '%s'", account_name))
  rsconnect::connectCloudClientCredentials(
    clientId = client_id,
    clientSecret = client_secret,
    accountName = account_name
  )
  invisible(NULL)
}

updateShiny <- function(Ergebnis, Ergebnis2, Ergebnis3,
                        Ergebnis3_Aufstieg = Ergebnis3,
                        directory = file.path(getwd(), "ShinyApp"),
                        forceUpdate = TRUE) {
  backend <- resolve_deploy_backend()

  # Ensure all required packages are loaded
  required_packages <- c("rsconnect", "shiny", "crayon", "ellipsis", "httpuv")

  for (pkg in required_packages) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
      stop(paste(
        "Required package not available:", pkg,
        "\nPlease ensure all dependencies are installed in the Docker container"
      ))
    }
  }

  # Use packrat mode to avoid "reproducible location" errors
  options(rsconnect.packrat = TRUE)

  switch(backend,
    shinyapps = authenticate_shinyapps(),
    connectcloud = authenticate_connectcloud()
  )

  # Restore the working directory even if the deploy fails: leaving the process
  # inside ShinyApp/ breaks the next scheduler loop's relative source() paths.
  curr_wd <- getwd()
  on.exit(setwd(curr_wd), add = TRUE)

  message(sprintf("Changing to directory: %s", directory))
  setwd(directory)

  if (!dir.exists("data")) {
    message("Creating data directory")
    dir.create("data", showWarnings = FALSE)
  }

  message("Saving simulation results to data/Ergebnis.Rds")
  save(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg, file = "data/Ergebnis.Rds")

  message(sprintf("Deploying app via backend '%s'", backend))
  rsconnect::deployApp(
    appFiles = c("app.R", "app_helpers.R", "data/Ergebnis.Rds"),
    appName = "FussballPrognosen", forceUpdate = forceUpdate
  )

  message("Deployment completed")
  invisible(NULL)
}
```

Three things changed beyond the seam: the `directory` default is now repo-relative (was an absolute `Dropbox-CSDataScience` path that does not exist in this checkout), the CWD restore moved into `on.exit()`, and the bare `library(rsconnect)` + `deployApp()` became a namespaced `rsconnect::deployApp()`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-updateShiny-env.R")'`

Expected: all six tests PASS (2 pre-existing shinyapps + 4 new).

- [ ] **Step 5: Run the full suite to check for regressions**

Run: `Rscript -e 'source("tests/testthat.R")'`

Expected: no new failures. Pay attention to `test-update-loop-gating.R` (stubs `updateShiny`) and `test-rust-required.R` (passes `shiny_directory = tempdir()`) — both exercise this call path.

- [ ] **Step 6: Commit**

```bash
git add RCode/updateShiny.R tests/testthat/test-updateShiny-env.R
git commit -m "feat: add Connect Cloud deployment backend behind SHINY_DEPLOY_TARGET

shinyapps.io is being retired; setAccountInfo() has no Connect Cloud
equivalent and connectCloudUser() is a browser handshake unusable from a
headless container. Add connectCloudClientCredentials() (OAuth2 service
account) behind a backend seam, defaulting to shinyapps so production
behaviour is unchanged.

Also fixes two defects in the touched lines: restore the working
directory via on.exit() so a failed deploy cannot break the next
scheduler loop, and replace the non-existent hardcoded directory default
with a repo-relative one."
```

---

### Task 2: CWD-restore regression test

Task 1 fixed the unsafe CWD restore but nothing yet proves it. This locks it in, because the bug is invisible until a deploy fails in production.

**Files:**
- Test: `tests/testthat/test-updateShiny-env.R`

**Interfaces:**
- Consumes: `updateShiny()` and `resolve_deploy_backend()` from Task 1.
- Produces: nothing consumed downstream.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-updateShiny-env.R`:

```r
test_that("updateShiny restores the working directory when deployment fails", {
  updateShiny <- source_updateShiny()

  app_dir <- withr::local_tempdir()
  # updateShiny writes into data/ then deploys; give it a directory to cd into.
  before <- getwd()

  withr::local_envvar(c(
    SHINY_DEPLOY_TARGET = "shinyapps",
    SHINYAPPS_IO_NAME = "acct",
    SHINYAPPS_IO_TOKEN = "tok", SHINYAPPS_IO_SECRET = "sec"
  ))

  # Force a failure at the deploy step, after the setwd() has happened.
  mockery::stub(updateShiny, "rsconnect::setAccountInfo", function(...) invisible(NULL))
  mockery::stub(updateShiny, "rsconnect::deployApp", function(...) stop("deploy boom"))

  expect_error(
    updateShiny(1, 2, 3, directory = app_dir),
    "deploy boom"
  )
  expect_equal(normalizePath(getwd()), normalizePath(before))
})
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-updateShiny-env.R")'`

Expected: PASS. This test is written *after* the fix, so it should pass immediately — that is intentional here. To confirm it actually guards the behaviour, temporarily change `on.exit(setwd(curr_wd), add = TRUE)` back to a trailing `setwd(curr_wd)` in `RCode/updateShiny.R`, re-run, and observe the FAIL on the `expect_equal(getwd(), ...)` assertion. Then restore the `on.exit()` version.

- [ ] **Step 3: Verify the guard, then restore**

Run the temporary-revert check described in Step 2 and confirm you saw the failure. Restore `RCode/updateShiny.R` to the Task 1 version:

```bash
git checkout RCode/updateShiny.R
```

- [ ] **Step 4: Re-run the file to confirm green after restore**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-updateShiny-env.R")'`

Expected: all seven tests PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-updateShiny-env.R
git commit -m "test: assert updateShiny restores CWD when deployment fails"
```

---

### Task 3: Pin rsconnect and fail fast on an old version

`packagelist.txt:14` is a bare `rsconnect`, so the Docker build installs whatever CRAN serves that day — meaning the production rsconnect version is currently accidental. Connect Cloud needs >= 1.10.0.

**Files:**
- Modify: `packagelist.txt:14`
- Test: `tests/testthat/test-updateShiny-env.R`

**Interfaces:**
- Consumes: `authenticate_connectcloud()` from Task 1 (its version guard).
- Produces: nothing consumed downstream.

- [ ] **Step 1: Write the failing test for the version guard**

Append to `tests/testthat/test-updateShiny-env.R`:

```r
test_that("packagelist pins rsconnect to a Connect Cloud capable version", {
  pkgs <- readLines(test_path("..", "..", "packagelist.txt"), warn = FALSE)
  rsconnect_line <- grep("^rsconnect", pkgs, value = TRUE)
  expect_length(rsconnect_line, 1)
  expect_match(rsconnect_line, "rsconnect \\(>= 1\\.10\\.0\\)", fixed = FALSE)
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-updateShiny-env.R")'`

Expected: FAIL — `packagelist.txt` line 14 is the bare string `rsconnect`, so `expect_match` does not find the version constraint.

- [ ] **Step 3: Pin the dependency**

In `packagelist.txt`, change line 14 from:

```
rsconnect
```

to:

```
rsconnect (>= 1.10.0)
```

Then check how the Docker build consumes this file. `Dockerfile:57` installs a hardcoded `shiny_pkgs <- c('htmltools', 'httpuv', 'promises', 'shiny', 'rsconnect')` vector rather than reading `packagelist.txt`, and `install.packages()` ignores version constraints in a plain name. So the pin is documentation unless the build enforces it. Add an explicit assertion after the R package installs in `Dockerfile` (immediately following the block ending at line 83):

```dockerfile
# Connect Cloud deployment needs rsconnect >= 1.10.0 (connectCloudClientCredentials).
RUN Rscript -e 'v <- utils::packageVersion("rsconnect"); \
    if (v < "1.10.0") stop(sprintf("rsconnect %s too old; need >= 1.10.0", v)); \
    cat("rsconnect", as.character(v), "OK\n")'
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-updateShiny-env.R")'`

Expected: all eight tests PASS.

- [ ] **Step 5: Verify the Docker build enforces the floor**

Run: `docker build -t league-simulator:cc-test .`

Expected: build succeeds and the log contains `rsconnect <version> OK` with a version >= 1.10.0. If the build fails on the version assertion, CRAN's current rsconnect is older than expected — investigate before proceeding rather than lowering the floor, since `connectCloudClientCredentials()` genuinely does not exist below 1.10.0.

- [ ] **Step 6: Commit**

```bash
git add packagelist.txt Dockerfile tests/testthat/test-updateShiny-env.R
git commit -m "build: require rsconnect >= 1.10.0 for Connect Cloud deployment

The dependency was unpinned, so the image got whichever version CRAN
served on build day. connectCloudClientCredentials() needs 1.10.0+;
assert it at build time rather than discovering it at deploy time."
```

---

### Task 4: Validate the selected backend's credentials at scheduler startup

Today `updateScheduler.R:6,16-18` preflights `SHINYAPPS_IO_SECRET` but **not** `SHINYAPPS_IO_TOKEN`, so a missing token is discovered hours later inside the matchday loop. Connect Cloud vars are not checked at all. This converts a silent mid-loop failure into a loud startup failure.

**Files:**
- Modify: `RCode/updateScheduler.R:6,16-18`
- Test: `tests/testthat/test-scheduler-deploy-preflight.R` (create)

**Interfaces:**
- Consumes: `resolve_deploy_backend()` from Task 1.
- Produces: `validate_deploy_credentials()` → invisible NULL; stops with the name of the first missing variable for the selected backend.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-scheduler-deploy-preflight.R`:

```r
# The scheduler must reject missing deployment credentials at startup rather
# than failing hours later inside the matchday loop.

source_validator <- function() {
  source(test_path("..", "..", "RCode", "updateShiny.R"), local = TRUE)
  environment()$validate_deploy_credentials
}

test_that("shinyapps backend requires both token and secret at startup", {
  validate <- source_validator()

  withr::local_envvar(c(
    SHINY_DEPLOY_TARGET = "shinyapps",
    SHINYAPPS_IO_TOKEN = "", SHINYAPPS_IO_SECRET = "sec"
  ))
  expect_error(validate(), "SHINYAPPS_IO_TOKEN")
})

test_that("shinyapps backend rejects a missing secret at startup", {
  validate <- source_validator()

  withr::local_envvar(c(
    SHINY_DEPLOY_TARGET = "shinyapps",
    SHINYAPPS_IO_TOKEN = "tok", SHINYAPPS_IO_SECRET = ""
  ))
  expect_error(validate(), "SHINYAPPS_IO_SECRET")
})

test_that("connectcloud backend requires client id and secret at startup", {
  validate <- source_validator()

  withr::local_envvar(c(
    SHINY_DEPLOY_TARGET = "connectcloud",
    CONNECT_CLOUD_CLIENT_ID = "", CONNECT_CLOUD_CLIENT_SECRET = "sec"
  ))
  expect_error(validate(), "CONNECT_CLOUD_CLIENT_ID")
})

test_that("validation passes when the selected backend is fully configured", {
  validate <- source_validator()

  withr::local_envvar(c(
    SHINY_DEPLOY_TARGET = "connectcloud",
    CONNECT_CLOUD_CLIENT_ID = "id", CONNECT_CLOUD_CLIENT_SECRET = "sec"
  ))
  expect_silent(validate())
})

test_that("validation ignores the other backend's credentials", {
  validate <- source_validator()

  # connectcloud selected and configured; shinyapps vars deliberately empty.
  withr::local_envvar(c(
    SHINY_DEPLOY_TARGET = "connectcloud",
    CONNECT_CLOUD_CLIENT_ID = "id", CONNECT_CLOUD_CLIENT_SECRET = "sec",
    SHINYAPPS_IO_TOKEN = "", SHINYAPPS_IO_SECRET = ""
  ))
  expect_silent(validate())
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-scheduler-deploy-preflight.R")'`

Expected: FAIL — `validate_deploy_credentials` does not exist, so `source_validator()` returns NULL and calling it errors with "attempt to apply non-function".

- [ ] **Step 3: Add the validator to `RCode/updateShiny.R`**

Insert after `authenticate_connectcloud()` (before `updateShiny()`):

```r
# Startup preflight: check the selected backend's credentials without
# performing any network call, so a misconfiguration fails at container start
# instead of hours later inside the matchday loop.
validate_deploy_credentials <- function() {
  backend <- resolve_deploy_backend()

  required <- switch(backend,
    shinyapps = c("SHINYAPPS_IO_TOKEN", "SHINYAPPS_IO_SECRET"),
    connectcloud = c("CONNECT_CLOUD_CLIENT_ID", "CONNECT_CLOUD_CLIENT_SECRET")
  )

  for (var in required) {
    if (Sys.getenv(var) == "") {
      stop(sprintf(
        "ERROR: %s environment variable not set (required for SHINY_DEPLOY_TARGET='%s')",
        var, backend
      ))
    }
  }
  invisible(NULL)
}
```

- [ ] **Step 4: Wire it into the scheduler**

In `RCode/updateScheduler.R`, delete the `SHINYAPPS_IO_SECRET` assignment on line 6 and replace the validation block on lines 16-18:

```r
if (SHINYAPPS_IO_SECRET == "") {
  stop("ERROR: SHINYAPPS_IO_SECRET environment variable not set")
}
```

with:

```r
# Validate deployment credentials for whichever backend is selected.
source("RCode/updateShiny.R")
validate_deploy_credentials()
```

Check whether `updateScheduler.R` already sources `updateShiny.R` later (`update_all_leagues_loop.R:59` does its own `source`). A second `source()` is harmless — it only redefines functions — but if `updateScheduler.R` already sources it at the top, reuse that instead of adding a duplicate line.

- [ ] **Step 5: Run the new tests and the full suite**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-scheduler-deploy-preflight.R")'`
Expected: all five tests PASS.

Run: `Rscript -e 'source("tests/testthat.R")'`
Expected: no new failures.

- [ ] **Step 6: Commit**

```bash
git add RCode/updateShiny.R RCode/updateScheduler.R tests/testthat/test-scheduler-deploy-preflight.R
git commit -m "fix: validate deployment credentials at scheduler startup

The preflight checked SHINYAPPS_IO_SECRET but never the token, so a
missing token surfaced hours later mid-loop. Validate whichever backend
is selected, including Connect Cloud, before the scheduler starts."
```

---

### Task 5: Document the cutover for the operator

The deploy is operator-run, not CI-run, so the runbook is the deliverable that makes this migration executable. Also removes now-wrong shinyapps references.

**Files:**
- Create: `docs/deployment/connect-cloud-migration.md`
- Modify: `.env.example`
- Modify: `docs/deployment/README.md` (env-var table, lines 18-30)

**Interfaces:**
- Consumes: env var names from Tasks 1 and 4.
- Produces: nothing consumed downstream.

- [ ] **Step 1: Add the Connect Cloud vars to `.env.example`**

Replace the required/optional blocks:

```bash
# --- Required ---
RAPIDAPI_KEY=your_rapidapi_key_here

# Deployment backend: shinyapps (default) or connectcloud
# SHINY_DEPLOY_TARGET=shinyapps

# Required when SHINY_DEPLOY_TARGET=shinyapps
SHINYAPPS_IO_SECRET=your_shinyapps_secret_here
SHINYAPPS_IO_TOKEN=your_shinyapps_token_here

# Required when SHINY_DEPLOY_TARGET=connectcloud
# Issue credentials at https://login.posit.cloud/identity/credentials
# CONNECT_CLOUD_CLIENT_ID=your_connect_cloud_client_id
# CONNECT_CLOUD_CLIENT_SECRET=your_connect_cloud_client_secret

# --- Optional (defaults shown) ---
# SHINYAPPS_IO_NAME=chrisschwer
# CONNECT_CLOUD_ACCOUNT=chrisschwer
# SEASON=2025
# DURATION=480
# RUST_API_URL=http://localhost:8080
# TZ=Europe/Berlin
```

- [ ] **Step 2: Update the env-var table in `docs/deployment/README.md`**

Replace the `SHINYAPPS_*` rows with:

```markdown
| `SHINY_DEPLOY_TARGET` | no | `shinyapps` | Deployment backend: `shinyapps` or `connectcloud` |
| `SHINYAPPS_IO_SECRET` | if `shinyapps` | — | ShinyApps.io deployment auth |
| `SHINYAPPS_IO_TOKEN` | if `shinyapps` | — | ShinyApps.io account token (rotate if ever exposed; no default) |
| `SHINYAPPS_IO_NAME` | no | `chrisschwer` | ShinyApps.io account name |
| `CONNECT_CLOUD_CLIENT_ID` | if `connectcloud` | — | Connect Cloud service-account OAuth client ID |
| `CONNECT_CLOUD_CLIENT_SECRET` | if `connectcloud` | — | Connect Cloud service-account OAuth client secret |
| `CONNECT_CLOUD_ACCOUNT` | no | `chrisschwer` | Connect Cloud account to publish to |
```

Also fix the sentence below the table — it says "fill in the three required values", which is now wrong. Change to: "fill in `RAPIDAPI_KEY` plus the credentials for your chosen `SHINY_DEPLOY_TARGET`."

- [ ] **Step 3: Write the operator runbook**

Create `docs/deployment/connect-cloud-migration.md`:

```markdown
# Migrating from shinyapps.io to Posit Connect Cloud

Posit is retiring shinyapps.io. This account (`chrisschwer`, Starter plan) is
**force-migrated on 2027-03-31**; the self-serve migration tool shipped in
September 2026. Starter maps to Connect Cloud **Basic**, with current pricing
held until 2029.

The Shiny app itself needs no changes. Only the unattended deploy path does:
`setAccountInfo()` has no Connect Cloud equivalent, and the advertised
replacement `connectCloudUser()` is an interactive browser handshake. The
headless path is `connectCloudClientCredentials()` — an OAuth2 service account,
requiring **rsconnect >= 1.10.0**.

## One-time setup

1. Issue service-account credentials at <https://login.posit.cloud/identity/credentials>.
   Grant publish permission on the target account.
2. Put them in `.env`:

   ```bash
   CONNECT_CLOUD_CLIENT_ID=...
   CONNECT_CLOUD_CLIENT_SECRET=...
   ```

3. Use the migration tool in Connect Cloud to import `FussballPrognosen`. Test
   the imported app before finalizing. Finalizing sets up a redirect from the
   shinyapps.io URL and archives the app there.

## Cutover

Deploy backends are switched with one variable, so cutover and rollback are
symmetric.

```bash
# Dry run against Connect Cloud from a local R session
SHINY_DEPLOY_TARGET=connectcloud Rscript -e '
  source("RCode/updateShiny.R")
  validate_deploy_credentials()
  cat("credentials OK\n")
'
```

Then flip the container:

```bash
# .env
SHINY_DEPLOY_TARGET=connectcloud
```

```bash
docker-compose up -d
docker-compose logs -f league-simulator-integrated
```

Confirm in the logs: `Authenticating to Posit Connect Cloud as 'chrisschwer'`
followed by a successful deploy.

## Rollback

Set `SHINY_DEPLOY_TARGET=shinyapps` (or remove the line — `shinyapps` is the
default) and restart. Valid until shinyapps.io is switched off.

## Verify after cutover

- App reachable at its Connect Cloud URL, and the old shinyapps.io URL redirects.
- Footer timestamp updates after a scheduler cycle (proves the bundled
  `data/Ergebnis.Rds` is being refreshed, not just cached).
- All three leagues selectable and rendering heatmaps.

## Open risk: deploy frequency

The scheduler redeploys every 2 minutes from 14:45–22:45 — up to ~241 full
bundle uploads per matchday. **Posit documents no deployment rate limit for
Connect Cloud.** Watch the first matchday after cutover for throttling or
rejected deploys.

If throttling appears, the fix is to skip redeploys when results are unchanged:
hash the saved `Ergebnis` objects and compare against the previous cycle before
calling `deployApp()`. That is worth doing regardless — most cycles during a
matchday produce identical output.
```

- [ ] **Step 4: Remove the dead shinyapps CI references**

`docs/GITHUB_ACTIONS_CONFIG.md:14-16,127-130` tells operators to set
`SHINYAPPS_IO_*` as GitHub secrets, but no workflow reads them — deployment is
operator-run from inside the container (confirmed as deliberate in
`docs/superpowers/specs/2026-05-02-ci-rebuild-design.md:24`). Delete those
secret-setup instructions and replace them with a one-line pointer:

```markdown
Deployment credentials are **not** GitHub secrets — the container deploys at
runtime. See [`docs/deployment/connect-cloud-migration.md`](deployment/connect-cloud-migration.md).
```

- [ ] **Step 5: Verify the docs are internally consistent**

Run:

```bash
grep -rn "three required values" docs/ .env.example
grep -rn "SHINYAPPS_IO" docs/ | grep -v connect-cloud-migration
```

Expected: the first returns nothing (the stale phrase is gone). The second
should only show the env-var table in `docs/deployment/README.md` and the
quick-start — every hit should describe shinyapps as one of two backends, not
as the only one. Fix any that still read as unconditional.

- [ ] **Step 6: Commit**

```bash
git add .env.example docs/deployment/README.md docs/deployment/connect-cloud-migration.md docs/GITHUB_ACTIONS_CONFIG.md
git commit -m "docs: add Connect Cloud cutover runbook and backend env vars

Documents the SHINY_DEPLOY_TARGET switch, the service-account credential
setup, rollback, and the undocumented-rate-limit risk from redeploying
every 2 minutes. Also drops the GitHub-secrets instructions for
SHINYAPPS_IO_*, which no workflow has ever read."
```

---

### Task 6: Live verification against Connect Cloud

**This task cannot be completed before the migration tool ships (September 2026) and requires real credentials.** It is the empirical answer to the three open questions in the spec. Do not mark the plan complete without it — every prior task is unverified against the real service.

**Files:** none (verification only)

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: a go/no-go decision on flipping the default backend.

- [ ] **Step 1: Confirm rsconnect in the image supports Connect Cloud**

Run:

```bash
docker run --rm league-simulator:latest Rscript -e '
  cat("rsconnect:", as.character(packageVersion("rsconnect")), "\n")
  cat("client credentials:", "connectCloudClientCredentials" %in% getNamespaceExports("rsconnect"), "\n")
'
```

Expected: version >= 1.10.0 and `TRUE`. If `FALSE`, stop — Task 3's build assertion did not do its job.

- [ ] **Step 2: Authenticate with real credentials**

Run:

```bash
SHINY_DEPLOY_TARGET=connectcloud \
CONNECT_CLOUD_CLIENT_ID=<real> \
CONNECT_CLOUD_CLIENT_SECRET=<real> \
Rscript -e 'source("RCode/updateShiny.R"); authenticate_connectcloud(); cat("auth OK\n")'
```

Expected: `auth OK` with no browser prompt. **If a browser opens or the call blocks waiting for input, the client-credentials path does not work as documented** — that invalidates the core assumption of this design. Record the exact error and re-evaluate before proceeding; the fallback is GitHub-backed deployment, which is a different design.

- [ ] **Step 3: Perform one real deploy with live simulation data**

Run a single scheduler cycle against Connect Cloud, or deploy the existing
bundle directly:

```bash
SHINY_DEPLOY_TARGET=connectcloud \
CONNECT_CLOUD_CLIENT_ID=<real> CONNECT_CLOUD_CLIENT_SECRET=<real> \
Rscript -e '
  source("RCode/updateShiny.R")
  load("ShinyApp/data/Ergebnis.Rds")
  updateShiny(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg,
              directory = file.path(getwd(), "ShinyApp"))
'
```

Expected: deploy succeeds and prints a Connect Cloud URL.

- [ ] **Step 4: Verify the deployed app in a browser**

Open the Connect Cloud URL and confirm: all three leagues render heatmaps, the
footer timestamp matches this deploy, and no "Noch keine Prognosedaten
verfügbar" panel appears (which would mean the bundled `data/Ergebnis.Rds` did
not ship).

- [ ] **Step 5: Probe the deploy-frequency risk**

Run three consecutive deploys and time them:

```bash
for i in 1 2 3; do
  echo "--- deploy $i ---"
  time SHINY_DEPLOY_TARGET=connectcloud \
    CONNECT_CLOUD_CLIENT_ID=<real> CONNECT_CLOUD_CLIENT_SECRET=<real> \
    Rscript -e 'source("RCode/updateShiny.R"); load("ShinyApp/data/Ergebnis.Rds"); updateShiny(Ergebnis, Ergebnis2, Ergebnis3, Ergebnis3_Aufstieg, directory = file.path(getwd(), "ShinyApp"))'
done
```

Expected: three successes with no throttling error and no growing delay. If any
deploy is rejected or rate-limited, implement the hash-gated redeploy described
in `docs/deployment/connect-cloud-migration.md` before cutting over.

- [ ] **Step 6: Flip the default and record the outcome**

Only after Steps 1-5 pass: set `SHINY_DEPLOY_TARGET=connectcloud` in the
production `.env`, restart, and monitor the first live matchday. Then update
`docs/deployment/connect-cloud-migration.md` with what the rate-limit probe
actually showed, replacing the "Open risk" section with measured facts.

```bash
git add docs/deployment/connect-cloud-migration.md
git commit -m "docs: record measured Connect Cloud deploy behaviour after cutover"
```

---

## Self-Review

**Spec coverage:** Backend seam → Task 1. `on.exit` fix → Task 1, locked by Task 2. Hardcoded-path fix → Task 1. rsconnect >= 1.10.0 pin → Task 3. Scheduler preflight incl. the unchecked token → Task 4. Test strategy (both backends, unknown target, default unchanged, CWD restore) → Tasks 1, 2, 4. Docs/runbook → Task 5. The three open questions → Task 6 Steps 2 and 5. Rate-limit mitigation is specified concretely (hash-gated redeploy) rather than left vague.

**Naming consistency:** `resolve_deploy_backend()`, `authenticate_shinyapps()`, `authenticate_connectcloud()`, `validate_deploy_credentials()` are defined in Tasks 1 and 4 and used with identical names in Tasks 4, 5, and 6. Env vars `SHINY_DEPLOY_TARGET`, `CONNECT_CLOUD_CLIENT_ID`, `CONNECT_CLOUD_CLIENT_SECRET`, `CONNECT_CLOUD_ACCOUNT` are spelled identically throughout.

**Known deviation from strict TDD:** Task 2's test is written after its fix (the fix lands in Task 1, where the file is already being rewritten). Step 3 compensates with an explicit revert-and-observe-the-failure check, so the test is still proven to guard the behaviour.

**Blocked-by-external-dependency:** Task 6 cannot run until the migration tool exists and credentials are issued. Tasks 1-5 are complete and mergeable without it; they are inert in production because the default backend is unchanged.
