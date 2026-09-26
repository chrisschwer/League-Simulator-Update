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

# Der Aufstiegsteil braucht VIER Dateien, und die Reihenfolge ist nicht
# beliebig: rl_aufstieg.R ruft pruefe_staffel() auf, das in
# rl_abstiegskopplung.R steht, und p_sieg_matrix() aus aufstiegsspiele.R.
# Fehlt eine, faellt die Aufloesung ueber die Elternumgebung auf zufaellig
# vorhandene Definitionen aus anderen Testdateien zurueck -- der Test waere
# dann von der Ausfuehrungsreihenfolge abhaengig. (Begruendung des
# ehemaligen source_aufstieg()-Helfers, s. Git-Historie phase5 f62724d,
# Z. 201-206; die Reihenfolge steckt seit T6 in den source_module()-Aufrufen.)
# --- aus test-phase5-regionalligen.R ---
test_that("bei den Direktaufsteigern sind Meister und Aufstieg wirklich gleich", {
  # Die Rechtfertigung der einen Spalte: Nur wenn rl_aufstiegsprognose()
  # dort exakt die Meisterwahrscheinlichkeit liefert, ist die Vereinfachung
  # keine stille Abweichung. Nicht angenommen, sondern nachgerechnet.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")

  # Ungleiche Meisterchancen, damit ein versehentliches "alle gleich"
  # nicht durchginge.
  prognose <- function(teams, praefix) {
    m <- matrix(1 / teams, nrow = teams, ncol = teams,
                dimnames = list(paste0(praefix, seq_len(teams)),
                                as.character(seq_len(teams))))
    m[, 1] <- c(0.5, 0.3, rep(0.2 / (teams - 2), teams - 2))
    m
  }
  prognosen <- list(Nord = prognose(18, "N"), Nordost = prognose(18, "O"),
                    West = prognose(18, "W"), SuedWest = prognose(18, "S"),
                    Bayern = prognose(19, "B"))

  for (staffel in c("Nordost", "West", "SuedWest")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026)
    expect_equal(unname(df$Aufstieg),
                 unname(prognosen[[staffel]][, 1]),
                 tolerance = 1e-12, info = staffel)
  }
})

test_that("P(Aufstieg) ist fuer Nord und Bayern strikt kleiner als P(Meister)", {
  # Der inhaltliche Grund fuer die zweite Spalte: Wer Meister wird, muss
  # noch zwei Aufstiegsspiele gewinnen. Waeren beide Zahlen gleich, brauchte
  # es die Spalte nicht -- und die Seite behauptete einen Direktaufstieg.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")

  nord <- matrix(1 / 18, nrow = 18, ncol = 18,
                 dimnames = list(paste0("N", 1:18), as.character(1:18)))
  bayern <- matrix(1 / 19, nrow = 19, ncol = 19,
                   dimnames = list(paste0("B", 1:19), as.character(1:19)))
  prognosen <- list(Nord = nord, Nordost = nord, West = nord,
                    SuedWest = nord, Bayern = bayern)

  # Ausgeglichene Zweikaempfe: jede Paarung 50:50. Zeilen = Nord (in
  # STAFFELN frueher), Spalten = Bayern.
  p_sieg <- matrix(0.5, nrow = 18, ncol = 19,
                   dimnames = list(rownames(nord), rownames(bayern)))

  df_nord <- auf$rl_aufstiegsprognose("Nord", prognosen, 2026, p_sieg = p_sieg)
  df_bayern <- auf$rl_aufstiegsprognose("Bayern", prognosen, 2026,
                                        p_sieg = p_sieg)

  # P(Meister) = 1/18 bzw. 1/19; mit 50 % Siegquote genau die Haelfte.
  expect_equal(unname(df_nord$Aufstieg[[1]]), 0.5 / 18, tolerance = 1e-12)
  expect_equal(unname(df_bayern$Aufstieg[[1]]), 0.5 / 19, tolerance = 1e-12)

  expect_lt(df_nord$Aufstieg[[1]], 1 / 18)
  expect_lt(df_bayern$Aufstieg[[1]], 1 / 19)

  # Zusammen steigt genau EINE der beiden Staffeln auf.
  expect_equal(sum(df_nord$Aufstieg) + sum(df_bayern$Aufstieg), 1,
               tolerance = 1e-9)
})

