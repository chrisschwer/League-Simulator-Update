library(testthat)

# Phase 6, Nachtrag: Die Regionalliga Nord koppelt ihre Absteigerzahl nicht nur
# an die 3. Liga, sondern auch an den EIGENEN Aufstieg.
#
# Die Staffel hat 18 Teams, drei Regelabsteiger und drei Oberliga-Aufsteiger;
# die Bilanz geht auf: 18 - 3 + 3 = 18. Steigt der Nord-Meister aber in die
# 3. Liga auf, fehlt ein Team (18 - 1 - 3 + 3 = 17), die Staffelstaerke wird
# unterschritten, und nach NFV-SpO Par. 6 Abs. 3 a.E. geht "ein freier Platz
# zunaechst an den bestplatzierten zugelassenen Absteiger" -- der dritte
# Absteiger bleibt drin (docs/abstieg_aufstieg_RL_2026_2027.md, 2.1 und 3.2):
#
#   Meister bleibt      -> Basis 3   (Absteiger = 3 + k)
#   Meister steigt auf  -> Basis 2   (Absteiger = 2 + k)
#
# Gemischt ueber die binaere Aufstiegsvariable, mit d = Platz von unten:
#
#   w[d] = P(Meister bleibt) * P(k >= d - 3) + P(Meister steigt auf) * P(k >= d - 2)
#
# (Die Vorgabe schrieb "P(k >= d-2)" und "P(k >= d-1)" -- das ist dieselbe
# Formel mit d ab 0 gezaehlt; die Tabelle darunter zaehlt ab 1. Verbindlich
# ist hier die Tabelle, also Basis 3 bzw. Basis 2:)
#
#   | Platz von unten | Meister bleibt | Meister steigt auf |
#   |-----------------|----------------|--------------------|
#   | 1, 2            | 1              | 1                  |
#   | 3               | 1              | P(k >= 1)          |
#   | 4               | P(k >= 1)      | P(k >= 2)          |
#   | 5               | P(k >= 2)      | P(k >= 3)          |
#
# Die letzten BEIDEN Plaetze sind in beiden Aesten sicher -- das ist die Probe.
#
# UNABHAENGIGKEIT -- eine bewusste Naeherung, kein exaktes Produkt:
# "Team X landet auf Platz p" und "der Meister dieser Staffel steigt auf"
# leben in DERSELBEN Liga und sind deshalb nicht stochastisch unabhaengig.
# Trotzdem wird multiplikativ genaehert: Dasselbe Team ist praktisch nie
# zugleich Meisterkandidat und Abstiegskandidat, und gegen Saisonende
# trennen sich Auf- und Abstiegszone ohnehin. Der Fehler ist klein und
# beschraenkt. Das ist BEWUSST ANDERS als bei relegation_group_counts
# INNERHALB der 3. Liga: Dort belegen genau K Teams die K Abstiegsplaetze,
# die Ereignisse sind stark negativ korreliert, und deshalb wird dort je
# Iteration exakt ausgezaehlt statt gerechnet. Wer die beiden Faelle
# verwechselt, rechnet entweder hier unnoetig aus oder dort falsch.
# Algebraische Folge der Naeherung, die unten getestet wird: Die Gewichte
# sind LINEAR in p_meister_aufstieg, w(p) = (1-p) * w(0) + p * w(1).
#
# Nord hat 2026/27 genau zwei potenzielle Drittliga-Absteiger: Havelse und
# SV Meppen (RCode/TeamList_2026.csv, Liga 80, Region Nord; beide im
# Spielplan data/fixture_cache/80_2026.json). k ist also 0, 1 oder 2. Der
# Worst Case -- beide steigen ab UND der Nord-Meister steigt nicht auf --
# ergibt 3 + 2 = 5 Absteiger.
#
# Erwartete API-Erweiterung in RCode/rl_abstiegskopplung.R:
#
#   platz_gewichte(staffel, verteilung, teams, p_meister_aufstieg = 0)
#   rl_abstiegsprognose(staffel, prognose, relegation_group_counts,
#                       p_meister_aufstieg = 0)
#
#   p_meister_aufstieg: EINE Zahl in [0, 1] -- P(der Meister dieser Staffel
#   steigt in die 3. Liga auf). Wird als fertige Zahl hineingereicht und
#   NICHT intern aus rl_aufstieg.R geholt: Das haelt die Module getrennt und
#   macht die Zahl im Test setzbar. Default 0 = Verhalten wie bisher, die
#   118 Tests in test-rl-abstiegskopplung.R bleiben unveraendert gruen.
#   Werte ausserhalb [0, 1], NA oder Vektoren der Laenge != 1 -> Fehler.
#
#   Nur Nord ist betroffen. West, SuedWest und Nordost sind Direktaufsteiger,
#   ihr Meisteraufstieg steckt bereits in der Basis (Nordost-Schema:
#   "- Aufsteiger 3. Liga: 1" in beiden Varianten); Bayern koppelt ueber die
#   Ligagroesse und ist strukturell anders. Fuer diese vier darf das
#   Argument NICHTS aendern.

