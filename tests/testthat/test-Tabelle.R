# Test suite for Tabelle() -- aggregates a (partial) season matrix into
# each team's points, goals and rank. Tabelle() had no direct test before
# Stufe 4.5 (#212): it lives since #218 only indirectly behind the ELO walk
# and is gestubbt (not exercised) in test-elo_aggregation.R.

library(testthat)

source("../../RCode/Tabelle.R")

context("Tabelle")

test_that("Tabelle rechnet Punkte, Tore und Tordifferenz je Team", {
  # 3 Teams: 1-2 2:0, 2-3 1:1, 3-1 0:3 (Heim=Spalte1, Gast=Spalte2).
  season <- matrix(c(
    1, 2, 2, 0,
    2, 3, 1, 1,
    3, 1, 0, 3
  ), ncol = 4, byrow = TRUE)

  ergebnis <- Tabelle(season, numberTeams = 3, numberGames = 3)

  # Spalten: team_number, rank, goals, goalsAgainst, goalDiff, points.
  team1 <- ergebnis[ergebnis[, 1] == 1, ]
  team2 <- ergebnis[ergebnis[, 1] == 2, ]
  team3 <- ergebnis[ergebnis[, 1] == 3, ]

  expect_equal(unname(team1[c(3, 4, 5, 6)]), c(5, 0, 5, 6))
  expect_equal(unname(team2[c(3, 4, 5, 6)]), c(1, 3, -2, 1))
  expect_equal(unname(team3[c(3, 4, 5, 6)]), c(1, 4, -3, 1))
})

test_that("der Rang folgt Punkten, dann Tordifferenz, dann Toren", {
  season <- matrix(c(
    1, 2, 2, 0,
    2, 3, 1, 1,
    3, 1, 0, 3
  ), ncol = 4, byrow = TRUE)

  ergebnis <- Tabelle(season, numberTeams = 3, numberGames = 3)
  rang_je_team <- ergebnis[order(ergebnis[, 1]), 2]
  expect_equal(rang_je_team, c(1, 2, 3))

  # Gleiche Punkte, gleiche Tordifferenz, aber mehr Tore -> besserer Rang
  # (dritte Ebene des Rangwerts 10000*Punkte + 100*Diff + Tore, Z. 83).
  # Ueber die Anpassungsvektoren direkt gesetzt, ohne Spiele.
  leer <- matrix(numeric(0), nrow = 0, ncol = 4)
  ergebnis2 <- Tabelle(leer,
    numberTeams = 2, numberGames = 0,
    AdjPoints = c(5, 5), AdjGoalDiff = c(3, 3), AdjGoals = c(10, 8)
  )
  expect_equal(unname(ergebnis2[ergebnis2[, 1] == 1, 2]), 1)
  expect_equal(unname(ergebnis2[ergebnis2[, 1] == 2, 2]), 2)

  # Die drei Ebenen gegeneinander: Punkte schlagen Tordifferenz, auch wenn
  # die Tordifferenz das Gegenteil nahelegt.
  konflikt_punkte <- Tabelle(leer,
    numberTeams = 2, numberGames = 0,
    AdjPoints = c(4, 3), AdjGoalDiff = c(-20, 20)
  )
  expect_equal(konflikt_punkte[order(konflikt_punkte[, 1]), 2], c(1, 2))

  # Tordifferenz schlaegt Tore, auch wenn die Tore das Gegenteil nahelegen.
  konflikt_diff <- Tabelle(leer,
    numberTeams = 2, numberGames = 0,
    AdjPoints = c(1, 1), AdjGoalDiff = c(1, 0), AdjGoals = c(2, 10)
  )
  expect_equal(konflikt_diff[order(konflikt_diff[, 1]), 2], c(1, 2))
})

test_that("gleiche Rangwerte teilen sich den besseren Rang (ties.method max)", {
  # Team 1 klar besser, Team 2 und 3 identisch (und schlechter) -- die
  # beiden Letzten teilen sich Rang 2, Rang 3 taucht nicht auf.
  leer <- matrix(numeric(0), nrow = 0, ncol = 4)
  ergebnis <- Tabelle(leer, numberTeams = 3, numberGames = 0, AdjPoints = c(3, 1, 1))

  rang_je_team <- ergebnis[order(ergebnis[, 1]), 2]
  expect_equal(rang_je_team, c(1, 2, 2))
  expect_false(3 %in% rang_je_team)
})

test_that("Anpassungsvektoren gehen als Vorbelastung ein", {
  season <- matrix(c(
    1, 2, 2, 0,
    2, 3, 1, 1,
    3, 1, 0, 3
  ), ncol = 4, byrow = TRUE)

  # Ohne Anpassung (vorheriger Fall): Team 1 hat 6 Punkte, 5 Tore, +5 Diff.
  ergebnis <- Tabelle(season,
    numberTeams = 3, numberGames = 3,
    AdjPoints = c(-3, 0, 0), AdjGoals = c(7, 0, 0), AdjGoalDiff = c(10, 0, 0)
  )

  team1 <- ergebnis[ergebnis[, 1] == 1, ]
  expect_equal(unname(team1[6]), 6 - 3)
  expect_equal(unname(team1[3]), 5 + 7)
  expect_equal(unname(team1[5]), 5 + 10)
})

test_that("ohne Spiele stehen alle Teams auf ihren Anpassungen und teilen Rang 1", {
  leer <- matrix(numeric(0), nrow = 0, ncol = 4)
  ergebnis <- Tabelle(leer, numberTeams = 3, numberGames = 0)

  expect_equal(unname(ergebnis[, 6]), c(0, 0, 0))
  expect_equal(unname(ergebnis[, 2]), c(1, 1, 1))
})

test_that("ein Team ohne Spiel behaelt seine Anpassung", {
  # Nur Spiel 1-2 (3:1); Team 3 spielt nicht mit.
  season <- matrix(c(1, 2, 3, 1), ncol = 4, byrow = TRUE)

  ergebnis <- Tabelle(season,
    numberTeams = 3, numberGames = 1,
    AdjGoals = c(0, 0, 4), AdjGoalsAgainst = c(0, 0, 6), AdjGoalDiff = c(0, 0, -50)
  )

  team3 <- ergebnis[ergebnis[, 1] == 3, ]
  expect_equal(unname(team3[c(3, 4, 5, 6)]), c(4, 6, -50, 0))
  expect_equal(unname(team3[2]), 3) # letzter Rang
})
