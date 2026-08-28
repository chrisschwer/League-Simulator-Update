# Helfer für die Spieldetail-Tests: baut das flache details-Data-Frame,
# das extract_fixture_details() liefert (eine Zeile je Spiel).

fd_row <- function(fixture_id, round, kickoff, status, home_id, away_id,
                   goals_home = NA_real_, goals_away = NA_real_,
                   home_name = paste("Team", home_id),
                   away_name = paste("Team", away_id)) {
  data.frame(
    fixture_id = fixture_id,
    round = as.integer(round),
    kickoff = as.POSIXct(kickoff, tz = "UTC"),
    status = status,
    home_id = home_id,
    away_id = away_id,
    home_name = home_name,
    away_name = away_name,
    goals_home = goals_home,
    goals_away = goals_away,
    stringsAsFactors = FALSE
  )
}

make_details <- function(...) {
  do.call(rbind, list(...))
}

# Vier Testteams im TeamList-Format (Reihenfolge ist die Payload-Reihenfolge).
make_test_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    Promotion = c(0, 0, 0, 0),
    InitialELO = c(1500, 1500, 1500, 1500),
    stringsAsFactors = FALSE
  )
}