# ===========================================================================
# 4a. Die Seite "Aufstieg in die 3. Liga"
# ===========================================================================
#
# ENTSCHIEDEN (Nutzer, 2026-09-07): Variante 2 aus dem Kopfentwurf --
# Randsummen, keine Matrix. Navigation unter "Regionalliga".
#
# Je Team eine Zeile mit vier Spalten:
#
#   Team | P(Meister) | P(Aufstieg) | Siegquote
#
# P(Meister) ist Spalte 1 der jeweiligen Prognose, P(Aufstieg) kommt aus
# rl_aufstiegsprognose(), und die Siegquote ist deren Quotient:
#
#   Siegquote = P(Aufstieg) / P(Meister)
#
# Das ist die ueber den Gegner ausintegrierte Zweikampfquote -- also genau
# die Zahl, die die 18x19-Matrix aus Variante 1 zusammenfasst. Fuer die
# Direktaufsteiger ist sie 1, weil dort P(Aufstieg) = P(Meister) gilt.
#
# WAS BEWUSST NICHT GEBAUT WIRD: keine Paarungsmatrix, keine Liste der
# wahrscheinlichsten Paarungen. Begruendung des Nutzers: "Fuer naechste
# Saison muessen wir eh vermutlich neue Aufstiegsregeln implementieren, und
# dann bauen wir halt auch die Aufstiegsseite passend um." Also die
# einfachste tragfaehige Form, kein Vorbau fuer Regeln, die es noch nicht
# gibt. Wer hier spaeter eine Matrix ergaenzt, faengt bewusst neu an --
# diese Tests stehen ihm nicht im Weg, weil sie nur die vier Spalten
# festhalten.
#
# DIE UNDEFINIERTE STELLE: Bei P(Meister) = 0 ist der Quotient undefiniert
# (0/0). Festgelegt: Die Zelle bleibt LEER. Weder 0 noch NaN noch "100 %".
#
#   Eine 0 waere eine Aussage ueber die Spielstaerke ("verliert das
#   Aufstiegsspiel sicher"), die aus den Daten nicht folgt -- das Team
#   erreicht das Spiel ja gar nicht. NaN waere ein sichtbarer Rechenfehler
#   auf einer veroeffentlichten Seite. Leer sagt genau das Richtige: Zu
#   dieser Frage weiss das Modell nichts, weil sie sich nicht stellt.
#
#   Dieselbe Konvention wie in der Heatmap, wo eine Null-Zelle leer bleibt
#   (render_heatmap / .heatmap_cell).
#
# SAISONABHAENGIGKEIT -- die Falle: Die Paarung Nord-Bayern gilt fuer
# 2026/27 und NUR dafuer. Wer den dritten Direktplatz bekommt, beschliesst
# das DFB-Praesidium jaehrlich (Regeldoku 3.3). Die Seite darf die Paarung
# deshalb nicht verdrahten, sondern muss aufstiegsmodus(season) folgen.
# Ein Test injiziert eine ANDERE Rotation und verlangt eine andere
# Playoff-Staffel -- ohne Fakten fuer kuenftige Saisons zu erfinden: Die
# injizierte Rotation ist Testeingabe, keine Behauptung ueber 2027/28.
# Eine unbekannte Saison muss abbrechen.

# Prognosematrix mit vorgegebenen Meisterchancen. Nur Spalte 1 traegt die
# Aussage; der Rest ist Fuellmasse, damit die Matrix quadratisch bleibt.
mk_meister <- function(praefix, p_meister) {
  n <- length(p_meister)
  m <- matrix(0, nrow = n, ncol = n,
              dimnames = list(paste0(praefix, seq_len(n)),
                              as.character(seq_len(n))))
  m[, 1] <- p_meister
  m
}

# Realistische, ungleiche Meisterchancen -- ein versehentliches "alle
# gleich" wuerde damit auffallen. Nord und Bayern spielen 2026/27 mit 18
# bzw. 19 Vereinen.
aufstiegs_prognosen <- function() {
  list(
    Nord     = mk_meister("N", c(0.42, 0.31, 0.15, 0.08, 0.04, rep(0, 13))),
    Nordost  = mk_meister("O", c(0.50, 0.30, 0.20, rep(0, 15))),
    West     = mk_meister("W", c(0.45, 0.35, 0.20, rep(0, 15))),
    SuedWest = mk_meister("S", c(0.60, 0.25, 0.15, rep(0, 15))),
    Bayern   = mk_meister("B", c(0.55, 0.20, 0.12, 0.09, 0.04, rep(0, 14)))
  )
}

