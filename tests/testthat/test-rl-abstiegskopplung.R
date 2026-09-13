library(testthat)

# Phase 6: Abstiegskopplung der Regionalligen an die 3. Liga (R-Seite).
#
# Kernformel, pro Platz zerlegt:
#
#   P(Team steigt ab) = SUMME ueber Plaetze p:
#                       P(Team auf Platz p) * P(Platz p ist Abstiegsplatz)
#
# Der erste Faktor ist die Zeile des Teams in der Prognosematrix der
# Regionalliga. Der zweite Faktor kommt aus `relegation_group_counts` der
# 3. Liga (Phase 3): eine Matrix [Staffel, Anzahl], deren Zelle zaehlt, in
# wie vielen Iterationen GENAU `Anzahl` Drittliga-Absteiger auf diese
# Staffel entfielen. Zeilensumme = Iterationszahl.
#
# Warum das Produkt EXAKT ist und keine Naeherung: 3. Liga und Regionalliga
# sind disjunkte Wettbewerbe ohne ein einziges gemeinsames Spiel. Das
# Ereignis "Team X landet auf Platz p seiner Staffel" und das Ereignis
# "k Drittligisten fallen in diese Staffel" sind deshalb stochastisch
# unabhaengig, und P(A und B) = P(A) * P(B) gilt ohne Rest. Das ist der
# Unterschied zur Lage INNERHALB einer Liga: Dort belegen genau vier Teams
# die vier letzten Plaetze, die Ereignisse sind stark negativ korreliert,
# und genau deshalb wurde in Phase 3 die Poisson-Binomial-Naeherung
# verworfen und die Verteilung stattdessen je Iteration ausgezaehlt.
#
# Die fuenf Staffeln koppeln NICHT gleich (docs/abstieg_aufstieg_RL_2026_2027.md,
# Abschnitt 3.2):
#   SuedWest  Basis 3, +1 je Drittliga-Absteiger, Deckel 5   (RLSW-SpO Par. 47)
#   Nordost   Basis 1, +1 je Drittliga-Absteiger, Schema bis 2 (NOFV A. Nr. 5)
#   Nord      Basis 3, +1 je Drittliga-Absteiger, kein Deckel (NFV-SpO Par. 6 Abs. 4)
#   West      ENTKOPPELT: feste 4, unabhaengig von k (WDFV Abstieg Nr. 1).
#             Die Verminderungsgruende Nr. 3 (weniger Oberliga-Aufsteiger)
#             und Nr. 5 (Nichtlizenzierung) haengen NICHT an der 3. Liga;
#             Nr. 4 (Zweitvertretung eines absteigenden Lizenzvereins rueckt
#             ans Tabellenende) ist BEWUSST NICHT MODELLIERT. Bis Issue #207
#             stand hier, der Fall koenne 2026/27 nicht eintreten -- das war
#             falsch: Fortuna Duesseldorf spielt in Liga 80, Fortuna II in
#             der RL West. Die feste 4 bleibt trotzdem richtig, weil die
#             Abbildung eine Abstiegswahrscheinlichkeit je Platz braeuchte
#             (Issue #185) und die Wirkung an Fortunas Abstieg haengt.
#   Bayern    Zahl aendert sich NICHT: 2 Direktabsteiger (die zwei Letzten)
#             und 2 Relegationsteilnehmer (die zwei davor). Die Relegation
#             wird NICHT aufgeloest -- Bayernligisten werden nicht
#             simuliert, es darf keine Gewinnquote erfunden werden.
#
# Erwartete Implementierung: RCode/rl_abstiegskopplung.R mit
#
#   absteiger_verteilung(relegation_group_counts, iterations = NULL)
#     Eingabe: die Zaehlmatrix der 3. Liga -- als numerische Matrix ODER als
#     Liste von Listen, so wie sie aus dem JSON der Engine kommt. Zeilen in
#     STAFFELN-Reihenfolge, Spalten = Anzahl 0..K.
#     Ausgabe: Matrix der Wahrscheinlichkeiten P(genau k), 5 Zeilen mit
#     rownames = STAFFELN, Spalten mit colnames "0".."K".
#     Bricht ab, wenn die Zeilensummen nicht uebereinstimmen (bzw. nicht
#     `iterations` entsprechen) oder wenn die Summe der Erwartungswerte
#     ueber alle Staffeln nicht exakt K ergibt. Fehlende Zeilen am Ende
#     (die Engine leitet group_count aus max(group_of_team)+1 ab, s. Plan
#     "Fuer Phase 6 zu beachten") werden mit P(0) = 1 aufgefuellt.
#
#   p_mindestens(verteilung, staffel, j)
#     P(mindestens j Drittliga-Absteiger in `staffel`), j >= 0.
#
#   abstiegsplaetze(staffel, drittliga_absteiger)
#     Zahl der tabellarischen Direktabsteiger der Staffel bei k
#     Drittliga-Absteigern. Vektorisiert ueber k. Fuer Bayern konstant 2.
#
#   platz_gewichte(staffel, verteilung, teams)
#     Numerischer Vektor der Laenge `teams`, Index = ABSOLUTER Tabellenplatz
#     (1 = Meister, teams = Letzter): P(Platz ist Direktabstiegsplatz).
#     Fuer Bayern nur der Direktabstieg (die Relegation ist eine eigene
#     Groesse, s. rl_abstiegsprognose).
#
#   abstiegswahrscheinlichkeit(prognose, gewichte)
#     prognose: Matrix Teams x Plaetze (rownames = Teams, Spalte p =
#     P(Platz p)), also die probability_matrix der Engine. gewichte: der
#     Vektor aus platz_gewichte(). Ausgabe: benannter numerischer Vektor je
#     Team, das Skalarprodukt aus Zeile und Gewichten.
#
#   rl_abstiegsprognose(staffel, prognose, relegation_group_counts)
#     Die ganze Kette. Ausgabe: data.frame mit rownames = Teams und der
#     Spalte "Abstieg" -- fuer Bayern die ZWEI Spalten "Relegation" und
#     "Abstieg", nicht verrechnet.