source_kopplung <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  datei <- test_path("..", "..", "RCode", "rl_abstiegskopplung.R")
  if (file.exists(datei)) source(datei, local = env)
  env
}

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
K_DRITTE_LIGA <- 4L

zaehlung <- function(...) {
  m <- matrix(0, nrow = 5, ncol = K_DRITTE_LIGA + 1)
  m[, 1] <- N_ITER
  zeilen <- list(...)
  for (staffel in names(zeilen)) {
    m[match(staffel, STAFFELN_ERWARTET), ] <- zeilen[[staffel]]
  }
  m
}

prognose_zeile <- function(teams, plaetze, p, name = "A") {
  stopifnot(abs(sum(p) - 1) < 1e-12)
  m <- matrix(0, nrow = 1, ncol = teams,
              dimnames = list(name, as.character(seq_len(teams))))
  m[1, plaetze] <- p
  m
}

# Fixture "Nord 30/50/20": P(k=0) = 0.3, P(k=1) = 0.5, P(k=2) = 0.2 -- also
# P(k >= 1) = 0.7, P(k >= 2) = 0.2, P(k >= 3) = 0. E[k] = 0.9.
# Uebrige Zeilen: West 0.9*2 + 0.1*3 = 2.1, SuedWest 1, Nordost 0,
# Bayern 0 -- Summe 0.9 + 2.1 + 1 = 4.
zaehlung_nord305020 <- function() {
  zaehlung(
    Nord     = c(3000, 5000, 2000, 0, 0),
    West     = c(0, 0, 9000, 1000, 0),
    SuedWest = c(0, N_ITER, 0, 0, 0)
  )
}

# Fixture "Nordost 89 %" aus der Bestandsdatei: Nord P(k=1) = 0.89,
# P(k=2) = 0.11, also P(k >= 1) = 1, P(k >= 2) = 0.11. Mit p = 0 liefert die
# Bestandsdatei fuer Nord und Team A den Wert 0.90.
zaehlung_nordost89 <- function() {
  zaehlung(
    Nordost  = c(1100, 8900, 0, 0, 0),
    Nord     = c(0, 8900, 1100, 0, 0),
    West     = c(0, N_ITER, 0, 0, 0),
    SuedWest = c(0, N_ITER, 0, 0, 0)
  )
}

# Fixture "Nord k = 2 sicher": beide Nord-Drittligisten (Havelse, Meppen)
# steigen ab. West ebenfalls 2 sicher -> Summe 4.
zaehlung_nord_k2 <- function() {
  zaehlung(Nord = c(0, 0, N_ITER, 0, 0), West = c(0, 0, N_ITER, 0, 0))
}

# Fixture "Nord k = 0 sicher": kein Nord-Drittligist steigt ab. West 4 -> Summe 4.
zaehlung_nord_k0 <- function() {
  zaehlung(West = c(0, 0, 0, 0, N_ITER))
}

# Das Team aus dem Fixpunkt-Beispiel der Bestandsdatei: 10 % Meister,
# 10 / 20 / 30 / 30 % auf den Plaetzen 15 / 16 / 17 / 18.
team_a <- function() {
  prognose_zeile(18L, plaetze = c(1, 15, 16, 17, 18),
                 p = c(0.10, 0.10, 0.20, 0.30, 0.30))
}

