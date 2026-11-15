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

# Der Frueh-Lauf: EIN Komplettzyklus (alle Ligen abrufen, simulieren, Seite
# rendern) um 00:30 Berliner Zeit, vor dem regulaeren Fenster. Grund ist der
# Ausblick (Hingucker der Woche): Er rechnet auf die naechsten sieben Tage
# ab `now` und waere sonst bis 11:00 auf dem Stand des Vorabends -- das Spiel
# von heute stuende noch als "morgen" da. Kein Dauerbetrieb: eine Runde, dann
# Schlaf bis 11:00.
SCHEDULE_EARLY_MINUTES <- 30

# Budget: Der Frueh-Lauf liegt ausserhalb des Fensters, das der Regler
# (rate_limit_takt.R, "die Nacht kann keine Runden aufnehmen", #224) plant --
# er kostet ~11 Requests (1 Probe + 1 Vollabruf je Liga), die
# nicht im Tagesbudget stehen. Das Kontingent ist ein ROLLIERENDES Fenster
# (rate_limit_takt.R: gemessen, nicht Mitternacht), der Reset-Zeitpunkt also
# nicht bekannt. Deshalb prueft der Lauf vorher das Kontingent
# (checkAPILimits) und faellt bei erschoepftem Kontingent aus; 12 von 7.500
# Requests sind gegenueber dem Tagesbudget vernachlaessigbar.

# Marker des letzten Frueh-Laufs (Epochensekunden), im persistenten
# Site-Volume. Er verhindert Wiederholungen bei Neustarts (Deploy, Absturz,
# OOM-Kill): Geschrieben wird VOR dem Lauf, ein Absturz mitten im Zyklus fuehrt
# also nicht zur Schleife.
FRUEHLAUF_MARKER <- file.path(Sys.getenv("STATIC_SITE_DIR", "ShinyApp/public"),
                              ".fruehlauf")

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

# Der Takt des Normalbetriebs in Minuten: eine Runde je zwei Minuten.
SCHEDULE_TAKT_MINUTES <- 2

# Der Tagesplan als reine Rechnung (Stufe 4.2, #212): Zeitpunkt rein, Plan raus,
# kein Schlafen, keine Meldung, kein API-Aufruf. Rechnet in Europe/Berlin,
# unabhaengig von der Prozess-Zeitzone -- TZ setzt heute nur docker-compose,
# nicht das Dockerfile.
#
# Das Fensterende (#287): Der Zweig "nach" beginnt nicht erst NACH 23:00,
# sondern sobald hoechstens noch ein Takt (zwei Minuten) bleibt, also ab
# 22:58. Grund ist der Prozess-Lebenslauf: Der Scheduler ist je Prozess ein
# Tageslauf. Der regulaere Lauf endet, sobald die naechste Runde nicht mehr
# vor dem Fensterende passt -- weniger als ein Takt davor --, Docker startet
# den Container rund 19 s spaeter neu (`unless-stopped`), und erst der neue
# Prozess schlaeft bis 11:00. Plante er stattdessen noch eine Runde (vorher
# bei 22:58, 22:59 und 23:00 je eine), endete er nach ihr und startete
# erneut -- am 05.10. sieben Neustarts zwischen 22:59 und 23:01, jeder mit
# einem Komplettzyklus, der den eben beendeten nur wiederholte. Ab zwei
# Minuten Restzeit passt keine zweite Runde mehr (die Runde selbst dauert
# ~18 s); ein solcher Lauf ist immer genau dieser Kurzlauf. So bleibt pro
# Abend der eine gewollte Neustart.
#
# Warum 22:58 und nicht erst 22:59: Das Fensterende des regulaeren Laufs
# liegt bei 23:00:ss (Start 11:00:ss plus 720 Minuten), seine letzte Runde
# endet also irgendwo zwischen 22:58:ss und 23:01 -- der Neustart kann
# damit schon in 22:58 fallen. Vor 22:58 liegt er bei normalem Takt nie;
# nur ein vom Regler gestreckter Takt kann den Tageslauf frueher beenden.
#
# Die Wartezeit (Zweige "vor" und "nach") ist die echte Spanne von `jetzt`
# bis zum naechsten Fensterstart in Berliner Zeit -- heute, wenn `jetzt` davor
# liegt, sonst morgen. Frueher rechnete sie in Uhrzeit-Minuten und unterstellte
# damit, dass jede Nacht 24 Stunden hat. In der Nacht der Umstellung auf
# Sommerzeit (23 Stunden) wachte der Scheduler deshalb erst um 12:00 auf und
# verpasste die erste Stunde; in der Herbstnacht (25 Stunden) schon um 10:00
# und lief dann mit dem vollen 720-Minuten-Fenster bis 22:00, gefolgt von
# einem zusaetzlichen Neustart fuer die letzte Stunde. Die Sekunden von
# `jetzt` gehen mit ein: Das Ziel ist 11:00:00, nicht die volle Minute.
naechster_fensterstart <- function(jetzt, start = SCHEDULE_START_MINUTES,
                                   tz = "Europe/Berlin") {
  uhrzeit <- sprintf("%02d:%02d:00", start %/% 60, start %% 60)
  tag <- as.Date(format(jetzt, tz = tz, "%Y-%m-%d"))
  ziel <- as.POSIXct(paste(tag, uhrzeit), tz = tz)
  if (ziel <= jetzt) ziel <- as.POSIXct(paste(tag + 1, uhrzeit), tz = tz)
  ziel
}