source_kopplung <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  datei <- test_path("..", "..", "RCode", "rl_abstiegskopplung.R")
  if (file.exists(datei)) source(datei, local = env)
  env
}

# Holt eine Funktion aus der Umgebung und meldet klar, wenn sie fehlt --
# statt des kryptischen "attempt to apply non-function" bei env$name().
fn <- function(env, name) {
  if (!exists(name, envir = env, inherits = FALSE)) {
    stop(sprintf(
      "Funktion '%s' nicht gefunden -- erwartet in RCode/rl_abstiegskopplung.R",
      name
    ), call. = FALSE)
  }
  get(name, envir = env, inherits = FALSE)
}

STAFFELN_ERWARTET <- c("Nord", "Nordost", "West", "SuedWest", "Bayern")
N_ITER <- 10000
K_DRITTE_LIGA <- 4L  # Absteiger der 3. Liga; Spalten 0..4

# Zaehlmatrix der 3. Liga bauen. Jede nicht genannte Staffel bekommt
# "immer 0 Drittliga-Absteiger". ACHTUNG: In einer echten Zaehlung entfallen
# in JEDER Iteration genau K Absteiger auf die fuenf Staffeln zusammen --
# die Summe der Erwartungswerte ueber alle Zeilen muss also exakt K sein.
# Alle Fixtures unten erfuellen das; ein Fixture, das es verletzt, muss die
# Implementierung ablehnen (eigener Test).
zaehlung <- function(...) {
  m <- matrix(0, nrow = 5, ncol = K_DRITTE_LIGA + 1)
  m[, 1] <- N_ITER
  zeilen <- list(...)
  for (staffel in names(zeilen)) {
    m[match(staffel, STAFFELN_ERWARTET), ] <- zeilen[[staffel]]
  }
  m
}

# Fixture "Nordost 89 %": In 89 % der Iterationen faellt genau ein
# Drittligist nach Nordost, nie zwei. Erwartungswerte: Nordost 0.89,
# Nord 1.11, West 1, SuedWest 1, Bayern 0 -- Summe 4.
zaehlung_nordost89 <- function() {
  zaehlung(
    Nordost  = c(1100, 8900, 0, 0, 0),
    Nord     = c(0, 8900, 1100, 0, 0),
    West     = c(0, N_ITER, 0, 0, 0),
    SuedWest = c(0, N_ITER, 0, 0, 0)
  )
}

# Prognosezeile eines Teams, das nur die genannten Plaetze erreichen kann.
# `plaetze` sind absolute Plaetze, `p` die Wahrscheinlichkeiten dazu.
prognose_zeile <- function(teams, plaetze, p, name = "A") {
  stopifnot(abs(sum(p) - 1) < 1e-12)
  m <- matrix(0, nrow = 1, ncol = teams,
              dimnames = list(name, as.character(seq_len(teams))))
  m[1, plaetze] <- p
  m
}

# --- Kernformel: das verbindliche Zahlenbeispiel ----------------------------

test_that("Kernformel: 30/30/20/10 auf den letzten vier Plaetzen ergibt 77,8 %", {
  # Das Fixpunkt-Beispiel. Team A: 30 % Letzter, 30 % Vorletzter, 20 %
  # Drittletzter, 10 % Viertletzter (und 10 % Meister, damit die Zeile
  # summiert). Der Drittletzte ist nur zu 89 % ein Abstiegsplatz, der
  # Viertletzte gar nicht (rechnerisch kein weiterer Drittliga-Absteiger
  # moeglich).
  #
  #   0.30 * 1 + 0.30 * 1 + 0.20 * 0.89 + 0.10 * 0 = 0.778
  #
  # (Die Aufgabenstellung nannte 0.798 -- das ist ein Rechenfehler: 0.20 * 0.89
  # ist 0.178, nicht 0.198. Die Eingaben sind unveraendert, die Zahl stimmt.)
  env <- source_kopplung()
  teams <- 18L

  prognose <- prognose_zeile(teams, plaetze = c(1, 15, 16, 17, 18),
                             p = c(0.10, 0.10, 0.20, 0.30, 0.30))
  # Absolut indiziert: Platz 18 = Letzter.
  gewichte <- c(rep(0, 14), 0, 0.89, 1, 1)

  p <- fn(env, "abstiegswahrscheinlichkeit")(prognose, gewichte)

  expect_named(p, "A")
  expect_equal(unname(p), 0.778, tolerance = 1e-12)
})

test_that("Kernformel: ein um einen Platz verrutschtes Gewicht ergibt eine andere Zahl", {
  # Gegenprobe zum Fixpunkt. Landet das 0.89 einen Platz zu weit oben
  # (Viertletzter statt Drittletzter), muss 0.889 herauskommen, nicht
  # 0.778. Und wer den Gewichtsvektor von der falschen Seite liest
  # (rev), bekommt 0.189. Beides sind echte Zahlen, kein Strukturcheck.
  env <- source_kopplung()
  teams <- 18L
  prognose <- prognose_zeile(teams, plaetze = c(1, 15, 16, 17, 18),
                             p = c(0.10, 0.10, 0.20, 0.30, 0.30))
  f <- fn(env, "abstiegswahrscheinlichkeit")

  verrutscht <- c(rep(0, 14), 0.89, 1, 1, 1)
  expect_equal(unname(f(prognose, verrutscht)), 0.889, tolerance = 1e-12)

  gewichte <- c(rep(0, 14), 0, 0.89, 1, 1)
  expect_equal(unname(f(prognose, rev(gewichte))),
               0.10 * 1 + 0.10 * 0 + 0.20 * 0 + 0 + 0, tolerance = 1e-12)
  expect_false(isTRUE(all.equal(unname(f(prognose, rev(gewichte))), 0.778)))
})

