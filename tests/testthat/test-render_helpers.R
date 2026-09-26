# The rendering primitives moved out of ShinyApp/app.R into
# RCode/render_helpers.R so the static site generator can reuse them.
# These assertions pin the behaviour across the move.
# display_result() was removed once the static site generator stopped
# using ggplot2 (Phase 3); groupResultsDF/prozent are still in use.

source_render_helpers <- function() {
  source(test_path("..", "..", "RCode", "render_helpers.R"), local = TRUE)
  environment()
}

test_that("render_helpers.R defines its primitives", {
  env <- source_render_helpers()
  expect_true(is.function(env$prozent))
  expect_true(is.function(env$groupResultsDF))
})

test_that("prozent keeps its boundary behaviour after the move", {
  env <- source_render_helpers()
  expect_equal(env$prozent(0), 0)
  expect_equal(env$prozent(0.5), 50)
  expect_equal(env$prozent(1), intToUtf8(0x2713))
  expect_equal(env$prozent(0.995), ">99")
  expect_equal(env$prozent(0.001), "<1")
  expect_equal(env$prozent("text"), "text")
})

test_that("groupResultsDF sums column ranges and preserves rownames", {
  env <- source_render_helpers()
  m <- matrix(0.1, nrow = 2, ncol = 4,
              dimnames = list(c("AAA", "BBB"), NULL))
  out <- env$groupResultsDF(m, labels = c("first", "rest"),
                            groups = cbind(c(1, 1), c(2, 4)))
  expect_equal(colnames(out), c("first", "rest"))
  expect_equal(rownames(out), c("AAA", "BBB"))
  expect_equal(out$first, c(0.1, 0.1))
  expect_equal(out$rest, c(0.3, 0.3), tolerance = 1e-8)
})
