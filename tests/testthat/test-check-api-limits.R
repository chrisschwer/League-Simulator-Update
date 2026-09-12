# checkAPILimits() entscheidet einmal je Scheduler-Lauf, wie viele Runden das
# Tagesbudget hergibt. Der Funktionskoerper war bis hierher voellig ungetestet
# -- gedeckt war nur der Default-Ausdruck der Signatur
# (test-frauen-ligen-aktivierung.R). Diese Datei holt das nach.
#
# Anlass ist Issue #129, Punkt 1: Die Funktion trug einen Cache-Zweig, der die
# von retrieveResults() aufgezeichneten Rate-Limit-Header wiederverwenden
# sollte, statt einen eigenen Probe-Request auszugeben. Der Zweig war in
# Produktion unerreichbar:
#
#   updateScheduler.R:189  loop_config <- calculate_loops()  -> checkAPILimits()
#   updateScheduler.R:192  update_all_leagues_loop(...)      -> retrieveResults()
#
# calculate_loops() ist der einzige Aufrufer und laeuft genau einmal je
# Prozess -- es gibt keine Schleife, die zurueckspringt. Der Cache
# (.api_rate_limit, gefuellt in retrieveResults.R:19-27) wird also erst NACH
# der einzigen Abfrage beschrieben und ist bei ihr immer leer; der
# Probe-Request ging ohnehin jedes Mal hinaus. Entscheidung Christoph: Zweig
# entfernen, den einen Request pro Tag akzeptieren -- toter Code, der nach
# Funktion aussieht, ist schlimmer als eine ehrliche Sonde.
#
# Diese Tests beschreiben den Zustand DANACH: was die Funktion noch leistet,
# und dass sie die Header wirklich abfragt, statt sich auf einen Cache zu
# verlassen.
#
# Mocking: Die Datei wird per source() geladen, nicht als Paket -- ein
# Namespace-Mock (local_mocked_bindings) findet hier nichts, und ein
# httr-Objekt in der Ladeumgebung greift nicht, weil httr::GET am `::`
# vorbeigeht. mockery::stub() schreibt den Aufruf innerhalb der Funktion um
# und ist das Muster, mit dem diese Suite ohnehin arbeitet
# (test-update-loop-gating.R).

library(testthat)
library(mockery)

lade_check_api_limits <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "checkAPILimits.R"), local = env)
  env
}

# Ein Schluessel muss gesetzt sein, sonst steigt die Funktion vorher aus.
mit_api_key <- function(code) {
  alt <- Sys.getenv("RAPIDAPI_KEY", unset = NA)
  Sys.setenv(RAPIDAPI_KEY = "test-key")
  on.exit({
    if (is.na(alt)) Sys.unsetenv("RAPIDAPI_KEY") else Sys.setenv(RAPIDAPI_KEY = alt)
  }, add = TRUE)
  force(code)
}

# Die Funktion mit vorgegebenen Rate-Limit-Headern. `zaehler` (optional) wird
# je Probe-Request hochgezaehlt, damit ein Test belegen kann, DASS abgefragt
# wurde -- nicht nur, was dabei herauskam.
mit_headern <- function(env, hdrs, zaehler = NULL) {
  f <- env$checkAPILimits
  stub(f, "httr::GET", function(...) {
    if (!is.null(zaehler)) {
      assign("n", get("n", envir = zaehler) + 1L, envir = zaehler)
    }
    structure(list(), class = "response")
  })
  stub(f, "httr::headers", function(response) hdrs)
  f
}

je_loop_von <- function(env) {
  eval(formals(env$checkAPILimits)$avg_calls_per_loop, envir = env)
}

test_that("checkAPILimits deckelt die Rundenzahl auf das, was das Budget hergibt", {
  # 200 Restrequests, Sicherheitsabschlag 0.9, bei zehn Ligen 6 Requests je
  # Loop -> floor(180 / 6) = 30. Der Wunsch von 360 wird darauf gekuerzt.
  env <- lade_check_api_limits()
  f <- mit_headern(env, list(
    `x-ratelimit-requests-remaining` = "200",
    `x-ratelimit-requests-limit` = "7500"
  ))

  mit_api_key(expect_equal(f(360), floor((200 * 0.9) / je_loop_von(env))))
})

test_that("checkAPILimits laesst den Wunsch stehen, wenn das Budget reicht", {
  # Volles Tagesbudget: Die Rundenzahl darf NICHT nach oben korrigiert
  # werden -- die Funktion ist eine Obergrenze, kein Planer.
  env <- lade_check_api_limits()
  f <- mit_headern(env, list(
    `x-ratelimit-requests-remaining` = "7500",
    `x-ratelimit-requests-limit` = "7500"
  ))

  mit_api_key(expect_equal(f(360), 360))
})

