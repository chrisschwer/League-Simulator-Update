library(testthat)

# ===========================================================================
# 6. Rundenfilter an den echten RL-Spielplaenen
# ===========================================================================

# Der Cache hat 83-87 nur bis 2025; 2026 gibt es dort noch nicht. Die
# 2025er-Spielplaene sind die schaerfste verfuegbare Probe, weil genau dort
# die beiden Fallen liegen:
#
#   Liga 84 wechselte 2025 die Sprache: "Nord - 12" -> "North - 12"
#   Liga 86 schreibt "Suedwest - 12" mit Umlaut im ue
#
# Eine Positivliste (startsWith "Regular Season") haette JEDES dieser Spiele
# verworfen und die Liga leer simuliert -- ohne Fehlermeldung. Das ist der
# Regressionsschutz fuer den Livegang.

test_that("der Rundenfilter behaelt alle Hauptrundenspiele der fuenf RL", {
  rf <- source_module("round_filter")

  # Gemessen an den committeten Spielplaenen: 34 Spieltage, 18 Teams.
  erwartet_spieltage <- 34L

  for (id in RL_IDS) {
    pfad <- test_path("fixtures", "fixture_cache",
                      paste0(id, "_2025.json"))
    skip_if_not(file.exists(pfad), paste("Fixture fehlt:", id))

    x <- jsonlite::fromJSON(pfad)
    keep <- rf$is_regular_season_round(x$round)

    # Kein Hauptrundenspiel darf verlorengehen: Alles, was nicht als
    # K.-o.-Runde erkannt wird, bleibt drin.
    expect_identical(length(unique(x$round[keep])), erwartet_spieltage,
                     info = id)
    expect_gte(sum(keep), 300L)
  }
})

test_that("Liga 84 ueberlebt den Sprachwechsel Nord -> North", {
  # 2024 hiess der Spieltag "Nord - 12", 2025 "North - 12". Beide muessen
  # durchkommen; eine Positivliste haette beim Wechsel lautlos eine leere
  # Liga erzeugt.
  rf <- source_module("round_filter")

  for (saison in c(2024, 2025)) {
    pfad <- test_path("fixtures", "fixture_cache",
                      paste0("84_", saison, ".json"))
    skip_if_not(file.exists(pfad))

    x <- jsonlite::fromJSON(pfad)
    keep <- rf$is_regular_season_round(x$round)
    expect_identical(sum(!keep), 0L, info = as.character(saison))
  }

  # Und beide Schreibweisen kommen wirklich vor -- sonst prueft der Test
  # oben nichts.
  labels_2024 <- jsonlite::fromJSON(
    test_path("fixtures", "fixture_cache", "84_2024.json"))$round
  labels_2025 <- jsonlite::fromJSON(
    test_path("fixtures", "fixture_cache", "84_2025.json"))$round
  expect_true(any(grepl("^Nord - ", labels_2024)))
  expect_true(any(grepl("^North - ", labels_2025)))
})

test_that("Liga 86 ueberlebt den Umlaut in Suedwest", {
  rf <- source_module("round_filter")
  pfad <- test_path("fixtures", "fixture_cache", "86_2025.json")
  skip_if_not(file.exists(pfad))

  x <- jsonlite::fromJSON(pfad)
  # Die Schreibweise steht wirklich mit Umlaut im Spielplan.
  expect_true(any(grepl("dwest - ", x$round)))
  expect_identical(sum(!rf$is_regular_season_round(x$round)), 0L)
})

test_that("Liga 83 verwirft die Relegationsrunde und behaelt den Rest", {
  # Bayern 2025 enthaelt eine "Relegation Round". Sie MUSS raus -- sie ist
  # kein Hauptrundenspiel und wuerde die Tabelle verfaelschen. Alles andere
  # bleibt.
  rf <- source_module("round_filter")
  pfad <- test_path("fixtures", "fixture_cache", "83_2025.json")
  skip_if_not(file.exists(pfad))

  x <- jsonlite::fromJSON(pfad)
  keep <- rf$is_regular_season_round(x$round)

  expect_identical(unique(x$round[!keep]), "Relegation Round")
  expect_identical(length(unique(x$round[keep])), 34L)
})

test_that("assert_rounds_kept schuetzt jede der fuenf neuen Ligen", {
  # Das Schutznetz aus Phase 0, jetzt scharf: Wuerde eine kuenftige
  # Schreibweise am Filter scheitern, bricht der Lauf mit den beobachteten
  # Labels ab -- statt eine leere Liga zu simulieren.
  rf <- source_module("round_filter")

  expect_error(
    rf$assert_rounds_kept(306, 0, c("Bayern - 1", "Bayern - 2"),
                          context = "RL Bayern"),
    "Bayern - 1"
  )
  # Kein Abbruch, wenn ueberhaupt keine Spiele angesetzt sind.
  expect_true(rf$assert_rounds_kept(0, 0, character(0)))
})

# --- aus test-fixture_cache.R (Stufe 4.4a) ---

test_that("is_regular_season_round erkennt die abweichenden RL-Labels", {
  # Die Regionalligen liefern "Bayern - 34" / "Nord - 20" statt
  # "Regular Season - N", und wechseln zwischen Saisons sogar die Sprache
  # ("Nord" vs "North"). Eine Positivliste wuerde jedes RL-Spiel verwerfen --
  # daher Negativliste: alles zaehlt, was keine K.-o.-Runde ist.
  expect_true(is_regular_season_round("Regular Season - 12"))
  expect_true(is_regular_season_round("Bayern - 34"))
  expect_true(is_regular_season_round("Nord - 20"))
  expect_true(is_regular_season_round("North - 20"))
})

test_that("is_regular_season_round verwirft K.-o.- und Playoff-Runden", {
  expect_false(is_regular_season_round("Relegation - 1"))
  expect_false(is_regular_season_round("Promotion Play-offs - 1"))
  expect_false(is_regular_season_round("Final"))
  expect_false(is_regular_season_round("Semi-finals"))
})

test_that("is_regular_season_round ist gegen NA und Leerstring robust", {
  expect_false(is_regular_season_round(NA_character_))
  expect_false(is_regular_season_round(""))
})
