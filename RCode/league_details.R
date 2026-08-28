# Spieldetails für die statische Seite (ADR 0002): Spieltag-Klassifikation,
# Rückblick-/Ausblick-Fensterung, Ligatabelle und der Client für den
# deterministischen Rust-Endpoint POST /league-details.
#
# Phase 2, TDD: Die Signaturen stehen, die Implementierung folgt nach dem
# Review der Tests (tests/testthat/test-fixture-details.R,
# test-spieltag-logik.R, test-ligatabelle.R, test-league-details-client.R).
# Die Tests definieren die Semantik; Kurzfassung:
#
# - Statusgruppen (api-football `fixture$status$short`):
#     beendet    = FT, AET, PEN
#     live       = 1H, HT, 2H, ET, BT, P, SUSP, INT, LIVE
#     verschoben = PST, CANC, TBD, ABD
#     offen      = alles andere (insb. NS)
# - Ein Spieltag ist "abgeschlossen", wenn mindestens ein Spiel beendet ist,
#   kein Spiel live ist und jedes Spiel beendet oder verschoben ist;
#   "laufend", wenn er begonnen hat (>= 1 beendet/live) und nicht abgeschlossen
#   ist; sonst "ausstehend".
# - Der aktuelle Spieltag ist der HÖCHSTE begonnene (ein wieder angesetztes
#   Nachholspiel macht seinen alten Spieltag nicht zum aktuellen).
# - Rückblick: alle beendeten Spiele mit Anstoß >= Beginn (früheste
#   Anstoßzeit) des zuletzt abgeschlossenen Spieltags; Spiele älterer Runden
#   werden als Nachholspiel markiert.
# - Ausblick: Ziel ist der laufende Spieltag, sonst die kleinste Runde über
#   dem aktuellen mit offenen Spielen; aufgenommen werden alle offenen, nicht
#   verschobenen Spiele mit Anstoß bis zum letzten offenen Spiel des Ziels
#   (früher angesetzte Nachholspiele eingeschlossen, markiert).

extract_fixture_details <- function(fixtures) {
  stop("noch nicht implementiert (Phase 2, nach Test-Review)")
}

classify_matchday_status <- function(details) {
  stop("noch nicht implementiert (Phase 2, nach Test-Review)")
}

current_matchday <- function(details) {
  stop("noch nicht implementiert (Phase 2, nach Test-Review)")
}

rueckblick_matches <- function(details) {
  stop("noch nicht implementiert (Phase 2, nach Test-Review)")
}

ausblick_matches <- function(details) {
  stop("noch nicht implementiert (Phase 2, nach Test-Review)")
}

# Laufende Spiele werden auf der Seite berichtet (Zwischenstand), aber ohne
# Prognose — mit dem Hinweis, dass Prognosen während des Spiels nicht
# aktualisiert werden (Planergänzung 2026-08-28).
live_matches <- function(details) {
  stop("noch nicht implementiert (Phase 2, nach Test-Review)")
}

build_league_table <- function(details, teams) {
  stop("noch nicht implementiert (Phase 2, nach Test-Review)")
}

build_league_details_payload <- function(details, teams, mod_factor = 20,
                                         home_advantage = 65, max_goals = 6) {
  stop("noch nicht implementiert (Phase 2, nach Test-Review)")
}

parse_league_details_response <- function(json_text) {
  stop("noch nicht implementiert (Phase 2, nach Test-Review)")
}
