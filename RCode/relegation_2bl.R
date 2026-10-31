# Die Relegationen der Profiligen: Bundesliga 16. gegen 2. Bundesliga 3. und
# 2. Bundesliga 16. gegen 3. Liga 3. (berechtigter Dritter).
#
# Bis hierher zeigten die Seiten fuer diese Plaetze nur P(Platz 16) bzw.
# P(Platz 3) -- die Platzsumme, nicht den Ausgang des Duells. Hier entsteht
# die Zahl dahinter: P(Aufstieg gesamt) = P(Platz 1-2) + P(Platz 3) * P(Sieg),
# P(Abstieg gesamt) = P(Platz 17-18) + P(Platz 16) * P(Niederlage).
#
# WARUM DAS EXAKT IST: Die drei Ligen teilen kein Spiel. Wer in der einen
# Liga auf Platz 16 steht, ist unabhaengig davon, wer in der anderen Dritter
# wird -- dieselbe Unabhaengigkeit wie bei der Abstiegskopplung (ADR 0006).
# Das Duell haengt nur von den beiden beteiligten Mannschaften ab, und die
# Verteilung der Gegner ist die Randverteilung der Gegenliga.
#
# MODELL (Annahmen, in docs/modellannahmen-rl-kopplung.md dokumentiert):
#   - Hin- und Rueckspiel, gewertet wird die Gesamttordifferenz, keine
#     Auswaertstorregel (aufstiegsspiele.R).
#   - Heimrecht: Hinspiel bei der Aufstiegsseite (Drittligist) bzw. bei der
#     Abstiegsseite (Bundesligist) -- siehe RELEGATIONEN. Die Quelle sind
#     Suchtreffer-Ausschnitte der DFB/DFL-Seiten, nicht der Wortlaut der
#     Spielordnung; vor dem Verlassen darauf gegen die Spielordnung pruefen.
#   - Verlaengerung MIT Heimvorteil des Rueckspiel-Gastgebers.
#   - Das Rueckspiel-Heimrecht nach Ruhetagen ist nicht modelliert.
#   - AKTUELLE ELO, nicht die ELO am Saisonende je Iteration (wie bei den
#     Aufstiegsspielen Nord gegen Bayern).
#   - Ist der Dritte der 3. Liga eine gesperrte Zweitvertretung, tritt der
#     naechste Berechtigte an: Die Verteilung kommt aus Ergebnis3_Aufstieg,
#     in dem Zweitvertretungen unten stehen.
#
# Wie aufstiegsspiele.R kennt diese Datei keine Tormodell-Konstante: Die
# Tor-Raten holt zweikampf_paarungen_rust() beim Rust-Server (ADR 0002).
#
# Setzt aufstiegsspiele.R, rust_integration.R und league_registry.R voraus.

# Die beiden Duelle. `abstieg`/`aufstieg` sind Registry-Schluessel der Liga,
# deren Teilnehmer absteigen bzw. aufsteigen wuerde; `hinspiel_bei` sagt, wer
# das Hinspiel zu Hause hat (der Rueckspiel-Gastgeber bekommt damit auch die
# Verlaengerung).
RELEGATIONEN <- list(
  bundesliga_zweite = list(
    abstieg = "bundesliga", aufstieg = "zweite_bundesliga",
    hinspiel_bei = "abstiegsseite"
  ),
  zweite_dritte = list(
    abstieg = "zweite_bundesliga", aufstieg = "dritte_liga",
    hinspiel_bei = "aufstiegsseite"
  )
)

#' Plaetze einer Liga aus der Registry.
#'
#' Aus promotion_slots, relegation_slots und der Teamzahl, nicht als
#' dritte Kopie der Zahlen aus league_views(): Platz 3 der 2. Bundesliga ist
#' promotion_slots + 1, Platz 16 ist n - relegation_slots.
#'
#' @param key Registry-Schluessel.
#' @param n Zahl der Teams der Prognosematrix.
#' @return list(aufstieg = Plaetze mit direktem Aufstieg, relegation_hoch =
#'   Platz der Relegation nach oben, relegation_runter = Platz der Relegation
#'   nach unten (NA, wo es keine gibt), abstieg = Plaetze mit direktem
#'   Abstieg).
relegation_plaetze <- function(key, n) {
  eintrag <- league_registry()[[key]]
  aufstieg_n <- as.integer(eintrag$promotion_slots)
  abstieg_n <- as.integer(eintrag$relegation_slots)
  list(
    aufstieg = seq_len(aufstieg_n),
    relegation_hoch = aufstieg_n + 1L,
    relegation_runter = if (identical(key, "dritte_liga")) {
      NA_integer_
    } else {
      n - abstieg_n
    },
    abstieg = seq.int(n - abstieg_n + 1L, n)
  )
}

