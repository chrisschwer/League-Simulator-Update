# retrieveResults() meldet einen fehlgeschlagenen Abruf bisher nur per
# warning() (RCode/retrieveResults.R:61-63) -- ohne options(warn = 1) sammelt
# Rscript Warnungen bis zur Rueckkehr aus main() und verwirft sie beim
# regulaeren quit() der Produktions-Schleife (Issue #208, Punkt 2). Diese
# Tests pinnen, dass Statuscode UND Liga zusaetzlich ueber message() sofort
# sichtbar werden.
#
# Mocking: Die Datei wird per source() geladen, kein Paket -- ein
# Namespace-Mock (local_mocked_bindings) greift hier nicht, mockery::stub()
# schreibt den Aufruf innerhalb der Funktion um (Muster aus
# test-check-api-limits.R / test-update-loop-gating.R).

library(testthat)
library(mockery)

lade_retrieve_results <- function() {
  env <- new.env()
  Sys.setenv(RAPIDAPI_KEY = "test-key")
  source(test_path("..", "..", "RCode", "retrieveResults.R"), local = env)
  env
}

fake_response <- function(status) {
  structure(list(status_code = status), class = "response")
}

test_that("retrieveResults meldet Statuscode und Liga per message() bei HTTP-Fehler", {
  env <- lade_retrieve_results()
  f <- env$retrieveResults
  stub(f, "VERB", function(...) fake_response(500))
  stub(f, "status_code", function(response) response$status_code)

  msgs <- capture_messages(
    suppressWarnings(result <- f(league = "78", season = "2026"))
  )

  expect_null(result)
  expect_true(any(grepl("500", msgs, fixed = TRUE)))
  expect_true(any(grepl("78", msgs, fixed = TRUE)))
})

test_that("retrieveResults meldet die Liga auch bei leerer Antwort (200, kein response)", {
  env <- lade_retrieve_results()
  f <- env$retrieveResults
  stub(f, "VERB", function(...) fake_response(200))
  stub(f, "status_code", function(response) response$status_code)
  stub(f, "content", function(...) '{"response": []}')
  stub(f, "fromJSON", function(...) list(response = list()))

  msgs <- capture_messages(
    suppressWarnings(result <- f(league = "85", season = "2026"))
  )

  expect_null(result)
  expect_true(any(grepl("85", msgs, fixed = TRUE)))
})
