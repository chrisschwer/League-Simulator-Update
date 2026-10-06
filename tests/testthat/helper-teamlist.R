# Die TeamList der aktuellen Saison, fuer DATENPRUEFUNGEN (Issue #271).
#
# Datenpruefungen testen nicht Code, sondern die gepflegte Liste selbst:
# laedt sie, sind die Kuerzel je Liga eindeutig, traegt die Staffelzuordnung
# sie. Bis Oktober 2026 lasen sie fest verdrahtet TeamList_2026.csv -- nach
# dem naechsten Saisonwechsel haetten sie still eine Vorjahresdatei geprueft.
#
# Welche Datei gilt, entscheidet dieselbe Variable wie im Betrieb: SEASON
# (im Image per Dockerfile gesetzt). Ohne SEASON -- lokal der Normalfall --
# die neueste TeamList_<Jahr>.csv in RCode/. Entwuerfe (_entwurf) und
# Ligadateien (_League..._temp) zaehlen nicht.
#
# Fehlt die Datei, bricht der Helfer ab. Ein Skip waere hier ein gruenes
# Ergebnis fuer eine Pruefung, die gar nicht stattgefunden hat.
#
# Einheitentests nehmen NICHT diese Datei, sondern eine Fixture: Sie sollen
# Code pruefen und nicht kippen, wenn sich die Ligazusammensetzung aendert.
aktuelle_teamlist_pfad <- function() {
  verzeichnis <- test_path("..", "..", "RCode")
  season <- Sys.getenv("SEASON")

  pfad <- if (nzchar(season)) {
    file.path(verzeichnis, sprintf("TeamList_%s.csv", season))
  } else {
    kandidaten <- list.files(verzeichnis, pattern = "^TeamList_[0-9]{4}\\.csv$")
    if (length(kandidaten) == 0) {
      stop("aktuelle_teamlist_pfad: keine TeamList_<Jahr>.csv in RCode/", call. = FALSE)
    }
    file.path(verzeichnis, max(kandidaten))
  }

  if (!file.exists(pfad)) {
    stop(sprintf("aktuelle_teamlist_pfad: %s fehlt (SEASON = '%s')", pfad, season),
         call. = FALSE)
  }
  pfad
}