# Ungleiche Zweikampfquoten: Zeilen = Nord (in STAFFELN frueher), Spalten
# = Bayern. Eine konstante Matrix wuerde einen Positionsfehler in der
# Doppelsumme nicht sichtbar machen.
aufstiegs_p_sieg <- function(prognosen = aufstiegs_prognosen()) {
  n <- nrow(prognosen$Nord)
  m <- nrow(prognosen$Bayern)
  matrix(seq(0.2, 0.8, length.out = n * m), nrow = n, ncol = m,
         dimnames = list(rownames(prognosen$Nord),
                         rownames(prognosen$Bayern)))
}

# --- Direktaufsteiger: Meister = Aufstieg, Siegquote 100 % ------------------

test_that("bei den Direktaufsteigern sind Meister und Aufstieg exakt gleich", {
  # Die Rechtfertigung dafuer, dass die Siegquote dort entfaellt: Es gibt
  # kein Spiel, das noch zu gewinnen waere. Exakt gleich, nicht ungefaehr
  # -- rl_aufstiegsprognose() reicht P(Meister) unveraendert durch.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")
  prognosen <- aufstiegs_prognosen()

  for (staffel in c("Nordost", "West", "SuedWest")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026)
    expect_identical(unname(df$Aufstieg),
                     unname(prognosen[[staffel]][, 1]), info = staffel)
  }
})

test_that("die Siegquote der Direktaufsteiger ist exakt eins, wo es einen Meister gibt", {
  # Der Quotient P(Aufstieg)/P(Meister) ist dort definitionsgemaess 1. Die
  # Seite darf ihn als "100 %" zeigen oder weglassen -- was sie NICHT darf,
  # ist eine andere Zahl.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")
  prognosen <- aufstiegs_prognosen()

  for (staffel in c("Nordost", "West", "SuedWest")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026)
    p_meister <- prognosen[[staffel]][, 1]
    hat_chance <- p_meister > 0

    quote <- unname(df$Aufstieg[hat_chance]) / unname(p_meister[hat_chance])
    expect_equal(quote, rep(1, sum(hat_chance)), tolerance = 1e-12,
                 info = staffel)
  }
})

# --- Nord und Bayern: die Doppelsumme und ihr Quotient ----------------------

test_that("die Siegquote von Nord und Bayern liegt strikt zwischen null und eins", {
  # Der inhaltliche Kern der Spalte: Wer Meister wird, muss noch zwei
  # Spiele gewinnen -- also weniger als 1. Und die Gegner sind nicht
  # unschlagbar -- also mehr als 0. Genau eine Zahl dazwischen macht die
  # Spalte ueberhaupt sinnvoll.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")
  prognosen <- aufstiegs_prognosen()
  p_sieg <- aufstiegs_p_sieg(prognosen)

  for (staffel in c("Nord", "Bayern")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026, p_sieg = p_sieg)
    p_meister <- prognosen[[staffel]][, 1]
    hat_chance <- p_meister > 0

    quote <- unname(df$Aufstieg[hat_chance]) / unname(p_meister[hat_chance])
    expect_true(all(quote > 0), info = staffel)
    expect_true(all(quote < 1), info = staffel)
  }
})

test_that("die Siegquote ist wirklich die ausintegrierte Zweikampfquote", {
  # Nicht nur ein Wertebereich, sondern die Zahl selbst: Bei einer
  # konstanten Zweikampfquote q muss der Quotient fuer JEDES Nord-Team
  # exakt q sein, weil die Meisterchancen der Gegenstaffel auf 1 summieren.
  # Damit ist die Formel gepinnt, nicht nur ihr Vorzeichen.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")
  prognosen <- aufstiegs_prognosen()

  q <- 0.37
  p_sieg <- matrix(q, nrow = nrow(prognosen$Nord),
                   ncol = nrow(prognosen$Bayern),
                   dimnames = list(rownames(prognosen$Nord),
                                   rownames(prognosen$Bayern)))

  df_nord <- auf$rl_aufstiegsprognose("Nord", prognosen, 2026,
                                      p_sieg = p_sieg)
  p_meister <- prognosen$Nord[, 1]
  hat_chance <- p_meister > 0

  quote <- unname(df_nord$Aufstieg[hat_chance]) / unname(p_meister[hat_chance])
  expect_equal(quote, rep(q, sum(hat_chance)), tolerance = 1e-12)

  # Und die Gegenrichtung: Ueber zwei Spiele gibt es kein Remis, Bayern
  # traegt also 1 - q.
  df_bayern <- auf$rl_aufstiegsprognose("Bayern", prognosen, 2026,
                                        p_sieg = p_sieg)
  p_meister_b <- prognosen$Bayern[, 1]
  hat_chance_b <- p_meister_b > 0
  quote_b <- unname(df_bayern$Aufstieg[hat_chance_b]) /
    unname(p_meister_b[hat_chance_b])
  expect_equal(quote_b, rep(1 - q, sum(hat_chance_b)), tolerance = 1e-12)
})

