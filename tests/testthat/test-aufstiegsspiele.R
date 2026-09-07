library(testthat)

# Phase 7, Nachtrag: Die Zweikampfquote p_sieg fuer die Aufstiegsspiele
# Nord gegen Bayern wird aus dem Tormodell GERECHNET statt gefordert.
#
# Bis hierher war p_sieg in rl_aufstiegsprognose() ein reiner Eingang; ohne
# ihn bricht die Funktion ab (test-rl-aufstieg.R, "Playoff-Staffel ohne
# Gewinnquoten bricht ab"). Das bleibt so -- ein expliziter p_sieg hat
# Vorrang. Neu ist, dass die Matrix aus den Tor-Raten hergeleitet wird, die
# der Rust-Server fuer jede Paarung liefert.
#
# ARCHITEKTUR (Entscheidung des Nutzers, ADR 0002: kein Nachbau der
# Modelllogik in R -- der Nachtrag dort zeigt, wie beim Heimvorteil vier
# R-Stellen den Rust-Default nie sahen):
#
#   Rust  POST /match-preview -- ein virtuelles Spiel ohne Spielplan.
#         Eingabe:  elo_home, elo_away, optional home_advantage, tore_slope,
#                   tore_intercept, max_goals
#         Ausgabe:  lambda_home, lambda_away, p_home_win, p_draw, p_away_win,
#                   score_matrix (wie in /league-details)
#         Rechnet mit der VORHANDENEN Funktion match_probabilities() in
#         league_details/mod.rs; die Formel ELO -> lambda und die Konstanten
#         leben nur dort. Getestet in league-simulator-rust/src/api/tests.rs.
#
#   R     RCode/aufstiegsspiele.R macht NUR Kombinatorik auf gegebenen
#         Tor-Raten: Poisson-Differenz je Spiel, Faltung ueber zwei Spiele,
#         Verlaengerung, Elfmeter. KEIN lambda aus ELO, KEINE
#         Tormodell-Konstanten. Der Client, der die Raten holt, liegt in
#         RCode/rust_integration.R.
#
# MODUS (docs/abstieg_aufstieg_RL_2026_2027.md, Abschnitt 1: Par. 55b Nr. 2
# DFB-SpO, "zwei Aufstiegsspiele", Hin- und Rueckspiel):
#
#   Hinspiel:       90 Min, Heimvorteil fuer A
#   Rueckspiel:     90 Min, Heimvorteil fuer B (getauscht)
#   Gleichstand nach zwei Spielen -> Verlaengerung, 30 Min, OHNE Heimvorteil,
#                   Tor-Rate lambda_ev = lambda_90 / 3 (lambda_90 = neutrale
#                   90-Minuten-Rate). Reine Spielzeit-Proportionalitaet,
#                   bewusst KEINE Verhaltensannahme: Dass Verlaengerungen
#                   empirisch torarmer sind, ist eine bekannte, bewusst nicht
#                   eingebaute Verfeinerung.
#   Danach immer noch Gleichstand -> Elfmeterschiessen, 50:50.
#
#   Die Verlaengerung ist ohne Heimvorteil, weil nicht ermittelbar ist, wer
#   sie zu Hause bestreitet: Das Heimrecht wird bei Nord/Bayern vor
#   Saisonbeginn ausgelost (Doku Abschnitt 1).
#
#   AUSWAERTSTORREGEL: Es gibt Heimrecht, also gibt es auch Auswaertstore.
#   Die Regel wird trotzdem NICHT modelliert -- eine bewusste AUSLASSUNG,
#   weil sie in der DFB-Aufstiegsrelegation abgeschafft ist. Gezaehlt wird
#   allein die Gesamttordifferenz ueber beide Spiele.
#
# GERECHNET WIRD ANALYTISCH, kein Monte Carlo. Die Tore je Team und Spiel
# sind unabhaengig Poisson; die Tordifferenz eines Spiels ist die Faltung,
# die Gesamtdifferenz ueber zwei Spiele die Faltung der Einzelspiel-
# Differenzen.
#
# DER HEIMVORTEIL HEBT SICH IN DER GESAMTQUOTE EXAKT AUF: Im Rust-Modell ist
# lambda linear in der ELO-Differenz, der Heimvorteil additiv darauf
# (lambda_heim = lambda_neutral + h * s). Die Summe unabhaengiger Poisson-
# Variablen ist Poisson: A's Gesamttore ueber beide Spiele sind
# Pois(lambda_hin + lambda_rueck), und lambda_hin + lambda_rueck =
# 2 * lambda_neutral ist von h unabhaengig -- ebenso fuer B. Die Verteilung
# der Gesamtdifferenz, P(Gleichstand) und die Quote sind deshalb mit
# Heimvorteil 40 EXAKT dieselben wie mit 0 (solange die 0.001-Klemme nicht
# greift). Die Erwartung, ein getauschtes Heimrecht erzeuge "mehr klare
# Ergebnisse, seltener Gleichstand", trifft in diesem linearen Modell nicht
# zu. Der Heimvorteil wirkt sehr wohl im EINZELSPIEL, und der Symmetrie-Test
# faengt einen Heimvorteil, der beidesmal derselben Seite zugeschlagen wird.
#
# Erwartete Implementierung:
#
# RCode/aufstiegsspiele.R (reine Kombinatorik, kein Modellwissen):
#
#   tordifferenz_verteilung(lambda_a, lambda_b, max_tore = 15)
#     -> benannter numerischer Vektor der Laenge 2 * max_tore + 1,
#        names = as.character(-max_tore:max_tore),
#        v[["d"]] = P(Tore A - Tore B = d) in EINEM Spiel; zwei unabhaengige
#        Poisson, je Team auf 0..max_tore abgeschnitten (keine Renormierung;
#        der Rest ist bei realistischen lambda < 1e-9).
#
#   verlaengerung_lambda(lambda_90)
#     -> lambda_90 / 3, vektorisiert, Namen bleiben erhalten.
#
#   zweikampf_quote(hin, rueck, neutral, max_tore = 15)
#     hin     = c(a, b): Tor-Raten von A und B im Hinspiel (A hat Heimrecht)
#     rueck   = c(a, b): dito im Rueckspiel (B hat Heimrecht)
#     neutral = c(a, b): dito ohne Heimvorteil; daraus wird intern die
#               Verlaengerungs-Rate neutral / 3.
#     -> EINE Zahl in [0, 1]: P(A setzt sich durch).
#     Jedes Argument: numerisch, Laenge 2, nicht-negativ, sonst Fehler.
#
#   p_sieg_matrix(paarungen, max_tore = 15)
#     paarungen: data.frame mit den Spalten a, b (Teamnamen) und hin_a,
#     hin_b, rueck_a, rueck_b, neutral_a, neutral_b (Tor-Raten) -- eine Zeile
#     je Paar, so wie zweikampf_paarungen_rust() sie liefert.
#     -> Matrix mit dimnames list(unique(a), unique(b)),
#        M[a, b] = zweikampf_quote(c(hin_a, hin_b), c(rueck_a, rueck_b),
#                                  c(neutral_a, neutral_b)).
#        Fehlt eine Paarung a x b -> Fehler, der das Paar nennt.
#
#   rl_aufstiegsprognose(staffel, prognosen, season, p_sieg = NULL,
#                        rotation = AUFSTIEGSROTATION, paarungen = NULL)
#     Vorrang: p_sieg explizit > p_sieg_matrix(paarungen) > Fehler ("p_sieg").
#     paarungen: a = Teams der in STAFFELN frueheren Staffel (Nord), b =
#     Teams der spaeteren (Bayern) -- dieselbe Orientierung wie p_sieg.
#     Fehlt ein Team der Prognosematrix in paarungen -> Fehler, der das
#     Team nennt.
#
# RCode/rust_integration.R (Client, Integrationstests unten):
#
#   match_preview_rust(elo_home, elo_away, home_advantage = NULL,
#                      tore_slope = NULL, tore_intercept = NULL,
#                      max_goals = NULL)
#     -> list(lambda_home, lambda_away, p_home_win, p_draw, p_away_win,
#             score_matrix) -- NULL-Felder werden nicht gesendet, der Server
#        nimmt seine Defaults (ADR 0002).
#
#   zweikampf_paarungen_rust(elo_a, elo_b, tore_slope = NULL,
#                            tore_intercept = NULL)
#     elo_a, elo_b: benannte ELO-Vektoren beider Staffeln.
#     -> das paarungen-data.frame: je Paar drei Aufrufe (A heim, B heim,
#        home_advantage = 0 fuer die Verlaengerung).
#
# Die drei bestehenden Testdateien (test-rl-aufstieg.R, test-rl-nord-
# aufstiegskopplung.R, test-rl-abstiegskopplung.R) bleiben unveraendert und
# muessen gruen bleiben.