test_that("Kernformel: Wahrscheinlichkeit exakt 0 und exakt 1 fuer einen Platz", {
  env <- source_kopplung()
  f <- fn(env, "abstiegswahrscheinlichkeit")
  teams <- 6L
  gewichte <- c(0, 0, 0, 0, 1, 1)

  # Sicherer Letzter -> sicherer Absteiger, ohne Rundungsrest.
  letzter <- prognose_zeile(teams, plaetze = 6, p = 1, name = "L")
  expect_identical(unname(f(letzter, gewichte)), 1)

  # Sicherer Meister -> exakt 0, nicht "ungefaehr 0".
  meister <- prognose_zeile(teams, plaetze = 1, p = 1, name = "M")
  expect_identical(unname(f(meister, gewichte)), 0)

  # Ein Team, das nur Platz 4 (Gewicht 0) oder Platz 5 (Gewicht 1)
  # erreichen kann: P(Abstieg) = P(Platz 5).
  mitte <- prognose_zeile(teams, plaetze = c(4, 5), p = c(0.25, 0.75), name = "X")
  expect_equal(unname(f(mitte, gewichte)), 0.75)
})

test_that("Kernformel rechnet mehrere Teams zeilenweise und benennt sie", {
  env <- source_kopplung()
  f <- fn(env, "abstiegswahrscheinlichkeit")

  prognose <- rbind(
    prognose_zeile(4, plaetze = c(3, 4), p = c(0.5, 0.5), name = "P"),
    prognose_zeile(4, plaetze = c(1, 2), p = c(0.5, 0.5), name = "Q"),
    prognose_zeile(4, plaetze = c(2, 3, 4), p = c(0.2, 0.3, 0.5), name = "R")
  )
  gewichte <- c(0, 0, 0.4, 1)

  p <- f(prognose, gewichte)
  expect_equal(p, c(P = 0.5 * 0.4 + 0.5, Q = 0, R = 0.3 * 0.4 + 0.5))
})

test_that("Kernformel lehnt einen Gewichtsvektor falscher Laenge ab", {
  # Ein zu kurzer Vektor wuerde in R still recycelt -- und die Zahlen
  # waeren falsch, ohne dass etwas auffaellt.
  env <- source_kopplung()
  f <- fn(env, "abstiegswahrscheinlichkeit")
  prognose <- prognose_zeile(6, plaetze = 6, p = 1)

  expect_error(f(prognose, c(0, 0, 1)))
  expect_error(f(prognose, rep(0, 7)))
})

# --- Verteilung aus der Zaehlmatrix ----------------------------------------

test_that("absteiger_verteilung normiert je Zeile auf die Iterationszahl", {
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nordost89())

  expect_equal(dim(v), c(5L, 5L))
  expect_equal(rownames(v), STAFFELN_ERWARTET)
  expect_equal(colnames(v), as.character(0:4))
  expect_equal(unname(v["Nordost", ]), c(0.11, 0.89, 0, 0, 0))
  expect_equal(unname(v["Nord", ]), c(0, 0.89, 0.11, 0, 0))
  expect_equal(unname(v["Bayern", ]), c(1, 0, 0, 0, 0))
  expect_equal(unname(rowSums(v)), rep(1, 5))
})

test_that("absteiger_verteilung nimmt die Listenform der Engine-Antwort an", {
  # content(response, "parsed") liefert eine Liste von Listen, keine
  # Matrix. Genau diese Form muss ohne Umweg funktionieren -- sonst baut
  # sich jeder Aufrufer seine eigene Konvertierung.
  env <- source_kopplung()
  m <- zaehlung_nordost89()
  als_liste <- lapply(seq_len(nrow(m)), function(i) as.list(m[i, ]))

  v_liste <- fn(env, "absteiger_verteilung")(als_liste)
  v_matrix <- fn(env, "absteiger_verteilung")(m)

  expect_equal(v_liste, v_matrix)
})

test_that("absteiger_verteilung verlangt gleiche Zeilensummen", {
  # Zeilensumme = Iterationszahl ist die Invariante der Auszaehlung: Jede
  # Iteration traegt in JEDER Staffelzeile genau einen Zaehler bei. Eine
  # abweichende Zeile ist ein kaputtes Ergebnis, kein Rundungsproblem.
  env <- source_kopplung()
  f <- fn(env, "absteiger_verteilung")

  kaputt <- zaehlung_nordost89()
  kaputt[2, 1] <- kaputt[2, 1] + 1
  expect_error(f(kaputt))

  # Explizite Iterationszahl, die nicht zu den Zeilen passt.
  expect_error(f(zaehlung_nordost89(), iterations = N_ITER + 1))
  # Passende Iterationszahl geht durch.
  expect_silent(f(zaehlung_nordost89(), iterations = N_ITER))
})

test_that("absteiger_verteilung verlangt, dass die Absteiger ueber alle Staffeln exakt K ergeben", {
  # Die starke Invariante aus dem Plan (Abschnitt 7): In jeder Iteration
  # gehen genau K Drittligisten runter, jeder in genau eine Staffel. Also
  # ist SUMME ueber Staffeln von E[k] exakt K = ncol - 1. Nicht "ungefaehr":
  # Das ist eine Auszaehlung, keine Naeherung.
  env <- source_kopplung()
  f <- fn(env, "absteiger_verteilung")

  # Alle Zeilen "immer 0 Absteiger": Summe der Erwartungswerte 0 statt 4.
  expect_error(f(zaehlung()))

  # Zeilensummen stimmen, aber E-Summe = 5.
  zu_viel <- zaehlung(Nord = c(0, 0, 0, 0, N_ITER), Nordost = c(0, N_ITER, 0, 0, 0))
  expect_error(f(zu_viel))
})

test_that("absteiger_verteilung fuellt fehlende Staffelzeilen mit P(0) = 1 auf", {
  # Die Engine leitet group_count aus max(group_of_team) + 1 ab. Stellt
  # die 3. Liga kein Team aus Bayern (Index 4), hat die Matrix nur vier
  # Zeilen. Fachlich heisst das: nach Bayern faellt sicher niemand --
  # P(0) = 1. Eine kuerzere Matrix darf also nicht abbrechen, aber auch
  # nicht die Zeilen verschieben.
  env <- source_kopplung()
  m <- zaehlung(Nord = c(0, N_ITER, 0, 0, 0),
                West = c(0, 0, 0, N_ITER, 0))[1:4, ]

  v <- fn(env, "absteiger_verteilung")(m)

  expect_equal(rownames(v), STAFFELN_ERWARTET)
  expect_equal(unname(v["Bayern", ]), c(1, 0, 0, 0, 0))
  expect_equal(unname(v["West", ]), c(0, 0, 0, 1, 0))
  expect_equal(unname(v["Nord", ]), c(0, 1, 0, 0, 0))
})

