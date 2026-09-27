# Fixture fuer test-scripts-testthat_ci.R: ein Block ohne Skip -- Gegenstueck
# zu skips-beispiel.R fuer den Fall "keine Skips im Lauf".

test_that("phantom ohne Skip", {
  expect_true(TRUE)
})
