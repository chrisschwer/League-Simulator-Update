# Abstiegskopplung der Regionalligen an die 3. Liga.
#
# Wie viele Teams aus einer Regionalliga absteigen, steht vor der Saison
# nicht fest: Es haengt davon ab, wie viele Drittligisten in genau diese
# Staffel fallen. Diese Datei uebersetzt die Auszaehlung der 3. Liga in
# Platzgewichte und daraus in Abstiegswahrscheinlichkeiten je Team.
#
#   P(Team steigt ab) = SUMME ueber Plaetze p:
#                       P(Team auf Platz p) * P(Platz p ist Abstiegsplatz)
#
# WARUM DAS PRODUKT EXAKT IST -- und keine Naeherung: 3. Liga und
# Regionalliga sind disjunkte Wettbewerbe ohne ein einziges gemeinsames
# Spiel. "Team X landet auf Platz p" und "k Drittligisten fallen in diese
# Staffel" sind deshalb wirklich unabhaengig, und P(A und B) = P(A) * P(B)
# gilt ohne Rest.
#
# Das ist der Unterschied zur Lage INNERHALB einer Liga: Dort belegen genau
# so viele Teams die Abstiegsplaetze, wie es Abstiegsplaetze gibt -- die
# Ereignisse sind stark negativ korreliert, und eine Poisson-Binomial ueber
# die Randverteilungen liefert einen falschen Erwartungswert. Genau deshalb
# zaehlt die Engine je Iteration aus (Phase 3), statt zu rechnen. Wer diese
# Formel auf einen anderen Fall uebertraegt, muss zuerst pruefen, ob die
# Unabhaengigkeit dort ebenfalls gilt.
#
# ZWEITE KOPPLUNG, NUR NORD: Dort haengt die Absteigerzahl zusaetzlich am
# EIGENEN Meisteraufstieg (Basis 3 bzw. 2, s. platz_gewichte()). Diese zweite
# Mischung ist -- anders als die an die 3. Liga -- eine Naeherung, weil beide
# Groessen aus derselben Nord-Simulation stammen; die Begruendung steht bei
# platz_gewichte(), damit sie niemand mit dem exakten Fall oben verwechselt.
#
# Amtliche Regeln mit Fundstellen: docs/abstieg_aufstieg_RL_2026_2027.md
# Annahmen und Luecken:           docs/modellannahmen-rl-kopplung.md
#
# Setzt STAFFELN aus RCode/staffel_zuordnung.R voraus.

# --- Die fuenf Abstiegsregeln ----------------------------------------------

#' Zahl der tabellarischen Direktabsteiger einer Staffel bei k
#' Drittliga-Absteigern.
#'
#' Die fuenf Staffeln koppeln NICHT gleichsinnig -- ein einheitliches
#' "Basis + k" waere fuer zwei von fuenf vorzeichenfalsch:
#'
#'   SuedWest  3 + k, gedeckelt auf 5   (RLSW-SpO Par. 47 Nr. 1, Deckel Nr. 2)
#'   Nordost   1 + k, gedeckelt auf 2   (NOFV A. Nr. 5, Schema A/B; der Deckel
#'                                       ist eine ANNAHME, s. Modellannahmen 5.1)
#'   Nord      3 + k, ohne Deckel       (NFV-SpO Par. 6 Abs. 3 und 4)
#'   West      konstant 4               (WDFV Abstieg Nr. 1) -- ENTKOPPELT.
#'                                       Nr. 3 haengt an den Oberligen, Nr. 5
#'                                       an der Lizenzierung; nur Nr. 4
#'                                       beruehrt die 3. Liga, und der Fall
#'                                       (Zweitvertretung eines absteigenden
#'                                       Lizenzvereins) kann 2026/27 nicht
#'                                       eintreten: Die Erstvertretungen
#'                                       aller West-Zweitvertretungen spielen
#'                                       in Liga 78/79 und koennen in einer
#'                                       Saison nicht bis in die RL fallen.
#'   Bayern    konstant 2               (BFV A&A II. Nr. 1) -- koppelt gar
#'                                       nicht; die Relegation (II. Nr. 3) ist
#'                                       eine eigene Groesse, s. unten
#'
#' @param staffel Name einer Staffel aus STAFFELN.
#' @param drittliga_absteiger Integer-Vektor der k-Werte.
#' @return Integer-Vektor gleicher Laenge.
abstiegsplaetze <- function(staffel, drittliga_absteiger) {
  staffel <- pruefe_staffel(staffel, "abstiegsplaetze")

  k <- as.integer(drittliga_absteiger)
  if (any(is.na(k)) || any(k < 0L)) {
    stop(sprintf(
      "abstiegsplaetze: k muss eine nicht-negative ganze Zahl sein, war: %s",
      paste(drittliga_absteiger, collapse = ", ")
    ), call. = FALSE)
  }

  plaetze <- switch(
    staffel,
    Nord     = 3L + k,
    Nordost  = pmin(1L + k, 2L),
    West     = rep(4L, length(k)),
    SuedWest = pmin(3L + k, 5L),
    Bayern   = rep(2L, length(k))
  )

  as.integer(plaetze)
}

