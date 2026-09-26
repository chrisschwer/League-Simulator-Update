# Issue #226: Das Sicherheitsnetz des Loops misst Zeit, nicht Runden.
#
# Es ist der einzige Ausloeser fuer Spiele, die nie live waren (etwa eine
# Partie, die bei der Quelle auf NS eingefroren ist). Frueher griff es nach
# einer festen Zahl von Runden (30). Seit der Takt-Regler (#222) den Takt
# streckt, wurde daraus bei 5400 s Takt ein Abstand von 45 Stunden -- mehr
# als das ganze Tagesfenster. Jetzt gilt: spaetestens alle
# `full_fetch_mindestens_alle` Sekunden (Default 3600) ein Vollabruf,
# gleich wie weit die Runden auseinanderliegen.
#
# Kosten: Der Regler plant jede Runde ohnehin als Vollabruf
# (expected_cost_per_loop = 1 + Ligen). Ein Netz, das hoechstens einmal je
# Runde feuert, kann deshalb nie mehr verbrauchen, als eingeplant ist.

library(testthat)
library(mockery)

source("../../RCode/update_all_leagues_loop.R")

# fake_fixtures() und fake_transformed() stehen in helper-fixtures.R.

# Durchgehend leere Runden im Abstand `takt`; zurueck kommen die Runden, in
# denen voll abgerufen wurde. Nur Loop 1 und das Netz koennen hier abrufen.
idle_lauf <- function(takt, loops, ...) {
  uhr <- runden_uhr(takt)
  fetch_loops <- integer(0)

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    if (league == "78") fetch_loops <<- c(fetch_loops, uhr$runde())
    fake_fixtures(c("FT", "NS"))
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures",
       uhr$tick(function(...) integer(0)))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) invisible(character(0)))

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = loops, initial_wait = 0, n = 10,
      saison = "2024",
      TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), jetzt = uhr$jetzt, ...
    )
  })
  fetch_loops
}

test_that("bei gestrecktem Takt greift das Netz nach einer Stunde, nicht nach 30 Runden", {
  # 90-Minuten-Takt (Regler-Maximum 5400 s): Jede Runde liegt mehr als eine
  # Stunde nach dem letzten Vollabruf, also ist jede Runde faellig. Mit dem
  # alten Rundenzaehler kaeme erst Loop 31 -- nach 45 Stunden.
  expect_identical(idle_lauf(takt = 5400, loops = 4), 1:4)
})

test_that("bei 10-Minuten-Takt greift das Netz nach sechs Runden", {
  # Loop 1 um 0 s, Loop 7 um 3600 s: genau eine Stunde -> faellig.
  expect_identical(idle_lauf(takt = 600, loops = 8), c(1L, 7L))
})

test_that("im Normaltakt bleibt es bei einem Netz-Abruf je Stunde", {
  # 120 s Takt: Loop 31 steht auf 3600 s. Das ist exakt das bisherige
  # Verhalten mit 30 Runden -- der Normalbetrieb aendert sich nicht.
  expect_identical(idle_lauf(takt = 120, loops = 31), c(1L, 31L))
})

test_that("das Intervall ist einstellbar und wird in Sekunden gelesen", {
  expect_identical(
    idle_lauf(takt = 600, loops = 5, full_fetch_mindestens_alle = 1200),
    c(1L, 3L, 5L)
  )
})