#' Ausgang einer Relegation fuer beide Seiten.
#'
#' @param p_abstiegsplatz Benannter Vektor: P(Team steht auf dem
#'   Relegationsplatz der oberen Liga), Namen = Kurznamen. Summe etwa 1.
#' @param p_aufstiegsplatz Dasselbe fuer den Relegationsplatz der unteren
#'   Liga.
#' @param elo_abstieg,elo_aufstieg Benannte aktuelle ELO-Vektoren der beiden
#'   Ligen (Namen wie oben).
#' @param hinspiel_bei "abstiegsseite" oder "aufstiegsseite".
#' @param tore_slope,tore_intercept Abweichendes Tormodell (ADR 0004);
#'   NULL heisst: Defaults des Servers.
#' @param paarungen_fn Funktion wie zweikampf_paarungen_rust(); als Argument
#'   nur, damit Tests ohne Server rechnen.
#' @return list(p_aufstieg_sieg, p_abstieg_niederlage): BEDINGTE
#'   Wahrscheinlichkeiten, je Team der unteren bzw. oberen Liga, dass es das
#'   Duell gewinnt bzw. verliert -- unter der Bedingung, dass es antritt.
#'   Teams ohne Masse auf dem Relegationsplatz tragen 0.
relegation_duell <- function(p_abstiegsplatz, p_aufstiegsplatz,
                             elo_abstieg, elo_aufstieg,
                             hinspiel_bei = c("aufstiegsseite", "abstiegsseite"),
                             tore_slope = NULL, tore_intercept = NULL,
                             paarungen_fn = zweikampf_paarungen_rust) {
  hinspiel_bei <- match.arg(hinspiel_bei)

  .pruefe_relegation_eingang(p_abstiegsplatz, elo_abstieg, "abstieg")
  .pruefe_relegation_eingang(p_aufstiegsplatz, elo_aufstieg, "aufstieg")

  # Nur Teams mit Masse antreten lassen. Monte-Carlo-Wahrscheinlichkeiten
  # sind Vielfache von 1/n; "> 0" laesst also exakt die Teams weg, die in
  # keiner Iteration auf dem Platz standen -- ohne Fehler.
  oben <- p_abstiegsplatz[p_abstiegsplatz > 0]
  unten <- p_aufstiegsplatz[p_aufstiegsplatz > 0]

  p_aufstieg_sieg <- stats::setNames(numeric(length(p_aufstiegsplatz)),
                                     names(p_aufstiegsplatz))
  p_abstieg_niederlage <- stats::setNames(numeric(length(p_abstiegsplatz)),
                                          names(p_abstiegsplatz))
  if (length(oben) == 0L || length(unten) == 0L) {
    return(list(p_aufstieg_sieg = p_aufstieg_sieg,
                p_abstieg_niederlage = p_abstieg_niederlage))
  }

  # Erstgenannte Seite = Gastgeber des Hinspiels (so liest es
  # zweikampf_paarungen_rust()). M[a, b] = P(a setzt sich gegen b durch).
  if (identical(hinspiel_bei, "aufstiegsseite")) {
    paarungen <- paarungen_fn(elo_aufstieg[names(unten)],
                              elo_abstieg[names(oben)],
                              tore_slope = tore_slope,
                              tore_intercept = tore_intercept)
    m <- p_sieg_matrix(paarungen, verlaengerung = "rueckspiel")
    p_unten_gewinnt <- m[names(unten), names(oben), drop = FALSE]
  } else {
    paarungen <- paarungen_fn(elo_abstieg[names(oben)],
                              elo_aufstieg[names(unten)],
                              tore_slope = tore_slope,
                              tore_intercept = tore_intercept)
    m <- p_sieg_matrix(paarungen, verlaengerung = "rueckspiel")
    p_unten_gewinnt <- 1 - t(m[names(oben), names(unten), drop = FALSE])
  }

  # Gegnerverteilung: Randverteilung der Gegenliga, auf 1 normiert.
  w_oben <- oben / sum(oben)
  w_unten <- unten / sum(unten)

  p_aufstieg_sieg[names(unten)] <- as.numeric(p_unten_gewinnt %*% w_oben)
  # Die obere Seite verliert genau dann, wenn die untere gewinnt: Ueber die
  # Gegnerverteilung der unteren Liga summiert ist das die Spaltensumme von
  # p_unten_gewinnt, nicht ihr Komplement.
  p_abstieg_niederlage[names(oben)] <-
    as.numeric(t(p_unten_gewinnt) %*% w_unten)

  list(p_aufstieg_sieg = p_aufstieg_sieg,
       p_abstieg_niederlage = p_abstieg_niederlage)
}

