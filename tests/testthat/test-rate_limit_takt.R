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

test_that("unter der Stopp-Grenze wird gar nicht mehr abgerufen", {
  # Drosseln reicht nicht, wenn das Kontingent fast leer ist: Ein
  # gestreckter Takt verbraucht weiter, nur langsamer. Unterhalb von
  # `stopp_unter` sagt der Regler deshalb "gar nicht", nicht "langsamer".
  #
  # Die Grenze liegt bewusst ueber 0: Bei zehn Ligen kostet eine Runde 11
  # Requests. Wer erst bei 0 stoppt, hat die letzte Runde schon halb
  # bezahlt und mitten im Vollabruf ein 429 kassiert -- Requests ausgegeben
  # und trotzdem keine vollstaendigen Daten bekommen.
  env <- lade_takt()
  grenze <- takt_default(env, "stopp_unter")

  for (rest in 0:(grenze - 1)) {
    ergebnis <- env$naechste_waittime(
      remaining = rest, limit = 7500,
      seconds_until_reset = 4 * 3600,
      loops_remaining = 100,
      expected_cost_per_loop = 11,
      current_waittime = 120,
      ideal_waittime = 120
    )
    expect_true(ergebnis$stopp, info = sprintf("remaining = %d", rest))
  }
})

test_that("auf der Stopp-Grenze wird noch abgerufen", {
  # Gegenprobe: Ohne sie liesse sich der Test oben erfuellen, indem man
  # immer stoppt. Genau AUF der Grenze (10) laeuft der Abruf noch.
  env <- lade_takt()
  grenze <- takt_default(env, "stopp_unter")

  ergebnis <- env$naechste_waittime(
    remaining = grenze, limit = 7500,
    seconds_until_reset = 4 * 3600,
    loops_remaining = 100,
    expected_cost_per_loop = 11,
    current_waittime = 120,
    ideal_waittime = 120
  )

  expect_false(ergebnis$stopp)
})

test_that("ohne Messwert wird nicht gestoppt", {
  # Ein fehlender Header ist keine Messung eines leeren Kontingents,
  # sondern gar keine Messung. Wer daraus einen Stopp ableitet, legt den
  # Scheduler lahm, sobald die API einmal ohne Header antwortet.
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = NA_real_, limit = NA_real_,
    seconds_until_reset = NA_real_,
    loops_remaining = 100,
    expected_cost_per_loop = 11,
    current_waittime = 120,
    ideal_waittime = 120
  )

  expect_false(ergebnis$stopp)
})

test_that("bei komfortablem Budget wird nicht gestoppt", {
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 7000, limit = 7500,
    seconds_until_reset = 8 * 3600,
    loops_remaining = 100,
    expected_cost_per_loop = 6,
    current_waittime = 120,
    ideal_waittime = 120
  )

  expect_false(ergebnis$stopp)
})

