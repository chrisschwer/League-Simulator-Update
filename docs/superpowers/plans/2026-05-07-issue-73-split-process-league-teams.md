# Split `process_league_teams` Implementation Plan (Issue #73)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 120-line mixed-concern `process_league_teams` function with three small, independently testable units (`resolve_team_history`, `build_new_team_record`, `build_carryover_team_record`) behind a thin ~30-line orchestrator. New tests exercise the units directly without `mockery::stub`. Existing tests continue to pass unchanged because the public signature gains exactly one optional parameter (`prompt_fn`) with a default that preserves current behavior.

**Architecture:** Three new top-level functions extract the four mixed concerns the current function performs in one `tryCatch`: existence resolution (with two-source fallback), new-team interactive flow, carryover construction (with secondary fallback), and ELO selection. The orchestrator becomes a loop over teams that resolves history, dispatches to the right builder, and accumulates results. The `prompt_fn` parameter takes a function (default `prompt_for_team_info`); tests pass a stub function value instead of patching globally, but legacy `mockery::stub` patterns continue working because the default function lookup is unchanged.

**Tech Stack:** R 4.3+, testthat 3.x, mockery (existing). No new package dependencies. Two new files in flat `RCode/` layout per existing convention.

---

## File Structure

**Create:**

- `RCode/team_history_resolver.R` — defines `resolve_team_history(team_id, previous_team_list, final_elos)`. Pure. Returns one of three discriminated states.
- `RCode/team_record_builder.R` — defines `build_new_team_record(team, league_id, liga3_baseline, existing_short_names, prompt_fn)` and `build_carryover_team_record(team, history, league_id, liga3_baseline, existing_short_names)`. Both pure (the prompt path injects via parameter).
- `tests/testthat/test-team-history-resolver.R` — unit tests for the resolver.
- `tests/testthat/test-team-record-builder.R` — unit tests for both record builders.

**Modify:**

- `RCode/season_processor.R` — replace `process_league_teams` body (lines 228–348) with the new ~30-line orchestrator. Add optional `prompt_fn = prompt_for_team_info` parameter. The single call site at line 163 (in `process_single_season`) is unchanged because all old positional args still match.

**Untouched:**

- `RCode/team_data_carryover.R::get_existing_team_data` (line 99) — already a top-level pure function; the new resolver and existing tests both call it.
- `RCode/api_service.R::convert_second_team_short_name`, `get_team_short_name`, `get_league_name` — top-level helpers used by both old and new code paths.
- `RCode/interactive_prompts.R::prompt_for_team_info`, `generate_unique_short_name` — top-level helpers.
- `tests/testthat/test-season-processor.R`, `tests/testthat/test-season-transition-regression.R` — both keep their `mockery::stub` patterns. They continue to pass because the orchestrator's default `prompt_fn` is `prompt_for_team_info` (the global, which `stub()` still patches at the call boundary inside `build_new_team_record`).

> **Important compatibility note about mockery::stub.** `mockery::stub(process_league_teams, "prompt_for_team_info", ...)` patches the lookup of `prompt_for_team_info` *inside `process_league_teams`'s function environment*. After this refactor, `process_league_teams` no longer calls `prompt_for_team_info` directly — it passes `prompt_fn` to `build_new_team_record`, which calls `prompt_fn(...)`. This means the existing stubs would silently no-op.
>
> **Mitigation:** Task 6 verifies this empirically. If the existing stubs no longer take effect, two equivalently-cheap fixes exist:
>
> 1. **Re-target the stubs** — change `stub(process_league_teams, "prompt_for_team_info", X)` to `stub(build_new_team_record, "prompt_fn", X)` *or* `stub(build_new_team_record, "prompt_for_team_info", X)` depending on what mockery's lookup actually captures.
> 2. **Set `prompt_fn` directly** — add `prompt_fn = X` as a positional parameter in the existing test calls.
>
> Task 6 picks whichever is mechanically smallest, with the goal of keeping existing tests green. The split's *new* tests use option 2 throughout.

---

## Pre-flight (no commits, just baseline checks)

### Task 0: Capture the green baseline

**Why:** This refactor's safety hinges on the full testthat suite continuing to pass. Capture the baseline before any code change.

**Files:**
- Read: `RCode/season_processor.R:228-348`, `tests/testthat/test-season-processor.R`, `tests/testthat/test-season-transition-regression.R`, `tests/testthat/test-season-transition-csv-snapshot.R`

- [ ] **Step 1: Run the full testthat suite from the worktree root**

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update.issue-73-split-process-league-teams"
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -10
```

Expected: `[ FAIL 0 | WARN 13 | SKIP 4 | PASS 211 ]`. The 4 SKIPs are pre-existing (interactive-prompts mocking ×2, Rust binary not built ×1, empty test ×1).

If anything fails, **STOP and report**. Do not start the refactor.

- [ ] **Step 2: Run the load-bearing snapshot test in isolation**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")' 2>&1 | tail -8
```

Expected: 4 PASS / 0 FAIL with byte-identical CSV against `tests/testthat/fixtures/season-transition-2024-to-2025/TeamList_2025.csv.snapshot`. This is the load-bearing acceptance criterion of the refactor.

