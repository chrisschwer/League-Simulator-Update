library(testthat)

# Hingucker der Woche: Inverser Simpson-Index, Saisonausgaenge je Liga und die
# Auswahl der Spiele der naechsten sieben Tage.

hg <- source_module("hingucker", "league_views", "league_details")

# 18 Teams T1..T18, jede Platzwahrscheinlichkeit 1/18.
hg_gleichverteilt <- function(teams = 18L) {
  as.table(matrix(1 / teams, nrow = teams, ncol = teams,
                  dimnames = list(paste0("T", seq_len(teams)),
                                  as.character(seq_len(teams)))))
}

hg_env_bundesliga <- function() {
  env <- new.env()
  env$Ergebnis <- hg_gleichverteilt(18L)
  env
}

hg_views <- function(...) {
  alle <- unclass(hg$league_views())
  alle[c(...)]
}

# ---------------------------------------------------------------------------
# inverse_simpson
# ---------------------------------------------------------------------------

test_that("inverse_simpson ist die effektive Zahl gleich wahrscheinlicher Ausgaenge", {
  expect_equal(hg$inverse_simpson(c(1, 0, 0)), 1)
  expect_equal(hg$inverse_simpson(rep(1 / 3, 3)), 3)
  expect_equal(hg$inverse_simpson(rep(1 / 7, 7)), 7)
  # 50 / 30 / 20: 1 / (0,25 + 0,09 + 0,04)
  expect_equal(hg$inverse_simpson(c(0.5, 0.3, 0.2)), 1 / 0.38)
})

test_that("inverse_simpson normiert und ignoriert Nullen", {
  expect_equal(hg$inverse_simpson(c(2, 2)), 2)
  expect_equal(hg$inverse_simpson(c(0.5, 0, 0.5)), 2)
  expect_true(is.na(hg$inverse_simpson(c(0, 0))))
  expect_true(is.na(hg$inverse_simpson(numeric(0))))
})

# ---------------------------------------------------------------------------
# liga_ausgaenge
# ---------------------------------------------------------------------------

test_that("liga_ausgaenge buendelt die Bundesliga-Plaetze zu Zonen plus Mittelfeld", {
  aus <- hg$liga_ausgaenge(hg_views("bundesliga")$bundesliga, hg_env_bundesliga())

  expect_equal(colnames(aus),
               c("Meister", "Champions League", "Europa League",
                 "Conference League Quali", "Mittelfeld", "Relegation", "Abstieg"))
  expect_equal(unname(aus["T1", ]) * 18, c(1, 3, 1, 1, 9, 1, 2))
  expect_equal(unname(rowSums(aus)), rep(1, 18))
  # (1 + 9 + 1 + 1 + 81 + 1 + 4) / 18^2 = 98 / 324
  expect_equal(hg$inverse_simpson(aus["T1", ]), 324 / 98)
})

test_that("ein Team mit sicherem Platz hat die effektive Zahl 1", {
  env <- hg_env_bundesliga()
  m <- unclass(env$Ergebnis)
  m["T1", ] <- c(1, rep(0, 17))
  env$Ergebnis <- as.table(m)

  aus <- hg$liga_ausgaenge(hg_views("bundesliga")$bundesliga, env)

  expect_equal(hg$inverse_simpson(aus["T1", ]), 1)
})

test_that("liga_ausgaenge zaehlt negative Grenzen von unten (Frauen-Bundesliga)", {
  env <- new.env()
  env$Ergebnis_frauen_bundesliga <- hg_gleichverteilt(14L)

  aus <- hg$liga_ausgaenge(hg_views("frauen_bundesliga")$frauen_bundesliga, env)

  expect_equal(unname(aus["T1", "Abstieg"]), 2 / 14)
  expect_equal(unname(aus["T1", "Meister"]), 1 / 14)
  expect_equal(unname(rowSums(aus)), rep(1, 14))
})

test_that("optionale berechnete Spalten zaehlen nicht als eigener Ausgang", {
  # 2. Bundesliga: "Aufstieg gesamt" und "Abstieg gesamt" sind Zusatzzahlen.
  env <- new.env()
  env$Ergebnis2 <- hg_gleichverteilt(18L)

  aus <- hg$liga_ausgaenge(hg_views("zweite_bundesliga")$zweite_bundesliga, env)

  expect_false(any(grepl("gesamt", colnames(aus))))
  expect_equal(unname(rowSums(aus)), rep(1, 18))
})