source_aufstiegsspiele <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  for (datei in c("rl_abstiegskopplung.R", "rl_aufstieg.R", "aufstiegsspiele.R")) {
    pfad <- test_path("..", "..", "RCode", datei)
    if (file.exists(pfad)) source(pfad, local = env)
  }
  env
}

fn <- function(env, name) {
  if (!exists(name, envir = env, inherits = FALSE)) {
    stop(sprintf(
      "Funktion '%s' nicht gefunden -- erwartet in RCode/aufstiegsspiele.R (Client: rust_integration.R)",
      name
    ), call. = FALSE)
  }
  get(name, envir = env, inherits = FALSE)
}

# --- Fixtures: Tor-Raten, wie /match-preview sie liefert ---------------------
#
# Die Herren-Konstanten stehen NUR hier im Test, um Fixtures zu erzeugen --
# so, wie der Endpunkt sie mit seinen Defaults liefert (belegt durch die
# Rust-Tests in api/tests.rs: match_preview_returns_rust_goal_model_lambdas).
# Die R-Implementierung darf sie nicht kennen.

HERREN_SLOPE <- 0.0017854953143549
HERREN_INTERCEPT <- 1.3218390804597700

endpunkt_lambdas <- function(elo_heim, elo_gast, ha = 40, slope = HERREN_SLOPE,
                             intercept = HERREN_INTERCEPT) {
  delta <- elo_heim + ha - elo_gast
  c(heim = max(delta * slope + intercept, 0.001),
    gast = max(-delta * slope + intercept, 0.001))
}

# Die drei Raten-Paare eines Zweikampfs A gegen B, jeweils als c(a, b).
zweikampf_lambdas <- function(elo_a, elo_b, ha = 40, slope = HERREN_SLOPE,
                              intercept = HERREN_INTERCEPT) {
  hin <- endpunkt_lambdas(elo_a, elo_b, ha, slope, intercept)
  r <- endpunkt_lambdas(elo_b, elo_a, ha, slope, intercept)
  n <- endpunkt_lambdas(elo_a, elo_b, 0, slope, intercept)
  list(hin = c(a = hin[["heim"]], b = hin[["gast"]]),
       rueck = c(a = r[["gast"]], b = r[["heim"]]),
       neutral = c(a = n[["heim"]], b = n[["gast"]]))
}

# Die vorgerechneten Raten fuer 1600 gegen 1400 (Heimvorteil 40):
#   hin     = (1.679057, 0.964621)   ELO-Delta +240
#   rueck   = (1.607637, 1.036041)   ELO-Delta +160 (A auswaerts)
#   neutral = (1.643347, 1.000331)   ELO-Delta +200
L_1600_1400 <- zweikampf_lambdas(1600, 1400)
# 1500 gegen 1500 (Heimvorteil 40): hin = (1.393259, 1.250419), rueck
# gespiegelt, neutral = (1.321839, 1.321839).
L_GLEICH <- zweikampf_lambdas(1500, 1500)

# --- Unabhaengiges Orakel ------------------------------------------------------
#
# Bewusst NICHT ueber eine Faltung gerechnet, sondern ueber die
# Poisson-Additivitaet: A gesamt ~ Pois(hin_a + rueck_a), B gesamt ~
# Pois(hin_b + rueck_b). P(A vorn) = SUMME_k P(A = k) * P(B <= k - 1).
# Stimmt die Implementierung mit diesem Orakel ueberein, ist die Faltung
# richtig -- zwei voellig verschiedene Rechenwege, ein Ergebnis.

orakel_stufen <- function(hin, rueck, ev, N = 300) {
  A <- hin[[1]] + rueck[[1]]
  B <- hin[[2]] + rueck[[2]]
  k <- 0:N
  # ppois(-1, .) ist 0 -- der Term k = 0 traegt zu "A vorn" nichts bei.
  list(
    p_a_vorn = sum(dpois(k, A) * ppois(k - 1, B)),
    p_gleich = sum(dpois(k, A) * dpois(k, B)),
    p_a_ev = sum(dpois(k, ev[[1]]) * ppois(k - 1, ev[[2]])),
    p_gleich_ev = sum(dpois(k, ev[[1]]) * dpois(k, ev[[2]]))
  )
}

# ev_faktor: Anteil der Verlaengerungs-Rate an der 90-Minuten-Rate (1/3).
# verlaengerung = FALSE: bei Gleichstand direkt der Muenzwurf.
orakel_quote <- function(hin, rueck, neutral, ev_faktor = 1 / 3,
                         verlaengerung = TRUE) {
  st <- orakel_stufen(hin, rueck, neutral * ev_faktor)
  if (!verlaengerung) {
    return(st$p_a_vorn + 0.5 * st$p_gleich)
  }
  st$p_a_vorn + st$p_gleich * (st$p_a_ev + 0.5 * st$p_gleich_ev)
}

orakel_elo <- function(elo_a, elo_b, ha = 40, slope = HERREN_SLOPE,
                       intercept = HERREN_INTERCEPT, ...) {
  L <- zweikampf_lambdas(elo_a, elo_b, ha, slope, intercept)
  orakel_quote(L$hin, L$rueck, L$neutral, ...)
}

# Skellam-Dichte: P(Pois(la) - Pois(lb) = d), geschlossene Form ueber die
# modifizierte Besselfunktion. Unabhaengige Kontrolle der Faltung.
skellam <- function(d, la, lb) {
  exp(-(la + lb)) * (la / lb)^(d / 2) * besselI(2 * sqrt(la * lb), abs(d))
}

# --- tordifferenz_verteilung: ein Spiel ---------------------------------------

test_that("tordifferenz_verteilung: Form -- Laenge 2 * max_tore + 1, Namen -max_tore..max_tore", {
  env <- source_aufstiegsspiele()
  f <- fn(env, "tordifferenz_verteilung")

  v <- f(1.3, 1.1, max_tore = 15)
  expect_length(v, 31)
  expect_identical(names(v), as.character(-15:15))
  expect_true(all(v >= 0))

  v5 <- f(1.3, 1.1, max_tore = 5)
  expect_length(v5, 11)
  expect_identical(names(v5), as.character(-5:5))
})

test_that("tordifferenz_verteilung stimmt mit der Skellam-Dichte ueberein (lambda 1 gegen 1)", {
  # Geschlossene Form: P(D = d) = exp(-2) * I_|d|(2).
  #   P(D = 0) = 0.308508322553671
  #   P(D = 1) = P(D = -1) = 0.215269289248938
  env <- source_aufstiegsspiele()
  f <- fn(env, "tordifferenz_verteilung")
  v <- f(1, 1, max_tore = 15)

  expect_equal(v[["0"]], 0.308508322553671, tolerance = 1e-12)
  expect_equal(v[["1"]], 0.215269289248938, tolerance = 1e-12)
  expect_equal(v[["-1"]], 0.215269289248938, tolerance = 1e-12)
  expect_equal(v[["0"]], exp(-2) * besselI(2, 0), tolerance = 1e-12)
  # Jede Differenz gegen die Besselform, bis in den Schwanz.
  for (d in -8:8) {
    expect_equal(v[[as.character(d)]], skellam(d, 1, 1), tolerance = 1e-12,
                 info = paste("d =", d))
  }
})

