library(testthat)
source("../../RCode/league_details.R")

# Issue #157: Gewertete Spiele (api-football `AWD` = Wertung am gruenen Tisch,
# `WO` = kampflos) fielen in der Fensterung unter "offen".
#
# Entschiedene Semantik: Ein Wertungsergebnis ist sportrechtlich ein Ergebnis
# und zaehlt fuer die TABELLE -- aber es sagt nichts ueber Spielstaerke und
# darf deshalb den ELO-WALK nicht beruehren.
#
# Daraus folgt je Stelle:
#
#   Fensterung/Anzeige   AWD zaehlt wie beendet (Rueckblick, Spieltag-Abschluss)
#   Ligatabelle          AWD zaehlt (Punkte, Tore)
#   ELO-Walk             AWD wird uebersprungen
#
# Der ELO-Teil ist der heikle: Der Seam zum Rust-Server ist TORBASIERT --
# `build_league_details_payload()` sendet Tore nur bei STATUS_BEENDET, und
# Rust leitet "gespielt" allein aus der Praesenz beider Tore ab. Wer AWD-Tore
# mitsendet, bekommt automatisch auch das ELO-Update. Deshalb pruefen die
# Tests hier BEIDE Richtungen: Tabelle ja, ELO nein.

# --- Fensterung: classify_matchday_status -----------------------------------

test_that("ein gewertetes Spiel schliesst den Spieltag ab", {
  # Der eigentliche Schaden des Bugs: Solange AWD als "offen" galt, wurde ein
  # Spieltag mit einem Wertungsspiel NIE abgeschlossen -- der Rueckblick-Anker
  # fror ein und der Ausblick zeigte dauerhaft auf die alte Runde.
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "FT", 101, 102, 2, 1),
    fd_row(2, 1, "2026-08-01 15:30", "AWD", 103, 104, 3, 0)
  )

  status <- classify_matchday_status(details)

  expect_equal(unname(status[["1"]]), "abgeschlossen")
})

test_that("WO wird wie AWD behandelt", {
  # Kampflos (Walkover) ist derselbe Fall; beide stehen in STATUS_AWARDED.
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "FT", 101, 102, 2, 1),
    fd_row(2, 1, "2026-08-01 15:30", "WO", 103, 104, 3, 0)
  )

  expect_equal(unname(classify_matchday_status(details)[["1"]]), "abgeschlossen")
})

test_that("ein gewertetes Spiel allein macht den Spieltag begonnen", {
  # AWD zaehlt als beendet -- ein Spieltag, der nur daraus besteht, ist
  # abgeschlossen und nicht etwa "ausstehend".
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "AWD", 101, 102, 3, 0)
  )

  expect_equal(unname(classify_matchday_status(details)[["1"]]), "abgeschlossen")
})

test_that("ein laufender Spieltag bleibt laufend, wenn ein AWD dazukommt", {
  # Gegenprobe: AWD darf nicht dazu fuehren, dass ein Spieltag mit noch
  # offenen Spielen faelschlich abgeschlossen wird.
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "AWD", 101, 102, 3, 0),
    fd_row(2, 1, "2026-08-01 15:30", "NS", 103, 104)
  )

  expect_equal(unname(classify_matchday_status(details)[["1"]]), "laufend")
})

# --- Fensterung: Rueckblick und Ausblick ------------------------------------

test_that("ein gewertetes Spiel erscheint im Rueckblick", {
  # Ohne diesen Fix fehlt das Spiel dort komplett -- Leser saehen einen
  # Punktestand, dessen Spiel nirgends auftaucht.
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "FT", 101, 102, 2, 1),
    fd_row(2, 1, "2026-08-01 15:30", "AWD", 103, 104, 3, 0)
  )

  rb <- rueckblick_matches(details)

  expect_equal(nrow(rb), 2)
  expect_true(2 %in% rb$fixture_id)
})

