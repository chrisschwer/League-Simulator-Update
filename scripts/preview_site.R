#!/usr/bin/env Rscript

# Local preview of the static site: loads a saved simulation results file
# and renders it into a directory via generate_static_site(), then prints
# the path to the resulting index.html. No server, no browser autostart --
# open the printed path in a browser yourself.
#
# Usage: Rscript scripts/preview_site.R [ergebnis.Rds] [output_dir]
#   ergebnis.Rds  Pfad zu einem save()-Image mit den Ergebnisobjekten
#                 (default: ShinyApp/data/Ergebnis.Rds)
#   output_dir    Zielverzeichnis (default: ein frisches tempdir())
#
# ALLE Objekte der Datei werden durchgereicht, nicht nur die vier alten:
# Seit Phase 5 gibt es zehn Ligen, und die Regionalliga-Seiten haengen
# zusaetzlich an berechneten Spalten (Ergebnis_rl_<staffel>_abstieg,
# _aufstieg). Wer nur Ergebnis/Ergebnis2/Ergebnis3 weiterreicht, bekommt
# von der Vorschau eine Seite, die es im Betrieb nicht gibt.
#
# Rueckwaertskompatibel: Eine Fixture mit nur den vier alten Objekten
# rendert weiterhin genau ihre vier Seiten -- der Generator ueberspringt
# jede Liga, deren Objekte fehlen.

args <- commandArgs(trailingOnly = TRUE)

ergebnis_path <- if (length(args) >= 1) args[[1]] else file.path("ShinyApp", "data", "Ergebnis.Rds")
output_dir <- if (length(args) >= 2) args[[2]] else file.path(tempdir(), "preview-site")

if (!file.exists(ergebnis_path)) {
  stop(sprintf("preview_site: Ergebnis-Datei nicht gefunden: %s", ergebnis_path))
}

# R kodiert Leerzeichen im --file=-Argument als "~+~" (siehe ?commandArgs).
# Ohne Dekodierung scheitert jeder Aufruf mit absolutem Pfad, sobald ein
# Verzeichnis ein Leerzeichen enthaelt -- etwa "Coding Projects/".
file_arg <- sub("^--file=", "",
                grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
file_arg <- gsub("~+~", " ", file_arg, fixed = TRUE)
script_dir <- dirname(file_arg)
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

# Objektname -> Schluessel: die Umkehrung von .ergebnis_objektname(). Sie
# wird aus derselben Funktion abgeleitet und nicht danebengeschrieben,
# damit Skript und Generator nicht auseinanderlaufen koennen. Der Generator
# legt die Objekte gleich wieder unter ihren Namen ab -- der Umweg ueber die
# Schluessel ist noetig, weil `ergebnisse` die Liste ist, die er nimmt.
ergebnis_schluessel <- function(objektname) {
  bekannt <- c("bundesliga", "zweite_bundesliga", "dritte_liga",
               "dritte_liga_aufstieg")
  treffer <- bekannt[vapply(bekannt, function(k) {
    identical(.ergebnis_objektname(k), objektname)
  }, logical(1))]
  if (length(treffer) == 1L) {
    return(treffer)
  }
  if (startsWith(objektname, "Ergebnis_")) {
    return(sub("^Ergebnis_", "", objektname))
  }
  NULL
}

ergebnisse <- list()
for (objektname in ls(data_env)) {
  key <- ergebnis_schluessel(objektname)
  if (!is.null(key)) {
    ergebnisse[[key]] <- get(objektname, envir = data_env)
  }
}

# Die 3. Liga ohne eigenen Aufstiegslauf: Frueher fiel die Aufstiegstabelle
# per Default-Argument auf Ergebnis3 zurueck. Ueber die Liste `ergebnisse`
# gibt es diesen Default nicht mehr, also steht er hier -- sonst
# uebersprungen der Generator die 3. Liga bei alten Fixtures.
if (is.null(ergebnisse[["dritte_liga_aufstieg"]])) {
  ergebnisse[["dritte_liga_aufstieg"]] <- ergebnisse[["dritte_liga"]]
}

generate_static_site(ergebnisse = ergebnisse, output_dir = output_dir)

# The Bundesliga view has slug "index" (see RCode/league_views.R), so it
# renders to output_dir/index.html -- the landing page for the preview.
index_path <- file.path(output_dir, "index.html")
cat(index_path, "\n", sep = "")
