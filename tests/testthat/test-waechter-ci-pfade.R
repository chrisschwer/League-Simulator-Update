# Issue #146, Teil 2: EIN ELO-Walk statt zweier.
#
# WORUM ES GEHT. Das Projekt rechnet ELO an zwei Stellen -- und zwar mit
# verschiedenen Heimvorteilen:
#
#   Prognose   (Rust, /simulate und /league-details)  home_advantage = 40
#   Saisonwechsel (R, calculate_elo_update)           home_advantage = 100
#
# Nachgeprueft im Design vom 12.09.2026: Die beiden Formeln sind sonst
# MATHEMATISCH IDENTISCH -- dieselbe Clamp auf +/-400, dieselbe Wurzel der
# Tordifferenz (Minimum 1), derselbe K-Faktor 20, dieselbe Erwartungsformel.
# Sie unterscheiden sich in genau diesem einen Wert.
#
# Der R-Walk ist damit kein zweites Modell, sondern ein DUPLIKAT mit einem
# abweichenden Parameter. Die Start-ELOs jeder neuen Saison entstehen auf
# einer Physik, mit der anschliessend keine einzige Prognose rechnet.
#
# WARUM NICHT EINFACH 40 EINSETZEN. Weil die beiden Werte gar nicht
# vergleichbar sind: In Rust wirkt der Heimvorteil ueber das Poisson-Tormodell
# (tore_slope), in R ueber die ELO-Erwartungsformel. An den beobachteten
# Anteilen geeicht laege der R-Wert bei ~25,8. Eine 25,8 einzutragen hiesse,
# die zweite Physik zu konservieren -- mit einer Zahl, die niemand mehr mit
# der 40 der Prognose in Beziehung setzen kann. Die einzige Variante, die
# EINEN Heimvorteil herstellt, ist die Loeschung (Design, Abschnitt Context).
#
# WAS DIESE DATEI ABSICHERT. Die drei R-Funktionen calculate_final_elos(),
# update_elos_for_match() und calculate_elo_update() entfallen; die End-ELOs
# des Saisonwechsels kommen kuenftig ueber POST /league-details, also aus
# demselben Rust-Walk, der auch jede Prognose rechnet. Damit erfuellt der
# Saisonwechsel endlich, was ADR 0002 verlangt: keine Modelllogik in R.
#
# Die Tests sind ROT, solange die Umstellung nicht implementiert ist. Sie
# beschreiben den Sollzustand, nicht den heutigen.
#
# ----------------------------------------------------------------------------
# ZWEI ENTWURFSENTSCHEIDUNGEN, DIE DIESE TESTS FESTSCHREIBEN
#
# (1) ZWEI INJIZIERBARE SEAMS. Die Tests duerfen weder einen laufenden
#     Rust-Server noch einen API-Schluessel brauchen. calculate_final_elos()
#     bekommt deshalb zwei Parameter mit Produktions-Defaults, genau wie
#     build_league_page_data() es vormacht (league_details.R:
#     `fetch_fn = fetch_league_details`):
#
#       calculate_final_elos(season,
#                            fetch_fn    = fetch_league_details,
#                            fixtures_fn = retrieveResults)
#
#     WARUM ZWEI und nicht einer: extract_fixture_details() braucht die ROHEN
#     api-football-Fixtures (verschachtelte fixture/league/teams/goals-Spalten).
#     fetch_league_results() -- die Quelle des alten Walks -- liefert bereits
#     ein FLACHGEKLOPFTES data.frame mit Spalten wie `teams_home_id`; das
#     passt nicht in extract_fixture_details(). Der Fixture-Seam muss also
#     retrieveResults()-Gestalt liefern, und der Endpoint-Seam ist davon
#     unabhaengig.
#
#     Sollte die Implementierung die Parameter anders benennen, sind diese
#     Tests entsprechend anzupassen -- die SACHE, die sie pruefen, bleibt:
#     die End-ELOs kommen aus dem Endpoint, nicht aus einer R-Rechnung.
#
# (2) DIE MOCK-ANTWORT FOLGT DEM GESENDETEN PAYLOAD. Seit PR #200 sortiert
#     extract_fixture_details() chronologisch; eine Mock-Antwort mit fest
#     verdrahteter Reihenfolge wuerde deshalb still am Payload vorbeigehen.
#     antwort_zum_payload() unten liest `elo_values` und `team_names` aus dem
#     tatsaechlich gesendeten Payload und baut die Antwort daraus -- dasselbe
#     Muster wie in test-league-page-data-*.R.

