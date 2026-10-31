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

test_that("ein Verzicht bei abweichender League-Spalte wird gemeldet statt verworfen", {
  sp <- berechtigung_spielplan(c("CCC", "AAA", "BBB"))
  tl <- berechtigung_teamlist(Aufstiegsverzicht = c("", "", "", ""))
  tl$Aufstiegsverzicht[tl$ShortText == "CCC"] <- "ja"
  tl$League[tl$ShortText == "CCC"] <- 81   # Tippfehler in der League-Spalte

  expect_warning(
    erg <- berechtigung_aus_teamlist(sp, tl, 80, mit_sperre = FALSE),
    "Aufstiegsverzicht ignoriert: CCC"
  )
  expect_identical(erg, c(TRUE, TRUE, TRUE))
})

test_that("ohne abweichende League-Spalte gibt es keine Warnung", {
  sp <- berechtigung_spielplan(c("CCC", "AAA", "BBB"))
  tl <- berechtigung_teamlist(Aufstiegsverzicht = c("", "", "", ""))
  tl$Aufstiegsverzicht[tl$ShortText == "CCC"] <- "ja"
  expect_no_warning(berechtigung_aus_teamlist(sp, tl, 80, mit_sperre = FALSE))
})

test_that("ein Tippfehler bei einem Verein einer ANDEREN Liga legt diese Liga nicht lahm", {
  sp <- berechtigung_spielplan(c("CCC", "AAA", "BBB"))
  tl <- berechtigung_teamlist(Aufstiegsverzicht = c("", "", "", "vielleicht"))
  expect_no_warning(
    erg <- berechtigung_aus_teamlist(sp, tl, 80, mit_sperre = FALSE)
  )
  expect_identical(erg, c(TRUE, TRUE, TRUE))
  # In seiner eigenen Liga bleibt der Tippfehler ein Fehler.
  sp81 <- berechtigung_spielplan(c("FOO", "ZZZ"))
  expect_error(berechtigung_aus_teamlist(sp81, tl, 81, mit_sperre = FALSE),
               "unlesbarer Wert")
})

test_that("gleiches Kuerzel in zwei Ligen: der Verzicht der anderen Liga warnt nicht", {
  sp <- berechtigung_spielplan(c("CCC", "AAA", "BBB"))
  tl <- berechtigung_teamlist(Aufstiegsverzicht = c("", "", "", ""))
  fremd <- tl[tl$ShortText == "CCC", ]
  fremd$League <- 85
  fremd$Aufstiegsverzicht <- "ja"
  tl <- rbind(tl, fremd)
  expect_no_warning(
    erg <- berechtigung_aus_teamlist(sp, tl, 80, mit_sperre = FALSE)
  )
  expect_identical(erg, c(TRUE, TRUE, TRUE))
})

test_that("eine leere League-Zelle bei gesetztem Verzicht bricht nichts ab", {
  sp <- berechtigung_spielplan(c("CCC", "AAA", "BBB"))
  tl <- berechtigung_teamlist(Aufstiegsverzicht = c("", "", "", ""))
  tl$Aufstiegsverzicht[tl$ShortText == "CCC"] <- "ja"
  tl$League[tl$ShortText == "CCC"] <- NA   # Verein des Spielplans, League leer
  expect_no_error(
    erg <- berechtigung_aus_teamlist(sp, tl, 80, mit_sperre = FALSE)
  )
  expect_identical(erg, c(TRUE, TRUE, TRUE))
})
