# Trivialfall-Probe fuer Issue #205: laeuft GEGEN DEN ECHTEN RUST-SERVER
# (kein Stub), weil ihr einziger Zweck ist zu zeigen, dass tore_slope/
# tore_intercept tatsaechlich im Poisson-Modell ankommen -- ein Stub wuerde
# genau das nicht pruefen koennen.
#
# WICHTIG, empirisch verifiziert (nicht aus dem Code geraten): match_sim.rs
# und league_details/mod.rs klemmen lambda auf `.max(0.001)`
# (tore_heim_durchschnitt / lambda_home, -away analog). Mit
# tore_slope = tore_intercept = 0 ist lambda deshalb 0.001, NICHT 0 --
# P(0:0) = exp(-0.001)^2 = 0.998001998..., nicht exakt 1. Die Assertions
# unten pruefen also "praktisch immer 0:0" mit Toleranz, nie exakte
# Gleichheit mit 1 bzw. 0.

library(testthat)

# --- Server-Helfer, dupliziert aus test-rust-required.R -----------------
#
# test_dir() laedt jede test-*.R-Datei in einer eigenen Umgebung; die dortigen
# start_rust_server()/stop_rust_server() sind hier nicht sichtbar. Die
# Duplikation ist das etablierte Muster in dieser Suite (with_repo_root()
# steht ebenso in fuenf weiteren Dateien).

rust_binary <- function() {
  kandidaten <- c(
    file.path("..", "..", "league-simulator-rust", "target", "release", "league-simulator-rust"),
    "/usr/local/bin/league-simulator-rust"
  )
  for (bin in kandidaten) {
    if (file.exists(bin)) {
      return(normalizePath(bin))
    }
  }
  skip(sprintf("Rust binary not found in any of: %s; run `cargo build --release` in league-simulator-rust/",
               paste(kandidaten, collapse = ", ")))
}

start_rust_server <- function(port = 18081L) {
  bin <- rust_binary()
  log <- tempfile(fileext = ".log")
  old_port <- Sys.getenv("PORT", unset = NA)
  Sys.setenv(PORT = as.character(port))
  pid <- sys::exec_background(bin, args = "--api", std_out = log, std_err = log)
  if (is.na(old_port)) Sys.unsetenv("PORT") else Sys.setenv(PORT = old_port)
  prior_rust_api_url <- Sys.getenv("RUST_API_URL", unset = NA)
  Sys.setenv(RUST_API_URL = sprintf("http://localhost:%d", port))
  ok <- FALSE
  for (i in 1:50) {
    Sys.sleep(0.2)
    res <- tryCatch(httr::GET(paste0(Sys.getenv("RUST_API_URL"), "/health"),
                              httr::timeout(0.5)),
                    error = function(e) NULL)
    if (!is.null(res) && httr::status_code(res) == 200) { ok <- TRUE; break }
  }
  list(pid = pid, log = log, ok = ok, port = port,
       prior_rust_api_url = prior_rust_api_url)
}

stop_rust_server <- function(handle) {
  if (!is.null(handle$pid)) {
    try(tools::pskill(handle$pid), silent = TRUE)
  }
  if (!is.null(handle$prior_rust_api_url)) {
    if (is.na(handle$prior_rust_api_url)) {
      Sys.unsetenv("RUST_API_URL")
    } else {
      Sys.setenv(RUST_API_URL = handle$prior_rust_api_url)
    }
  }
}

# --- Fixture: 4-Team-Liga, kein Spiel gespielt, verschiedene ELOs --------
#
# Verschiedene ELOs (nicht alle 1500 wie make_test_teams()), damit ein
# NICHT-NULL slope tatsaechlich etwas veraendern wuerde -- sonst waere ein
# Bug, der slope stillschweigend ignoriert, von dieser Probe gar nicht zu
# unterscheiden.
tormodell_test_season <- function() {
  data.frame(
    TeamHeim = c("A", "C", "A", "B", "A", "B"),
    TeamGast = c("B", "D", "C", "D", "D", "C"),
    ToreHeim = rep(NA_real_, 6),
    ToreGast = rep(NA_real_, 6),
    A = rep(1600, 6), B = rep(1500, 6), C = rep(1400, 6), D = rep(1300, 6)
  )
}