test_that("die 3. Liga liest das obere Panel als Rang unter den Berechtigten, das untere als Tabellenplatz", {
  env <- new.env()
  env$Ergebnis3 <- hg_gleichverteilt(20L)
  # Eine gesperrte Zweitvertretung traegt im oberen Panel null (ADR 0009).
  top <- unclass(hg_gleichverteilt(20L))
  top["T2", ] <- 0
  env$Ergebnis3_Aufstieg <- as.table(top)

  aus <- hg$liga_ausgaenge(hg_views("dritte_liga")$dritte_liga, env)

  expect_equal(unname(aus["T2", c("Aufstieg", "Relegation", "DFB-Pokal")]), c(0, 0, 0))
  expect_equal(unname(aus["T2", "Abstieg"]), 4 / 20)
  expect_equal(unname(aus["T1", "Aufstieg"]), 2 / 20)
  expect_equal(unname(rowSums(aus)), rep(1, 20))
})

test_that("die Normierung faengt entartete Eingaben ab: die Zeilensumme bleibt 1", {
  env <- new.env()
  env$Ergebnis3 <- hg_gleichverteilt(20L)
  top <- unclass(hg_gleichverteilt(20L))
  top["T1", ] <- c(0.7, rep(0.3 / 19, 19))
  env$Ergebnis3_Aufstieg <- as.table(top)
  unten <- unclass(hg_gleichverteilt(20L))
  unten["T1", ] <- c(rep(0.3 / 19, 19), 0.7)
  env$Ergebnis3 <- as.table(unten)

  aus <- hg$liga_ausgaenge(hg_views("dritte_liga")$dritte_liga, env)

  expect_equal(unname(rowSums(aus)), rep(1, 20))
  expect_equal(unname(aus["T1", "Mittelfeld"]), 0)
})

test_that("Regionalliga Bayern: Aufstiegsspiele und Abstieg kommen aus den berechneten Objekten", {
  teams <- paste0("T", 1:19)
  env <- new.env()
  env$Ergebnis_rl_bayern <- hg_gleichverteilt(19L)
  # Meister (Platz 1) = 1/19 je Team.
  env$Ergebnis_rl_bayern_aufstieg <- data.frame(Aufstieg = rep(0.02, 19),
                                                row.names = teams)
  env$Ergebnis_rl_bayern_abstieg <- data.frame(Relegation = rep(0.1, 19),
                                               Abstieg = rep(0.1, 19),
                                               row.names = teams)

  aus <- hg$liga_ausgaenge(hg_views("rl_bayern")$rl_bayern, env)

  # Eine Zone "Aufstiegsspiele" (erster Berechtigter = hier der Meister, 1/19),
  # kein Aufstieg und kein "verloren": Teilnahme zaehlt, nicht der Ausgang.
  expect_equal(colnames(aus), c("Aufstiegsspiele", "Mittelfeld", "Relegation", "Abstieg"))
  expect_equal(unname(aus["T1", "Aufstiegsspiele"]), 1 / 19)
  expect_equal(unname(rowSums(aus)), rep(1, 19))
})

test_that("Verzicht in Nord oder Bayern: wer verzichtet, spielt keine Aufstiegsspiele", {
  teams <- paste0("T", 1:19)
  env <- new.env()
  env$Ergebnis_rl_bayern <- hg_gleichverteilt(19L)
  # T1 verzichtet (spielt nie), T2 rueckt nach und spielt mit 10 %.
  aufstieg <- data.frame(Aufstieg = c(0, 0.04, rep(0.01, 17)), row.names = teams)
  attr(aufstieg, "p_erster_berechtigter") <- stats::setNames(c(0, 0.1, rep(1 / 19, 17)), teams)
  attr(aufstieg, "verzichtet") <- "T1"
  env$Ergebnis_rl_bayern_aufstieg <- aufstieg
  env$Ergebnis_rl_bayern_abstieg <- data.frame(Relegation = rep(0.1, 19),
                                               Abstieg = rep(0.1, 19), row.names = teams)

  aus <- hg$liga_ausgaenge(hg_views("rl_bayern")$rl_bayern, env)

  expect_equal(unname(aus["T1", "Aufstiegsspiele"]), 0)
  # Das Meisterplus von T1 (1/19) fliesst ins Mittelfeld, nicht in Aufstiegsspiele.
  expect_equal(unname(aus["T1", "Mittelfeld"]), 0.8)
  # T2 spielt mit 10 %; ob es die Spiele gewinnt, zaehlt hier nicht.
  expect_equal(unname(aus["T2", "Aufstiegsspiele"]), 0.1)
  expect_equal(unname(rowSums(aus)), rep(1, 19))
})

