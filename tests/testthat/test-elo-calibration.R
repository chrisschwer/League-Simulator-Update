# Unit tests fuer die Offline-ELO-Kalibrierung (Phase 4 Ligen-Ausbau).
#
# Die Kalibrierung erzeugt Start-ELOs fuer Ligen ohne Historie. Sie baut den
# ELO-Walk NICHT in R nach (ADR 0002), sondern laesst ihn von Rust rechnen;
# die hier getesteten Funktionen sind die reinen Rechenschritte davor und
# danach: Ankerung, Relegationskopplung und die Streuungspruefung.

library(testthat)

source("../../RCode/api_service.R")   # get_team_short_name
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

# --- build_walk_payload -----------------------------------------------------

test_that("build_walk_payload nutzt 1-basierte Team-Indizes", {
  matches <- data.frame(
    teams_home_id = c(10, 20),
    teams_away_id = c(20, 10),
    goals_home = c(2, 0),
    goals_away = c(1, 0)
  )
  teams <- data.frame(TeamID = c(10, 20), ShortText = c("AAA", "BBB"),
                      InitialELO = c(1500, 1500))

  p <- build_walk_payload(matches, teams)

  expect_equal(p$schedule[[1]][[1]], 1)
  expect_equal(p$schedule[[1]][[2]], 2)
  expect_equal(p$schedule[[2]][[1]], 2)
  expect_equal(p$elo_values, c(1500, 1500))
  expect_equal(p$team_names, c("AAA", "BBB"))
})

test_that("build_walk_payload sendet home_advantage nicht mit", {
  # ADR 0002: Die Modellkonstante lebt ausschliesslich im Rust-Server.
  # Die Kalibrierung muss auf derselben Physik ruhen wie jede Prognose.
  matches <- data.frame(teams_home_id = 10, teams_away_id = 20,
                        goals_home = 1, goals_away = 0)
  teams <- data.frame(TeamID = c(10, 20), ShortText = c("AAA", "BBB"),
                      InitialELO = c(1500, 1500))

  p <- build_walk_payload(matches, teams)

  expect_null(p$home_advantage)
})

test_that("build_walk_payload verwirft Spiele mit unbekannten Teams", {
  matches <- data.frame(
    teams_home_id = c(10, 99),   # 99 ist nicht in teams
    teams_away_id = c(20, 10),
    goals_home = c(2, 1),
    goals_away = c(1, 0)
  )
  teams <- data.frame(TeamID = c(10, 20), ShortText = c("AAA", "BBB"),
                      InitialELO = c(1500, 1500))

  p <- build_walk_payload(matches, teams)

  expect_equal(length(p$schedule), 1)
})

test_that("build_walk_payload bricht ab, wenn kein Spiel uebrig bleibt", {
  # Eine leere Liga wuerde klaglos simuliert -- genau der Fehler, den der
  # Rundenfilter der Regionalligen sonst erzeugt haette.
  matches <- data.frame(teams_home_id = 99, teams_away_id = 98,
                        goals_home = 1, goals_away = 0)
  teams <- data.frame(TeamID = c(10, 20), ShortText = c("AAA", "BBB"),
                      InitialELO = c(1500, 1500))

  expect_error(build_walk_payload(matches, teams), "kein")
})

# --- teams_from_matches -----------------------------------------------------

test_that("teams_from_matches sammelt alle Teams einer Spielmenge", {
  matches <- data.frame(
    teams_home_id = c(10, 20, 30),
    teams_away_id = c(20, 30, 10)
  )

  t <- teams_from_matches(matches, start_elo = 920)

  expect_equal(sort(t$TeamID), c(10, 20, 30))
  expect_true(all(t$InitialELO == 920))
})

test_that("teams_from_matches uebernimmt bekannte ELOs und fuellt den Rest", {
  # Absteiger tragen ihren bekannten Wert mit; nur wer keine Historie hat,
  # startet auf dem Familien-Mittelwert.
  matches <- data.frame(teams_home_id = c(10, 20), teams_away_id = c(20, 30))
  known <- c("10" = 1150)

  t <- teams_from_matches(matches, start_elo = 920, known_elos = known)

  expect_equal(t$InitialELO[t$TeamID == 10], 1150)
  expect_equal(t$InitialELO[t$TeamID == 20], 920)
})