- [ ] **Step 3: Run the season-processor and regression tests in isolation**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-processor.R")' 2>&1 | tail -8
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-regression.R")' 2>&1 | tail -8
```

Expected: green. Note exact PASS counts — they must match after every later commit.

No commit in this task.

---

## Phase 1: New units (TDD)

### Task 1: `resolve_team_history` — write the test, then the function

**Why:** This is the load-bearing piece of the refactor. Today's `process_league_teams` mutates three flags (`team_exists`, `team_elo`, `previous_data`) across two if-blocks for what is conceptually one function: "given a team ID, what's its history?" Pulling it into a pure function with a discriminated return value is half the architectural fix.

**Files:**
- Create: `tests/testthat/test-team-history-resolver.R`
- Create: `RCode/team_history_resolver.R`

#### Step 1: Write the failing test

Create `tests/testthat/test-team-history-resolver.R` with this exact content:

```r
# Unit tests for resolve_team_history.
#
# resolve_team_history is the existence-resolution unit extracted from
# process_league_teams in issue #73. It takes a team_id, the previous
# team list (used for ShortText/Promotion carryover), and the final ELOs
# table from the previous season. It returns one of three discriminated
# states the caller dispatches on.

library(testthat)

source("../../RCode/team_data_carryover.R")  # for get_existing_team_data
source("../../RCode/team_history_resolver.R")

context("resolve_team_history — three-state discriminated return")

prev_team_list <- data.frame(
  TeamID = c(168, 167),
  ShortText = c("B04", "HOF"),
  Promotion = c(0, 0),
  InitialELO = c(1765, 1628),
  stringsAsFactors = FALSE
)

final_elos <- data.frame(
  TeamID = c(168, 999),
  FinalELO = c(1800, 1234)
)

test_that("resolve_team_history returns 'carryover' when team is in previous_team_list", {
  result <- resolve_team_history(168, prev_team_list, final_elos)

  expect_equal(result$state, "carryover")
  expect_equal(result$previous_data$short_name, "B04")
  expect_equal(result$previous_data$promotion_value, 0)
  expect_equal(result$team_elo, 1800)
})

test_that("resolve_team_history returns 'carryover' with NULL team_elo when team is in previous_team_list but not in final_elos", {
  # Team 167 is in prev_team_list but not in final_elos
  result <- resolve_team_history(167, prev_team_list, final_elos)

  expect_equal(result$state, "carryover")
  expect_equal(result$previous_data$short_name, "HOF")
  expect_null(result$team_elo)
})

test_that("resolve_team_history returns 'fallback' when team is only in final_elos", {
  # Team 999 is in final_elos but not in prev_team_list
  result <- resolve_team_history(999, prev_team_list, final_elos)

  expect_equal(result$state, "fallback")
  expect_null(result$previous_data)
  expect_equal(result$team_elo, 1234)
})

test_that("resolve_team_history returns 'new' when team is in neither source", {
  result <- resolve_team_history(42, prev_team_list, final_elos)

  expect_equal(result$state, "new")
  expect_null(result$previous_data)
  expect_null(result$team_elo)
})

test_that("resolve_team_history handles NULL previous_team_list (first season)", {
  result <- resolve_team_history(168, NULL, final_elos)

  # No previous_team_list means no carryover possible — falls through
  # to final_elos check, which has 168, so 'fallback'.
  expect_equal(result$state, "fallback")
  expect_null(result$previous_data)
  expect_equal(result$team_elo, 1800)
})

test_that("resolve_team_history returns 'new' when both inputs are empty", {
  result <- resolve_team_history(168, NULL, data.frame(TeamID = integer(), FinalELO = numeric()))

  expect_equal(result$state, "new")
  expect_null(result$previous_data)
  expect_null(result$team_elo)
})
```

#### Step 2: Run the test to verify it fails

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update.issue-73-split-process-league-teams"
Rscript -e 'testthat::test_file("tests/testthat/test-team-history-resolver.R")' 2>&1 | tail -8
```

Expected: All 6 tests FAIL with "could not find function 'resolve_team_history'" or "cannot open file ... team_history_resolver.R".

#### Step 3: Write the minimal implementation

Create `RCode/team_history_resolver.R` with this exact content:

```r
#' Resolve a team's history across previous-season data sources
#'
#' Looks up team_id first in previous_team_list (current-processing carryover
#' source) and falls back to final_elos (previous-season ELO source). Returns
#' a discriminated state the caller dispatches on.
#'
#' Extracted from process_league_teams in issue #73 to make existence
#' resolution testable in isolation.
#'
#' @param team_id Integer team ID to resolve.
#' @param previous_team_list Data frame with columns TeamID, ShortText, Promotion,
#'   InitialELO. May be NULL on the first season.
#' @param final_elos Data frame with columns TeamID, FinalELO. May be empty.
#' @return List with three slots:
#'   \describe{
#'     \item{state}{One of "carryover", "fallback", "new".}
#'     \item{previous_data}{Named list (short_name, promotion_value) when
#'       state == "carryover", else NULL.}
#'     \item{team_elo}{Numeric ELO from final_elos when available, else NULL.}
#'   }
#' @export
resolve_team_history <- function(team_id, previous_team_list, final_elos) {
  previous_data <- if (!is.null(previous_team_list)) {
    get_existing_team_data(team_id, previous_team_list)
  } else {
    NULL
  }

  elo_match <- final_elos$FinalELO[final_elos$TeamID == team_id]
  team_elo <- if (length(elo_match) > 0) elo_match[1] else NULL

  state <- if (!is.null(previous_data)) {
    "carryover"
  } else if (!is.null(team_elo)) {
    "fallback"
  } else {
    "new"
  }

  list(
    state = state,
    previous_data = previous_data,
    team_elo = team_elo
  )
}
```