#' Bricht ab, wenn `staffel` keine der fuenf ist.
#'
#' Eine unbekannte Staffel darf nicht still zu einem Ersatzwert fuehren --
#' das waere eine Liga, die lautlos mit fremden Abstiegsregeln gerechnet
#' wird. Gleicher Fehlerstil wie staffel_index() in staffel_zuordnung.R.
pruefe_staffel <- function(staffel, wo) {
  if (length(staffel) != 1L || is.na(staffel) || !(staffel %in% STAFFELN)) {
    stop(sprintf(
      "%s: unbekannte Staffel '%s'. Erlaubt sind: %s.",
      wo, paste(staffel, collapse = ", "), paste(STAFFELN, collapse = ", ")
    ), call. = FALSE)
  }
  as.character(staffel)
}

# --- Verteilung aus der Zaehlmatrix ----------------------------------------

#' Verteilung der Drittliga-Absteiger je Staffel aus der Zaehlmatrix.
#'
#' Eingabe ist `relegation_group_counts` der 3. Liga: Zeile = Staffel (in
#' STAFFELN-Reihenfolge), Spalte = Anzahl 0..K, Zelle = Zahl der Iterationen
#' mit GENAU dieser Anzahl. Akzeptiert wird die Matrix ebenso wie die
#' Liste-von-Listen, die aus dem JSON der Engine kommt -- sonst baut sich
#' jeder Aufrufer seine eigene Konvertierung.
#'
#' @param relegation_group_counts Matrix oder Liste von Listen/Vektoren.
#' @param iterations Erwartete Iterationszahl; NULL = aus der ersten Zeile.
#' @return Matrix P(genau k), 5 Zeilen (rownames = STAFFELN), colnames "0".."K".
absteiger_verteilung <- function(relegation_group_counts, iterations = NULL) {
  m <- als_zaehlmatrix(relegation_group_counts)

  if (nrow(m) > length(STAFFELN)) {
    stop(sprintf(
      paste0(
        "absteiger_verteilung: %d Zeilen, aber es gibt nur %d Staffeln (%s). ",
        "Stilles Abschneiden wuerde die Zuordnung verschieben."
      ),
      nrow(m), length(STAFFELN), paste(STAFFELN, collapse = ", ")
    ), call. = FALSE)
  }

  # Fehlende Zeilen am Ende: Die Engine leitet group_count aus
  # max(group_of_team) + 1 ab. Stellt die 3. Liga kein Team aus der
  # hoechstnummerierten Staffel, fehlt deren Zeile schlicht. Fachlich heisst
  # das: dorthin steigt sicher niemand ab, also P(0) = 1 (Modellannahmen 5.5).
  if (nrow(m) < length(STAFFELN)) {
    fehlend <- matrix(0, nrow = length(STAFFELN) - nrow(m), ncol = ncol(m))
    fehlend[, 1] <- if (is.null(iterations)) sum(m[1, ]) else iterations
    m <- rbind(m, fehlend)
  }

  zeilensummen <- rowSums(m)
  soll <- if (is.null(iterations)) zeilensummen[[1]] else as.numeric(iterations)

  # Die Invariante der Auszaehlung: Jede Iteration traegt in JEDER
  # Staffelzeile genau einen Zaehler bei. Eine abweichende Zeile ist ein
  # kaputtes Ergebnis, kein Rundungsproblem.
  if (soll <= 0 || any(zeilensummen != soll)) {
    stop(sprintf(
      paste0(
        "absteiger_verteilung: Zeilensummen muessen alle der Iterationszahl ",
        "%s entsprechen, waren: %s."
      ),
      format(soll), paste(format(zeilensummen), collapse = ", ")
    ), call. = FALSE)
  }

  v <- m / soll
  dimnames(v) <- list(STAFFELN, as.character(seq_len(ncol(v)) - 1L))

  # Die starke Invariante: In jeder Iteration gehen genau K Drittligisten
  # runter, jeder in genau eine Staffel. Also ist die Summe der
  # Erwartungswerte ueber alle Staffeln exakt K = ncol - 1. Nicht
  # "ungefaehr" -- das ist eine Auszaehlung, keine Naeherung. Weicht sie ab,
  # wurde entweder falsch zugeordnet oder eine Zeile geht verloren.
  K <- ncol(v) - 1L
  k_werte <- seq_len(ncol(v)) - 1L
  # colSums statt rowSums: Eine 1-Zeilen-Matrix wuerde rowSums zum Skalar
  # droppen. Hier wird ohnehin ueber alle Staffeln aufsummiert, also erst
  # spaltenweise und dann gewichtet.
  erwartung <- sum(colSums(v) * k_werte)
  if (!isTRUE(all.equal(erwartung, as.numeric(K), tolerance = 1e-9))) {
    stop(sprintf(
      paste0(
        "absteiger_verteilung: die Erwartungswerte ueber alle Staffeln ",
        "ergeben %s statt exakt %d Absteiger der 3. Liga. Entweder fehlt ",
        "eine Staffel in der Zaehlung oder die Zuordnung ist verrutscht."
      ),
      format(erwartung), K
    ), call. = FALSE)
  }

  v
}

