source_zuordnung <- function() {
  source(file.path("..", "..", "scripts", "dev", "zuordnung_tests.R"), local = TRUE)
  environment()
}

test_that("ein Block, der nur Funktionen einer Einheit ruft, landet dort", {
  z <- source_zuordnung()
  index <- list(load_team_list = "transform_data", pruefe_kuerzel_vertrag = "transform_data")
  expect_identical(z$einheit_fuer(c("load_team_list", "pruefe_kuerzel_vertrag"), index),
                   "transform_data")
})

test_that("ein Block, der Funktionen mehrerer Einheiten ruft, bekommt die am haeufigsten gerufene", {
  z <- source_zuordnung()
  index <- list(build_league_table = "league_details",
                render_league_page = "generate_static_site",
                league_views = "league_views")
  expect_identical(z$einheit_fuer(c("build_league_table", "build_league_table", "league_views"), index),
                   "league_details")
})

test_that("indirekte Aufrufe ueber Stringliterale zaehlen als Aufruf", {
  z <- source_zuordnung()
  index <- list(abstiegswahrscheinlichkeit = "rl_abstiegskopplung")
  body <- 'p <- fn(env, "abstiegswahrscheinlichkeit")(prognose, gewichte)'
  expect_identical(z$einheit_fuer_block(body, index), "rl_abstiegskopplung")
})

test_that("gestubbte Mitspieler zaehlen nicht, die Funktion unter Test schon", {
  # Zweifelsregel (tests/testthat/README.md): Gestubbte Mitspieler zaehlen
  # nicht. stub(f, "g", ...) nennt g als String -- das ist kein Aufruf von g,
  # sondern einer von f.
  z <- source_zuordnung()
  index <- list(update_all_leagues_loop = "update_all_leagues_loop",
                retrieveResults = "retrieveResults",
                transform_data = "transform_data",
                simulate_league_rust = "rust_integration")
  body <- paste(
    'stub(update_all_leagues_loop, "retrieveResults", function(...) NULL)',
    'stub(update_all_leagues_loop, "transform_data", function(...) NULL)',
    'stub(env$simulate_league_rust, "POST", function(...) NULL)',
    sep = "\n")
  expect_identical(sort(unique(z$gerufene_funktionen(body, index))),
                   c("simulate_league_rust", "update_all_leagues_loop"))
  expect_identical(z$einheit_fuer_block(body, index), "update_all_leagues_loop")
})

test_that("ein Block ohne bekannte Funktion bekommt NA, keinen Rateversuch", {
  z <- source_zuordnung()
  expect_true(is.na(z$einheit_fuer(character(0), list())))
})

test_that("Grep-Tests auf Quelltext werden als waechter erkannt", {
  z <- source_zuordnung()
  body <- 'quelle <- readLines("../../RCode/league_registry.R"); expect_false(any(grepl("40", quelle)))'
  expect_identical(z$einheit_fuer_block(body, list()), "waechter")
})

test_that("die geladenen Einheiten werden aus allen Pfadformen gelesen", {
  z <- source_zuordnung()
  kopf <- c('source(test_path("..", "..", "RCode", "league_details.R"))',
            'source("../../RCode/render_helpers.R")',
            'source(rcode("rl_aufstieg.R"), local = env)',
            'for (datei in c("rl_abstiegskopplung.R", "staffel_zuordnung.R")) source(rcode(datei))')
  expect_identical(z$gesourcte_einheiten(kopf, c("league_details", "render_helpers", "rl_aufstieg",
                                                 "rl_abstiegskopplung", "staffel_zuordnung")),
                   c("league_details", "render_helpers", "rl_aufstieg",
                     "rl_abstiegskopplung", "staffel_zuordnung"))
})

test_that("Kommentare und unbekannte Dateinamen zaehlen nicht als geladene Einheit", {
  z <- source_zuordnung()
  kopf <- c('# frueher: source("../../RCode/rust_integration.R")',
            'pfad <- "fixtures/TeamList_minimal.R"')
  expect_identical(z$gesourcte_einheiten(kopf, c("rust_integration")), character(0))
})
