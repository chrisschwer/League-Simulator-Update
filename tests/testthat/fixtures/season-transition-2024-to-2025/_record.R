# One-time cassette recording for the season-transition snapshot test.
# Run manually with: Rscript tests/testthat/fixtures/season-transition-2024-to-2025/_record.R
# Requires RAPIDAPI_KEY in the environment.
#
# After running, inspect the captured JSON files for any sensitive content,
# then commit. Re-run only when the api-football response shape changes.
#
# DESIGN NOTES:
# - httptest::capture_requests intercepts httr calls in-process only.
# - We source all modules from the project root first (before changing dir),
#   so module-level source() calls resolve correctly.
# - We then change cwd to csv_dir for the actual process_season_transition()
#   call so that CSV writes go to the temp dir (not the real RCode/).
# - TeamList_2024.csv is pre-copied to csv_dir/RCode/ as the script's input.
# - We do NOT pre-create fixture_abs so that with_mock_dir uses capture_requests.

stopifnot(Sys.getenv("RAPIDAPI_KEY") != "")

library(httptest)
library(withr)
suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(tidyr)
})

# All paths absolute
project_root <- normalizePath(getwd())
fixture_dir  <- "tests/testthat/fixtures/season-transition-2024-to-2025"
fixture_abs  <- file.path(project_root, fixture_dir)
rcode_abs    <- file.path(project_root, "RCode")

# Create a temp working directory with the expected RCode/ subdirectory
csv_dir   <- tempfile("season-transition-snapshot-")
rcode_tmp <- file.path(csv_dir, "RCode")
dir.create(rcode_tmp, recursive = TRUE)

# Copy TeamList_2024.csv (the script's input) into the temp RCode/
file.copy(file.path(rcode_abs, "TeamList_2024.csv"),
          file.path(rcode_tmp, "TeamList_2024.csv"))

# Ensure fixture parent dir exists but fixture_abs itself does NOT.
# with_mock_dir runs capture_requests when the dir does not exist.
# We keep the _record.R file safe by NOT deleting the fixture directory here.
# Instead we remove only cassette subdirectories (not the dir itself, since
# _record.R lives here). If this is a fresh run, nothing to remove.
for (d in list.dirs(fixture_abs, full.names = TRUE, recursive = FALSE)) {
  unlink(d, recursive = TRUE)
}
# Remove any cassette JSON files directly in fixture_abs
file.remove(list.files(fixture_abs, pattern = "\\.json$", full.names = TRUE))
# Remove snapshot if present (will be regenerated)
snapshot_path <- file.path(fixture_abs, "TeamList_2025.csv.snapshot")
if (file.exists(snapshot_path)) file.remove(snapshot_path)

# For with_mock_dir to use capture_requests, the fixture_abs dir must NOT exist.
# Since _record.R lives inside fixture_abs, we can't delete the whole dir.
# Instead we use capture_requests() directly and set the mock path manually.
cat("Recording to:", fixture_abs, "\n")
cat("Temp working dir:", csv_dir, "\n")

# ---- Source all modules from the project root (cwd = project_root here) ----
# Module-level source() calls in season_processor.R resolve against project root.
options(season_transition.non_interactive = TRUE)

required_modules <- c(
  "season_validation.R",
  "elo_aggregation.R",
  "api_service.R",
  "api_helpers.R",
  "interactive_prompts.R",
  "input_validation.R",
  "csv_generation.R",
  "file_operations.R",
  "season_processor.R",
  "league_processor.R",
  "error_handling.R",
  "logging.R",
  "input_handler.R",
  "team_config_loader.R",
  "team_data_carryover.R"
)

existing_modules <- c(
  "retrieveResults.R",
  "transform_data.R",
  "SpielCPP.R"
)

cat("Loading required modules from project root...\n")
for (module in required_modules) {
  module_path <- file.path(rcode_abs, module)
  if (file.exists(module_path)) {
    tryCatch(source(module_path), error = function(e) {
      cat("Note: sourcing", module, "raised:", conditionMessage(e), "\n")
    })
  } else {
    warning(paste("Module not found:", module))
  }
}

for (module in existing_modules) {
  module_path <- file.path(rcode_abs, module)
  if (file.exists(module_path)) {
    tryCatch(source(module_path), warning = function(w) {
      cat("Note: sourcing", module, ":", conditionMessage(w), "\n")
    })
  }
}
cat("Modules loaded.\n\n")

# ---- Run the season transition inside capture context ----
# Use capture_requests() directly with explicit path (avoids with_mock_dir's
# dir-existence check that would switch to with_mock_api).
result <- tryCatch({
  capture_requests(path = fixture_abs, {
    with_dir(csv_dir, {
      # Ensure non-interactive mode is set (survives into new frame)
      options(season_transition.non_interactive = TRUE)

      # Initialize logging (creates logs/ inside csv_dir)
      non_interactive_log <- create_non_interactive_log("2024", "2025")
      options(season_transition.log_file = non_interactive_log)

      cat("=== Starting Season Transition (cwd:", getwd(), ") ===\n")
      process_season_transition("2024", "2025")
    })
  })
}, error = function(e) {
  cat("ERROR during recording:", conditionMessage(e), "\n")
  list(success = FALSE, error = conditionMessage(e))
})

cat("\nRecording complete. Result success:", isTRUE(result$success), "\n")

if (!isTRUE(result$success)) {
  cat("Error:", result$error %||% "unknown", "\n")
}

# ---- Save snapshot CSV ----
src_csv <- file.path(csv_dir, "RCode", "TeamList_2025.csv")
dst_csv <- file.path(fixture_abs, "TeamList_2025.csv.snapshot")

if (file.exists(src_csv)) {
  file.copy(src_csv, dst_csv, overwrite = TRUE)
  cat("Snapshot saved to:", dst_csv, "\n")
  cat("Snapshot size:", file.size(dst_csv), "bytes\n")
  cat("Snapshot rows:", nrow(read.csv(dst_csv, sep = ";")), "\n")
} else {
  cat("WARNING: TeamList_2025.csv not found at", src_csv, "\n")
  cat("Files in RCode dir:\n")
  print(list.files(rcode_tmp))
}

# ---- Report cassette count ----
cassette_files <- list.files(fixture_abs, pattern = "\\.json$", recursive = TRUE, full.names = FALSE)
cat("Cassettes captured:", length(cassette_files), "\n")
if (length(cassette_files) > 0) {
  for (f in cassette_files) cat(" -", f, "\n")
}

# Probe value — not applicable for in-process recording
cat("Probe value: NA (in-process recording; SEASON_TRANSITION_ENGINE_PROBE not used)\n")

# ---- Cleanup ----
unlink(csv_dir, recursive = TRUE)
cat("Done.\n")
