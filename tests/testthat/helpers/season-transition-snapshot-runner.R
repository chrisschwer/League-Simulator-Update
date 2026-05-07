# Subprocess wrapper for the season-transition CSV snapshot test.
# Invoked by tests/testthat/test-season-transition-csv-snapshot.R via Rscript.
#
# Usage:
#   Rscript helpers/season-transition-snapshot-runner.R <project_root> <csv_dir> <fixture_dir>
#
# Environment vars expected:
#   RAPIDAPI_KEY (any non-empty value; httptest intercepts before the key is sent)

suppressPackageStartupMessages({
  library(httptest)
  library(withr)
  library(httr)
  library(jsonlite)
  library(tidyr)
})

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3)
project_root <- args[1]
csv_dir      <- args[2]
fixture_dir  <- args[3]

setwd(project_root)
# Normalize fixture_dir to absolute path: httptest resolves cassettes relative to
# cwd at request time, and cwd changes to csv_dir inside with_dir(). An absolute
# fixture_dir path ensures cassettes are always found regardless of cwd.
fixture_dir <- normalizePath(fixture_dir, mustWork = FALSE)
options(season_transition.non_interactive = TRUE)

# Source the same module set scripts/season_transition.R uses, from the project root.
modules <- c(
  "season_validation.R", "elo_aggregation.R", "api_service.R", "api_helpers.R",
  "interactive_prompts.R", "input_validation.R", "csv_generation.R", "file_operations.R",
  "season_processor.R", "league_processor.R", "error_handling.R", "logging.R",
  "input_handler.R", "team_config_loader.R", "team_data_carryover.R",
  "retrieveResults.R", "transform_data.R"
)
for (m in modules) {
  p <- file.path("RCode", m)
  if (file.exists(p)) {
    tryCatch(source(p), error = function(e) cat("source-err:", m, conditionMessage(e), "\n"))
  }
}

with_mock_dir(fixture_dir, {
  with_dir(csv_dir, {
    non_interactive_log <- create_non_interactive_log("2024", "2025")
    options(season_transition.log_file = non_interactive_log)
    result <- process_season_transition("2024", "2025")
    if (!isTRUE(result$success)) {
      cat("ERROR: process_season_transition returned success=FALSE\n")
      quit(status = 1)
    }
  })
})

cat("OK\n")
