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
# ANDEREN Liga dasselbe traegt. Massgeblich ist nicht die Haeufigkeit des
# Namensbestandteils, sondern welcher Verein unter dem Kuerzel bekannt ist.
# Wird in der Vertrag-Haelfte unten geprueft: Bloecke "KEIN Verstoss" /
# "Nord, Nordost und Bayern".
#
# KORRIGIERT (Issue #197): Hier stand, aufstiegswahrscheinlichkeit() ordne
# ueber NAMEN zu und ein doppeltes Kuerzel vertausche Teams. Das trifft
# nicht zu -- die beiden Staffeln liegen auf getrennten Achsen der
# p_sieg-Matrix. Begruendung im Detail in transform_data.R.

# --- aus test-kuerzel-vertrag.R ---
# Der Kuerzel-Vertrag als EINE Pruefung (Issues #195, #197, ADR 0007).
#
# Bis hierher gab es ihn dreimal, in drei Fassungen:
#
#   load_team_list()            je Liga + Ausnahme 83/84/85   -- die richtige
#   merge_league_files()        global, benennt still um      -- die gefaehrliche
#   validate_csv_data()         global, lehnt ab              -- die widerspruechliche
#
# Der Saisonwechsel setzt damit einen Vertrag durch, den der Loader seit
# PR #183 nicht mehr kennt. TeamList_2026 traegt rund vierzig absichtlich
# gleiche Kuerzel ueber Ligagrenzen (FCH, VFB, RWE, alle angeglichenen
# Frauen-Kuerzel); merge_league_files() wuerde sie beim naechsten Lauf zu
# "FC1", "VF1" umbenennen und Erfolg melden.
#
# Diese Datei beschreibt die gemeinsame Pruefung, auf die beide Seiten
# umgestellt werden. Sie bekommt einen fertigen data.frame statt eines
# Dateipfads -- nur so kann der Saisonwechsel sie auf seiner
# Zwischenrepraesentation aufrufen, bevor etwas geschrieben ist.

lade_pruefung <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "transform_data.R"), local = env)
  env
}

mk_teams <- function(...) {
  zeilen <- list(...)
  data.frame(
    TeamID = vapply(zeilen, function(z) z[[1]], numeric(1)),
    ShortText = vapply(zeilen, function(z) z[[2]], character(1)),
    League = vapply(zeilen, function(z) z[[3]], character(1)),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------

test_that("pruefe_kuerzel_vertrag meldet nichts, wenn der Vertrag eingehalten ist", {
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "FCB", "78"),
    list(2, "BVB", "78"),
    list(3, "FCB", "82")   # Frauenteam desselben Vereins -- gewollt
  ))

  expect_length(verstoesse, 0L)
})

test_that("gleiche Kuerzel in DERSELBEN Liga sind ein Verstoss", {
  # Der einzige Fall, der echten Schaden anrichtet: ShortText wird in
  # transform_data() zum Spaltennamen, eine Dopplung vertauscht Teams
  # stillschweigend.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "FCB", "78"),
    list(2, "FCB", "78")
  ))

  expect_length(verstoesse, 1L)
  expect_match(verstoesse[[1]], "FCB", fixed = TRUE)
  expect_match(verstoesse[[1]], "78", fixed = TRUE)
})

test_that("gleiche Kuerzel zwischen Maenner- und Frauenliga sind KEIN Verstoss", {
  # Ausdrueckliche Absicht (ADR 0007, CONTEXT.md): Derselbe Verein traegt
  # dasselbe Kuerzel, einschliesslich der "2"-Variante. In TeamList_2026
  # betrifft das ueber zwanzig Vereine.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "SGE", "78"),
    list(2, "SGE", "82"),
    list(3, "SGE2", "80"),
    list(4, "SGE2", "1034")
  ))

  expect_length(verstoesse, 0L)
})

