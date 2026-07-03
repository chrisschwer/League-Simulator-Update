helpers_path <- test_path("..", "..", "ShinyApp", "app_helpers.R")

test_that("load_results returns FALSE for missing or corrupt file", {
  source(helpers_path, local = TRUE)
  expect_false(load_results(file.path(tempdir(), "does_not_exist.Rds"), new.env()))
  corrupt <- tempfile(fileext = ".Rds")
  writeLines("not an rds", corrupt)
  expect_false(load_results(corrupt, new.env()))
})

test_that("load_results loads a valid results file", {
  source(helpers_path, local = TRUE)
  Ergebnis <- matrix(1 / 18, 18, 18)
  f <- tempfile(fileext = ".Rds")
  save(Ergebnis, file = f)
  env <- new.env()
  expect_true(load_results(f, env))
  expect_true(exists("Ergebnis", envir = env))
})

test_that("data_age_hours computes hours between mtime and now", {
  source(helpers_path, local = TRUE)
  now <- as.POSIXct("2026-07-02 18:00:00", tz = "Europe/Berlin")
  mtime <- as.POSIXct("2026-07-01 18:00:00", tz = "Europe/Berlin")
  expect_equal(data_age_hours(mtime, now), 24)
})

test_that("stale_warning_text triggers only past the threshold", {
  source(helpers_path, local = TRUE)
  expect_null(stale_warning_text(3, threshold_hours = 24))
  msg <- stale_warning_text(49.6, threshold_hours = 24)
  expect_match(msg, "50 Stunden")
})
