# Helper functions and fixtures for unit tests

# Create a simple test season with 4 teams and 12 games (each team plays 3 games)
create_test_season <- function(games_played = 0) {
  # Season matrix: columns are TeamHome, TeamAway, GoalsHome, GoalsAway
  season <- matrix(NA, nrow = 12, ncol = 4)
  
  # Define match schedule (round-robin subset)
  matches <- list(
    c(1, 2), c(3, 4),  # Round 1
    c(1, 3), c(2, 4),  # Round 2
    c(1, 4), c(2, 3),  # Round 3
    c(2, 1), c(4, 3),  # Round 4
    c(3, 1), c(4, 2),  # Round 5
    c(4, 1), c(3, 2)   # Round 6
  )
  
  for (i in 1:12) {
    season[i, 1:2] <- matches[[i]]
  }
  
  # Fill in results for played games
  if (games_played > 0) {
    results <- list(
      c(2, 1), c(3, 1),  # Round 1: Home wins
      c(1, 1), c(2, 2),  # Round 2: Draw and draw
      c(0, 2), c(1, 0),  # Round 3: Away win and home win
      c(1, 2), c(2, 0),  # Round 4: Away win and home win
      c(2, 1), c(1, 1),  # Round 5: Home win and draw
      c(3, 0), c(0, 1)   # Round 6: Home win and away win
    )
    
    for (i in 1:min(games_played, 12)) {
      season[i, 3:4] <- results[[i]]
    }
  }
  
  return(season)
}

# Create test adjustments
create_test_adjustments <- function(num_teams = 4, type = "none") {
  if (type == "none") {
    return(rep(0, num_teams))
  } else if (type == "points") {
    # Team 1 gets -6 points penalty, team 3 gets +3 bonus
    adj <- rep(0, num_teams)
    adj[1] <- -6
    adj[3] <- 3
    return(adj)
  } else if (type == "goals") {
    # Various goal adjustments
    return(c(2, -1, 0, 1)[1:num_teams])
  } else if (type == "goals_against") {
    # Goals against adjustments
    return(c(-2, 1, 0, -1)[1:num_teams])
  } else if (type == "goal_diff") {
    # Goal difference adjustments
    return(c(1, -2, 3, 0)[1:num_teams])
  }
}

# Create test fixtures for transform_data.R
create_test_fixtures_api <- function() {
  # Create a tibble that mimics the API response structure
  # The key is that each row's columns contain data frames that will be unnested
  fixtures <- tibble::tibble(
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
        away = I(list(data.frame(id = 103, name = "Team C")))
      )
    ),
    goals = list(
      data.frame(home = 2, away = 1),
      data.frame(home = 1, away = 1),
      data.frame(home = NA, away = NA)  # Use NA instead of NULL for unplayed games
    ),
    fixture = list(
      data.frame(id = 1001, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 1002, status = I(list(data.frame(short = "FT")))),
      data.frame(id = 1003, status = I(list(data.frame(short = "NS"))))
    )
  )
  return(fixtures)
}

# Create test teams data for transform_data.R
create_test_teams_api <- function() {
  # Create a data frame in the format transform_data expects
  teams <- data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("TEA", "TEB", "TEC", "TED"),
    InitialELO = c(1500, 1450, 1550, 1400),
    stringsAsFactors = FALSE
  )
  return(teams)
}

# Helper to create a completed season for table testing
create_completed_season <- function() {
  season <- create_test_season(12)
  # Ensure we have a variety of results for proper table testing
  return(season)
}

# Prognose-Attrappe: gleichverteilte Prognose (1/n je Platz), damit die
# erwarteten Prozentwerte der Panels exakt bekannt sind. Bisher kopiert in
# test-generate_static_site.R und test-rl_abstiegskopplung.R (#211, Stufe 2, T7).
mk_ergebnis <- function(teams) {
  m <- matrix(1 / teams, nrow = teams, ncol = teams,
              dimnames = list(paste0("T", seq_len(teams)),
                              as.character(seq_len(teams))))
  as.table(m)
}

# ELO-Walk-Attrappen: bisher kopiert in test-league_details.R und
# test-transform_data.R (#211, Stufe 2, T7).

# Ein Spiel als Liste der vier List-Column-Bausteine.
ewr_spiel <- function(fixture_id, datum, status, heim_id, gast_id,
                      tore_heim = NA_real_, tore_gast = NA_real_,
                      runde = 1L) {
  list(
    teams = data.frame(
      home = I(list(data.frame(id = heim_id, name = paste("Team", heim_id)))),
      away = I(list(data.frame(id = gast_id, name = paste("Team", gast_id))))
    ),
    goals = data.frame(home = tore_heim, away = tore_gast),
    fixture = data.frame(
      id = fixture_id,
      date = datum,
      status = I(list(data.frame(short = status)))
    ),
    league = data.frame(round = paste("Regular Season -", runde))
  )
}