test_that("Verzicht in einer Direktstaffel: Aufstieg ist P(erster Berechtigter), nicht P(Platz 1)", {
  teams <- paste0("T", 1:18)
  env <- new.env()
  env$Ergebnis_rl_west <- hg_gleichverteilt(18L)
  m <- unclass(env$Ergebnis_rl_west)
  m["T1", ] <- c(0.6, rep(0.4 / 17, 17))   # T1 haette gute Chancen auf Platz 1 ...
  env$Ergebnis_rl_west <- as.table(m)
  aufstieg <- data.frame(Aufstieg = c(0, 0.5, rep(0.5 / 16, 16)), row.names = teams)
  attr(aufstieg, "verzichtet") <- "T1"       # ... verzichtet aber
  env$Ergebnis_rl_west_aufstieg <- aufstieg
  env$Ergebnis_rl_west_abstieg <- data.frame(Abstieg = rep(0.1, 18), row.names = teams)

  aus <- hg$liga_ausgaenge(hg_views("rl_west")$rl_west, env)

  expect_equal(unname(aus["T1", "Aufstieg"]), 0)
  expect_equal(unname(aus["T2", "Aufstieg"]), 0.5)
  expect_equal(unname(rowSums(aus)), rep(1, 18))
})

test_that("liga_ausgaenge liefert NULL, wenn eine tragende Quelle fehlt", {
  env <- new.env()
  expect_null(hg$liga_ausgaenge(hg_views("bundesliga")$bundesliga, env))

  env$Ergebnis_rl_bayern <- hg_gleichverteilt(19L)  # Abstiegsobjekt fehlt
  expect_null(hg$liga_ausgaenge(hg_views("rl_bayern")$rl_bayern, env))
})

# ---------------------------------------------------------------------------
# hingucker_kandidaten
# ---------------------------------------------------------------------------

hg_spiel <- function(id, kickoff, home, away, status = "NS", zeit_offen = FALSE,
                     p = c(1 / 3, 1 / 3, 1 / 3)) {
  data.frame(
    fixture_id = id, round = 10L,
    kickoff = as.POSIXct(kickoff, tz = "UTC"),
    status = status, zeit_offen = zeit_offen, nachholspiel = FALSE,
    home_id = home, away_id = away,
    home_name = paste("Team", home), away_name = paste("Team", away),
    p_home_win = p[1], p_draw = p[2], p_away_win = p[3],
    stringsAsFactors = FALSE
  )
}

hg_league_data <- function(spiele) {
  m <- do.call(rbind, spiele)
  m$score_matrix <- rep(list(matrix(0, 7, 7)), nrow(m))
  list(
    matches = m,
    teams = data.frame(TeamID = 1:18, ShortText = paste0("T", 1:18),
                       stringsAsFactors = FALSE),
    tabelle = data.frame(platz = 1:18, kuerzel = paste0("T", 1:18),
                         stringsAsFactors = FALSE)
  )
}

hg_jetzt <- as.POSIXct("2026-10-31 10:00", tz = "UTC")  # Samstag, 11:00 Berlin

test_that("das Fenster reicht von heute (inklusive) sieben Berliner Kalendertage", {
  ld <- list(bundesliga = hg_league_data(list(
    hg_spiel(1, "2026-10-31 14:30", 1, 2),   # heute, noch offen
    hg_spiel(2, "2026-11-06 19:00", 3, 4),   # letzter Tag
    hg_spiel(3, "2026-11-06 23:30", 5, 6),   # 7.11., 00:30 Berlin -> draussen
    hg_spiel(4, "2026-11-07 12:00", 7, 8),   # draussen
    hg_spiel(5, "2026-10-30 19:00", 9, 10)   # gestern
  )))

  k <- hg$hingucker_kandidaten(hg_views("bundesliga"), hg_env_bundesliga(), ld,
                               now = hg_jetzt)

  expect_setequal(k$fixture_id, c(1, 2))
})