plane_fenster <- function(jetzt,
                          start = SCHEDULE_START_MINUTES,
                          ende = SCHEDULE_END_MINUTES,
                          dauer_max = DURATION,
                          tz = "Europe/Berlin",
                          takt = SCHEDULE_TAKT_MINUTES) {
  lokal <- as.POSIXlt(jetzt, tz = tz)
  minuten <- lokal$hour * 60 + lokal$min
  deckeln <- function(m) if (dauer_max > 0 && m > dauer_max) dauer_max else m
  wartezeit <- function() {
    ziel <- naechster_fensterstart(jetzt, start = start, tz = tz)
    as.numeric(difftime(ziel, jetzt, units = "secs"))
  }
  if (minuten < start) {
    verfuegbar <- deckeln(ende - start)
    list(zweig = "vor", wartezeit_s = wartezeit(),
         verfuegbar = verfuegbar, ideal_loops = floor(verfuegbar / 2) + 1)
  } else if (ende - minuten <= takt) {
    verfuegbar <- deckeln(ende - start)
    list(zweig = "nach", wartezeit_s = wartezeit(),
         verfuegbar = verfuegbar, ideal_loops = floor(verfuegbar / 2) + 1)
  } else {
    verfuegbar <- deckeln(ende - minuten)
    list(zweig = "im", wartezeit_s = 0,
         verfuegbar = verfuegbar, ideal_loops = floor(verfuegbar / 2) + 1)
  }
}

# Der letzte Frueh-Termin (00:30) an oder vor `jetzt`, in Berliner Zeit.
letzter_fruehtermin <- function(jetzt, frueh = SCHEDULE_EARLY_MINUTES,
                                tz = "Europe/Berlin") {
  uhrzeit <- sprintf("%02d:%02d:00", frueh %/% 60, frueh %% 60)
  tag <- as.Date(format(jetzt, tz = tz, "%Y-%m-%d"))
  ziel <- as.POSIXct(paste(tag, uhrzeit), tz = tz)
  if (ziel > jetzt) ziel <- as.POSIXct(paste(tag - 1, uhrzeit), tz = tz)
  ziel
}

# Ob dieser Prozess vor dem regulaeren Fensterstart einen Frueh-Lauf einlegt
# -- reine Rechnung wie plane_fenster().
#
# Ja, ausser im Fenster (11:00-23:00): Vor 00:30 wartet er bis 00:30, ab 00:30
# bis 11:00 (Neustart nach Absturz oder Deploy) laeuft der Frueh-Lauf sofort,
# nach dem Fensterende (Abendneustart) am naechsten 00:30 -- es sei denn,
# `letzter_lauf` (Zeitpunkt des Markers) liegt schon an oder nach dem heutigen
# Termin: dann ist er gelaufen, und ein Neustart wiederholt ihn nicht.
plane_frueh_lauf <- function(jetzt,
                             frueh = SCHEDULE_EARLY_MINUTES,
                             start = SCHEDULE_START_MINUTES,
                             tz = "Europe/Berlin",
                             letzter_lauf = NULL) {
  nein <- list(aktiv = FALSE, wartezeit_s = 0)
  if (length(frueh) != 1L || is.na(frueh) || frueh >= start) return(nein)
  zweig <- plane_fenster(jetzt, start = start, tz = tz)$zweig
  if (zweig == "im") return(nein)
  lokal <- as.POSIXlt(jetzt, tz = tz)
  if (zweig == "vor" && lokal$hour * 60 + lokal$min >= frueh) {
    if (length(letzter_lauf) == 1L && !is.na(letzter_lauf) &&
          letzter_lauf >= letzter_fruehtermin(jetzt, frueh, tz)) {
      return(nein)
    }
    return(list(aktiv = TRUE, wartezeit_s = 0))
  }
  ziel <- naechster_fensterstart(jetzt, start = frueh, tz = tz)
  list(aktiv = TRUE, wartezeit_s = as.numeric(difftime(ziel, jetzt, units = "secs")))
}

