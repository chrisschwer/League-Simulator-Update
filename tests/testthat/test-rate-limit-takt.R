# Der Takt-Regler (Issue #190, Stufe 2).
#
# Bis hierher plante der Scheduler sein Tagesbudget EINMAL beim Start
# (checkAPILimits() -> loops) und fror daraus in update_all_leagues_loop()
# eine feste waittime ein. Aendert sich das Limit unterwegs -- Plan
# herabgestuft, ein Nebenpfad verbraucht still Requests, ein Fehlerfall
# feuert schneller als geplant -- merkt der laufende Prozess nichts davon.
#
# Die Rate-Limit-Header liegen dabei nach JEDEM Produktiv-Request vor
# (.api_rate_limit in retrieveResults.R). Der Regler hier macht daraus eine
# nachgefuehrte Wartezeit.
#
# Er ist bewusst eine REINE Funktion: kein HTTP, kein Sys.time(), kein
# Zustand. Alles, was er wissen muss, kommt als Argument herein. Damit ist
# das eigentliche Verhalten -- strecken, zurueckfedern, nicht schwingen --
# ohne Netz und ohne Uhr pruefbar, und der Loop bleibt eine duenne Huelle
# darum.

library(testthat)

lade_takt <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "rate_limit_takt.R"), local = env)
  env
}

# Die Defaults der Signatur, damit die Tests nicht neben der Implementierung
# eigene Zahlen pflegen.
takt_default <- function(env, name) {
  eval(formals(env$naechste_waittime)[[name]], envir = env)
}

test_that("komfortables Budget laeuft im Idealtakt", {
  # Volles Tageskontingent, wenige Runden vor uns: Es gibt keinen Grund zu
  # strecken. Der Regler muss dann den Idealtakt liefern -- er ist eine
  # Bremse, kein Planer, und darf nie schneller werden als gewuenscht.
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 7000, limit = 7500,
    seconds_until_reset = 8 * 3600,
    loops_remaining = 100,
    expected_cost_per_loop = 6,
    current_waittime = 120,
    ideal_waittime = 120
  )

  expect_equal(ergebnis$waittime, 120)
  expect_false(ergebnis$gedrosselt)
})

test_that("knappes Budget streckt den Takt, bis es bis zum Reset reicht", {
  # 300 Requests, 200 Runden a 6 Requests geplant (= 1.200): Das Budget
  # traegt nur ein Viertel der Runden. Der Regler muss den Takt so weit
  # strecken, dass die verbleibende Zeit bis zum Reset auf die Runden
  # verteilt wird, die das Budget noch hergibt.
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 300, limit = 7500,
    seconds_until_reset = 3600,
    loops_remaining = 200,
    expected_cost_per_loop = 6,
    current_waittime = 120,
    ideal_waittime = 120
  )

  # bezahlbare Runden = floor(300 * 0.9 / 6) = 45; 3600 s / 45 = 80 s --
  # das ist kuerzer als der Idealtakt, also greift der Idealtakt. Gegen
  # ihn gestreckt wird erst, wenn die Zeit je bezahlbarer Runde LAENGER
  # ist als der Ideal-Takt. Dieser Fall gehoert trotzdem hierher: Er
  # belegt, dass die Formel nicht einfach nach oben durchschlaegt.
  expect_equal(ergebnis$waittime, 120)

  # Jetzt der echte Engpass: dieselben 300 Requests, aber acht Stunden
  # Restfenster. 28.800 s / 45 Runden = 640 s -- gedeckelt auf das Maximum.
  eng <- env$naechste_waittime(
    remaining = 300, limit = 7500,
    seconds_until_reset = 8 * 3600,
    loops_remaining = 200,
    expected_cost_per_loop = 6,
    current_waittime = 120,
    ideal_waittime = 120
  )

  expect_gt(eng$waittime, 120)
  expect_true(eng$gedrosselt)
  expect_lte(eng$waittime, takt_default(env, "max_waittime"))
})

test_that("die Streckung deckt das Budget bis zum Reset ab", {
  # Kernaussage der Stufe 2: Nach der Anpassung darf die Hochrechnung
  # "Runden, die bis zum Reset noch laufen x Kosten je Runde" das
  # Restbudget (abzueglich Sicherheitsabschlag) nicht mehr ueberschreiten.
  env <- lade_takt()

  remaining <- 600
  reset <- 6 * 3600
  kosten <- 6

  ergebnis <- env$naechste_waittime(
    remaining = remaining, limit = 7500,
    seconds_until_reset = reset,
    loops_remaining = 500,
    expected_cost_per_loop = kosten,
    current_waittime = 120,
    ideal_waittime = 120
  )

  runden_bis_reset <- floor(reset / ergebnis$waittime)
  expect_lte(runden_bis_reset * kosten,
             remaining * takt_default(env, "safety_margin"))
})

