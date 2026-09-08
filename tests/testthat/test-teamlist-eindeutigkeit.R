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
# Maßgeblich ist dabei die WECHSELGEMEINSCHAFT (ADR 0004), nicht die gesamte
# Liste: transform_data() wird je Liga aufgerufen, und Herren (78, 79, 80,
# 83-87) und Frauen (82, 1034) tauschen nie Teams. Ein Kurzname, den beide
# benutzen, kann nie in denselben Data-Frame geraten -- er ist sogar
# erwünscht, damit die Frauenmannschaft eines Vereins dasselbe Kürzel trägt
# wie die Herrenmannschaft.
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
  # Zwei Teams DERSELBEN Liga mit demselben Kurznamen. Hier wird ShortText
  # zum Spaltennamen des Simulations-Data-Frames -- eine Dopplung
  # vertauschte die Teams stillschweigend.
  #
  # Der Test pruefte bis September 2026 zwei VERSCHIEDENE Ligen (78 und 83).
  # Das ist seit Regel 3 erlaubt: Wo ein Kuerzel fuer einen Verein
  # eingefuehrt ist, bekommt er es, auch wenn ein anderer Verein in einer
  # anderen Liga dasselbe traegt.
  pfad <- schreibe_teamlist(c(
    "157;FCB;0;2057.2;78;;Bayern München",
    "9001;FCB;0;1500.0;78;;FC Bamberg"
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
    "9001;FCB;0;950.0;78;Bayern;FC Bamberg",
    "165;BVB;0;1876.1;78;;Borussia Dortmund",
    "9002;BVB;0;930.0;78;West;BV Bocholt"
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

  # 237 aus der Kalibrierung + 10 fuer die Saison 2026 nachgetragene Teams
  # (zwei Drittliga-Absteiger, acht Aufsteiger aus Oberligen).
  expect_equal(nrow(teams), 247)
  expect_false(any(duplicated(teams$TeamID)))

  # Eindeutig je LIGA, nicht je Wechselgemeinschaft: Seit Regel 3
  # (September 2026) tragen auch zwei Herren-Vereine dasselbe Kuerzel, wenn
  # beide darunter bekannt sind -- VFB (Stuttgart 78 / Luebeck 84), FCH
  # (Heidenheim 79 / Hansa Rostock 80), RWE (Essen 80 / Erfurt 85).
  #
  # Dieser Test prueft bis dahin je Wechselgemeinschaft. Er lief gruen,
  # weil die TeamList damals keine Herren-Dopplung enthielt -- die Luecke
  # fiel erst auf, als die neuen Kuerzel eingetragen wurden.
  for (grp in split(teams$ShortText, teams$League)) {
    expect_false(any(duplicated(grp)))
  }

  # Die harte Ausnahme gilt weiter: Nord, Nordost und Bayern bleiben
  # untereinander frei, weil zwei von ihnen jaehrlich die Aufstiegsspiele
  # bestreiten und die Doppelsumme ueber Namen zuordnet.
  playoff <- teams$ShortText[teams$League %in% c(83, 84, 85)]
  expect_false(any(duplicated(playoff)))

  expect_true(any(duplicated(teams$ShortText)))
})

test_that("load_team_list meldet eine fehlende Datei verständlich", {
  # Der Dateiname muss in der Meldung stehen, sonst ist im Betrieb nicht
  # erkennbar, welche Liste gesucht wurde.
  err <- expect_error(load_team_list("gibt/es/nicht.csv"))
  expect_match(conditionMessage(err), "gibt/es/nicht.csv", fixed = TRUE)
})

test_that("load_team_list erlaubt gleiche Kurznamen über Wechselgemeinschaften", {
  # Der Verein stellt beide Mannschaften: dasselbe Kürzel ist gewollt, weil
  # transform_data() je Liga aufgerufen wird und Herren- und Frauen-Ligen nie
  # Teams tauschen (ADR 0004). Auf den Seiten überschneiden sie sich nicht.
  pfad <- schreibe_teamlist(c(
    "168;SCF;0;1650.0;78;;SC Freiburg",
    "9010;SCF;0;1600.0;82;;SC Freiburg W",
    "173;RBL;0;1780.0;78;;RB Leipzig",
    "9011;RBL;0;1400.0;1034;;RB Leipzig W"
  ))

  teams <- load_team_list(pfad)

  expect_equal(nrow(teams), 4)
  expect_equal(sum(teams$ShortText == "SCF"), 2)
})

test_that("load_team_list erlaubt gleiche Kurznamen in den beiden Frauen-Ligen", {
  # Seit Regel 3 (September 2026) ist auch das erlaubt: 82 und 1034 sind
  # verschiedene Ligen und stehen auf getrennten Seiten. Steigt eines der
  # beiden Teams auf oder ab, wird der Konflikt dann geloest -- die
  # Alternative waere, jede denkbare kuenftige Paarung heute zu verbieten.
  #
  # Der Test verlangte bis dahin einen Abbruch. Christoph hat die Regel
  # bewusst auf "eindeutig je Liga" gestellt, mit der einzigen Ausnahme
  # Nord/Nordost/Bayern (s. u.).
  pfad <- schreibe_teamlist(c(
    "9012;WOL;0;1700.0;82;;VfL Wolfsburg W",
    "9013;WOL;0;1300.0;1034;;Werder Oldenburg W"
  ))

  teams <- load_team_list(pfad)
  expect_equal(nrow(teams), 2)
})

