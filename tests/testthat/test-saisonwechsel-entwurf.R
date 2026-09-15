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

# --- Der Konfliktbericht als DATEI (ADR 0007) ------------------------------
#
# Die Terminalausgabe allein traegt nicht: Der Lauf findet einmal im Juli
# statt, und bis zur Nacharbeit waere sie weggescrollt. ADR 0007 verlangt
# deshalb "eine Datei neben der TeamList". Sie heisst
# TeamList_<Jahr>_entwurf_konflikte.md -- gleicher Stamm wie der Entwurf,
# damit beide zusammen bleiben und beim Aufraeumen gemeinsam auffallen.
#
# Die Endung .md und nicht .txt: Der Bericht ist zum Lesen da, und die drei
# Gruppen sind Listen.

konfliktbericht_pfad <- function(dir, season = "2027") {
  file.path(dir, paste0("TeamList_", season, "_entwurf_konflikte.md"))
}

test_that("der Lauf schreibt den Konfliktbericht als Datei neben den Entwurf", {
  env <- lade_entwurf_module()
  dir <- withr::local_tempdir()

  env$generate_team_list_csv(entwurfsdaten(), "2027", output_dir = dir)

  expect_true(file.exists(konfliktbericht_pfad(dir)))
})

test_that("der Bericht nennt Teams ohne Stammregion und die Neuzugaenge", {
  # Die Vorsaison kennt nur AAA; BBB ist damit neu UND ohne Region.
  env <- lade_entwurf_module()
  dir <- withr::local_tempdir()

  utils::write.table(
    data.frame(TeamID = 1, ShortText = "AAA", Promotion = 0,
               InitialELO = 1500, League = "87", Region = "West",
               Name = "Verein A", stringsAsFactors = FALSE),
    file.path(dir, "TeamList_2026.csv"),
    sep = ";", quote = FALSE, row.names = FALSE
  )

  env$generate_team_list_csv(entwurfsdaten(), "2027", output_dir = dir)
  text <- paste(readLines(konfliktbericht_pfad(dir), warn = FALSE),
                collapse = "\n")

  expect_match(text, "BBB")                    # ohne Stammregion
  expect_match(text, "Stammregion")
  expect_match(text, "[Nn]eu")                 # Neuzugang gegenueber 2026
  expect_match(text, "2027")                   # um welchen Entwurf es geht
})

test_that("der Bericht nennt Kuerzel-Konflikte", {
  # Direkt auf bericht_konflikte(): Ein Kuerzel-Konflikt laesst
  # generate_team_list_csv() schon an validate_csv_data() scheitern, der
  # Bericht kaeme dort nie zum Zug. Die Gruppe muss er trotzdem koennen --
  # sie ist die erste der drei, und sie speist die Nacharbeit.
  env <- lade_entwurf_module()
  dir <- withr::local_tempdir()

  daten <- entwurfsdaten()
  daten$ShortText <- c("AAA", "AAA")           # zweimal dasselbe in Liga 87

  env$bericht_konflikte(daten, "2027", output_dir = dir)
  text <- paste(readLines(konfliktbericht_pfad(dir), warn = FALSE),
                collapse = "\n")

  expect_match(text, "AAA")
  expect_match(text, "Kuerzel|Kürzel")
})

test_that("ohne Befund entsteht der Bericht trotzdem", {
  # Sonst bliebe offen, ob der Lauf nichts gefunden oder nicht berichtet
  # hat. Eine leere Datei traegt diese Auskunft nicht -- eine Zeile schon.
  env <- lade_entwurf_module()
  dir <- withr::local_tempdir()

  sauber <- entwurfsdaten()
  sauber$Region <- c("West", "West")           # keine leere Region mehr

  env$bericht_konflikte(sauber, "2027", output_dir = dir)
  text <- paste(readLines(konfliktbericht_pfad(dir), warn = FALSE),
                collapse = "\n")

  expect_match(text, "[Kk]eine Konflikte")
})

test_that("der Bericht wiederholt, was die Terminalausgabe sagt", {
  # Zwei Ausgabewege, ein Inhalt. Liefen sie auseinander, waere nicht mehr
  # klar, welcher gilt.
  env <- lade_entwurf_module()
  dir <- withr::local_tempdir()

  ausgabe <- capture.output(
    env$generate_team_list_csv(entwurfsdaten(), "2027", output_dir = dir)
  )
  datei <- readLines(konfliktbericht_pfad(dir), warn = FALSE)

  expect_true(any(grepl("BBB", ausgabe)))
  expect_true(any(grepl("BBB", datei)))
})
