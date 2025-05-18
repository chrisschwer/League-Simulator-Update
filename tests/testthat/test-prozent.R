library(testthat)
source("RCode/prozent.R")

test_that("prozent converts fractions to percentages", {
  expect_equal(prozent(0.5), 50)
  expect_equal(prozent(1), 100)
  expect_equal(prozent(0), 0)
})

test_that("prozent handles edge cases", {
  expect_equal(prozent(0.00999), "<1")
  expect_equal(prozent(0.99001), ">99")
})

