# Per-league configuration. The leagues are asymmetric: 3. Liga's promotion
# table comes from Ergebnis3_Aufstieg while its relegation table and heatmap
# come from Ergebnis3. These assertions pin that down.

source_league_views <- function() {
  source(test_path("..", "..", "RCode", "league_views.R"), local = TRUE)
  environment()$league_views
}

test_that("league_views defines exactly the three leagues", {
  views <- source_league_views()()
  expect_named(views, c("bundesliga", "zweite_bundesliga", "dritte_liga"))
})

test_that("Bundesliga is the canonical index page", {
  v <- source_league_views()()$bundesliga
  expect_equal(v$slug, "index")
  expect_equal(v$nav_label, "Bundesliga")
  expect_equal(v$plot_source, "Ergebnis")
  expect_equal(v$teams, 18)
  expect_equal(v$top$labels,
               c("Meister", "Champions League", "Europa League",
                 "Conference League Quali"))
  expect_equal(v$top$filter_cols, 1:6)
  expect_equal(v$bottom$labels, c("Relegation", "Abstieg"))
  expect_equal(v$bottom$filter_cols, 16:18)
})

test_that("2. Bundesliga uses Ergebnis2 for every panel", {
  v <- source_league_views()()$zweite_bundesliga
  expect_equal(v$slug, "2-bundesliga")
  expect_equal(v$plot_source, "Ergebnis2")
  expect_equal(v$top$source, "Ergebnis2")
  expect_equal(v$bottom$source, "Ergebnis2")
  expect_equal(v$top$labels, c("Aufstieg", "Relegation Bundesliga"))
  expect_equal(v$top$filter_cols, 1:3)
})

test_that("3. Liga draws its top table from Ergebnis3_Aufstieg but its bottom from Ergebnis3", {
  v <- source_league_views()()$dritte_liga
  expect_equal(v$slug, "3-liga")
  expect_equal(v$teams, 20)
  expect_equal(v$plot_source, "Ergebnis3")
  expect_equal(v$top$source, "Ergebnis3_Aufstieg")
  expect_equal(v$bottom$source, "Ergebnis3")
  expect_equal(v$top$labels, c("Aufstieg", "Relegation", "DFB-Pokal"))
  expect_equal(v$top$filter_cols, 1:4)
  expect_equal(v$bottom$labels, "Abstieg")
  expect_equal(v$bottom$filter_cols, 17:20)
})

test_that("group matrices have two rows and one column per label", {
  views <- source_league_views()()
  for (nm in names(views)) {
    v <- views[[nm]]
    for (panel in c("top", "bottom")) {
      g <- v[[panel]]$groups
      expect_equal(nrow(g), 2, info = paste(nm, panel))
      expect_equal(ncol(g), length(v[[panel]]$labels), info = paste(nm, panel))
      expect_true(all(g[1, ] <= g[2, ]), info = paste(nm, panel))
    }
  }
})
