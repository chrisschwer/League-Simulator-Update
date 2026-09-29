# Test suite for input_handler.R -- get_user_input(), can_accept_input()
# and confirm_action() are the three functions with live callers
# (interactive_prompts.R, season_validation.R). get_numeric_input() and
# get_choice_input() had none and were removed in the same PR that adds
# this file (Stufe 4.5, #212); interactive_prompts.R stubbed these three
# functions but never exercised their own logic before.

library(testthat)
library(mockery)

source("../../RCode/input_handler.R")

context("input_handler")

test_that("get_user_input liefert im expliziten Non-interactive-Modus den Default", {
  withr::local_options(season_transition.non_interactive = TRUE)

  ausgabe <- capture.output(ergebnis <- get_user_input("x? ", default = 7))

  expect_equal(ergebnis, "7")
  expect_match(paste(ausgabe, collapse = "\n"), "Using default")
})

test_that("get_user_input bricht im Non-interactive-Modus ohne Default ab", {
  withr::local_options(season_transition.non_interactive = TRUE)

  expect_error(get_user_input("x? "), "requires default")
})

test_that("get_user_input nimmt ohne Terminal den Default", {
  stub(get_user_input, "interactive", FALSE)
  stub(get_user_input, "isatty", FALSE)

  ausgabe <- capture.output(ergebnis <- get_user_input("x? ", default = 7))

  expect_equal(ergebnis, "7")
  expect_match(paste(ausgabe, collapse = "\n"), "No terminal")
})

test_that("get_user_input bricht ohne Terminal und ohne Default ab", {
  stub(get_user_input, "interactive", FALSE)
  stub(get_user_input, "isatty", FALSE)

  expect_error(get_user_input("x? "), "non-TTY")
})

test_that("get_user_input liest mit Terminal eine Zeile per scan", {
  stub(get_user_input, "interactive", FALSE)
  stub(get_user_input, "isatty", TRUE)
  stub(get_user_input, "scan", "abc")
  expect_equal(get_user_input("x? "), "abc")

  stub(get_user_input, "interactive", FALSE)
  stub(get_user_input, "isatty", TRUE)
  stub(get_user_input, "scan", character(0))
  expect_equal(get_user_input("x? ", default = 7), "7")

  stub(get_user_input, "interactive", FALSE)
  stub(get_user_input, "isatty", TRUE)
  stub(get_user_input, "scan", character(0))
  expect_equal(get_user_input("x? "), "")
})

test_that("can_accept_input: Option schlaegt Terminal, sonst folgt sie interactive()/isatty()", {
  stub(can_accept_input, "interactive", TRUE)
  withr::with_options(list(season_transition.non_interactive = TRUE), {
    expect_false(can_accept_input())
  })

  stub(can_accept_input, "interactive", TRUE)
  expect_true(can_accept_input())

  stub(can_accept_input, "interactive", FALSE)
  stub(can_accept_input, "isatty", FALSE)
  expect_false(can_accept_input())
})

test_that("confirm_action normalisiert Ja-Antworten", {
  for (antwort in c(" YES ", "y", "1", "true")) {
    stub(confirm_action, "get_user_input", function(...) antwort)
    expect_true(confirm_action("ok? "), label = antwort)
  }

  for (antwort in c("n", "nein")) {
    stub(confirm_action, "get_user_input", function(...) antwort)
    expect_false(confirm_action("ok? "), label = antwort)
  }

  stub(confirm_action, "get_user_input", function(...) "")
  expect_true(confirm_action("ok? ", default = "y"))

  stub(confirm_action, "get_user_input", function(...) "")
  expect_false(confirm_action("ok? ", default = "n"))
})