test_that("tordifferenz_verteilung stimmt mit der Skellam-Dichte ueberein (lambda 1.5 gegen 1.2)", {
  # P(D = -2) = 0.084798943251594
  env <- source_aufstiegsspiele()
  f <- fn(env, "tordifferenz_verteilung")
  v <- f(1.5, 1.2, max_tore = 15)

  expect_equal(v[["-2"]], 0.084798943251594, tolerance = 1e-12)
  for (d in -8:8) {
    expect_equal(v[[as.character(d)]], skellam(d, 1.5, 1.2), tolerance = 1e-12,
                 info = paste("d =", d))
  }
  # Das staerkere Team liegt haeufiger vorn.
  expect_gt(sum(v[as.character(1:15)]), sum(v[as.character(-15:-1)]))
  # P(A vorn) nach der Orakelformel: SUMME_k dpois(k, 1.5) * ppois(k - 1, 1.2).
  k <- 0:100
  expect_equal(sum(v[as.character(1:15)]),
               sum(dpois(k, 1.5) * ppois(k - 1, 1.2)), tolerance = 1e-10)
  expect_equal(v[["0"]], sum(dpois(k, 1.5) * dpois(k, 1.2)), tolerance = 1e-12)
})

test_that("tordifferenz_verteilung: Spiegelung -- P_(a,b)(d) = P_(b,a)(-d)", {
  env <- source_aufstiegsspiele()
  f <- fn(env, "tordifferenz_verteilung")
  v <- f(1.7, 0.9, max_tore = 12)
  w <- f(0.9, 1.7, max_tore = 12)
  expect_equal(unname(v), unname(rev(w)), tolerance = 1e-14)
  # Bei gleichen lambda ist die Verteilung exakt symmetrisch.
  s <- f(1.32, 1.32, max_tore = 12)
  expect_equal(unname(s), unname(rev(s)), tolerance = 1e-15)
})

test_that("tordifferenz_verteilung ist die Antidiagonalsumme der Rust-score_matrix", {
  # /match-preview und /league-details liefern score_matrix[i][j] =
  # P(Heim i, Gast j) = pmf_home[i] * pmf_away[j] (league_details/mod.rs).
  # Die Differenzverteilung ist die Summe ueber die Antidiagonalen i - j = d.
  # Die Raten sind die von 1500 gegen 1400 mit Heimvorteil 40.
  env <- source_aufstiegsspiele()
  f <- fn(env, "tordifferenz_verteilung")
  la <- 1.57180842446946
  lb <- 1.07186973645008
  N <- 15
  score_matrix <- outer(dpois(0:N, la), dpois(0:N, lb))   # [i+1, j+1]
  v <- f(la, lb, max_tore = N)
  for (d in -N:N) {
    i <- 0:N
    j <- i - d
    ok <- j >= 0 & j <= N
    erwartet <- sum(score_matrix[cbind(i[ok] + 1, j[ok] + 1)])
    expect_equal(v[[as.character(d)]], erwartet, tolerance = 1e-14,
                 info = paste("d =", d))
  }
})

test_that("tordifferenz_verteilung summiert auf 1 bis auf einen Rest < 1e-9", {
  # Realistische Herren-Raten liegen zwischen ~0.7 und ~1.93 (ELO-Differenz
  # +-300 plus Heimvorteil 40). Der Poisson-Schwanz jenseits von 15 Toren
  # ist bei 1.93 noch 2.9e-10, bei 1.32 nur 1.2e-12. Keine Renormierung --
  # die Summe darf 1 nicht ueberschreiten, und der Rest ist genau der
  # Schwanz beider Seiten.
  env <- source_aufstiegsspiele()
  f <- fn(env, "tordifferenz_verteilung")

  for (paar in list(c(1.32, 1.32), c(1.9, 0.8), c(1.93, 0.72), c(0.001, 1.5))) {
    s <- sum(f(paar[1], paar[2], max_tore = 15))
    expect_lte(s, 1 + 1e-12)
    expect_gte(s, 1 - 1e-9)
    rest <- 1 - ppois(15, paar[1]) * ppois(15, paar[2])
    expect_equal(1 - s, rest, tolerance = 1e-12)
    expect_lt(rest, 1e-9)
  }

  # Der Schwanz waechst mit lambda: Wer das Modell mit Raten > 2.2 je Spiel
  # benutzt (ELO-Differenz > 450), muss max_tore erhoehen. Ein groesseres
  # max_tore drueckt den Rest unter jede Schwelle.
  expect_gt(1 - sum(f(2.5, 2.5, max_tore = 15)), 1e-9)
  expect_lt(1 - sum(f(2.5, 2.5, max_tore = 30)), 1e-15)
})

test_that("tordifferenz_verteilung: lambda 0 auf einer Seite -- die Differenz ist die Poisson-Verteilung selbst", {
  env <- source_aufstiegsspiele()
  f <- fn(env, "tordifferenz_verteilung")
  v <- f(1, 0, max_tore = 10)
  expect_equal(v[["0"]], exp(-1), tolerance = 1e-14)
  expect_equal(v[["1"]], exp(-1), tolerance = 1e-14)
  expect_equal(v[["2"]], exp(-1) / 2, tolerance = 1e-14)
  expect_equal(v[["3"]], exp(-1) / 6, tolerance = 1e-14)
  expect_equal(sum(v[as.character(-10:-1)]), 0)
})

# --- verlaengerung_lambda: lambda / 3, explizit ------------------------------

test_that("verlaengerung_lambda ist exakt lambda_90 / 3 -- Spielzeit-Proportionalitaet", {
  env <- source_aufstiegsspiele()
  f <- fn(env, "verlaengerung_lambda")
  expect_identical(f(1.5), 0.5)
  expect_identical(f(0.9), 0.3)
  expect_equal(f(1.3218390804597700), 1.3218390804597700 / 3, tolerance = 1e-15)
  expect_equal(f(c(1.2, 2.4)), c(0.4, 0.8), tolerance = 1e-15)
  # Ein benannter Vektor behaelt seine Namen.
  expect_equal(f(c(a = 1.5, b = 0.6)), c(a = 0.5, b = 0.2), tolerance = 1e-15)
})

# --- zweikampf_quote: Symmetrie, Summe, Monotonie ----------------------------
#
# Die Exaktheitstests (Toleranz 1e-12) laufen mit max_tore = 40: Bei
# max_tore = 15 kostet die Abschneidung je Spiel bis zu ~1e-9 Masse, und
# ohne Renormierung verschiebt das eine 0.5 um ~1e-10 -- das ist kein
# Faltungsfehler, sondern der Schwanz. Was die Abschneidung bei 15 kostet,
# ist unten separat quantifiziert ("max_tore: ..."). Ein Indexfehler in
# der Faltung liegt dagegen bei 1e-2 und faellt hier sofort auf.

MAX_TORE_EXAKT <- 40

