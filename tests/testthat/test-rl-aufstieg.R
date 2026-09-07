library(testthat)

# Phase 7: Aufstieg aus den Regionalligen in die 3. Liga, Saison 2026/27.
#
# Rechtsgrundlage ist Par. 55b DFB-Spielordnung (docs/abstieg_aufstieg_RL_2026_2027.md,
# Abschnitt 1 und 3.1): Vier Aufsteiger. West und SuedWest steigen DAUERHAFT
# direkt auf. Von Nord, Nordost und Bayern bekommt jaehrlich EINE Staffel den
# dritten Direktplatz, die beiden anderen ermitteln in zwei Aufstiegsspielen
# (Hin- und Rueckspiel) den vierten Aufsteiger.
#
# 2026/27, amtlich belegt durch die BFV-Regelung (Bayern gegen Nord):
#   Direktaufsteiger: West, SuedWest, Nordost
#   Aufstiegsspiele:  Nord gegen Bayern
#
# Wer den Rotationsplatz bekommt, legt das DFB-Praesidium jaehrlich fest --
# es steht in KEINER Ordnung. Die Zuordnung muss deshalb je Saison
# konfigurierbar sein und darf nicht als Konstante in der Registry stehen.
# Fuer 2027/28 ist sie NICHT bekannt (Doku 3.3) und muss neu recherchiert
# werden; eine unbekannte Saison ist ein Fehler, kein stilles Weiterlaufen.
#
# Aufstiegswahrscheinlichkeit:
#   Direktaufsteiger:  P(Aufstieg) = P(Meister)
#   Aufstiegsspiele:   exakte Doppelsumme --
#     P(X steigt auf) = P(X Meister) * SUMME_Y P(Y Meister) * P(X gewinnt gegen Y)
#   Die Meister-Ereignisse VERSCHIEDENER Staffeln sind unabhaengig
#   (disjunkte Ligen, keine gemeinsamen Spiele), das Produkt ist exakt.
#   2026/27 laeuft Y nur ueber die Teams der jeweils anderen Staffel.
#
# Erwartete Implementierung: RCode/rl_aufstieg.R mit
#
#   AUFSTIEGSROTATION
#     Benannter Character-Vektor: Saison (Startjahr, "2026" = 2026/27) ->
#     die Staffel aus {Nord, Nordost, Bayern}, die den dritten Direktplatz
#     hat. Nur belegte Saisons stehen drin.
#
#   aufstiegsmodus(season, rotation = AUFSTIEGSROTATION)
#     -> list(direkt = c("West", "SuedWest", <Rotationsstaffel>),
#             playoff = die zwei uebrigen von Nord/Nordost/Bayern)
#     Bricht ab, wenn die Saison nicht in `rotation` steht oder der
#     Rotationswert keine der drei rotierenden Staffeln ist.
#
#   rl_aufstiegs_slots(staffel, season)
#     -> list(promotion_slots = 0/1, playoff_slots = 1/0)
#
#   aufstiegswahrscheinlichkeit(p_meister_x, p_meister_y, p_sieg)
#     p_meister_x: benannter Vektor P(Meister) je Team der Staffel X;
#     p_meister_y: dito fuer Y; p_sieg: Matrix mit dimnames, p_sieg[x, y] =
#     P(x setzt sich ueber zwei Spiele gegen y durch). Zuordnung ueber
#     NAMEN, nicht ueber Position. Ausgabe: benannter Vektor je Team von X.
#
#   rl_aufstiegsprognose(staffel, prognosen, season, p_sieg = NULL,
#                        rotation = AUFSTIEGSROTATION)
#     prognosen: benannte Liste Staffel -> Prognosematrix (Teams x Plaetze,
#     rownames = Teams; die Aufstiegs-Variante, in der Zweitvertretungen
#     bereits ausgeschlossen sind). p_sieg: Matrix fuer die Playoff-Paarung
#     der Saison, Zeilen = Teams der in STAFFELN frueheren Staffel, Spalten
#     = Teams der spaeteren; fuer die Gegenrichtung gilt 1 - t(p_sieg)
#     (ueber zwei Spiele gibt es keinen Unentschieden-Ausgang).
#     Ausgabe: data.frame rownames = Teams, Spalte "Aufstieg".
#     Playoff-Staffel ohne p_sieg -> Fehler; keine erfundene Gewinnquote.

