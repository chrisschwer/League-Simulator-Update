library(testthat)

# relegation_2bl.R: Bundesliga 16. gegen 2. Bundesliga 3. und 2. Bundesliga 16.
# gegen den berechtigten Dritten der 3. Liga.
#
# Alle Tests rechnen OHNE Rust-Server: Die Tor-Raten kommen aus einer
# Attrappe, die dieselbe lineare Formel wie der Server benutzt (Herren-
# Tormodell, Heimvorteil 40). Die Formel steht hier nur, damit die
# Kombinatorik gegen bekannte Raten laeuft; im Betrieb holt
# zweikampf_paarungen_rust() sie vom Server (ADR 0002).

rel_module <- function() {
  source_module("league_registry", "aufstiegsspiele", "relegation_2bl")
}

# Tor-Raten wie /match-preview, aufgebaut wie zweikampf_paarungen_rust():
# erstgenannte Seite (elo_a) hat das Hinspiel zu Hause.
rel_paarungen_attrappe <- function(elo_a, elo_b, tore_slope = NULL,
                                   tore_intercept = NULL) {
  slope <- 0.0017854953143549
  achse <- 1.32183908045977
  ha <- 40
  lam <- function(delta) max(0.001, delta * slope + achse)
  zeilen <- list()
  for (a in names(elo_a)) {
    for (b in names(elo_b)) {
      hin_a <- lam(elo_a[[a]] + ha - elo_b[[b]])
      hin_b <- lam(elo_b[[b]] - ha - elo_a[[a]])
      rueck_b <- lam(elo_b[[b]] + ha - elo_a[[a]])
      rueck_a <- lam(elo_a[[a]] - ha - elo_b[[b]])
      zeilen[[length(zeilen) + 1L]] <- data.frame(
        a = a, b = b,
        hin_a = hin_a, hin_b = hin_b,
        rueck_a = rueck_a, rueck_b = rueck_b,
        neutral_a = (hin_a + rueck_a) / 2, neutral_b = (hin_b + rueck_b) / 2,
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, zeilen)
}

# Gleichverteilte Prognosematrix n x n mit Teamnamen <praefix>1..n.
rel_prognose <- function(praefix, n) {
  namen <- paste0(praefix, seq_len(n))
  matrix(1 / n, nrow = n, ncol = n,
         dimnames = list(namen, as.character(seq_len(n))))
}

rel_elo <- function(praefix, n, mitte = 1500, spanne = 300) {
  stats::setNames(seq(mitte + spanne, mitte - spanne, length.out = n),
                  paste0(praefix, seq_len(n)))
}

test_that("relegation_plaetze liest die Plaetze aus der Registry", {
  env <- rel_module()
  plaetze <- fn(env, "relegation_plaetze")

  bl <- plaetze("bundesliga", 18L)
  expect_identical(bl$relegation_runter, 16L)
  expect_identical(bl$abstieg, 17:18)

  zweite <- plaetze("zweite_bundesliga", 18L)
  expect_identical(zweite$aufstieg, 1:2)
  expect_identical(zweite$relegation_hoch, 3L)
  expect_identical(zweite$relegation_runter, 16L)
  expect_identical(zweite$abstieg, 17:18)

  # Die 3. Liga hat unten keine Relegation: Ihre vier Absteiger gehen direkt
  # in die Regionalligen.
  dritte <- plaetze("dritte_liga", 20L)
  expect_identical(dritte$aufstieg, 1:2)
  expect_identical(dritte$relegation_hoch, 3L)
  expect_true(is.na(dritte$relegation_runter))
  expect_identical(dritte$abstieg, 17:20)
})

test_that("relegation_duell: bei gleicher ELO entscheidet nur das Heimrecht der Verlaengerung", {
  env <- rel_module()
  duell <- fn(env, "relegation_duell")
  p_ab <- c(O1 = 1)
  p_auf <- c(U1 = 1)
  elo_ab <- c(O1 = 1500)
  elo_auf <- c(U1 = 1500)

  # Hinspiel bei der Aufstiegsseite -> der Rueckspiel-Gastgeber (und damit der
  # Gastgeber der Verlaengerung) ist die Abstiegsseite.
  auf_hin <- duell(p_ab, p_auf, elo_ab, elo_auf, hinspiel_bei = "aufstiegsseite",
                   paarungen_fn = rel_paarungen_attrappe)
  expect_lt(auf_hin$p_aufstieg_sieg[["U1"]], 0.5)

  # Umgekehrt: Hinspiel bei der Abstiegsseite -> die Aufstiegsseite hat die
  # Verlaengerung zu Hause.
  ab_hin <- duell(p_ab, p_auf, elo_ab, elo_auf, hinspiel_bei = "abstiegsseite",
                  paarungen_fn = rel_paarungen_attrappe)
  expect_gt(ab_hin$p_aufstieg_sieg[["U1"]], 0.5)

  # Das Duell ist spiegelsymmetrisch: Dieselbe Reihenfolge mit vertauschten
  # Rollen ergibt dieselbe Zahl.
  expect_equal(auf_hin$p_aufstieg_sieg[["U1"]],
               1 - ab_hin$p_aufstieg_sieg[["U1"]], tolerance = 1e-12)
})

test_that("relegation_duell: Sieg der einen Seite ist Niederlage der anderen", {
  env <- rel_module()
  duell <- fn(env, "relegation_duell")

  d <- duell(c(O1 = 1), c(U1 = 1), c(O1 = 1560), c(U1 = 1480),
             hinspiel_bei = "aufstiegsseite",
             paarungen_fn = rel_paarungen_attrappe)
  # Gewinnt die untere Seite, verliert die obere: dieselbe Wahrscheinlichkeit.
  expect_equal(d$p_aufstieg_sieg[["U1"]], d$p_abstieg_niederlage[["O1"]],
               tolerance = 1e-12)
  # Der Staerkere (die obere Liga) setzt sich eher durch.
  expect_lt(d$p_aufstieg_sieg[["U1"]], 0.5)
})

test_that("relegation_duell: erwartete Zahl der Wechsler ist auf beiden Seiten gleich", {
  # Jedes Duell hat genau einen Gewinner: Die Summe von P(Platz) * P(Sieg)
  # ueber die untere Liga ist die Zahl der Aufsteiger, die Summe von
  # P(Platz) * P(Niederlage) ueber die obere Liga die der Absteiger.
  env <- rel_module()
  duell <- fn(env, "relegation_duell")

  p_ab <- c(O1 = 0.5, O2 = 0.3, O3 = 0.2, O4 = 0)
  p_auf <- c(U1 = 0.1, U2 = 0.6, U3 = 0.3)
  elo_ab <- c(O1 = 1600, O2 = 1500, O3 = 1450, O4 = 1300)
  elo_auf <- c(U1 = 1550, U2 = 1480, U3 = 1400)

  for (seite in c("aufstiegsseite", "abstiegsseite")) {
    d <- duell(p_ab, p_auf, elo_ab, elo_auf, hinspiel_bei = seite,
               paarungen_fn = rel_paarungen_attrappe)
    aufsteiger <- sum(p_auf * d$p_aufstieg_sieg[names(p_auf)])
    absteiger <- sum(p_ab * d$p_abstieg_niederlage[names(p_ab)])
    expect_equal(aufsteiger, absteiger, tolerance = 1e-12, info = seite)
  }
})

test_that("relegation_duell: Teams ohne Masse bekommen 0 und brauchen keine ELO", {
  env <- rel_module()
  duell <- fn(env, "relegation_duell")

  d <- duell(c(O1 = 1, O2 = 0), c(U1 = 1, U2 = 0),
             c(O1 = 1500), c(U1 = 1500),
             paarungen_fn = rel_paarungen_attrappe)
  expect_identical(d$p_aufstieg_sieg[["U2"]], 0)
  expect_identical(d$p_abstieg_niederlage[["O2"]], 0)
  expect_identical(names(d$p_aufstieg_sieg), c("U1", "U2"))
})

test_that("relegation_duell bricht ab, wenn ein antretendes Team keine ELO hat", {
  env <- rel_module()
  duell <- fn(env, "relegation_duell")

  expect_error(
    duell(c(O1 = 0.5, O2 = 0.5), c(U1 = 1), c(O1 = 1500), c(U1 = 1500),
          paarungen_fn = rel_paarungen_attrappe),
    "O2"
  )
  expect_error(
    duell(c(1), c(U1 = 1), c(O1 = 1500), c(U1 = 1500),
          paarungen_fn = rel_paarungen_attrappe),
    "Teamnamen"
  )
})

test_that("relegation_spalten: Aufstieg gesamt und Abstieg gesamt schliessen sich zu Duellen", {
  env <- rel_module()
  spalten <- fn(env, "relegation_spalten")

  prognosen <- list(
    bundesliga = rel_prognose("B", 18L),
    zweite_bundesliga = rel_prognose("Z", 18L),
    dritte_liga = rel_prognose("D", 20L)
  )
  elos <- list(
    bundesliga = rel_elo("B", 18L, 1650),
    zweite_bundesliga = rel_elo("Z", 18L, 1500),
    dritte_liga = rel_elo("D", 20L, 1380)
  )
  s <- spalten(prognosen, elos, paarungen_fn = rel_paarungen_attrappe)

  expect_named(s, c("bundesliga", "zweite_bundesliga", "dritte_liga"),
               ignore.order = TRUE)
  expect_identical(colnames(s$bundesliga), "Abstieg gesamt")
  expect_identical(colnames(s$zweite_bundesliga),
                   c("Aufstieg gesamt", "Abstieg gesamt"))
  expect_identical(colnames(s$dritte_liga), "Aufstieg gesamt")
  expect_identical(rownames(s$bundesliga), rownames(prognosen$bundesliga))

  # Gleichverteilte Prognose: Jedes Team steht mit 1/n auf jedem Platz.
  # Abstieg gesamt = 2/18 (Platz 17-18) + 1/18 * P(Niederlage).
  expect_true(all(s$bundesliga[["Abstieg gesamt"]] >= 2 / 18))
  expect_true(all(s$bundesliga[["Abstieg gesamt"]] <= 3 / 18))

  # Bundesliga 16. gegen 2. BL 3.: Was die Bundesliga verliert, gewinnt die
  # 2. BL. Beide Summen sind 2 (direkt) plus die Zahl der Relegationswechsler.
  wechsel_bl <- sum(s$bundesliga[["Abstieg gesamt"]]) - 2
  wechsel_2bl <- sum(s$zweite_bundesliga[["Aufstieg gesamt"]]) - 2
  expect_equal(wechsel_bl, wechsel_2bl, tolerance = 1e-12)
  expect_gt(wechsel_bl, 0)
  expect_lt(wechsel_bl, 1)

  # 2. BL 16. gegen 3. Liga 3.: dasselbe eine Ebene tiefer.
  wechsel_ab <- sum(s$zweite_bundesliga[["Abstieg gesamt"]]) - 2
  wechsel_auf <- sum(s$dritte_liga[["Aufstieg gesamt"]]) - 2
  expect_equal(wechsel_ab, wechsel_auf, tolerance = 1e-12)

  # Der Staerkere gewinnt eher: Die Bundesliga ist hier klar staerker, also
  # steigen im Schnitt weniger als eine halbe Mannschaft ab.
  expect_lt(wechsel_bl, 0.5)
})

test_that("relegation_spalten laesst eine Liga weg, wenn ihre Eingaben fehlen", {
  env <- rel_module()
  spalten <- fn(env, "relegation_spalten")

  prognosen <- list(
    bundesliga = rel_prognose("B", 18L),
    zweite_bundesliga = rel_prognose("Z", 18L)
  )
  elos <- list(
    bundesliga = rel_elo("B", 18L, 1650),
    zweite_bundesliga = rel_elo("Z", 18L, 1500)
  )
  s <- spalten(prognosen, elos, paarungen_fn = rel_paarungen_attrappe)

  # Ohne 3. Liga entfaellt das untere Duell -- und mit ihm "Abstieg gesamt"
  # der 2. BL sowie die ganze Spalte der 3. Liga. Das obere Duell bleibt.
  expect_named(s, c("bundesliga", "zweite_bundesliga"), ignore.order = TRUE)
  expect_identical(colnames(s$zweite_bundesliga), "Aufstieg gesamt")

  expect_length(spalten(list(), list(), paarungen_fn = rel_paarungen_attrappe), 0L)
})