test_that("absteiger_verteilung lehnt mehr als fuenf Zeilen ab", {
  env <- source_kopplung()
  m <- rbind(zaehlung_nordost89(), c(N_ITER, 0, 0, 0, 0))
  f <- fn(env, "absteiger_verteilung")
  expect_error(f(m), "Zeilen|Staffeln")
})

test_that("p_mindestens liest die richtige Zeile ueber den Staffelnamen", {
  # Jede Zeile bekommt einen anderen Wert fuer P(k >= 2), damit eine
  # Verwechslung von Zeilenindex und Staffelname auffaellt.
  # Erwartungswerte: Nord 0.1+1.3 = 1.4, Nordost 0.2+0.6 = 0.8,
  # West 0.3+0.4 = 0.7, SuedWest 0.4+0.2 = 0.6, Bayern 0.5 -- Summe 4.
  env <- source_kopplung()
  m <- zaehlung(
    Nord     = c(2500, 1000, 6500, 0, 0),
    Nordost  = c(5000, 2000, 3000, 0, 0),
    West     = c(5000, 3000, 2000, 0, 0),
    SuedWest = c(5000, 4000, 1000, 0, 0),
    Bayern   = c(5000, 5000, 0, 0, 0)
  )
  v <- fn(env, "absteiger_verteilung")(m)
  pm <- fn(env, "p_mindestens")

  expect_equal(pm(v, "Nord", 2), 0.65)
  expect_equal(pm(v, "Nordost", 2), 0.30)
  expect_equal(pm(v, "West", 2), 0.20)
  expect_equal(pm(v, "SuedWest", 2), 0.10)
  expect_equal(pm(v, "Bayern", 2), 0)

  # j = 0 ist das sichere Ereignis; jenseits von K ist es unmoeglich.
  expect_equal(pm(v, "West", 0), 1)
  expect_identical(pm(v, "West", 5), 0)
  # P(>= 1) = 1 - P(0).
  expect_equal(pm(v, "Nord", 1), 0.75)
})

test_that("p_mindestens bricht bei unbekannter Staffel ab", {
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nordost89())
  f <- fn(env, "p_mindestens")
  expect_error(f(v, "Suedost", 1), "Suedost")
})

# --- Die fuenf Regeln: abstiegsplaetze(staffel, k) --------------------------

test_that("SuedWest: 3 + k, gedeckelt auf 5", {
  # RLSW-SpO Par. 47 Nr. 1 und Nr. 2 -- das Schema der Spielordnung fuer
  # Sollstaerke 18: k = 0..4 -> 3, 4, 5, 5, 5.
  env <- source_kopplung()
  f <- fn(env, "abstiegsplaetze")
  expect_equal(f("SuedWest", 0:4), c(3L, 4L, 5L, 5L, 5L))
})

test_that("Nordost: 1 + k, Schema nur bis 2", {
  # NOFV Auf- und Abstiegsregelung A. Nr. 5, Varianten A/B: 1 Absteiger,
  # 2 bei einem Drittliga-Absteiger. Mehr sieht das Schema nicht vor
  # (Hansa Rostock ist der einzige NOFV-Drittligist); ANNAHME: jenseits
  # des Schemas bleibt es beim Deckel 2.
  env <- source_kopplung()
  f <- fn(env, "abstiegsplaetze")
  expect_equal(f("Nordost", 0:2), c(1L, 2L, 2L))
})

test_that("Nord: 3 + k, ohne Deckel", {
  # NFV-SpO Par. 6 Abs. 3 (drei Regelabsteiger) und Abs. 4 (Erhoehung, sobald
  # die Staffelstaerke durch Drittliga-Absteiger ueberschritten wird).
  env <- source_kopplung()
  f <- fn(env, "abstiegsplaetze")
  expect_equal(f("Nord", 0:4), c(3L, 4L, 5L, 6L, 7L))
})

test_that("West: feste 4, unabhaengig von der 3. Liga", {
  # WDFV Abstieg Nr. 1: "bei 18 teilnehmenden Vereinen die vier Vereine mit
  # der geringsten Punktezahl". Kein Term, der an der 3. Liga haengt.
  #
  # Hier stand zuvor 4 - k. Das folgte der Zusammenschau in Regeldoku 3.2,
  # nicht dem Ordnungstext: Von den drei Verminderungsgruenden haengt Nr. 3
  # an den Oberligen und Nr. 5 an der Lizenzierung; nur Nr. 4 beruehrt die
  # 3. Liga, und dieser Fall ist bewusst nicht modelliert (s. Kopfkommentar).
  # Bilanzlogisch war 4 - k sogar verkehrt herum: Ein Drittliga-Absteiger
  # ERHOEHT die Teamzahl auf 19; der WDFV gleicht das ueber die
  # Aufstiegsseite und die Ligagroesse aus, nicht ueber weniger Absteiger.
  env <- source_kopplung()
  f <- fn(env, "abstiegsplaetze")
  expect_equal(f("West", 0:4), rep(4L, 5))
  # Konstant -- keine Kopplung in irgendeine Richtung.
  expect_true(all(diff(f("West", 0:4)) == 0))
})

test_that("Bayern: zwei Direktabsteiger, unabhaengig von k", {
  # BFV A&A II. Nr. 1. Die Relegation (II. Nr. 3) ist KEIN Abstiegsplatz
  # und taucht hier nicht auf.
  env <- source_kopplung()
  f <- fn(env, "abstiegsplaetze")
  expect_equal(f("Bayern", 0:4), rep(2L, 5))
})

test_that("abstiegsplaetze bricht bei unbekannter Staffel ab", {
  env <- source_kopplung()
  f <- fn(env, "abstiegsplaetze")
  expect_error(f("Sued", 0L), "Sued")
})

# --- Platzgewichte: P(Platz ist Abstiegsplatz) ------------------------------