test_that("Symmetrie: gleiche Staerke -> Quote exakt 0.5, MIT Heimvorteil in beiden Spielen", {
  # Der schaerfste Test. Beide Einzelspiele sind asymmetrisch (Heimvorteil:
  # hin = (1.393, 1.250), rueck = (1.250, 1.393)), aber wer im Hinspiel
  # Heimrecht hat, hat es im Rueckspiel nicht. Er faengt Indexfehler in der
  # Faltung UND einen Heimvorteil, der nur einmal oder beidesmal derselben
  # Seite zugeschlagen wird.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")

  expect_equal(q(L_GLEICH$hin, L_GLEICH$rueck, L_GLEICH$neutral,
                 max_tore = MAX_TORE_EXAKT), 0.5, tolerance = 1e-12)
  # Anderes Niveau, anderes Tormodell (Frauen-Raten), groesserer Heimvorteil.
  for (L in list(zweikampf_lambdas(1200, 1200), zweikampf_lambdas(1800, 1800),
                 zweikampf_lambdas(1500, 1500, slope = 0.0024058833,
                                   intercept = 1.6527603153),
                 zweikampf_lambdas(1500, 1500, ha = 200))) {
    expect_equal(q(L$hin, L$rueck, L$neutral, max_tore = MAX_TORE_EXAKT), 0.5,
                 tolerance = 1e-12)
  }
  # Und mit dem Default max_tore = 15: 0.5 bis auf den Schwanz.
  expect_equal(q(L_GLEICH$hin, L_GLEICH$rueck, L_GLEICH$neutral), 0.5,
               tolerance = 1e-9)
})

test_that("Symmetrie-Gegenprobe: Heimvorteil beidesmal fuer A ergaebe 0.548, nicht 0.5", {
  # Der Nachweis, dass der Symmetrie-Test den Bug wirklich faengt: rueck =
  # hin (A hat zweimal Heimrecht) liefert bei gleicher Staerke 0.548. Die
  # Implementierung muss mit den richtigen Raten bei 0.5 liegen -- und mit
  # den falschen Raten selbst 0.548 liefern, sonst rechnet sie das Rueckspiel
  # nicht aus seinen eigenen Raten.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")

  bug <- orakel_quote(L_GLEICH$hin, L_GLEICH$hin, L_GLEICH$neutral)
  expect_equal(bug, 0.548242613492610, tolerance = 1e-12)

  expect_equal(q(L_GLEICH$hin, L_GLEICH$rueck, L_GLEICH$neutral,
                 max_tore = MAX_TORE_EXAKT), 0.5, tolerance = 1e-12)
  expect_equal(q(L_GLEICH$hin, L_GLEICH$hin, L_GLEICH$neutral,
                 max_tore = MAX_TORE_EXAKT), bug, tolerance = 1e-12)
})

test_that("Symmetrie ohne Heimvorteil: alle Raten gleich -> exakt 0.5", {
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")
  n <- c(1.3218390804597700, 1.3218390804597700)
  expect_equal(q(n, n, n, max_tore = MAX_TORE_EXAKT), 0.5, tolerance = 1e-12)
  expect_equal(q(c(0.4, 0.4), c(0.4, 0.4), c(0.4, 0.4), max_tore = MAX_TORE_EXAKT),
               0.5, tolerance = 1e-12)
})

test_that("Summe zu 1: quote aus Sicht von A + quote aus Sicht von B == 1", {
  # Aus Sicht von B sind die Paare vertauscht: B's Hinspiel ist A's
  # Hinspiel mit getauschten Rollen.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")

  for (paar in list(c(1600, 1400), c(1520, 1480), c(1300, 1700), c(1500, 1900))) {
    for (ha in c(0, 40)) {
      L <- zweikampf_lambdas(paar[1], paar[2], ha)
      s <- q(L$hin, L$rueck, L$neutral, max_tore = MAX_TORE_EXAKT) +
        q(rev(L$hin), rev(L$rueck), rev(L$neutral), max_tore = MAX_TORE_EXAKT)
      expect_equal(s, 1, tolerance = 1e-12,
                   info = sprintf("%s gegen %s, ha = %s", paar[1], paar[2], ha))
    }
  }
  # Mit dem Default max_tore = 15 fehlt hoechstens der Schwanz (< 1e-8).
  L <- L_1600_1400
  s15 <- q(L$hin, L$rueck, L$neutral) + q(rev(L$hin), rev(L$rueck), rev(L$neutral))
  expect_equal(s15, 1, tolerance = 1e-8)
  expect_lte(s15, 1 + 1e-12)
})

test_that("Monotonie: hoehere Raten fuer A -> hoehere Quote, streng monoton", {
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")

  # A's Rate waechst in allen drei Spielen, B's bleibt.
  gitter <- seq(0.6, 2.2, by = 0.1)
  quoten <- vapply(gitter, function(la) {
    q(c(la + 0.07, 1.25), c(la - 0.07, 1.39), c(la, 1.32), max_tore = MAX_TORE_EXAKT)
  }, numeric(1))
  expect_true(all(diff(quoten) > 0))
  expect_true(all(quoten >= 0 & quoten <= 1))

  # Und ueber ELO: unter 1500 < 0.5, ueber 1500 > 0.5, bei 1500 exakt 0.5.
  elo_gitter <- seq(1200, 1800, by = 50)
  q_elo <- vapply(elo_gitter, function(e) {
    L <- zweikampf_lambdas(e, 1500)
    q(L$hin, L$rueck, L$neutral, max_tore = MAX_TORE_EXAKT)
  }, numeric(1))
  expect_true(all(diff(q_elo) > 0))
  expect_true(all(q_elo[elo_gitter < 1500] < 0.5))
  expect_true(all(q_elo[elo_gitter > 1500] > 0.5))
  expect_equal(q_elo[elo_gitter == 1500], 0.5, tolerance = 1e-12)
})

# --- zweikampf_quote: Werte gegen das Orakel ----------------------------------

test_that("Wert: die Raten von 1600 gegen 1400 -> 0.741839833112276", {
  # Vorgerechnet mit dem Poisson-Additivitaets-Orakel oben.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")
  L <- L_1600_1400

  quote <- q(L$hin, L$rueck, L$neutral, max_tore = MAX_TORE_EXAKT)
  expect_equal(quote, 0.741839833112276, tolerance = 1e-12)
  expect_equal(quote, orakel_quote(L$hin, L$rueck, L$neutral), tolerance = 1e-12)
  expect_equal(q(rev(L$hin), rev(L$rueck), rev(L$neutral), max_tore = MAX_TORE_EXAKT),
               1 - 0.741839833112276, tolerance = 1e-12)
  # Mit dem Default max_tore = 15 auf 1e-9 -- der Schwanz bei Rate 1.68
  # ist 4e-11 je Spiel.
  expect_equal(q(L$hin, L$rueck, L$neutral), 0.741839833112276, tolerance = 1e-9)
})

test_that("Werte: die Implementierung stimmt ueber ein Raten-Gitter mit dem Orakel ueberein", {
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")

  for (ea in c(1350, 1500, 1650)) {
    for (eb in c(1400, 1550, 1700)) {
      for (ha in c(0, 40)) {
        L <- zweikampf_lambdas(ea, eb, ha)
        expect_equal(q(L$hin, L$rueck, L$neutral, max_tore = MAX_TORE_EXAKT),
                     orakel_quote(L$hin, L$rueck, L$neutral), tolerance = 1e-12,
                     info = sprintf("%s gegen %s, ha = %s", ea, eb, ha))
      }
    }
  }
  # Beliebige Raten ohne ELO-Bezug: dieselbe Kombinatorik.
  expect_equal(q(c(2.0, 0.5), c(1.1, 0.9), c(1.5, 0.8), max_tore = MAX_TORE_EXAKT),
               orakel_quote(c(2.0, 0.5), c(1.1, 0.9), c(1.5, 0.8)), tolerance = 1e-12)
})

test_that("Randfall: winzige Raten -> fast immer 0:0 -> fast immer Elfmeter -> Quote nahe 0.5", {
  # Raten 0.0021 gegen 0.0019: Praktisch jedes Spiel endet 0:0, die
  # Verlaengerung auch, es entscheidet die Muenze.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")

  a <- c(0.0021, 0.0019)
  quote <- q(a, a, a)
  expect_gt(quote, 0.5)
  expect_lt(quote, 0.5 + 1e-3)
  expect_equal(quote, orakel_quote(a, a, a), tolerance = 1e-12)
})

