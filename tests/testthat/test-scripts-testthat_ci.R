# Testet scripts/ci/testthat_ci.R (Stufe 4.1, #212 Punkt 7): das CI-Skript
# listet alle Skip-Gruende und bricht bei RUST_SKIPS_VERBOTEN=1 ab, sobald
# ein Test sich trotz laufendem Rust-Server ueberspringt.

source_testthat_ci <- function() {
  source(file.path("..", "..", "scripts", "ci", "testthat_ci.R"), local = TRUE)
  environment()
}

test_that("rust_skips erkennt jede Rust-Meldung, aber keine Fixture- oder Mocking-Skips", {
  z <- source_testthat_ci()
  rust_texte <- c(
    "Rust-Server nicht erreichbar",
    "RUST_API_URL ist leer gesetzt",
    "Rust binary not found in any of: a, b; run `cargo build --release` in league-simulator-rust/",
    "Rust server failed to come up on port 18080; log: /tmp/rust.log"
  )
  andere_texte <- c(
    "Fixture fehlt: x",
    "Mocking issues with nested function calls",
    "ShinyApp/data/Ergebnis.Rds fehlt (gitignored, nur lokal)"
  )
  expect_identical(z$rust_skips(c(rust_texte, andere_texte)), rust_texte)
})

test_that("skip_meldungen liest die Skip-Gruende aus einem echten testthat-Ergebnis", {
  z <- source_testthat_ci()
  res <- testthat::test_file(test_path("fixtures", "ci-skips", "skips-beispiel.R"), reporter = "silent")
  df <- z$skip_meldungen(res)
  expect_identical(df$test, c("phantom Rust-Check", "phantom Fixture-Check"))
  expect_identical(df$meldung, c("Reason: Rust-Server nicht erreichbar", "Reason: Fixture fehlt: x"))
})

test_that("skip_meldungen liefert ohne Skips null Zeilen", {
  z <- source_testthat_ci()
  res <- testthat::test_file(test_path("fixtures", "ci-skips", "keine-skips-beispiel.R"), reporter = "silent")
  df <- z$skip_meldungen(res)
  expect_identical(nrow(df), 0L)
})

test_that("zusammenfassung zaehlt Fehlschlaege, Warnungen, Skips und Erwartungen", {
  z <- source_testthat_ci()
  df <- data.frame(
    failed = c(0L, 2L, 0L),
    warning = c(0L, 1L, 1L),
    skipped = c(1L, 0L, 0L),
    nb = c(3L, 5L, 2L)
  )
  expect_identical(z$zusammenfassung(df), "FAIL=1 WARN=2 SKIP=1 PASS=10")
})

test_that("das Skript startet beim Laden keine Testsuite", {
  ziel <- withr::local_tempfile(fileext = ".txt")
  withr::local_envvar(TESTTHAT_SUMMARY = ziel)
  vor <- Sys.time()
  z <- source_testthat_ci()
  nach <- Sys.time()
  expect_true(is.function(z$main))
  expect_lt(as.numeric(nach - vor, units = "secs"), 5)
  expect_false(file.exists(ziel))
})