library(testthat)

source("../../RCode/league_details.R")


# =============================================================================
# 6. Damit die Umstellung in der CI ueberhaupt geprueft wird
# =============================================================================

test_that("rust_binary findet das Binary auch am Ort des Produktionsimages", {
  # ENTSCHEIDUNG DES USERS (Issue #146, Teil 2).
  #
  # Der Befund, der diesen Test ausgeloest hat: Die R-Suite laeuft in der CI
  # IM PRODUKTIONSIMAGE (ci.yml, Job "image-build-and-test"). Dort liegt das
  # Binary nach Dockerfile:116 unter /usr/local/bin/ -- den Entwicklerpfad
  # target/release/ gibt es im Image nicht, weil der Rust-Build in einer
  # verworfenen Build-Stage passiert.
  #
  # test-rust-required.R hat sich deshalb seit jeher still uebersprungen. Das
  # faellt nicht auf: Ein Skip ist gruen. Genau deshalb steht hier ein Test --
  # er prueft die SUCHE, nicht den Fund, und bleibt damit auf jeder Maschine
  # aussagekraeftig, auch ohne gebautes Binary.
  # rust_binary() steht seit Stufe 3.6 in helper-rust.R.
  quelle <- readLines(test_path("helper-rust.R"), warn = FALSE)
  code <- paste(quelle, collapse = "\n")

  expect_match(code, "/usr/local/bin/league-simulator-rust", fixed = TRUE,
               info = paste("Ohne diesen Pfad prueft test-update_all_leagues_loop-rust.R in",
                            "der CI nichts -- es skippt sich still."))
  expect_match(code, "target", fixed = TRUE,
               info = "Der Entwicklerpfad muss erhalten bleiben.")
})

test_that("der Snapshot-Test des Saisonwechsels faehrt die echte ELO-Kette", {
  # ENTSCHEIDUNG DES USERS: Der Snapshot-Test darf einen Rust-Server
  # voraussetzen -- damit die ECHTE Kette einschliesslich ELO-Physik geprueft
  # bleibt, statt sie hinter einer Kassette wegzumocken.
  #
  # Bei der Umsetzung ergab sich die bessere Haelfte beider Varianten: Die
  # /league-details-Antworten wurden gegen die echte Engine aufgezeichnet und
  # liegen als httptest-Kassetten vor. Die Physik ist damit in der geprueften
  # Kette -- die Zahlen im Snapshot stammen aus dem Rust-Walk --, aber weder
  # CI noch Entwicklerrechner brauchen einen laufenden Server.
  #
  # Was dieser Test festhaelt: dass die Kette den Endpoint ueberhaupt anfasst.
  # Ohne die Kassetten liefe der Snapshot-Lauf daran vorbei, und der Test
  # pruefte wieder nur noch CSV-Formatierung.
  runner <- paste(
    readLines(test_path("helpers", "season-transition-snapshot-runner.R"),
              warn = FALSE),
    collapse = "\n")

  expect_match(runner, "league_details.R", fixed = TRUE,
               info = paste("Nach Teil 2 holt der Saisonwechsel die End-ELOs",
                            "ueber /league-details; ohne dieses Modul bricht",
                            "der Subprozess ab."))

  kassetten <- list.files(
    test_path("fixtures", "season-transition-2024-to-2025"),
    pattern = "league-details.*\\.json$", recursive = TRUE)
  expect_gt(length(kassetten), 0)
})