test_that("Nordost-Gewichte aus der 89-%-Zaehlung: 1, 0.89, exakt 0", {
  # Aus zaehlung_nordost89: P(k >= 1) = 0.89, P(k >= 2) = 0.
  # Basis 1 -> der Letzte steigt sicher ab, der Vorletzte zu 89 %, der
  # Drittletzte NIE -- rechnerisch kein weiterer Absteiger moeglich, also
  # Gewicht exakt 0, nicht 1e-17.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nordost89())
  w <- fn(env, "platz_gewichte")("Nordost", v, teams = 18L)

  expect_length(w, 18L)
  # Werte pruefen, nicht Indexform: Platz 18 ist der Letzte.
  expect_equal(unname(w[18]), 1)
  expect_equal(unname(w[17]), 0.89)
  expect_identical(unname(w[16]), 0)
  expect_identical(unname(w[1:15]), rep(0, 15))
})

test_that("Nordost: Team mit 30/30/20/10 auf den letzten vier Plaetzen hat 56,7 %", {
  # Dieselbe Teamzeile wie im Fixpunkt-Beispiel, aber die Gewichte kommen
  # jetzt aus der Zaehlung: 0.30 * 1 + 0.30 * 0.89 + 0.20 * 0 + 0.10 * 0
  # = 0.567. Ein anderes Ergebnis als 0.778, weil Nordost Basis 1 hat.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nordost89())
  w <- fn(env, "platz_gewichte")("Nordost", v, teams = 18L)
  prognose <- prognose_zeile(18L, plaetze = c(1, 15, 16, 17, 18),
                             p = c(0.10, 0.10, 0.20, 0.30, 0.30))

  p <- fn(env, "abstiegswahrscheinlichkeit")(prognose, w)
  expect_equal(unname(p), 0.567, tolerance = 1e-12)
})

test_that("SuedWest: Deckel 5 -- bei vier Drittliga-Absteigern bleibt Platz 13 sicher", {
  # P(k = 4) = 1. Ohne Deckel waeren es 7 Absteiger (Plaetze 12-18); mit
  # Deckel 5 sind es die Plaetze 14-18, und Platz 13 hat Gewicht exakt 0.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(
    zaehlung(SuedWest = c(0, 0, 0, 0, N_ITER))
  )
  w <- fn(env, "platz_gewichte")("SuedWest", v, teams = 18L)

  expect_equal(unname(w[14:18]), rep(1, 5))
  expect_identical(unname(w[13]), 0)
  expect_identical(unname(w[12]), 0)
})

test_that("SuedWest: gemischte Zaehlung gewichtet Platz 15 und 14 unterschiedlich", {
  # SuedWest: P(k=0) = 0.5, P(k=1) = 0.3, P(k=2) = 0.2  (E = 0.7)
  # Nord:     P(k=3) = 1                                 (E = 3)
  # Bayern:   P(k=0) = 0.7, P(k=1) = 0.3                 (E = 0.3) -- Summe 4
  #
  # Abstiegsplaetze SuedWest: 3 / 4 / 5.
  #   Platz 16-18: immer            -> 1
  #   Platz 15:    bei k >= 1       -> 0.5
  #   Platz 14:    bei k >= 2       -> 0.2
  #   Platz 13:    nie              -> 0
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung(
    SuedWest = c(5000, 3000, 2000, 0, 0),
    Nord     = c(0, 0, 0, N_ITER, 0),
    Bayern   = c(7000, 3000, 0, 0, 0)
  ))
  w <- fn(env, "platz_gewichte")("SuedWest", v, teams = 18L)

  expect_equal(unname(w[16:18]), c(1, 1, 1))
  expect_equal(unname(w[15]), 0.5)
  expect_equal(unname(w[14]), 0.2)
  expect_identical(unname(w[13]), 0)
})

test_that("West: die Zaehlung der 3. Liga aendert die Abstiegsplaetze nicht", {
  # West ist entkoppelt (WDFV Abstieg Nr. 1): immer die vier Letzten,
  # egal wie viele Drittligisten in die Staffel fallen. Das ist die
  # Gegenprobe -- zwei voellig verschiedene Zaehlungen, identische
  # Gewichte.
  env <- source_kopplung()
  f <- fn(env, "absteiger_verteilung")
  g <- fn(env, "platz_gewichte")

  v <- f(zaehlung(West = c(5000, 5000, 0, 0, 0),
                  SuedWest = c(0, 5000, 5000, 0, 0),
                  Nord = c(0, 0, N_ITER, 0, 0)))
  v2 <- f(zaehlung(West = c(0, 0, N_ITER, 0, 0), Nord = c(0, 0, N_ITER, 0, 0)))

  w <- g("West", v, teams = 18L)
  w2 <- g("West", v2, teams = 18L)

  expect_identical(w, w2)
  expect_equal(unname(w[15:18]), c(1, 1, 1, 1))
  expect_identical(unname(w[14]), 0)
  # Erwartete Absteigerzahl konstant 4, nicht 3.5 oder 2.
  expect_equal(sum(w), 4)
  expect_equal(sum(w2), 4)
})

test_that("Nord: 3 + k ohne Deckel -- zwei Drittliga-Absteiger machen fuenf Plaetze", {
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung(
    Nord = c(0, 0, N_ITER, 0, 0),
    West = c(0, 0, N_ITER, 0, 0)
  ))
  w <- fn(env, "platz_gewichte")("Nord", v, teams = 18L)

  expect_equal(unname(w[14:18]), rep(1, 5))
  expect_identical(unname(w[13]), 0)
})

test_that("Bayern: genau die zwei Letzten, egal was die 3. Liga tut", {
  # Zwei voellig verschiedene Zaehlungen -- dieselben Gewichte.
  env <- source_kopplung()
  f <- fn(env, "absteiger_verteilung")
  g <- fn(env, "platz_gewichte")

  v_a <- f(zaehlung(Bayern = c(0, N_ITER, 0, 0, 0), Nord = c(0, 0, 0, N_ITER, 0)))
  v_b <- f(zaehlung(Bayern = c(N_ITER, 0, 0, 0, 0), Nord = c(0, 0, 0, 0, N_ITER)))

  w_a <- g("Bayern", v_a, teams = 19L)
  w_b <- g("Bayern", v_b, teams = 19L)

  expect_identical(w_a, w_b)
  expect_equal(unname(w_a[18:19]), c(1, 1))
  expect_identical(unname(w_a[1:17]), rep(0, 17))
})

