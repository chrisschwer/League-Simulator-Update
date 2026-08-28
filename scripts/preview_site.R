#!/usr/bin/env Rscript

# Local preview of the static site: loads a saved simulation results file
# and renders it into a directory via generate_static_site(), then prints
# the path to the resulting index.html. No server, no browser autostart --
# open the printed path in a browser yourself.
#
# Usage: Rscript scripts/preview_site.R [ergebnis.Rds] [output_dir]
#   ergebnis.Rds  Path to a save()-image containing Ergebnis, Ergebnis2,
#                 Ergebnis3, Ergebnis3_Aufstieg (default: ShinyApp/data/Ergebnis.Rds)
#   output_dir    Directory to render into (default: a fresh tempdir())

args <- commandArgs(trailingOnly = TRUE)

ergebnis_path <- if (length(args) >= 1) args[[1]] else file.path("ShinyApp", "data", "Ergebnis.Rds")
output_dir <- if (length(args) >= 2) args[[2]] else file.path(tempdir(), "preview-site")

if (!file.exists(ergebnis_path)) {
  stop(sprintf("preview_site: Ergebnis-Datei nicht gefunden: %s", ergebnis_path))
}

script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
rcode_dir <- if (length(script_dir) == 1 && nzchar(script_dir)) {
  file.path(dirname(script_dir), "RCode")
} else {
  file.path("RCode")
}

source(file.path(rcode_dir, "generate_static_site.R"))

# generate_static_site.R uses load(), not readRDS() -- the fixture is a
# save()-image, not a single serialized object.
data_env <- new.env()
if (!load_results(ergebnis_path, data_env)) {
  stop(sprintf("preview_site: konnte Ergebnis-Datei nicht laden: %s", ergebnis_path))
}

required_vars <- c("Ergebnis", "Ergebnis2", "Ergebnis3")
missing_vars <- required_vars[!vapply(required_vars, exists, logical(1), envir = data_env)]
if (length(missing_vars) > 0) {
  stop(sprintf("preview_site: Ergebnis-Datei fehlen Variablen: %s",
               paste(missing_vars, collapse = ", ")))
}

Ergebnis3_Aufstieg <- if (exists("Ergebnis3_Aufstieg", envir = data_env)) {
  get("Ergebnis3_Aufstieg", envir = data_env)
} else {
  get("Ergebnis3", envir = data_env)
}

generate_static_site(
  Ergebnis = get("Ergebnis", envir = data_env),
  Ergebnis2 = get("Ergebnis2", envir = data_env),
  Ergebnis3 = get("Ergebnis3", envir = data_env),
  Ergebnis3_Aufstieg = Ergebnis3_Aufstieg,
  output_dir = output_dir
)

# The Bundesliga view has slug "index" (see RCode/league_views.R), so it
# renders to output_dir/index.html -- the landing page for the preview.
index_path <- file.path(output_dir, "index.html")
cat(index_path, "\n", sep = "")
