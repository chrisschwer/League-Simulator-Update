# Regressionstest aus dem 4c-Abschlussreview: Die Heat-Skalierung der
# Ergebnis-Matrix muss (p / max) * 0.75 rechnen (Mock-up-Formel). Die
# invertierte Lesart p / (max * 0.75) treibt die Spitzenzelle über 1 und
# .heat_style() in negative RGB-Kanäle — ungültiges CSS, die Zelle rendert
# weiß auf weiß.

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

mk_ausblick_einzeilig <- function() {
  m <- matrix(0, nrow = 7, ncol = 7)
  m[2, 1] <- 0.135   # Spitzenzelle (1:0)
  m[1, 1] <- 0.052
  df <- data.frame(
    fixture_id = 8001, round = 3L,
    kickoff = as.POSIXct("2026-12-04 19:30", tz = "UTC"), status = "NS",
    home_id = 101, away_id = 102,
    home_name = "FC Alpha", away_name = "SV Beta",
    goals_home = NA_real_, goals_away = NA_real_,
    p_home_win = 0.4, p_draw = 0.3, p_away_win = 0.3,
    elo_delta_home = NA_real_, nachholspiel = FALSE,
    stringsAsFactors = FALSE
  )
  df$score_matrix <- list(m)
  df
}

test_that("die Spitzenzelle trägt die Mock-up-Färbung, kein ungültiges CSS", {
  gen <- source_generator()
  html <- gen$render_ausblick(mk_ausblick_einzeilig(), runde = 3L)

  # Niemals negative RGB-Kanäle (Browser verwerfen die ganze Deklaration)
  expect_false(grepl("rgb(-", html, fixed = TRUE))

  # Spitzenzelle: p/max = 1 -> Färbung exakt .heat_style(0.75)
  expect_match(html, gen$.heat_style(0.75), fixed = TRUE)
  # Nebenzelle: 0.052/0.135 * 0.75
  expect_match(html, gen$.heat_style(0.052 / 0.135 * 0.75), fixed = TRUE)
})