#### Step 4: Run the test to verify it passes

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-team-history-resolver.R")' 2>&1 | tail -8
```

Expected: 6 PASS / 0 FAIL.

#### Step 5: Commit

```bash
git add RCode/team_history_resolver.R tests/testthat/test-team-history-resolver.R
git commit -m "$(cat <<'EOF'
refactor(#73): extract resolve_team_history pure function

Pulls existence resolution out of process_league_teams (currently 120 lines
of mixed concerns) into a dedicated pure function with a three-state
discriminated return: "carryover" (in previous_team_list), "fallback"
(only in final_elos), "new" (in neither).

Phase 1/3 of the split. The orchestrator still uses the inline logic;
that gets replaced in Phase 3 once both record builders exist.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `build_carryover_team_record` — pure record builder

**Why:** The "team has carryover or fallback data" branch of `process_league_teams` does three things: pick a `short_name` (from carryover record or generate fresh + uniquify), pick a `promotion_value`, and pick `initial_elo` (from `team_elo` or league-baseline). Pure inputs → pure output, so it's directly unit-testable with no stubs.

**Files:**
- Create: `tests/testthat/test-team-record-builder.R` (carryover tests only; new-team tests added in Task 3)
- Create: `RCode/team_record_builder.R` (carryover builder only; new-team builder added in Task 3)

#### Step 1: Write the failing test

Create `tests/testthat/test-team-record-builder.R` with this content:

```r
# Unit tests for build_carryover_team_record and build_new_team_record.
#
# These are the record-building units extracted from process_league_teams
# in issue #73. They take pre-resolved history and return a fully-formed
# team record. build_new_team_record takes the prompt as an injected
# parameter so tests can pass a stub function directly.

library(testthat)

source("../../RCode/api_service.R")           # convert_second_team_short_name, get_team_short_name, get_league_name
source("../../RCode/interactive_prompts.R")   # generate_unique_short_name, prompt_for_team_info
source("../../RCode/team_data_carryover.R")
source("../../RCode/team_history_resolver.R")
source("../../RCode/team_record_builder.R")

context("build_carryover_team_record — pure carryover/fallback builder")

test_that("build_carryover_team_record uses previous_data when state is 'carryover'", {
  team <- list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE)
  history <- list(
    state = "carryover",
    previous_data = list(short_name = "B04", promotion_value = 0),
    team_elo = 1800
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "78",
    liga3_baseline = 1100,
    existing_short_names = character()
  )

  expect_equal(result$id, 168)
  expect_equal(result$short_name, "B04")
  expect_equal(result$initial_elo, 1800)
  expect_equal(result$promotion_value, 0)
})

test_that("build_carryover_team_record uses baseline when team_elo is NULL", {
  team <- list(id = 167, name = "Hoffenheim", is_second_team = FALSE)
  history <- list(
    state = "carryover",
    previous_data = list(short_name = "HOF", promotion_value = 0),
    team_elo = NULL  # carryover with no final ELO
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "78",
    liga3_baseline = 1100,
    existing_short_names = character()
  )

  # league 78 (Bundesliga) baseline is 1500
  expect_equal(result$initial_elo, 1500)
  expect_equal(result$short_name, "HOF")
})

test_that("build_carryover_team_record uses liga3_baseline for league 80 with no team_elo", {
  team <- list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)
  history <- list(
    state = "carryover",
    previous_data = list(short_name = "FCE", promotion_value = 0),
    team_elo = NULL
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "80",
    liga3_baseline = 1046,
    existing_short_names = character()
  )

  expect_equal(result$initial_elo, 1046)
})

test_that("build_carryover_team_record generates fresh short_name when state is 'fallback'", {
  team <- list(id = 999, name = "Mystery FC", is_second_team = FALSE)
  history <- list(
    state = "fallback",
    previous_data = NULL,  # only in final_elos, no carryover record
    team_elo = 1234
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "78",
    liga3_baseline = 1100,
    existing_short_names = character()
  )

  # short_name comes from get_team_short_name on the API name
  expect_equal(result$short_name, get_team_short_name("Mystery FC"))
  expect_equal(result$initial_elo, 1234)
  expect_equal(result$promotion_value, 0)  # default for non-second-team
})

test_that("build_carryover_team_record uniquifies short_name in 'fallback' state when collision exists", {
  team <- list(id = 999, name = "Mystery FC", is_second_team = FALSE)
  history <- list(state = "fallback", previous_data = NULL, team_elo = 1234)

  collision <- get_team_short_name("Mystery FC")

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "78",
    liga3_baseline = 1100,
    existing_short_names = c(collision)
  )

  # uniquification happens via generate_unique_short_name
  expect_false(result$short_name == collision)
  expect_true(nchar(result$short_name) > 0)
})

test_that("build_carryover_team_record applies second-team conversion to short_name", {
  team <- list(id = 333, name = "Bayern München II", is_second_team = TRUE)
  history <- list(
    state = "carryover",
    previous_data = list(short_name = "FCB", promotion_value = -50),
    team_elo = 1500
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "80",
    liga3_baseline = 1046,
    existing_short_names = character()
  )

  # convert_second_team_short_name turns "FCB" into "FCB2" given is_second_team + promo=-50
  expect_equal(result$short_name, convert_second_team_short_name("FCB", TRUE, -50))
  expect_equal(result$promotion_value, -50)
})
```

#### Step 2: Run the test to verify it fails

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-team-record-builder.R")' 2>&1 | tail -8
```

Expected: All tests FAIL with "could not find function 'build_carryover_team_record'" or file-not-found.

#### Step 3: Write the minimal implementation

Create `RCode/team_record_builder.R` with this content (only the carryover builder for now; `build_new_team_record` is added in Task 3):

```r
#' Build a team record from resolved history (carryover or fallback path)
#'
#' Pure function: takes a team's API row, its resolved history (from
#' resolve_team_history), and the league context, and returns the final
#' team record. Handles both "carryover" (use previous_data verbatim) and
#' "fallback" (generate fresh short_name, default promotion_value) cases.
#'
#' Extracted from process_league_teams in issue #73 to make record
#' construction testable without stubs.
#'
#' @param team Named list from API: id, name, is_second_team.
#' @param history Result of resolve_team_history; state must be
#'   "carryover" or "fallback".
#' @param league_id League identifier ("78", "79", "80").
#' @param liga3_baseline Baseline ELO for Liga 3.
#' @param existing_short_names Character vector of already-assigned short
#'   names; used to uniquify newly-generated names in fallback state.
#' @return Named list: id, name, short_name, initial_elo, promotion_value.
#' @export
build_carryover_team_record <- function(team, history, league_id, liga3_baseline, existing_short_names) {
  if (!is.null(history$previous_data)) {
    short_name <- history$previous_data$short_name
    promotion_value <- history$previous_data$promotion_value
  } else {
    warning(paste("Team", team$id, "-", team$name, "not found in previous season, generating new data"))
    short_name <- get_team_short_name(team$name)
    if (short_name %in% existing_short_names) {
      short_name <- generate_unique_short_name(short_name, existing_short_names)
    }
    promotion_value <- ifelse(team$is_second_team, -50, 0)
  }

  final_short_name <- convert_second_team_short_name(
    short_name,
    team$is_second_team,
    promotion_value
  )

  initial_elo <- if (!is.null(history$team_elo) && length(history$team_elo) > 0) {
    history$team_elo[1]
  } else {
    if (league_id == 80 || league_id == "80") liga3_baseline else 1500
  }

  list(
    id = team$id,
    name = team$name,
    short_name = final_short_name,
    initial_elo = initial_elo,
    promotion_value = promotion_value
  )
}
```

#### Step 4: Run the test to verify it passes

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-team-record-builder.R")' 2>&1 | tail -8
```

Expected: 6 PASS / 0 FAIL. (Some tests may emit a warning from the "fallback" branch — that's intentional and documented; warnings don't fail testthat by default.)

If a warning is reported as a failure, wrap the relevant test calls in `expect_warning(... , regexp = NA)` *or* add `expect_warning(...)` at the appropriate site. Read the actual failure first; don't blindly suppress.

#### Step 5: Commit

```bash
git add RCode/team_record_builder.R tests/testthat/test-team-record-builder.R
git commit -m "$(cat <<'EOF'
refactor(#73): extract build_carryover_team_record pure function

Pulls the carryover/fallback record-construction branch out of
process_league_teams. Pure function: takes team + resolved history +
league context, returns the final team record. The "fallback" branch
preserves the existing warning ("not found in previous season,
generating new data") for diagnostic continuity.

Phase 2/3 of the split. build_new_team_record (which takes an injected
prompt_fn) lands in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `build_new_team_record` — prompt-injected new-team builder

**Why:** The "team has no history" branch is the one with side effects (interactive prompt). Injecting the prompt as a parameter (`prompt_fn`) makes the function testable without `mockery::stub` — tests pass a closure that returns a canned response.

**Files:**
- Modify: `tests/testthat/test-team-record-builder.R` (append new-team tests)
- Modify: `RCode/team_record_builder.R` (append new-team builder)

#### Step 1: Append failing tests for `build_new_team_record`

Open `tests/testthat/test-team-record-builder.R` and append (at the end of the file):

```r
context("build_new_team_record — prompt-injected new-team builder")

test_that("build_new_team_record calls prompt_fn and returns its short_name", {
  team <- list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)

  prompt_calls <- list()
  fake_prompt <- function(team_name, league, existing_short_names = NULL, baseline = NULL, retry_count = 0) {
    prompt_calls[[length(prompt_calls) + 1]] <<- list(
      team_name = team_name,
      league = league,
      existing_short_names = existing_short_names,
      baseline = baseline
    )
    list(short_name = "FCE", initial_elo = 1100, promotion_value = 0)
  }

  result <- build_new_team_record(
    team,
    league_id = "78",
    liga3_baseline = 1100,
    existing_short_names = c("B04", "HOF"),
    prompt_fn = fake_prompt
  )

  expect_equal(result$id, 1320)
  expect_equal(result$short_name, "FCE")
  expect_equal(result$initial_elo, 1100)
  expect_equal(result$promotion_value, 0)
  expect_length(prompt_calls, 1)
  expect_equal(prompt_calls[[1]]$team_name, "Energie Cottbus")
  expect_equal(prompt_calls[[1]]$league, "78")
  expect_equal(prompt_calls[[1]]$existing_short_names, c("B04", "HOF"))
  expect_equal(prompt_calls[[1]]$baseline, 1100)
})

