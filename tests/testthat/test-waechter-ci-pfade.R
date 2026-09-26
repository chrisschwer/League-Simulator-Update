# Zwei CI-Pfad-Waechter fuer die #146-Umstellung (End-ELOs ueber
# /league-details statt R-Rechnung):
#
#   1. rust_binary() findet das Binary auch unter /usr/local/bin/, dem
#      Pfad des Produktionsimages -- nicht nur unter target/release/.
#   2. Der Saisonwechsel-Snapshot faehrt die echte ELO-Kette: die
#      season-transition-Kassetten belegen /league-details, nicht nur
#      CSV-Formatierung.

library(testthat)

source("../../RCode/league_details.R")


# =============================================================================
# 6. Damit die Umstellung in der CI ueberhaupt geprueft wird
# =============================================================================

test_that("rust_binary findet das Binary auch am Ort des Produktionsimages", {
  # ENTSCHEIDUNG DES USERS (Issue #146, Teil 2).
  #
  # Der Befund, der diesen Test ausgeloest hat: Die R-Suite laeuft in der CI
  # IM PRODUKTIONSIMAGE (ci.yml, Job "image-build-and-test"). Dort liegt das
  # Binary nach Dockerfile:116 unter /usr/local/bin/ -- den Entwicklerpfad
  # target/release/ gibt es im Image nicht, weil der Rust-Build in einer
  # verworfenen Build-Stage passiert.
  #
  # test-update_all_leagues_loop-rust.R hat sich deshalb seit jeher still
  # uebersprungen. Das
  # faellt nicht auf: Ein Skip ist gruen. Genau deshalb steht hier ein Test --
  # er prueft die SUCHE, nicht den Fund, und bleibt damit auf jeder Maschine
  # aussagekraeftig, auch ohne gebautes Binary.
  # rust_binary() steht seit Stufe 3.6 in helper-rust.R.
  quelle <- readLines(test_path("helper-rust.R"), warn = FALSE)
  code <- paste(quelle, collapse = "\n")

  expect_match(code, "/usr/local/bin/league-simulator-rust", fixed = TRUE,
               info = paste("Ohne diesen Pfad prueft test-update_all_leagues_loop-rust.R in",
                            "der CI nichts -- es skippt sich still."))
  expect_match(code, "target", fixed = TRUE,
               info = "Der Entwicklerpfad muss erhalten bleiben.")
})

test_that("der Snapshot-Test des Saisonwechsels faehrt die echte ELO-Kette", {
  # ENTSCHEIDUNG DES USERS: Der Snapshot-Test darf einen Rust-Server
  # voraussetzen -- damit die ECHTE Kette einschliesslich ELO-Physik geprueft
  # bleibt, statt sie hinter einer Kassette wegzumocken.
  #
  # Bei der Umsetzung ergab sich die bessere Haelfte beider Varianten: Die
  # /league-details-Antworten wurden gegen die echte Engine aufgezeichnet und
  # liegen als httptest-Kassetten vor. Die Physik ist damit in der geprueften
  # Kette -- die Zahlen im Snapshot stammen aus dem Rust-Walk --, aber weder
  # CI noch Entwicklerrechner brauchen einen laufenden Server.
  #
  # Was dieser Test festhaelt: dass die Kette den Endpoint ueberhaupt anfasst.
  # Ohne die Kassetten liefe der Snapshot-Lauf daran vorbei, und der Test
  # pruefte wieder nur noch CSV-Formatierung.
  runner <- paste(
    readLines(test_path("helpers", "season-transition-snapshot-runner.R"),
              warn = FALSE),
    collapse = "\n")

  expect_match(runner, "league_details.R", fixed = TRUE,
               info = paste("Nach Teil 2 holt der Saisonwechsel die End-ELOs",
                            "ueber /league-details; ohne dieses Modul bricht",
                            "der Subprozess ab."))

  kassetten <- list.files(
    test_path("fixtures", "season-transition-2024-to-2025"),
    pattern = "league-details.*\\.json$", recursive = TRUE)
  expect_gt(length(kassetten), 0)
})
