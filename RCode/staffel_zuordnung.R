# Uebersetzung Stammregion -> Staffel-Index fuer die Abstiegskopplung.
#
# Die 3. Liga schickt ihre Absteiger in fuenf regionale Staffeln, je nach
# Stammregion des Vereins (Spalte `Region` der TeamList). Die Engine
# identifiziert Teams aber ueber die POSITION im Vektor -- wie bei
# elo_values, adj_points und elo_neutral. Zwischen beidem liegt diese
# Uebersetzung.
#
# Sie ist die gefaehrlichste Stelle der ganzen Kopplung: Verrutscht die
# Zuordnung, zaehlt die Engine die Absteiger der falschen Staffel zu, ohne
# dass irgendetwas fehlschlaegt. Deshalb bricht jede Unklarheit hier ab,
# statt einen Ersatzwert zu waehlen.
#
# Was die einzelne Staffel dann aus dieser Zahl macht, ist je Verband
# verschieden -- SuedWest/Nordost/Nord erhoehen ihre Absteigerzahl, West und
# Bayern vermindern sie stattdessen. Die amtlichen Regeln mit Fundstellen:
# docs/abstieg_aufstieg_RL_2026_2027.md

# Die Staffeln in fester Reihenfolge. Sie ist Vertrag: Der Index bestimmt,
# welche Zeile der Ergebnismatrix zu welcher Staffel gehoert. Aendert sie
# sich unbemerkt, werden die Zahlen vertauscht -- deshalb pinnt ein Test sie.
STAFFELN <- c("Nord", "Nordost", "West", "SuedWest", "Bayern")

#' Staffel-Index (0-basiert) zu einer Stammregion.
#'
#' @param region Zeichenvektor der Regionsnamen.
#' @return Integer-Vektor gleicher Laenge; NA fuer Teams ohne Region.
staffel_index <- function(region) {
  region <- as.character(region)

  # Teams ohne Region sind (noch) keiner Staffel zugeordnet -- in
  # TeamList_2026 betraf das anfangs sieben Drittliga-Teams. Sie bekommen NA
  # und duerfen nicht stillschweigend in Staffel 0 landen.
  leer <- is.na(region) | !nzchar(region)

  unbekannt <- !leer & !(region %in% STAFFELN)
  if (any(unbekannt)) {
    stop(sprintf(
      paste0(
        "staffel_index: unbekannte Region(en): %s. Erlaubt sind: %s. ",
        "Ein Tippfehler in der TeamList waere sonst ein Team, das ",
        "lautlos aus der Abstiegszaehlung verschwindet."
      ),
      paste(unique(region[unbekannt]), collapse = ", "),
      paste(STAFFELN, collapse = ", ")
    ), call. = FALSE)
  }

  idx <- match(region, STAFFELN) - 1L
  idx[leer] <- NA_integer_
  idx
}

#' Staffel-Index je Team, in der Reihenfolge des Spielplans.
#'
#' Die Engine ordnet ueber die Position zu: `group_of_team[i]` gehoert zum
#' i-ten Team des Spielplans -- NICHT zur i-ten Zeile der TeamList. Beide
#' Reihenfolgen unterscheiden sich in der Regel.
#'
#' WARUM `teams` AUF EINE LIGA GEFILTERT SEIN MUSS: `ShortText` ist in der
#' TeamList nicht eindeutig. "FCH" traegt 1. FC Heidenheim (Liga 79) und
#' Hansa Rostock (Liga 80); "VFB", "RWE", "SGS" und rund vierzig weitere
#' Kuerzel kommen ebenfalls mehrfach vor, quer ueber Herren-, Frauen- und
#' Zweitvertretungen. Innerhalb EINER Liga sind sie eindeutig.
#'
#' match() nahm hier still den ersten Treffer. Fuer die 3. Liga hiess das:
#' "FCH" wurde zu Heidenheim aufgeloest und Rostocks Abstiegsrisiko der
#' Staffel SuedWest zugeschlagen, waehrend die Nordost-Zeile der Auszaehlung
#' auf P(0 Absteiger) = exakt 1 stand. An der Regionalliga Nordost fehlte
#' dadurch die Abstiegszone auf Platz 17. Gefunden an der laufenden Seite --
#' die Tests reichten stets eine schon gefilterte TeamList herein und waren
#' deshalb gruen (Issue #185).
#'
#' Ein mehrdeutiges Kuerzel bricht jetzt ab, statt eine von zwei moeglichen
#' Antworten zu waehlen: Diese Datei ist laut ihrem eigenen Kopf die
#' gefaehrlichste Stelle der Kopplung, weil ein Fehler hier die Absteiger
#' der falschen Staffel zuzaehlt, ohne dass irgendetwas fehlschlaegt.
#'
#' @param team_shorttexts Kurznamen in Spielplan-Reihenfolge (die Teamspalten
#'   des Simulations-Data-Frames).
#' @param teams TeamList-Ausschnitt mit den Spalten ShortText und Region,
#'   auf GENAU EINE Liga gefiltert (s. oben).
#' @return Integer-Vektor, so lang wie `team_shorttexts`.
group_of_team <- function(team_shorttexts, teams) {
  idx <- match(team_shorttexts, teams$ShortText)

  if (any(is.na(idx))) {
    stop(sprintf(
      "group_of_team: Team(s) nicht in der TeamList: %s",
      paste(team_shorttexts[is.na(idx)], collapse = ", ")
    ), call. = FALSE)
  }

  # Nur die angefragten Kuerzel pruefen: Dass die TeamList als ganze
  # Dubletten enthaelt, ist normal und kein Fehler.
  mehrfach <- team_shorttexts[
    vapply(team_shorttexts, function(k) sum(teams$ShortText == k) > 1L,
           logical(1))
  ]
  if (length(mehrfach) > 0) {
    stop(sprintf(
      paste0(
        "group_of_team: mehrdeutige(s) Kuerzel: %s. `teams` muss auf eine ",
        "Liga gefiltert sein -- sonst waehlte match() still einen der ",
        "Treffer und zaehlte die Absteiger der falschen Staffel zu."
      ),
      paste(unique(mehrfach), collapse = ", ")
    ), call. = FALSE)
  }

  staffel_index(teams$Region[idx])
}