test_that("build_new_team_record applies second-team short-name conversion", {
  team <- list(id = 444, name = "Borussia Dortmund II", is_second_team = TRUE)

  fake_prompt <- function(team_name, league, existing_short_names = NULL, baseline = NULL, retry_count = 0) {
    list(short_name = "BVB", initial_elo = 1046, promotion_value = -50)
  }

  result <- build_new_team_record(
    team,
    league_id = "80",
    liga3_baseline = 1046,
    existing_short_names = character(),
    prompt_fn = fake_prompt
  )

  # convert_second_team_short_name turns "BVB" into "BVB2" with is_second_team + promo=-50
  expect_equal(result$short_name, convert_second_team_short_name("BVB", TRUE, -50))
  expect_equal(result$promotion_value, -50)
})

test_that("build_new_team_record passes liga3_baseline to prompt_fn", {
  team <- list(id = 1234, name = "FC Test", is_second_team = FALSE)
  observed_baseline <- NULL

  fake_prompt <- function(team_name, league, existing_short_names = NULL, baseline = NULL, retry_count = 0) {
    observed_baseline <<- baseline
    list(short_name = "FCT", initial_elo = baseline, promotion_value = 0)
  }

  build_new_team_record(
    team,
    league_id = "80",
    liga3_baseline = 1234,
    existing_short_names = character(),
    prompt_fn = fake_prompt
  )

  expect_equal(observed_baseline, 1234)
})
```

#### Step 2: Run the test to verify the new tests fail

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-team-record-builder.R")' 2>&1 | tail -8
```