test_that("tore_slope = tore_intercept = 0 ergibt (fast) nur 0:0 -- ueber den echten Rust-Server (#205)", {
  skip_if_not_installed("sys")
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")

  handle <- start_rust_server()
  on.exit(stop_rust_server(handle), add = TRUE)
  if (!handle$ok) {
    skip(sprintf("Rust server failed to come up on port %d; log: %s",
                 handle$port, handle$log))
  }

  with_repo_root({
    source("RCode/rust_integration.R", local = TRUE)
    source("RCode/league_details.R", local = TRUE)

    # (a) match_preview_rust (derselbe Endpunkt, den /league-details fuer
    # Score-Matrix und 1/X/2 einer Paarung nutzt): P(0:0) und 1/X/2 fuer
    # mehrere Paarungen mit UNTERSCHIEDLICHER ELO-Differenz. Waere der
    # Trivialfall wirklich lambda = 0 statt des geklemmten 0.001, stuende
    # hier exakt 1/0/1/0 -- das Server-Minimum verhindert das exakt, daher
    # Toleranz statt expect_equal(..., 1).
    paarungen <- list(
      c(1600, 1300), # groesste ELO-Differenz der Fixture
      c(1500, 1400),
      c(1400, 1400) # gleiche ELO
    )
    for (p in paarungen) {
      mp <- match_preview_rust(p[[1]], p[[2]], tore_slope = 0, tore_intercept = 0,
                               max_goals = 4)
      # lambda selbst: der dokumentierte Rust-Boden 0.001 (match_sim.rs /
      # league_details/mod.rs, `.max(0.001)`), NICHT 0.
      expect_equal(mp$lambda_home, 0.001, tolerance = 1e-9)
      expect_equal(mp$lambda_away, 0.001, tolerance = 1e-9)
      # P(0:0) = exp(-0.001)^2 = 0.998001998... -- "praktisch immer", nicht
      # exakt 1. Toleranz 1e-4 statt 1e-8: Der Server rundet seine JSON-
      # Antwort (p_draw, p_home_win, p_away_win) sichtbar staerker als die
      # volle double-Praezision, die R fuer ausgehende Payloads erzwingt
      # (digits = NA in rust_integration.R) -- score_matrix traf die volle
      # Praezision, p_draw/p_home_win/p_away_win rundeten auf 3 Nachkomma-
      # stellen (empirisch beobachtet: 0.998 statt 0.9980019987).
      expect_equal(mp$score_matrix[1, 1], exp(-0.001)^2, tolerance = 1e-4)
      expect_equal(mp$p_draw, exp(-0.001)^2, tolerance = 1e-4)
      # 1/X/2: beide Seiten je (1 - exp(-lambda))*exp(-lambda) statt exakt 0.
      erwartet_sieg <- (1 - exp(-0.001)) * exp(-0.001)
      expect_equal(mp$p_home_win, erwartet_sieg, tolerance = 1e-4)
      expect_equal(mp$p_away_win, erwartet_sieg, tolerance = 1e-4)
      # Trotzdem: der Sieg-Anteil ist verschwindend klein gegen den
      # Remis-Anteil -- das ist die eigentliche Aussage des Tests.
      expect_lt(mp$p_home_win, 0.005)
      expect_lt(mp$p_away_win, 0.005)
      expect_gt(mp$p_draw, 0.99)
    }

    # (b) leagueSimulatorRust ueber die ganze Liga: bei (fast) nur 0:0-Spielen
    # enden alle vier Teams mit identischen Punkten (0) und identischer
    # Tordifferenz (0). calculate_table() (season.rs) sortiert bei
    # vollstaendigem Gleichstand ueber Rusts stabilen `sort_by` -- ohne
    # Zufalls-Tiebreak bleibt die urspruengliche Team-Reihenfolge (Team-Index)
    # erhalten. monte_carlo/mod.rs sortiert die Ausgabematrix zusaetzlich
    # nach Durchschnittsplatz (`partial_cmp`, ebenfalls stabil) -- bei
    # (fast) identischen Durchschnittsplaetzen bleibt daher dieselbe
    # Reihenfolge A/B/C/D -> Platz 1/2/3/4 stehen.
    #
    # Empirisch verifiziert (n = 200, Fixture oben): die Matrix ist NICHT
    # gleichverteilt (0.25 je Zelle) -- die 0,2 % Nicht-0:0-Spiele je
    # Paarung sind zu selten, um die durch den Team-Index vorgegebene
    # Reihenfolge im Mittel zu kippen. Die Matrix ist naeherungsweise die
    # Einheitsmatrix (Diagonale >> Nebendiagonalen), aber wegen der
    # verbleibenden ~0,2 %-Wahrscheinlichkeit pro Spiel nicht exakt 1/0 --
    # daher eine Diagonal-Dominanz-Assertion statt expect_equal() mit der
    # Einheitsmatrix.
    # set.seed() hier wäre wirkungslos: Rust erzeugt seine eigenen Seeds
    # (monte_carlo/mod.rs, rand::rng()) unabhängig vom R-Prozess. Die
    # Toleranz unten (> 0.9 Diagonale gegen empirisch beobachtete ~0.995)
    # ist deshalb bewusst grosszuegig statt auf einen Lauf gepinnt.
    ergebnis0 <- leagueSimulatorRust(tormodell_test_season(), n = 500,
                                     toreSlope = 0, toreIntercept = 0)
    diagonale <- diag(ergebnis0)
    expect_true(all(diagonale > 0.9),
                info = paste("Diagonale:", paste(round(diagonale, 3), collapse = ", ")))
    expect_true(all(rowSums(ergebnis0) - diagonale < 0.1))

    # (c) Gegenprobe in DERSELBEN laufenden Server-Instanz: die Herren-
    # Defaults (Parameter weggelassen) ergeben fuer dieselbe Liga ein
    # deutlich kleineres P(0:0) -- der Unterschied zu (a)/(b) beweist, dass
    # tore_slope/tore_intercept tatsaechlich im Rust-Server ankommen und
    # nicht nur lokal in R verpuffen.
    mp_default <- match_preview_rust(1600, 1300, max_goals = 4)
    expect_lt(mp_default$p_draw, 1)
    expect_lt(mp_default$score_matrix[1, 1], 0.9)
    expect_gt(mp_default$lambda_home, 0.5) # weit ueber dem 0.001-Boden

    ergebnis_default <- leagueSimulatorRust(tormodell_test_season(), n = 500)
    # Mit unterschiedlichen ELOs und den Herren-Konstanten ist die Liga NICHT
    # naeherungsweise die Einheitsmatrix -- Team A (hoechste ELO) liegt im
    # Schnitt vorn, die Diagonale ist deutlich flacher als im Trivialfall.
    expect_true(any(diag(ergebnis_default) < 0.9))
  })
})

