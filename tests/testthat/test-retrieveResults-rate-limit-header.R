# Die Buchfuehrung ueber das Tageskontingent (Issue #190, Stufe 1).
#
# `.record_rate_limit_headers()` schreibt nach jedem Produktiv-Request die
# Rate-Limit-Header in `.api_rate_limit` -- und war bis hierher voellig
# ungetestet. Solange niemand las, war das konsequent. Mit dem Takt-Regler
# (Stufe 2) wird `.api_rate_limit` zum Eingang einer Entscheidung, und ein
# stiller Schreibfehler wuerde dort zu einem falschen Takt, nicht zu einem
# Fehler.
#
# Der zweite Teil: der Getter. Die Header lagen bereits vor, wurden aber von
# niemandem gelesen -- geparst und weggeworfen.

library(testthat)

lade_retrieve <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "retrieveResults.R"), local = env)
  env
}

# Eine Antwort mit vorgegebenen Headern. `.record_rate_limit_headers()` ruft
# httr::headers() darauf auf; wir haengen die Header ans Objekt und ersetzen
# httr::headers() nicht -- das haelt den Test an der echten Schnittstelle.
fake_response <- function(hdrs) {
  structure(list(headers = hdrs), class = "response")
}

mit_headers_stub <- function(env, code) {
  alt <- env$.record_rate_limit_headers
  # httr::headers() geht am `::` vorbei; der Ersatz muss in der Ladeumgebung
  # der Funktion stehen. Wir legen eine eigene httr-Liste darueber.
  f <- alt
  environment(f) <- new.env(parent = environment(alt))
  assign("httr", list(headers = function(response) response$headers),
         envir = environment(f))
  force(code(f))
}

test_that("vorhandene Header landen vollstaendig in .api_rate_limit", {
  env <- lade_retrieve()
  env$.api_rate_limit$remaining <- NULL
  env$.api_rate_limit$limit <- NULL
  env$.api_rate_limit$reset <- NULL

  mit_headers_stub(env, function(f) {
    f(fake_response(list(
      `x-ratelimit-requests-remaining` = "6807",
      `x-ratelimit-requests-limit` = "7500",
      `x-ratelimit-requests-reset` = "31302"
    )))
  })

  stand <- env$api_rate_limit_stand()
  expect_equal(stand$remaining, 6807)
  expect_equal(stand$limit, 7500)
  # Der Reset-Header ist eine DAUER in Sekunden (rollierendes Fenster,
  # gemessen 2026-09-12: 31302 s ~ 8,7 h), kein Zeitstempel. Wer ihn als
  # Mitternacht liest, rechnet die Tagesbilanz gegen die falsche Grenze.
  expect_equal(stand$reset_seconds, 31302)
  expect_s3_class(stand$as_of, "POSIXct")
})

test_that("fehlende Header lassen den letzten Stand unangetastet", {
  # Jede aufgezeichnete httptest-Kassette kommt ohne Rate-Limit-Header, und
  # 404er liefern sie auch in Produktion nicht. Der Schreibvorgang darf
  # daran weder scheitern noch einen gueltigen frueheren Stand mit NA
  # ueberschreiben -- sonst waere eine einzige header-lose Antwort genug,
  # um den Regler blind zu machen.
  env <- lade_retrieve()

  mit_headers_stub(env, function(f) {
    f(fake_response(list(
      `x-ratelimit-requests-remaining` = "6807",
      `x-ratelimit-requests-limit` = "7500",
      `x-ratelimit-requests-reset` = "31302"
    )))
    expect_silent(f(fake_response(list())))
  })

  stand <- env$api_rate_limit_stand()
  expect_equal(stand$remaining, 6807)
  expect_equal(stand$limit, 7500)
})

test_that("ohne je gesehene Header meldet der Getter NA statt zu scheitern", {
  # Loop 1 laeuft ohne vorherigen Live-Poll; vor dem ersten Vollabruf hat
  # noch niemand Header gesehen. Der Getter muss das als "keine Aussage"
  # melden koennen, ohne dass der Aufrufer auf exists() pruefen muss.
  env <- lade_retrieve()
  env$.api_rate_limit <- new.env(parent = emptyenv())

  stand <- env$api_rate_limit_stand()
  expect_true(is.na(stand$remaining))
  expect_true(is.na(stand$limit))
  expect_true(is.na(stand$reset_seconds))
})

test_that("der Reset-Rest schrumpft mit der Zeit seit der Messung", {
  # Der Header nennt die Restdauer ZUM ZEITPUNKT DER ANTWORT. Zwischen zwei
  # Loops vergehen Minuten; wer den Rohwert weiterreicht, rechnet mit einem
  # Fenster, das laenger ist als das echte, und drosselt zu schwach.
  env <- lade_retrieve()
  env$.api_rate_limit$remaining <- 6807
  env$.api_rate_limit$limit <- 7500
  env$.api_rate_limit$reset_seconds <- 3600
  env$.api_rate_limit$as_of <- Sys.time() - 600

  stand <- env$api_rate_limit_stand()
  expect_lt(stand$reset_seconds, 3600)
  expect_gt(stand$reset_seconds, 2900)
})

test_that("ein abgelaufenes Reset-Fenster geht nicht ins Negative", {
  env <- lade_retrieve()
  env$.api_rate_limit$remaining <- 6807
  env$.api_rate_limit$limit <- 7500
  env$.api_rate_limit$reset_seconds <- 60
  env$.api_rate_limit$as_of <- Sys.time() - 3600

  stand <- env$api_rate_limit_stand()
  expect_gte(stand$reset_seconds, 0)
})
