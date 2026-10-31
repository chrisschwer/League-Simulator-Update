library(testthat)
source("../../RCode/transform_data.R")

# berechtigung_aus_teamlist(): die Maske der Aufstiegsberechtigten in
# Spielplan-Reihenfolge (ADR 0009). Zwei Quellen der Nichtberechtigung: die
# Zweitvertretungs-Sperre (Promotion < 0) und der Aufstiegsverzicht (Spalte
# Aufstiegsverzicht, nur diese Saison).

berechtigung_spielplan <- function(teams) {
  df <- data.frame(TeamHeim = teams[1], TeamGast = teams[2], ToreHeim = 1L, ToreGast = 0L)
  for (t in teams) df[[t]] <- 1500
  df
}

berechtigung_teamlist <- function(...) {
  data.frame(
    ShortText = c("AAA", "BBB", "CCC", "FOO"),
    League = c(80, 80, 80, 81),
    Promotion = c(0, -50, 0, 0),
    stringsAsFactors = FALSE,
    ...
  )
}

test_that("Zweitvertretungen mit Promotion < 0 sind nicht berechtigt", {
  sp <- berechtigung_spielplan(c("CCC", "AAA", "BBB"))
  expect_identical(berechtigung_aus_teamlist(sp, berechtigung_teamlist(), 80),
                   c(TRUE, TRUE, FALSE))
})

test_that("ohne Sperre (Regionalligen) zaehlt Promotion nicht", {
  sp <- berechtigung_spielplan(c("CCC", "AAA", "BBB"))
  expect_identical(
    berechtigung_aus_teamlist(sp, berechtigung_teamlist(), 80, mit_sperre = FALSE),
    c(TRUE, TRUE, TRUE)
  )
})

test_that("Aufstiegsverzicht sperrt, in 1/ja/TRUE-Schreibweise; leer und NA nicht", {
  sp <- berechtigung_spielplan(c("AAA", "BBB", "CCC"))
  tl <- berechtigung_teamlist(Aufstiegsverzicht = c("ja", "", "1", "0"))
  expect_identical(
    berechtigung_aus_teamlist(sp, tl, 80, mit_sperre = FALSE),
    c(FALSE, TRUE, FALSE)
  )
  tl$Aufstiegsverzicht <- c(NA, NA, NA, NA)
  expect_identical(
    berechtigung_aus_teamlist(sp, tl, 80, mit_sperre = FALSE),
    c(TRUE, TRUE, TRUE)
  )
})

test_that("ein unlesbarer Verzichtswert bricht ab statt als 'kein Verzicht' durchzugehen", {
  sp <- berechtigung_spielplan(c("AAA", "BBB"))
  tl <- berechtigung_teamlist(Aufstiegsverzicht = c("vielleicht", "", "", ""))
  expect_error(berechtigung_aus_teamlist(sp, tl, 80), "unlesbarer Wert 'vielleicht'")
})

test_that("gefiltert wird auf die Liga: Kurznamen sind nur dort eindeutig", {
  sp <- berechtigung_spielplan(c("FOO", "AAA"))
  tl <- berechtigung_teamlist(Aufstiegsverzicht = c("", "", "", "ja"))
  # FOO verzichtet in Liga 81; in Liga 80 gibt es kein FOO -> berechtigt.
  expect_identical(berechtigung_aus_teamlist(sp, tl, 80), c(TRUE, TRUE))
  expect_identical(berechtigung_aus_teamlist(sp, tl, 81), c(FALSE, TRUE))
})

test_that("fehlt die Spalte Aufstiegsverzicht, verzichtet niemand", {
  sp <- berechtigung_spielplan(c("AAA", "CCC"))
  expect_identical(berechtigung_aus_teamlist(sp, berechtigung_teamlist(), 80), c(TRUE, TRUE))
})