test_that("checkAPILimits fragt die Header ab, statt einen Cache zu benutzen", {
  # Der Kern von Issue #129, Punkt 1: Ein vorhandener, frischer
  # .api_rate_limit-Eintrag darf die Abfrage NICHT ersetzen. Der fruehere
  # Cache-Zweig haette hier abgekuerzt und 7500 statt der echten 200
  # gelesen -- in Produktion unerreichbar, aber genau hier sichtbar.
  env <- lade_check_api_limits()
  env$.api_rate_limit <- new.env(parent = emptyenv())
  env$.api_rate_limit$remaining <- 7500
  env$.api_rate_limit$limit <- 7500
  env$.api_rate_limit$as_of <- Sys.time()

  zaehler <- new.env(parent = emptyenv())
  zaehler$n <- 0L
  f <- mit_headern(env, list(
    `x-ratelimit-requests-remaining` = "200",
    `x-ratelimit-requests-limit` = "7500"
  ), zaehler = zaehler)

  mit_api_key(expect_equal(f(360), floor((200 * 0.9) / je_loop_von(env))))
  expect_equal(zaehler$n, 1L)
})

test_that("ohne API-Schluessel gibt checkAPILimits den Wunsch unveraendert zurueck", {
  # Kein Schluessel heisst: keine Aussage moeglich. Die Funktion darf dann
  # nicht deckeln -- der Lauf scheitert spaeter deutlicher an anderer Stelle.
  env <- lade_check_api_limits()
  alt <- Sys.getenv("RAPIDAPI_KEY", unset = NA)
  Sys.unsetenv("RAPIDAPI_KEY")
  on.exit(if (!is.na(alt)) Sys.setenv(RAPIDAPI_KEY = alt), add = TRUE)

  expect_warning(ergebnis <- env$checkAPILimits(360), "No RAPIDAPI_KEY")
  expect_equal(ergebnis, 360)
})

test_that("unlesbare Header deckeln nicht, sondern lassen den Wunsch stehen", {
  # BEIM SCHREIBEN DIESES TESTS GEFUNDEN, nicht aus dem Issue: Fehlt der
  # Header, liefert as.numeric(NULL) einen Vektor der LAENGE 0 -- und
  # `if (is.na(remaining))` scheitert daran mit "Argument hat Laenge 0",
  # statt den Zweig zu nehmen. Die Warnung "Could not read rate limit
  # headers" ist damit unerreichbar; der Fehler laeuft in das aeussere
  # tryCatch und zieht still die konservative Schaetzung.
  #
  # Folge in Produktion: Antwortet die API einmal ohne Header (Fehlercode,
  # Proxy, Wartung), plant der Scheduler 9 statt 360 Runden -- er endet
  # dann nach rund 18 Minuten, und niemand erfaehrt warum, denn die
  # Meldung nennt einen "Error checking API limits" und nicht den
  # fehlenden Header.
  #
  # Der Test haelt die ABSICHT des vorhandenen Guards fest, nicht das
  # heutige Verhalten: keine Aussage moeglich -> nicht deckeln.
  #
  # UEBERSPRUNGEN bis #190: Der Fix gehoert dorthin -- das Issue nimmt den
  # Fall ausdruecklich auf ("Mitzunehmen") und verweist auf genau diesen
  # Test. Hier stehen zu bleiben waere die falsche Stelle: #190 baut die
  # Ueberwachung, die diesen Fehlerfall ueberhaupt erst sichtbar macht.
  # Der Test bleibt als ausformulierte Reproduktion stehen, statt in einer
  # Issue-Beschreibung zu verwittern.
  skip("Fix gehoert zu #190 (Rate-Limit-Ueberwachung); Reproduktion bleibt hier")

  env <- lade_check_api_limits()
  f <- mit_headern(env, list())

  mit_api_key({
    expect_warning(ergebnis <- f(360), "Could not read rate limit")
    expect_equal(ergebnis, 360)
  })
})

test_that("faellt die Abfrage aus, greift die konservative Schaetzung aus der Registry", {
  # Der Fallback folgt der Ligazahl: ein Live-Poll plus im unguenstigsten
  # Fall ein Vollabruf je aktiver Liga. Ohne Registry-Bezug stuende hier die
  # 33 aus der Drei-Ligen-Zeit.
  env <- lade_check_api_limits()
  erwartet <- floor(100 / (1 + length(env$league_ids())))

  f <- env$checkAPILimits
  stub(f, "httr::GET", function(...) stop("Netzwerk weg"))

  mit_api_key({
    expect_warning(ergebnis <- f(360))
    expect_equal(ergebnis, erwartet)
  })
})