test_that("offene und laufende Spiele zaehlen; offene Anstosszeit bleibt drin", {
  ld <- list(bundesliga = hg_league_data(list(
    hg_spiel(1, "2026-10-31 09:00", 1, 2, status = "FT"),     # heute schon gespielt
    hg_spiel(2, "2026-10-31 09:30", 3, 4, status = "1H"),     # laeuft
    hg_spiel(3, "2026-11-01 12:00", 5, 6, status = "PST"),    # verlegt
    hg_spiel(4, "2026-11-01 12:00", 7, 8, zeit_offen = TRUE)  # Zeit offen
  )))

  k <- hg$hingucker_kandidaten(hg_views("bundesliga"), hg_env_bundesliga(), ld,
                               now = hg_jetzt)

  expect_setequal(k$fixture_id, c(2, 4))
  expect_true(k$laeuft[k$fixture_id == 2])
  expect_false(k$laeuft[k$fixture_id == 4])
  expect_true(k$zeit_offen[k$fixture_id == 4])
})

test_that("laufend heisst: spielt und vor hoechstens vier Stunden angepfiffen", {
  ld <- list(bundesliga = hg_league_data(list(
    hg_spiel(1, "2026-10-31 06:30", 1, 2, status = "2H"),    # 3,5 h her: laeuft noch
    hg_spiel(2, "2026-10-31 05:30", 3, 4, status = "LIVE"),  # 4,5 h her: Altlast
    hg_spiel(3, "2026-10-31 09:00", 5, 6, status = "SUSP"),  # ausgesetzt
    hg_spiel(4, "2026-10-31 09:00", 7, 8, status = "INT"),   # unterbrochen
    hg_spiel(5, "2026-10-31 11:00", 9, 10, status = "1H")    # Anstoss in der Zukunft
  )))

  k <- hg$hingucker_kandidaten(hg_views("bundesliga"), hg_env_bundesliga(), ld,
                               now = hg_jetzt)

  expect_equal(k$fixture_id, 1)
  expect_true(k$laeuft)
})

test_that("Score ist Spiel-Index mal Heim- und Gast-Index, je geteilt durch den Liga-Median", {
  ld <- list(bundesliga = hg_league_data(list(
    hg_spiel(1, "2026-11-01 15:30", 1, 2, p = c(0.5, 0.3, 0.2))
  )))

  k <- hg$hingucker_kandidaten(hg_views("bundesliga"), hg_env_bundesliga(), ld,
                               now = hg_jetzt)

  expect_equal(k$d_spiel, 1 / 0.38)
  expect_equal(k$d_heim, 324 / 98)
  expect_equal(k$d_gast, 324 / 98)
  # Alle 18 Teams sind gleich offen: der Median ist ihr gemeinsamer Wert, beide
  # Teams sind "typisch" (Faktor 1), und der Score ist der Spiel-Index allein.
  expect_equal(k$d_median, 324 / 98)
  expect_equal(k$score, 1 / 0.38)
  expect_equal(k$platz_heim, 1)
  expect_equal(k$platz_gast, 2)
  expect_equal(k$liga_label, "Bundesliga")
})

# Eine Bundesliga, in der T1 und T2 offener sind als der Rest: T1 und T2 halten
# je zur Haelfte Platz 1 und Platz 2, alle anderen sind unveraendert gleichverteilt.
hg_env_bundesliga_offen <- function() {
  env <- hg_env_bundesliga()
  m <- unclass(env$Ergebnis)
  m["T1", ] <- c(0.5, 0.5, rep(0, 16))
  m["T2", ] <- c(0.5, 0.5, rep(0, 16))
  env$Ergebnis <- as.table(m)
  env
}

test_that("d_median ist der Median von D_Team ueber ALLE Teams der Liga, nicht nur die im Fenster", {
  env <- hg_env_bundesliga()
  m <- unclass(env$Ergebnis)
  # Zehn Teams ohne Spiel im Fenster sind sicher im Mittelfeld (D = 1), acht
  # Teams gleichverteilt (D = 324 / 98): Der Median liegt bei den sicheren.
  for (t in paste0("T", 9:18)) m[t, ] <- c(rep(0, 8), 1, rep(0, 9))
  env$Ergebnis <- as.table(m)
  ld <- list(bundesliga = hg_league_data(list(
    hg_spiel(1, "2026-11-01 15:30", 1, 2)   # nur die gleichverteilten Teams spielen
  )))

  k <- hg$hingucker_kandidaten(hg_views("bundesliga"), env, ld, now = hg_jetzt)

  expect_equal(k$d_median, 1)
  expect_equal(k$d_heim, 324 / 98)
  expect_equal(k$score, k$d_spiel * (324 / 98)^2)
})