test_that("Platzgewichte sind ueber die Ligagroesse aufgeloest, nicht als negative Indizes", {
  # Wer Gewichte "von unten" per negativem Index baut, bekommt in R den
  # AUSSCHLUSS: x[c(-2, -1)] sind alle ausser den ersten beiden. Deshalb
  # wird hier der WERT an Positionen geprueft, bei einer kleinen Liga, wo
  # die Verwechslung sofort sichtbar waere: Bei 6 Teams und Basis 1
  # (Nordost, k = 0 sicher) darf nur Platz 6 Gewicht 1 haben.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung(
    Nord = c(0, 0, 0, 0, N_ITER)
  ))
  w <- fn(env, "platz_gewichte")("Nordost", v, teams = 6L)

  expect_equal(unname(w), c(0, 0, 0, 0, 0, 1))

  # Und bei 22 Teams (RL Nord kann so gross sein) rutscht nichts mit.
  w22 <- fn(env, "platz_gewichte")("Nordost", v, teams = 22L)
  expect_equal(unname(w22), c(rep(0, 21), 1))
})

test_that("Platzgewichte steigen zum Tabellenende hin monoton -- in allen fuenf Staffeln", {
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung(
    Nord     = c(2500, 1000, 6500, 0, 0),
    Nordost  = c(5000, 2000, 3000, 0, 0),
    West     = c(5000, 3000, 2000, 0, 0),
    SuedWest = c(5000, 4000, 1000, 0, 0),
    Bayern   = c(5000, 5000, 0, 0, 0)
  ))
  g <- fn(env, "platz_gewichte")

  for (staffel in STAFFELN_ERWARTET) {
    w <- g(staffel, v, teams = 18L)
    expect_true(all(diff(w) >= 0), info = staffel)
    expect_true(all(w >= 0 & w <= 1), info = staffel)
    expect_equal(unname(w[18]), 1, info = staffel)
  }
})

test_that("Erwartete Absteigerzahl = Summe der Platzgewichte = Summe ueber Teams", {
  # Die exakte Erwartungswert-Kontrolle: Weil jede Platzspalte der
  # Prognose ueber die Teams auf 1 summiert, ist die Summe der
  # Abstiegswahrscheinlichkeiten ueber alle Teams gleich der Summe der
  # Platzgewichte -- und die ist E[abstiegsplaetze(k)]. Keine Toleranz
  # noetig, das ist Algebra.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung(
    SuedWest = c(5000, 3000, 2000, 0, 0),
    Nord     = c(0, 0, 0, N_ITER, 0),
    Bayern   = c(7000, 3000, 0, 0, 0)
  ))
  w <- fn(env, "platz_gewichte")("SuedWest", v, teams = 6L)

  # E[Absteiger SuedWest] = 0.5*3 + 0.3*4 + 0.2*5 = 3.7
  expect_equal(sum(w), 3.7)

  # Doppelt stochastische Prognose: halb Identitaet, halb zyklische
  # Verschiebung -- jede Zeile und jede Spalte summiert auf 1.
  n <- 6L
  ident <- diag(n)
  shift <- ident[c(2:n, 1), ]
  prognose <- 0.5 * ident + 0.5 * shift
  rownames(prognose) <- paste0("T", seq_len(n))

  p <- fn(env, "abstiegswahrscheinlichkeit")(prognose, w)
  expect_equal(sum(p), 3.7)
})

# --- Die ganze Kette: rl_abstiegsprognose -----------------------------------

test_that("rl_abstiegsprognose rechnet Nordost vom Zaehler bis zur Spalte durch", {
  env <- source_kopplung()
  prognose <- rbind(
    prognose_zeile(18L, plaetze = c(1, 15, 16, 17, 18),
                   p = c(0.10, 0.10, 0.20, 0.30, 0.30), name = "A"),
    prognose_zeile(18L, plaetze = 18, p = 1, name = "Letzter"),
    prognose_zeile(18L, plaetze = 2, p = 1, name = "Vize")
  )

  df <- fn(env, "rl_abstiegsprognose")("Nordost", prognose, zaehlung_nordost89())

  expect_s3_class(df, "data.frame")
  expect_equal(colnames(df), "Abstieg")
  expect_equal(rownames(df), c("A", "Letzter", "Vize"))
  expect_equal(df["A", "Abstieg"], 0.567, tolerance = 1e-12)
  expect_equal(df["Letzter", "Abstieg"], 1)
  expect_identical(df["Vize", "Abstieg"], 0)
})

test_that("rl_abstiegsprognose nimmt die Listenform der Engine-Antwort an", {
  env <- source_kopplung()
  m <- zaehlung_nordost89()
  als_liste <- lapply(seq_len(nrow(m)), function(i) as.list(m[i, ]))
  prognose <- prognose_zeile(18L, plaetze = c(17, 18), p = c(0.5, 0.5))

  df <- fn(env, "rl_abstiegsprognose")("Nordost", prognose, als_liste)
  expect_equal(df["A", "Abstieg"], 0.5 * 0.89 + 0.5)
})

