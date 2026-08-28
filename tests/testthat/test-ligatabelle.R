library(testthat)
source("../../RCode/league_details.R")

# build_league_table(): aktuelle Tabelle aus beendeten Spielen.
# Sortierung nach Bundesliga-Regel: Punkte, Tordifferenz, erzielte Tore.
# Nur beendete Spiele (FT/AET/PEN) zählen — insbesondere nicht die
# Zwischenstände laufender Spiele.

tabellen_details <- function() {
  make_details(
    fd_row(1, 1, "2026-08-28 18:30", "FT", 101, 102, 2, 1), # A schlägt B
    fd_row(2, 1, "2026-08-29 13:30", "FT", 103, 104, 1, 1), # C - D remis
    fd_row(3, 2, "2026-09-04 18:30", "FT", 102, 103, 3, 0), # B schlägt C
    fd_row(4, 2, "2026-09-05 13:30", "NS", 104, 101),       # offen
    fd_row(5, 3, "2026-09-12 13:30", "2H", 104, 102, 2, 0)  # live, zählt nicht
  )
}

test_that("Tabelle zählt nur beendete Spiele und sortiert nach Punkten und Tordifferenz", {
  tab <- build_league_table(tabellen_details(), make_test_teams())

  expect_s3_class(tab, "data.frame")
  expect_true(all(c(
    "platz", "team_id", "spiele", "tore", "gegentore", "tordifferenz", "punkte"
  ) %in% names(tab)))
  expect_equal(nrow(tab), 4)

  # B: 2 Spiele, 4:2 Tore, 3 Punkte; A: 1 Spiel, 2:1, 3 Punkte
  # -> B vor A (Tordifferenz +2 vor +1); D (0) vor C (-3) bei je 1 Punkt.
  expect_equal(tab$team_id, c(102, 101, 104, 103))
  expect_equal(tab$platz, 1:4)
  expect_equal(tab$punkte, c(3, 3, 1, 1))
  expect_equal(tab$spiele, c(2, 1, 1, 2))
  expect_equal(tab$tordifferenz, c(2, 1, 0, -3))
})

test_that("bei gleichen Punkten und gleicher Tordifferenz entscheiden die erzielten Tore", {
  details <- make_details(
    fd_row(1, 1, "2026-08-28 18:30", "FT", 101, 103, 3, 2), # A: 3:2
    fd_row(2, 1, "2026-08-29 13:30", "FT", 102, 104, 1, 0)  # B: 1:0
  )

  tab <- build_league_table(details, make_test_teams())

  # A und B je 3 Punkte, Tordifferenz +1 — A hat mehr Tore erzielt.
  expect_equal(tab$team_id[1:2], c(101, 102))
})

test_that("Teams ohne beendetes Spiel stehen mit Nullwerten in der Tabelle", {
  details <- make_details(
    fd_row(1, 1, "2026-08-28 18:30", "FT", 101, 102, 1, 0)
  )

  tab <- build_league_table(details, make_test_teams())

  expect_equal(nrow(tab), 4)
  reihe_c <- tab[tab$team_id == 103, ]
  expect_equal(reihe_c$spiele, 0)
  expect_equal(reihe_c$punkte, 0)
  expect_equal(reihe_c$tordifferenz, 0)
})
