# Fixture fuer test-scripts-testthat_ci.R (Review Fix 1): ein Block, der mit
# einem unbehandelten R-Fehler abbricht. testthat zaehlt das als failed = 0,
# error = TRUE -- das alte Exit-Kriterium any(df$failed > 0) uebersah das
# (Befund der Review: test-scripts-preview_site.R:14 blieb deshalb in der CI
# unsichtbar rot). Kein test-/test_-Praefix (.gitignore:56, test_dir()).

test_that("phantom Fehler-Block", {
  stop("kaputt")
})