test_that("kleine Aenderungen bewegen den Takt nicht (Hysterese)", {
  # Ohne Hysterese folgte die Wartezeit jedem Rauschen im Restbudget und
  # sprunge Runde fuer Runde hin und her -- im Log nicht mehr lesbar und in
  # der Live-Ansicht als unregelmaessiger Takt sichtbar. Aendert sich der
  # rechnerische Zielwert nur um wenige Prozent, bleibt der Takt stehen.
  env <- lade_takt()

  basis <- env$naechste_waittime(
    remaining = 600, limit = 7500,
    seconds_until_reset = 6 * 3600,
    loops_remaining = 500,
    expected_cost_per_loop = 6,
    current_waittime = 120,
    ideal_waittime = 120
  )$waittime

  # Ein Prozent weniger Restbudget: Der Zielwert verschiebt sich minimal.
  kaum_anders <- env$naechste_waittime(
    remaining = 594, limit = 7500,
    seconds_until_reset = 6 * 3600,
    loops_remaining = 500,
    expected_cost_per_loop = 6,
    current_waittime = basis,
    ideal_waittime = 120
  )

  expect_equal(kaum_anders$waittime, basis)
})

test_that("grosse Aenderungen bewegen den Takt sehr wohl", {
  # Gegenprobe zur Hysterese: Ohne sie liesse sich der Test oben erfuellen,
  # indem man den Takt gar nicht mehr nachfuehrt.
  env <- lade_takt()

  basis <- env$naechste_waittime(
    remaining = 600, limit = 7500,
    seconds_until_reset = 6 * 3600,
    loops_remaining = 500,
    expected_cost_per_loop = 6,
    current_waittime = 120,
    ideal_waittime = 120
  )$waittime

  halbiert <- env$naechste_waittime(
    remaining = 300, limit = 7500,
    seconds_until_reset = 6 * 3600,
    loops_remaining = 500,
    expected_cost_per_loop = 6,
    current_waittime = basis,
    ideal_waittime = 120
  )

  expect_gt(halbiert$waittime, basis)
})

test_that("der Takt federt zum Ideal zurueck, wenn das Budget wieder reicht", {
  # Nach dem Reset (oder nachdem ein Nebenpfad aufgehoert hat zu
  # verbrauchen) darf der gestreckte Takt nicht stehenbleiben.
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 7400, limit = 7500,
    seconds_until_reset = 8 * 3600,
    loops_remaining = 200,
    expected_cost_per_loop = 6,
    current_waittime = 600, # vorher gestreckt
    ideal_waittime = 120
  )

  expect_equal(ergebnis$waittime, 120)
  expect_false(ergebnis$gedrosselt)
})

test_that("der Takt wird nie schneller als der Idealwert", {
  # Selbst bei unverbrauchtem Kontingent und sehr wenigen Runden bleibt der
  # Idealtakt die Obergrenze der Frequenz. Der Regler spart Requests, er
  # verteilt kein uebriges Budget in schnellere Abrufe -- das waere eine
  # Produktentscheidung und keine Rate-Limit-Frage.
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 7500, limit = 7500,
    seconds_until_reset = 12 * 3600,
    loops_remaining = 2,
    expected_cost_per_loop = 6,
    current_waittime = 120,
    ideal_waittime = 120
  )

  expect_equal(ergebnis$waittime, 120)
})

test_that("ein erschoepftes Kontingent liefert die maximale Wartezeit", {
  # remaining = 0 heisst: jede weitere Runde wird einzeln abgerechnet. Der
  # Regler darf daraus keine Division durch Null und schon gar keine
  # Wartezeit <= 0 machen -- das waere ein Loop ohne Pause, also genau der
  # Ausfall aus #204 mit umgekehrtem Vorzeichen.
  env <- lade_takt()

  for (rest in c(0, -50)) {
    ergebnis <- env$naechste_waittime(
      remaining = rest, limit = 7500,
      seconds_until_reset = 4 * 3600,
      loops_remaining = 100,
      expected_cost_per_loop = 6,
      current_waittime = 120,
      ideal_waittime = 120
    )

    expect_equal(ergebnis$waittime, takt_default(env, "max_waittime"),
                 info = sprintf("remaining = %d", rest))
    expect_true(ergebnis$gedrosselt)
  }
})

