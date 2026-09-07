# Aufstieg aus den Regionalligen in die 3. Liga.
#
# Rechtsgrundlage ist Par. 55b DFB-Spielordnung
# (docs/abstieg_aufstieg_RL_2026_2027.md, Abschnitt 1 und 3.1): Vier
# Aufsteiger. West und SuedWest steigen DAUERHAFT direkt auf. Von Nord,
# Nordost und Bayern bekommt jaehrlich EINE Staffel den dritten Direktplatz,
# die beiden anderen ermitteln in zwei Aufstiegsspielen den vierten
# Aufsteiger.
#
# Setzt STAFFELN (staffel_zuordnung.R) und pruefe_staffel()
# (rl_abstiegskopplung.R) voraus. Beide werden hier geladen, falls sie
# fehlen: Ohne das laesst sich die Datei nicht allein sourcen, und in den
# Tests haengt das Ergebnis davon ab, welche Datei zufaellig vorher lief --
# genau so war ein Test gruen, der es nicht haette sein duerfen.
# Muster wie in fixture_cache.R.
if (!exists("pruefe_staffel") || !exists("STAFFELN")) {
  local({
    d <- NULL
    for (f in rev(sys.frames())) {
      if (!is.null(f$ofile)) {
        d <- dirname(f$ofile)
        break
      }
    }
    if (is.null(d) || is.na(d) || !nzchar(d)) d <- "RCode"
    if (!exists("STAFFELN")) source(file.path(d, "staffel_zuordnung.R"))
    if (!exists("pruefe_staffel")) source(file.path(d, "rl_abstiegskopplung.R"))
  })
}

# Staffeln mit dauerhaftem Direktplatz -- sie rotieren nie (Par. 55b Nr. 2).
AUFSTIEG_DAUERPLAETZE <- c("West", "SuedWest")

# Die drei Staffeln, die den dritten Direktplatz unter sich ausrotieren.
AUFSTIEG_ROTIERENDE <- c("Nord", "Nordost", "Bayern")

#' Wer traegt in welcher Saison den dritten Direktplatz.
#'
#' Schluessel ist das Startjahr ("2026" = Saison 2026/27), Wert die Staffel
#' aus AUFSTIEG_ROTIERENDE.
#'
#' WARUM DAS DATEN SIND UND KEINE KONSTANTE IN DER REGISTRY: Die Reihenfolge
#' legt das DFB-Praesidium jaehrlich fest; sie steht in KEINER Ordnung
#' (Regeldoku 3.3). Nur belegte Saisons stehen hier -- eine unbekannte
#' Saison muss abbrechen und neu recherchiert werden, statt still mit dem
#' Vorjahreswert weiterzurechnen.
#'
#' 2026/27 amtlich belegt durch die BFV-Regelung (I. Nr. 1: Bayern gegen
#' Nord), woraus Nordost als dritter Direktaufsteiger zwingend folgt.
#' ACHTUNG: kicker und Wikipedia fuehren dieselbe Zuordnung um eine Saison
#' verschoben (Bayern direkt, Nord gegen Nordost) -- das ist falsch, die
#' Regeldoku markiert es ausdruecklich.
AUFSTIEGSROTATION <- c("2026" = "Nordost")

