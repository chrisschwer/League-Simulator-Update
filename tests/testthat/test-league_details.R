library(testthat)
source("../../RCode/league_details.R")

# Spieltag-Klassifikation und Rückblick-/Ausblick-Fensterung.
#
# Begriffe (CONTEXT.md, verfeinert):
# - abgeschlossen: >= 1 Spiel beendet, kein Spiel live, jedes Spiel beendet
#   oder verschoben (PST/CANC/TBD/ABD). Verschobene halten nicht offen.
#   TBD mit Termin heute oder später ist offen, nicht verschoben -- siehe
#   test-tbd-termin.R (Issue #230).
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

# --- aus test-fixture-details.R ---
# extract_fixture_details() zieht aus der genesteten api-football-Struktur die
# Angaben, die transform_data() bisher verwirft: Spieltag, Anstoßzeit, Status,
# Team-IDs/-Namen und Tore. Eine Zeile je Spiel, API-Reihenfolge bleibt
# erhalten (Positions-Alignment mit dem transform_data-Spielplan).

make_nested_fixtures <- function() {
  tibble::tibble(
    fixture = list(
      data.frame(
        id = 1001, date = "2026-11-27T19:30:00+00:00",
        status = I(list(data.frame(short = "FT")))
      ),
      data.frame(
        id = 1002, date = "2026-11-28T14:30:00+00:00",
        status = I(list(data.frame(short = "NS")))
      ),
      data.frame(
        id = 9999, date = "2027-05-27T18:30:00+00:00",
        status = I(list(data.frame(short = "NS")))
      )
    ),
    league = list(
      data.frame(round = "Regular Season - 12"),
      data.frame(round = "Regular Season - 13"),
      data.frame(round = "Final")   # Relegation, gehört nicht in die Saison
    ),
    teams = list(
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 102, name = "Team B")))
      ),
      data.frame(
        home = I(list(data.frame(id = 103, name = "Team C"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      ),
      data.frame(
        home = I(list(data.frame(id = 101, name = "Team A"))),
        away = I(list(data.frame(id = 104, name = "Team D")))
      )
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    )
  )
}

test_that("extract_fixture_details liefert eine flache Zeile je Regular-Season-Spiel", {
  details <- extract_fixture_details(make_nested_fixtures())

  expect_s3_class(details, "data.frame")
  expect_equal(nrow(details), 2) # "Final" ist herausgefiltert
  expect_true(all(c(
    "fixture_id", "round", "kickoff", "status",
    "home_id", "away_id", "home_name", "away_name",
    "goals_home", "goals_away"
  ) %in% names(details)))

  expect_equal(details$fixture_id, c(1001, 1002))
  expect_equal(details$round, c(12L, 13L))
  expect_equal(details$status, c("FT", "NS"))
  expect_equal(details$home_id, c(101, 103))
  expect_equal(details$away_id, c(102, 104))
  expect_equal(details$home_name, c("Team A", "Team C"))
  expect_equal(details$away_name, c("Team B", "Team D"))
})

test_that("extract_fixture_details parst die Anstoßzeit als POSIXct in UTC", {
  details <- extract_fixture_details(make_nested_fixtures())

  expect_s3_class(details$kickoff, "POSIXct")
  expect_equal(
    details$kickoff[1],
    as.POSIXct("2026-11-27 19:30:00", tz = "UTC")
  )
})

test_that("extract_fixture_details übernimmt Tore nur als Zahlen, NA für offene Spiele", {
  details <- extract_fixture_details(make_nested_fixtures())

  expect_equal(details$goals_home[1], 2)
  expect_equal(details$goals_away[1], 1)
  expect_true(is.na(details$goals_home[2]))
  expect_true(is.na(details$goals_away[2]))
})

test_that("extract_fixture_details ist positionsgleich mit transform_data", {
  # Beide Funktionen filtern auf Regular-Season-Runden und behalten die
  # API-Reihenfolge — Zeile i beschreibt in beiden dasselbe Spiel. Darauf
  # verlässt sich das Index-Mapping der /league-details-Antwort.
  source("../../RCode/transform_data.R")
  fixtures <- make_nested_fixtures()
  teams <- data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    InitialELO = c(1500, 1500, 1500, 1500),
    stringsAsFactors = FALSE
  )

  details <- extract_fixture_details(fixtures)
  schedule <- transform_data(fixtures, teams)

  expect_equal(nrow(details), nrow(schedule))
  expect_equal(
    teams$ShortText[match(details$home_id, teams$TeamID)],
    schedule$TeamHeim
  )
  expect_equal(
    teams$ShortText[match(details$away_id, teams$TeamID)],
    schedule$TeamGast
  )
})

