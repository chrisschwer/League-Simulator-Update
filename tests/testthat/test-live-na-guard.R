# Regressionstest für den 4b-Review-Übertrag (in 4c umgesetzt): api-football
# meldet Fixtures in den ersten Minuten nach Anpfiff als live, ohne die
# goals-Felder zu befüllen. Der Zwischenstand darf dann nie "NA:NA" zeigen,
# sondern einen Strich-Platzhalter.

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

test_that("Live-Zwischenstand ohne Tore rendert Striche, nie NA", {
  gen <- source_generator()
  lv <- data.frame(
    fixture_id = 7001, round = 2L,
    kickoff = as.POSIXct("2026-08-30 15:30", tz = "UTC"), status = "1H",
    home_id = 101, away_id = 102,
    home_name = "FC Alpha", away_name = "SV Beta",
    goals_home = NA_real_, goals_away = NA_real_,
    stringsAsFactors = FALSE
  )

  html <- gen$render_live(lv)

  expect_false(grepl("NA", html, fixed = TRUE))
  expect_match(html, "–:–", fixed = TRUE)
})