Expected: 6 PASS (Task 2's tests still green) plus 3 FAIL (the new tests can't find `build_new_team_record`).

#### Step 3: Append the implementation

Open `RCode/team_record_builder.R` and append (at the end of the file):

```r
#' Build a team record for a team with no carryover history
#'
#' Pure function modulo the injected prompt: takes a team's API row, the
#' league context, and a prompt function. The prompt function is the
#' single side-effecting dependency; tests pass a stub closure.
#'
#' Extracted from process_league_teams in issue #73 to make new-team
#' record construction testable without mockery::stub.
#'
#' @param team Named list from API: id, name, is_second_team.
#' @param league_id League identifier ("78", "79", "80").
#' @param liga3_baseline Baseline ELO for Liga 3.
#' @param existing_short_names Character vector of already-assigned short
#'   names; passed to prompt_fn so the prompt can warn on collisions.
#' @param prompt_fn Function with the signature of prompt_for_team_info:
#'   (team_name, league, existing_short_names, baseline, retry_count = 0)
#'   returning list(short_name, initial_elo, promotion_value).
#' @return Named list: id, name, short_name, initial_elo, promotion_value.
#' @export
build_new_team_record <- function(team, league_id, liga3_baseline, existing_short_names, prompt_fn) {
  cat("\n--- New Team Detected ---\n")
  cat("Team ID:", team$id, "\n")
  cat("Team Name:", team$name, "\n")
  cat("League:", get_league_name(league_id), "\n")

  team_info <- prompt_fn(team$name, league_id, existing_short_names, liga3_baseline)

  final_short_name <- convert_second_team_short_name(
    team_info$short_name,
    team$is_second_team,
    team_info$promotion_value
  )

  list(
    id = team$id,
    name = team$name,
    short_name = final_short_name,
    initial_elo = team_info$initial_elo,
    promotion_value = team_info$promotion_value
  )
}
```