# --- Rueckwaertskompatibilitaet -------------------------------------------

test_that("Nord: ohne das Argument und mit p_meister_aufstieg = 0 kommt IDENTISCH dasselbe heraus", {
  # Default 0 = Basis 3, das bisherige Verhalten. Aus zaehlung_nordost89:
  # Plaetze 16-18 sicher, Platz 15 P(k >= 1) = 1, Platz 14 P(k >= 2) = 0.11,
  # Platz 13 P(k >= 3) = exakt 0.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nordost89())
  g <- fn(env, "platz_gewichte")

  ohne <- g("Nord", v, teams = 18L)
  mit  <- g("Nord", v, teams = 18L, p_meister_aufstieg = 0)

  expect_identical(mit, ohne)
  expect_equal(unname(mit[16:18]), c(1, 1, 1))
  expect_equal(unname(mit[15]), 1)
  expect_equal(unname(mit[14]), 0.11)
  expect_identical(unname(mit[13]), 0)
})

test_that("Nord: rl_abstiegsprognose ohne Argument liefert weiter 0.90 fuer Team A", {
  # Der Wert aus der Bestandsdatei ("Nord und SuedWest liefern verschiedene
  # Zahlen als Nordost"): 0.30 + 0.30 + 0.20 * 1 + 0.10 * 1 = 0.90.
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")

  ohne <- f("Nord", team_a(), zaehlung_nordost89())
  mit  <- f("Nord", team_a(), zaehlung_nordost89(), p_meister_aufstieg = 0)

  expect_identical(mit, ohne)
  expect_equal(ohne["A", "Abstieg"], 0.90, tolerance = 1e-12)
})

# --- Die beiden reinen Aeste ------------------------------------------------

test_that("Nord, Meister bleibt sicher (p = 0): Basis 3 -- Gewichte 1, 1, 1, 0.7, 0.2, exakt 0", {
  # zaehlung_nord305020: P(k >= 1) = 0.7, P(k >= 2) = 0.2, P(k >= 3) = 0.
  #   Platz 18, 17, 16 (d = 1..3): 1
  #   Platz 15 (d = 4):            P(k >= 1) = 0.7
  #   Platz 14 (d = 5):            P(k >= 2) = 0.2
  #   Platz 13 (d = 6):            P(k >= 3) = 0 -- exakt, kein Rundungsrest
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord305020())
  w <- fn(env, "platz_gewichte")("Nord", v, teams = 18L, p_meister_aufstieg = 0)

  expect_length(w, 18L)
  expect_equal(unname(w[16:18]), c(1, 1, 1))
  expect_equal(unname(w[15]), 0.7)
  expect_equal(unname(w[14]), 0.2)
  expect_identical(unname(w[13]), 0)
  expect_identical(unname(w[1:12]), rep(0, 12))
})

test_that("Nord, Meister steigt sicher auf (p = 1): Basis 2 -- alles rutscht einen Platz nach unten", {
  # Dieselbe Zaehlung, aber der dritte Absteiger bleibt drin:
  #   Platz 18, 17 (d = 1, 2): 1
  #   Platz 16 (d = 3):        P(k >= 1) = 0.7   (bei p = 0 war das 1)
  #   Platz 15 (d = 4):        P(k >= 2) = 0.2   (bei p = 0 war das 0.7)
  #   Platz 14 (d = 5):        P(k >= 3) = 0     (bei p = 0 war das 0.2)
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord305020())
  w <- fn(env, "platz_gewichte")("Nord", v, teams = 18L, p_meister_aufstieg = 1)

  expect_equal(unname(w[17:18]), c(1, 1))
  expect_equal(unname(w[16]), 0.7)
  expect_equal(unname(w[15]), 0.2)
  expect_identical(unname(w[14]), 0)
  expect_identical(unname(w[13]), 0)
  expect_identical(unname(w[1:13]), rep(0, 13))
})