test_that("Randfall: sehr grosse Staerkedifferenz -> Quote nahe 1, aber nie ueber 1", {
  # ELO-Differenz 1000 ohne Heimvorteil: Rate 3.11 gegen die Klemme 0.001.
  # B trifft praktisch nie; A verliert nur, wenn es in beiden Spielen und
  # der Verlaengerung torlos bleibt und dann die Muenze verliert.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")

  L <- zweikampf_lambdas(2500, 1500, ha = 0)
  expect_identical(unname(L$hin[["b"]]), 0.001)
  quote <- q(L$hin, L$rueck, L$neutral, max_tore = 30)
  expect_lte(quote, 1)
  expect_gt(quote, 0.999)
  expect_equal(quote, 0.99963710020780772, tolerance = 1e-9)

  # Und die Gegenrichtung: nie unter 0.
  gegen <- q(rev(L$hin), rev(L$rueck), rev(L$neutral), max_tore = 30)
  expect_gte(gegen, 0)
  expect_lt(gegen, 0.001)
  expect_equal(quote + gegen, 1, tolerance = 1e-12)

  # Noch extremer (Rate 7.57), mit max_tore gross genug: immer noch <= 1.
  X <- zweikampf_lambdas(5000, 1500)
  extrem <- q(X$hin, X$rueck, X$neutral, max_tore = 80)
  expect_lte(extrem, 1)
  expect_gt(extrem, 0.9999)
})

test_that("zweikampf_quote lehnt unbrauchbare Raten ab", {
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")
  ok <- c(1.3, 1.1)
  expect_error(q(c(1.3), ok, ok))               # Laenge 1
  expect_error(q(ok, c(1.3, 1.1, 0.9), ok))     # Laenge 3
  expect_error(q(ok, ok, c(-0.1, 1.1)))         # negativ
  expect_error(q(ok, c(NA_real_, 1.1), ok))     # NA
  expect_error(q(ok, ok, NULL))                 # fehlt
})

# --- Verlaengerung und Elfmeter: wirksam und richtig parametrisiert -----------

test_that("Die Verlaengerung ist wirksam: gegen die Rechnung 'Gleichstand -> sofort Muenze'", {
  # Bei ungleichen Raten muessen sich die Zahlen unterscheiden, und die
  # Quote des staerkeren Teams muss MIT Verlaengerung hoeher sein: Es
  # bekommt noch eine Chance, statt in den Muenzwurf zu gehen.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")
  L <- L_1600_1400

  mit <- q(L$hin, L$rueck, L$neutral, max_tore = MAX_TORE_EXAKT)
  ohne <- orakel_quote(L$hin, L$rueck, L$neutral, verlaengerung = FALSE)

  # 0.7418 gegen 0.7295: die Verlaengerung ist 1.2 Prozentpunkte wert.
  expect_gt(abs(mit - ohne), 1e-3)
  expect_gt(mit, ohne)
  expect_equal(ohne, 0.729450730832753, tolerance = 1e-12)

  # Der Zugewinn ist P(Gleichstand) * (P(A gewinnt EV) - P(B gewinnt EV)) / 2.
  st <- orakel_stufen(L$hin, L$rueck, L$neutral / 3)
  zugewinn <- st$p_gleich * (st$p_a_ev - (1 - st$p_a_ev - st$p_gleich_ev)) / 2
  expect_equal(mit - ohne, zugewinn, tolerance = 1e-10)

  # Fuer das schwaechere Team ist es umgekehrt.
  expect_lt(q(rev(L$hin), rev(L$rueck), rev(L$neutral)),
            orakel_quote(rev(L$hin), rev(L$rueck), rev(L$neutral), verlaengerung = FALSE))
})

test_that("Die Verlaengerung rechnet mit neutral / 3 -- nicht mit / 2 und nicht mit 90 Minuten", {
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")
  L <- L_1600_1400

  quote <- q(L$hin, L$rueck, L$neutral, max_tore = MAX_TORE_EXAKT)
  expect_equal(quote, orakel_quote(L$hin, L$rueck, L$neutral, ev_faktor = 1 / 3),
               tolerance = 1e-12)
  # Die Alternativen liegen messbar daneben: / 2 um 3.9e-3, 90 Minuten um 1.2e-2.
  expect_gt(abs(quote - orakel_quote(L$hin, L$rueck, L$neutral, ev_faktor = 1 / 2)), 1e-3)
  expect_gt(abs(quote - orakel_quote(L$hin, L$rueck, L$neutral, ev_faktor = 1)), 1e-2)
})

test_that("Die Verlaengerung rechnet mit den NEUTRALEN Raten, nicht mit denen des Hinspiels", {
  # Bei gleicher Staerke: Nimmt die Verlaengerung die Hinspiel-Raten (mit
  # Heimvorteil fuer A), kommt 0.50297 statt 0.5 heraus. Mit den neutralen
  # Raten bleibt es exakt 0.5.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")
  L <- L_GLEICH

  falsch <- orakel_quote(L$hin, L$rueck, L$hin)
  expect_gt(abs(falsch - 0.5), 1e-3)
  expect_equal(q(L$hin, L$rueck, L$neutral, max_tore = MAX_TORE_EXAKT), 0.5,
               tolerance = 1e-12)
  # Ein bewusst falsches drittes Argument muss die Quote bewegen -- sonst
  # wird es ignoriert.
  expect_equal(q(L$hin, L$rueck, L$hin, max_tore = MAX_TORE_EXAKT), falsch,
               tolerance = 1e-12)
})

test_that("Elfmeter 50:50: bei gleichen Raten in allen drei Spielen ist die Quote exakt 0.5", {
  # Jede andere Muenze als 50:50 faellt hier auf -- alles vor dem
  # Elfmeterschiessen ist symmetrisch.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")
  for (r in c(0.4, 1.3, 2.0)) {
    p <- c(r, r)
    expect_equal(q(p, p, p, max_tore = MAX_TORE_EXAKT), 0.5, tolerance = 1e-12,
                 info = paste("Rate", r))
  }
})

# --- Heimvorteil: im Einzelspiel wirksam, in der Gesamtdifferenz neutral ------

test_that("Heimvorteil wirkt im Einzelspiel: Hinspiel-Siegquote von A > Rueckspiel-Siegquote von A", {
  env <- source_aufstiegsspiele()
  td <- fn(env, "tordifferenz_verteilung")
  L <- L_GLEICH

  v_hin <- td(L$hin[["a"]], L$hin[["b"]])        # A zu Hause
  v_rueck <- td(L$rueck[["a"]], L$rueck[["b"]])  # A auswaerts
  p_a_hin <- sum(v_hin[as.character(1:15)])
  p_a_rueck <- sum(v_rueck[as.character(1:15)])
  # 0.066 Unterschied.
  expect_gt(p_a_hin - p_a_rueck, 0.06)
  # Gegenprobe ohne Heimvorteil: beide Spiele identisch verteilt.
  v_n <- td(L$neutral[["a"]], L$neutral[["b"]])
  expect_equal(unname(v_n), unname(rev(v_n)), tolerance = 1e-15)
})

test_that("Heimvorteil hebt sich ueber Hin- und Rueckspiel EXAKT auf: Quote(mit) == Quote(neutral, neutral)", {
  # Poisson-Additivitaet: A gesamt ~ Pois(hin_a + rueck_a), und
  # hin_a + rueck_a = 2 * neutral_a. Das ist kein Bug, sondern eine
  # Eigenschaft des linearen Tormodells -- siehe Testkopf. Ein Test, der
  # hier eine Differenz verlangte, waere mathematisch unerfuellbar.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")

  for (paar in list(c(1600, 1400), c(1520, 1480), c(1300, 1700))) {
    L <- zweikampf_lambdas(paar[1], paar[2])
    # Die Voraussetzung, explizit: hin + rueck = 2 * neutral.
    expect_equal(unname(L$hin + L$rueck), unname(2 * L$neutral), tolerance = 1e-13)
    mit <- q(L$hin, L$rueck, L$neutral, max_tore = MAX_TORE_EXAKT)
    ohne <- q(L$neutral, L$neutral, L$neutral, max_tore = MAX_TORE_EXAKT)
    expect_equal(mit, ohne, tolerance = 1e-12,
                 info = sprintf("%s gegen %s", paar[1], paar[2]))
  }
})