#### Step 4: Run the test to verify it passes

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-team-record-builder.R")' 2>&1 | tail -8
```

Expected: 9 PASS / 0 FAIL (6 carryover + 3 new-team).

#### Step 5: Commit

```bash
git add RCode/team_record_builder.R tests/testthat/test-team-record-builder.R
git commit -m "$(cat <<'EOF'
refactor(#73): extract build_new_team_record with injected prompt_fn

Pulls the new-team interactive flow out of process_league_teams into a
prompt-injected pure function. Tests pass a closure as prompt_fn and
inspect its calls directly — no mockery::stub needed.

Phase 3/3 of the unit extraction. The orchestrator still has the old
inline body; it gets replaced in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: Wire the units into the orchestrator

### Task 4: Replace `process_league_teams` body with the thin orchestrator

**Why:** Now that all three units exist and pass their own tests, the orchestrator collapses to a loop that resolves history, dispatches to the right builder, and accumulates results.

**Files:**
- Modify: `RCode/season_processor.R:228-348`

#### Step 1: Read the current state of `RCode/season_processor.R` around lines 228–348

Confirm the function still has its original 120-line body. The signature is:

```r
process_league_teams <- function(teams, league_id, season, final_elos, liga3_baseline, previous_team_list = NULL)
```

#### Step 2: Replace the function body

Replace lines 228–348 with this implementation. The signature gains exactly one parameter (`prompt_fn = prompt_for_team_info`) so all existing callers continue to work without edits.

```r
#' Process teams for a league
#'
#' Thin orchestrator over resolve_team_history + build_*_team_record.
#' Refactored in issue #73 from a 120-line mixed-concern implementation.
#'
#' @param teams List of team records from API
#' @param league_id League ID ("78", "79", "80")
#' @param season Season year (currently unused; kept for caller signature stability)
#' @param final_elos Data frame of previous-season final ELOs
#' @param liga3_baseline Baseline ELO for Liga 3
#' @param previous_team_list Previous season's team list (or NULL on first season)
#' @param prompt_fn Function used to prompt for new-team data; default
#'   prompt_for_team_info. Tests can pass a stub closure to bypass I/O.
#' @return List of team records, or NULL on error
#' @export
process_league_teams <- function(teams, league_id, season, final_elos, liga3_baseline,
                                 previous_team_list = NULL,
                                 prompt_fn = prompt_for_team_info) {
  tryCatch({
    processed_teams <- list()
    existing_short_names <- character()

    for (i in seq_along(teams)) {
      team <- teams[[i]]
      history <- resolve_team_history(team$id, previous_team_list, final_elos)

      processed_team <- if (history$state == "new") {
        build_new_team_record(team, league_id, liga3_baseline,
                              existing_short_names, prompt_fn)
      } else {
        if (history$state == "carryover" && !is.null(history$team_elo)) {
          cat("Team", team$id, "(", team$name, "): Using final ELO",
              round(history$team_elo, 2), "\n")
        } else if (!is.null(history$team_elo)) {
          cat("Team", team$id, "(", team$name, "): Using final ELO",
              round(history$team_elo, 2), "\n")
        } else {
          baseline_elo <- if (league_id == 80 || league_id == "80") liga3_baseline else 1500
          cat("Team", team$id, "(", team$name, "): Using baseline ELO",
              round(baseline_elo, 2), "\n")
        }
        build_carryover_team_record(team, history, league_id,
                                    liga3_baseline, existing_short_names)
      }

      existing_short_names <- c(existing_short_names, processed_team$short_name)
      processed_teams[[i]] <- processed_team
    }

    return(processed_teams)
  }, error = function(e) {
    warning(paste("Error processing league", league_id, "teams:", e$message))
    return(NULL)
  })
}
```

The orchestrator is ~45 lines (slightly longer than the PRD's 30-line target, because the diagnostic `cat()` calls for the ELO selection are kept verbatim — this is the byte-identical-output safety net).

#### Step 3: Run the season-processor tests

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-processor.R")' 2>&1 | tail -10
```

Expected outcome: **either all PASS, or the `mockery::stub`-based tests fail because the stubs no longer take effect inside the new orchestrator path.** Both outcomes are valid signals — record exact PASS/FAIL counts and proceed.

If the stubs still work (because mockery's lookup walks far enough to catch the call inside `build_new_team_record`): proceed to Step 4.

If the stubs no longer work: Task 6 fixes them; for now, proceed.

#### Step 4: Run the regression tests

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-regression.R")' 2>&1 | tail -10
```

Same rationale as Step 3.

#### Step 5: Run the load-bearing snapshot test

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")' 2>&1 | tail -8
```

**Expected: 4 PASS / 0 FAIL with byte-identical CSV.** This is non-negotiable. If this fails, the orchestrator is producing different output and the refactor is wrong somewhere. **STOP and report**.

#### Step 6: Run the full testthat suite to capture the rest of the world

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -10
```

Expected: PASS count is *at least* 211 + 9 (the new unit tests) = 220, with FAIL at whatever the season-processor and regression tests showed. Record the exact counts.

#### Step 7: Commit

```bash
git add RCode/season_processor.R
git commit -m "$(cat <<'EOF'
refactor(#73): collapse process_league_teams onto the new units

Replaces the 120-line mixed-concern implementation with a thin
orchestrator (~45 lines) that calls resolve_team_history and dispatches
to build_new_team_record or build_carryover_team_record. The function
gains an optional prompt_fn parameter (default prompt_for_team_info)
so tests can bypass I/O without mockery::stub.

The CSV snapshot regression test passes byte-identically against the
fixture, confirming observable behavior is unchanged. Existing
mockery::stub-based tests in test-season-processor.R and
test-season-transition-regression.R may need re-targeting; that is
addressed in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Reconcile legacy stubs

### Task 5: Decide and apply the legacy-stub strategy

**Why:** Task 4 produces one of two outcomes for the existing `mockery::stub`-based tests. This task picks the right reconciliation and applies it.

**Files:**
- Possibly modify: `tests/testthat/test-season-processor.R`, `tests/testthat/test-season-transition-regression.R`

#### Step 1: Inspect Task 4's PASS/FAIL counts for the two test files

If Task 4's Step 3 + 4 reported all PASS for both files: **skip this task entirely** and jump to Task 6. Document in Task 6's commit body that no legacy-stub reconciliation was needed.

If any test failed because the stub no longer took effect: continue.

#### Step 2: Identify which stubs no longer work

For each failing test, look at the error message. The pattern to look for is "Mock not called" or a real (non-mocked) call to `prompt_for_team_info` (which usually crashes in non-interactive R because `readLines(stdin())` returns nothing, or the test reaches a `prompt_for_team_info` retry path).

Read the failing test and identify which stub line is now ineffective. Likely candidates:

- `stub(process_league_teams, "prompt_for_team_info", X)` — most likely to break, because `process_league_teams` no longer calls it directly.
- `stub(process_league_teams, "get_existing_team_data", X)` — likely still works, because `process_league_teams` still calls `resolve_team_history`, which calls `get_existing_team_data`. Mockery's stub walks the call chain.
- `stub(process_league_teams, "convert_second_team_short_name", X)` — depends on whether mockery walks into `build_*_record`. Test empirically.

#### Step 3: Apply the smallest possible fix

For each broken stub line, choose ONE of the two fixes:

**Fix A — re-target the stub at the unit that now does the call.** Example:

```r
# BEFORE
stub(process_league_teams, "prompt_for_team_info", mock_prompt)
result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_data)

# AFTER
stub(build_new_team_record, "prompt_fn", mock_prompt)
result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_data)
```

**Fix B — pass `prompt_fn` directly as a parameter.** Example:

```r
# BEFORE
mock_prompt <- mock(list(short_name = "FCE", initial_elo = 1100, promotion_value = 0))
stub(process_league_teams, "prompt_for_team_info", mock_prompt)
result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_data)

