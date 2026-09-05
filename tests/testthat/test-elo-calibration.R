# Unit tests fuer die Offline-ELO-Kalibrierung (Phase 4 Ligen-Ausbau).
#
# Die Kalibrierung erzeugt Start-ELOs fuer Ligen ohne Historie. Sie baut den
# ELO-Walk NICHT in R nach (ADR 0002), sondern laesst ihn von Rust rechnen;
# die hier getesteten Funktionen sind die reinen Rechenschritte davor und
# danach: Ankerung, Relegationskopplung und die Streuungspruefung.

library(testthat)

source("../../RCode/elo_calibration.R")

# --- anchor_to_mean ---------------------------------------------------------

test_that("anchor_to_mean trifft den Zielmittelwert exakt", {
  elos <- c(1200, 1300, 1400, 1500)

  result <- anchor_to_mean(elos, target_mean = 920)

  expect_equal(mean(result), 920)
})

test_that("anchor_to_mean verschiebt additiv und laesst die Streuung unveraendert", {
  elos <- c(1200, 1300, 1400, 1500)

  result <- anchor_to_mean(elos, target_mean = 920)

  # Additive Verschiebung: alle Abstaende bleiben erhalten.
  expect_equal(sd(result), sd(elos))
  expect_equal(diff(result), diff(elos))
})

test_that("anchor_to_mean ist eine Identitaet, wenn der Mittelwert schon stimmt", {
  elos <- c(900, 920, 940)

  expect_equal(anchor_to_mean(elos, target_mean = 920), elos)
})

test_that("anchor_to_mean akzeptiert benannte Vektoren und erhaelt die Namen", {
  elos <- c(a = 1000, b = 1100)

  result <- anchor_to_mean(elos, target_mean = 500)

  expect_equal(names(result), c("a", "b"))
  expect_equal(mean(result), 500)
})

test_that("anchor_to_mean weist leere Eingaben zurueck", {
  expect_error(anchor_to_mean(numeric(0), target_mean = 920), "leer")
})

# --- apply_relegation_coupling ----------------------------------------------

test_that("apply_relegation_coupling verschiebt beide Ligen gegenlaeufig", {
  # Die Relegation zeigt: Liga A ist um 60 ELO staerker als angenommen.
  # Die Haelfte davon wirkt auf alle Teams beider Ligen.
  elos_a <- c(1000, 1100)
  elos_b <- c(900, 950)

  result <- apply_relegation_coupling(elos_a, elos_b, delta = 60, share = 0.5)

  expect_equal(result$league_a, c(1030, 1130))
  expect_equal(result$league_b, c(870, 920))
})

test_that("apply_relegation_coupling erhaelt die Gesamt-ELO bei gleicher Teamzahl", {
  elos_a <- c(1000, 1100, 1200)
  elos_b <- c(900, 950, 1000)
  total_before <- sum(elos_a) + sum(elos_b)

  result <- apply_relegation_coupling(elos_a, elos_b, delta = 90)

  expect_equal(sum(result$league_a) + sum(result$league_b), total_before)
})

test_that("apply_relegation_coupling gewichtet ungleiche Ligagroessen korrekt", {
  # Bei ungleicher Teamzahl darf die Kopplung keine ELO aus dem Nichts
  # erzeugen: die Verschiebung wird so verteilt, dass die Summe konstant
  # bleibt.
  elos_a <- c(1000, 1000, 1000, 1000)   # 4 Teams
  elos_b <- c(900, 900)                  # 2 Teams
  total_before <- sum(elos_a) + sum(elos_b)

  result <- apply_relegation_coupling(elos_a, elos_b, delta = 60)

  expect_equal(sum(result$league_a) + sum(result$league_b), total_before)
  # Die kleinere Liga bewegt sich staerker je Team.
  expect_gt(abs(result$league_b[1] - elos_b[1]),
            abs(result$league_a[1] - elos_a[1]))
})

test_that("apply_relegation_coupling mit delta 0 aendert nichts", {
  elos_a <- c(1000, 1100)
  elos_b <- c(900, 950)

  result <- apply_relegation_coupling(elos_a, elos_b, delta = 0)

  expect_equal(result$league_a, elos_a)
  expect_equal(result$league_b, elos_b)
})

test_that("apply_relegation_coupling akzeptiert nur einen share in [0, 1]", {
  expect_error(
    apply_relegation_coupling(c(1000), c(900), delta = 10, share = 1.5),
    "share"
  )
})

# --- poisson_draw_ceiling ---------------------------------------------------

test_that("poisson_draw_ceiling reproduziert die Decke des heutigen Modells", {
  # Gleich starke Teams, kein Heimvorteil: lambda = tore_intercept je Seite.
  # Bei 1.32184 sind das 26.1 % Remis -- die obere Grenze, die das
  # unabhaengige Poisson-Modell ueberhaupt erzeugen kann.
  expect_equal(poisson_draw_ceiling(TORE_INTERCEPT), 0.261, tolerance = 0.001)
})

test_that("poisson_draw_ceiling faellt mit steigendem Torniveau", {
  # Mehr Tore -> weniger Remis. Bei Intercept 1.59 (gemessenes BL-Niveau)
  # liegt die Decke unter der beobachteten Remisquote von 25 %.
  expect_lt(poisson_draw_ceiling(1.59), poisson_draw_ceiling(1.32184))
  expect_lt(poisson_draw_ceiling(1.59), 0.25)
})

# --- check_spread -----------------------------------------------------------

test_that("check_spread meldet ein Ziel oberhalb der Poisson-Decke als unerreichbar", {
  # 30 % Remis liegt ueber der Decke von 26.1 % -- mit diesem Modell
  # grundsaetzlich nicht darstellbar, egal wie klein die Streuung ist.
  result <- check_spread(c(1000, 1100, 1200), observed_draw_rate = 0.30)

  expect_false(result$reachable)
  expect_gt(result$ceiling, 0.26)
})

test_that("check_spread haelt ein Ziel unterhalb der Decke fuer erreichbar", {
  result <- check_spread(c(1000, 1100, 1200), observed_draw_rate = 0.159)

  expect_true(result$reachable)
})

test_that("check_spread nennt die noetige SD fuer die Frauen-Bundesliga", {
  # Bei festem Intercept 1.32184 und HA 40 braucht eine Remisquote von
  # 15.9 % eine ELO-Streuung um 460 (gegen ~145 in der Bundesliga).
  result <- check_spread(c(1000, 1100, 1200), observed_draw_rate = 0.159)

  expect_gt(result$required_sd, 400)
  expect_lt(result$required_sd, 520)
})

test_that("check_spread gibt die tatsaechliche Streuung der Eingabe zurueck", {
  elos <- c(1000, 1200, 1400, 1600)

  result <- check_spread(elos, observed_draw_rate = 0.20)

  expect_equal(result$actual_sd, sd(elos))
})