test_that("ein gewertetes Spiel erscheint NICHT im Ausblick", {
  # Vorher blieb es dort dauerhaft stehen -- samt 1/X/2 und Score-Matrix fuer
  # ein Spiel, das nie stattfindet.
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "FT", 101, 102, 2, 1),
    fd_row(2, 1, "2026-08-01 15:30", "AWD", 103, 104, 3, 0),
    fd_row(3, 2, "2026-08-08 13:00", "NS", 101, 103),
    fd_row(4, 2, "2026-08-08 15:30", "NS", 102, 104)
  )

  ab <- ausblick_matches(details)

  expect_false(2 %in% ab$fixture_id)
  expect_setequal(ab$fixture_id, c(3, 4))
})

test_that("ein gewertetes Spiel bestimmt das Ausblick-Fenster nicht mehr", {
  # `offen_status` trieb sechs Stellen in ausblick_matches(), darunter das
  # Fensterende (max kickoff der offenen Spiele des Ziel-Spieltags). Ein
  # frueher angesetztes AWD-Spiel einer alten Runde konnte das Fenster
  # verzerren.
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "FT", 101, 102, 2, 1),
    fd_row(2, 1, "2026-08-01 15:30", "FT", 103, 104, 1, 1),
    fd_row(3, 2, "2026-08-08 13:00", "AWD", 101, 103, 3, 0),
    fd_row(4, 2, "2026-08-08 15:30", "NS", 102, 104)
  )

  ab <- ausblick_matches(details)

  expect_equal(ab$fixture_id, 4)
})

# --- Ligatabelle ------------------------------------------------------------

test_that("die Ligatabelle zaehlt das Wertungsergebnis", {
  # Sportrechtlich eindeutig: Punkte und Tore zaehlen.
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "AWD", 101, 102, 3, 0)
  )
  teams <- make_test_teams()

  tab <- build_league_table(details, teams)
  heim <- tab[tab$team_id == 101, ]
  gast <- tab[tab$team_id == 102, ]

  expect_equal(heim$punkte, 3)
  expect_equal(heim$tore, 3)
  expect_equal(heim$gegentore, 0)
  expect_equal(heim$spiele, 1)
  expect_equal(gast$punkte, 0)
  expect_equal(gast$tore, 0)
  expect_equal(gast$gegentore, 3)
  expect_equal(gast$spiele, 1)
})

test_that("die Ligatabelle uebersteht ein gewertetes Spiel ohne Tore", {
  # api-football liefert bei AWD ueblicherweise 3:0, aber nicht garantiert.
  # Ohne NA-Schutz erzeugte die Summenbildung NA in Punkten und Toren und
  # damit eine unbrauchbare Tabelle -- schlimmer als das fehlende Spiel.
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "FT", 101, 102, 2, 1),
    fd_row(2, 1, "2026-08-01 15:30", "AWD", 103, 104)
  )
  teams <- make_test_teams()

  tab <- build_league_table(details, teams)

  expect_false(any(is.na(tab$punkte)))
  expect_false(any(is.na(tab$tore)))
  expect_false(any(is.na(tab$gegentore)))
  # Das torlose Wertungsspiel zaehlt fuer niemanden als absolviertes Spiel.
  expect_equal(tab$spiele[tab$team_id == 103], 0)
  expect_equal(tab$spiele[tab$team_id == 104], 0)
  # Die uebrige Tabelle bleibt korrekt.
  expect_equal(tab$punkte[tab$team_id == 101], 3)
})

# --- ELO: der Seam zum Rust-Server ------------------------------------------

test_that("das Wertungsergebnis geht NICHT an den ELO-Walk", {
  # Kern der Modellentscheidung. Der Seam ist torbasiert: Rust leitet
  # "gespielt" allein aus der Praesenz beider Tore ab (league_details/mod.rs).
  # Werden AWD-Tore mitgesendet, passt Rust automatisch das ELO an -- genau
  # das soll nicht passieren.
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "FT", 101, 102, 2, 1),
    fd_row(2, 1, "2026-08-01 15:30", "AWD", 103, 104, 3, 0)
  )
  teams <- make_test_teams()

  payload <- build_league_details_payload(details, teams)

  # Zeile 1 (FT) traegt Tore, Zeile 2 (AWD) nicht.
  expect_equal(payload$schedule[[1]][[3]], 2)
  expect_equal(payload$schedule[[1]][[4]], 1)
  expect_null(payload$schedule[[2]][[3]])
  expect_null(payload$schedule[[2]][[4]])
})