test_that("gleiche Kuerzel verschiedener Vereine in verschiedenen Ligen sind KEIN Verstoss", {
  # Die drei echten Faelle aus TeamList_2026, Entscheidung aus PR #186:
  # Wo ein Kuerzel fuer einen Verein eingefuehrt ist, bekommt er es.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "VFB", "78"),   # Stuttgart
    list(2, "VFB", "84"),   # Luebeck
    list(3, "FCH", "79"),   # Heidenheim
    list(4, "FCH", "80"),   # Hansa Rostock
    list(5, "RWE", "80"),   # Essen
    list(6, "RWE", "85")    # Erfurt
  ))

  expect_length(verstoesse, 0L)
})

test_that("gleiche Kuerzel zwischen Nord, Nordost und Bayern sind ein Verstoss", {
  # Lesbarkeitsregel: Zwei dieser drei Staffeln stehen jaehrlich gemeinsam
  # auf der Aufstiegsseite; dort waeren gleiche Kuerzel nicht zu
  # unterscheiden. Welche zwei es trifft, beschliesst das DFB-Praesidium
  # jaehrlich -- alle drei frei zu halten ist die einzige Fassung, die nicht
  # jedes Jahr nachgezogen werden muss.
  env <- lade_pruefung()

  for (paar in list(c("84", "83"), c("84", "85"), c("85", "83"))) {
    verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
      list(1, "SVA", paar[[1]]),
      list(2, "SVA", paar[[2]])
    ))
    expect_length(verstoesse, 1L)
    expect_match(verstoesse[[1]], "SVA", fixed = TRUE, info = paste(paar, collapse = "/"))
  }

  # Gegenprobe: West und SuedWest spielen die Aufstiegsspiele nie.
  expect_length(
    env$pruefe_kuerzel_vertrag(mk_teams(list(1, "SVA", "86"), list(2, "SVA", "87"))),
    0L
  )
})

test_that("doppelte TeamIDs sind ein Verstoss", {
  # Sie vervielfachen beim merge() die Spielzeilen -- ebenso still.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(7, "AAA", "78"),
    list(7, "BBB", "79")
  ))

  expect_length(verstoesse, 1L)
  expect_match(verstoesse[[1]], "7", fixed = TRUE)
})

test_that("ohne League-Spalte gilt die ganze Liste als eine Gruppe", {
  # TeamLists bis Saison 2025 kennen die Spalte nicht. Dort ist jede
  # Dopplung ein Verstoss -- mangels Information, ob sie erlaubt waere.
  env <- lade_pruefung()
  ohne <- data.frame(TeamID = c(1, 2), ShortText = c("FCB", "FCB"),
                     stringsAsFactors = FALSE)

  expect_length(env$pruefe_kuerzel_vertrag(ohne), 1L)
})

test_that("die Pruefung meldet ALLE Verstoesse, nicht nur den ersten", {
  # Sie speist den Konfliktbericht des Saisonwechsels (ADR 0007). Wer nach
  # jedem Fund abbricht, zwingt zu so vielen Laeufen, wie es Konflikte gibt.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "AAA", "78"),
    list(2, "AAA", "78"),
    list(3, "BBB", "79"),
    list(4, "BBB", "79")
  ))

  expect_length(verstoesse, 2L)
})

# --- load_team_list() benutzt dieselbe Pruefung ----------------------------

test_that("die Fehlermeldung der 83/84/85-Regel nennt den richtigen Grund", {
  # KORRIGIERT (Issue #197): Hier stand, die Doppelsumme ordne ueber Namen
  # zu und ein doppeltes Kuerzel vertausche Teams. Das trifft nicht zu --
  # die beiden Staffeln liegen auf getrennten Achsen der p_sieg-Matrix.
  # Der Grund ist Lesbarkeit auf der gemeinsamen Aufstiegsseite.
  env <- lade_pruefung()
  pfad <- withr::local_tempfile(fileext = ".csv")
  writeLines(c(
    "TeamID;ShortText;Promotion;InitialELO;League;Region;Name",
    "1;SVA;0;1000;84;Nord;Team Eins",
    "2;SVA;0;1000;83;Bayern;Team Zwei"
  ), pfad)

  expect_error(env$load_team_list(pfad), "Aufstiegsseite")
  expect_error(env$load_team_list(pfad), "SVA")
})