test_that("Bayern: zwei getrennte Groessen, nicht zu einer Abstiegszahl verrechnet", {
  # 19 Teams (Bayern spielt 2026/27 ueber der Sollzahl). Direktabstieg =
  # die zwei Letzten (18, 19); Relegation = die zwei davor (16, 17).
  # Team B: 10 % Platz 15, 20 % Platz 16, 30 % Platz 17, 25 % Platz 18,
  # 15 % Platz 19.
  #   Relegation = 0.20 + 0.30 = 0.50
  #   Abstieg    = 0.25 + 0.15 = 0.40
  # Waere die Relegation zu 50 % "aufgeloest" und dazugezaehlt, staende
  # 0.65 da; waere sie voll dazugezaehlt, 0.90. Beides ist falsch: Wir
  # simulieren keine Bayernligisten und erfinden keine Gewinnquote.
  env <- source_kopplung()
  prognose <- rbind(
    prognose_zeile(19L, plaetze = 15:19, p = c(0.10, 0.20, 0.30, 0.25, 0.15),
                   name = "B"),
    prognose_zeile(19L, plaetze = 19, p = 1, name = "Letzter"),
    prognose_zeile(19L, plaetze = 17, p = 1, name = "Relegant")
  )
  counts <- zaehlung(Bayern = c(0, N_ITER, 0, 0, 0), Nord = c(0, 0, 0, N_ITER, 0))

  df <- fn(env, "rl_abstiegsprognose")("Bayern", prognose, counts)

  expect_equal(colnames(df), c("Relegation", "Abstieg"))
  expect_equal(df["B", "Relegation"], 0.50)
  expect_equal(df["B", "Abstieg"], 0.40)
  expect_false(isTRUE(all.equal(df["B", "Abstieg"], 0.65)))
  expect_false(isTRUE(all.equal(df["B", "Abstieg"], 0.90)))

  expect_equal(df["Letzter", "Abstieg"], 1)
  expect_identical(df["Letzter", "Relegation"], 0)
  expect_equal(df["Relegant", "Relegation"], 1)
  expect_identical(df["Relegant", "Abstieg"], 0)
})

test_that("Bayern: die Zaehlung der 3. Liga aendert das Ergebnis nicht", {
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  prognose <- prognose_zeile(19L, plaetze = 15:19, p = c(0.10, 0.20, 0.30, 0.25, 0.15))

  df_a <- f("Bayern", prognose,
            zaehlung(Bayern = c(0, N_ITER, 0, 0, 0), Nord = c(0, 0, 0, N_ITER, 0)))
  df_b <- f("Bayern", prognose,
            zaehlung(Bayern = c(N_ITER, 0, 0, 0, 0), Nord = c(0, 0, 0, 0, N_ITER)))

  expect_identical(df_a, df_b)
})

test_that("Bayern: Summe der Relegation ueber alle Teams ist exakt 2, Abstieg exakt 2", {
  # Zwei Teams gehen in die Relegation, zwei steigen direkt ab -- die
  # Spaltensummen ueber eine vollstaendige Prognose muessen das exakt
  # treffen. Waere die Relegation in den Abstieg eingerechnet, laege die
  # Abstiegssumme zwischen 2 und 4.
  env <- source_kopplung()
  n <- 19L
  ident <- diag(n)
  shift <- ident[c(2:n, 1), ]
  prognose <- 0.5 * ident + 0.5 * shift
  rownames(prognose) <- paste0("T", seq_len(n))
  counts <- zaehlung(Bayern = c(0, N_ITER, 0, 0, 0), Nord = c(0, 0, 0, N_ITER, 0))

  df <- fn(env, "rl_abstiegsprognose")("Bayern", prognose, counts)

  expect_equal(sum(df$Relegation), 2)
  expect_equal(sum(df$Abstieg), 2)
})

test_that("Nur Bayern bekommt eine Relegationsspalte", {
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  prognose <- prognose_zeile(18L, plaetze = c(17, 18), p = c(0.5, 0.5))
  counts <- zaehlung_nordost89()

  for (staffel in c("Nord", "Nordost", "West", "SuedWest")) {
    df <- f(staffel, prognose, counts)
    expect_equal(colnames(df), "Abstieg", info = staffel)
  }
})

test_that("rl_abstiegsprognose: Nord und SuedWest liefern verschiedene Zahlen als Nordost", {
  # Dieselbe Teamzeile, dieselbe Zaehlung -- drei verschiedene Ergebnisse,
  # weil die Basis verschieden ist. Nordost (Basis 1): 0.567.
  # Nord (Basis 3, P(k>=1) = 1, P(k>=2) = 0.11):
  #   Plaetze 16-18 sicher, Platz 15 zu 100 %, Platz 14 zu 11 %.
  #   Team A: 0.30 + 0.30 + 0.20 + 0.10 * 1 = 0.90
  # SuedWest (Basis 3, P(k>=1) = 1, P(k>=2) = 0):
  #   Team A: 0.30 + 0.30 + 0.20 + 0.10 * 1 = 0.90
  # West (entkoppelt, immer 4 Plaetze -> 15 bis 18):
  #   Team A: 0.30 + 0.30 + 0.20 + 0.10 * 1 = 0.90
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  prognose <- prognose_zeile(18L, plaetze = c(1, 15, 16, 17, 18),
                             p = c(0.10, 0.10, 0.20, 0.30, 0.30))
  counts <- zaehlung_nordost89()

  expect_equal(f("Nordost", prognose, counts)["A", "Abstieg"], 0.567, tolerance = 1e-12)
  expect_equal(f("Nord", prognose, counts)["A", "Abstieg"], 0.90, tolerance = 1e-12)
  expect_equal(f("SuedWest", prognose, counts)["A", "Abstieg"], 0.90, tolerance = 1e-12)
  expect_equal(f("West", prognose, counts)["A", "Abstieg"], 0.90, tolerance = 1e-12)
})

test_that("rl_abstiegsprognose bricht bei unbekannter Staffel ab, statt still zu raten", {
  env <- source_kopplung()
  prognose <- prognose_zeile(18L, plaetze = 18, p = 1)
  f <- fn(env, "rl_abstiegsprognose")
  expect_error(f("Sued", prognose, zaehlung_nordost89()), "Sued")
})

# --- Issue #185: P(Platz ist Abstiegsplatz) sichtbar machen ----------------
#
# platz_gewichte() rechnet die Zahl bereits aus; rl_abstiegsprognose()
# verdichtet sie sofort per Skalarprodukt zur Team-Wahrscheinlichkeit und
# wirft den Platzvektor weg. Genau dieser Zwischenwert ist es aber, den die
# Seite zeigen soll: Welcher Platz geht sicher runter, welcher nur
# vielleicht -- eine Aussage ueber den PLATZ, nicht ueber das Team.
#
# Der Vektor kommt als ATTRIBUT zurueck, nicht als zusaetzliche Spalte oder
# als Liste: Die Rueckgabe ist ein data.frame je Team (rownames = Teams).
# Eine Groesse je PLATZ passt dort in keine Spalte -- sie hat eine andere
# Laenge und eine andere Bedeutung. Als Attribut bleibt die bestehende
# Signatur unveraendert, und jeder vorhandene Aufrufer merkt nichts.