#' Normalisiert Matrix ODER Liste-von-Listen zu einer numerischen Matrix.
als_zaehlmatrix <- function(x) {
  if (is.matrix(x)) {
    m <- x
    storage.mode(m) <- "double"
    return(unname(m))
  }

  if (!is.list(x) || length(x) == 0L) {
    stop(
      paste0(
        "absteiger_verteilung: relegation_group_counts muss eine Matrix ",
        "oder eine nicht-leere Liste von Zeilen sein."
      ),
      call. = FALSE
    )
  }

  zeilen <- lapply(x, function(zeile) as.numeric(unlist(zeile, use.names = FALSE)))
  breiten <- unique(lengths(zeilen))
  if (length(breiten) != 1L) {
    stop(sprintf(
      "absteiger_verteilung: Zeilen ungleicher Laenge: %s.",
      paste(breiten, collapse = ", ")
    ), call. = FALSE)
  }

  matrix(unlist(zeilen, use.names = FALSE), nrow = length(zeilen), byrow = TRUE)
}

#' P(mindestens j Drittliga-Absteiger in dieser Staffel).
#'
#' @param verteilung Ergebnis von absteiger_verteilung().
#' @param staffel Name einer Staffel aus STAFFELN.
#' @param j Untere Schranke, j >= 0.
#' @return Skalare Wahrscheinlichkeit.
p_mindestens <- function(verteilung, staffel, j) {
  staffel <- pruefe_staffel(staffel, "p_mindestens")
  j <- as.integer(j)
  if (length(j) != 1L || is.na(j) || j < 0L) {
    stop(sprintf(
      "p_mindestens: j muss eine nicht-negative ganze Zahl sein, war: %s",
      paste(format(j), collapse = ", ")
    ), call. = FALSE)
  }

  zeile <- verteilung[staffel, ]
  K <- length(zeile) - 1L

  # j = 0 ist das sichere Ereignis. Jenseits von K ist es unmoeglich --
  # und dann identisch 0, nicht die Summe eines leeren Bereichs mit
  # Rundungsrest.
  if (j == 0L) return(sum(zeile))
  if (j > K) return(0)

  sum(zeile[(j + 1L):(K + 1L)])
}