# --- Regel 3: Dopplungen zwischen Ligen sind zulaessig ----------------------
#
# Entscheidung Christoph (2026-09-09): Wo ein Kuerzel fuer einen Verein
# eingefuehrt ist, bekommt er es -- auch wenn ein anderer Verein in einer
# ANDEREN Liga dasselbe traegt. Der VfB ist Stuttgart, in der RL Nord ist der
# VfB Luebeck; der FCK ist Kaiserslautern. Massgeblich ist nicht die
# Haeufigkeit des Namensbestandteils, sondern welcher Verein unter dem
# Kuerzel bekannt ist.
#
# Bis dahin galt Eindeutigkeit je WECHSELGEMEINSCHAFT. Das war zu streng: Es
# verbot VFB fuer Stuttgart (78) neben Luebeck (84), obwohl beide Ansprueche
# belegt sind und die Ligen auf getrennten Seiten stehen.
#
# Die Grenze bleibt scharf, wo sie zaehlt:
#   - INNERHALB einer Liga bleibt das Kuerzel eindeutig. Dort wird es zum
#     Spaltennamen des Simulations-Data-Frames; eine Dopplung vertauschte
#     Teams stillschweigend.
#   - Zwischen Nord, Nordost und Bayern ebenfalls. Zwei von ihnen bestreiten
#     jaehrlich die Aufstiegsspiele (rl_aufstieg.R), und dort ordnet
#     aufstiegswahrscheinlichkeit() ueber NAMEN zu. Welche zwei es sind,
#     beschliesst das DFB-Praesidium jaehrlich -- alle drei untereinander
#     frei zu halten ist die einzige Fassung, die nicht jedes Jahr
#     nachgezogen werden muss.

test_that("load_team_list erlaubt dasselbe Kuerzel in verschiedenen Ligen", {
  # Die drei echten Faelle aus TeamList_2026: VFB (Stuttgart 78 / Luebeck 84),
  # FCH (Heidenheim 79 / Hansa Rostock 80), RWE (Essen 80 / Erfurt 85).
  # Alle sechs Ansprueche sind einzeln belegt.
  pfad <- schreibe_teamlist(c(
    "172;VFB;0;1805.0;78;SuedWest;VfB Stuttgart",
    "1625;VFB;0;950.0;84;Nord;VfB Luebeck",
    "180;FCH;0;1520.0;79;SuedWest;1. FC Heidenheim",
    "1330;FCH;0;1160.0;80;Nordost;Hansa Rostock",
    "1324;RWE;0;1150.0;80;West;Rot-Weiss Essen",
    "1329;RWE;0;900.0;85;Nordost;FC Rot-Weiss Erfurt"
  ))

  teams <- load_team_list(pfad)

  expect_equal(nrow(teams), 6)
  expect_equal(sum(teams$ShortText == "VFB"), 2)
  expect_equal(sum(teams$ShortText == "FCH"), 2)
})

test_that("load_team_list bricht bei Kollision INNERHALB einer Liga ab", {
  # Die Lockerung gilt nur ueber Ligagrenzen. Innerhalb einer Liga wird der
  # Kurzname zum Spaltennamen -- hier muss es weiter knallen.
  pfad <- schreibe_teamlist(c(
    "9020;VFB;0;1800.0;78;SuedWest;VfB Stuttgart",
    "9021;VFB;0;1700.0;78;Nord;VfB Anderswo"
  ))

  err <- expect_error(load_team_list(pfad))
  expect_match(conditionMessage(err), "VFB")
})

test_that("load_team_list bricht bei Kollision zwischen Nord, Nordost und Bayern ab", {
  # Die harte Ausnahme. Zwei dieser drei Staffeln spielen jaehrlich die
  # Aufstiegsspiele gegeneinander, und die Doppelsumme ordnet ueber Namen zu.
  # Ein doppeltes Kuerzel vertauschte dort zwei Teams -- ohne Fehlermeldung.
  for (paar in list(c("84", "83"), c("84", "85"), c("85", "83"))) {
    pfad <- schreibe_teamlist(c(
      sprintf("9030;SVA;0;950.0;%s;Nord;SV Alpha", paar[[1]]),
      sprintf("9031;SVA;0;940.0;%s;Bayern;SV Alpha Zwei", paar[[2]])
    ))
    err <- expect_error(load_team_list(pfad),
                        info = paste(paar, collapse = " vs "))
    expect_match(conditionMessage(err), "SVA")
  }
})

test_that("load_team_list erlaubt dasselbe Kuerzel in West und SuedWest", {
  # Gegenprobe zur harten Regel: West (87) und SuedWest (86) bestreiten die
  # Aufstiegsspiele NIE -- sie haben dauerhafte Direktplaetze (Par. 55b
  # DFB-SpO). Zwischen ihnen ist eine Dopplung deshalb zulaessig.
  pfad <- schreibe_teamlist(c(
    "9040;SVB;0;950.0;87;West;SV Beta",
    "9041;SVB;0;940.0;86;SuedWest;SV Beta Zwei"
  ))

  teams <- load_team_list(pfad)
  expect_equal(nrow(teams), 2)
})