source_aufstieg <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  for (datei in c("rl_abstiegskopplung.R", "rl_aufstieg.R")) {
    pfad <- test_path("..", "..", "RCode", datei)
    if (file.exists(pfad)) source(pfad, local = env)
  }
  env
}

fn <- function(env, name) {
  if (!exists(name, envir = env, inherits = FALSE)) {
    stop(sprintf(
      "Funktion '%s' nicht gefunden -- erwartet in RCode/rl_aufstieg.R (abstiegsplaetze: rl_abstiegskopplung.R)",
      name
    ), call. = FALSE)
  }
  get(name, envir = env, inherits = FALSE)
}

# Prognosematrix (Teams x Plaetze) aus den Meisterwahrscheinlichkeiten; der
# Rest der Masse liegt auf Platz 2, damit jede Zeile summiert.
prognose_aus_meister <- function(p_meister, teams = 18L) {
  m <- matrix(0, nrow = length(p_meister), ncol = teams,
              dimnames = list(names(p_meister), as.character(seq_len(teams))))
  m[, 1] <- p_meister
  m[, 2] <- 1 - p_meister
  m
}

# Das Rechenbeispiel fuer die Doppelsumme. X = Nord {A, B}, Y = Bayern {C, D}.
#   P(A) = 0.6 * (0.7 * 0.5 + 0.3 * 0.8) = 0.6 * 0.59 = 0.354
#   P(B) = 0.4 * (0.7 * 0.3 + 0.3 * 0.6) = 0.4 * 0.39 = 0.156
#   P(C) = 0.7 * (0.6 * 0.5 + 0.4 * 0.7) = 0.7 * 0.58 = 0.406
#   P(D) = 0.3 * (0.6 * 0.2 + 0.4 * 0.4) = 0.3 * 0.28 = 0.084
# Summe ueber beide Staffeln: 1.000 -- genau einer steigt auf.
meister_nord <- c(A = 0.6, B = 0.4)
meister_bayern <- c(C = 0.7, D = 0.3)
sieg_nord_gegen_bayern <- matrix(c(0.5, 0.8,
                                   0.3, 0.6), nrow = 2, byrow = TRUE,
                                 dimnames = list(c("A", "B"), c("C", "D")))

# --- Doppelsumme --------------------------------------------------------------

test_that("Doppelsumme: das Rechenbeispiel Nord gegen Bayern", {
  env <- source_aufstieg()
  f <- fn(env, "aufstiegswahrscheinlichkeit")

  p_nord <- f(meister_nord, meister_bayern, sieg_nord_gegen_bayern)
  expect_equal(p_nord, c(A = 0.354, B = 0.156), tolerance = 1e-12)

  # Gegenrichtung: Bayern gewinnt, wenn Nord nicht gewinnt.
  sieg_bayern_gegen_nord <- 1 - t(sieg_nord_gegen_bayern)
  p_bayern <- f(meister_bayern, meister_nord, sieg_bayern_gegen_nord)
  expect_equal(p_bayern, c(C = 0.406, D = 0.084), tolerance = 1e-12)

  # Genau einer der vier steigt auf.
  expect_equal(sum(p_nord) + sum(p_bayern), 1, tolerance = 1e-12)
})

test_that("Doppelsumme: Muenzwurf halbiert die Meisterwahrscheinlichkeit", {
  env <- source_aufstieg()
  f <- fn(env, "aufstiegswahrscheinlichkeit")
  muenze <- matrix(0.5, nrow = 2, ncol = 2,
                   dimnames = list(c("A", "B"), c("C", "D")))

  expect_equal(f(meister_nord, meister_bayern, muenze), c(A = 0.3, B = 0.2))
})