# AFTER
mock_prompt <- function(team_name, league, existing_short_names = NULL, baseline = NULL, retry_count = 0) {
  list(short_name = "FCE", initial_elo = 1100, promotion_value = 0)
}
result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_data,
                               prompt_fn = mock_prompt)
```

**Default to Fix B for `prompt_for_team_info` stubs** because it removes the indirection entirely and reads more clearly. Use Fix A only for stubs of `get_existing_team_data` or `convert_second_team_short_name` if those are also broken (they probably aren't).

For each test file, edit the failing tests as above. **Do NOT edit tests that still pass** — minimize the diff.

#### Step 4: Re-run both test files

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-processor.R")' 2>&1 | tail -10
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-regression.R")' 2>&1 | tail -10
```

Expected: both green. PASS count matches the baseline from Task 0.

#### Step 5: Re-run the load-bearing snapshot test

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")' 2>&1 | tail -8
```

Expected: still 4 PASS / 0 FAIL (this should not have been affected by test-only edits).

#### Step 6: Commit (only if any test file was modified)

If you modified test files in Step 3:

```bash
git add tests/testthat/test-season-processor.R tests/testthat/test-season-transition-regression.R
git commit -m "$(cat <<'EOF'
test(#73): re-target legacy mockery stubs at the new unit boundary

After process_league_teams was split into resolve_team_history and the
two record builders, some mockery::stub calls no longer captured the
intended call site. Switched the affected tests to pass prompt_fn
directly as a parameter (the cleanest path now that the orchestrator
exposes it).

Other stubs (get_existing_team_data, convert_second_team_short_name)
were left as-is because mockery's call-chain walk still finds them
through resolve_team_history and build_carryover_team_record.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If no test file was modified (Task 4 already passed everything): **skip this commit entirely** and proceed to Task 6.

---

## Phase 4: Final verification

### Task 6: Sweep, suite, summary

**Why:** Confirm the refactor is complete and observable behavior is unchanged.

**Files:**
- None modified — verification only.

#### Step 1: Confirm the new files exist and are sourced

```bash
cd "/Users/christophschwerdtfeger/Library/CloudStorage/Dropbox/Coding Projects/LeagueSimulator_Claude/League-Simulator-Update.issue-73-split-process-league-teams"
ls -la RCode/team_history_resolver.R RCode/team_record_builder.R
ls -la tests/testthat/test-team-history-resolver.R tests/testthat/test-team-record-builder.R
```

Expected: all four exist. The two `RCode/*.R` files are picked up automatically by `helper-test-setup.R`'s `source_rcode_modules()` because they don't match any exclude pattern.

#### Step 2: Confirm `process_league_teams` is now thin

```bash
awk '/^process_league_teams <- function/,/^}/' RCode/season_processor.R | wc -l
```

Expected: ~45 lines (down from ~120).

#### Step 3: Run the load-bearing snapshot test

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")' 2>&1 | tail -8
```

Expected: 4 PASS / 0 FAIL.

#### Step 4: Run the full testthat suite

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tee /tmp/issue-73-testthat.log | tail -10
```

Expected: PASS count is at minimum the Task-0 baseline (211) plus the new unit tests (9 more from Task 1 + Task 3). FAIL: 0. SKIP: 4 (unchanged).

#### Step 5: Look at the cumulative diff against `main`

```bash
git log --oneline main..HEAD
git diff --stat main..HEAD
```

Expected: 4–5 commits (one per task that touched code), modest insertions in the new files, large deletions in `season_processor.R` from the body replacement.

#### Step 6: Push the branch and open a draft PR

```bash
git push -u origin feature/issue-73-split-process-league-teams
gh pr create --draft --title "refactor(#73): split process_league_teams into testable units" --body "$(cat <<'EOF'
## Summary

Closes #73. Replaces the 120-line mixed-concern \`process_league_teams\` with three small, independently testable units behind a thin ~45-line orchestrator:

- \`resolve_team_history(team_id, previous_team_list, final_elos)\` — pure, returns a 3-state discriminated record.
- \`build_carryover_team_record(team, history, league_id, liga3_baseline, existing_short_names)\` — pure.
- \`build_new_team_record(team, league_id, liga3_baseline, existing_short_names, prompt_fn)\` — prompt-injected.

The public signature of \`process_league_teams\` gains exactly one optional parameter (\`prompt_fn = prompt_for_team_info\`); all existing callers and tests continue to work.

### What changed

- New: \`RCode/team_history_resolver.R\`, \`RCode/team_record_builder.R\`
- New: \`tests/testthat/test-team-history-resolver.R\` (6 tests), \`tests/testthat/test-team-record-builder.R\` (9 tests)
- Modified: \`RCode/season_processor.R\` — function body collapsed to a dispatcher
- Possibly modified: \`tests/testthat/test-season-processor.R\` and/or \`tests/testthat/test-season-transition-regression.R\` — re-targeted legacy stubs (only if Task 4 showed they were needed)

### Test plan

- [x] New unit tests: 6 + 9 = 15 PASS / 0 FAIL
- [x] \`tests/testthat/test-season-transition-csv-snapshot.R\` passes 4/4 byte-identically against the fixture — the load-bearing acceptance criterion
- [x] Full \`testthat::test_dir("tests/testthat")\` is green: FAIL 0, PASS ≥ 220
- [ ] CI green on this PR

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

#### Step 7: Mark PR ready when CI is green

```bash
gh pr ready
```

---

## Risks and Recovery

- **Risk:** Task 4's orchestrator produces subtly different output for an edge case the existing tests don't cover (e.g., a team that's in `final_elos` but with a trailing-NA `FinalELO` row). Mitigation: the load-bearing CSV snapshot test exercises the full season-transition path against a real-world cassette. If it stays byte-identical, edge cases that matter operationally are covered.

- **Risk:** A `mockery::stub` somewhere we didn't enumerate (e.g., in `tests/testthat/helper-*.R`) silently no-ops after the split. Mitigation: Task 6 Step 4 runs the full suite, which surfaces any such regression as a FAIL.

- **Risk:** A subtle order-of-operations bug — the original function appended to `existing_short_names` *inside* both branches at line 290 and 336. The orchestrator now appends in one place after the dispatch (cleaner, but a sequencing change). Mitigation: this is exactly what Task 4 Step 5's CSV snapshot catches. If the snapshot diverges, the dispatch-then-append order is the first thing to inspect.

- **Risk:** The orchestrator's `cat()` calls for ELO logging differ from the original by one whitespace character. Mitigation: the snapshot test compares CSV output, not stdout. Diagnostic output drift is acceptable; CSV drift is not.

---

## Self-Review

**Spec coverage** (vs. issue #73 acceptance criteria):

- ✅ Three units extracted: `resolve_team_history` (Task 1), `build_carryover_team_record` (Task 2), `build_new_team_record` (Task 3).
- ✅ Orchestrator collapses to a thin dispatcher: Task 4. ~45 lines, slightly above the PRD's 30-line target due to the `cat()` diagnostics, which the byte-identical-CSV requirement makes load-bearing.
- ✅ New tests exercise units directly without `mockery::stub`: Tasks 1 and 3 (which uses an injected closure as `prompt_fn`).
- ✅ Existing callers and tests continue to work unchanged: Task 4's orchestrator keeps the same positional signature and adds only an optional `prompt_fn`. Task 5 re-targets legacy stubs only if empirically necessary.
- ✅ Public signature gains exactly one optional parameter (`prompt_fn = prompt_for_team_info`): Task 4.
- ✅ `RCode/` flat layout, no new dependencies: Tasks 1–3.

**Placeholder scan:** No "TBD", "TODO", "implement later", or "similar to Task N" strings. Every step has either an exact command or a complete code block.

**Type/name consistency:**

- `resolve_team_history` returns `list(state, previous_data, team_elo)` — used identically in Task 2's tests, Task 3's signature, and Task 4's orchestrator dispatch.
- `previous_data` is `list(short_name, promotion_value)` — matches what `get_existing_team_data` returns at `RCode/team_data_carryover.R:114-117`.
- `state` values "carryover" / "fallback" / "new" — used consistently across Tasks 1, 2, 4.
- `prompt_fn` signature `(team_name, league, existing_short_names, baseline, retry_count = 0) -> list(short_name, initial_elo, promotion_value)` — matches `prompt_for_team_info` at `RCode/interactive_prompts.R:113`.

**One nuance flagged for the implementer:** the orchestrator's "carryover" diagnostics include both the `cat("... Using final ELO ...")` and `cat("... Using baseline ELO ...")` paths, just like the original. The condition that picks between them differs slightly between the original (`if (!is.null(team_elo) && length(team_elo) > 0)`) and the orchestrator (`if (history$state == "carryover" && !is.null(history$team_elo))`). I've kept both branches in the orchestrator code so output stays equivalent. If the snapshot test surfaces a difference, simplify the diagnostic block — it's not load-bearing for CSV output, only for human-readable logs.

---

## Plan complete

**Saved to:** `docs/superpowers/plans/2026-05-07-issue-73-split-process-league-teams.md` in the `feature/issue-73-split-process-league-teams` worktree.

Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

Which approach?
