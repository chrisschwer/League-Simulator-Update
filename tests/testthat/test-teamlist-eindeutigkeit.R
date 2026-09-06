library(testthat)
source("../../RCode/transform_data.R")

# Phase 0 des Ligen-Ausbaus, zweites Schutznetz: globale Kurznamen-Eindeutigkeit.
#
# transform_data() macht aus jedem ShortText einen SPALTENNAMEN des
# Simulations-Data-Frames (siehe die Schleife über unique(TeamHeim, TeamGast)).
# Kollidieren zwei Kurznamen, entstehen doppelte Spaltennamen -- und damit
# stillschweigend vertauschte Teams. R wirft dabei keinen Fehler.
#
# Bisher wird Eindeutigkeit nur PRO LIGA hergestellt (generate_unique_short_name()
# bekommt die Namen einer Liga als existing_short_names, season_processor.R ruft
# es je Liga in der Schleife auf). Bei 56 Teams in drei Ligen ging das gut; bei
# 237 Teams in zehn Ligen -- darunter rund 30 Zweitvertretungen -- sind
# Kollisionen über Ligagrenzen hinweg der Normalfall.
#
# TeamList_2026.csv ist heute global kollisionsfrei (237/237). Genau das soll
# beim Laden geprüft werden, damit es so bleibt: eine künftig eingespielte Liste
# mit Kollision muss laut scheitern, nicht leise falsch rechnen.
#
# Geprüft wird load_team_list() -- die Ladefunktion, die read.csv() in
# update_all_leagues_loop.R:87 ersetzt.

schreibe_teamlist <- function(zeilen) {
  pfad <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame())
  writeLines(c("TeamID;ShortText;Promotion;InitialELO;League;Region;Name", zeilen),
             pfad)
  pfad
}

test_that("load_team_list lädt eine kollisionsfreie Liste", {
  pfad <- schreibe_teamlist(c(
    "157;FCB;0;2057.2;78;;Bayern München",
    "165;BVB;0;1876.1;78;;Borussia Dortmund",
    "1320;FCE;0;1265.4;79;Nordost;Energie Cottbus"
  ))

  teams <- load_team_list(pfad)

  expect_equal(nrow(teams), 3)
  expect_equal(teams$ShortText, c("FCB", "BVB", "FCE"))
  # Die Spalten müssen unverändert durchgereicht werden -- transform_data()
  # merged über TeamID und liest InitialELO.
  expect_true(all(c("TeamID", "ShortText", "InitialELO") %in% names(teams)))
  expect_true(is.numeric(teams$InitialELO))
})

test_that("load_team_list bricht bei kollidierenden Kurznamen ab", {
  # Zwei Teams aus VERSCHIEDENEN Ligen mit demselben Kurznamen -- genau der
  # Fall, den die ligaweise Vergabe nicht verhindert.
  pfad <- schreibe_teamlist(c(
    "157;FCB;0;2057.2;78;;Bayern München",
    "9001;FCB;0;950.0;83;Bayern;FC Bamberg"
  ))

  # Präzise auf den Kollisionsbefund prüfen, nicht auf irgendeinen Fehler --
  # sonst besteht der Test auch, solange load_team_list() gar nicht existiert.
  err <- expect_error(load_team_list(pfad))
  expect_match(conditionMessage(err), "FCB")
  expect_match(conditionMessage(err), regexp = "eindeutig|Kollision|doppelt|duplicate",
               ignore.case = TRUE)
})

test_that("load_team_list nennt alle kollidierenden Kurznamen", {
  # Bei mehreren Kollisionen muss die Meldung sie alle nennen, sonst wird das
  # Aufräumen zum Ratespiel über mehrere Läufe.
  pfad <- schreibe_teamlist(c(
    "157;FCB;0;2057.2;78;;Bayern München",
    "9001;FCB;0;950.0;83;Bayern;FC Bamberg",
    "165;BVB;0;1876.1;78;;Borussia Dortmund",
    "9002;BVB;0;930.0;87;West;BV Bocholt"
  ))

  err <- expect_error(load_team_list(pfad))
  expect_match(conditionMessage(err), "FCB")
  expect_match(conditionMessage(err), "BVB")
  expect_match(conditionMessage(err), regexp = "eindeutig|Kollision|doppelt|duplicate",
               ignore.case = TRUE)
})

test_that("load_team_list bricht bei doppelten TeamIDs ab", {
  # Eine doppelte TeamID lässt den merge() in transform_data() Zeilen
  # vervielfachen -- ebenfalls ein stiller Fehler.
  pfad <- schreibe_teamlist(c(
    "157;FCB;0;2057.2;78;;Bayern München",
    "157;FCX;0;950.0;83;Bayern;Doppelgänger"
  ))

  err <- expect_error(load_team_list(pfad))
  expect_match(conditionMessage(err), "157")
  expect_match(conditionMessage(err), regexp = "TeamID|eindeutig|doppelt|duplicate",
               ignore.case = TRUE)
})

test_that("load_team_list akzeptiert vierstellige Kurznamen", {
  # Die neuen Ligen brauchen vier Zeichen (WACA, BAYB, FR2B). Ein Loader, der
  # weiter auf drei Zeichen besteht, würde 52 der 237 Einträge ablehnen.
  pfad <- schreibe_teamlist(c(
    "9003;WACA;0;900.0;83;Bayern;Wacker Burghausen",
    "9004;BAYB;0;890.0;83;Bayern;Bayreuth",
    "9005;FR2B;-50;1200.0;1034;;Eintracht Frankfurt II W"
  ))

  teams <- load_team_list(pfad)

  expect_equal(nrow(teams), 3)
  expect_equal(teams$ShortText, c("WACA", "BAYB", "FR2B"))
})

test_that("load_team_list akzeptiert die echte TeamList_2026", {
  # Der scharfe Test: die produktive Liste mit 237 Teams über zehn Ligen muss
  # durchlaufen. Schlägt das fehl, ist entweder die Prüfung zu streng oder die
  # Liste kaputt -- beides muss auffallen.
  pfad <- test_path("..", "..", "RCode", "TeamList_2026.csv")
  skip_if_not(file.exists(pfad), "TeamList_2026.csv nicht gefunden")

  teams <- load_team_list(pfad)

  expect_equal(nrow(teams), 237)
  expect_false(any(duplicated(teams$ShortText)))
  expect_false(any(duplicated(teams$TeamID)))
})

test_that("load_team_list meldet eine fehlende Datei verständlich", {
  # Der Dateiname muss in der Meldung stehen, sonst ist im Betrieb nicht
  # erkennbar, welche Liste gesucht wurde.
  err <- expect_error(load_team_list("gibt/es/nicht.csv"))
  expect_match(conditionMessage(err), "gibt/es/nicht.csv", fixed = TRUE)
})