# Aus mehreren ewr_spiel()-Ergebnissen den fixtures-Tibble bauen, wie ihn
# retrieveResults() liefert.
ewr_fixtures <- function(...) {
  spiele <- list(...)
  tibble::tibble(
    teams   = lapply(spiele, `[[`, "teams"),
    goals   = lapply(spiele, `[[`, "goals"),
    fixture = lapply(spiele, `[[`, "fixture"),
    league  = lapply(spiele, `[[`, "league")
  )
}

# Vier Teams, Kurznamen wie in helper-fixtures.R.
ewr_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("TEA", "TEB", "TEC", "TED"),
    InitialELO = c(1500, 1450, 1550, 1400),
    stringsAsFactors = FALSE
  )
}

# Regionalliga-Testkonstanten: bisher kopiert in test-generate_static_site.R,
# test-league_registry.R, test-league_views.R und test-round_filter.R
# (#211, Stufe 2, T7).
RL_IDS <- c("84", "85", "87", "86", "83")
RL_SLUGS <- c("rl-nord", "rl-nordost", "rl-west", "rl-suedwest", "rl-bayern")

# Die fuenf RL in Registry-Reihenfolge. Sie ist Vertrag (Fetch-Reihenfolge
# und Navigation), deshalb hier einmal ausgeschrieben. Bisher kopiert in
# test-generate_static_site.R, test-league_registry.R, test-league_views.R
# und test-rl_abstiegskopplung.R (#211, Stufe 3.6).
RL_SCHLUESSEL <- c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest",
                   "rl_bayern")

# Slug der Seite "Aufstieg in die 3. Liga". Steht hier und nicht erst bei
# den Aufstiegstests: testthat wertet Top-Level-Code sequenziell aus, und
# die Navigations- und Seitenzahl-Tests weiter oben brauchen den Wert
# bereits.
AUFSTIEGSSEITE_SLUG <- "rl-aufstieg"

# Die Staffeln mit Direktaufstieg 2026/27 (Par. 55b DFB-SpO Nr. 2 plus der
# Rotationsplatz, den 2026/27 Nordost traegt).
RL_DIREKTAUFSTIEG <- c("rl_nordost", "rl_west", "rl_suedwest")
# Nord und Bayern spielen stattdessen zwei Aufstiegsspiele gegeneinander.
RL_AUFSTIEGSSPIELE <- c("rl_nord", "rl_bayern")

# --- Regionalliga-Aufstieg-Attrappen ------------------------------------------
# Gebraucht in test-rl_aufstieg.R und test-aufstiegsspiele.R (#211, Stufe 3.6).

# Prognosematrix (Teams x Plaetze) aus den Meisterwahrscheinlichkeiten; der
# Rest der Masse liegt auf Platz 2, damit jede Zeile summiert.
prognose_aus_meister <- function(p_meister, teams = 18L) {
  m <- matrix(0, nrow = length(p_meister), ncol = teams,
              dimnames = list(names(p_meister), as.character(seq_len(teams))))
  m[, 1] <- p_meister
  m[, 2] <- 1 - p_meister
  m
}

# Das Rechenbeispiel fuer die Doppelsumme. X = Nord {A, B}, Y = Bayern {C, D}.
#   P(A) = 0.6 * (0.7 * 0.5 + 0.3 * 0.8) = 0.6 * 0.59 = 0.354
#   P(B) = 0.4 * (0.7 * 0.3 + 0.3 * 0.6) = 0.4 * 0.39 = 0.156
#   P(C) = 0.7 * (0.6 * 0.5 + 0.4 * 0.7) = 0.7 * 0.58 = 0.406
#   P(D) = 0.3 * (0.6 * 0.2 + 0.4 * 0.4) = 0.3 * 0.28 = 0.084
# Summe ueber beide Staffeln: 1.000 -- genau einer steigt auf.
meister_nord <- c(A = 0.6, B = 0.4)
meister_bayern <- c(C = 0.7, D = 0.3)
sieg_nord_gegen_bayern <- matrix(c(0.5, 0.8,
                                   0.3, 0.6), nrow = 2, byrow = TRUE,
                                 dimnames = list(c("A", "B"), c("C", "D")))

# Prognosen aller fuenf Staffeln fuer die ganze Kette rl_aufstiegsprognose().
prognosen_2026 <- function() {
  list(
    Nord     = prognose_aus_meister(meister_nord),
    Nordost  = prognose_aus_meister(c(E = 0.9, F = 0.1)),
    West     = prognose_aus_meister(c(G = 0.55, H = 0.45)),
    SuedWest = prognose_aus_meister(c(I = 1.0, J = 0.0)),
    Bayern   = prognose_aus_meister(meister_bayern, teams = 19L)
  )
}

# --- Abstiegskopplung-Attrappen -----------------------------------------------
# Gebraucht in test-rl_abstiegskopplung.R und test-rl_abstiegskopplung-nord.R
# (#211, Stufe 3.6).