#' Aufstiegsmodus einer Saison.
#'
#' @param season Startjahr der Saison (2026 = 2026/27), Integer oder Double.
#' @param rotation Benannter Vektor Saison -> Rotationsstaffel.
#' @return list(direkt = drei Staffeln, playoff = die zwei uebrigen).
aufstiegsmodus <- function(season, rotation = AUFSTIEGSROTATION) {
  schluessel <- as.character(as.integer(season))

  if (!(schluessel %in% names(rotation))) {
    stop(sprintf(
      paste0(
        "aufstiegsmodus: fuer die Saison %s ist nicht belegt, welche Staffel ",
        "den dritten Direktplatz hat. Das beschliesst das DFB-Praesidium ",
        "jaehrlich und steht in keiner Ordnung -- es muss recherchiert und ",
        "in AUFSTIEGSROTATION eingetragen werden. Belegt sind: %s."
      ),
      schluessel,
      if (length(rotation)) paste(names(rotation), collapse = ", ") else "keine"
    ), call. = FALSE)
  }

  rotationsstaffel <- unname(rotation[[schluessel]])

  # Ein Dauerplatz oder ein Tippfehler als Rotationswert ist ein
  # Konfigurationsfehler: Er ergaebe eine Saison mit vier oder zwei
  # Direktaufsteigern, ohne dass etwas fehlschlaegt.
  if (!(rotationsstaffel %in% AUFSTIEG_ROTIERENDE)) {
    stop(sprintf(
      paste0(
        "aufstiegsmodus: '%s' kann den Rotationsplatz der Saison %s nicht ",
        "tragen. Es rotieren nur: %s. West und SuedWest haben nach ",
        "Par. 55b Nr. 2 einen Dauerplatz."
      ),
      rotationsstaffel, schluessel,
      paste(AUFSTIEG_ROTIERENDE, collapse = ", ")
    ), call. = FALSE)
  }

  list(
    direkt = c(AUFSTIEG_DAUERPLAETZE, rotationsstaffel),
    playoff = setdiff(AUFSTIEG_ROTIERENDE, rotationsstaffel)
  )
}

#' Aufstiegs-Slots einer Staffel in einer Saison.
#'
#' Die saisonabhaengige Quelle fuer die promotion_slots/playoff_slots, die
#' die Registry als abgeleiteten Stand mitfuehrt.
#'
#' @return list(promotion_slots = 0/1, playoff_slots = 1/0).
rl_aufstiegs_slots <- function(staffel, season, rotation = AUFSTIEGSROTATION) {
  staffel <- pruefe_staffel(staffel, "rl_aufstiegs_slots")
  modus <- aufstiegsmodus(season, rotation)

  if (staffel %in% modus$direkt) {
    list(promotion_slots = 1L, playoff_slots = 0L)
  } else {
    list(promotion_slots = 0L, playoff_slots = 1L)
  }
}

# --- Die Doppelsumme -------------------------------------------------------

#' Aufstiegswahrscheinlichkeit ueber die Aufstiegsspiele.
#'
#'   P(X steigt auf) = P(X Meister) * SUMME_Y P(Y Meister) * P(X gewinnt gegen Y)
#'
#' Exakt und nicht genaehert, weil die Meister-Ereignisse VERSCHIEDENER
#' Staffeln unabhaengig sind: Die Staffeln sind disjunkte Wettbewerbe ohne
#' ein gemeinsames Spiel. Innerhalb einer Staffel gilt das nicht -- dort
#' wird genau ein Team Meister, die Ereignisse schliessen einander aus.
#'
#' @param p_meister_x Benannter Vektor P(Meister) je Team der Staffel X.
#' @param p_meister_y Dito fuer die gegnerische Staffel Y.
#' @param p_sieg Matrix mit dimnames: p_sieg[x, y] = P(x setzt sich ueber
#'   zwei Spiele gegen y durch).
#' @return Benannter numerischer Vektor je Team von X.
aufstiegswahrscheinlichkeit <- function(p_meister_x, p_meister_y, p_sieg) {
  p_sieg <- as.matrix(p_sieg)

  # Zuordnung ueber NAMEN, nicht ueber Position: Die Prognosematrizen
  # kommen aus zwei getrennten Simulationslaeufen, deren Teamreihenfolge
  # nichts miteinander zu tun hat. Eine Positionszuordnung liefert Zahlen,
  # die plausibel aussehen und falsch sind.
  if (is.null(rownames(p_sieg)) || is.null(colnames(p_sieg))) {
    stop(
      paste0(
        "aufstiegswahrscheinlichkeit: p_sieg braucht Zeilen- und ",
        "Spaltennamen. Ohne Namen bliebe nur die Zuordnung ueber die ",
        "Position, und die ist zwischen zwei Simulationslaeufen zufaellig."
      ),
      call. = FALSE
    )
  }
  if (is.null(names(p_meister_x)) || is.null(names(p_meister_y))) {
    stop(
      "aufstiegswahrscheinlichkeit: p_meister_x und p_meister_y brauchen Namen.",
      call. = FALSE
    )
  }

  fehlend_x <- setdiff(names(p_meister_x), rownames(p_sieg))
  if (length(fehlend_x)) {
    stop(sprintf(
      "aufstiegswahrscheinlichkeit: keine Zeile in p_sieg fuer: %s.",
      paste(fehlend_x, collapse = ", ")
    ), call. = FALSE)
  }
  fehlend_y <- setdiff(names(p_meister_y), colnames(p_sieg))
  if (length(fehlend_y)) {
    stop(sprintf(
      "aufstiegswahrscheinlichkeit: keine Spalte in p_sieg fuer: %s.",
      paste(fehlend_y, collapse = ", ")
    ), call. = FALSE)
  }

  if (any(is.na(p_sieg)) || any(p_sieg < 0) || any(p_sieg > 1)) {
    stop(sprintf(
      paste0(
        "aufstiegswahrscheinlichkeit: p_sieg enthaelt Werte ausserhalb ",
        "[0, 1]: %s."
      ),
      paste(format(p_sieg[is.na(p_sieg) | p_sieg < 0 | p_sieg > 1]),
            collapse = ", ")
    ), call. = FALSE)
  }

  # Ueber die Namen ausgerichtet, dann das Matrixprodukt: Zeile x mal
  # Vektor der P(Y Meister) ist genau die innere Summe.
  block <- p_sieg[names(p_meister_x), names(p_meister_y), drop = FALSE]
  gegner <- as.vector(block %*% as.numeric(p_meister_y))

  p <- as.numeric(p_meister_x) * gegner
  names(p) <- names(p_meister_x)
  p
}