test_that("Doppelsumme: Wahrscheinlichkeit exakt 0 und exakt 1", {
  env <- source_aufstieg()
  f <- fn(env, "aufstiegswahrscheinlichkeit")

  # A ist sicher Meister und gewinnt sicher gegen jeden -> exakt 1.
  sicher <- matrix(c(1, 1, 1, 1), nrow = 2, dimnames = list(c("A", "B"), c("C", "D")))
  p <- f(c(A = 1, B = 0), meister_bayern, sicher)
  expect_identical(unname(p[["A"]]), 1)
  # B wird nie Meister -> exakt 0, nicht 1e-17.
  expect_identical(unname(p[["B"]]), 0)

  # A ist Meister, verliert aber sicher -> 0.
  chancenlos <- matrix(0, nrow = 2, ncol = 2, dimnames = list(c("A", "B"), c("C", "D")))
  expect_identical(unname(f(c(A = 1, B = 0), meister_bayern, chancenlos)[["A"]]), 0)
})

test_that("Doppelsumme ordnet ueber Namen zu, nicht ueber die Position", {
  # p_meister_y in der Reihenfolge (D, C), die Spalten von p_sieg aber in
  # (C, D). Eine Positionszuordnung rechnete fuer A:
  #   0.6 * (0.3 * 0.5 + 0.7 * 0.8) = 0.426  -- falsch.
  # Richtig bleibt 0.354.
  env <- source_aufstieg()
  f <- fn(env, "aufstiegswahrscheinlichkeit")

  p <- f(meister_nord, c(D = 0.3, C = 0.7), sieg_nord_gegen_bayern)
  expect_equal(p[["A"]], 0.354, tolerance = 1e-12)
  expect_false(isTRUE(all.equal(p[["A"]], 0.426)))

  # Dasselbe fuer die Zeilen: p_meister_x in (B, A).
  p2 <- f(c(B = 0.4, A = 0.6), meister_bayern, sieg_nord_gegen_bayern)
  expect_equal(p2[["A"]], 0.354, tolerance = 1e-12)
  expect_equal(p2[["B"]], 0.156, tolerance = 1e-12)
})

test_that("Doppelsumme bricht ohne Namen oder mit fehlender Paarung ab", {
  env <- source_aufstieg()
  f <- fn(env, "aufstiegswahrscheinlichkeit")

  ohne_namen <- unname(sieg_nord_gegen_bayern)
  expect_error(f(meister_nord, meister_bayern, ohne_namen), "[Nn]ame")

  # Team E in Y, aber keine Spalte dafuer in p_sieg.
  expect_error(f(meister_nord, c(C = 0.5, D = 0.3, E = 0.2), sieg_nord_gegen_bayern), "\\bE\\b")

  # Eine Gewinnwahrscheinlichkeit ausserhalb [0, 1].
  kaputt <- sieg_nord_gegen_bayern
  kaputt["A", "C"] <- 1.2
  expect_error(f(meister_nord, meister_bayern, kaputt))
})

# --- Rotation: saisonabhaengig, nicht fest verdrahtet -------------------------

test_that("aufstiegsmodus 2026: Nordost direkt, Nord gegen Bayern", {
  # Amtlich: BFV A&A-Regelung 2026/27, I. Nr. 1 -- und daraus zwingend
  # Nordost als dritter Direktaufsteiger. NICHT die Wikipedia-Tabelle
  # (Bayern direkt, Nord-Nordost), die ist um ein Jahr verschoben.
  env <- source_aufstieg()
  modus <- fn(env, "aufstiegsmodus")(2026)

  expect_setequal(modus$direkt, c("West", "SuedWest", "Nordost"))
  expect_setequal(modus$playoff, c("Nord", "Bayern"))
  # Die Wikipedia-Variante muss ausgeschlossen sein.
  expect_false("Bayern" %in% modus$direkt)
  expect_false("Nordost" %in% modus$playoff)
})

test_that("aufstiegsmodus akzeptiert die Saison als Integer und als Double", {
  env <- source_aufstieg()
  f <- fn(env, "aufstiegsmodus")
  expect_equal(f(2026L), f(2026))
})

