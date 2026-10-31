library(testthat)

# Aufstiegsverzicht (#320) auf den Seiten: Die Aufstiegsseite schreibt
# "verzichtet" statt 0 %, und das obere Panel einer Direktstaffel liest die
# Aufstiegsspalte statt der Platzgruppe, sobald es sie gibt.

verzicht_aufstieg <- function() {
  d <- data.frame(Aufstieg = c(T1 = 0, T2 = 1))
  attr(d, "p_erster_berechtigter") <- c(T1 = 0, T2 = 1)
  attr(d, "verzichtet") <- "T1"
  d
}

verzicht_prognose <- function() {
  m <- matrix(0, nrow = 2, ncol = 2, dimnames = list(c("T1", "T2"), c("1", "2")))
  m[, 1] <- c(0.6, 0.4)
  m[, 2] <- c(0.4, 0.6)
  m
}

verzicht_env <- function(mit_aufstieg = TRUE) {
  env <- new.env()
  env$Ergebnis_rl_west <- verzicht_prognose()
  env$Ergebnis_rl_west_abstieg <- data.frame(Abstieg = c(T1 = 0.1, T2 = 0.2))
  if (mit_aufstieg) env$Ergebnis_rl_west_aufstieg <- verzicht_aufstieg()
  env
}

test_that("die Aufstiegsseite zeigt 'verzichtet' statt 0 %, die Meisterchance bleibt", {
  gen <- source_module("generate_static_site")
  out <- withr::local_tempdir()
  daten <- gen$.aufstiegsdaten("rl_west", verzicht_env())
  expect_identical(daten$West$verzichtet, "T1")
  expect_false(daten$West$playoff)

  html <- read_html(gen$.render_aufstiegsseite(gen$league_views()[["rl-aufstieg"]],
                                               daten, out))
  # Zeile T1: 60 % Meister, verzichtet; Zeile T2: 40 % Meister, 100 % Aufstieg.
  expect_true(grepl("verzichtet", html, fixed = TRUE))
  expect_true(grepl("<td>60</td><td>verzichtet</td>", html, fixed = TRUE))
})

test_that("ohne Verzicht bleibt die Aufstiegsseite einer Direktstaffel wie bisher", {
  gen <- source_module("generate_static_site")
  daten <- gen$.aufstiegsdaten("rl_west", verzicht_env(mit_aufstieg = FALSE))
  expect_identical(daten$West$verzichtet, character(0))
  expect_equal(unname(daten$West$aufstieg), unname(daten$West$meister))
})

test_that("das obere Panel einer Direktstaffel liest die Aufstiegsspalte, wenn es sie gibt", {
  gen <- source_module("generate_static_site")
  out <- withr::local_tempdir()
  view <- gen$league_views()$rl_west
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  mit <- read_html(gen$render_league_page(view, verzicht_env(), out, now = now))
  # T2 steigt sicher auf (erster Berechtigter; prozent() schreibt 100 % als
  # Haekchen), T1 ist nicht mehr dabei.
  expect_true(grepl("<td>✓</td>", mit, fixed = TRUE))

  ohne <- read_html(gen$render_league_page(view, verzicht_env(FALSE), out, now = now))
  # Ohne Objekt: Platzgruppe, P(Meister) = 60 / 40.
  expect_true(grepl("<td>60</td>", ohne, fixed = TRUE))
  expect_false(grepl("<td>✓</td>", ohne, fixed = TRUE))
})
