# Der Saisonwechsel schreibt einen ENTWURF, nicht die produktive TeamList
# (ADR 0007, Schritt 7 aus PR #199).
#
# Bis hierher schrieb generate_team_list_csv() nach TeamList_<Jahr>.csv --
# nach einem confirm_overwrite(), das im --non-interactive-Modus immer TRUE
# zurueckgibt. Ein Lauf 2026 -> 2027 nach dem Rezept aus CLAUDE.md
# ueberschriebe damit die handgepflegte TeamList_2026.csv ohne Rueckfrage.
#
# Die TeamList ist gepflegtes Stammdatenblatt: Ueber Kurznamen und
# Zweitvertretungs-Status entscheidet Christoph, der Lauf schreibt fort und
# schlaegt vor. Also schreibt er TeamList_<Jahr>_entwurf.csv und ruehrt eine
# vorhandene produktive Datei nicht an.
#
# Die Trennung ist der Punkt: Ein Entwurf kann nicht versehentlich simuliert
# werden, weil der Produktivpfad ihn gar nicht liest. Die Alternative --
# eine fertige Datei mit Sperrvermerk -- verliesse sich darauf, dass die
# Sperre ueberall greift, wo gelesen wird.

library(testthat)

lade_entwurf_module <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "transform_data.R"), local = env)
  source(test_path("..", "..", "RCode", "csv_generation.R"), local = env)
  env
}

entwurfsdaten <- function() {
  data.frame(
    TeamID = c(1, 2),
    ShortText = c("AAA", "BBB"),
    Promotion = c(0, -50),
    InitialELO = c(1500, 1400),
    League = c("87", "87"),
    Region = c("West", ""),
    Name = c("Verein A", "Verein B II"),
    stringsAsFactors = FALSE
  )
}

test_that("der Lauf schreibt TeamList_<Jahr>_entwurf.csv", {
  env <- lade_entwurf_module()
  dir <- withr::local_tempdir()

  pfad <- env$generate_team_list_csv(entwurfsdaten(), "2027", output_dir = dir)

  expect_equal(basename(pfad), "TeamList_2027_entwurf.csv")
  expect_true(file.exists(file.path(dir, "TeamList_2027_entwurf.csv")))
})

test_that("eine vorhandene produktive TeamList bleibt Byte fuer Byte stehen", {
  # Der Kern von ADR 0007. Ohne diesen Test bleibt der gefaehrliche Pfad
  # offen: confirm_overwrite() gibt im --non-interactive-Modus immer TRUE
  # zurueck, der Lauf meldete Erfolg, und die handgepflegte Datei waere weg.
  env <- lade_entwurf_module()
  dir <- withr::local_tempdir()

  produktiv <- file.path(dir, "TeamList_2027.csv")
  writeLines(c("TeamID;ShortText;Promotion;InitialELO;League;Region;Name",
               "999;HAND;0;1234.5;87;West;Von Hand gepflegt"),
             produktiv)
  vorher <- readBin(produktiv, "raw", file.info(produktiv)$size)

  env$generate_team_list_csv(entwurfsdaten(), "2027", output_dir = dir)

  nachher <- readBin(produktiv, "raw", file.info(produktiv)$size)
  expect_identical(nachher, vorher)
})

test_that("ein vorhandener Entwurf wird ohne Rueckfrage ersetzt", {
  # Der Entwurf ist ein Zwischenstand, kein gepflegtes Gut. Wer den Lauf
  # zweimal startet, will den zweiten Stand -- eine Rueckfrage waere hier
  # nur im Weg.
  env <- lade_entwurf_module()
  dir <- withr::local_tempdir()

  entwurf <- file.path(dir, "TeamList_2027_entwurf.csv")
  writeLines("alt", entwurf)

  env$generate_team_list_csv(entwurfsdaten(), "2027", output_dir = dir)

  expect_false(identical(readLines(entwurf, warn = FALSE), "alt"))
  expect_true(any(grepl("AAA", readLines(entwurf, warn = FALSE))))
})

test_that("die Konfliktliste nennt leere Regionen und Zweitvertretungen", {
  # Der Bericht ist kein Beiwerk (ADR 0007): Er sagt, was die Nacharbeit
  # anfassen muss. Geprueft wird, DASS die drei Gruppen vorkommen -- nicht
  # ihr Wortlaut.
  env <- lade_entwurf_module()
  dir <- withr::local_tempdir()

  ausgabe <- capture.output(
    env$generate_team_list_csv(entwurfsdaten(), "2027", output_dir = dir)
  )
  text <- paste(ausgabe, collapse = "\n")

  expect_match(text, "BBB")          # leere Region
  expect_match(text, "Entwurf")      # der Hinweis, dass nichts produktiv ist
})