# --- aus test-home-advantage-single-source.R ---
# Der Heimvorteil ist eine Modellkonstante und lebt ausschliesslich im
# Rust-Server (ADR 0002). Dieser Test haelt fest, dass die R-Seite ihn im
# Simulationspfad nicht mitsendet; das Gegenstueck fuer /league-details steht
# in test-league-details-client.R.
#
# Warum beides abgedeckt sein muss: Die Prognose-Heatmap entsteht ueber
# POST /simulate, Ligatabelle/Rueckblick/Ausblick ueber POST /league-details.
# Sendet nur einer der beiden Pfade einen abweichenden Wert, widersprechen sich
# Heatmap und 1/X/2-Werte derselben Seite - ohne dass etwas fehlschlaegt.

library(mockery)

test_that("simulate_league_rust sendet home_advantage nicht mit", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "rust_integration.R"), local = env)

  captured <- NULL
  stub(env$simulate_league_rust, "POST", function(url, body, ...) {
    captured <<- jsonlite::fromJSON(body)
    stop("abbruch nach payload-erfassung")
  })

  try(env$simulate_league_rust(
    schedule = matrix(c(1, 2, NA, NA), nrow = 1),
    elo_values = c(1500, 1500),
    team_names = c("AAA", "BBB")
  ), silent = TRUE)

  expect_false(is.null(captured))
  expect_false("home_advantage" %in% names(captured))
  expect_equal(captured$mod_factor, 20)
})

test_that("ein explizit uebergebener home_advantage landet im Payload", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "rust_integration.R"), local = env)

  captured <- NULL
  stub(env$simulate_league_rust, "POST", function(url, body, ...) {
    captured <<- jsonlite::fromJSON(body)
    stop("abbruch nach payload-erfassung")
  })

  try(env$simulate_league_rust(
    schedule = matrix(c(1, 2, NA, NA), nrow = 1),
    elo_values = c(1500, 1500),
    team_names = c("AAA", "BBB"),
    home_advantage = 40
  ), silent = TRUE)

  expect_equal(captured$home_advantage, 40)
})

# --- aus test-league-registry.R ---
# --- Tormodell: die Frauen-Werte erreichen beide Endpunkte ------------------

test_that("simulate_league_rust sendet das Tormodell nur, wenn es abweicht", {
  # ADR 0002: Modellkonstanten leben in Rust. Fuer die Herren-Ligen darf R
  # nichts senden -- sonst gibt es zwei Quellen. Fuer die Frauen-Ligen MUSS
  # R senden, weil Rust die Herren-Werte als Default haelt.
  env <- new.env()
  source(test_path("..", "..", "RCode", "rust_integration.R"), local = env)

  fang <- function(...) {
    captured <- NULL
    mockery::stub(env$simulate_league_rust, "POST", function(url, body, ...) {
      captured <<- jsonlite::fromJSON(body)
      stop("abbruch nach payload-erfassung")
    })
    try(env$simulate_league_rust(
      schedule = matrix(c(1, 2, NA, NA), nrow = 1),
      elo_values = c(1500, 1500), team_names = c("AAA", "BBB"), ...
    ), silent = TRUE)
    captured
  }

  ohne <- fang()
  expect_false("tore_slope" %in% names(ohne))
  expect_false("tore_intercept" %in% names(ohne))

  mit <- fang(tore_slope = 0.0024058833, tore_intercept = 1.6527603153)
  expect_equal(mit$tore_slope, 0.0024058833)
  expect_equal(mit$tore_intercept, 1.6527603153)
})
