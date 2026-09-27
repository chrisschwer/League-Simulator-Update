library(testthat)

# --- Zeitfenster ------------------------------------------------------------

source_scheduler <- function() {
  # updateScheduler.R fuehrt beim Sourcen main() aus; nur die Konstanten,
  # plane_fenster() und calculate_loops() werden gebraucht -- deshalb alles
  # bis main() auswerten.
  #
  # Unter dem Repo-Root, weil der Dateikopf die TeamList mit relativem Pfad
  # sucht. Dasselbe Muster wie in test-update_all_leagues_loop-gating.R.
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(old, "..", ".."))

  env <- new.env()
  code <- readLines(file.path("RCode", "updateScheduler.R"))
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

test_that("DURATION deckelt das Fenster nicht", {
  # Die eigentliche Falle: Fenster und DURATION sind zwei Groessen, und die
  # kleinere gewinnt. Stuende DURATION weiterhin auf den alten 480 Minuten,
  # hoerte der Scheduler um 19:00 auf -- das Fenster waere nicht verlaengert,
  # sondern VERSCHOBEN, und die Abendspiele der Altligen fielen aus.
  #
  # Der Default folgt deshalb der Fensterlaenge, statt eine eigene Zahl zu
  # sein. Geprueft wird die WIRKSAME Laufzeit, nicht nur die Konstante.
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()

  fenster <- env$SCHEDULE_END_MINUTES - env$SCHEDULE_START_MINUTES
  expect_equal(env$DURATION, fenster)
  expect_equal(min(fenster, env$DURATION), fenster)
})

test_that("ein gesetztes DURATION begrenzt weiterhin", {
  # Der Deckel bleibt als Betriebsmittel erhalten -- etwa fuer kurze
  # Testlaeufe im Container.
  withr::local_envvar(c(DURATION = "60"))
  env <- source_scheduler()

  expect_equal(env$DURATION, 60)
})

# --- Tagesplan: plane_fenster / calculate_loops -----------------------------

test_that("plane_fenster: vor dem Fenster wartet bis zum Start und plant das volle Fenster", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()
  jetzt <- as.POSIXct("2026-09-27 10:30:00", tz = "Europe/Berlin")

  plan <- env$plane_fenster(jetzt)

  expect_equal(plan$zweig, "vor")
  expect_equal(plan$wartezeit_s, 1800)
  expect_equal(plan$verfuegbar, 720)
  expect_equal(plan$ideal_loops, 361)
})

test_that("plane_fenster: im Fenster ohne Wartezeit -- Deckel greift erst, wenn er erreicht wird", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()

  # 15:00 -- 480 Minuten verfuegbar, 241 waeren ideal, der Deckel (#255) kappt
  # auf 200.
  plan_15 <- env$plane_fenster(as.POSIXct("2026-09-27 15:00:00", tz = "Europe/Berlin"))
  expect_equal(plan_15$zweig, "im")
  expect_equal(plan_15$wartezeit_s, 0)
  expect_equal(plan_15$verfuegbar, 480)
  expect_equal(plan_15$ideal_loops, 200)

  # 17:00 -- 360 Minuten verfuegbar, 181 ideal, der Deckel greift hier nicht.
  plan_17 <- env$plane_fenster(as.POSIXct("2026-09-27 17:00:00", tz = "Europe/Berlin"))
  expect_equal(plan_17$zweig, "im")
  expect_equal(plan_17$wartezeit_s, 0)
  expect_equal(plan_17$verfuegbar, 360)
  expect_equal(plan_17$ideal_loops, 181)
})

test_that("plane_fenster: nach dem Fenster wartet bis morgen 11:00 und plant das volle Fenster", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()
  jetzt <- as.POSIXct("2026-09-27 23:30:00", tz = "Europe/Berlin")

  plan <- env$plane_fenster(jetzt)

  expect_equal(plan$zweig, "nach")
  expect_equal(plan$wartezeit_s, (30 + 660) * 60)
  expect_equal(plan$verfuegbar, 720)
  expect_equal(plan$ideal_loops, 361)
})

test_that("plane_fenster: die Grenzen 11:00 und 23:00 gehoeren zum Zweig 'im'", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()

  plan_start <- env$plane_fenster(as.POSIXct("2026-09-27 11:00:00", tz = "Europe/Berlin"))
  expect_equal(plan_start$zweig, "im")
  expect_equal(plan_start$verfuegbar, 720)
  expect_equal(plan_start$ideal_loops, 200)

  plan_ende <- env$plane_fenster(as.POSIXct("2026-09-27 23:00:00", tz = "Europe/Berlin"))
  expect_equal(plan_ende$zweig, "im")
  expect_equal(plan_ende$verfuegbar, 0)
  expect_equal(plan_ende$ideal_loops, 1)
})

test_that("plane_fenster: dauer_max deckelt in allen drei Zweigen gleichermassen", {
  env <- source_scheduler()

  plan_vor <- env$plane_fenster(as.POSIXct("2026-09-27 10:30:00", tz = "Europe/Berlin"), dauer_max = 60)
  plan_im <- env$plane_fenster(as.POSIXct("2026-09-27 15:00:00", tz = "Europe/Berlin"), dauer_max = 60)
  plan_nach <- env$plane_fenster(as.POSIXct("2026-09-27 23:30:00", tz = "Europe/Berlin"), dauer_max = 60)

  expect_equal(plan_vor$verfuegbar, 60)
  expect_equal(plan_vor$ideal_loops, 31)
  expect_equal(plan_im$verfuegbar, 60)
  expect_equal(plan_im$ideal_loops, 31)
  expect_equal(plan_nach$verfuegbar, 60)
  expect_equal(plan_nach$ideal_loops, 31)
})

