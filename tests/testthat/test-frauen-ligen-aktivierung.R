library(testthat)

# Livegang der beiden Frauen-Bundesligen: Der Scheduler ruft sie ab, und das
# Zeitfenster wird auf ihre Anstosszeiten angepasst.
#
# Phase 5a hat den Renderer vorbereitet; hier wird scharfgeschaltet. Der
# Schritt ist bewusst getrennt, weil er das Betriebsverhalten aendert: mehr
# API-Requests, mehr Simulationen, ein laengerer Tag.

# --- Registry: fuenf aktive Ligen -------------------------------------------

test_that("die Frauen-Ligen sind aktiv", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  expect_equal(env$league_ids(), c("78", "79", "80", "82", "1034"))
  expect_equal(env$active_league_keys(),
               c("bundesliga", "zweite_bundesliga", "dritte_liga",
                 "frauen_bundesliga", "zweite_frauen_bundesliga"))
})

test_that("die Regionalligen bleiben inaktiv", {
  # Sie folgen erst nach Phase 6: Ihre Absteigerzahl haengt an der
  # Drittliga-Kopplung, ein festes Abstiegs-Panel waere sichtbar falsch.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  for (id in c("83", "84", "85", "86", "87")) {
    expect_false(id %in% env$league_ids(), info = id)
    expect_true(id %in% env$league_ids(active_only = FALSE), info = id)
  }
})

test_that("beide Frauen-Ligen tragen das Frauen-Tormodell", {
  # Ab jetzt wirksam: Der Loop sendet die Parameter an die Engine.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  for (id in c("82", "1034")) {
    gm <- env$goal_model(id)
    expect_equal(gm$tore_slope, 0.0024058833, info = id)
    expect_equal(gm$tore_intercept, 1.6527603153, info = id)
  }
  # Die Herren-Ligen senden weiterhin nichts -- Rust haelt die Defaults.
  for (id in c("78", "79", "80")) {
    expect_null(env$goal_model(id), info = id)
  }
})

# --- Zeitfenster ------------------------------------------------------------

source_scheduler <- function() {
  env <- new.env()
  # updateScheduler.R fuehrt beim Sourcen main() aus; nur die Konstanten und
  # calculate_loops() werden gebraucht.
  code <- readLines(test_path("..", "..", "RCode", "updateScheduler.R"))
  ende <- grep("^main <- function", code)[1] - 1
  eval(parse(text = paste(code[seq_len(ende)], collapse = "\n")), envir = env)
  env
}

test_that("das Fenster beginnt um 11:00 und endet um 23:00", {
  # Die 2. Frauen-Bundesliga spielt zu 37 % vormittags, fruehester Anstoss
  # 11:00 (an den Spielplaenen 2023-2025 gemessen). Mit dem alten Fenster ab
  # 14:45 waeren diese Spiele erst nach Abpfiff erfasst worden.
  env <- source_scheduler()

  expect_equal(env$SCHEDULE_START_MINUTES, 11 * 60)
  expect_equal(env$SCHEDULE_END_MINUTES, 23 * 60)
})

test_that("die Fenstergrenzen stehen nur in den Konstanten", {
  # Vorher standen 14:45 und 22:45 an neun Stellen in updateScheduler.R --
  # als Zahl, in Kommentaren und in Meldungstexten. Eine Verschiebung musste
  # alle treffen; eine vergessene Stelle waere nicht aufgefallen.
  #
  # Geprueft wird die AUSSAGE, nicht eine Anzahl: Die alten Uhrzeiten kommen
  # nirgends mehr vor, und die neuen Grenzen stehen als benannte Konstanten.
  code <- readLines(test_path("..", "..", "RCode", "updateScheduler.R"))

  expect_false(any(grepl("14:45|22:45", code)))
  expect_false(any(grepl("14 \\* 60|22 \\* 60", code)))

  # Die Meldungstexte bauen die Uhrzeit aus den Konstanten, statt sie zu
  # wiederholen.
  konstanten <- grep("SCHEDULE_(START|END)_MINUTES *<-", code, value = TRUE)
  expect_length(konstanten, 2)
})

test_that("calculate_loops rechnet mit dem neuen Fenster", {
  env <- source_scheduler()

  # Volles Fenster: 720 Minuten, alle zwei Minuten ein Loop.
  expect_equal(env$SCHEDULE_END_MINUTES - env$SCHEDULE_START_MINUTES, 720)
})

# --- Saisonwechsel bleibt vorerst bei den Altligen --------------------------

test_that("die Saisonvalidierung prueft nur die Altligen", {
  # Der Saisonwechsel laeuft einmal jaehrlich im Juli und stuetzt sich auf
  # aufgezeichnete API-Antworten ("Kassetten"), die es nur fuer 78/79/80
  # gibt. Die Ausweitung auf zehn Ligen ist ein eigener Vorgang -- bis dahin
  # bleibt die Validierung bewusst bei den drei Ligen, statt an fehlenden
  # Kassetten zu scheitern.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "season_validation.R"), local = env)

  expect_equal(env$SEASON_TRANSITION_LEAGUES, c("78", "79", "80"))
})

# --- Der Loop ruft die neuen Ligen ab ---------------------------------------

test_that("checkAPILimits skaliert mit fuenf Ligen", {
  # Ein Live-Poll deckt alle Ligen mit einem Request ab, dazu kommen die
  # Vollabrufe. Der Default folgt der Ligazahl.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "checkAPILimits.R"), local = env)

  expect_equal(eval(formals(env$checkAPILimits)$avg_calls_per_loop, envir = env),
               1 + 5 / 2)
})
