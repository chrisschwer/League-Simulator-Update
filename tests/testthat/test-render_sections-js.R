# Client-JS der Seite, Teil 2: Ligatabelle sortieren (.LIGA_SORT_SCRIPT) und
# Kuerzel-Tooltips (.KUERZEL_SCRIPT), beide in RCode/render_sections.R. Node +
# jsdom fuehren sie auf der gerenderten Ligaseite aus (Stufe 4.6, #212).
# jsdom hat kein Layout: die Position des Tooltips ist nicht pruefbar, nur
# Vorhandensein, Text und Sichtbarkeit.

# Punkte, gegen den Platz verschoben, damit Sortieren nach Punkten die
# Reihenfolge wirklich aendert.
js_punkte <- c(5, 12, 9, 3, 17, 1, 14, 8, 11, 2, 16, 7, 13, 4, 18, 6, 15, 10)

# Eine Ligaseite mit Tabelle und Kuerzeln.
liga_seite <- function() {
  gen <- source_module("generate_static_site")
  out <- withr::local_tempdir(.local_envir = parent.frame())
  entry <- list(tabelle = data.frame(
    platz = 1:18, team_id = 1:18, kuerzel = paste0("T", 1:18),
    name = paste("Verein", 1:18), spiele = 10, tore = 10, gegentore = 10,
    tordifferenz = 0, punkte = js_punkte, elo = 1400 + (js_punkte * 13) %% 50,
    delta_elo = 0, stringsAsFactors = FALSE
  ))
  path <- gen$render_league_page(
    gen$league_views()$bundesliga, make_data_env(), out,
    now = as.POSIXct("2026-09-24 20:00", tz = "Europe/Berlin"),
    league_entry = entry
  )
  read_html(path)
}

test_that("alle Skripte der Ligaseite bestehen die Syntaxpruefung", {
  skip_ohne_js()
  skripte <- js_skripte_aus_html(liga_seite())
  expect_gt(length(skripte), 0)
  expect_true(all(js_syntax_status(skripte) == 0L))
})

# --- Sortieren ---------------------------------------------------------------

test_that("Klick auf eine Spalte sortiert die Zeilen nach data-<key> in data-dir-Richtung", {
  skip_ohne_js()
  # "pkt" hat data-dir="desc" und weicht in der Fixture von der Platzreihenfolge ab.
  r <- js_szenario(liga_seite(), "sort", list(klicks = list("pkt")))
  schritt <- r$schritte[[1]]

  expect_length(r$fehler, 0)
  expect_identical(schritt$dir, "desc")
  expect_identical(as.numeric(unlist(schritt$werte)), sort(js_punkte, decreasing = TRUE))
  # die Zeilen sind dieselben, nur anders angeordnet
  expect_setequal(as.integer(unlist(schritt$plaetze)), 1:18)
})

test_that("aria-sort steht nur am geklickten Knopf", {
  skip_ohne_js()
  r <- js_szenario(liga_seite(), "sort", list(klicks = list("pkt")))
  aria <- r$schritte[[1]]$aria

  expect_length(aria, 1)
  expect_identical(aria[[1]]$key, "pkt")
  expect_identical(aria[[1]]$wert, "descending")
})

test_that("fremde Sortierung entfernt data-zonen, platz setzt es wieder", {
  skip_ohne_js()
  # Zonen tragen nur die Regionalligen; die Fixture-Seite hat keine. Darum die
  # Tabelle mit Zonen direkt rendern und das Sortierskript dahinter setzen.
  gen <- source_module("generate_static_site")
  n <- 18L
  tab <- data.frame(
    platz = seq_len(n), team_id = seq_len(n), name = paste("Verein", seq_len(n)),
    spiele = 10, tore = 10, gegentore = 10, tordifferenz = 0,
    punkte = js_punkte, elo = 1500, delta_elo = 0, stringsAsFactors = FALSE
  )
  abstieg <- numeric(n)
  abstieg[n] <- 1
  html <- paste0(
    "<!doctype html><html><body>",
    gen$render_liga_tabelle(tab, zonen = list(abstieg = abstieg, relegation = NULL,
                                              aufstieg = numeric(n))),
    gen$.LIGA_SORT_SCRIPT, "</body></html>"
  )

  r <- js_szenario(html, "sort", list(klicks = list("pkt", "platz")))

  expect_length(r$fehler, 0)
  expect_identical(r$vorher$zonen, "platz")
  expect_null(r$schritte[[1]]$zonen)
  expect_identical(r$schritte[[2]]$zonen, "platz")
  expect_identical(as.integer(unlist(r$schritte[[2]]$plaetze)), 1:n)
})