test_that("die Wartezeit ist nie negativ, nie null und nie unendlich", {
  # Eine Sammelpruefung ueber Grenzfaelle, die in Produktion vorkommen
  # koennen: fehlende Header (NA), ein Reset-Fenster von 0 s (kurz vor dem
  # Umschlag), keine Runden mehr, Kosten von 0.
  env <- lade_takt()
  min_takt <- takt_default(env, "min_waittime")
  max_takt <- takt_default(env, "max_waittime")

  faelle <- list(
    list(remaining = NA_real_, limit = NA_real_, seconds_until_reset = 3600,
         loops_remaining = 100, expected_cost_per_loop = 6),
    list(remaining = 5000, limit = 7500, seconds_until_reset = 0,
         loops_remaining = 100, expected_cost_per_loop = 6),
    list(remaining = 5000, limit = 7500, seconds_until_reset = 3600,
         loops_remaining = 0, expected_cost_per_loop = 6),
    list(remaining = 5000, limit = 7500, seconds_until_reset = 3600,
         loops_remaining = 100, expected_cost_per_loop = 0),
    list(remaining = 1, limit = 7500, seconds_until_reset = 43200,
         loops_remaining = 360, expected_cost_per_loop = 11)
  )

  for (k in seq_along(faelle)) {
    ergebnis <- do.call(env$naechste_waittime, c(
      faelle[[k]],
      list(current_waittime = 120, ideal_waittime = 120)
    ))
    expect_true(is.finite(ergebnis$waittime), info = sprintf("Fall %d", k))
    expect_true(ergebnis$waittime >= min_takt, info = sprintf("Fall %d", k))
    expect_true(ergebnis$waittime <= max_takt, info = sprintf("Fall %d", k))
  }
})

test_that("ohne Header-Wert bleibt der bisherige Takt stehen", {
  # Keine Aussage moeglich heisst: nicht raten. Weder drosseln (das
  # verlangsamte die Live-Ansicht ohne Anlass) noch beschleunigen.
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = NA_real_, limit = NA_real_,
    seconds_until_reset = NA_real_,
    loops_remaining = 100,
    expected_cost_per_loop = 6,
    current_waittime = 300,
    ideal_waittime = 120
  )

  expect_equal(ergebnis$waittime, 300)
})

test_that("der harte Mindesttakt wird nie unterschritten", {
  # Auch ein sehr kleiner ideal_waittime darf die Live-Ansicht nicht in
  # einen Request-Sturm verwandeln.
  env <- lade_takt()
  min_takt <- takt_default(env, "min_waittime")

  ergebnis <- env$naechste_waittime(
    remaining = 7500, limit = 7500,
    seconds_until_reset = 8 * 3600,
    loops_remaining = 100,
    expected_cost_per_loop = 6,
    current_waittime = 1,
    ideal_waittime = 1
  )

  expect_gte(ergebnis$waittime, min_takt)
})

# --- Stufe 3: Alarm ---------------------------------------------------------

test_that("unter der Alarmschwelle meldet der Regler Alarm", {
  # Unter 10 % Restbudget ist die Lage nicht mehr "gedrosselt", sondern
  # meldepflichtig. Der Regler entscheidet das (reine Funktion), der Loop
  # schreibt die Zeile.
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 700, limit = 7500, # 9,3 %
    seconds_until_reset = 4 * 3600,
    loops_remaining = 100,
    expected_cost_per_loop = 6,
    current_waittime = 120,
    ideal_waittime = 120
  )

  expect_true(ergebnis$alarm)
})

test_that("ueber der Alarmschwelle meldet der Regler keinen Alarm", {
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 3000, limit = 7500,
    seconds_until_reset = 4 * 3600,
    loops_remaining = 100,
    expected_cost_per_loop = 6,
    current_waittime = 120,
    ideal_waittime = 120
  )

  expect_false(ergebnis$alarm)
})

# --- Die Budget-Zeile -------------------------------------------------------

test_that("die Budget-Zeile nennt Verbrauch, Rest und Reset", {
  # Stufe 1: genau eine Zeile je Loop, aus der ein Operator den Tagesverlauf
  # lesen kann. Der Reset-Header ist ein ROLLIERENDES Fenster in Sekunden,
  # nicht Mitternacht -- die Zeile muss ihn als Dauer ausweisen, sonst
  # rechnet der Leser eine Tagesbilanz auf eine falsche Grenze.
  env <- lade_takt()

  zeile <- env$budget_zeile(
    loop = 42, loops = 361,
    remaining = 6297, limit = 7500,
    seconds_until_reset = 4.2 * 3600
  )

  expect_match(zeile, "Loop 42/361")
  # Verbraucht ist die Differenz limit - remaining, nicht etwa remaining.
  expect_match(zeile, "1\\.203/7\\.500")
  expect_match(zeile, "6\\.297")
  expect_match(zeile, "Reset in 4,2 h")
})

test_that("ohne Header-Werte sagt die Budget-Zeile genau das", {
  # Vor dem ersten Produktiv-Request (Loop 1, Live-Poll uebersprungen) sind
  # die Header noch leer. Die Zeile darf dann nicht "NA/NA verbraucht"
  # melden, als waere das eine Messung.
  env <- lade_takt()

  zeile <- env$budget_zeile(
    loop = 1, loops = 361,
    remaining = NA_real_, limit = NA_real_,
    seconds_until_reset = NA_real_
  )

  expect_match(zeile, "Loop 1/361")
  expect_no_match(zeile, "NA")
})
