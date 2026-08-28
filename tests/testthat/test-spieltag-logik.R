library(testthat)
source("../../RCode/league_details.R")

# Spieltag-Klassifikation und Rückblick-/Ausblick-Fensterung.
#
# Begriffe (CONTEXT.md, verfeinert):
# - abgeschlossen: >= 1 Spiel beendet, kein Spiel live, jedes Spiel beendet
#   oder verschoben (PST/CANC/TBD/ABD). Verschobene halten nicht offen.
# - laufend: begonnen (>= 1 beendet/live), aber nicht abgeschlossen.
# - ausstehend: noch nicht begonnen.
# - aktueller Spieltag: der HÖCHSTE begonnene. Ein neu terminiertes
#   Nachholspiel macht seine alte Runde nicht wieder zum aktuellen Spieltag.
# - Rückblick: alle beendeten Spiele ab Beginn (früheste Anstoßzeit) des
#   zuletzt abgeschlossenen Spieltags; ältere Runden => nachholspiel = TRUE.
# - Ausblick: Ziel = laufender Spieltag, sonst kleinste Runde über dem
#   aktuellen mit offenen Spielen; enthalten sind alle offenen, nicht
#   verschobenen Spiele mit Anstoß bis zum letzten offenen Spiel des Ziels.

# --- Szenario 1: Samstagmittag, Spieltag läuft --------------------------------
# Runde 12 komplett (20.-22.11.), Runde 13: Freitagsspiel beendet, zwei offen.
samstagmittag <- function() {
  make_details(
    fd_row(1, 12, "2026-11-20 19:30", "FT", 101, 102, 2, 1),
    fd_row(2, 12, "2026-11-21 14:30", "FT", 103, 104, 0, 0),
    fd_row(3, 12, "2026-11-22 16:30", "FT", 101, 103, 1, 3),
    fd_row(4, 13, "2026-11-27 19:30", "FT", 104, 101, 2, 2),
    fd_row(5, 13, "2026-11-28 14:30", "NS", 102, 103),
    fd_row(6, 13, "2026-11-29 16:30", "NS", 104, 102)
  )
}

test_that("laufender Spieltag: begonnene Runde mit offenen Spielen", {
  status <- classify_matchday_status(samstagmittag())

  expect_equal(unname(status[["12"]]), "abgeschlossen")
  expect_equal(unname(status[["13"]]), "laufend")
  expect_equal(current_matchday(samstagmittag()), 13L)
})

test_that("Rückblick während eines laufenden Spieltags: letzter abgeschlossener plus gespielte des laufenden", {
  rb <- rueckblick_matches(samstagmittag())

  expect_equal(rb$fixture_id, c(1, 2, 3, 4)) # chronologisch
  expect_true(all(rb$nachholspiel == FALSE))
})

test_that("Ausblick während eines laufenden Spieltags: dessen offene Spiele", {
  ab <- ausblick_matches(samstagmittag())

  expect_equal(ab$fixture_id, c(5, 6))
  expect_true(all(ab$nachholspiel == FALSE))
})

# --- Szenario 2: Montag, Nachholspiel am Dienstag terminiert ------------------
# Runde 5 hat ein neu angesetztes Nachholspiel (Di 1.12.), Runde 13 ist
# komplett, Runde 14 steht an (4.-6.12.).
montag_mit_nachholspiel <- function() {
  make_details(
    fd_row(10, 5, "2026-10-03 14:30", "FT", 101, 102, 1, 0),
    fd_row(11, 5, "2026-10-04 14:30", "FT", 103, 104, 2, 2),
    fd_row(12, 5, "2026-12-01 17:30", "NS", 102, 103), # Nachholspiel
    fd_row(13, 13, "2026-11-27 19:30", "FT", 104, 101, 0, 1),
    fd_row(14, 13, "2026-11-28 14:30", "FT", 102, 104, 3, 1),
    fd_row(15, 13, "2026-11-29 16:30", "FT", 103, 101, 1, 1),
    fd_row(16, 14, "2026-12-04 19:30", "NS", 101, 102),
    fd_row(17, 14, "2026-12-05 14:30", "NS", 104, 103),
    fd_row(18, 14, "2026-12-06 16:30", "NS", 102, 101)
  )
}

test_that("aktueller Spieltag ist der höchste begonnene, nicht die Nachholspiel-Runde", {
  expect_equal(current_matchday(montag_mit_nachholspiel()), 13L)

  status <- classify_matchday_status(montag_mit_nachholspiel())
  expect_equal(unname(status[["13"]]), "abgeschlossen")
  expect_equal(unname(status[["14"]]), "ausstehend")
})

test_that("Rückblick nach abgeschlossenem Spieltag: genau dessen Spiele", {
  rb <- rueckblick_matches(montag_mit_nachholspiel())

  expect_equal(rb$fixture_id, c(13, 14, 15))
  expect_true(all(rb$nachholspiel == FALSE))
})

test_that("Ausblick nimmt früher angesetzte Nachholspiele mit und markiert sie", {
  ab <- ausblick_matches(montag_mit_nachholspiel())

  # chronologisch: Nachholspiel (Di) vor dem 14. Spieltag (Fr-So)
  expect_equal(ab$fixture_id, c(12, 16, 17, 18))
  expect_equal(ab$nachholspiel, c(TRUE, FALSE, FALSE, FALSE))
})