test_that("ohne Meisterchance ist die Aufstiegschance exakt null", {
  # Die Vorbedingung fuer die Leer-Regel: Wo P(Meister) = 0 ist, muss auch
  # P(Aufstieg) IDENTISCH 0 sein -- nicht 1e-18. Sonst zeigte die Seite
  # ein "<1" fuer ein Team, das rechnerisch gar nicht aufsteigen kann, und
  # der Quotient waere kein 0/0, sondern eine erfundene Zahl.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")
  prognosen <- aufstiegs_prognosen()
  p_sieg <- aufstiegs_p_sieg(prognosen)

  df <- auf$rl_aufstiegsprognose("Nord", prognosen, 2026, p_sieg = p_sieg)
  ohne_chance <- prognosen$Nord[, 1] == 0
  expect_gt(sum(ohne_chance), 0)   # der Fall kommt in der Fixture vor

  expect_identical(unname(df$Aufstieg[ohne_chance]),
                   rep(0, sum(ohne_chance)))
})

# --- Die beiden Pflicht-Invarianten -----------------------------------------

test_that("Nord und Bayern stellen zusammen genau einen Aufsteiger", {
  # PFLICHTTEST (Vorgabe des Nutzers). Genau eine der beiden Staffeln
  # gewinnt die Aufstiegsspiele, also summiert P(Aufstieg) ueber BEIDE
  # Staffeln auf exakt 1.
  #
  # Das ist keine Zufallseigenschaft der Zahlen: P(X Meister) summiert je
  # Staffel auf 1, und p_sieg[x, y] + (1 - p_sieg[x, y]) = 1 fuer jede
  # Paarung -- ueber zwei Spiele gibt es keinen dritten Ausgang. Die
  # Doppelsumme zerlegt damit die Eins vollstaendig.
  #
  # Toleranz 1e-9, nicht 0.01: Eine Doppelsumme, die Masse verliert (etwa
  # weil eine Zeile ueber die Position statt ueber den Namen zugeordnet
  # wird), faellt bei weiter Toleranz nicht auf.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")
  prognosen <- aufstiegs_prognosen()
  p_sieg <- aufstiegs_p_sieg(prognosen)

  df_nord <- auf$rl_aufstiegsprognose("Nord", prognosen, 2026,
                                      p_sieg = p_sieg)
  df_bayern <- auf$rl_aufstiegsprognose("Bayern", prognosen, 2026,
                                        p_sieg = p_sieg)

  expect_equal(sum(df_nord$Aufstieg) + sum(df_bayern$Aufstieg), 1,
               tolerance = 1e-9)

  # Und beide Anteile sind echt positiv -- die Eins liegt nicht ganz auf
  # einer Seite, sonst pruefte die Summe nichts.
  expect_gt(sum(df_nord$Aufstieg), 0)
  expect_gt(sum(df_bayern$Aufstieg), 0)
})

test_that("jede Direktaufsteiger-Staffel stellt genau einen Aufsteiger", {
  # PFLICHTTEST (Vorgabe des Nutzers). Genau ein Team wird Meister, und der
  # Meister steigt auf -- die Spalte summiert je Staffel auf exakt 1.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")
  prognosen <- aufstiegs_prognosen()

  for (staffel in c("Nordost", "West", "SuedWest")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026)
    expect_equal(sum(df$Aufstieg), 1, tolerance = 1e-9, info = staffel)
  }
})

test_that("ueber alle fuenf Staffeln steigen genau vier Teams auf", {
  # Die Zusammenschau beider Invarianten -- und die Zahl, die Par. 55b
  # DFB-SpO vorgibt: drei Direktaufsteiger plus einer aus den
  # Aufstiegsspielen. Waere eine Staffel doppelt gezaehlt oder eine
  # vergessen, stuende hier 3 oder 5.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")
  prognosen <- aufstiegs_prognosen()
  p_sieg <- aufstiegs_p_sieg(prognosen)

  summe <- sum(vapply(c("Nord", "Nordost", "West", "SuedWest", "Bayern"),
                      function(s) {
                        df <- auf$rl_aufstiegsprognose(s, prognosen, 2026,
                                                       p_sieg = p_sieg)
                        sum(df$Aufstieg)
                      }, numeric(1)))

  expect_equal(summe, 4, tolerance = 1e-9)
})