test_that("Die Gesamtdifferenz ueber zwei Spiele ist vom Heimvorteil unabhaengig -- auch P(Gleichstand)", {
  # Faltung der beiden Einzelspiel-Differenzen aus dem Baustein der
  # Implementierung, einmal mit und einmal ohne Heimvorteil: dieselbe
  # Verteilung, also auch dieselbe Gleichstandswahrscheinlichkeit
  # (0.149344690258871 fuer 1600 gegen 1400). "Seltener Gleichstand durch
  # getauschtes Heimrecht" gibt es in diesem Modell nicht.
  env <- source_aufstiegsspiele()
  td <- fn(env, "tordifferenz_verteilung")
  L <- L_1600_1400

  gesamt <- function(p1, p2, N = 20) {
    v1 <- td(p1[["a"]], p1[["b"]], max_tore = N)
    v2 <- td(p2[["a"]], p2[["b"]], max_tore = N)
    # Faltung von Hand: P(D1 + D2 = d) = SUMME_i P(D1 = i) * P(D2 = d - i).
    d <- -(2 * N):(2 * N)
    out <- vapply(d, function(dd) {
      i <- -N:N
      j <- dd - i
      ok <- j >= -N & j <= N
      sum(v1[as.character(i[ok])] * v2[as.character(j[ok])])
    }, numeric(1))
    names(out) <- as.character(d)
    out
  }
  g_mit <- gesamt(L$hin, L$rueck)
  g_ohne <- gesamt(L$neutral, L$neutral)
  expect_equal(g_mit, g_ohne, tolerance = 1e-12)
  expect_equal(g_mit[["0"]], 0.149344690258871, tolerance = 1e-10)
  expect_equal(sum(g_mit), 1, tolerance = 1e-9)
})

# --- max_tore-Abschneidung ----------------------------------------------------

test_that("max_tore: die Quote aendert sich ab 15 nur noch um < 1e-9 (ELO-Differenz bis 250)", {
  # Schwanz je Spiel bei 15 Toren: 7e-11 (1600/1400), 1e-12 (1500/1500),
  # 1.5e-10 (1400/1650, Rate 1.84). Ueber zwei Spiele hoechstens das
  # Doppelte -- alles unter 1e-9.
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")

  for (paar in list(c(1600, 1400), c(1500, 1500), c(1400, 1650))) {
    L <- zweikampf_lambdas(paar[1], paar[2])
    q15 <- q(L$hin, L$rueck, L$neutral, max_tore = 15)
    q40 <- q(L$hin, L$rueck, L$neutral, max_tore = 40)
    expect_lt(abs(q15 - q40), 1e-9)
    expect_equal(q15, orakel_quote(L$hin, L$rueck, L$neutral), tolerance = 1e-9)
    expect_equal(q40, orakel_quote(L$hin, L$rueck, L$neutral), tolerance = 1e-12)
  }
})

test_that("max_tore ist der Default 15 und wird durchgereicht", {
  env <- source_aufstiegsspiele()
  q <- fn(env, "zweikampf_quote")
  td <- fn(env, "tordifferenz_verteilung")
  L <- L_1600_1400
  expect_length(td(1.3, 1.1), 31)
  expect_equal(q(L$hin, L$rueck, L$neutral),
               q(L$hin, L$rueck, L$neutral, max_tore = 15), tolerance = 1e-15)
})

# --- p_sieg_matrix: aus den Paarungen des Endpunkts -------------------------

