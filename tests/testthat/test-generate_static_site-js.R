# Client-JS der Seite, Teil 1: der Veraltet-Hinweis (.stale_script in
# RCode/generate_static_site.R). Node + jsdom fuehren das Skript auf der
# gerenderten Seite aus (Stufe 4.6, #212); Skript und Schwelle bleiben inline.
#
# Das Skript laeuft beim Laden der Seite. Date.now wird deshalb im Runner vor
# dem Parsen eingefroren (args$now, Millisekunden seit Epoche).

stunden_ms <- 3600 * 1000

# Die Seite aus der Preview-Fixture (make_data_env) und ihr Erzeugungszeitpunkt
# in ms, gelesen aus dem datetime-Attribut -- nicht geraten.
seite_mit_zeitstempel <- function() {
  gen <- source_module("generate_static_site")
  out <- withr::local_tempdir(.local_envir = parent.frame())
  path <- gen$render_league_page(
    gen$league_views()$bundesliga, make_data_env(), out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )
  html <- read_html(path)
  iso <- sub('.*<time id="generated" datetime="([^"]+)".*', "\\1", html)
  generated <- as.numeric(as.POSIXct(iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) * 1000
  list(html = html, generated = generated)
}

test_that("alle Skripte der Seite bestehen die Syntaxpruefung", {
  skip_ohne_js()
  seite <- seite_mit_zeitstempel()
  skripte <- js_skripte_aus_html(seite$html)
  expect_gt(length(skripte), 0)
  expect_true(all(js_syntax_status(skripte) == 0L))
})

test_that("der Veraltet-Hinweis bleibt eine Stunde vor der Schwelle verborgen", {
  skip_ohne_js()
  seite <- seite_mit_zeitstempel()
  r <- js_szenario(seite$html, "stale", list(now = seite$generated + 23 * stunden_ms))

  expect_length(r$fehler, 0)
  expect_true(r$verborgen)
  expect_identical(r$stunden, "?")
})

test_that("der Veraltet-Hinweis erscheint eine Stunde nach der Schwelle mit gerundeten Stunden", {
  skip_ohne_js()
  seite <- seite_mit_zeitstempel()
  r <- js_szenario(seite$html, "stale", list(now = seite$generated + 25.4 * stunden_ms))

  expect_length(r$fehler, 0)
  expect_false(r$verborgen)
  expect_identical(r$stunden, "25")
})

test_that("ohne #generated wirft das Skript keinen Fehler und der Hinweis bleibt verborgen", {
  skip_ohne_js()
  seite <- seite_mit_zeitstempel()
  html <- sub('<time id="generated" ', "<time ", seite$html, fixed = TRUE)
  expect_false(grepl('id="generated"', html, fixed = TRUE))

  # weit nach der Schwelle: ohne Zeitstempel darf trotzdem nichts erscheinen
  r <- js_szenario(html, "stale", list(now = seite$generated + 100 * stunden_ms))

  expect_length(r$fehler, 0)
  expect_true(r$verborgen)
})