# --- aus test-fixture-details-produktionsform.R ---
# Regressionstest aus der Phase-4a-QA (2026-08-28): Die echte api-football-
# Antwort kommt über jsonlite::fromJSON (retrieveResults) als FLACHE
# Data-Frame-Struktur — fixture/league/teams/goals sind data.frames mit
# atomaren bzw. df-Spalten, keine Listen von data.frames wie in den
# genesteten Test-Mocks. extract_fixture_details() muss beide Formen
# verarbeiten (Spiegelfall zum transform_data-List-Column-Fix aus Phase 2).

flache_produktions_fixtures <- function() {
  n <- 3
  fx <- data.frame(platzhalter = seq_len(n))

  fixture <- data.frame(
    id = c(3001, 3002, 9999),
    date = c("2026-11-27T19:30:00+00:00", "2026-11-28T14:30:00+00:00",
             "2027-05-27T18:30:00+00:00")
  )
  fixture$status <- data.frame(
    long = c("Match Finished", "Not Started", "Not Started"),
    short = c("FT", "NS", "NS"),
    elapsed = c(90, NA, NA)
  )
  fx$fixture <- fixture

  fx$league <- data.frame(
    id = c(78, 78, 78),
    season = c(2026, 2026, 2026),
    round = c("Regular Season - 12", "Regular Season - 13", "Final")
  )

  teams <- data.frame(platzhalter = seq_len(n))
  teams$home <- data.frame(
    id = c(101, 103, 101),
    name = c("Team A", "Team C", "Team A"),
    winner = c(TRUE, NA, NA)
  )
  teams$away <- data.frame(
    id = c(102, 104, 104),
    name = c("Team B", "Team D", "Team D"),
    winner = c(FALSE, NA, NA)
  )
  teams$platzhalter <- NULL
  fx$teams <- teams

  fx$goals <- data.frame(home = c(2, NA, NA), away = c(1, NA, NA))

  fx$platzhalter <- NULL
  fx
}

test_that("extract_fixture_details verarbeitet die flache Produktionsform", {
  details <- extract_fixture_details(flache_produktions_fixtures())

  expect_equal(nrow(details), 2) # "Final" herausgefiltert
  expect_equal(details$fixture_id, c(3001, 3002))
  expect_equal(details$round, c(12L, 13L))
  expect_equal(details$status, c("FT", "NS"))
  expect_equal(details$home_id, c(101, 103))
  expect_equal(details$away_id, c(102, 104))
  expect_equal(details$home_name, c("Team A", "Team C"))
  expect_equal(details$away_name, c("Team B", "Team D"))
  expect_equal(details$goals_home, c(2, NA))
  expect_equal(
    details$kickoff[1],
    as.POSIXct("2026-11-27 19:30:00", tz = "UTC")
  )
})

test_that("flache und genestete Form liefern identische Details", {
  # Dieselben drei Spiele in der genesteten Mock-Form der frozen Suite.
  genestet <- tibble::tibble(
    fixture = list(
      data.frame(id = 3001, date = "2026-11-27T19:30:00+00:00",
                 status = I(list(data.frame(short = "FT")))),
      data.frame(id = 3002, date = "2026-11-28T14:30:00+00:00",
                 status = I(list(data.frame(short = "NS")))),
      data.frame(id = 9999, date = "2027-05-27T18:30:00+00:00",
                 status = I(list(data.frame(short = "NS"))))
    ),
    league = list(
      data.frame(round = "Regular Season - 12"),
      data.frame(round = "Regular Season - 13"),
      data.frame(round = "Final")
    ),
    teams = list(
      data.frame(home = I(list(data.frame(id = 101, name = "Team A"))),
                 away = I(list(data.frame(id = 102, name = "Team B")))),
      data.frame(home = I(list(data.frame(id = 103, name = "Team C"))),
                 away = I(list(data.frame(id = 104, name = "Team D")))),
      data.frame(home = I(list(data.frame(id = 101, name = "Team A"))),
                 away = I(list(data.frame(id = 104, name = "Team D"))))
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = NA, away = NA),
      data.frame(home = NA, away = NA)
    )
  )

  aus_flach <- extract_fixture_details(flache_produktions_fixtures())
  aus_genestet <- extract_fixture_details(genestet)

  gemeinsame <- c("fixture_id", "round", "kickoff", "status",
                  "home_id", "home_name", "away_id", "away_name",
                  "goals_home", "goals_away")
  expect_equal(aus_flach[, gemeinsame], aus_genestet[, gemeinsame])
})

# --- aus test-ligatabelle.R ---
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
