# Update Scheduler with Rust Engine Integration
# Uses high-performance Rust simulation engine for 50-100x speedup

# Warnungen sofort ausgeben, statt sie zu sammeln (Issue #208, Punkt 2):
# Rscripts Default (warn = 0) sammelt Warnungen bis zur Rueckkehr aus
# main() und verwirft sie beim regulaeren quit() der Produktions-Schleife --
# ein Statuscode oder eine Degradation aus einem warning() waere damit erst
# nach zwoelf Stunden sichtbar, und dann nur noch als Sammelliste ohne
# Zeitbezug. warn = 1 schreibt jede Warnung sofort ins Docker-Log, an der
# Stelle, an der sie entsteht.
options(warn = 1)

# Das taegliche Zeitfenster, in dem der Scheduler laeuft (Minuten seit
# Mitternacht, Berliner Zeit).
#
# Der Start liegt am fruehesten Anstoss: Die 2. Frauen-Bundesliga spielt zu
# 37 % vormittags, ab 11 Uhr -- an den Spielplaenen 2023-2025 gemessen. Das
# vorherige, deutlich spaetere Fenster haette diese Spiele erst nach Abpfiff
# erfasst.
#
# Als Konstanten, nicht als Literale: Vorher standen die Uhrzeiten an neun
# Stellen -- als Zahl, in Kommentaren und in Meldungstexten. Eine Verschiebung
# musste alle treffen, eine vergessene Stelle waere nicht aufgefallen.
SCHEDULE_START_MINUTES <- 11 * 60
SCHEDULE_END_MINUTES <- 23 * 60

# "11:00" / "23:00" fuer Meldungstexte, aus den Konstanten abgeleitet.
.format_schedule_time <- function(minutes) {
  sprintf("%02d:%02d", minutes %/% 60, minutes %% 60)
}

# Load configuration from environment

RAPIDAPI_KEY <- Sys.getenv("RAPIDAPI_KEY")
# Obergrenze der Laufzeit je Scheduler-Lauf. Der Default ist die volle
# Fensterlaenge -- eine feste Zahl waere eine zweite Quelle, die beim
# Verschieben des Fensters stillschweigend zur Bremse wird: Stuende hier
# weiterhin 480, hoerte der Scheduler um 19:00 auf und verpasste die
# Abendspiele.
# Eine gesetzte, aber LEERE Variable liefert "" statt des Defaults -- genau
# so uebergibt docker-compose sie, wenn der Operator nichts angibt.
SCHEDULE_WINDOW_MINUTES <- SCHEDULE_END_MINUTES - SCHEDULE_START_MINUTES
DURATION <- local({
  gesetzt <- Sys.getenv("DURATION")
  if (nzchar(gesetzt)) as.numeric(gesetzt) else SCHEDULE_WINDOW_MINUTES
})
SEASON <- Sys.getenv("SEASON", format(Sys.Date(), "%Y"))
RUST_API_URL <- Sys.getenv("RUST_API_URL", "http://localhost:8080")

# Validate environment
if (RAPIDAPI_KEY == "") {
  stop("ERROR: RAPIDAPI_KEY environment variable not set")
}

# Auto-detect season if not set
if (SEASON == "") {
  current_month <- as.numeric(format(Sys.Date(), "%m"))
  current_year <- as.numeric(format(Sys.Date(), "%Y"))

  if (current_month >= 7) {
    SEASON <- as.character(current_year)
  } else {
    SEASON <- as.character(current_year - 1)
  }

  message(sprintf("Auto-detected season: %s", SEASON))
}

# Set up team list file
team_list_file <- sprintf("RCode/TeamList_%s.csv", SEASON)
if (!file.exists(team_list_file)) {
  # Try next year's file
  team_list_file_next <- sprintf("RCode/TeamList_%d.csv", as.numeric(SEASON) + 1)
  if (file.exists(team_list_file_next)) {
    team_list_file <- team_list_file_next
    message(sprintf("Using team list file: %s", team_list_file))
  } else {
    stop(sprintf("ERROR: Team list file not found: %s or %s", team_list_file, team_list_file_next))
  }
}

# Source required functions
source("RCode/update_all_leagues_loop.R")
source("RCode/checkAPILimits.R")