test_that("der Median geht quadratisch ein: score = d_spiel * d_heim * d_gast / d_median^2", {
  ld <- list(bundesliga = hg_league_data(list(
    hg_spiel(1, "2026-11-01 15:30", 1, 2, p = c(0.5, 0.3, 0.2)),   # beide offen
    hg_spiel(2, "2026-11-01 15:30", 1, 3, p = c(0.5, 0.3, 0.2))    # nur T1 offen
  )))

  k <- hg$hingucker_kandidaten(hg_views("bundesliga"), hg_env_bundesliga_offen(), ld,
                               now = hg_jetzt)

  expect_equal(k$score, k$d_spiel * k$d_heim * k$d_gast / k$d_median^2)
  # T1 und T2: D = 2, die uebrigen 16 Teams: D = 324 / 98. Median = 324 / 98.
  expect_equal(unique(k$d_median), 324 / 98)
  expect_equal(k$d_heim[k$fixture_id == 1], 2)
})

test_that("die Normierung nimmt Ligen mit weniger Zonen ihren Nachteil: typische Spiele sind gleich viel wert", {
  env <- hg_env_bundesliga()
  env$Ergebnis_frauen_bundesliga <- hg_gleichverteilt(14L)
  ld <- list(
    bundesliga = hg_league_data(list(hg_spiel(1, "2026-11-01 15:30", 1, 2))),
    frauen_bundesliga = hg_league_data(list(hg_spiel(2, "2026-11-01 15:30", 1, 2)))
  )

  k <- hg$hingucker_kandidaten(hg_views("bundesliga", "frauen_bundesliga"), env, ld,
                               now = hg_jetzt)

  expect_setequal(k$liga_label, c("Bundesliga", "Frauen-Bundesliga"))
  # Roh haette die Bundesliga (sieben Zonen) vorn gelegen; relativ zum typischen
  # Team der eigenen Liga sind beide Spiele gleich gut.
  expect_equal(k$score[k$liga == "bundesliga"], k$score[k$liga == "frauen_bundesliga"])
  expect_equal(k$d_heim[k$liga == "bundesliga"] > k$d_heim[k$liga == "frauen_bundesliga"], TRUE)
})

test_that("ein ueberdurchschnittlich offenes Frauenspiel schlaegt ein typisches Bundesligaspiel", {
  env <- hg_env_bundesliga()
  fr <- unclass(hg_gleichverteilt(14L))
  # In der Frauen-Bundesliga sind T1 und T2 ein offenes Titelrennen (D < Maximum,
  # aber klar ueber dem Median der Liga, in der die meisten Teams entschieden sind).
  fr[3:14, ] <- matrix(rep(c(rep(0, 4), 1, rep(0, 9)), each = 12), nrow = 12)
  fr[1, ] <- c(0.5, 0.5, rep(0, 12))
  fr[2, ] <- c(0.5, 0.5, rep(0, 12))
  env$Ergebnis_frauen_bundesliga <- as.table(fr)
  ld <- list(
    bundesliga = hg_league_data(list(hg_spiel(1, "2026-11-01 15:30", 3, 4))),
    frauen_bundesliga = hg_league_data(list(hg_spiel(2, "2026-11-01 15:30", 1, 2)))
  )

  k <- hg$hingucker_kandidaten(hg_views("bundesliga", "frauen_bundesliga"), env, ld,
                               now = hg_jetzt)

  expect_equal(k$liga[1], "frauen_bundesliga")
})

test_that("hingucker_fenster_text nennt sieben Tage ab heute", {
  expect_equal(hg$hingucker_fenster_text(hg_jetzt), "31.10. – 6.11.")
  expect_equal(hg$hingucker_fenster_text(as.POSIXct("2026-12-28 12:00", tz = "UTC")),
               "28.12. – 3.1.")
})