test_that("aufstiegsmodus: West und SuedWest sind in jeder belegten Saison direkt", {
  # Par. 55b Nr. 2: Dauerplaetze. Was auch immer in der Rotationstabelle
  # steht -- diese beiden rotieren nie.
  env <- source_aufstieg()
  rotation <- get("AUFSTIEGSROTATION", envir = env)
  f <- fn(env, "aufstiegsmodus")

  expect_true(length(rotation) >= 1)
  expect_equal(unname(rotation[["2026"]]), "Nordost")
  for (saison in names(rotation)) {
    modus <- f(as.integer(saison))
    expect_true(all(c("West", "SuedWest") %in% modus$direkt), info = saison)
    expect_length(modus$direkt, 3)
    expect_length(modus$playoff, 2)
    expect_setequal(c(modus$direkt, modus$playoff), env$STAFFELN)
  }
})

test_that("aufstiegsmodus: eine unbekannte Saison ist ein Fehler, kein Default", {
  # Die Reihenfolge ueber 2026/27 hinaus ist nirgends niedergelegt
  # (Doku 3.3). Wer 2027 fragt, muss recherchieren -- nicht die 2026er
  # Zuordnung stillschweigend weiterbenutzen.
  env <- source_aufstieg()
  f <- fn(env, "aufstiegsmodus")
  err <- expect_error(f(2027))
  expect_match(conditionMessage(err), "2027")
})

test_that("aufstiegsmodus ist ueber die Rotationstabelle konfigurierbar", {
  # Der Nachweis, dass die Zuordnung Daten sind und keine Konstante: Eine
  # hypothetische Tabelle fuer eine andere Saison dreht das Ergebnis.
  env <- source_aufstieg()
  f <- fn(env, "aufstiegsmodus")

  modus <- f(2031, rotation = c("2031" = "Bayern"))
  expect_setequal(modus$direkt, c("West", "SuedWest", "Bayern"))
  expect_setequal(modus$playoff, c("Nord", "Nordost"))

  modus2 <- f(2032, rotation = c("2031" = "Bayern", "2032" = "Nord"))
  expect_setequal(modus2$direkt, c("West", "SuedWest", "Nord"))
  expect_setequal(modus2$playoff, c("Nordost", "Bayern"))
})

test_that("aufstiegsmodus lehnt eine Dauerplatz-Staffel als Rotationswert ab", {
  # West rotiert nicht; ein solcher Eintrag ist ein Konfigurationsfehler.
  env <- source_aufstieg()
  f <- fn(env, "aufstiegsmodus")
  expect_error(f(2031, rotation = c("2031" = "West")), "West")
  expect_error(f(2031, rotation = c("2031" = "Suedost")), "Suedost")
})

test_that("rl_aufstiegs_slots 2026 folgt dem Modus", {
  env <- source_aufstieg()
  f <- fn(env, "rl_aufstiegs_slots")

  for (staffel in c("West", "SuedWest", "Nordost")) {
    s <- f(staffel, 2026)
    expect_equal(s$promotion_slots, 1L, info = staffel)
    expect_equal(s$playoff_slots, 0L, info = staffel)
  }
  for (staffel in c("Nord", "Bayern")) {
    s <- f(staffel, 2026)
    expect_equal(s$promotion_slots, 0L, info = staffel)
    expect_equal(s$playoff_slots, 1L, info = staffel)
  }
})

# --- Registry: der korrekte Sollzustand 2026/27 --------------------------------

test_that("Registry: Nord und Bayern haben keinen Direktplatz, sondern ein Aufstiegsspiel", {
  # Heute steht dort promotion_slots = 1 -- das ist fuer 2026/27 falsch.
  env <- source_aufstieg()
  reg <- env$league_registry()

  expect_equal(reg$rl_nord$promotion_slots, 0L)
  expect_equal(reg$rl_nord$playoff_slots, 1L)
  expect_equal(reg$rl_bayern$promotion_slots, 0L)
  expect_equal(reg$rl_bayern$playoff_slots, 1L)
})

