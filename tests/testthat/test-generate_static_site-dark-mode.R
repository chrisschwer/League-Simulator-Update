# Dark Mode: Die Seite folgt der System-Einstellung (prefers-color-scheme).
# Damit das vollstaendig gilt, muss (a) jede Farbvariable aus :root im
# dunklen Block neu belegt sein und (b) ausserhalb der beiden Variablen-
# bloecke keine feste Farbe im Stylesheet stehen -- jede feste Farbe waere
# eine Stelle, die im Dunkeln hell bleibt (so wie bisher das Weiss in den
# Quotenbalken und das Dunkelrot beim Ueberfahren von Links).

lies_css <- function() {
  paste(readLines(test_path("..", "..", "RCode", "site_assets", "site.css"),
                  warn = FALSE), collapse = "\n")
}

# Inhalt des ersten Blocks, der mit `kopf` beginnt, bis zur passenden
# schliessenden Klammer.
css_block <- function(css, kopf) {
  start <- regexpr(kopf, css, fixed = TRUE)
  if (start < 0) return(NA_character_)
  zeichen <- strsplit(substring(css, start), "")[[1]]
  tiefe <- 0L
  for (i in seq_along(zeichen)) {
    if (zeichen[i] == "{") tiefe <- tiefe + 1L
    if (zeichen[i] == "}") {
      tiefe <- tiefe - 1L
      if (tiefe == 0L) return(paste(zeichen[seq_len(i)], collapse = ""))
    }
  }
  NA_character_
}

farb_tokens <- function(block) {
  defs <- regmatches(block, gregexpr("--[a-z0-9-]+\\s*:\\s*[^;}]+", block))[[1]]
  namen <- sub("\\s*:.*$", "", defs)
  werte <- sub("^[^:]+:\\s*", "", defs)
  namen[grepl("^#|^rgb|^hsl|^color-mix", werte)]
}

test_that("der dunkle Block belegt jede Farbvariable neu", {
  css <- lies_css()
  hell <- css_block(css, ":root{")
  dunkel <- css_block(css, "@media (prefers-color-scheme:dark)")
  expect_false(is.na(dunkel))
  fehlend <- setdiff(farb_tokens(hell), farb_tokens(dunkel))
  expect_equal(fehlend, character(0))
  expect_match(dunkel, "color-scheme:dark", fixed = TRUE)
})

test_that("ausserhalb der Variablenbloecke steht keine feste Farbe", {
  css <- lies_css()
  rest <- css
  for (kopf in c(":root{", "@media (prefers-color-scheme:dark)")) {
    block <- css_block(css, kopf)
    if (!is.na(block)) rest <- sub(block, "", rest, fixed = TRUE)
  }
  rest <- gsub("(?s)/\\*.*?\\*/", "", rest, perl = TRUE)
  expect_false(grepl("#[0-9A-Fa-f]{3,8}\\b", rest, perl = TRUE))
  expect_false(grepl("\\brgba?\\(", rest, perl = TRUE))
})

test_that("Heatmap und Ergebnis-Matrix faerben aus --t und --hi", {
  css <- lies_css()
  for (tabelle in c("table.heatmap td", "table.score td")) {
    regel <- css_block(css, paste0(tabelle, "{"))
    expect_match(regel, "var(--t", fixed = TRUE, info = tabelle)
    expect_match(regel, "var(--hi", fixed = TRUE, info = tabelle)
  }
})

test_that("die Heatmap der Ligaseite traegt keine Inline-Farbe", {
  # Gegenstueck zu den Stylesheet-Pruefungen: Eine Inline-Farbe im HTML
  # schlaegt jede Regel im dunklen Block, die Zelle bliebe hell.
  gen <- source_module("generate_static_site")
  m <- matrix(c(0.7, 0.3, 0.3, 0.7), nrow = 2,
              dimnames = list(c("ALP", "BET"), NULL))
  html <- gen$render_heatmap(m)
  expect_false(grepl("background:", html, fixed = TRUE))
  expect_false(grepl("color:#", html, fixed = TRUE))
  expect_match(html, sprintf("--t:%.3f;--hi:1", 0.7^0.6), fixed = TRUE)
})