test_that("Nord, p = 1 mit der 89-%-Zaehlung: Team A faellt von 0.90 auf 0.811", {
  # Gewichte bei Basis 2: Platz 17-18 sicher, Platz 16 P(k >= 1) = 1,
  # Platz 15 P(k >= 2) = 0.11, Platz 14 exakt 0.
  #   Team A: 0.30 + 0.30 + 0.20 * 1 + 0.10 * 0.11 = 0.811
  # Das ist die Zahl, an der der Meisteraufstieg fuer ein Abstiegsteam
  # spuerbar wird: Platz 15 ist nur noch bei zwei Drittliga-Absteigern weg.
  env <- source_kopplung()
  df <- fn(env, "rl_abstiegsprognose")("Nord", team_a(), zaehlung_nordost89(),
                                       p_meister_aufstieg = 1)
  expect_equal(df["A", "Abstieg"], 0.811, tolerance = 1e-12)
  expect_equal(colnames(df), "Abstieg")
})

# --- Die Mischung -----------------------------------------------------------

test_that("Nord, p = 0.4: die Gewichte sind die Mischung beider Aeste -- 1, 1, 0.88, 0.50, 0.12, exakt 0", {
  # zaehlung_nord305020, P(Meister bleibt) = 0.6, P(Meister steigt auf) = 0.4:
  #   Platz 18, 17: 0.6 * 1   + 0.4 * 1   = 1
  #   Platz 16:     0.6 * 1   + 0.4 * 0.7 = 0.60 + 0.28 = 0.88
  #   Platz 15:     0.6 * 0.7 + 0.4 * 0.2 = 0.42 + 0.08 = 0.50
  #   Platz 14:     0.6 * 0.2 + 0.4 * 0   = 0.12
  #   Platz 13:     0.6 * 0   + 0.4 * 0   = 0 -- exakt, weil beide Aeste exakt 0
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord305020())
  w <- fn(env, "platz_gewichte")("Nord", v, teams = 18L, p_meister_aufstieg = 0.4)

  expect_equal(unname(w[17:18]), c(1, 1))
  expect_equal(unname(w[16]), 0.88)
  expect_equal(unname(w[15]), 0.50)
  expect_equal(unname(w[14]), 0.12)
  expect_identical(unname(w[13]), 0)
  expect_identical(unname(w[1:13]), rep(0, 13))
})

test_that("Nord, p = 0.4: Team A hat 82,6 % -- die Mischung aus 0.87 und 0.76", {
  # Ast "Meister bleibt" (Gewichte 1, 1, 1, 0.7 auf den Plaetzen 18..15):
  #   0.30 + 0.30 + 0.20 * 1   + 0.10 * 0.7 = 0.87
  # Ast "Meister steigt auf" (Gewichte 1, 1, 0.7, 0.2):
  #   0.30 + 0.30 + 0.20 * 0.7 + 0.10 * 0.2 = 0.76
  # Mischung: 0.6 * 0.87 + 0.4 * 0.76 = 0.522 + 0.304 = 0.826
  # Direkt ueber die gemischten Gewichte: 0.30 + 0.30 + 0.20 * 0.88 +
  #   0.10 * 0.50 = 0.60 + 0.176 + 0.05 = 0.826. Beide Wege muessen sich
  # treffen -- das ist die Linearitaet der Kernformel.
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  z <- zaehlung_nord305020()

  expect_equal(f("Nord", team_a(), z, p_meister_aufstieg = 0)["A", "Abstieg"],
               0.87, tolerance = 1e-12)
  expect_equal(f("Nord", team_a(), z, p_meister_aufstieg = 1)["A", "Abstieg"],
               0.76, tolerance = 1e-12)
  expect_equal(f("Nord", team_a(), z, p_meister_aufstieg = 0.4)["A", "Abstieg"],
               0.826, tolerance = 1e-12)
})

