library(testthat)

# Hingucker der Woche: Inverser Simpson-Index, Saisonausgaenge je Liga und die
# Auswahl der Spiele der naechsten sieben Tage.

hg <- source_module("hingucker", "league_views")

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

test_that("die 3. Liga liest oberes und unteres Panel aus ihren eigenen Quellen und normiert", {
  env <- new.env()
  top <- unclass(hg_gleichverteilt(20L))
  top["T1", ] <- c(0.7, rep(0.3 / 19, 19))
  env$Ergebnis3_Aufstieg <- as.table(top)
  unten <- unclass(hg_gleichverteilt(20L))
  unten["T1", ] <- c(rep(0.3 / 19, 19), 0.7)
  env$Ergebnis3 <- as.table(unten)

  aus <- hg$liga_ausgaenge(hg_views("dritte_liga")$dritte_liga, env)

  # Aufstieg 0,7 + 0,3/19 und Abstieg 0,7 + 3 * 0,3/19 -> Summe > 1, normiert.
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

  expect_equal(colnames(aus),
               c("Aufstieg", "Aufstiegsspiele", "Mittelfeld", "Relegation", "Abstieg"))
  expect_equal(unname(aus["T1", "Aufstieg"]), 0.02)
  # Meister (1/19) minus Aufstieg: die Ueberlappung zaehlt nur einmal.
  expect_equal(unname(aus["T1", "Aufstiegsspiele"]), 1 / 19 - 0.02)
  expect_equal(unname(rowSums(aus)), rep(1, 19))
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

test_that("nur offene Spiele zaehlen; offene Anstosszeit bleibt drin", {
  ld <- list(bundesliga = hg_league_data(list(
    hg_spiel(1, "2026-10-31 09:00", 1, 2, status = "FT"),     # heute schon gespielt
    hg_spiel(2, "2026-10-31 09:30", 3, 4, status = "1H"),     # laeuft
    hg_spiel(3, "2026-11-01 12:00", 5, 6, status = "PST"),    # verlegt
    hg_spiel(4, "2026-11-01 12:00", 7, 8, zeit_offen = TRUE)  # Zeit offen
  )))

  k <- hg$hingucker_kandidaten(hg_views("bundesliga"), hg_env_bundesliga(), ld,
                               now = hg_jetzt)

  expect_equal(k$fixture_id, 4)
  expect_true(k$zeit_offen)
})

test_that("Score ist das Produkt aus Spiel-, Heim- und Gast-Index", {
  ld <- list(bundesliga = hg_league_data(list(
    hg_spiel(1, "2026-11-01 15:30", 1, 2, p = c(0.5, 0.3, 0.2))
  )))

  k <- hg$hingucker_kandidaten(hg_views("bundesliga"), hg_env_bundesliga(), ld,
                               now = hg_jetzt)

  expect_equal(k$d_spiel, 1 / 0.38)
  expect_equal(k$d_heim, 324 / 98)
  expect_equal(k$d_gast, 324 / 98)
  expect_equal(k$score, (1 / 0.38) * (324 / 98)^2)
  expect_equal(k$platz_heim, 1)
  expect_equal(k$platz_gast, 2)
  expect_equal(k$liga_label, "Bundesliga")
})

test_that("sortiert nach Score; bei Gleichstand entscheidet der fruehere Anstoss", {
  env <- hg_env_bundesliga()
  m <- unclass(env$Ergebnis)
  m["T3", ] <- c(1, rep(0, 17))  # T3 hat nichts mehr offen: D_Heim = 1
  env$Ergebnis <- as.table(m)

  ld <- list(bundesliga = hg_league_data(list(
    hg_spiel(1, "2026-11-03 15:30", 3, 4),  # T3 entschieden -> niedriger Score
    hg_spiel(2, "2026-11-02 15:30", 5, 6),  # gleicher Score wie 3 ...
    hg_spiel(3, "2026-11-01 15:30", 7, 8)   # ... aber frueher
  )))

  k <- hg$hingucker_kandidaten(hg_views("bundesliga"), env, ld, now = hg_jetzt)

  expect_equal(k$fixture_id, c(3, 2, 1))
})

test_that("Ligen ohne league_data oder ohne Ausgaenge liefern keine Kandidaten", {
  expect_null(hg$hingucker_kandidaten(hg_views("bundesliga"), hg_env_bundesliga(),
                                      list(bundesliga = NULL), now = hg_jetzt))
  ld <- list(bundesliga = hg_league_data(list(hg_spiel(1, "2026-11-01 15:30", 1, 2))))
  expect_null(hg$hingucker_kandidaten(hg_views("bundesliga"), new.env(), ld,
                                      now = hg_jetzt))
})

test_that("Kandidaten aus mehreren Ligen werden gemeinsam gerankt und tragen den Ligennamen", {
  env <- hg_env_bundesliga()
  env$Ergebnis_frauen_bundesliga <- hg_gleichverteilt(14L)
  ld <- list(
    bundesliga = hg_league_data(list(hg_spiel(1, "2026-11-01 15:30", 1, 2))),
    frauen_bundesliga = hg_league_data(list(hg_spiel(2, "2026-11-01 15:30", 1, 2)))
  )

  k <- hg$hingucker_kandidaten(hg_views("bundesliga", "frauen_bundesliga"), env, ld,
                               now = hg_jetzt)

  expect_setequal(k$liga_label, c("Bundesliga", "Frauen-Bundesliga"))
  # Die Bundesliga hat sieben Ausgaenge, die Frauen-Bundesliga vier:
  # unnormiert liegt die Bundesliga vorn (siehe Kopfkommentar von hingucker.R).
  expect_equal(k$liga_label[1], "Bundesliga")
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
