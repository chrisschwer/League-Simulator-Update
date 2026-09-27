# Fixture fuer test-scripts-testthat_ci.R: drei Bloecke, zwei davon skippen.
# Kein test-/test_-Praefix (.gitignore:56, test_dir()) -- wird nicht als
# eigene Testdatei eingesammelt, nur per test_file() gezielt geladen.

test_that("phantom Rust-Check", {
  skip("Rust-Server nicht erreichbar")
})

test_that("phantom Fixture-Check", {
  skip("Fixture fehlt: x")
})

test_that("phantom bestehender Test", {
  expect_true(TRUE)
})
