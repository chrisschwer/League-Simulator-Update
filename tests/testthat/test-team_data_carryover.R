# Test suite for team_data_carryover.R -- load_previous_team_list() and
# get_existing_team_data() are the functions with live callers
# (season_processor.R, team_history_resolver.R). source_with_fallback() hatte
# hier eine wortgleiche, unbenutzte Kopie; sie fiel mit #267, ihr Test steht
# seither in test-season_processor.R bei der benutzten Definition.
# build_team_lookup_table(), validate_short_name_uniqueness(),
# merge_team_data_with_carryover() and ensure_unique_short_names() had none
# and were removed in the same PR that adds this file (Stufe 4.5, #212).
#
# Die beiden Bloecke "load_previous_team_list loads valid team data" und
# "get_existing_team_data returns correct team info" ziehen hierher aus
# test-season_processor.R (wortgleich, keine inhaltliche Aenderung) --
# season_processor.R testet process_league_teams() und
# process_single_season(), nicht die Carryover-Einheit selbst.

library(testthat)
library(mockery)

source("../../RCode/season_processor.R")
source("../../RCode/team_data_carryover.R")

context("team_data_carryover")

test_that("load_previous_team_list loads valid team data", {
  # Create temporary test file
  test_dir <- withr::local_tempdir()
  test_file <- file.path(test_dir, "RCode", "TeamList_2024.csv")
  dir.create(file.path(test_dir, "RCode"), recursive = TRUE, showWarnings = FALSE)
  
  # Write test data
  test_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1765, 1628)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock file path
  stub(load_previous_team_list, "paste0", function(...) test_file)
  stub(load_previous_team_list, "safe_file_read", function(path, ...) test_data)
  
  # Test
  result <- load_previous_team_list("2024")
  
  # Assertions
  expect_equal(nrow(result), 2)
  expect_equal(result$ShortText[1], "B04")
})

test_that("load_previous_team_list fuehrt vorhandene Temp-Dateien der Ligen zusammen", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "RCode"), recursive = TRUE)
  withr::local_dir(tmp)

  write.table(
    data.frame(TeamID = c(1, 2), ShortText = c("AAA", "BBB"), Promotion = c(0, 0), InitialELO = c(1000, 1000)),
    file.path("RCode", "TeamList_2025_League78_temp.csv"),
    sep = ";", row.names = FALSE, quote = FALSE
  )
  write.table(
    data.frame(TeamID = c(3, 4), ShortText = c("CCC", "DDD"), Promotion = c(0, 0), InitialELO = c(1000, 1000)),
    file.path("RCode", "TeamList_2025_League79_temp.csv"),
    sep = ";", row.names = FALSE, quote = FALSE
  )

  ausgabe <- capture.output(ergebnis <- load_previous_team_list("2025"))

  expect_equal(nrow(ergebnis), 4)
  expect_match(paste(ausgabe, collapse = "\n"), "merging for carryover")
})

test_that("load_previous_team_list liest sonst die zusammengefuehrte Datei", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "RCode"), recursive = TRUE)
  withr::local_dir(tmp)

  daten <- data.frame(
    TeamID = c(168, 167), ShortText = c("B04", "HOF"),
    Promotion = c(0, 0), InitialELO = c(1765, 1628)
  )
  write.table(daten, file.path("RCode", "TeamList_2025.csv"), sep = ";", row.names = FALSE, quote = FALSE)

  ergebnis <- load_previous_team_list("2025")

  expect_equal(nrow(ergebnis), 2)
  expect_equal(ncol(ergebnis), 4)
  expect_equal(ergebnis$ShortText, c("B04", "HOF"))
})

test_that("load_previous_team_list liefert NULL mit Warnung, wenn die Datei fehlt", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "RCode"), recursive = TRUE)
  withr::local_dir(tmp)

  expect_warning(ergebnis <- load_previous_team_list("2099"), "not found")
  expect_null(ergebnis)
})

test_that("load_previous_team_list liefert NULL mit Warnung, wenn Pflichtspalten fehlen", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "RCode"), recursive = TRUE)
  withr::local_dir(tmp)

  # Fehlt: Promotion.
  daten <- data.frame(TeamID = 1, ShortText = "AAA", InitialELO = 1000)
  write.table(daten, file.path("RCode", "TeamList_2025.csv"), sep = ";", row.names = FALSE, quote = FALSE)

  expect_warning(ergebnis <- load_previous_team_list("2025"), "missing required columns")
  expect_null(ergebnis)
})

test_that("get_existing_team_data returns correct team info", {
  # Setup
  prev_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, -50),
    stringsAsFactors = FALSE
  )
  
  # Test existing team
  result <- get_existing_team_data(168, prev_data)
  expect_equal(result$short_name, "B04")
  expect_equal(result$promotion_value, 0)
  
  # Test second team
  result <- get_existing_team_data(167, prev_data)
  expect_equal(result$short_name, "HOF")
  expect_equal(result$promotion_value, -50)
  
  # Test non-existing team
  result <- get_existing_team_data(999, prev_data)
  expect_null(result)
})

test_that("get_existing_team_data reicht die Region durch und laesst sie sonst leer", {
  mit_region <- data.frame(TeamID = 1, ShortText = "AAA", Promotion = 0, Region = "Nord", stringsAsFactors = FALSE)
  expect_equal(get_existing_team_data(1, mit_region)$region, "Nord")

  na_region <- data.frame(TeamID = 1, ShortText = "AAA", Promotion = 0, Region = NA_character_, stringsAsFactors = FALSE)
  expect_equal(get_existing_team_data(1, na_region)$region, "")

  ohne_region <- data.frame(TeamID = 1, ShortText = "AAA", Promotion = 0, stringsAsFactors = FALSE)
  expect_equal(get_existing_team_data(1, ohne_region)$region, "")

  expect_null(get_existing_team_data(1, NULL))
  expect_null(get_existing_team_data(1, data.frame()))
})