test_that("auch ein WO-Spiel bleibt aus dem ELO-Walk heraus", {
  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "WO", 101, 102, 3, 0)
  )

  payload <- build_league_details_payload(details, make_test_teams())

  expect_null(payload$schedule[[1]][[3]])
  expect_null(payload$schedule[[1]][[4]])
})

# --- Simulationspfad: transform_data ----------------------------------------
# (eigene Datei-Sektion, weil transform_data.R separat gesourct wird)

test_that("transform_data behaelt die Tore eines gewerteten Spiels", {
  # Bisher setzte transform_data() alles ausser FT/AET/PEN auf NA -- die
  # Simulation wuerfelte das Wertungsspiel in jedem Durchlauf neu aus, obwohl
  # es sportrechtlich entschieden ist. Fuer die ENDTABELLE der Simulation
  # muss das Ergebnis feststehen.
  #
  # Der ELO-Walk der Engine darf es trotzdem nicht sehen -- das leistet das
  # Rust-Flag (siehe cargo-Tests), nicht diese Funktion.
  source("../../RCode/transform_data.R", local = TRUE)

  fixtures <- tibble::tibble(
    league = data.frame(round = c("Regular Season - 1", "Regular Season - 1"),
                        stringsAsFactors = FALSE),
    teams = list(
      data.frame(home = I(list(data.frame(id = 101, name = "A"))),
                 away = I(list(data.frame(id = 102, name = "B")))),
      data.frame(home = I(list(data.frame(id = 103, name = "C"))),
                 away = I(list(data.frame(id = 104, name = "D"))))
    ),
    goals = list(data.frame(home = 2, away = 1), data.frame(home = 3, away = 0)),
    fixture = list(
      data.frame(id = 1, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 2, status = I(list(data.frame(short = "AWD"))))
    )
  )
  teams <- data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    InitialELO = c(1500, 1500, 1500, 1500),
    stringsAsFactors = FALSE
  )

  result <- transform_data(fixtures, teams)

  expect_equal(result$ToreHeim, c(2, 3))
  expect_equal(result$ToreGast, c(1, 0))
})

test_that("transform_data laesst offene und verschobene Spiele weiter offen", {
  # Verhaltensneutralitaet: Nur AWD/WO kommt dazu, NS und PST bleiben NA.
  source("../../RCode/transform_data.R", local = TRUE)

  fixtures <- tibble::tibble(
    league = data.frame(round = rep("Regular Season - 1", 3),
                        stringsAsFactors = FALSE),
    teams = list(
      data.frame(home = I(list(data.frame(id = 101, name = "A"))),
                 away = I(list(data.frame(id = 102, name = "B")))),
      data.frame(home = I(list(data.frame(id = 103, name = "C"))),
                 away = I(list(data.frame(id = 104, name = "D")))),
      data.frame(home = I(list(data.frame(id = 101, name = "A"))),
                 away = I(list(data.frame(id = 103, name = "C"))))
    ),
    goals = list(data.frame(home = 2, away = 1), data.frame(home = NA, away = NA),
                 data.frame(home = NA, away = NA)),
    fixture = list(
      data.frame(id = 1, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 2, status = I(list(data.frame(short = "NS")))),
      data.frame(id = 3, status = I(list(data.frame(short = "PST"))))
    )
  )
  teams <- data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    InitialELO = c(1500, 1500, 1500, 1500),
    stringsAsFactors = FALSE
  )

  result <- transform_data(fixtures, teams)

  expect_equal(result$ToreHeim[1], 2)
  expect_true(all(is.na(result$ToreHeim[2:3])))
  expect_true(all(is.na(result$ToreGast[2:3])))
})
