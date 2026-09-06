library(testthat)

# Phase 3, R-Seite: die Uebersetzung Stammregion -> Staffel-Index.
#
# Die Engine identifiziert Teams durchgaengig ueber die POSITION im Vektor
# (elo_values, adj_points, elo_neutral). `group_of_team` folgt dem: ein
# Integer je Team, der auf eine Zeile der Ergebnismatrix zeigt.
#
# Real steht die Stammregion aber als STRING in der Region-Spalte der
# TeamList ("Bayern", "Nord", "Nordost", "SuedWest", "West"). Zwischen beidem
# liegt eine Uebersetzung -- und genau dort entstuende ein stiller Fehler:
# Verrutscht die Zuordnung, zaehlt die Engine die Absteiger der falschen
# Staffel zu, ohne dass irgendetwas fehlschlaegt.
#
# Diese Tests sichern die Uebersetzung an ihren Raendern ab. Zwei davon sind
# nicht theoretisch: In TeamList_2026 haben sieben Drittliga-Teams KEINE
# Region, und "Nordost" kommt dort gar nicht vor -- obwohl Erzgebirge Aue
# dorthin abgestiegen ist.

source_zuordnung <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  env
}

test_that("die Staffeln haben eine feste, dokumentierte Reihenfolge", {
  # Die Reihenfolge ist Vertrag: Sie bestimmt, welche Zeile der
  # Ergebnismatrix zu welcher Staffel gehoert. Aendert sie sich unbemerkt,
  # werden die Zahlen vertauscht.
  env <- source_zuordnung()

  expect_equal(env$STAFFELN,
               c("Nord", "Nordost", "West", "SuedWest", "Bayern"))
})

test_that("staffel_index uebersetzt die Regionsnamen", {
  env <- source_zuordnung()

  expect_equal(env$staffel_index("Nord"), 0L)
  expect_equal(env$staffel_index("Bayern"), 4L)
  # Vektorwertig, in Eingabereihenfolge.
  expect_equal(env$staffel_index(c("West", "Nord", "Bayern")), c(2L, 0L, 4L))
})

test_that("Teams ohne Region bekommen keinen Staffel-Index", {
  # Sieben Drittliga-Teams in TeamList_2026 haben eine leere Region -- sie
  # sind (noch) keiner Staffel zugeordnet. Sie duerfen nicht stillschweigend
  # in Staffel 0 landen.
  env <- source_zuordnung()

  expect_true(is.na(env$staffel_index("")))
  expect_true(is.na(env$staffel_index(NA_character_)))
})

test_that("eine unbekannte Region bricht ab", {
  # Ein Tippfehler in der TeamList waere sonst ein stiller Fehler: Das Team
  # verschwaende aus der Zaehlung, ohne dass es auffiele.
  env <- source_zuordnung()

  err <- expect_error(env$staffel_index("Suedost"))
  expect_match(conditionMessage(err), "Suedost")
})

test_that("group_of_team folgt der Teamreihenfolge des Spielplans", {
  # Der eigentliche Kern: Die Engine ordnet ueber die Position zu. Der
  # Vektor muss also exakt so lang sein wie die Teamliste des Spielplans und
  # in derselben Reihenfolge stehen -- nicht in der der TeamList.
  env <- source_zuordnung()

  teams <- data.frame(
    ShortText = c("AAA", "BBB", "CCC"),
    Region = c("West", "Nord", "West"),
    stringsAsFactors = FALSE
  )

  # Spalten des Simulations-Data-Frames, absichtlich in anderer Reihenfolge
  # als die TeamList.
  expect_equal(env$group_of_team(c("BBB", "AAA", "CCC"), teams),
               c(0L, 2L, 2L))
})

test_that("group_of_team meldet ein unbekanntes Team", {
  env <- source_zuordnung()
  teams <- data.frame(ShortText = "AAA", Region = "Nord", stringsAsFactors = FALSE)

  err <- expect_error(env$group_of_team(c("AAA", "XXX"), teams))
  expect_match(conditionMessage(err), "XXX")
})

# --- End-to-End: von der TeamList bis zur Engine-Antwort --------------------

test_that("die Zuordnung traegt die echte 3. Liga", {
  # Gegen die produktive TeamList, nicht gegen eine Fixture: Sieben Teams
  # ohne Region und eine Staffel (Nordost), die dort gar nicht vorkommt --
  # beides muss die Uebersetzung aushalten.
  env <- source_zuordnung()
  suppressMessages({
    library(dplyr); library(tidyr)
  })
  source(test_path("..", "..", "RCode", "transform_data.R"), local = env)

  tl <- env$load_team_list(test_path("..", "..", "RCode", "TeamList_2026.csv"))
  liga3 <- tl[tl$League == 80, ]

  idx <- env$group_of_team(liga3$ShortText, liga3)

  expect_length(idx, nrow(liga3))
  # Teams ohne Region tragen NA, nicht 0.
  expect_equal(sum(is.na(idx)), sum(liga3$Region == ""))
  # Die zugeordneten Indizes liegen im gueltigen Bereich.
  expect_true(all(idx[!is.na(idx)] %in% seq_along(env$STAFFELN) - 1L))
})

test_that("Engine-Antwort und Staffelnamen passen zusammen", {
  # Der End-to-End-Test der Uebersetzung: Ein Spielplan, in dem bekannt ist,
  # welche Teams absteigen -- und die Kontrolle, dass die Zaehlung in der
  # ERWARTETEN Zeile landet.
  #
  # Zwei Teams aus "Nord" (Index 0) sind sicher die schlechtesten; die
  # Engine muss ihre Abstiege in Zeile 1 der Matrix zaehlen, nicht in einer
  # anderen.
  skip_if_not(nzchar(Sys.getenv("RUST_API_URL", "http://localhost:8080")))
  env <- source_zuordnung()
  source(test_path("..", "..", "RCode", "rust_integration.R"), local = env)
  skip_if_not(env$connect_rust_simulator(), "Rust-Server nicht erreichbar")

  # Vier Teams: AAA/BBB in Nord, CCC/DDD in Bayern. AAA und BBB verlieren
  # alles, sind also sicher die letzten beiden.
  teams <- data.frame(
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    Region = c("Nord", "Nord", "Bayern", "Bayern"),
    stringsAsFactors = FALSE
  )
  idx <- env$group_of_team(teams$ShortText, teams)
  expect_equal(idx, c(0L, 0L, 4L, 4L))

  res <- env$simulate_league_rust(
    schedule = matrix(c(3, 1, 9, 0,
                        4, 1, 9, 0,
                        3, 2, 9, 0,
                        4, 2, 9, 0,
                        1, 2, 0, 0,
                        3, 4, 0, 0), ncol = 4, byrow = TRUE),
    elo_values = rep(1500, 4),
    team_names = teams$ShortText,
    iterations = 200,
    group_of_team = idx,
    relegation_places = 2
  )

  counts <- res$relegation_group_counts
  # Fuenf Zeilen -- eine je Staffel, auch fuer die ohne Teams.
  expect_length(counts, length(env$STAFFELN))
  # Nord (Zeile 1) stellt immer beide Absteiger, Bayern (Zeile 5) nie einen.
  expect_equal(counts[[1]][[3]], 200)
  expect_equal(counts[[5]][[1]], 200)
})