# Marker lesen/schreiben (Epochensekunden). Fehlt oder zerfaellt die Datei,
# gilt der Frueh-Lauf als nicht gelaufen.
fruehlauf_marker_lesen <- function(pfad = FRUEHLAUF_MARKER) {
  wert <- tryCatch(suppressWarnings(as.numeric(readLines(pfad, n = 1L, warn = FALSE))),
                   error = function(e) NA_real_)
  if (length(wert) != 1L || is.na(wert)) return(NULL)
  as.POSIXct(wert, origin = "1970-01-01", tz = "UTC")
}
fruehlauf_marker_schreiben <- function(zeit, pfad = FRUEHLAUF_MARKER) {
  tryCatch(writeLines(format(as.numeric(zeit), scientific = FALSE), pfad),
           error = function(e) message(sprintf(
             "WARNUNG: Frueh-Lauf-Marker nicht schreibbar (%s)", conditionMessage(e))))
}

# Der eine Aufruf des Loops, geteilt von Frueh-Lauf und Tageslauf: Aendert
# sich ein gemeinsames Argument (n, Saison, Teamliste), aendert es sich
# an einer Stelle.
starte_loop <- function(...) {
  update_all_leagues_loop(n = 10000, saison = SEASON,
                          TeamList_file = team_list_file, ...)
}

# Der Frueh-Lauf als Ganzes: planen, warten, Marker setzen, Kontingent
# pruefen, EINEN Zyklus fahren. Fehler (R-Fehler) kosten den Tag nicht.
# Alles Aeussere injizierbar, damit die Abfolge testbar ist.
fuehre_fruehlauf_aus <- function(jetzt = Sys.time(), schlafen = Sys.sleep,
                                 lauf = starte_loop, kontingent = checkAPILimits,
                                 marker = FRUEHLAUF_MARKER) {
  plan <- plane_frueh_lauf(jetzt, letzter_lauf = fruehlauf_marker_lesen(marker))
  if (!plan$aktiv) return(invisible("uebersprungen"))

  message(sprintf("Frueh-Lauf (ab %s) - waiting %.1f hours",
                  .format_schedule_time(SCHEDULE_EARLY_MINUTES),
                  plan$wartezeit_s / 3600))
  if (plan$wartezeit_s > 0) schlafen(plan$wartezeit_s)

  # VOR dem Lauf: Ein Absturz mitten im Zyklus (OOM, Segfault) soll nicht in
  # eine Neustart-Schleife fuehren.
  fruehlauf_marker_schreiben(jetzt + plan$wartezeit_s, marker)

  # Mit den Kosten eines Vollzyklus (Probe + ein Abruf je Liga) rechnen,
  # nicht mit dem Halbwert der Tagesplanung -- sonst gaelte die Pruefung
  # schon ab 7 verbleibenden Requests.
  kosten <- 1 + length(league_ids())
  sicher <- tryCatch(kontingent(1, avg_calls_per_loop = kosten) >= 1,
                     error = function(e) TRUE)
  if (!isTRUE(sicher)) {
    message("Frueh-Lauf uebersprungen: Kontingent erschoepft.")
    return(invisible("kontingent"))
  }

  tryCatch(
    lauf(duration = 0, loops = 1, initial_wait = 0),
    error = function(e) {
      message(sprintf("ERROR im Frueh-Lauf (weiter mit dem regulaeren Tag): %s",
                      conditionMessage(e)))
    }
  )
  invisible("gelaufen")
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
      # Ab zwei Minuten vor dem Fensterende schon "nach" (#287) -- die
      # Meldung sagt dann nicht "After 23:00", obwohl es noch 22:59 ist.
      ende_text <- .format_schedule_time(SCHEDULE_END_MINUTES)
      lokal <- as.POSIXlt(jetzt, tz = "Europe/Berlin")
      if (lokal$hour * 60 + lokal$min < SCHEDULE_END_MINUTES) {
        lage <- sprintf("No loop fits before %s", ende_text)
      } else {
        lage <- sprintf("After %s", ende_text)
      }
      message(sprintf("%s - waiting %.1f hours until tomorrow's scheduled run",
                      lage, plan$wartezeit_s / 3600))
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

  # Frueh-Lauf (00:30): ein Komplettzyklus, damit der Ausblick frueh am Tag
  # aktuell ist (Details und Absicherung: fuehre_fruehlauf_aus).
  fuehre_fruehlauf_aus()

  # Calculate optimal number of loops
  loop_config <- calculate_loops()

  # Run the update loop. Rust availability has already been asserted above.
  starte_loop(
    duration = loop_config$duration, # Use actual time remaining, not DURATION
    loops = loop_config$loops,
    initial_wait = loop_config$initial_wait,
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