test_that("Registry: Nordost ist Direktaufsteiger ohne Playoff", {
  # Heute steht dort playoff_slots = 1 -- fuer 2026/27 falsch.
  env <- source_aufstieg()
  reg <- env$league_registry()

  expect_equal(reg$rl_nordost$promotion_slots, 1L)
  expect_equal(reg$rl_nordost$playoff_slots, 0L)
})

test_that("Registry: West und SuedWest bleiben Direktaufsteiger", {
  env <- source_aufstieg()
  reg <- env$league_registry()

  for (key in c("rl_west", "rl_suedwest")) {
    expect_equal(reg[[key]]$promotion_slots, 1L, info = key)
    expect_equal(reg[[key]]$playoff_slots, 0L, info = key)
  }
})

test_that("Registry: alle fuenf Regionalligen tragen relegation_slots (die Basis vor Kopplung)", {
  # Basis je Staffel (Doku 3.2): Nord 3, Nordost 1, West 4, SuedWest 3,
  # Bayern 2 Direktabsteiger. Heute fehlt das Feld ueberall.
  env <- source_aufstieg()
  reg <- env$league_registry()

  expect_equal(reg$rl_nord$relegation_slots, 3L)
  expect_equal(reg$rl_nordost$relegation_slots, 1L)
  expect_equal(reg$rl_west$relegation_slots, 4L)
  expect_equal(reg$rl_suedwest$relegation_slots, 3L)
  expect_equal(reg$rl_bayern$relegation_slots, 2L)
})

test_that("Registry: Bayern fuehrt die Abstiegsrelegation getrennt vom Aufstiegsspiel", {
  # playoff_slots = 1 ist das Aufstiegsspiel gegen Nord. Die zwei
  # Relegationsplaetze nach unten (BFV A&A II. Nr. 3) sind eine andere
  # Groesse und duerfen nicht in dasselbe Feld -- sonst waere "1" oder "3"
  # beides falsch.
  env <- source_aufstieg()
  reg <- env$league_registry()

  expect_equal(reg$rl_bayern$relegation_playoff_slots, 2L)
  for (key in c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest")) {
    rps <- reg[[key]]$relegation_playoff_slots
    expect_true(is.null(rps) || identical(rps, 0L), info = key)
  }
})

test_that("Registry-Slots der Regionalligen stimmen mit dem saisonabhaengigen Modus ueberein", {
  # Die Registry darf die 2026er Zuordnung tragen -- aber sie muss mit
  # aufstiegsmodus(2026) uebereinstimmen. Laufen beide auseinander, ist
  # eine Stelle fest verdrahtet.
  env <- source_aufstieg()
  reg <- env$league_registry()
  f <- fn(env, "rl_aufstiegs_slots")

  for (key in c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest", "rl_bayern")) {
    s <- f(reg[[key]]$staffel, 2026)
    expect_equal(reg[[key]]$promotion_slots, s$promotion_slots, info = key)
    expect_equal(reg[[key]]$playoff_slots, s$playoff_slots, info = key)
  }
})

test_that("Registry: relegation_slots ist die Basis von abstiegsplaetze(staffel, 0)", {
  # Bruecke zwischen Phase 6 und Registry: Ohne Drittliga-Absteiger muss
  # die Kopplung genau die Basis liefern.
  env <- source_aufstieg()
  reg <- env$league_registry()
  ap <- fn(env, "abstiegsplaetze")

  for (key in c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest", "rl_bayern")) {
    expect_equal(ap(reg[[key]]$staffel, 0L), reg[[key]]$relegation_slots, info = key)
  }
})

# --- Die ganze Kette: rl_aufstiegsprognose -------------------------------------

prognosen_2026 <- function() {
  list(
    Nord     = prognose_aus_meister(meister_nord),
    Nordost  = prognose_aus_meister(c(E = 0.9, F = 0.1)),
    West     = prognose_aus_meister(c(G = 0.55, H = 0.45)),
    SuedWest = prognose_aus_meister(c(I = 1.0, J = 0.0)),
    Bayern   = prognose_aus_meister(meister_bayern, teams = 19L)
  )
}