test_that("hingucker_logzeile nennt den besten Score je Liga, hoechsten zuerst", {
  k <- data.frame(score = c(10, 30, 20),
                  liga_label = c("Bundesliga", "Regionalliga Bayern", "Bundesliga"))

  expect_equal(hg$hingucker_logzeile(k),
               paste0("hingucker: 3 Spiele im Fenster, bester Score je Liga: ",
                      "Regionalliga Bayern 30.0 | Bundesliga 20.0"))
  expect_equal(hg$hingucker_logzeile(NULL), "hingucker: keine Spiele im Fenster")
})

test_that("hingucker_logzeile nennt zusaetzlich den Liga-Median von D_Team", {
  k <- data.frame(score = c(10, 30, 20),
                  liga_label = c("Bundesliga", "Regionalliga Bayern", "Bundesliga"),
                  d_median = c(2.19, 1.36, 2.19))

  expect_equal(hg$hingucker_logzeile(k),
               paste0("hingucker: 3 Spiele im Fenster, bester Score je Liga: ",
                      "Regionalliga Bayern 30.0 | Bundesliga 20.0; ",
                      "Median D_Team: Regionalliga Bayern 1.36 | Bundesliga 2.19"))
})

# ---------------------------------------------------------------------------
# Betriebsdaten: die Form, die build_league_page_data() wirklich liefert
# ---------------------------------------------------------------------------

# Die Hand-Fixtures oben tragen alle Spalten, die hingucker_kandidaten() liest.
# Diese Tests nehmen stattdessen die echte Ausgabe von build_league_page_data()
# (Fixtures und Endpoint-Antwort aus helper-seitendaten.R): Eine Spalte, die
# nur in den Handtabellen existiert, faellt hier auf.

hg_betriebsview <- function() {
  list(nav_label = "Bundesliga", plot_source = "Erg",
       top = list(source = "Erg", labels = "Meister", groups = cbind(c(1, 1))),
       bottom = list(source = "Erg", labels = "Abstieg", groups = cbind(c(-1, -1))))
}

hg_betriebsenv <- function() {
  env <- new.env()
  env$Erg <- as.table(matrix(0.25, 4, 4, dimnames = list(c("ALP", "BET", "GAM", "DEL"),
                                                         as.character(1:4))))
  env
}

test_that("Betriebsdaten: hingucker_kandidaten laeuft mit der Ausgabe von build_league_page_data", {
  pd <- hg$build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                                  fetch_fn = function(...) canned_page_response())
  # Das offene Spiel 2003 (BET - GAM) liegt am 04.09.; "heute" ist der 02.09.
  jetzt <- as.POSIXct("2026-09-02 10:00", tz = "UTC")

  expect_no_warning(
    k <- hg$hingucker_kandidaten(list(bundesliga = hg_betriebsview()),
                                 hg_betriebsenv(), list(bundesliga = pd), now = jetzt)
  )

  expect_equal(k$fixture_id, 2003)
  expect_false(k$nachholspiel)
  expect_equal(k$home_name, "SV Beta")
  expect_gt(k$score, 1)
})

test_that("matches tragen die Nachholspiel-Markierung wie Rueckblick und Ausblick", {
  pd <- hg$build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                                  fetch_fn = function(...) canned_page_response())

  expect_true("nachholspiel" %in% names(pd$matches))
  expect_type(pd$matches$nachholspiel, "logical")
  expect_length(pd$matches$nachholspiel, nrow(pd$matches))
})

test_that("eine Liga mit kaputten Daten faellt allein aus, die uebrigen bleiben", {
  pd <- hg$build_league_page_data(nested_league_fixtures(), teamlist_all_leagues(),
                                  fetch_fn = function(...) canned_page_response())
  kaputt <- pd
  kaputt$matches$nachholspiel <- NULL   # die Spalte, die im Betrieb gefehlt hat
  jetzt <- as.POSIXct("2026-09-02 10:00", tz = "UTC")
  views <- list(bundesliga = hg_betriebsview(), frauen_bundesliga = hg_betriebsview())
  env <- hg_betriebsenv()

  expect_warning(
    k <- hg$hingucker_kandidaten(views, env,
                                 list(bundesliga = pd, frauen_bundesliga = kaputt),
                                 now = jetzt),
    "frauen_bundesliga uebersprungen"
  )

  expect_equal(k$liga, "bundesliga")
})
