library(testthat)
source("../../RCode/league_details.R")

# Issue #230: api-football meldet `TBD` ("Time To Be Defined"), wenn das
# Datum eines Spiels feststeht, die Anstoßzeit aber noch nicht. Bis dahin
# galt TBD pauschal als verschoben -- das Spiel fiel aus dem Ausblick, und
# sein Spieltag galt als abgeschlossen (Havelse -- Fortuna Köln, 25.09.2026).
#
# Regel: extract_fixture_details() entscheidet TBD am Kalendertag (Berliner
# Zeit) gegen `jetzt`:
#   - Termin heute oder später -> offenes Spiel, markiert als `zeit_offen`
#   - Termin vor heute         -> bleibt TBD, also verschoben
# Verglichen wird der Tag, nicht die Uhrzeit, weil die API-Uhrzeit bei TBD
# ein Platzhalter ist -- sonst kippte das Spiel am Spieltag selbst vor dem
# Anpfiff in "verschoben".

tbd_fixtures <- function(ids, dates, status, rounds) {
  n <- length(ids)
  tibble::tibble(
    fixture = lapply(seq_len(n), function(i) data.frame(
      id = ids[i], date = dates[i],
      status = I(list(data.frame(short = status[i])))
    )),
    league = lapply(seq_len(n), function(i) {
      data.frame(round = paste0("Regular Season - ", rounds[i]))
    }),
    teams = lapply(seq_len(n), function(i) data.frame(
      home = I(list(data.frame(id = 100 + 2 * i, name = paste0("Heim ", i)))),
      away = I(list(data.frame(id = 101 + 2 * i, name = paste0("Gast ", i))))
    )),
    goals = lapply(seq_len(n), function(i) {
      if (status[i] == "FT") data.frame(home = 1, away = 0)
      else data.frame(home = NA, away = NA)
    })
  )
}

berlin <- function(x) as.POSIXct(x, tz = "Europe/Berlin")

# Der Fall aus #230: 7. Spieltag mit neun beendeten Spielen und einem
# TBD-Spiel am Freitag, 25.09., 8. Spieltag komplett offen.
spieltag_7_mit_tbd <- function() {
  tbd_fixtures(
    ids = c(1:9, 1584010, 11:12),
    dates = c(rep("2026-09-20T12:00:00+00:00", 9),
              "2026-09-25T17:00:00+00:00",
              rep("2026-10-10T12:00:00+00:00", 2)),
    status = c(rep("FT", 9), "TBD", "NS", "NS"),
    rounds = c(rep(7, 10), 8, 8)
  )
}

test_that("TBD mit Termin in der Zukunft ist ein offenes Spiel mit offener Anstoßzeit", {
  details <- extract_fixture_details(
    tbd_fixtures(1, "2026-09-25T17:00:00+00:00", "TBD", 7),
    jetzt = berlin("2026-09-24 10:00")
  )

  expect_false(details$status %in% STATUS_VERSCHOBEN)
  expect_true(details$zeit_offen)
})

test_that("TBD mit Termin in der Vergangenheit bleibt verschoben", {
  details <- extract_fixture_details(
    tbd_fixtures(1, "2026-09-25T17:00:00+00:00", "TBD", 7),
    jetzt = berlin("2026-09-26 10:00")
  )

  expect_true(details$status %in% STATUS_VERSCHOBEN)
  expect_false(details$zeit_offen)
})

test_that("am Spieltag selbst bleibt TBD offen, auch wenn die Platzhalterzeit vorbei ist", {
  # Platzhalter 00:00 Berliner Zeit (22:00 UTC am Vortag), jetzt 18:00 am
  # selben Berliner Kalendertag.
  details <- extract_fixture_details(
    tbd_fixtures(1, "2026-09-24T22:00:00+00:00", "TBD", 7),
    jetzt = berlin("2026-09-25 18:00")
  )

  expect_false(details$status %in% STATUS_VERSCHOBEN)
  expect_true(details$zeit_offen)
})

test_that("Spiele mit anderem Status tragen zeit_offen = FALSE", {
  details <- extract_fixture_details(
    tbd_fixtures(1:3,
                 c("2026-09-20T12:00:00+00:00", "2026-10-10T12:00:00+00:00",
                   "2026-10-10T12:00:00+00:00"),
                 c("FT", "NS", "PST"), c(7, 8, 8)),
    jetzt = berlin("2026-09-24 10:00")
  )

  expect_equal(details$zeit_offen, c(FALSE, FALSE, FALSE))
  expect_equal(details$status, c("FT", "NS", "PST"))
})

test_that("ein künftiges TBD-Spiel hält seinen Spieltag offen und steht im Ausblick (#230)", {
  details <- extract_fixture_details(spieltag_7_mit_tbd(),
                                     jetzt = berlin("2026-09-24 10:00"))

  expect_equal(unname(classify_matchday_status(details)[["7"]]), "laufend")

  ausblick <- ausblick_matches(details)
  expect_equal(ausblick$fixture_id, 1584010)
  expect_true(ausblick$zeit_offen)
})

test_that("ist der TBD-Termin verstrichen, gilt der Spieltag als abgeschlossen", {
  details <- extract_fixture_details(spieltag_7_mit_tbd(),
                                     jetzt = berlin("2026-09-26 10:00"))

  expect_equal(unname(classify_matchday_status(details)[["7"]]), "abgeschlossen")
  expect_equal(unique(ausblick_matches(details)$round), 8L)
})

test_that("der Ausblick zeigt bei offener Anstoßzeit das Datum mit 'Zeit offen'", {
  gen <- local({
    source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
    environment()
  })
  row <- data.frame(
    fixture_id = 1584010, round = 7L,
    kickoff = as.POSIXct("2026-09-25 17:00", tz = "UTC"),
    status = "NS", zeit_offen = TRUE,
    home_id = 1, away_id = 2,
    home_name = "TSV Havelse", away_name = "Fortuna Köln",
    goals_home = NA_real_, goals_away = NA_real_,
    p_home_win = 0.4, p_draw = 0.3, p_away_win = 0.3,
    elo_delta_home = NA_real_, nachholspiel = FALSE,
    stringsAsFactors = FALSE
  )
  row$score_matrix <- list(matrix(1 / 49, 7, 7))

  html <- gen$render_ausblick(row, runde = 7L)

  expect_match(html, "Fr. 25.9., Zeit offen", fixed = TRUE)
  expect_false(grepl("19:00", html, fixed = TRUE))
})
