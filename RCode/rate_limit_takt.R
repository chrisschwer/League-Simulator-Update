# Der Takt-Regler des Schedulers (Issue #190, Stufen 2 und 3).
#
# Vorher plante der Scheduler sein Tagesbudget EINMAL beim Start
# (checkAPILimits() -> loops) und leitete daraus eine feste Wartezeit ab.
# Kippte unterwegs eine der beiden Annahmen -- das Limit des Providers oder
# unsere Schaetzung der Kosten je Runde --, lief der Prozess blind weiter.
#
# Die Information lag dabei schon vor: Jeder erfolgreiche Request traegt die
# Rate-Limit-Header, und `.record_rate_limit_headers()` (retrieveResults.R)
# schreibt sie mit. Dieser Regler macht daraus eine nachgefuehrte Wartezeit.
#
# Er ist bewusst eine REINE Funktion: kein HTTP, kein Sys.time(), kein
# Zustand zwischen den Aufrufen. Alles kommt als Argument herein, alles geht
# als Wert hinaus. Der Loop bleibt die duenne Huelle, die misst und schlaeft;
# die Entscheidung ist hier und ohne Netz pruefbar (test-rate-limit-takt.R).

# Die Vorgabewerte. Sie stehen im Signaturausdruck und nicht als Konstanten
# darueber, damit sie ueber formals() ablesbar sind -- die Tests lesen sie
# von dort, statt eigene Zahlen zu pflegen.
#
# TAKT_IDEAL_SEKUNDEN (120) ist der Zwei-Minuten-Takt, mit dem der Scheduler
# ohnehin plant (updateScheduler.R: ideal_loops = minutes / 2 + 1).
# TAKT_MAX_SEKUNDEN (600) ist die aeusserste Drosselung: Zehn Minuten sind
# fuer eine Live-Ansicht schon zaeh, aber immer noch eine Ansicht. Wer
# darueber hinaus streckt, kann die Seite auch abschalten.
# TAKT_MIN_SEKUNDEN (60) ist der harte Mindesttakt nach unten -- kein Wert,
# den der Regler anstrebt, sondern eine Grenze gegen eine fehlerhaft kleine
# `ideal_waittime`, die aus dem Loop einen Request-Sturm machen wuerde.

