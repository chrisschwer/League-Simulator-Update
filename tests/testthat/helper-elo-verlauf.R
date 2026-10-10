# Helfer fuer die Tests der ELO-Verlaufsseiten (Issue #184).
#
# verlauf_entry() baut einen league_entry in der Form, die
# build_league_page_data() liefert -- ohne Rust: Die Endpunktspalten
# (played, elo_home_pre, elo_away_pre, elo_delta_home, p_*) entstehen aus
# einem einfachen Walk mit vorgegebenen Heim-Deltas. Gespielt ist ein Spiel
# wie im Seam: Status beendet (STATUS_BEENDET) und beide Tore vorhanden;
# gewertete Spiele (AWD) bewegen das ELO nicht (Issue #157).
#
# verlauf_beispiel(): vier Vereine, drei Runden. Von Hand nachgerechnet
# (Standardfall, laufende Saison):
#   Start          101: 1600  102: 1500  103: 1400  104: 1450
#   f1 R1 101-102 2:1, Delta +10    -> 101 1610, 102 1490
#   f2 R1 103-104 0:0, Delta -2     -> 103 1398, 104 1452
#   f3 R2 102-103 1:1, Delta -1,5   -> 102 1488,5, 103 1399,5
#   f4 R2 104-101 2:0, Delta +40    -> 104 1492, 101 1570
#   f5/f6 R3 offen (NS) am 22.08.
#   Heute: 101 1570, 104 1492, 102 1488,5, 103 1399,5
# f1 hat Anstoss 22:30 UTC am 08.08. -- in Berlin schon der 09.08.

verlauf_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    Promotion = c(0, 0, 0, 0),
    InitialELO = c(1600, 1500, 1400, 1450),
    stringsAsFactors = FALSE
  )
}

verlauf_spiel <- function(fixture_id, round, kickoff, status, home_id, away_id,
                          goals_home = NA_real_, goals_away = NA_real_,
                          delta = NA_real_, p = c(0.5, 0.25, 0.25)) {
  zeile <- fd_row(fixture_id, round, kickoff, status, home_id, away_id,
                  goals_home, goals_away)
  zeile$delta <- delta
  zeile$p_home_win <- p[1]
  zeile$p_draw <- p[2]
  zeile$p_away_win <- p[3]
  zeile
}

verlauf_entry <- function(spiele, teams = verlauf_teams(), namen = NULL) {
  ld <- source_module("league_details")
  spiele <- spiele[order(spiele$kickoff), ]
  rownames(spiele) <- NULL

  elo <- stats::setNames(teams$InitialELO, as.character(teams$TeamID))
  n <- nrow(spiele)
  played <- logical(n)
  pre_h <- numeric(n)
  pre_a <- numeric(n)
  d <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    h <- as.character(spiele$home_id[i])
    a <- as.character(spiele$away_id[i])
    played[i] <- spiele$status[i] %in% ld$STATUS_BEENDET &&
      !is.na(spiele$goals_home[i]) && !is.na(spiele$goals_away[i])
    pre_h[i] <- elo[[h]]
    pre_a[i] <- elo[[a]]
    if (played[i]) {
      d[i] <- spiele$delta[i]
      elo[[h]] <- elo[[h]] + d[i]
      elo[[a]] <- elo[[a]] - d[i]
    }
  }

  details <- spiele[, c("fixture_id", "round", "kickoff", "status", "home_id",
                        "away_id", "home_name", "away_name", "goals_home",
                        "goals_away")]
  endpunkt <- data.frame(
    index = seq_len(n) - 1L, played = played,
    elo_home_pre = pre_h, elo_away_pre = pre_a, elo_delta_home = d,
    p_home_win = spiele$p_home_win, p_draw = spiele$p_draw,
    p_away_win = spiele$p_away_win
  )
  matches <- cbind(details, endpunkt)

  tabelle <- ld$build_league_table(details, teams)
  tabelle$name <- paste("Team", tabelle$team_id)
  if (!is.null(namen)) {
    treffer <- match(names(namen), as.character(tabelle$team_id))
    tabelle$name[treffer] <- unname(namen)
  }
  tabelle$kuerzel <- teams$ShortText[match(tabelle$team_id, teams$TeamID)]
  tabelle$elo <- unname(elo[as.character(tabelle$team_id)])
  tabelle$delta_elo <- tabelle$elo -
    teams$InitialELO[match(tabelle$team_id, teams$TeamID)]

  list(details = details, teams = teams, matches = matches,
       current_elos = unname(elo[as.character(teams$TeamID)]),
       tabelle = tabelle)
}