# --- Die ganze Kette -------------------------------------------------------

#' Aufstiegsprognose einer Regionalliga-Staffel.
#'
#' @param staffel Name einer Staffel aus STAFFELN.
#' @param prognosen Benannte Liste Staffel -> Prognosematrix (Teams x
#'   Plaetze, rownames = Teams). Erwartet wird die Aufstiegs-Variante, in
#'   der Zweitvertretungen bereits ausgeschlossen sind.
#' @param season Startjahr der Saison.
#' @param p_sieg Matrix der Zweikampfquoten fuer die Playoff-Paarung; Zeilen
#'   = Teams der in STAFFELN frueheren Staffel, Spalten = Teams der
#'   spaeteren. Fuer die Gegenrichtung gilt 1 - t(p_sieg): Ueber zwei Spiele
#'   gibt es keinen Unentschieden-Ausgang.
#' @param rotation Benannter Vektor Saison -> Rotationsstaffel.
#' @param paarungen Optional das data.frame der Tor-Raten je Paarung, wie
#'   zweikampf_paarungen_rust() es liefert (Spalten a, b, hin_a, hin_b,
#'   rueck_a, rueck_b, neutral_a, neutral_b). Daraus wird p_sieg ueber
#'   p_sieg_matrix() hergeleitet -- a = Teams der in STAFFELN frueheren
#'   Staffel, b = Teams der spaeteren, dieselbe Orientierung wie p_sieg.
#'   Ein explizit uebergebenes p_sieg hat Vorrang; liegt beides nicht vor,
#'   bricht die Funktion ab.
#' @return data.frame mit rownames = Teams und der Spalte "Aufstieg".
rl_aufstiegsprognose <- function(staffel, prognosen, season, p_sieg = NULL,
                                 rotation = AUFSTIEGSROTATION,
                                 paarungen = NULL) {
  staffel <- pruefe_staffel(staffel, "rl_aufstiegsprognose")
  modus <- aufstiegsmodus(season, rotation)

  prognose <- prognosen[[staffel]]
  if (is.null(prognose)) {
    stop(sprintf(
      "rl_aufstiegsprognose: keine Prognosematrix fuer die Staffel %s.",
      staffel
    ), call. = FALSE)
  }
  p_meister <- meisterwahrscheinlichkeit(prognose)

  # Direktaufsteiger: P(Aufstieg) ist P(Meister), ohne Zwischenschritt.
  if (staffel %in% modus$direkt) {
    return(data.frame(Aufstieg = p_meister, row.names = names(p_meister)))
  }

  gegner <- setdiff(modus$playoff, staffel)
  prognose_gegner <- prognosen[[gegner]]
  if (is.null(prognose_gegner)) {
    stop(sprintf(
      paste0(
        "rl_aufstiegsprognose: %s bestreitet %d/%d die Aufstiegsspiele gegen ",
        "%s, aber es liegt keine Prognosematrix fuer %s vor."
      ),
      staffel, as.integer(season), as.integer(season) + 1L, gegner, gegner
    ), call. = FALSE)
  }

  # Vorrang: ein explizit uebergebenes p_sieg gilt unveraendert. Erst wenn
  # keins vorliegt, wird es aus den Tor-Raten hergeleitet. Die Reihenfolge
  # ist bewusst: Wer die Quote selbst kennt (Kalibrierung, Testfixture,
  # Sonderregel), soll sie nicht gegen eine Herleitung verteidigen muessen.
  if (is.null(p_sieg) && !is.null(paarungen)) {
    p_sieg <- p_sieg_matrix(paarungen)

    # Die Herleitung deckt nur die Teams ab, die in paarungen vorkommen.
    # Fehlt eines, waere die Doppelsumme unvollstaendig -- und zwar
    # lautlos, weil sie ueber die vorhandenen Namen einfach weiterrechnete.
    # Beide Seiten werden hier geprueft, damit der Fehler das TEAM nennt
    # und nicht erst weiter unten die fehlende Zeile oder Spalte.
    frueher <- if (match(staffel, STAFFELN) < match(gegner, STAFFELN)) {
      staffel
    } else {
      gegner
    }
    spaeter <- setdiff(c(staffel, gegner), frueher)

    fehlend <- c(
      setdiff(names(meisterwahrscheinlichkeit(prognosen[[frueher]])),
              rownames(p_sieg)),
      setdiff(names(meisterwahrscheinlichkeit(prognosen[[spaeter]])),
              colnames(p_sieg))
    )
    if (length(fehlend)) {
      stop(sprintf(
        paste0(
          "rl_aufstiegsprognose: in paarungen fehlen die Tor-Raten fuer: %s. ",
          "Ohne sie bliebe die Doppelsumme unvollstaendig, ohne dass etwas ",
          "fehlschlaegt."
        ),
        paste(fehlend, collapse = ", ")
      ), call. = FALSE)
    }
  }

  # Keine erfundene 50:50. Wer die Zweikampfquote nicht liefert, bekommt
  # keine Zahl -- so wie die Bayern-Relegation nach unten nicht aufgeloest
  # wird, weil wir die Bayernligen nicht simulieren.
  if (is.null(p_sieg)) {
    stop(sprintf(
      paste0(
        "rl_aufstiegsprognose: %s bestreitet die Aufstiegsspiele gegen %s. ",
        "Ohne p_sieg gibt es keine Aufstiegswahrscheinlichkeit -- eine ",
        "angenommene Gewinnquote waere erfunden."
      ),
      staffel, gegner
    ), call. = FALSE)
  }

  # p_sieg ist in STAFFELN-Reihenfolge orientiert: Zeilen = fruehere
  # Staffel. Ist die gefragte Staffel die spaetere, wird gedreht -- ueber
  # zwei Spiele gibt es keinen Unentschieden-Ausgang, also 1 - t(p_sieg).
  p_sieg <- as.matrix(p_sieg)
  if (match(staffel, STAFFELN) > match(gegner, STAFFELN)) {
    p_sieg <- 1 - t(p_sieg)
  }

  p <- aufstiegswahrscheinlichkeit(
    p_meister, meisterwahrscheinlichkeit(prognose_gegner), p_sieg
  )
  data.frame(Aufstieg = p, row.names = names(p))
}

#' P(Meister) je Team: die erste Spalte der Prognosematrix.
meisterwahrscheinlichkeit <- function(prognose) {
  prognose <- as.matrix(prognose)
  if (ncol(prognose) < 1L) {
    stop(
      "rl_aufstiegsprognose: die Prognosematrix hat keine Platzspalten.",
      call. = FALSE
    )
  }
  p <- prognose[, 1L]
  names(p) <- rownames(prognose)
  p
}