test_that("Nord: die Gewichte sind linear in p -- das ist die Unabhaengigkeitsnaeherung", {
  # Multiplikativ genaehert heisst: w(p) = (1 - p) * w(0) + p * w(1) fuer
  # jedes p. Eine Implementierung, die die Kopplung anders einbaut (etwa
  # ueber die Prognosezeile des Meisters), wuerde diese Gerade verlassen.
  # Fuer ein Team, das Meister UND Absteiger werden koennte, ist die Gerade
  # bewusst eine Naeherung -- siehe Dateikopf.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord305020())
  g <- fn(env, "platz_gewichte")

  w0 <- g("Nord", v, teams = 18L, p_meister_aufstieg = 0)
  w1 <- g("Nord", v, teams = 18L, p_meister_aufstieg = 1)

  for (p in c(0.1, 0.37, 0.5, 0.9)) {
    expect_equal(g("Nord", v, teams = 18L, p_meister_aufstieg = p),
                 (1 - p) * w0 + p * w1, info = paste("p =", p))
  }
})

# --- Die Proben -------------------------------------------------------------

test_that("Nord: die letzten beiden Plaetze haben in JEDEM Fall Gewicht 1", {
  # Basis 2 ist das Minimum: Selbst wenn der Meister sicher aufsteigt und
  # kein Drittligist kommt, steigen die zwei Letzten ab.
  env <- source_kopplung()
  f <- fn(env, "absteiger_verteilung")
  g <- fn(env, "platz_gewichte")

  fixtures <- list(
    k0     = f(zaehlung_nord_k0()),
    k2     = f(zaehlung_nord_k2()),
    misch  = f(zaehlung_nord305020()),
    no89   = f(zaehlung_nordost89())
  )
  for (name in names(fixtures)) {
    for (p in c(0, 0.25, 0.5, 0.75, 1)) {
      w <- g("Nord", fixtures[[name]], teams = 18L, p_meister_aufstieg = p)
      expect_identical(unname(w[17:18]), c(1, 1),
                       info = sprintf("%s, p = %s", name, p))
    }
  }
})

test_that("Nord, Minimalfall: Meister steigt auf, kein Drittligist kommt -> genau zwei Absteiger", {
  # k = 0 sicher, p = 1: 2 + 0 = 2 Absteiger. Platz 16 hat Gewicht exakt 0.
  # Zum Vergleich p = 0: 3 Absteiger, Platz 16 Gewicht 1, Platz 15 exakt 0.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord_k0())
  g <- fn(env, "platz_gewichte")

  w1 <- g("Nord", v, teams = 18L, p_meister_aufstieg = 1)
  expect_identical(unname(w1), c(rep(0, 16), 1, 1))
  expect_equal(sum(w1), 2)

  w0 <- g("Nord", v, teams = 18L, p_meister_aufstieg = 0)
  expect_identical(unname(w0), c(rep(0, 15), 1, 1, 1))
  expect_equal(sum(w0), 3)
})

test_that("Nord, Worst Case: Havelse und Meppen steigen ab, der Meister nicht auf -> fuenf Absteiger", {
  # k = 2 sicher (beide Nord-Drittligisten fallen), p = 0 (Meister bleibt):
  # 3 + 2 = 5 Absteiger, Plaetze 14-18 Gewicht 1, Platz 13 exakt 0.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord_k2())
  g <- fn(env, "platz_gewichte")

  w <- g("Nord", v, teams = 18L, p_meister_aufstieg = 0)
  expect_equal(unname(w[14:18]), rep(1, 5))
  expect_identical(unname(w[13]), 0)
  expect_identical(unname(w[1:13]), rep(0, 13))
  expect_equal(sum(w), 5)

  # Gegenprobe: Steigt der Meister sicher auf, sind es 2 + 2 = 4 -- Platz 14
  # ist dann exakt sicher.
  w1 <- g("Nord", v, teams = 18L, p_meister_aufstieg = 1)
  expect_equal(unname(w1[15:18]), rep(1, 4))
  expect_identical(unname(w1[14]), 0)
  expect_equal(sum(w1), 4)

  # Und dazwischen haengt Platz 14 genau an P(Meister bleibt):
  #   0.75 * 1 + 0.25 * 0 = 0.75
  w25 <- g("Nord", v, teams = 18L, p_meister_aufstieg = 0.25)
  expect_equal(unname(w25[14]), 0.75)
  expect_equal(unname(w25[15:18]), rep(1, 4))
  expect_identical(unname(w25[13]), 0)
})