verlauf_beispiel <- function(laeuft = TRUE, nachhol = FALSE, gewertet = FALSE,
                             verschoben = FALSE, abgesagt = FALSE,
                             leer = FALSE, nur_erstes = FALSE,
                             pause_tage = 0, namen = NULL) {
  # pause_tage verschiebt Runde 2 und 3 nach hinten (Winterpause).
  t2 <- function(x) {
    format(as.POSIXct(x, tz = "UTC") + pause_tage * 86400, "%Y-%m-%d %H:%M:%S",
           tz = "UTC")
  }
  f4_zeit <- if (nachhol) "2026-08-26 18:30:00" else "2026-08-15 16:30:00"
  spiele <- rbind(
    verlauf_spiel(1, 1, "2026-08-08 22:30:00", "FT", 101, 102, 2, 1,
                  delta = 10, p = c(0.6, 0.25, 0.15)),
    if (gewertet) {
      verlauf_spiel(2, 1, "2026-08-09 13:30:00", "AWD", 103, 104, 0, 3)
    } else {
      verlauf_spiel(2, 1, "2026-08-09 13:30:00", "FT", 103, 104, 0, 0, delta = -2)
    },
    verlauf_spiel(3, 2, t2("2026-08-15 13:30:00"), "FT", 102, 103, 1, 1,
                  delta = -1.5),
    if (verschoben) {
      verlauf_spiel(4, 2, t2("2026-08-15 16:30:00"), "PST", 104, 101)
    } else {
      verlauf_spiel(4, 2, t2(f4_zeit), "FT", 104, 101, 2, 0, delta = 40,
                    p = c(0.2, 0.3, 0.5))
    },
    if (laeuft) {
      verlauf_spiel(5, 3, t2("2026-08-22 13:30:00"), "NS", 101, 103)
    } else {
      verlauf_spiel(5, 3, t2("2026-08-22 13:30:00"), "FT", 101, 103, 1, 0, delta = 5)
    },
    if (laeuft) {
      verlauf_spiel(6, 3, t2("2026-08-22 13:30:00"), "NS", 102, 104)
    } else if (abgesagt) {
      verlauf_spiel(6, 3, t2("2026-08-22 13:30:00"), "CANC", 102, 104)
    } else {
      verlauf_spiel(6, 3, t2("2026-08-22 13:30:00"), "FT", 102, 104, 1, 1, delta = -3)
    }
  )
  offen <- if (leer) rep(TRUE, nrow(spiele)) else if (nur_erstes) spiele$fixture_id != 1 else NULL
  if (!is.null(offen)) {
    spiele$status[offen] <- "NS"
    spiele$goals_home[offen] <- NA_real_
    spiele$goals_away[offen] <- NA_real_
  }
  verlauf_entry(spiele, namen = namen)
}

# Rendert die Site mit der Preview-Fixture (make_data_env) und `league_data`
# in ein temporaeres Verzeichnis, das mit `envir` aufgeraeumt wird.
verlauf_site <- function(league_data, envir = parent.frame()) {
  gen <- source_module("generate_static_site")
  out <- withr::local_tempdir(.local_envir = envir)
  suppressMessages(gen$generate_static_site(
    ergebnisse = ergebnisse_aus_env(make_data_env()), output_dir = out,
    now = as.POSIXct("2026-10-10 12:00:00", tz = "Europe/Berlin"),
    league_data = league_data
  ))
  out
}
