# Welche Runden einer api-football-Antwort zur Hauptrunde gehoeren.
#
# Der Filter war bis Phase 0 des Ligen-Ausbaus eine POSITIVLISTE
# (startsWith "Regular Season"). Das traegt nur die drei Altligen: Die
# Regionalligen liefern ihre Spieltage als "Bayern - 34" oder "Nord - 20",
# Liga 84 wechselt zwischen den Saisons sogar die Sprache ("Nord" -> "North"),
# Liga 86 schreibt "Suedwest" mit Umlaut. Die Positivliste haette jedes
# Regionalliga-Spiel verworfen und klaglos eine leere Liga simuliert.
#
# Deshalb eine NEGATIVLISTE: Hauptrunde ist alles, was keine bekannte
# K.-o.-Runde ist. Das ueberlebt neue Staffelnamen ebenso wie Umbenennungen --
# eine Positivliste muesste jede Schreibweise vorher kennen.
#
# Die Kehrseite: Eine unbekannte K.-o.-Runde rutscht durch. Das ist die
# bewusst gewaehlte Fehlerrichtung -- ein zu viel simuliertes Playoff-Spiel
# faellt in der Tabelle auf, eine komplett leere Liga nicht.
#
# Zweite Haelfte des Schutznetzes ist assert_rounds_kept(): Wenn der Filter
# ALLE Spiele entfernt, ist das ein Abbruch mit den beobachteten Labels --
# nicht eine leere Liga, die weitersimuliert wird.
#
# Dieselbe Logik nutzt der Offline-Fixture-Cache (RCode/fixture_cache.R), der
# sie fuer die ELO-Kalibrierung eingefuehrt hat. Sie lebt hier, damit der
# Produktivpfad nicht am Cache-Modul haengt (ADR-0002-Abgrenzung dort).

# Runden, die keine Hauptrunde sind.
KO_ROUND_PATTERNS <- c(
  "Relegation",
  "Promotion",
  "Play-?off",
  "Final",
  "Semi-?final",
  "Quarter-?final",
  "8th Finals",
  "16th Finals",
  "Round of"
)

#' Ist diese Runde eine Hauptrundenpartie?
#'
#' @param round_label Zeichenvektor der Rundenbezeichnungen.
#' @return Logischer Vektor gleicher Laenge.
is_regular_season_round <- function(round_label) {
  if (length(round_label) == 0) return(logical(0))

  ko <- Reduce(
    `|`,
    lapply(KO_ROUND_PATTERNS, function(p) grepl(p, round_label, ignore.case = TRUE)),
    init = rep(FALSE, length(round_label))
  )

  !is.na(round_label) & nzchar(round_label) & !ko
}

#' Bricht ab, wenn der Rundenfilter alle Spiele entfernt hat.
#'
#' Ohne diese Pruefung simuliert eine Liga, deren Rundenbezeichnungen der
#' Filter nicht kennt, stillschweigend als leere Liga weiter. Die Meldung
#' nennt die beobachteten Labels, weil der Fehler sonst im Betrieb nicht zu
#' diagnostizieren ist -- man saehe nur, dass nichts da ist.
#'
#' Kein Abbruch bei leerer EINGABE: Eine Liga ohne angesetzte Spiele ist zum
#' Saisonstart normal und darf den Scheduler nicht anhalten.
#'
#' @param n_vorher Zahl der Spiele vor dem Filtern.
#' @param n_nachher Zahl der Spiele nach dem Filtern.
#' @param round_labels Die beobachteten Rundenbezeichnungen (ungefiltert).
#' @param context Aufrufende Funktion, erscheint in der Meldung.
assert_rounds_kept <- function(n_vorher, n_nachher, round_labels,
                               context = "Rundenfilter") {
  if (n_vorher == 0 || n_nachher > 0) {
    return(invisible(TRUE))
  }

  beobachtet <- unique(as.character(round_labels))
  beobachtet <- beobachtet[!is.na(beobachtet)]
  if (length(beobachtet) > 10) {
    beobachtet <- c(beobachtet[1:10], "...")
  }

  stop(sprintf(
    paste0(
      "%s: Der Rundenfilter hat alle %d Spiele verworfen -- die Liga waere ",
      "leer simuliert worden. Beobachtete Rundenbezeichnungen: %s. ",
      "Ist das eine unbekannte Hauptrunden-Schreibweise, gehoert sie NICHT ",
      "in KO_ROUND_PATTERNS (RCode/round_filter.R)."
    ),
    context, n_vorher, paste(beobachtet, collapse = ", ")
  ), call. = FALSE)
}
