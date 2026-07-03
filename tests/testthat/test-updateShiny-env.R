# updateShiny must hard-fail with an actionable message when ShinyApps.io
# credentials are missing from the environment (no hardcoded fallbacks).

source_updateShiny <- function() {
  source(test_path("..", "..", "RCode", "updateShiny.R"), local = TRUE)
  environment()$updateShiny
}

test_that("updateShiny stops when SHINYAPPS_IO_TOKEN is not set", {
  updateShiny <- source_updateShiny()
  withr::local_envvar(c(SHINYAPPS_IO_TOKEN = "", SHINYAPPS_IO_SECRET = "dummy"))
  expect_error(
    updateShiny(NULL, NULL, NULL, directory = tempdir()),
    "SHINYAPPS_IO_TOKEN"
  )
})

test_that("updateShiny stops when SHINYAPPS_IO_SECRET is not set", {
  updateShiny <- source_updateShiny()
  withr::local_envvar(c(SHINYAPPS_IO_TOKEN = "dummy", SHINYAPPS_IO_SECRET = ""))
  expect_error(
    updateShiny(NULL, NULL, NULL, directory = tempdir()),
    "SHINYAPPS_IO_SECRET"
  )
})