# --- Szenario 3: verschobenes Spiel hält den Spieltag nicht offen -------------
verschoben <- function() {
  make_details(
    fd_row(20, 13, "2026-11-27 19:30", "FT", 101, 102, 2, 0),
    fd_row(21, 13, "2026-11-28 14:30", "FT", 103, 104, 1, 1),
    fd_row(22, 13, "2026-11-28 14:30", "PST", 102, 103), # verschoben, Termin offen
    fd_row(23, 14, "2026-12-05 14:30", "NS", 104, 101)
  )
}

test_that("PST zählt nicht als offen: Spieltag ist abgeschlossen", {
  status <- classify_matchday_status(verschoben())

  expect_equal(unname(status[["13"]]), "abgeschlossen")
})

test_that("verschobene Spiele erscheinen nicht im Ausblick", {
  ab <- ausblick_matches(verschoben())

  expect_equal(ab$fixture_id, 23)
})

# --- Szenario 4: frisch gespieltes Nachholspiel erscheint im Rückblick --------
nachholspiel_gespielt <- function() {
  make_details(
    fd_row(30, 5, "2026-10-03 14:30", "FT", 101, 102, 1, 0),
    fd_row(31, 5, "2026-10-04 14:30", "FT", 103, 104, 2, 2),
    fd_row(32, 5, "2026-12-02 17:30", "FT", 102, 103, 0, 2), # Nachholspiel, Mi
    fd_row(33, 13, "2026-11-27 19:30", "FT", 104, 101, 0, 1),
    fd_row(34, 13, "2026-11-28 14:30", "FT", 102, 104, 3, 1),
    fd_row(35, 13, "2026-11-29 16:30", "FT", 103, 101, 1, 1),
    fd_row(36, 14, "2026-12-05 14:30", "NS", 104, 103)
  )
}

test_that("gespieltes Nachholspiel steht markiert im Rückblick, alte Spiele nicht", {
  rb <- rueckblick_matches(nachholspiel_gespielt())

  # chronologisch: 13. Spieltag (27.-29.11.), dann das Nachholspiel (2.12.)
  expect_equal(rb$fixture_id, c(33, 34, 35, 32))
  expect_equal(rb$nachholspiel, c(FALSE, FALSE, FALSE, TRUE))
})

# --- Szenario 5: Saisonstart --------------------------------------------------
saisonstart <- function() {
  make_details(
    fd_row(40, 1, "2026-08-28 18:30", "NS", 101, 102),
    fd_row(41, 1, "2026-08-29 13:30", "NS", 103, 104),
    fd_row(42, 2, "2026-09-04 18:30", "NS", 102, 103)
  )
}

test_that("Saisonstart: kein aktueller Spieltag, leerer Rückblick, Ausblick = 1. Spieltag", {
  expect_true(is.na(current_matchday(saisonstart())))

  rb <- rueckblick_matches(saisonstart())
  expect_equal(nrow(rb), 0)

  ab <- ausblick_matches(saisonstart())
  expect_equal(ab$fixture_id, c(40, 41))
})

# --- Szenario 6: live ---------------------------------------------------------
live_spieltag <- function() {
  make_details(
    fd_row(50, 13, "2026-11-27 19:30", "FT", 101, 102, 2, 1),
    fd_row(51, 13, "2026-11-28 14:30", "2H", 103, 104, 1, 0), # läuft gerade
    fd_row(52, 13, "2026-11-29 16:30", "NS", 102, 103)
  )
}

test_that("laufende Spiele erscheinen weder im Rückblick noch im Ausblick", {
  status <- classify_matchday_status(live_spieltag())
  expect_equal(unname(status[["13"]]), "laufend")

  rb <- rueckblick_matches(live_spieltag())
  expect_equal(rb$fixture_id, 50)

  ab <- ausblick_matches(live_spieltag())
  expect_equal(ab$fixture_id, 52)
})

test_that("live_matches liefert laufende Spiele mit Zwischenstand, chronologisch", {
  # Planergänzung 2026-08-28: Laufende Spiele werden berichtet (Zwischenstand),
  # aber ohne Prognose; der Hinweis "Prognosen werden während des Spiels nicht
  # aktualisiert" ist Sache des Renderers.
  details <- make_details(
    fd_row(70, 13, "2026-11-28 16:30", "HT", 102, 104, 0, 0),
    fd_row(71, 13, "2026-11-28 14:30", "2H", 103, 101, 1, 2),
    fd_row(72, 13, "2026-11-27 19:30", "FT", 101, 102, 2, 1),
    fd_row(73, 13, "2026-11-29 16:30", "NS", 104, 103)
  )

  lv <- live_matches(details)

  expect_equal(lv$fixture_id, c(71, 70)) # chronologisch nach Anstoß
  expect_equal(lv$goals_home, c(1, 0))   # Zwischenstände bleiben erhalten
  expect_equal(lv$goals_away, c(2, 0))
})

test_that("live_matches ist leer, wenn kein Spiel läuft", {
  lv <- live_matches(samstagmittag())

  expect_equal(nrow(lv), 0)
})

test_that("Spieltag mit ausschließlich Live-Spielen gilt als laufend", {
  details <- make_details(
    fd_row(60, 1, "2026-08-28 18:30", "1H", 101, 102, 0, 0),
    fd_row(61, 1, "2026-08-28 18:30", "HT", 103, 104, 1, 1)
  )

  status <- classify_matchday_status(details)
  expect_equal(unname(status[["1"]]), "laufend")
  expect_equal(current_matchday(details), 1L)
})