STAFFELN_ERWARTET <- c("Nord", "Nordost", "West", "SuedWest", "Bayern")
# zaehlung() und zaehlung_nordost89() lesen N_ITER als freie Variable, und
# Erwartungen in beiden Kopplungsdateien rechnen damit -- deshalb steht es
# hier und nicht lokal. Die Loop-Verdrahtung hat ihr eigenes N_ITER_LOOP.
N_ITER <- 10000
K_DRITTE_LIGA <- 4L  # Absteiger der 3. Liga; Spalten 0..4

# Zaehlmatrix der 3. Liga bauen. Jede nicht genannte Staffel bekommt
# "immer 0 Drittliga-Absteiger". ACHTUNG: In einer echten Zaehlung entfallen
# in JEDER Iteration genau K Absteiger auf die fuenf Staffeln zusammen --
# die Summe der Erwartungswerte ueber alle Zeilen muss also exakt K sein.
# Alle Fixtures erfuellen das; ein Fixture, das es verletzt, muss die
# Implementierung ablehnen (eigener Test).
zaehlung <- function(...) {
  m <- matrix(0, nrow = 5, ncol = K_DRITTE_LIGA + 1)
  m[, 1] <- N_ITER
  zeilen <- list(...)
  for (staffel in names(zeilen)) {
    m[match(staffel, STAFFELN_ERWARTET), ] <- zeilen[[staffel]]
  }
  m
}

# Fixture "Nordost 89 %": In 89 % der Iterationen faellt genau ein
# Drittligist nach Nordost, nie zwei. Erwartungswerte: Nordost 0.89,
# Nord 1.11, West 1, SuedWest 1, Bayern 0 -- Summe 4.
zaehlung_nordost89 <- function() {
  zaehlung(
    Nordost  = c(1100, 8900, 0, 0, 0),
    Nord     = c(0, 8900, 1100, 0, 0),
    West     = c(0, N_ITER, 0, 0, 0),
    SuedWest = c(0, N_ITER, 0, 0, 0)
  )
}

# Prognosezeile eines Teams, das nur die genannten Plaetze erreichen kann.
# `plaetze` sind absolute Plaetze, `p` die Wahrscheinlichkeiten dazu.
prognose_zeile <- function(teams, plaetze, p, name = "A") {
  stopifnot(abs(sum(p) - 1) < 1e-12)
  m <- matrix(0, nrow = 1, ncol = teams,
              dimnames = list(name, as.character(seq_len(teams))))
  m[1, plaetze] <- p
  m
}

# --- Loop-Attrappen ------------------------------------------------------------
# Gebraucht in test-update_all_leagues_loop-gating.R, -sicherheitsnetz.R,
# -verdrahtung.R (n_ligen, n_sims_pro_runde) und test-update_all_leagues_loop.R
# (fake_transformed) (#211, Stufe 3.6).

# Minimal stand-in for one league's raw fixture list. The loop reads
# fixture$id + fixture$status$short (beendet-set per league, pending-set
# resolution) and id/date/status/goals for the render signature.
# transform_data() is mocked in the tests, so the rest of the shape is irrelevant.
fake_fixtures <- function(statuses, ids = seq_along(statuses),
                          goals_home = rep(NA_integer_, length(statuses)),
                          goals_away = rep(NA_integer_, length(statuses))) {
  list(
    fixture = list(
      id = ids,
      date = rep("2026-08-29T15:30:00+02:00", length(statuses)),
      status = list(
        short = statuses,
        elapsed = rep(NA_integer_, length(statuses))
      )
    ),
    goals = list(home = goals_home, away = goals_away)
  )
}

# Ligazahl der Registry und Simulationen je Runde: eine je Liga, plus ein
# zweiter Lauf fuer jede Liga, aus der Zweitvertretungen nicht aufsteigen
# duerfen (3. Liga, 2. Frauen-BL). Die Loop-Tests leiten ihre Erwartungen
# daraus ab statt aus festen Zahlen.
n_ligen <- function() length(source_module("league_registry")$league_ids())

n_sims_pro_runde <- function() {
  env <- source_module("league_registry")
  ids <- env$league_ids()
  length(ids) + sum(vapply(ids, env$has_promotion_restriction, logical(1)))
}

# Minimal stand-in for transform_data()'s output: leagueSimulatorRust() is
# mocked in the tests and never inspects it, but the Liga3-second-team penalty
# loop in the production code does `for (j in 5:dim(Liga3)[2])` and reads
# `names(Liga3)[j]`, so the fake needs at least 5 columns with team-like
# names in columns 5+.
fake_transformed <- function() {
  data.frame(
    TeamHeim = "AAA", TeamGast = "BBB", ToreHeim = 1, ToreGast = 0,
    AAA = 1500, BBB = 1500
  )
}