test_that("Sortieren nach Platz stellt auf der Ligaseite die Platzreihenfolge wieder her", {
  skip_ohne_js()
  r <- js_szenario(liga_seite(), "sort", list(klicks = list("pkt", "platz")))

  expect_length(r$fehler, 0)
  expect_identical(as.integer(unlist(r$schritte[[2]]$plaetze)), 1:18)
  expect_identical(r$schritte[[2]]$aria[[1]]$wert, "ascending")
})

# --- Kuerzel-Tooltip ---------------------------------------------------------
# Es gibt auf der Seite mehrere abbr.kz (Heatmap, Panels, Tabelle); der Index
# zaehlt in Dokumentreihenfolge. 0 und 1 sind fest gewaehlt: jede Tabelle der
# Seite enthaelt mehr als ein Kuerzel.

test_that("Klick auf ein Kuerzel zeigt den title-Text als Tooltip", {
  skip_ohne_js()
  r <- js_szenario(liga_seite(), "tooltip", list(schritte = list(list(art = "klick", index = 0))))
  z <- r$schritte[[1]]

  expect_length(r$fehler, 0)
  expect_true(z$vorhanden)
  expect_identical(z$rolle, "tooltip")
  expect_false(z$verborgen)
  expect_match(z$text, "^Verein [0-9]+$")
  expect_identical(z$text, r$titel[[1]])
})

test_that("zweiter Klick, Klick daneben, Escape, Scroll und Resize schliessen den Tooltip", {
  skip_ohne_js()
  html <- liga_seite()
  auf <- list(art = "klick", index = 0)
  schliessen <- list(
    zweiter_klick = list(art = "klick", index = 0),
    daneben = list(art = "daneben"),
    escape = list(art = "escape"),
    scroll = list(art = "scroll"),
    resize = list(art = "resize")
  )
  for (fall in names(schliessen)) {
    # je Fall ab frisch geoeffnetem Tooltip
    r <- js_szenario(html, "tooltip", list(schritte = list(auf, schliessen[[fall]])))
    expect_length(r$fehler, 0)
    expect_false(r$schritte[[1]]$verborgen, info = fall)
    expect_true(r$schritte[[2]]$verborgen, info = fall)
  }
})

test_that("ein Klick auf ein anderes Kuerzel wechselt den Text, statt zu schliessen", {
  skip_ohne_js()
  r <- js_szenario(liga_seite(), "tooltip", list(schritte = list(
    list(art = "klick", index = 0), list(art = "klick", index = 1)
  )))

  expect_length(r$fehler, 0)
  expect_false(r$schritte[[2]]$verborgen)
  expect_identical(r$schritte[[2]]$text, r$titel[[2]])
  expect_false(identical(r$schritte[[1]]$text, r$schritte[[2]]$text))
})

test_that("Enter auf einem Kuerzel oeffnet den Tooltip", {
  skip_ohne_js()
  r <- js_szenario(liga_seite(), "tooltip", list(schritte = list(list(art = "enter", index = 0))))
  z <- r$schritte[[1]]

  expect_length(r$fehler, 0)
  expect_true(z$vorhanden)
  expect_false(z$verborgen)
  expect_identical(z$text, r$titel[[1]])
})