# Das paarungen-data.frame, wie zweikampf_paarungen_rust() es liefert.
paarungen_aus <- function(elo_a, elo_b, ha = 40, ...) {
  zeilen <- list()
  for (a in names(elo_a)) {
    for (b in names(elo_b)) {
      L <- zweikampf_lambdas(elo_a[[a]], elo_b[[b]], ha, ...)
      zeilen[[length(zeilen) + 1]] <- data.frame(
        a = a, b = b,
        hin_a = L$hin[["a"]], hin_b = L$hin[["b"]],
        rueck_a = L$rueck[["a"]], rueck_b = L$rueck[["b"]],
        neutral_a = L$neutral[["a"]], neutral_b = L$neutral[["b"]],
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, zeilen)
}

elo_nord <- c(A = 1520, B = 1480, X = 1600)
elo_bayern <- c(C = 1560, D = 1440)

test_that("p_sieg_matrix: dimnames aus den Paarungen, Werte in [0, 1], Eintraege = zweikampf_quote", {
  env <- source_aufstiegsspiele()
  m <- fn(env, "p_sieg_matrix")
  q <- fn(env, "zweikampf_quote")

  pa <- paarungen_aus(elo_nord, elo_bayern)
  expect_equal(nrow(pa), 6)
  M <- m(pa)

  expect_true(is.matrix(M))
  expect_identical(dim(M), c(3L, 2L))
  expect_identical(rownames(M), c("A", "B", "X"))
  expect_identical(colnames(M), c("C", "D"))
  expect_true(all(M >= 0 & M <= 1))
  expect_false(any(is.na(M)))

  for (i in seq_len(nrow(pa))) {
    z <- pa[i, ]
    expect_equal(M[z$a, z$b],
                 q(c(z$hin_a, z$hin_b), c(z$rueck_a, z$rueck_b),
                   c(z$neutral_a, z$neutral_b)),
                 tolerance = 1e-14, info = paste(z$a, z$b))
    expect_equal(M[z$a, z$b], orakel_elo(elo_nord[[z$a]], elo_bayern[[z$b]]),
                 tolerance = 1e-9, info = paste(z$a, z$b))
  }
  # Das staerkste Nord-Team hat gegen jeden Bayern die hoechste Quote.
  expect_true(all(M["X", ] > M["A", ]))
  expect_true(all(M["A", ] > M["B", ]))

  # max_tore wird durchgereicht: mit 40 liegt die Matrix auf 1e-12 am Orakel.
  M40 <- m(pa, max_tore = MAX_TORE_EXAKT)
  for (i in seq_len(nrow(pa))) {
    z <- pa[i, ]
    expect_equal(M40[z$a, z$b], orakel_elo(elo_nord[[z$a]], elo_bayern[[z$b]]),
                 tolerance = 1e-12, info = paste(z$a, z$b))
  }
})

test_that("p_sieg_matrix: die Zeilenreihenfolge der Paarungen ist egal -- Zuordnung ueber a und b", {
  env <- source_aufstiegsspiele()
  m <- fn(env, "p_sieg_matrix")
  pa <- paarungen_aus(elo_nord, elo_bayern)
  gemischt <- pa[c(6, 2, 4, 1, 5, 3), ]
  M1 <- m(pa, max_tore = MAX_TORE_EXAKT)
  M2 <- m(gemischt, max_tore = MAX_TORE_EXAKT)
  expect_equal(M2[rownames(M1), colnames(M1)], M1, tolerance = 1e-15)
})

test_that("p_sieg_matrix: Gegenrichtung ist 1 - t(p_sieg) -- kein Unentschieden ueber zwei Spiele", {
  # Die Paarungen aus Bayern-Sicht: a = Bayern-Team, b = Nord-Team, mit
  # eigenen Raten (Bayern hat dann im Hinspiel Heimrecht).
  env <- source_aufstiegsspiele()
  m <- fn(env, "p_sieg_matrix")
  M <- m(paarungen_aus(elo_nord, elo_bayern), max_tore = MAX_TORE_EXAKT)
  R <- m(paarungen_aus(elo_bayern, elo_nord), max_tore = MAX_TORE_EXAKT)
  expect_equal(R, 1 - t(M), tolerance = 1e-12)
  # Und mit dem Default bis auf den Schwanz.
  M15 <- m(paarungen_aus(elo_nord, elo_bayern))
  R15 <- m(paarungen_aus(elo_bayern, elo_nord))
  expect_equal(R15, 1 - t(M15), tolerance = 1e-9)
})

test_that("p_sieg_matrix: gleiche Staerke ueberall -> ueberall exakt 0.5", {
  env <- source_aufstiegsspiele()
  m <- fn(env, "p_sieg_matrix")
  M <- m(paarungen_aus(c(A = 1500, B = 1500), c(C = 1500, D = 1500)),
         max_tore = MAX_TORE_EXAKT)
  expect_equal(unname(M), matrix(0.5, 2, 2), tolerance = 1e-12)
})

test_that("p_sieg_matrix bricht bei fehlender Paarung oder fehlender Spalte ab", {
  env <- source_aufstiegsspiele()
  m <- fn(env, "p_sieg_matrix")
  pa <- paarungen_aus(elo_nord, elo_bayern)

  # Paarung X gegen D fehlt.
  expect_error(m(pa[!(pa$a == "X" & pa$b == "D"), ]), "X.*D|D.*X")
  # Eine Ratenspalte fehlt.
  expect_error(m(pa[, setdiff(names(pa), "neutral_b")]), "neutral_b")
  # Leer.
  expect_error(m(pa[0, ]))
})

test_that("p_sieg_matrix: andere Raten (Frauen-Tormodell) liefern andere Zahlen -- R kennt keine Konstanten", {
  env <- source_aufstiegsspiele()
  m <- fn(env, "p_sieg_matrix")
  herren <- m(paarungen_aus(c(A = 1600), c(C = 1450)), max_tore = MAX_TORE_EXAKT)
  frauen <- m(paarungen_aus(c(A = 1600), c(C = 1450), slope = 0.0024058833,
                            intercept = 1.6527603153), max_tore = MAX_TORE_EXAKT)
  # 3.5 Prozentpunkte Unterschied.
  expect_gt(abs(herren[["A", "C"]] - frauen[["A", "C"]]), 1e-2)
  expect_equal(frauen[["A", "C"]],
               orakel_elo(1600, 1450, slope = 0.0024058833, intercept = 1.6527603153),
               tolerance = 1e-12)
})

# --- Anbindung: rl_aufstiegsprognose leitet p_sieg aus den Paarungen her ------

# Wie in test-rl-aufstieg.R: Prognosematrix aus den Meisterwahrscheinlichkeiten.
prognose_aus_meister <- function(p_meister, teams = 18L) {
  m <- matrix(0, nrow = length(p_meister), ncol = teams,
              dimnames = list(names(p_meister), as.character(seq_len(teams))))
  m[, 1] <- p_meister
  m[, 2] <- 1 - p_meister
  m
}

meister_nord <- c(A = 0.6, B = 0.4)
meister_bayern <- c(C = 0.7, D = 0.3)
sieg_nord_gegen_bayern <- matrix(c(0.5, 0.8,
                                   0.3, 0.6), nrow = 2, byrow = TRUE,
                                 dimnames = list(c("A", "B"), c("C", "D")))

prognosen_2026 <- function() {
  list(
    Nord     = prognose_aus_meister(meister_nord),
    Nordost  = prognose_aus_meister(c(E = 0.9, F = 0.1)),
    West     = prognose_aus_meister(c(G = 0.55, H = 0.45)),
    SuedWest = prognose_aus_meister(c(I = 1.0, J = 0.0)),
    Bayern   = prognose_aus_meister(meister_bayern, teams = 19L)
  )
}

elos_2026 <- list(Nord = c(A = 1520, B = 1480), Bayern = c(C = 1560, D = 1440))
paarungen_2026 <- function() paarungen_aus(elos_2026$Nord, elos_2026$Bayern)

# Doppelsumme von Hand, gegen das Orakel.
orakel_aufstieg_nord <- function() {
  M <- outer(names(meister_nord), names(meister_bayern),
             Vectorize(function(a, b) orakel_elo(elos_2026$Nord[[a]], elos_2026$Bayern[[b]])))
  dimnames(M) <- list(names(meister_nord), names(meister_bayern))
  p <- meister_nord * as.vector(M %*% meister_bayern)
  names(p) <- names(meister_nord)
  p
}

test_that("Anbindung: die hergeleitete Matrix laeuft durch aufstiegswahrscheinlichkeit()", {
  env <- source_aufstiegsspiele()
  m <- fn(env, "p_sieg_matrix")
  aw <- fn(env, "aufstiegswahrscheinlichkeit")

  M <- m(paarungen_2026())
  p_nord <- aw(meister_nord, meister_bayern, M)
  p_bayern <- aw(meister_bayern, meister_nord, 1 - t(M))

  expect_named(p_nord, c("A", "B"))
  expect_named(p_bayern, c("C", "D"))
  # 1e-9: Default max_tore = 15, Schwanz bei diesen Raten < 1.1e-11 je Spiel.
  expect_equal(p_nord, orakel_aufstieg_nord(), tolerance = 1e-9)
  expect_equal(sum(p_nord) + sum(p_bayern), 1, tolerance = 1e-12)
  # Nicht die Meisterwahrscheinlichkeit durchgereicht.
  expect_lt(p_nord[["A"]], 0.6)
  expect_gt(p_nord[["A"]], 0)
})

test_that("Anbindung: rl_aufstiegsprognose rechnet p_sieg aus paarungen, wenn keins uebergeben wird", {
  env <- source_aufstiegsspiele()
  f <- fn(env, "rl_aufstiegsprognose")
  pr <- prognosen_2026()

  df_nord <- f("Nord", pr, season = 2026, paarungen = paarungen_2026())
  expect_s3_class(df_nord, "data.frame")
  expect_equal(colnames(df_nord), "Aufstieg")
  erwartet <- orakel_aufstieg_nord()
  expect_equal(df_nord["A", "Aufstieg"], erwartet[["A"]], tolerance = 1e-9)
  expect_equal(df_nord["B", "Aufstieg"], erwartet[["B"]], tolerance = 1e-9)

  df_bayern <- f("Bayern", pr, season = 2026, paarungen = paarungen_2026())
  # Genau einer der vier steigt ueber die Aufstiegsspiele auf.
  expect_equal(sum(df_nord$Aufstieg) + sum(df_bayern$Aufstieg), 1, tolerance = 1e-12)
  # Bayern-Seite ist die Gegenrichtung derselben Matrix.
  expect_equal(df_bayern["C", "Aufstieg"],
               0.7 * (0.6 * (1 - orakel_elo(1520, 1560)) +
                        0.4 * (1 - orakel_elo(1480, 1560))),
               tolerance = 1e-9)
})

test_that("Anbindung: ein explizites p_sieg hat Vorrang vor der Herleitung aus paarungen", {
  # Beides uebergeben: Es gilt das Rechenbeispiel aus test-rl-aufstieg.R
  # (0.354 / 0.156), nicht die Herleitung.
  env <- source_aufstiegsspiele()
  f <- fn(env, "rl_aufstiegsprognose")
  pr <- prognosen_2026()

  df <- f("Nord", pr, season = 2026, p_sieg = sieg_nord_gegen_bayern,
          paarungen = paarungen_2026())
  expect_equal(df["A", "Aufstieg"], 0.354, tolerance = 1e-12)
  expect_equal(df["B", "Aufstieg"], 0.156, tolerance = 1e-12)
  expect_false(isTRUE(all.equal(df["A", "Aufstieg"], orakel_aufstieg_nord()[["A"]])))
})

test_that("Anbindung: ohne p_sieg UND ohne paarungen bricht es weiter mit 'p_sieg' ab", {
  # Das bestehende Verhalten (test-rl-aufstieg.R) bleibt: keine erfundene 50:50.
  env <- source_aufstiegsspiele()
  f <- fn(env, "rl_aufstiegsprognose")
  expect_error(f("Nord", prognosen_2026(), season = 2026), "p_sieg")
  expect_error(f("Bayern", prognosen_2026(), season = 2026, p_sieg = NULL,
                 paarungen = NULL), "p_sieg")
})

test_that("Anbindung: fehlt ein Team in paarungen, nennt der Fehler das Team", {
  env <- source_aufstiegsspiele()
  f <- fn(env, "rl_aufstiegsprognose")
  pa <- paarungen_2026()
  # Ueber Variablen, damit der deparste Aufruf in einer generischen
  # R-Fehlermeldung ("unused argument" / "unbenutzte Argumente", je nach
  # Locale) den Teamnamen nicht zufaellig enthaelt und den Test faelschlich
  # gruen macht.
  ohne_d <- pa[pa$b != "D", ]
  ohne_b <- pa[pa$a != "B", ]
  err <- expect_error(f("Nord", prognosen_2026(), season = 2026, paarungen = ohne_d))
  expect_match(conditionMessage(err), "\\bD\\b")
  expect_false(grepl("unused argument|unbenutzte", conditionMessage(err)))
  err <- expect_error(f("Bayern", prognosen_2026(), season = 2026, paarungen = ohne_b))
  expect_match(conditionMessage(err), "\\bB\\b")
  expect_false(grepl("unused argument|unbenutzte", conditionMessage(err)))
})

test_that("Anbindung: Direktaufsteiger brauchen weder p_sieg noch paarungen", {
  env <- source_aufstiegsspiele()
  f <- fn(env, "rl_aufstiegsprognose")
  df <- f("Nordost", prognosen_2026(), season = 2026, paarungen = paarungen_2026())
  expect_equal(df["E", "Aufstieg"], 0.9)
  expect_equal(f("West", prognosen_2026(), season = 2026)["G", "Aufstieg"], 0.55)
})

test_that("Anbindung: gleiche Staerke ueberall -> die Doppelsumme halbiert die Meisterwahrscheinlichkeit", {
  # Mit lauter 0.5 in p_sieg ist P(Aufstieg) = P(Meister) / 2 -- der
  # Muenzwurf-Test aus test-rl-aufstieg.R, jetzt ueber die Herleitung.
  env <- source_aufstiegsspiele()
  f <- fn(env, "rl_aufstiegsprognose")
  pa <- paarungen_aus(c(A = 1500, B = 1500), c(C = 1500, D = 1500))
  df <- f("Nord", prognosen_2026(), season = 2026, paarungen = pa)
  expect_equal(df["A", "Aufstieg"], 0.3, tolerance = 1e-9)
  expect_equal(df["B", "Aufstieg"], 0.2, tolerance = 1e-9)
})

# --- Integration: der Rust-Endpunkt liefert die Raten ------------------------
#
# Diese Tests brauchen einen laufenden Rust-Server (RUST_API_URL, Default
# localhost:8080) und werden sonst uebersprungen -- wie in
# test-staffel-zuordnung.R.

source_mit_client <- function() {
  env <- source_aufstiegsspiele()
  source(test_path("..", "..", "RCode", "rust_integration.R"), local = env)
  env
}

test_that("Integration: match_preview_rust liefert die Raten des Rust-Tormodells", {
  skip_if_not(nzchar(Sys.getenv("RUST_API_URL", "http://localhost:8080")))
  env <- source_mit_client()
  skip_if_not(env$connect_rust_simulator(), "Rust-Server nicht erreichbar")
  f <- fn(env, "match_preview_rust")

  # 1500 gegen 1400, Server-Defaults (Heimvorteil 40, Herren-Tormodell):
  # ELO-Delta 140 -> 1.57180842446946 / 1.07186973645008.
  res <- f(1500, 1400, max_goals = 15)
  expect_equal(res$lambda_home, 1.57180842446946, tolerance = 1e-12)
  expect_equal(res$lambda_away, 1.07186973645008, tolerance = 1e-12)
  expect_true(is.matrix(res$score_matrix))
  expect_identical(dim(res$score_matrix), c(16L, 16L))
  expect_equal(sum(res$score_matrix), 1, tolerance = 1e-12)
  expect_equal(res$score_matrix[1, 1], exp(-res$lambda_home) * exp(-res$lambda_away),
               tolerance = 1e-12)
  expect_equal(res$p_home_win + res$p_draw + res$p_away_win, 1, tolerance = 1e-12)

  # Ohne Heimvorteil: ELO-Delta 100 -> 1.50038861189526 / 1.14328954902428.
  res0 <- f(1500, 1400, home_advantage = 0)
  expect_equal(res0$lambda_home, 1.50038861189526, tolerance = 1e-12)
  expect_equal(res0$lambda_away, 1.14328954902428, tolerance = 1e-12)
})

test_that("Integration: zweikampf_paarungen_rust liefert das paarungen-data.frame", {
  skip_if_not(nzchar(Sys.getenv("RUST_API_URL", "http://localhost:8080")))
  env <- source_mit_client()
  skip_if_not(env$connect_rust_simulator(), "Rust-Server nicht erreichbar")
  f <- fn(env, "zweikampf_paarungen_rust")

  pa <- f(elos_2026$Nord, elos_2026$Bayern)
  expect_s3_class(pa, "data.frame")
  expect_true(all(c("a", "b", "hin_a", "hin_b", "rueck_a", "rueck_b",
                    "neutral_a", "neutral_b") %in% names(pa)))
  expect_equal(nrow(pa), 4)
  expect_setequal(paste(pa$a, pa$b), c("A C", "A D", "B C", "B D"))

  # Die Raten sind exakt die des Endpunkts (Fixture-Generator oben).
  erwartet <- paarungen_2026()
  for (i in seq_len(nrow(erwartet))) {
    z <- pa[pa$a == erwartet$a[i] & pa$b == erwartet$b[i], ]
    expect_equal(nrow(z), 1)
    for (sp in c("hin_a", "hin_b", "rueck_a", "rueck_b", "neutral_a", "neutral_b")) {
      expect_equal(z[[sp]], erwartet[[sp]][i], tolerance = 1e-12,
                   info = paste(erwartet$a[i], erwartet$b[i], sp))
    }
  }
  # Die Verlaengerungs-Raten sind neutral: hin + rueck = 2 * neutral.
  expect_equal(pa$hin_a + pa$rueck_a, 2 * pa$neutral_a, tolerance = 1e-12)
  expect_equal(pa$hin_b + pa$rueck_b, 2 * pa$neutral_b, tolerance = 1e-12)
})

test_that("Integration: die ganze Kette -- Rust-Raten -> p_sieg_matrix -> rl_aufstiegsprognose", {
  skip_if_not(nzchar(Sys.getenv("RUST_API_URL", "http://localhost:8080")))
  env <- source_mit_client()
  skip_if_not(env$connect_rust_simulator(), "Rust-Server nicht erreichbar")

  pa <- fn(env, "zweikampf_paarungen_rust")(elos_2026$Nord, elos_2026$Bayern)
  M <- fn(env, "p_sieg_matrix")(pa)
  expect_equal(M, fn(env, "p_sieg_matrix")(paarungen_2026()), tolerance = 1e-12)

  df_nord <- fn(env, "rl_aufstiegsprognose")("Nord", prognosen_2026(),
                                             season = 2026, paarungen = pa)
  df_bayern <- fn(env, "rl_aufstiegsprognose")("Bayern", prognosen_2026(),
                                               season = 2026, paarungen = pa)
  erwartet <- orakel_aufstieg_nord()
  expect_equal(df_nord["A", "Aufstieg"], erwartet[["A"]], tolerance = 1e-9)
  expect_equal(df_nord["B", "Aufstieg"], erwartet[["B"]], tolerance = 1e-9)
  expect_equal(sum(df_nord$Aufstieg) + sum(df_bayern$Aufstieg), 1, tolerance = 1e-12)
})
