library(testthat)

# --- Zeitfenster ------------------------------------------------------------

source_scheduler <- function() {
  # updateScheduler.R fuehrt beim Sourcen main() aus; nur die Konstanten und
  # calculate_loops() werden gebraucht -- deshalb alles bis main() auswerten.
  #
  # Unter dem Repo-Root, weil der Dateikopf die TeamList mit relativem Pfad
  # sucht. Dasselbe Muster wie in test-update-loop-gating.R.
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

test_that("calculate_loops rechnet mit dem neuen Fenster", {
  env <- source_scheduler()

  # Volles Fenster: 720 Minuten, alle zwei Minuten ein Loop.
  expect_equal(env$SCHEDULE_END_MINUTES - env$SCHEDULE_START_MINUTES, 720)
})