test_that("Nord, Worst Case ueber die ganze Kette: ein Team auf Platz 14 steigt sicher ab", {
  env <- source_kopplung()
  prognose <- rbind(
    prognose_zeile(18L, plaetze = 14, p = 1, name = "Vierzehnter"),
    prognose_zeile(18L, plaetze = 13, p = 1, name = "Dreizehnter"),
    prognose_zeile(18L, plaetze = c(13, 14), p = c(0.5, 0.5), name = "Halb")
  )
  df <- fn(env, "rl_abstiegsprognose")("Nord", prognose, zaehlung_nord_k2(),
                                       p_meister_aufstieg = 0)

  expect_identical(df["Vierzehnter", "Abstieg"], 1)
  expect_identical(df["Dreizehnter", "Abstieg"], 0)
  expect_equal(df["Halb", "Abstieg"], 0.5)
})

test_that("Nord: Gewichte steigen zum Tabellenende monoton, fuer jedes p", {
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord305020())
  g <- fn(env, "platz_gewichte")

  for (p in c(0, 0.1, 0.4, 0.5, 0.9, 1)) {
    w <- g("Nord", v, teams = 18L, p_meister_aufstieg = p)
    expect_true(all(diff(w) >= 0), info = paste("p =", p))
    expect_true(all(w >= 0 & w <= 1), info = paste("p =", p))
    expect_equal(unname(w[18]), 1, info = paste("p =", p))
  }
})

test_that("Nord: Erwartete Absteigerzahl = Summe der Gewichte = 3 + E[k] - p", {
  # Erwartungswert je Ast: Meister bleibt 3 + E[k], Meister steigt auf
  # 2 + E[k]. Gemischt: (1-p)(3 + E[k]) + p(2 + E[k]) = 3 + E[k] - p.
  # Mit E[k] = 0.9 aus zaehlung_nord305020:
  #   p = 0:   3.9   (= 3 + 0.7 + 0.2)
  #   p = 1:   2.9   (= 2 + 0.7 + 0.2)
  #   p = 0.4: 3.5   (= 2 + 0.88 + 0.50 + 0.12)
  # Das ist Algebra, keine Simulation -- und weil jede Platzspalte einer
  # vollstaendigen Prognose ueber die Teams auf 1 summiert, ist die Summe
  # der Abstiegswahrscheinlichkeiten ueber alle Teams dieselbe Zahl.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord305020())
  g <- fn(env, "platz_gewichte")

  expect_equal(sum(g("Nord", v, teams = 18L, p_meister_aufstieg = 0)), 3.9)
  expect_equal(sum(g("Nord", v, teams = 18L, p_meister_aufstieg = 1)), 2.9)
  expect_equal(sum(g("Nord", v, teams = 18L, p_meister_aufstieg = 0.4)), 3.5)

  # Doppelt stochastische Prognose ueber 18 Teams.
  n <- 18L
  ident <- diag(n)
  shift <- ident[c(2:n, 1), ]
  prognose <- 0.5 * ident + 0.5 * shift
  rownames(prognose) <- paste0("T", seq_len(n))

  df <- fn(env, "rl_abstiegsprognose")("Nord", prognose, zaehlung_nord305020(),
                                       p_meister_aufstieg = 0.4)
  expect_equal(sum(df$Abstieg), 3.5)
})

test_that("Nord: ein sicherer Meister hat Abstieg exakt 0, egal wie hoch p ist", {
  # p_meister_aufstieg beschreibt den Aufstieg der STAFFEL, nicht den eines
  # bestimmten Teams. Der Meister selbst bekommt von der Kopplung nichts ab.
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  meister <- prognose_zeile(18L, plaetze = 1, p = 1, name = "M")

  for (p in c(0, 0.5, 1)) {
    df <- f("Nord", meister, zaehlung_nord305020(), p_meister_aufstieg = p)
    expect_identical(df["M", "Abstieg"], 0, info = paste("p =", p))
  }
})