# --- Platzgewichte ---------------------------------------------------------

#' P(Tabellenplatz ist ein Direktabstiegsplatz), je absolutem Platz.
#'
#' Der Rueckgabevektor ist ueber die LIGAGROESSE aufgeloest: Index 1 ist der
#' Meister, Index `teams` der Letzte. Bewusst nicht "von unten" ueber
#' negative Indizes gebaut -- in R ist x[c(-2, -1)] der AUSSCHLUSS der
#' ersten beiden Elemente, nicht die letzten zwei. Diese Verwechslung
#' schlaegt nicht fehl, sie liefert nur falsche Zahlen.
#'
#' Der Platz d-ter-von-unten ist genau dann Abstiegsplatz, wenn die Staffel
#' mindestens d Abstiegsplaetze hat. Fuer die koppelnden Staffeln (Nord,
#' Nordost, SuedWest) heisst das P(k >= d - Basis); West und Bayern koppeln
#' nicht, dort ist es 0 oder 1. Statt die Faelle getrennt zu fuehren, wird
#' hier ueber die Verteilung summiert -- das deckt jede Richtung ab und
#' bleibt richtig, falls eine Regel sich aendert (etwa wenn West doch wieder
#' koppelt).
#'
#' NORD UND DER EIGENE MEISTERAUFSTIEG: Nord spielt mit 18 Teams, drei
#' Regelabsteigern und drei Oberliga-Aufsteigern -- die Bilanz 18 - 3 + 3 = 18
#' geht auf. Steigt der Nord-MEISTER in die 3. Liga auf, fehlt ein Team
#' (18 - 1 - 3 + 3 = 17), die Staffelstaerke wird unterschritten, und nach
#' NFV-SpO Par. 6 Abs. 3 a.E. geht "ein freier Platz zunaechst an den
#' bestplatzierten zugelassenen Absteiger": Der dritte Absteiger bleibt drin.
#' Also Basis 3, wenn der Meister bleibt, und Basis 2, wenn er aufsteigt.
#' `p_meister_aufstieg` mischt beide Aeste. Nur Nord ist betroffen -- Nordost,
#' West und SuedWest stellen Direktaufsteiger, deren Meisteraufstieg steckt
#' schon in der Basis, und Bayerns Absteigerzahl ist ohnehin konstant.
#'
#' @param staffel Name einer Staffel aus STAFFELN.
#' @param verteilung Ergebnis von absteiger_verteilung().
#' @param teams Zahl der Mannschaften in der Staffel.
#' @param p_meister_aufstieg Eine Zahl in [0, 1]: P(der Meister DIESER Staffel
#'   steigt in die 3. Liga auf). Default 0 = Verhalten ohne Kopplung.
#' @return Numerischer Vektor der Laenge `teams`.
platz_gewichte <- function(staffel, verteilung, teams, p_meister_aufstieg = 0) {
  staffel <- pruefe_staffel(staffel, "platz_gewichte")
  teams <- as.integer(teams)
  if (length(teams) != 1L || is.na(teams) || teams < 1L) {
    stop(sprintf(
      "platz_gewichte: teams muss eine positive ganze Zahl sein, war: %s",
      paste(format(teams), collapse = ", ")
    ), call. = FALSE)
  }
  # Staffelunabhaengig geprueft: Fuer vier der fuenf Staffeln wird der Wert
  # zwar ignoriert, aber ein Wert ausserhalb [0, 1] ist trotzdem ein
  # Aufruferfehler und darf nicht davon abhaengen, welche Staffel gerade
  # gerechnet wird. 1.1 wuerde still negative Gewichte erzeugen, ein Vektor
  # wuerde still recyceln.
  p <- pruefe_p_meister_aufstieg(p_meister_aufstieg, "platz_gewichte")

  zeile <- verteilung[staffel, ]
  k_werte <- seq_len(length(zeile)) - 1L
  n_plaetze <- abstiegsplaetze(staffel, k_werte)

  if (!identical(staffel, "Nord") || p == 0) {
    return(gewichte_aus_platzzahlen(zeile, n_plaetze, teams))
  }

  # Der Ast "Meister steigt auf": eine Basis weniger, also ein Abstiegsplatz
  # weniger je k. pmax(., 0L) ist nur Vorsicht -- 3 + k - 1 wird nie negativ.
  n_plaetze_auf <- pmax(n_plaetze - 1L, 0L)

  w_bleibt <- gewichte_aus_platzzahlen(zeile, n_plaetze, teams)
  w_auf    <- gewichte_aus_platzzahlen(zeile, n_plaetze_auf, teams)

  # NAEHERUNG, und zwar eine bewusste: "Team X landet auf Platz d" und "der
  # Meister dieser Staffel steigt auf" stammen aus DERSELBEN Nord-Simulation
  # und sind korreliert. Trotzdem wird hier multiplikativ gemischt: Dasselbe
  # Team ist praktisch nie zugleich Meister- und Abstiegskandidat, und gegen
  # Saisonende trennen sich beide Zonen ohnehin. Der Fehler ist klein und
  # beschraenkt.
  #
  # Das ist ausdruecklich ANDERS als die Kopplung an die 3. Liga oben: Dort
  # sind die Wettbewerbe disjunkt, das Produkt ist exakt (s. Dateikopf). Wer
  # beide Faelle verwechselt, haelt hier eine Naeherung fuer exakt -- oder
  # rechnet dort umstaendlich, wo nichts zu naehern ist.
  (1 - p) * w_bleibt + p * w_auf
}