test_that("rl_abstiegsprognose reicht P(Platz ist Abstiegsplatz) als Attribut durch", {
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  gew <- fn(env, "platz_gewichte")
  verteilung <- fn(env, "absteiger_verteilung")

  prognose <- prognose_zeile(18L, plaetze = c(1, 15, 16, 17, 18),
                             p = c(0.10, 0.10, 0.20, 0.30, 0.30))
  counts <- zaehlung_nordost89()

  ergebnis <- f("Nordost", prognose, counts)
  platz_p <- attr(ergebnis, "platz_abstieg")

  # Genau der Vektor, den platz_gewichte() ohnehin berechnet -- keine
  # zweite Rechnung, die auseinanderlaufen koennte.
  expect_equal(platz_p, gew("Nordost", verteilung(counts), 18L),
               tolerance = 1e-12)
  expect_length(platz_p, 18L)

  # Nordost: Basis 1 Abstiegsplatz, mit 89 % ein zweiter. Platz 18 ist in
  # JEDEM Szenario Abstiegsplatz, Platz 17 nur im 89-%-Fall, Platz 16 nie.
  expect_equal(platz_p[[18]], 1, tolerance = 1e-12)
  expect_equal(platz_p[[17]], 0.89, tolerance = 1e-12)
  expect_equal(platz_p[[16]], 0, tolerance = 1e-12)
})

test_that("das Attribut laesst die bisherige Rueckgabe unveraendert", {
  # Absicherung der Entwurfsentscheidung: Ein Attribut darf den data.frame
  # nicht veraendern -- weder Spalten noch Zeilen noch Werte. Sonst haette
  # jeder bestehende Aufrufer eine stille Aenderung.
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  prognose <- prognose_zeile(18L, plaetze = c(17, 18), p = c(0.5, 0.5))
  counts <- zaehlung_nordost89()

  ergebnis <- f("Nordost", prognose, counts)

  expect_identical(names(ergebnis), "Abstieg")
  expect_identical(rownames(ergebnis), rownames(prognose))
  # Der Wert entsteht weiterhin aus Prognose x Gewichten.
  expect_equal(ergebnis["A", "Abstieg"],
               0.5 * 0.89 + 0.5 * 1, tolerance = 1e-12)
})

test_that("Bayern reicht Relegations- und Abstiegsplaetze GETRENNT durch", {
  # Die beiden Groessen duerfen nicht zu einer Zahl addiert werden (das ist
  # der ausdrueckliche Punkt 3 aus Issue #185): Die zwei Letzten steigen
  # direkt ab, die zwei davor spielen Relegation gegen die Bayernliga --
  # ein Ausgang, den wir nicht simulieren. Zwei Attribute, zwei Farben.
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")

  prognose <- prognose_zeile(19L, plaetze = c(16, 17, 18, 19),
                             p = c(0.25, 0.25, 0.25, 0.25))
  ergebnis <- f("Bayern", prognose, zaehlung_nordost89())

  platz_ab <- attr(ergebnis, "platz_abstieg")
  platz_rel <- attr(ergebnis, "platz_relegation")

  expect_length(platz_ab, 19L)
  expect_length(platz_rel, 19L)

  # 19 Teams: Direktabstieg auf 18 und 19, Relegation auf 16 und 17.
  expect_equal(platz_ab[c(18, 19)], c(1, 1), tolerance = 1e-12)
  expect_equal(platz_ab[c(16, 17)], c(0, 0), tolerance = 1e-12)
  expect_equal(platz_rel[c(16, 17)], c(1, 1), tolerance = 1e-12)
  expect_equal(platz_rel[c(18, 19)], c(0, 0), tolerance = 1e-12)

  # Und sie bleiben getrennt: kein Platz traegt beides.
  expect_true(all(platz_ab * platz_rel == 0))
})

test_that("nur Bayern traegt ein Relegations-Attribut", {
  # Die anderen vier Staffeln kennen keine Abstiegsrelegation. Ein Attribut
  # mit lauter Nullen waere schlimmer als keines: Der Renderer muesste
  # raten, ob "alles 0" bedeutet "keine Relegation" oder "Relegation, aber
  # gerade unwahrscheinlich".
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  prognose <- prognose_zeile(18L, plaetze = 18, p = 1)

  for (staffel in c("Nord", "Nordost", "West", "SuedWest")) {
    ergebnis <- f(staffel, prognose, zaehlung_nordost89())
    expect_null(attr(ergebnis, "platz_relegation"), info = staffel)
    expect_false(is.null(attr(ergebnis, "platz_abstieg")), info = staffel)
  }
})

test_that("Nords Meisteraufstieg senkt auch die PLATZ-Wahrscheinlichkeiten", {
  # Steigt der Nord-Meister auf, hat Nord einen Abstiegsplatz weniger. Das
  # wirkt schon auf die Team-Zahl (Test weiter oben) -- der Platzvektor muss
  # dieselbe Mischung tragen, sonst widersprechen sich Linie und Fussnote
  # auf derselben Seite.
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  gew <- fn(env, "platz_gewichte")
  verteilung <- fn(env, "absteiger_verteilung")
  counts <- zaehlung_nordost89()
  prognose <- prognose_zeile(18L, plaetze = 18, p = 1)

  ohne <- attr(f("Nord", prognose, counts), "platz_abstieg")
  mit <- attr(f("Nord", prognose, counts, p_meister_aufstieg = 0.4),
              "platz_abstieg")

  expect_equal(mit, gew("Nord", verteilung(counts), 18L,
                        p_meister_aufstieg = 0.4), tolerance = 1e-12)
  # Weniger Abstiegsplaetze heisst: kein Platz wird gefaehrdeter.
  expect_true(all(mit <= ohne + 1e-12))
  expect_true(any(mit < ohne - 1e-12))
})