#' Die naechste Wartezeit aus dem frischen Kontingent-Stand.
#'
#' @param remaining Restliche Requests laut Header. NA = keine Aussage.
#' @param limit Kontingent laut Header. NA = keine Aussage.
#' @param seconds_until_reset Restdauer des ROLLIERENDEN Kontingent-Fensters
#'   in Sekunden (nicht Mitternacht -- gemessen 2026-09-12: 31302 s).
#' @param loops_remaining Geplante Runden bis zum Ende des Zeitfensters.
#' @param expected_cost_per_loop Erwartete Requests je Runde.
#' @param current_waittime Die Wartezeit, mit der der Loop gerade laeuft.
#' @param ideal_waittime Der gewuenschte Takt; zugleich die schnellste
#'   Frequenz, die der Regler je zurueckgibt.
#' @return Liste mit `waittime` (Sekunden), `gedrosselt` (TRUE, wenn
#'   gestreckt wurde) und `alarm` (TRUE unter der Alarmschwelle).
naechste_waittime <- function(remaining, limit, seconds_until_reset,
                              loops_remaining, expected_cost_per_loop,
                              current_waittime, ideal_waittime = 120,
                              min_waittime = 60,
                              max_waittime = 600,
                              safety_margin = 0.9,
                              hysterese = 0.15,
                              alarm_anteil = 0.10) {
  klemmen <- function(x) max(min_waittime, min(max_waittime, x))

  # Ohne Messwert wird nicht geraten: weder gedrosselt (das verlangsamte die
  # Live-Ansicht ohne Anlass) noch beschleunigt. Der bisherige Takt bleibt.
  if (length(remaining) != 1L || is.na(remaining)) {
    return(list(waittime = klemmen(current_waittime),
                gedrosselt = FALSE, alarm = FALSE))
  }

  # Kein Kontingent mehr: Ab hier wird jeder Request einzeln abgerechnet.
  # Die aeusserste Drosselung, nicht etwa eine Division durch Null oder --
  # schlimmer -- eine Wartezeit <= 0, die aus dem Loop ein Schnellfeuer
  # machte (genau der Ausfall aus #204, mit umgekehrtem Vorzeichen).
  if (remaining <= 0) {
    return(list(waittime = max_waittime, gedrosselt = TRUE, alarm = TRUE))
  }

  alarm <- length(limit) == 1L && !is.na(limit) && limit > 0 &&
    (remaining / limit) < alarm_anteil

  bezahlbar <- if (length(expected_cost_per_loop) != 1L ||
                     is.na(expected_cost_per_loop) ||
                     expected_cost_per_loop <= 0) {
    Inf
  } else {
    floor((remaining * safety_margin) / expected_cost_per_loop)
  }

  # Das Fenster, ueber das gestreckt werden muss. Zwei Grenzen, und die
  # engere gilt:
  #
  #   1. Bis zum Reset des Kontingents -- danach zaehlt der Provider neu.
  #   2. Bis zum geplanten Ende des Laufs (loops_remaining im Idealtakt) --
  #      wer ueber den Feierabend hinaus streckt, spart Requests, die das
  #      Kontingent ihm ohnehin geschenkt haette.
  #
  # Beide beschreiben Zeit, ueber die die noch bezahlbaren Runden verteilt
  # werden muessen.
  fenster <- suppressWarnings(as.numeric(seconds_until_reset))
  if (length(fenster) != 1L || is.na(fenster) || fenster < 0) fenster <- 0
  restrunden <- if (length(loops_remaining) == 1L && !is.na(loops_remaining) &&
                      loops_remaining > 0) {
    loops_remaining
  } else {
    0
  }
  if (restrunden > 0 && ideal_waittime > 0) {
    fenster <- min(fenster, restrunden * ideal_waittime)
  }

  ziel <- if (is.infinite(bezahlbar)) {
    # Eine Runde kostet nichts -- es gibt nichts zu strecken.
    ideal_waittime
  } else if (bezahlbar <= 0 || fenster <= 0) {
    # Das Budget traegt keine einzige Runde mehr, oder es gibt kein Fenster,
    # ueber das gestreckt werden koennte. Aeusserste Drosselung.
    max_waittime
  } else if (restrunden > 0 && bezahlbar >= restrunden) {
    # Das Budget traegt alle noch geplanten Runden. Keine Drosselung noetig
    # -- und keine aus einer Reset-Frist heraus, die laenger ist als der
    # Lauf selbst.
    ideal_waittime
  } else {
    # Die verbleibende Zeit auf die Runden verteilen, die das Budget noch
    # hergibt. `ceiling`, nicht `round`: Die Rundung muss zugunsten des
    # Budgets ausfallen, sonst passt eine Runde mehr ins Fenster als bezahlt
    # ist.
    ceiling(fenster / bezahlbar)
  }

  # Der Regler ist eine Bremse, kein Planer: Er wird nie schneller als
  # gewuenscht. Uebriges Budget in haeufigere Abrufe zu verwandeln waere
  # eine Produktentscheidung und keine Rate-Limit-Frage.
  ziel <- klemmen(max(ziel, ideal_waittime))

  gedrosselt <- ziel > ideal_waittime

  # Hysterese: Ohne sie folgte die Wartezeit jedem Rauschen im Restbudget
  # und sprunge Runde fuer Runde hin und her -- im Log nicht mehr lesbar,
  # in der Live-Ansicht als unregelmaessiger Takt sichtbar. Nur eine
  # Abweichung von mehr als `hysterese` bewegt den Takt.
  #
  # Ausnahme nach unten: Der Idealtakt selbst wird immer angenommen, sonst
  # bliebe ein einmal gestreckter Takt bei kleiner Differenz dauerhaft
  # oberhalb des Ideals stehen, ohne je zurueckzufedern.
  aktuell <- klemmen(current_waittime)
  if (!identical(ziel, aktuell) && aktuell > 0 &&
        abs(ziel - aktuell) / aktuell < hysterese &&
        !isTRUE(all.equal(ziel, klemmen(ideal_waittime)))) {
    ziel <- aktuell
    gedrosselt <- ziel > ideal_waittime
  }

  list(waittime = ziel, gedrosselt = gedrosselt, alarm = alarm)
}

# Zahlen im deutschen Format: Punkt als Tausender-, Komma als Dezimaltrenner.
# Die Budget-Zeile ist fuer einen menschlichen Leser im Log gedacht, nicht
# zum Parsen.
.takt_zahl <- function(x) {
  # decimal.mark explizit: In einer deutschen Locale sind big.mark und
  # decimal.mark sonst beide ".", und formatC warnt darueber bei jedem
  # Aufruf -- eine Warnung je Loop im Produktionslog.
  formatC(x, format = "d", big.mark = ".", decimal.mark = ",")
}

#' Die eine Budget-Zeile je Runde (Issue #190, Stufe 1).
#'
#' Bis hierher gab es genau eine Rate-Limit-Zeile je PROZESSSTART
#' (checkAPILimits). Der Tagesverlauf -- wer wann wie viel verbraucht hat --
#' war im Log nicht nachvollziehbar.
#'
#' `seconds_until_reset` wird bewusst als DAUER ausgewiesen ("Reset in
#' 4,2 h") und nicht als Uhrzeit: Der Header ist ein rollierendes Fenster,
#' keine Tagesgrenze. Wer daraus eine Mitternachtsbilanz liest, rechnet
#' gegen die falsche Grenze.
budget_zeile <- function(loop, loops, remaining, limit, seconds_until_reset) {
  kopf <- sprintf("Loop %d/%d: API", loop, loops)

  if (length(remaining) != 1L || is.na(remaining) ||
        length(limit) != 1L || is.na(limit)) {
    return(paste(kopf, "Kontingent noch unbekannt (keine Header gesehen)"))
  }

  verbraucht <- limit - remaining
  reset <- suppressWarnings(as.numeric(seconds_until_reset))
  reset_text <- if (length(reset) != 1L || is.na(reset)) {
    "Reset unbekannt"
  } else {
    sprintf("Reset in %s h", sub("\\.", ",", sprintf("%.1f", reset / 3600)))
  }

  sprintf("%s %s/%s verbraucht, %s verbleibend, %s",
          kopf, .takt_zahl(verbraucht), .takt_zahl(limit),
          .takt_zahl(remaining), reset_text)
}