# Der Tagesplan als reine Rechnung (Stufe 4.2, #212): Zeitpunkt rein, Plan raus,
# kein Schlafen, keine Meldung, kein API-Aufruf. Rechnet in Europe/Berlin,
# unabhaengig von der Prozess-Zeitzone -- TZ setzt heute nur docker-compose,
# nicht das Dockerfile.
plane_fenster <- function(jetzt,
                          start = SCHEDULE_START_MINUTES,
                          ende = SCHEDULE_END_MINUTES,
                          dauer_max = DURATION,
                          tz = "Europe/Berlin") {
  lokal <- as.POSIXlt(jetzt, tz = tz)
  minuten <- lokal$hour * 60 + lokal$min
  deckeln <- function(m) if (dauer_max > 0 && m > dauer_max) dauer_max else m
  if (minuten < start) {
    verfuegbar <- deckeln(ende - start)
    list(zweig = "vor", wartezeit_s = (start - minuten) * 60,
         verfuegbar = verfuegbar, ideal_loops = floor(verfuegbar / 2) + 1)
  } else if (minuten > ende) {
    verfuegbar <- deckeln(ende - start)
    list(zweig = "nach", wartezeit_s = ((24 * 60 - minuten) + start) * 60,
         verfuegbar = verfuegbar, ideal_loops = floor(verfuegbar / 2) + 1)
  } else {
    verfuegbar <- deckeln(ende - minuten)
    list(zweig = "im", wartezeit_s = 0,
         verfuegbar = verfuegbar, ideal_loops = floor(verfuegbar / 2) + 1)
  }
}

# Huelle um plane_fenster: schlafen, melden, Kontingent fragen. `jetzt`/
# `schlafen` sind nur fuer Tests injizierbar, main() ruft ohne Argumente.
calculate_loops <- function(jetzt = Sys.time(), schlafen = Sys.sleep) {
  plan <- plane_fenster(jetzt)

  if (plan$wartezeit_s > 0) {
    if (plan$zweig == "vor") {
      message(sprintf("Before %s - waiting %.1f hours for scheduled run time",
                      .format_schedule_time(SCHEDULE_START_MINUTES), plan$wartezeit_s / 3600))
    } else {
      message(sprintf("After %s - waiting %.1f hours until tomorrow's scheduled run",
                      .format_schedule_time(SCHEDULE_END_MINUTES), plan$wartezeit_s / 3600))
    }
    schlafen(plan$wartezeit_s)
  }

  loops <- checkAPILimits(plan$ideal_loops)
  message(sprintf("Planning to run %d loops (ideal: %d)", loops, plan$ideal_loops))
  if (plan$zweig == "im") {
    message(sprintf("Time remaining: %.1f minutes", plan$verfuegbar))
  } else {
    message(sprintf("Time available: %.1f minutes", plan$verfuegbar))
  }

  list(loops = loops, initial_wait = 0, duration = plan$verfuegbar,
       plan_reduziert = api_limits_plan_reduziert())
}

# Main execution
main <- function() {
  message("===========================================")
  message("League Simulator Scheduler with Rust Engine")
  message("===========================================")
  message(sprintf("Season: %s", SEASON))
  message(sprintf("Team list: %s", team_list_file))
  message(sprintf("Rust API: %s", RUST_API_URL))
  message("")

  # Assert Rust availability at scheduler startup. Issue #77 Phase 1: there is
  # no in-process fallback to C++. A missing Rust server fails the scheduler
  # here so the operator sees the real cause; the loop's own assertion is the
  # second-tier guard against the server dying mid-run.
  source("RCode/rust_integration.R")
  if (!connect_rust_simulator()) {
    stop(sprintf(
      "Rust simulator not available at %s. Start the Rust server before invoking this scheduler.",
      RUST_API_URL
    ))
  }

  # Calculate optimal number of loops
  loop_config <- calculate_loops()

  # Run the update loop. Rust availability has already been asserted above.
  update_all_leagues_loop(
    duration = loop_config$duration, # Use actual time remaining, not DURATION
    loops = loop_config$loops,
    initial_wait = loop_config$initial_wait,
    n = 10000,
    saison = SEASON,
    TeamList_file = team_list_file,
    # Kam die Rundenzahl aus einem Fallback (fehlender Header, Probe im
    # Timeout), darf der Loop auf Normaltakt zurueckschalten, sobald die
    # Header doch noch eintreffen -- und dann begrenzt die Uhr den Tag,
    # nicht die Rundenzahl. Ohne dieses Signal ist eine kleine Rundenzahl
    # eine Ansage und bleibt (Issue #224).
    plan_reduziert = isTRUE(loop_config$plan_reduziert)
    # static_site_dir defaults to STATIC_SITE_DIR (see update_all_leagues_loop.R)
  )

  message("Scheduler completed successfully")
}

# Run with error handling
tryCatch(
  {
    main()
  },
  error = function(e) {
    message(sprintf("ERROR in scheduler: %s", e$message))
    quit(status = 1)
  }
)
