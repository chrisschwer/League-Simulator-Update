library(testthat)

# Phase 3 baut den Shiny-Preview aus; lokale Vorschau ist künftig
# "Generator laufen lassen, HTML öffnen" via scripts/preview_site.R.

test_that("scripts/preview_site.R existiert und ist syntaktisch valide", {
  path <- test_path("..", "..", "scripts", "preview_site.R")
  expect_true(file.exists(path))
  expect_no_error(parse(path))
})

test_that("der Shiny-Preview ist ausgebaut", {
  expect_false(file.exists(test_path("..", "..", "ShinyApp", "app.R")))
  packagelist <- readLines(test_path("..", "..", "packagelist.txt"), warn = FALSE)
  expect_false(any(trimws(packagelist) == "shiny"))
})