test_that("Nord: die Gewichte sind ueber die Ligagroesse aufgeloest, auch mit p = 1", {
  # Kleine Liga, damit eine Index-Verwechslung sichtbar wird: 6 Teams,
  # k = 0 sicher. Basis 2 (p = 1) -> nur Platz 5 und 6; Basis 3 (p = 0) ->
  # Platz 4, 5, 6.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord_k0())
  g <- fn(env, "platz_gewichte")

  expect_identical(unname(g("Nord", v, teams = 6L, p_meister_aufstieg = 1)),
                   c(0, 0, 0, 0, 1, 1))
  expect_identical(unname(g("Nord", v, teams = 6L, p_meister_aufstieg = 0)),
                   c(0, 0, 0, 1, 1, 1))
  expect_equal(unname(g("Nord", v, teams = 6L, p_meister_aufstieg = 0.5)),
               c(0, 0, 0, 0.5, 1, 1))
})

# --- Nur Nord ist betroffen -------------------------------------------------

test_that("p_meister_aufstieg aendert fuer Nordost, West, SuedWest und Bayern NICHTS", {
  # West/SuedWest/Nordost sind Direktaufsteiger, ihr Meisteraufstieg steckt
  # schon in der Basis; Bayern koppelt ueber die Ligagroesse. Das Argument
  # muss angenommen, aber ignoriert werden -- identisch, nicht "ungefaehr".
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung(
    Nord     = c(2500, 1000, 6500, 0, 0),
    Nordost  = c(5000, 2000, 3000, 0, 0),
    West     = c(5000, 3000, 2000, 0, 0),
    SuedWest = c(5000, 4000, 1000, 0, 0),
    Bayern   = c(5000, 5000, 0, 0, 0)
  ))
  g <- fn(env, "platz_gewichte")

  for (staffel in c("Nordost", "West", "SuedWest", "Bayern")) {
    basis <- g(staffel, v, teams = 18L)
    for (p in c(0, 0.5, 1)) {
      expect_identical(g(staffel, v, teams = 18L, p_meister_aufstieg = p), basis,
                       info = sprintf("%s, p = %s", staffel, p))
    }
  }

  # Und Nord aendert sich sehr wohl -- sonst prueft der Test oben nichts.
  expect_false(identical(g("Nord", v, teams = 18L, p_meister_aufstieg = 1),
                         g("Nord", v, teams = 18L)))
})

test_that("rl_abstiegsprognose: p_meister_aufstieg aendert die vier anderen Staffeln nicht", {
  env <- source_kopplung()
  f <- fn(env, "rl_abstiegsprognose")
  counts <- zaehlung_nordost89()

  for (staffel in c("Nordost", "West", "SuedWest")) {
    expect_identical(f(staffel, team_a(), counts, p_meister_aufstieg = 1),
                     f(staffel, team_a(), counts), info = staffel)
  }

  bayern <- prognose_zeile(19L, plaetze = 15:19, p = c(0.10, 0.20, 0.30, 0.25, 0.15))
  expect_identical(f("Bayern", bayern, counts, p_meister_aufstieg = 1),
                   f("Bayern", bayern, counts))
})

# --- Fehlerfaelle -----------------------------------------------------------

test_that("p_meister_aufstieg ausserhalb von [0, 1], NA oder mit Laenge != 1 wird abgelehnt", {
  # Eine Wahrscheinlichkeit von 1.1 wuerde still negative Gewichte erzeugen;
  # ein Vektor wuerde still recyceln. Beides muss abbrechen, in beiden
  # Funktionen.
  env <- source_kopplung()
  v <- fn(env, "absteiger_verteilung")(zaehlung_nord305020())
  g <- fn(env, "platz_gewichte")
  f <- fn(env, "rl_abstiegsprognose")

  for (schlecht in list(-0.01, 1.01, NA_real_, c(0.2, 0.3), numeric(0))) {
    expect_error(g("Nord", v, teams = 18L, p_meister_aufstieg = schlecht),
                 info = paste("platz_gewichte:", deparse(schlecht)))
    expect_error(f("Nord", team_a(), zaehlung_nord305020(),
                   p_meister_aufstieg = schlecht),
                 info = paste("rl_abstiegsprognose:", deparse(schlecht)))
  }

  # Die Raender selbst sind erlaubt.
  expect_silent(g("Nord", v, teams = 18L, p_meister_aufstieg = 0))
  expect_silent(g("Nord", v, teams = 18L, p_meister_aufstieg = 1))
})