#' Die berechneten Spalten "Aufstieg gesamt" / "Abstieg gesamt" je Liga.
#'
#' @param prognosen Benannte Liste der Prognosematrizen (Teams x Plaetze) mit
#'   den Schluesseln "bundesliga", "zweite_bundesliga" und "dritte_liga".
#'   Fuer die 3. Liga ist das die Aufstiegsprognose (Ergebnis3_Aufstieg), in
#'   der Zweitvertretungen unten stehen.
#' @param elos Benannte Liste der aktuellen ELO-Vektoren, gleiche Schluessel.
#' @return Benannte Liste von data.frames, Zeilen = Teams der Liga:
#'   bundesliga ("Abstieg gesamt"), zweite_bundesliga ("Aufstieg gesamt",
#'   "Abstieg gesamt"), dritte_liga ("Aufstieg gesamt"). Eine Liga fehlt,
#'   wenn ihre Eingaben fehlen.
relegation_spalten <- function(prognosen, elos, tore_args = list(),
                               paarungen_fn = zweikampf_paarungen_rust) {
  ergebnis <- list()
  duelle <- list()

  for (name in names(RELEGATIONEN)) {
    r <- RELEGATIONEN[[name]]
    p_ab <- prognosen[[r$abstieg]]
    p_auf <- prognosen[[r$aufstieg]]
    if (is.null(p_ab) || is.null(p_auf) ||
          is.null(elos[[r$abstieg]]) || is.null(elos[[r$aufstieg]])) {
      next
    }
    ab <- as.matrix(p_ab)
    auf <- as.matrix(p_auf)
    pl_ab <- relegation_plaetze(r$abstieg, ncol(ab))
    pl_auf <- relegation_plaetze(r$aufstieg, ncol(auf))

    # Der Relegationsplatz der oberen Liga ist ihr Platz "nach unten", der
    # der unteren Liga ihr Platz "nach oben".
    tormodell <- tore_args[[r$aufstieg]]
    duelle[[name]] <- relegation_duell(
      p_abstiegsplatz = ab[, pl_ab$relegation_runter],
      p_aufstiegsplatz = auf[, pl_auf$relegation_hoch],
      elo_abstieg = elos[[r$abstieg]], elo_aufstieg = elos[[r$aufstieg]],
      hinspiel_bei = r$hinspiel_bei,
      tore_slope = tormodell$tore_slope,
      tore_intercept = tormodell$tore_intercept,
      paarungen_fn = paarungen_fn
    )
  }

  summe <- function(m, plaetze) rowSums(m[, plaetze, drop = FALSE])

  # Aufstieg gesamt: direkte Plaetze + Relegationsplatz * P(Sieg).
  aufstieg_gesamt <- function(key, duell) {
    m <- as.matrix(prognosen[[key]])
    pl <- relegation_plaetze(key, ncol(m))
    summe(m, pl$aufstieg) +
      m[, pl$relegation_hoch] * duell$p_aufstieg_sieg[rownames(m)]
  }
  abstieg_gesamt <- function(key, duell) {
    m <- as.matrix(prognosen[[key]])
    pl <- relegation_plaetze(key, ncol(m))
    summe(m, pl$abstieg) +
      m[, pl$relegation_runter] * duell$p_abstieg_niederlage[rownames(m)]
  }

  bl <- duelle$bundesliga_zweite
  z <- duelle$zweite_dritte
  if (!is.null(bl)) {
    ergebnis$bundesliga <- data.frame(
      `Abstieg gesamt` = abstieg_gesamt("bundesliga", bl),
      check.names = FALSE
    )
  }
  zweite <- list()
  if (!is.null(bl)) {
    zweite[["Aufstieg gesamt"]] <- aufstieg_gesamt("zweite_bundesliga", bl)
  }
  if (!is.null(z)) {
    zweite[["Abstieg gesamt"]] <- abstieg_gesamt("zweite_bundesliga", z)
    ergebnis$dritte_liga <- data.frame(
      `Aufstieg gesamt` = aufstieg_gesamt("dritte_liga", z),
      check.names = FALSE
    )
  }
  if (length(zweite) > 0L) {
    ergebnis$zweite_bundesliga <- data.frame(zweite, check.names = FALSE)
  }
  ergebnis
}

.pruefe_relegation_eingang <- function(p, elo, seite) {
  if (is.null(names(p)) || is.null(names(elo))) {
    stop(sprintf(
      paste0(
        "relegation_duell: p_%splatz und elo_%s brauchen Teamnamen. Ohne ",
        "sie bliebe nur die Zuordnung ueber die Position."
      ),
      seite, seite
    ), call. = FALSE)
  }
  fehlend <- setdiff(names(p)[p > 0], names(elo))
  if (length(fehlend)) {
    stop(sprintf(
      paste0(
        "relegation_duell: fuer %s fehlt die aktuelle ELO (Seite '%s'). ",
        "Ein Team ohne ELO wuerde still aus dem Duell fallen."
      ),
      paste(fehlend, collapse = ", "), seite
    ), call. = FALSE)
  }
  invisible(p)
}