# --- find_league_movers -----------------------------------------------------

test_that("find_league_movers erkennt Auf- und Absteiger", {
  # Vorsaison: oben 1,2,3 / unten 4,5,6. Danach ist 4 oben, 3 unten.
  m <- find_league_movers(
    lower_ids_prev = c(4, 5, 6), upper_ids_prev = c(1, 2, 3),
    lower_ids_now  = c(3, 5, 6), upper_ids_now  = c(1, 2, 4)
  )

  expect_equal(m$promoted, 4)
  expect_equal(m$relegated, 3)
})

test_that("find_league_movers meldet nichts, wenn sich nichts bewegt", {
  m <- find_league_movers(c(4, 5), c(1, 2), c(4, 5), c(1, 2))

  expect_length(m$promoted, 0)
  expect_length(m$relegated, 0)
})

test_that("find_league_movers ignoriert Teams, die ganz verschwinden", {
  # Team 6 taucht danach nirgends auf -- kein Auf- oder Abstieg.
  m <- find_league_movers(
    lower_ids_prev = c(4, 5, 6), upper_ids_prev = c(1, 2),
    lower_ids_now  = c(4, 5),    upper_ids_now  = c(1, 2)
  )

  expect_length(m$promoted, 0)
  expect_length(m$relegated, 0)
})

# --- LEAGUE_FAMILIES --------------------------------------------------------

test_that("Ligafamilien trennen Herren und Frauen vollstaendig", {
  # Eine Familie ist eine Wechselgemeinschaft. Herren und Frauen tauschen
  # keine Teams aus -- nur deshalb duerfen sie eine eigene Skala haben.
  expect_length(intersect(LEAGUE_FAMILIES$herren, LEAGUE_FAMILIES$frauen), 0)
  expect_true(all(REGIONALLIGEN %in% LEAGUE_FAMILIES$herren))
  expect_true("80" %in% LEAGUE_FAMILIES$herren)
})

# --- assign_short_names -----------------------------------------------------
# ShortText wird in transform_data() zum Spaltennamen des Simulations-
# Data-Frames. Doppelte Kuerzel erzeugen doppelte Spalten und damit
# stillschweigend vertauschte Teams -- diese Tests sind das Schutznetz.

test_that("assign_short_names vergibt durchweg eindeutige Kuerzel", {
  df <- data.frame(
    TeamID = 1:5,
    Name = c("FC Bayern Muenchen", "FC Bayern Muenchen II",
             "Bayer Leverkusen", "Bayreuth", "Bayern Hof"),
    stringsAsFactors = FALSE
  )

  r <- assign_short_names(df)

  expect_equal(length(unique(r$ShortText)), 5)
  expect_equal(nrow(r), 5)
})

test_that("assign_short_names kollidiert nicht mit reservierten Kuerzeln", {
  df <- data.frame(TeamID = 1, Name = "FC Bayern Muenchen",
                   stringsAsFactors = FALSE)

  r <- assign_short_names(df, reserved = c("FCB", "FCB2", "FCB3"))

  expect_false(r$ShortText %in% c("FCB", "FCB2", "FCB3"))
})

test_that("assign_short_names markiert Zweitvertretungen mit -50", {
  df <- data.frame(
    TeamID = 1:2,
    Name = c("Borussia Dortmund II", "Borussia Dortmund"),
    stringsAsFactors = FALSE
  )

  r <- assign_short_names(df)

  expect_equal(r$Promotion[1], -50)
  expect_equal(r$Promotion[2], 0)
})

test_that("assign_short_names haelt auch bei vielen aehnlichen Namen durch", {
  # 30 Vereine, die alle mit denselben drei Buchstaben beginnen.
  df <- data.frame(
    TeamID = 1:30,
    Name = paste("SV Musterstadt", 1:30),
    stringsAsFactors = FALSE
  )

  r <- assign_short_names(df)

  expect_equal(length(unique(r$ShortText)), 30)
})