test_that("rl_aufstiegsprognose: Direktaufsteiger bekommen P(Meister)", {
  env <- source_aufstieg()
  f <- fn(env, "rl_aufstiegsprognose")
  pr <- prognosen_2026()

  df <- f("Nordost", pr, season = 2026)
  expect_s3_class(df, "data.frame")
  expect_equal(colnames(df), "Aufstieg")
  expect_equal(df["E", "Aufstieg"], 0.9)
  expect_equal(df["F", "Aufstieg"], 0.1)

  expect_equal(f("West", pr, season = 2026)["G", "Aufstieg"], 0.55)
  df_sw <- f("SuedWest", pr, season = 2026)
  expect_identical(df_sw["I", "Aufstieg"], 1)
  expect_identical(df_sw["J", "Aufstieg"], 0)
})

test_that("rl_aufstiegsprognose: Nord und Bayern rechnen die Doppelsumme gegeneinander", {
  env <- source_aufstieg()
  f <- fn(env, "rl_aufstiegsprognose")
  pr <- prognosen_2026()

  df_nord <- f("Nord", pr, season = 2026, p_sieg = sieg_nord_gegen_bayern)
  expect_equal(df_nord["A", "Aufstieg"], 0.354, tolerance = 1e-12)
  expect_equal(df_nord["B", "Aufstieg"], 0.156, tolerance = 1e-12)
  # Nicht die Meisterwahrscheinlichkeit durchgereicht.
  expect_false(isTRUE(all.equal(df_nord["A", "Aufstieg"], 0.6)))

  df_bayern <- f("Bayern", pr, season = 2026, p_sieg = sieg_nord_gegen_bayern)
  expect_equal(df_bayern["C", "Aufstieg"], 0.406, tolerance = 1e-12)
  expect_equal(df_bayern["D", "Aufstieg"], 0.084, tolerance = 1e-12)

  expect_equal(sum(df_nord$Aufstieg) + sum(df_bayern$Aufstieg), 1, tolerance = 1e-12)
})

test_that("rl_aufstiegsprognose: Playoff-Staffel ohne Gewinnquoten bricht ab", {
  # Keine erfundene 50:50. Wer die Zweikampfquote nicht liefert, bekommt
  # keine Zahl.
  env <- source_aufstieg()
  f <- fn(env, "rl_aufstiegsprognose")
  expect_error(f("Nord", prognosen_2026(), season = 2026), "p_sieg")
  expect_error(f("Bayern", prognosen_2026(), season = 2026, p_sieg = NULL), "p_sieg")
})

test_that("rl_aufstiegsprognose: bei anderer Rotation wird Bayern zum Direktaufsteiger", {
  # Dieselben Prognosen, eine andere Saisonkonfiguration: Bayern direkt,
  # Nord gegen Nordost. Dann ist P(C) = 0.7, nicht 0.406 -- und Nord
  # rechnet gegen E/F statt gegen C/D.
  env <- source_aufstieg()
  f <- fn(env, "rl_aufstiegsprognose")
  pr <- prognosen_2026()
  rotation <- c("2031" = "Bayern")

  df_bayern <- f("Bayern", pr, season = 2031, rotation = rotation)
  expect_equal(df_bayern["C", "Aufstieg"], 0.7)

  sieg_nord_gegen_nordost <- matrix(c(0.5, 0.5,
                                      0.5, 0.5), nrow = 2,
                                    dimnames = list(c("A", "B"), c("E", "F")))
  df_nord <- f("Nord", pr, season = 2031, rotation = rotation,
               p_sieg = sieg_nord_gegen_nordost)
  expect_equal(df_nord["A", "Aufstieg"], 0.3)
  expect_equal(df_nord["B", "Aufstieg"], 0.2)
})

test_that("rl_aufstiegsprognose bricht bei fehlender Partnerprognose ab", {
  # Nord ist Playoff-Staffel; ohne die Bayern-Prognose fehlt Y.
  env <- source_aufstieg()
  f <- fn(env, "rl_aufstiegsprognose")
  pr <- prognosen_2026()
  pr$Bayern <- NULL
  expect_error(f("Nord", pr, season = 2026, p_sieg = sieg_nord_gegen_bayern), "Bayern")
})