#' Platzgewichte aus einer Verteilung ueber k und den zugehoerigen
#' Abstiegsplatzzahlen.
#'
#' Von unten gezaehlt: d = 1 ist der Letzte, d = teams der Meister.
#' P(Platz d-von-unten ist Abstiegsplatz) = SUMME ueber k mit
#' n_plaetze(k) >= d von P(k).
#'
#' Nur ueber die tatsaechlich moeglichen k summiert, nie ueber alle mit
#' Gewicht 0 multipliziert: Wo rechnerisch kein Absteiger mehr moeglich ist,
#' muss das Gewicht IDENTISCH 0 sein und nicht 1e-17. sum() eines leeren
#' Vektors ist exakt 0.
gewichte_aus_platzzahlen <- function(zeile, n_plaetze, teams) {
  gewichte <- numeric(teams)
  for (d in seq_len(teams)) {
    gewichte[teams - d + 1L] <- sum(zeile[n_plaetze >= d])
  }
  gewichte
}

#' Bricht ab, wenn `p` keine einzelne Wahrscheinlichkeit ist.
#'
#' Gleicher Fehlerstil wie die uebrigen Pruefungen dieser Datei: der
#' beanstandete Wert steht im Text, call. = FALSE.
pruefe_p_meister_aufstieg <- function(p, wo) {
  p <- suppressWarnings(as.numeric(p))
  if (length(p) != 1L || is.na(p) || p < 0 || p > 1) {
    stop(sprintf(
      "%s: p_meister_aufstieg muss eine einzelne Zahl in [0, 1] sein, war: %s",
      wo, paste(format(p), collapse = ", ")
    ), call. = FALSE)
  }
  p
}

# --- Die Kernformel --------------------------------------------------------