test_that("der freie Plan (100 Requests/Tag) laesst sich noch bedienen", {
  # Der Grund, aus dem max_waittime 5400 s und nicht 600 s ist: Der FREIE
  # api-football-Plan gibt 100 Requests am Tag. Bei zehn Ligen kostet ein
  # Vollabruf 11, das Budget traegt also rund neun Abrufe -- auf ein
  # 24-Stunden-Fenster verteilt gut zwei Stunden je Runde.
  #
  # Bei einer Deckelung auf 600 s koennte der Regler gar nicht weit genug
  # strecken: Er liefe in den Deckel und verbrauchte das Kontingent
  # trotzdem lange vor Tagesende. Der Test haelt fest, dass er wirklich
  # streckt -- und dass er dabei die Obergrenze nicht durchbricht.
  env <- lade_takt()
  max_takt <- takt_default(env, "max_waittime")

  ergebnis <- env$naechste_waittime(
    remaining = 100, limit = 100,
    seconds_until_reset = 24 * 3600,
    loops_remaining = 360,
    expected_cost_per_loop = 11,
    current_waittime = 120,
    ideal_waittime = 120
  )

  # floor(100 * 0.9 / 11) = 8 bezahlbare Runden. Das Fenster ist hier nicht
  # der Reset (24 h), sondern das geplante Laufende (360 x 120 s = 12 h),
  # weil die engere der beiden Grenzen gilt: 43200 / 8 = 5400 s.
  expect_gte(ergebnis$waittime, 5400)
  expect_lte(ergebnis$waittime, max_takt)
  expect_true(ergebnis$gedrosselt)
  # KEIN Alarm: Das Kontingent ist mit 100 von 100 unangetastet. Die
  # Alarmschwelle misst den ANTEIL, nicht die absolute Zahl -- ein kleiner
  # Plan ist kein Notfall, ein aufgebrauchter schon. Genau deshalb sind
  # Drosselung und Alarm zwei getrennte Aussagen des Reglers.
  expect_false(ergebnis$alarm)
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

# --- Der Planungshorizont bei kleinem Kontingent (Issue #224, Punkt 3) ---
#
# Das Restbudget muss bis zum NAECHSTEN RESET reichen, nicht nur bis zum
# Ende des heutigen Fensters. Bei 7.500 Requests faellt der Unterschied
# nicht auf -- das Budget traegt den Tag ohnehin. Beim Free-Plan (100 pro
# rollierenden 24 h) entscheidet er alles:
#
# Reset um 12:00 des Folgetages, jetzt ist 12:00 heute, 89 Requests uebrig.
# Wer nur bis 23:00 plant, verteilt sie auf elf Stunden -- und steht ab
# 23:00 ohne Kontingent da, waehrend der Reset noch dreizehn Stunden
# entfernt ist. Am naechsten Morgen ab 11:00 ist nichts mehr da.
#
# Gezaehlt werden dabei nur Minuten INNERHALB des Fensters (11:00-23:00):
# Zwischen 23:00 und 11:00 laeuft der Scheduler nicht, diese Stunden
# koennen also keine Runden aufnehmen. Der Horizont ist "Fenster-Sekunden
# bis zum Reset", nicht "Sekunden bis zum Reset".

test_that("bei kleinem Kontingent reicht der Horizont ueber das Fensterende hinaus", {
  # 89 Requests, 11 je Runde, Sicherheitsabschlag 0,9 -> 7 bezahlbare
  # Runden. Der Reset liegt 24 h entfernt; davon liegen 11 h im heutigen
  # Fenster (12:00-23:00) und 13 h im morgigen (11:00-12:00 ist nur 1 h,
  # aber das Fenster beginnt 11:00, also 1 h) -- zusammen 12 h Fensterzeit.
  #
  # Der Kern der Zusicherung: Der Takt muss LAENGER sein als der, der sich
  # aus dem heutigen Fensterrest allein ergaebe. Wer nur bis 23:00 plant,
  # taktet zu schnell und ist vor dem Reset leer.
  # Die Zusicherung wird an der ungedeckelten Rechnung geprueft: Beide
  # Horizonte laufen bei diesem winzigen Budget in `max_waittime`, der
  # Deckel verwischt den Unterschied also im Ergebnis. Gepinnt wird
  # deshalb, dass der laengere Horizont wirklich in die Rechnung eingeht --
  # ueber einen Fall, in dem der Deckel noch nicht greift.
  env <- lade_takt()
  gedeckelt <- takt_default(env, "max_waittime")

  # 300 Requests, 6 je Runde -> 45 bezahlbare Runden. Ueber 11 h ergaebe
  # das 880 s je Runde, ueber 24 h Fensterzeit 1920 s. Beide unter dem
  # Deckel, der Unterschied also sichtbar.
  nur_heute <- env$naechste_waittime(
    remaining = 300, limit = 7500,
    seconds_until_reset = 24 * 3600,
    fenster_sekunden_bis_reset = 11 * 3600,
    loops_remaining = 360, expected_cost_per_loop = 6,
    current_waittime = 120, ideal_waittime = 120
  )
  bis_reset <- env$naechste_waittime(
    remaining = 300, limit = 7500,
    seconds_until_reset = 24 * 3600,
    fenster_sekunden_bis_reset = 24 * 3600,
    loops_remaining = 360, expected_cost_per_loop = 6,
    current_waittime = 120, ideal_waittime = 120
  )

  expect_gt(bis_reset$waittime, nur_heute$waittime)
  expect_lt(bis_reset$waittime, gedeckelt)

  # Und der Fall aus dem Auftrag: 89 Requests kurz nach einem Reset. Er
  # laeuft in den Deckel -- was die richtige Antwort ist, aber eben keine,
  # an der sich der Horizont ablesen liesse.
  frei_plan <- env$naechste_waittime(
    remaining = 89, limit = 100,
    seconds_until_reset = 24 * 3600,
    fenster_sekunden_bis_reset = 12 * 3600,
    loops_remaining = 360,
    expected_cost_per_loop = 11,
    current_waittime = 120,
    ideal_waittime = 120
  )
  expect_equal(frei_plan$waittime, gedeckelt)
  expect_true(frei_plan$gedrosselt)
})

test_that("ohne eigenen Horizont bleibt es beim Reset-Fenster", {
  # Der neue Parameter ist optional: Wer ihn nicht setzt (alle bisherigen
  # Aufrufer, alle bisherigen Tests), bekommt das bisherige Verhalten.
  env <- lade_takt()

  mit <- env$naechste_waittime(
    remaining = 300, limit = 7500,
    seconds_until_reset = 8 * 3600,
    fenster_sekunden_bis_reset = 8 * 3600,
    loops_remaining = 200,
    expected_cost_per_loop = 6,
    current_waittime = 120, ideal_waittime = 120
  )
  ohne <- env$naechste_waittime(
    remaining = 300, limit = 7500,
    seconds_until_reset = 8 * 3600,
    loops_remaining = 200,
    expected_cost_per_loop = 6,
    current_waittime = 120, ideal_waittime = 120
  )

  expect_equal(mit$waittime, ohne$waittime)
})

test_that("der Fenster-Horizont deckelt nicht laenger an loops_remaining", {
  # Die Rundenzahl war bis Issue #224 die zweite Grenze des Horizonts
  # ("nicht laenger strecken als der Lauf dauert"). Sobald der Loop auf
  # Normaltakt zurueckschalten kann, ist sie keine Aussage ueber das
  # Tagesende mehr -- der reduzierte Tagesplan (9 Runden) wuerde den
  # Horizont sonst auf 18 Minuten schrumpfen und die Drosselung
  # aushebeln, obwohl das Budget fuer den ganzen Tag reichen muss.
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 89, limit = 100,
    seconds_until_reset = 24 * 3600,
    fenster_sekunden_bis_reset = 12 * 3600,
    loops_remaining = 9, # der reduzierte Tagesplan aus dem Vorfall
    expected_cost_per_loop = 11,
    current_waittime = 120,
    ideal_waittime = 120
  )

  # 7 bezahlbare Runden auf 12 h Fensterzeit -> deutlich mehr als eine
  # Stunde je Runde, nicht 12 h / 9 Runden aus dem alten Deckel.
  expect_gt(ergebnis$waittime, 3600)
})

test_that("fenster_sekunden zaehlt nur Zeit innerhalb des Scheduler-Fensters", {
  # Die Nacht kann keine Runden aufnehmen: Zwischen 23:00 und 11:00 laeuft
  # der Scheduler nicht. Wer die vollen 24 h als Horizont nimmt, streckt
  # den Takt um rund Faktor zwei zu weit.
  env <- lade_takt()
  mittag <- as.POSIXct("2026-09-14 12:00:00", tz = "Europe/Berlin")

  # Von 12:00 aus 24 h voraus: heute 12:00-23:00 (11 h), morgen
  # 11:00-12:00 (1 h) -> 12 h.
  expect_equal(env$fenster_sekunden(mittag, 24 * 3600), 12 * 3600)

  # Innerhalb des Fensters bleibend: volle Dauer.
  expect_equal(env$fenster_sekunden(mittag, 2 * 3600), 2 * 3600)

  # Ueber das Fensterende hinaus: nur bis 23:00 zaehlt.
  expect_equal(env$fenster_sekunden(mittag, 13 * 3600), 11 * 3600)
})

test_that("fenster_sekunden vor Fensterbeginn zaehlt erst ab 11:00", {
  env <- lade_takt()
  frueh <- as.POSIXct("2026-09-14 08:00:00", tz = "Europe/Berlin")

  # 08:00 + 4 h = 12:00; davon liegt nur 11:00-12:00 im Fenster.
  expect_equal(env$fenster_sekunden(frueh, 4 * 3600), 1 * 3600)
})

test_that("fenster_sekunden liefert 0 fuer nichtige Dauern", {
  env <- lade_takt()
  mittag <- as.POSIXct("2026-09-14 12:00:00", tz = "Europe/Berlin")

  expect_equal(env$fenster_sekunden(mittag, 0), 0)
  expect_equal(env$fenster_sekunden(mittag, -100), 0)
  expect_equal(env$fenster_sekunden(mittag, NA_real_), 0)
})

# ---------------------------------------------------------------------------
# Reset steht unmittelbar bevor (Issue #239)
# ---------------------------------------------------------------------------
#
# Vorfall 25.09.2026, 20:33: "API 1.133/7.500 verbraucht, 6.367 verbleibend,
# Reset in 0,0 h" -- und der Regler streckte auf 90 Minuten. Ein Fenster von
# 0 s bis zum Reset heisst aber nicht "kein Fenster, also bremsen", sondern
# "das Budget wird gleich neu gefuellt": Zu rationieren gibt es nichts.

test_that("steht der Reset unmittelbar bevor, laeuft der Idealtakt (Vorfall 25.09.)", {
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 6367, limit = 7500,
    seconds_until_reset = 0,
    loops_remaining = 361 - 282,
    expected_cost_per_loop = 11,
    current_waittime = 120,
    ideal_waittime = 120,
    fenster_sekunden_bis_reset = 0
  )

  expect_equal(ergebnis$waittime, 120)
  expect_false(ergebnis$gedrosselt)
  expect_false(ergebnis$stopp)
})

test_that("ohne bezahlbare Runde bleibt es auch bei Fenster 0 bei der Drosselung", {
  # Die andere Haelfte der Bedingung: Traegt das Budget keine einzige Runde
  # mehr (hier 10 Requests Rest bei 11 je Runde, ueber der Stopp-Grenze),
  # hilft auch ein naher Reset nicht -- die Runde waere nicht bezahlt.
  env <- lade_takt()

  ergebnis <- env$naechste_waittime(
    remaining = 10, limit = 7500,
    seconds_until_reset = 0,
    loops_remaining = 50,
    expected_cost_per_loop = 11,
    current_waittime = 120,
    ideal_waittime = 120,
    fenster_sekunden_bis_reset = 0
  )

  expect_equal(ergebnis$waittime, takt_default(env, "max_waittime"))
  expect_true(ergebnis$gedrosselt)
})
