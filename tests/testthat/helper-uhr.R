# Eine vorgegebene Uhr fuer update_all_leagues_loop(jetzt = ...) (Issue #226).
#
# Das Sicherheitsnetz misst Zeit, nicht Runden. Ein Testlauf dauert aber nur
# Millisekunden, die echte Uhr kaeme nie ueber das Netz-Intervall. Diese Uhr
# laeuft deshalb je RUNDE um `takt` Sekunden weiter: Runde k steht auf
# (k - 1) * takt.
#
# Den Rundenwechsel erkennt sie am Live-Poll -- genau einmal je Runde und
# vor dem Abruf; Loop 1 ruft ohne Poll voll ab (dieselbe Annahme wie
# lauf_mit_safety_fetch() in test-update_all_leagues_loop-gating.R). `tick()` umhuellt
# deshalb den Stub fuer retrieveLiveFixtures:
#
#   uhr <- runden_uhr(takt = 600)
#   stub(update_all_leagues_loop, "retrieveLiveFixtures",
#        uhr$tick(function(...) integer(0)))
#   update_all_leagues_loop(..., jetzt = uhr$jetzt)
#
# Hat der Test schon einen mehrzeiligen Poll-Stub, ruft er stattdessen
# `uhr$weiter()` als erste Anweisung darin auf.
runden_uhr <- function(takt, start = as.POSIXct("2026-09-26 11:00:00",
                                                 tz = "Europe/Berlin")) {
  polls <- 0L
  list(
    jetzt = function() start + polls * takt,
    weiter = function() polls <<- polls + 1L,
    tick = function(poll_fn) {
      function(...) {
        polls <<- polls + 1L
        poll_fn(...)
      }
    },
    runde = function() polls + 1L
  )
}