# --- Saisonabhaengigkeit: die Paarung ist nicht verdrahtet ------------------

test_that("die Seite folgt einer injizierten Rotation statt der verdrahteten Paarung", {
  # DIE FALLE: Nord gegen Bayern gilt fuer 2026/27 und NUR dafuer. Wer den
  # dritten Direktplatz bekommt, beschliesst das DFB-Praesidium jaehrlich.
  #
  # Der Test injiziert eine ANDERE Rotation und verlangt eine andere
  # Playoff-Paarung. Die injizierte Rotation ist Testeingabe, KEINE
  # Behauptung darueber, wer 2027/28 wirklich dran ist -- deshalb eine
  # Saison, die in AUFSTIEGSROTATION bewusst nicht steht.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")

  # Stand 2026/27: Nordost direkt, Nord gegen Bayern.
  modus_2026 <- auf$aufstiegsmodus(2026)
  expect_setequal(modus_2026$direkt, c("West", "SuedWest", "Nordost"))
  expect_setequal(modus_2026$playoff, c("Nord", "Bayern"))

  # Injiziert: Nord traegt den Rotationsplatz -- dann spielen Nordost und
  # Bayern.
  modus_alt <- auf$aufstiegsmodus(2027, rotation = c("2027" = "Nord"))
  expect_setequal(modus_alt$direkt, c("West", "SuedWest", "Nord"))
  expect_setequal(modus_alt$playoff, c("Nordost", "Bayern"))

  # Und der dritte Fall, damit nicht bloss zwei Zustaende geprueft sind.
  modus_bayern <- auf$aufstiegsmodus(2027, rotation = c("2027" = "Bayern"))
  expect_setequal(modus_bayern$playoff, c("Nord", "Nordost"))
})

test_that("die Aufstiegsprognose folgt der injizierten Rotation", {
  # Nicht nur der Modus, sondern die RECHNUNG: Unter einer Rotation, in der
  # Nord direkt aufsteigt, muss Nord P(Meister) bekommen -- und Nordost
  # stattdessen die Doppelsumme gegen Bayern. Waere die Paarung
  # verdrahtet, kaeme hier weiterhin die Nord-Bayern-Rechnung heraus.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")
  prognosen <- aufstiegs_prognosen()
  rotation <- c("2027" = "Nord")

  df_nord <- auf$rl_aufstiegsprognose("Nord", prognosen, 2027,
                                      rotation = rotation)
  expect_identical(unname(df_nord$Aufstieg),
                   unname(prognosen$Nord[, 1]))

  # Nordost bestreitet jetzt die Aufstiegsspiele -- gegen Bayern. Zeilen =
  # Nordost (in STAFFELN frueher als Bayern), Spalten = Bayern.
  p_sieg <- matrix(0.5, nrow = nrow(prognosen$Nordost),
                   ncol = nrow(prognosen$Bayern),
                   dimnames = list(rownames(prognosen$Nordost),
                                   rownames(prognosen$Bayern)))
  df_nordost <- auf$rl_aufstiegsprognose("Nordost", prognosen, 2027,
                                         p_sieg = p_sieg, rotation = rotation)
  df_bayern <- auf$rl_aufstiegsprognose("Bayern", prognosen, 2027,
                                        p_sieg = p_sieg, rotation = rotation)

  # Halbe Meisterchance, weil jede Paarung 50:50 steht.
  expect_equal(unname(df_nordost$Aufstieg),
               unname(prognosen$Nordost[, 1]) / 2, tolerance = 1e-12)
  # Die Invariante gilt auch unter der anderen Rotation.
  expect_equal(sum(df_nordost$Aufstieg) + sum(df_bayern$Aufstieg), 1,
               tolerance = 1e-9)
})

test_that("eine unbekannte Saison bricht ab, statt die Paarung zu raten", {
  # Der wichtigste Teil der Saisonabhaengigkeit: Fuer 2027/28 ist noch
  # nicht bekannt, wer den Rotationsplatz traegt. Die Seite darf dann NICHT
  # mit dem Vorjahreswert weiterrechnen -- das waere eine Prognose, die
  # falsch ist, ohne dass etwas fehlschlaegt.
  auf <- source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")

  expect_error(auf$aufstiegsmodus(2027), "2027")
  expect_error(auf$aufstiegsmodus(2027), "DFB-Praesidium")

  # Auch die ganze Kette bricht ab, nicht erst irgendein Folgeschritt.
  expect_error(
    auf$rl_aufstiegsprognose("Nord", aufstiegs_prognosen(), 2027),
    "2027"
  )
})
