#!/usr/bin/env Rscript

# Cleanup-Wrapper for incomplete season transitions.
#
# Removes intermediate league CSVs (TeamList_<season>_League<78|79|80>.csv)
# left behind when scripts/season_transition.R aborts before merging.
#
# When to use: only after a failed season transition. The successful path
# cleans up automatically — running this manually is a recovery tool.
#
# Does NOT touch: TeamList_<season>.csv (final), .tmp, .lock, or any file
# outside RCode/.
#
# Usage:
#   Rscript scripts/season_transition/cleanup.R 2025          # dry-run
#   Rscript scripts/season_transition/cleanup.R 2025 --confirm

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  cat("Usage: Rscript scripts/season_transition/cleanup.R <season> [--confirm]\n")
  quit(status = 1)
}

season <- args[1]
confirm <- "--confirm" %in% args[-1]

if (!grepl("^[0-9]{4}$", season)) {
  cat("Error: season must be a 4-digit year (e.g., 2025)\n")
  quit(status = 1)
}

# Narrow regex: match exactly the intermediate files the pipeline produces
# via generate_league_csv for leagues 78 (Bundesliga), 79 (2. Bundesliga),
# 80 (3. Liga). The final TeamList_<season>.csv is intentionally NOT matched.
pattern <- paste0("^TeamList_", season, "_League(78|79|80)\\.csv$")
search_dir <- "RCode"

matches <- list.files(search_dir, pattern = pattern, full.names = TRUE)

if (length(matches) == 0) {
  cat("No cleanup files found for season ", season, ".\n", sep = "")
  cat("(Searched ", search_dir, "/ for TeamList_", season,
      "_League(78|79|80).csv)\n", sep = "")
  quit(status = 0)
}

if (!confirm) {
  cat("Cleanup dry-run for season ", season, "\n", sep = "")
  cat("Pattern: TeamList_", season, "_League(78|79|80).csv in ",
      search_dir, "/\n", sep = "")
  cat("Would remove ", length(matches), " files:\n", sep = "")
  for (f in matches) cat("  ", f, "\n", sep = "")
  cat("Use --confirm to actually delete.\n")
  quit(status = 0)
}

# Confirmed: delete and report.
cat("Cleanup for season ", season, "\n", sep = "")
removed <- character(0)
for (f in matches) {
  if (file.remove(f)) {
    removed <- c(removed, f)
  } else {
    warning(paste("Could not remove:", f))
  }
}
cat("Removed ", length(removed), " files:\n", sep = "")
for (f in removed) cat("  ", f, "\n", sep = "")
quit(status = 0)
