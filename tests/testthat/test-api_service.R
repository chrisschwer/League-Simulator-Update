# Test suite for get_team_short_name / short-name generation
#
# Regression: season transition 2025 -> 2026 aborted because the
# auto-generated short name for "Würzburger Kickers" was "WÜR" — the
# umlaut fails CSV ShortText validation (letters and digits only).

library(testthat)

source("../../RCode/api_service.R")

test_that("get_team_short_name transliterates German umlauts", {
  expect_equal(get_team_short_name("Würzburger Kickers"), "WUE")
  expect_equal(get_team_short_name("Grünberger SV"), "GRU")
})

test_that("get_team_short_name output is always alphanumeric ASCII", {
  names <- c(
    "Würzburger Kickers",
    "SG Sonnenhof Grossaspach",
    "Fortuna Köln",
    "Preußen Münster",
    "1. FC Köln",
    "Bayer 04 Leverkusen"
  )
  for (n in names) {
    expect_match(get_team_short_name(n), "^[A-Z0-9]+$", info = n)
  }
})

test_that("explicit mappings still win over generation", {
  expect_equal(get_team_short_name("FC Bayern München"), "FCB")
  expect_equal(get_team_short_name("1. FC Köln"), "FCK")
})