test_that("plane_fenster: der 200er-Deckel gilt nur im Zweig 'im' (#255, bewusst gepinnt)", {
  # Heutiges Verhalten, keine Verbesserung: unmittelbar nach Fensterstart
  # schlaegt der Deckel sofort zu, unmittelbar davor (Zweig "vor") gilt er
  # nicht.
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()

  plan_danach <- env$plane_fenster(as.POSIXct("2026-09-27 11:02:00", tz = "Europe/Berlin"))
  expect_equal(plan_danach$zweig, "im")
  expect_equal(plan_danach$ideal_loops, 200)

  plan_davor <- env$plane_fenster(as.POSIXct("2026-09-27 10:58:00", tz = "Europe/Berlin"))
  expect_equal(plan_davor$zweig, "vor")
  expect_equal(plan_davor$ideal_loops, 361)
})

test_that("plane_fenster rechnet in Europe/Berlin, unabhaengig von der Prozess-Zeitzone", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()
  withr::local_timezone("UTC")

  # 09:30 UTC = 11:30 CEST (Sommerzeit) -- im Fenster.
  plan_utc <- env$plane_fenster(as.POSIXct("2026-09-27 09:30:00", tz = "UTC"))
  expect_equal(plan_utc$zweig, "im")
  expect_equal(plan_utc$verfuegbar, 690)

  # Gegenprobe: dieselbe Uhrzeit als Berliner Zeit ist noch vor dem Fenster.
  plan_berlin <- env$plane_fenster(as.POSIXct("2026-09-27 09:30:00", tz = "Europe/Berlin"))
  expect_equal(plan_berlin$zweig, "vor")

  # Winterzeit: 10:30 UTC = 11:30 CET -- ebenfalls im Fenster.
  plan_winter <- env$plane_fenster(as.POSIXct("2026-12-05 10:30:00", tz = "UTC"))
  expect_equal(plan_winter$zweig, "im")
})

test_that("calculate_loops: Huelle vor dem Fenster schlaeft die Wartezeit und reicht das Kontingent durch", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()
  env$checkAPILimits <- function(n, ...) n
  env$api_limits_plan_reduziert <- function() FALSE
  geschlafen <- NULL

  res <- suppressMessages(env$calculate_loops(
    jetzt = as.POSIXct("2026-09-27 10:30:00", tz = "Europe/Berlin"),
    schlafen = function(s) geschlafen <<- s
  ))

  expect_equal(geschlafen, 1800)
  expect_equal(res$loops, 361)
  expect_equal(res$duration, 720)
  expect_equal(res$initial_wait, 0)
  expect_false(res$plan_reduziert)
})

test_that("calculate_loops: Huelle im Fenster schlaeft nicht", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()
  env$checkAPILimits <- function(n, ...) n
  env$api_limits_plan_reduziert <- function() FALSE
  geschlafen <- NULL

  res_15 <- suppressMessages(env$calculate_loops(
    jetzt = as.POSIXct("2026-09-27 15:00:00", tz = "Europe/Berlin"),
    schlafen = function(s) geschlafen <<- s
  ))
  expect_null(geschlafen)
  expect_equal(res_15$loops, 200)
  expect_equal(res_15$duration, 480)

  res_17 <- suppressMessages(env$calculate_loops(
    jetzt = as.POSIXct("2026-09-27 17:00:00", tz = "Europe/Berlin"),
    schlafen = function(s) geschlafen <<- s
  ))
  expect_null(geschlafen)
  expect_equal(res_17$loops, 181)
  expect_equal(res_17$duration, 360)
})

test_that("calculate_loops: Huelle nach dem Fenster schlaeft bis morgen", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()
  env$checkAPILimits <- function(n, ...) n
  env$api_limits_plan_reduziert <- function() FALSE
  geschlafen <- NULL

  res <- suppressMessages(env$calculate_loops(
    jetzt = as.POSIXct("2026-09-27 23:30:00", tz = "Europe/Berlin"),
    schlafen = function(s) geschlafen <<- s
  ))

  expect_equal(geschlafen, 41400)
})

test_that("calculate_loops: Huelle reicht ein reduziertes Kontingent von checkAPILimits durch", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()
  env$checkAPILimits <- function(n, ...) 5L
  env$api_limits_plan_reduziert <- function() TRUE

  res <- suppressMessages(env$calculate_loops(
    jetzt = as.POSIXct("2026-09-27 15:00:00", tz = "Europe/Berlin"),
    schlafen = function(s) NULL
  ))

  expect_equal(res$loops, 5)
  expect_true(isTRUE(res$plan_reduziert))
})

test_that("calculate_loops: Huelle meldet den gewaehlten Zweig", {
  withr::local_envvar(c(DURATION = ""))
  env <- source_scheduler()
  env$checkAPILimits <- function(n, ...) n
  env$api_limits_plan_reduziert <- function() FALSE

  expect_message(
    env$calculate_loops(
      jetzt = as.POSIXct("2026-09-27 10:30:00", tz = "Europe/Berlin"),
      schlafen = function(s) NULL
    ),
    "Before 11:00"
  )
  expect_message(
    env$calculate_loops(
      jetzt = as.POSIXct("2026-09-27 23:30:00", tz = "Europe/Berlin"),
      schlafen = function(s) NULL
    ),
    "After 23:00"
  )
})
