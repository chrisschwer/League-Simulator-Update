# Client-JS der Verlaufsseiten (Issue #184): assets/verlauf.js zeichnet das
# Diagramm aus #verlauf-daten. Node + jsdom fuehren es auf der gerenderten
# Seite aus (Runner-Szenario "verlauf"). Geometrie wie im Entwurf:
# W = 1080, M.l = 52, M.r = 80, also Zeichenbreite 948, rechter Rand x = 1000.
vjs_gen <- source_module("generate_static_site")

vjs_seite <- function(league_data, slug = "bundesliga-verlauf", envir = parent.frame()) {
  dir <- verlauf_site(league_data, envir = envir)
  js_assets_einbetten(html_lesen(file.path(dir, paste0(slug, ".html"))), dir)
}

vjs_lauf <- function(..., schritte = list()) {
  html <- vjs_seite(list(bundesliga = verlauf_beispiel(...)))
  js_szenario(html, "verlauf", list(schritte = schritte))
}

test_that("die Skripte der Verlaufsseite bestehen die Syntaxpruefung", {
  skip_ohne_js()
  html <- vjs_seite(list(bundesliga = verlauf_beispiel()))
  html <- gsub('(?s)<script type="application/json".*?</script>', "", html, perl = TRUE)
  skripte <- js_skripte_aus_html(html)
  expect_gt(length(skripte), 1)
  expect_true(all(js_syntax_status(skripte) == 0L))
})

test_that("eine Linie je Verein, Schnittstelle vorhanden, keine Skriptfehler", {
  skip_ohne_js()
  r <- vjs_lauf()
  expect_length(r$fehler, 0)
  expect_identical(r$api, "object")
  expect_true(r$vorher$hat_svg)
  expect_identical(r$vorher$linien, 4L)
  expect_false(r$vorher$pfad_kaputt)
  expect_identical(unlist(r$vorher$gedrueckt), c("true", "false"))
})

test_that("Spielachse: laufend endet die laengste Linie vor dem rechten Rand, abgeschlossen am Rand", {
  skip_ohne_js()
  laufend <- unlist(vjs_lauf()$vorher$letzte_x)
  expect_equal(unname(laufend), rep(684, 4), tolerance = 0.11)
  fertig <- unlist(vjs_lauf(laeuft = FALSE)$vorher$letzte_x)
  expect_equal(unname(fertig), rep(1000, 4), tolerance = 0.11)
})

test_that("Datumsachse: Saisonstart am linken Rand, Spiele nach Kalendertag", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "modus", wert = "datum")))
  s <- r$schritte[[1]]
  expect_identical(unlist(s$gedrueckt), c("false", "true"))
  expect_equal(unname(unlist(s$erste_x)), rep(52, 4), tolerance = 0.11)
  # Verein 101 (data-i 0): letztes Spiel 15.08.; Achse 02.08. bis 22.08. (20 Tage)
  expect_equal(s$letzte_x[["0"]], 52 + 948 * 13 / 20, tolerance = 0.11)
})

test_that("die Winterpause erscheint nur auf der Datumsachse", {
  skip_ohne_js()
  r <- vjs_lauf(pause_tage = 40, schritte = list(list(art = "modus", wert = "datum"),
                                                 list(art = "modus", wert = "spiel")))
  expect_false(r$vorher$pause)
  expect_true(r$schritte[[1]]$pause)
  expect_false(r$schritte[[2]]$pause)
})

test_that("die Endbeschriftungen ueberlappen in beiden Modi nicht", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "modus", wert = "datum")))
  for (zustand in list(r$vorher, r$schritte[[1]])) {
    y <- sort(unlist(zustand$label_y))
    expect_length(y, 4)
    expect_true(all(diff(y) >= 12.4))
  }
})

test_that("Tooltip: Datum, Spieltag, Paarung, Ergebnis, Erwartung, ELO", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "zeige", index = 0, n = 2)))
  s <- r$schritte[[1]]
  expect_true(s$tip_sichtbar)
  expect_identical(unlist(s$an), 0L)
  for (teil in c("Sa. 15. Aug. 2026 · 2. Spieltag", "Team 104", "Team 101", "2:0",
                 "50 % Sieg, 30 % Remis", "1610,0 → 1570,0", "−40,0")) {
    expect_match(s$tip_text, teil, fixed = TRUE)
  }
  expect_false(grepl("Nachholspiel", s$tip_text, fixed = TRUE))
})

test_that("ein Nachholspiel ist im Tooltip gekennzeichnet", {
  skip_ohne_js()
  r <- vjs_lauf(nachhol = TRUE, schritte = list(list(art = "zeige", index = 0, n = 2),
                                                list(art = "zeige", index = 0, n = 1)))
  expect_match(r$schritte[[1]]$tip_text, "2. Spieltag · Nachholspiel", fixed = TRUE)
  expect_false(grepl("Nachholspiel", r$schritte[[2]]$tip_text, fixed = TRUE))
})

test_that("eine Tabellenzeile hebt ihre Linie hervor, ein zweiter Klick hebt es auf", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "zeile", index = 1), list(art = "zeile", index = 1)))
  expect_identical(unlist(r$schritte[[1]]$an), 1L)
  expect_identical(unlist(r$schritte[[1]]$zeilen_an), 1L)
  expect_identical(r$schritte[[1]]$gedimmt, 3L)
  expect_length(unlist(r$schritte[[2]]$an), 0)
  expect_identical(r$schritte[[2]]$gedimmt, 0L)
  expect_length(r$fehler, 0)
})

test_that("der Moduswechsel behaelt die Auswahl", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "zeile", index = 2), list(art = "modus", wert = "datum")))
  expect_identical(unlist(r$schritte[[2]]$an), 2L)
})

test_that("Saisonauftakt mit einem einzigen Spiel: Diagramm ohne Fehler und ohne NaN", {
  skip_ohne_js()
  r <- vjs_lauf(nur_erstes = TRUE, schritte = list(list(art = "modus", wert = "datum")))
  expect_length(r$fehler, 0)
  expect_identical(r$vorher$linien, 4L)
  expect_false(r$vorher$pfad_kaputt)
  expect_false(r$schritte[[1]]$pfad_kaputt)
  # Achse: 1 Spiel + Ueberhang = 2; 101 (data-i 0) steht bei der Haelfte
  expect_equal(r$vorher$letzte_x[["0"]], 52 + 948 / 2, tolerance = 0.11)
})

test_that("ein offenes verschobenes Spiel: der Verein endet frueher, Beschriftungen ueberlappen nicht", {
  skip_ohne_js()
  r <- vjs_lauf(verschoben = TRUE)
  # Reihenfolge heute: 101 (1610), 102 (1488,5), 104 (1452), 103 (1399,5)
  expect_equal(r$vorher$letzte_x[["0"]], 52 + 948 / 3, tolerance = 0.11)
  expect_equal(r$vorher$letzte_x[["1"]], 52 + 948 * 2 / 3, tolerance = 0.11)
  expect_true(all(diff(sort(unlist(r$vorher$label_y))) >= 12.4))
})

test_that("ohne gespielte Spiele: kein Diagramm, kein Fehler", {
  skip_ohne_js()
  r <- vjs_lauf(leer = TRUE)
  expect_false(r$vorher$hat_svg)
  expect_length(r$fehler, 0)
})
