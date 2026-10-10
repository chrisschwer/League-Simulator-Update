# ELO-Verlauf (Issue #184): elo_verlauf_daten() formt aus dem league_entry die
# Daten der Verlaufsseite. Erwartungswerte aus verlauf_beispiel()
# (helper-elo-verlauf.R), dort von Hand nachgerechnet.

ev_daten <- function(...) {
  fn(source_module("elo_verlauf"), "elo_verlauf_daten")(verlauf_beispiel(...))
}
ev_verein <- function(daten, id) Filter(function(t) t$id == id, daten$teams)[[1]]
ev_punkt <- function(verein, n) Filter(function(p) p$n == n, verein$punkte)[[1]]

test_that("die Vereine stehen nach ELO heute, nicht nach Startwert", {
  d <- ev_daten()
  expect_identical(vapply(d$teams, function(t) t$id, numeric(1)), c(101, 104, 102, 103))
  expect_equal(vapply(d$teams, function(t) t$aktuell, numeric(1)), c(1570, 1492, 1488.5, 1399.5))
  expect_equal(vapply(d$teams, function(t) t$start, numeric(1)), c(1600, 1450, 1500, 1400))
  expect_identical(vapply(d$teams, function(t) t$kuerzel, ""), c("AAA", "DDD", "BBB", "CCC"))
  expect_identical(vapply(d$teams, function(t) t$name, ""), c("Team 101", "Team 104", "Team 102", "Team 103"))
})

test_that("der erste Punkt ist der Saisonstart, danach ein Punkt je ELO-wirksamem Spiel", {
  v <- ev_verein(ev_daten(), 101)
  expect_length(v$punkte, 3)
  expect_identical(v$punkte[[1]], list(n = 0L, nach = 1600))
  expect_identical(vapply(v$punkte, function(p) as.integer(p$n), integer(1)), 0:2)
})

test_that("Heim- und Gastsicht: Delta mit Vorzeichen, Siegchance des eigenen Vereins", {
  d <- ev_daten()
  heim <- ev_punkt(ev_verein(d, 104), 2)
  expect_true(heim$heim)
  expect_equal(c(heim$vor, heim$delta, heim$nach), c(1452, 40, 1492))
  expect_equal(c(heim$p_sieg, heim$p_remis), c(0.2, 0.3))
  expect_identical(c(heim$gegner, heim$gegner_name), c("AAA", "Team 101"))
  expect_equal(c(heim$tore_heim, heim$tore_gast), c(2, 0))

  gast <- ev_punkt(ev_verein(d, 101), 2)
  expect_false(gast$heim)
  expect_equal(c(gast$vor, gast$delta, gast$nach), c(1610, -40, 1570))
  expect_equal(c(gast$p_sieg, gast$p_remis), c(0.5, 0.3))
  expect_identical(c(gast$gegner, gast$gegner_name), c("DDD", "Team 104"))
  expect_identical(gast$runde, 2L)
  expect_false(gast$nachhol)
})

test_that("das Datum ist der Berliner Kalendertag des Anstosses", {
  p <- ev_punkt(ev_verein(ev_daten(), 101), 1)
  # Anstoss 2026-08-08 22:30 UTC = 2026-08-09 00:30 in Berlin
  expect_identical(p$datum, "2026-08-09")
  expect_identical(p$runde, 1L)
})

test_that("laufende Saison: die Achse reicht ein Spiel und sieben Tage weiter", {
  d <- ev_daten()
  expect_true(d$saison_laeuft)
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(d$achse_datum_ende, "2026-08-22")
})

test_that("abgeschlossene Saison: kein Ueberhang auf der Achse", {
  d <- ev_daten(laeuft = FALSE)
  expect_false(d$saison_laeuft)
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(d$achse_datum_ende, "2026-08-22")
  expect_equal(vapply(d$teams, function(t) t$aktuell, numeric(1)), c(1575, 1495, 1485.5, 1394.5))
})

test_that("ein abgesagtes Spiel haelt die Saison nicht offen", {
  d <- ev_daten(laeuft = FALSE, abgesagt = TRUE)
  expect_false(d$saison_laeuft)
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(d$achse_datum_ende, "2026-08-22")
  expect_length(ev_verein(d, 102)$punkte, 3)
})

test_that("ein verschobenes offenes Spiel: der Verein endet ein Spiel frueher, die Saison laeuft", {
  d <- ev_daten(verschoben = TRUE)
  expect_true(d$saison_laeuft)
  expect_length(ev_verein(d, 101)$punkte, 2)
  expect_length(ev_verein(d, 102)$punkte, 3)
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(d$achse_datum_ende, "2026-08-22")
  expect_equal(ev_verein(d, 101)$aktuell, 1610)
})

test_that("ein Nachholspiel steht chronologisch und ist markiert", {
  d <- ev_daten(nachhol = TRUE)
  v <- ev_verein(d, 101)
  expect_false(ev_punkt(v, 1)$nachhol)
  nach <- ev_punkt(v, 2)
  expect_true(nach$nachhol)
  expect_identical(nach$datum, "2026-08-26")
  expect_identical(nach$runde, 2L)
  expect_identical(d$achse_datum_ende, "2026-09-02")
})

test_that("ein am gruenen Tisch gewertetes Spiel erzeugt keinen Punkt", {
  d <- ev_daten(gewertet = TRUE)
  expect_length(ev_verein(d, 103)$punkte, 2)
  expect_length(ev_verein(d, 104)$punkte, 2)
  expect_equal(ev_verein(d, 103)$aktuell, 1401.5)
  expect_true(d$saison_laeuft)
})

test_that("vor dem ersten Spiel: nur Startpunkte, Achse ein Spiel, kein Datum", {
  d <- ev_daten(leer = TRUE)
  expect_true(all(vapply(d$teams, function(t) length(t$punkte), integer(1)) == 1L))
  expect_identical(d$achse_spiele_max, 1L)
  expect_identical(d$achse_datum_ende, NA_character_)
  expect_true(d$saison_laeuft)
})

test_that("die Saison heisst nach dem fruehesten Anstoss", {
  expect_identical(ev_daten()$saison, "2026/27")
  saison <- fn(source_module("elo_verlauf"), "elo_verlauf_saison")
  expect_identical(saison(as.POSIXct("2099-08-01 12:00:00", tz = "UTC")), "2099/00")
  expect_identical(saison(as.POSIXct(character(0), tz = "UTC")), "")
})

test_that("weicht der Verlauf von der Tabelle ab, bricht die Funktion mit Verein und Werten ab", {
  e <- verlauf_beispiel()
  e$tabelle$elo[e$tabelle$team_id == 104] <- 1500
  f <- fn(source_module("elo_verlauf"), "elo_verlauf_daten")
  expect_error(f(e), "ELO-Verlauf von Team 104 endet bei 1492.000, die Tabelle sagt 1500.000",
               fixed = TRUE)
})