#' Abstiegswahrscheinlichkeit je Team: Skalarprodukt aus Prognosezeile und
#' Platzgewichten.
#'
#' @param prognose Matrix Teams x Plaetze (rownames = Teams, Spalte p =
#'   P(Team belegt Platz p)) -- die probability_matrix der Engine.
#' @param gewichte Vektor aus platz_gewichte(), Laenge = Zahl der Plaetze.
#' @return Benannter numerischer Vektor je Team.
abstiegswahrscheinlichkeit <- function(prognose, gewichte) {
  prognose <- as.matrix(prognose)

  # Ein zu kurzer Gewichtsvektor wuerde in R still recycelt: Die Zahlen
  # waeren falsch, ohne dass irgendetwas auffaellt.
  if (length(gewichte) != ncol(prognose)) {
    stop(sprintf(
      paste0(
        "abstiegswahrscheinlichkeit: %d Gewichte, aber die Prognose hat %d ",
        "Plaetze. R wuerde still recyceln und falsche Zahlen liefern."
      ),
      length(gewichte), ncol(prognose)
    ), call. = FALSE)
  }

  # drop = FALSE waere hier ohne Wirkung, aber %*% auf einer 1-Zeilen-Matrix
  # liefert eine 1x1-Matrix -- deshalb explizit zum Vektor und die Namen aus
  # den rownames zurueckholen.
  p <- as.vector(prognose %*% as.numeric(gewichte))
  names(p) <- rownames(prognose)
  p
}

# --- Die ganze Kette -------------------------------------------------------

#' Abstiegsprognose einer Regionalliga-Staffel.
#'
#' @param staffel Name einer Staffel aus STAFFELN.
#' @param prognose Prognosematrix Teams x Plaetze (rownames = Teams).
#' @param relegation_group_counts Zaehlmatrix der 3. Liga (Matrix oder Liste).
#' @param p_meister_aufstieg P(Meister dieser Staffel steigt in die 3. Liga
#'   auf), eine Zahl in [0, 1]. Wirkt nur auf Nord (s. platz_gewichte()).
#'   Wird als fertige Zahl hereingereicht und NICHT intern aus rl_aufstieg.R
#'   geholt: Das haelt die Module getrennt und die Zahl im Test setzbar.
#' @return data.frame mit rownames = Teams. Spalte "Abstieg"; fuer Bayern die
#'   zwei Spalten "Relegation" und "Abstieg".
rl_abstiegsprognose <- function(staffel, prognose, relegation_group_counts,
                                p_meister_aufstieg = 0) {
  staffel <- pruefe_staffel(staffel, "rl_abstiegsprognose")
  # Vor der teuren Auszaehlung geprueft, damit ein Aufruferfehler nicht erst
  # nach der Verteilungsrechnung auffaellt.
  pruefe_p_meister_aufstieg(p_meister_aufstieg, "rl_abstiegsprognose")
  prognose <- as.matrix(prognose)
  teams <- ncol(prognose)

  verteilung <- absteiger_verteilung(relegation_group_counts)
  gewichte <- platz_gewichte(staffel, verteilung, teams,
                             p_meister_aufstieg = p_meister_aufstieg)
  abstieg <- abstiegswahrscheinlichkeit(prognose, gewichte)

  if (!identical(staffel, "Bayern")) {
    return(data.frame(Abstieg = abstieg, row.names = rownames(prognose)))
  }

  # Bayern weist nach unten ZWEI Groessen aus, die nicht verrechnet werden:
  # die zwei Letzten steigen direkt ab (BFV A&A II. Nr. 1), die zwei davor
  # gehen in die Relegation gegen zwei Bayernligisten (II. Nr. 3).
  #
  # Die Relegation wird NICHT aufgeloest. Wir simulieren die Bayernligen
  # nicht; jede Gewinnquote waere erfunden. Getrennt ausgewiesen steht auf
  # der Seite genau das, was das Modell weiss (Modellannahmen 3).
  #
  # Relativ gerechnet, also n-3 und n-2 -- 2026/27 spielt Bayern mit 19
  # statt 18 Vereinen, und die Regeldoku nennt "die zwei vor den
  # Festabsteigern", nicht feste Platznummern (Modellannahmen 5.4).
  relegations_gewichte <- numeric(teams)
  relegations_plaetze <- c(teams - 3L, teams - 2L)
  relegations_plaetze <- relegations_plaetze[relegations_plaetze >= 1L]
  relegations_gewichte[relegations_plaetze] <- 1
  relegation <- abstiegswahrscheinlichkeit(prognose, relegations_gewichte)

  data.frame(
    Relegation = relegation,
    Abstieg = abstieg,
    row.names = rownames(prognose)
  )
}
