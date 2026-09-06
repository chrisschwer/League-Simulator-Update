# Unit tests fuer den Fixture-Cache der ELO-Kalibrierung.
#
# Der Cache legt rohe API-Antworten je (Liga, Saison) auf Platte, damit die
# Kalibrierung ohne erneute API-Last wiederholbar ist. Er ist bewusst KEINE
# Persistenzschicht des Produktivpfads (ADR 0002) -- er lebt nur fuer den
# einmaligen Offline-Lauf und ist gitignored.

library(testthat)

source("../../RCode/fixture_cache.R")

test_that("cache_path baut einen Pfad je Liga und Saison", {
  p <- cache_path("83", 2024, cache_dir = "/tmp/x")

  expect_equal(p, "/tmp/x/83_2024.json")
})

test_that("cached_fixtures schreibt beim ersten Aufruf und liest danach ohne Fetch", {
  tmp <- file.path(tempdir(), paste0("fc-", as.integer(runif(1, 1e6, 9e6))))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  calls <- 0
  fetcher <- function(league, season) {
    calls <<- calls + 1
    data.frame(fixture_id = c(1, 2), goals_home = c(1, 0), goals_away = c(0, 2))
  }

  first <- cached_fixtures("83", 2024, fetch_fn = fetcher, cache_dir = tmp)
  second <- cached_fixtures("83", 2024, fetch_fn = fetcher, cache_dir = tmp)

  expect_equal(calls, 1)          # zweiter Aufruf kommt aus dem Cache
  expect_equal(nrow(first), 2)
  expect_equal(second$fixture_id, first$fixture_id)
  expect_equal(second$goals_away, first$goals_away)
})

test_that("cached_fixtures holt bei refresh = TRUE erneut", {
  tmp <- file.path(tempdir(), paste0("fc-", as.integer(runif(1, 1e6, 9e6))))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  calls <- 0
  fetcher <- function(league, season) {
    calls <<- calls + 1
    data.frame(fixture_id = 1, goals_home = 1, goals_away = 0)
  }

  cached_fixtures("83", 2024, fetch_fn = fetcher, cache_dir = tmp)
  cached_fixtures("83", 2024, fetch_fn = fetcher, cache_dir = tmp, refresh = TRUE)

  expect_equal(calls, 2)
})

test_that("cached_fixtures haelt Ligen und Saisons getrennt", {
  tmp <- file.path(tempdir(), paste0("fc-", as.integer(runif(1, 1e6, 9e6))))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  fetcher <- function(league, season) {
    data.frame(fixture_id = as.numeric(paste0(league, season)))
  }

  a <- cached_fixtures("83", 2024, fetch_fn = fetcher, cache_dir = tmp)
  b <- cached_fixtures("84", 2024, fetch_fn = fetcher, cache_dir = tmp)

  expect_false(identical(a$fixture_id, b$fixture_id))
})

test_that("cached_fixtures schreibt nichts, wenn der Fetch NULL liefert", {
  tmp <- file.path(tempdir(), paste0("fc-", as.integer(runif(1, 1e6, 9e6))))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  result <- cached_fixtures("99", 2024,
                            fetch_fn = function(league, season) NULL,
                            cache_dir = tmp)

  expect_null(result)
  expect_false(file.exists(cache_path("99", 2024, cache_dir = tmp)))
})

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

test_that("is_relegation_round erkennt genau die Relegationspartien", {
  # Diese Spiele sind die einzige direkte Evidenz zwischen sonst getrennten
  # Ligen -- sie werden gebraucht, nicht verworfen.
  expect_true(is_relegation_round("Relegation - 1"))
  expect_true(is_relegation_round("Promotion Play-offs - 2"))
  expect_false(is_relegation_round("Bayern - 34"))
  expect_false(is_relegation_round("Regular Season - 12"))
})
