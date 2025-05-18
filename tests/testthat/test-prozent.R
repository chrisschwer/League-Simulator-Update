library(testthat)
source("RCode/prozent.R")

test_that("prozent converts fractions to percentages", {
  expect_equal(prozent(0.5), 50)
  expect_equal(prozent(1), 100)
  expect_equal(prozent(0), 0)
})
