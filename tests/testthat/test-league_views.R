# Per-league configuration. The leagues are asymmetric: 3. Liga's promotion
# table comes from Ergebnis3_Aufstieg while its relegation table and heatmap
# come from Ergebnis3. These assertions pin that down.

test_that("league_views defines the live leagues in registry order", {
  # Seit Phase 5a sind die beiden Frauen-Bundesligen dabei. Die Reihenfolge
  # ist Vertrag: Sie haelt league_views() und die Registry deckungsgleich
  # (gleiche Schluessel, gleiche Slugs) und bestimmt die Fetch-Reihenfolge.
  #
  # KORRIGIERT mit Issue #178: Hier stand, sie bestimme auch "die
  # Navigation". Das galt nur faktisch, nie aus einem Grund -- die
  # Menuereihenfolge fiel als Nebenprodukt heraus. Seit #178 ist sie eigene
  # Angabe im Renderer (NAV_GRUPPEN_REIHENFOLGE in generate_static_site.R);
  # Anzeige und Abruf bewegen sich unabhaengig voneinander.
  #
  # Und die Simulation haengt nicht an der Reihenfolge: Die Abstiegskopplung
  # der Regionalligen laeuft NACH der Simulationsschleife und rechnet mit
  # einer Zaehlung der 3. Liga, die Loops ueberlebt
  # (update_all_leagues_loop.R:110-116). Eine Regionalliga darf also vor der
  # 3. Liga simuliert werden -- festgehalten in test-rl-verdrahtung.R,
  # "(a) eine neu simulierte Regionalliga mischt mit der gueltigen Zaehlung
  # aus dem frueheren Lauf".
  #
  # ANGEPASST in Phase 5: Dazu kommen die fuenf Regionalligen. Die
  # Reihenfolge folgt weiterhin der Registry -- Herren, Frauen,
  # Regionalliga; innerhalb der Regionalligen Nord, Nordost, West,
  # SuedWest, Bayern.
  views <- source_module("league_views")$league_views()
  expect_named(views, c("bundesliga", "zweite_bundesliga", "dritte_liga",
                        "frauen_bundesliga", "zweite_frauen_bundesliga",
                        "rl_nord", "rl_nordost", "rl_west", "rl_suedwest",
                        "rl_bayern"))
})

test_that("Bundesliga is the canonical index page", {
  v <- source_module("league_views")$league_views()$bundesliga
  expect_equal(v$slug, "index")
  expect_equal(v$nav_label, "Bundesliga")
  expect_equal(v$plot_source, "Ergebnis")
  expect_equal(v$teams, 18)
  expect_equal(v$top$labels,
               c("Meister", "Champions League", "Europa League",
                 "Conference League Quali"))
  expect_equal(v$top$filter_cols, 1:6)
  expect_equal(v$bottom$labels, c("Relegation", "Abstieg"))
  expect_equal(v$bottom$filter_cols, 16:18)
})

test_that("2. Bundesliga uses Ergebnis2 for every panel", {
  v <- source_module("league_views")$league_views()$zweite_bundesliga
  expect_equal(v$slug, "2-bundesliga")
  expect_equal(v$plot_source, "Ergebnis2")
  expect_equal(v$top$source, "Ergebnis2")
  expect_equal(v$bottom$source, "Ergebnis2")
  expect_equal(v$top$labels, c("Aufstieg", "Relegation Bundesliga"))
  expect_equal(v$top$filter_cols, 1:3)
})

test_that("3. Liga draws its top table from Ergebnis3_Aufstieg but its bottom from Ergebnis3", {
  v <- source_module("league_views")$league_views()$dritte_liga
  expect_equal(v$slug, "3-liga")
  expect_equal(v$teams, 20)
  expect_equal(v$plot_source, "Ergebnis3")
  expect_equal(v$top$source, "Ergebnis3_Aufstieg")
  expect_equal(v$bottom$source, "Ergebnis3")
  expect_equal(v$top$labels, c("Aufstieg", "Relegation", "DFB-Pokal"))
  expect_equal(v$top$filter_cols, 1:4)
  expect_equal(v$bottom$labels, "Abstieg")
  expect_equal(v$bottom$filter_cols, 17:20)
})

test_that("group matrices have two rows and one column per non-computed label", {
  # ANGEPASST in Phase 5 (Regionalligen live). Bis dahin hatte JEDES Panel
  # jeder Liga eine `groups`-Matrix, weil jedes Panel eine Platzgruppe war.
  #
  # Die Regionalligen brechen das bewusst: Ihre Abstiegszahl steht nicht
  # fest (sie haengt an der 3. Liga, Phase 6), und die
  # Aufstiegswahrscheinlichkeit von Nord und Bayern ist eine Doppelsumme
  # ueber zwei Staffeln (Phase 7). Beides ist keine Summe von Platzspalten
  # und traegt deshalb `computed` statt `groups`. Begruendung ausfuehrlich
  # im Kopf von test-phase5-regionalligen.R.
  #
  # Der Test prueft weiterhin dieselbe Sache -- die Gruppenmatrix passt zu
  # den Labels --, jetzt aber nur fuer die Labels, die wirklich eine
  # Platzgruppe sind. Ein Panel ganz OHNE groups muss dafuer vollstaendig
  # als berechnet ausgewiesen sein; sonst faellt es hier durch.
  views <- source_module("league_views")$league_views()
  for (nm in names(views)) {
    v <- views[[nm]]
    for (panel in c("top", "bottom")) {
      p <- v[[panel]]
      computed <- if (is.null(p$computed)) {
        rep(FALSE, length(p$labels))
      } else {
        rep_len(as.logical(p$computed), length(p$labels))
      }

      if (all(computed)) {
        # Vollstaendig berechnet: keine Platzgruppe, also auch keine
        # Gruppenmatrix -- und erst recht keine, die stillschweigend
        # ignoriert wuerde.
        expect_null(p$groups, info = paste(nm, panel))
        next
      }

      g <- p$groups
      expect_equal(nrow(g), 2, info = paste(nm, panel))
      expect_equal(ncol(g), sum(!computed), info = paste(nm, panel))
      expect_true(all(g[1, ] <= g[2, ]), info = paste(nm, panel))
    }
  }
})

# --- aus test-frauen-ligen-live.R ---
library(testthat)

# --- 2. league_views kennt die Frauen-Ligen ---------------------------------

test_that("league_views enthaelt die beiden Frauen-Ligen", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_views.R"), local = env)
  views <- env$league_views()

  expect_true("frauen_bundesliga" %in% names(views))
  expect_true("zweite_frauen_bundesliga" %in% names(views))
  # ANGEPASST in Phase 5: Hier stand `expect_length(views, 5)`. Die Zahl war
  # nie die Aussage dieses Tests -- er prueft, dass die beiden Frauen-Ligen
  # dabei sind. Die vollstaendige Liste pinnt test-league-views.R.
})

test_that("die 2. Frauen-Bundesliga hat drei Abstiegsplaetze", {
  # Laut kicker steigen die letzten drei ab; an den Spielplaenen bestaetigt
  # (je drei Absteiger 2024/25 und 2025/26).
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_views.R"), local = env)
  v <- env$league_views()$zweite_frauen_bundesliga

  expect_equal(v$top$labels, "Aufstieg")
  expect_equal(v$bottom$labels, "Abstieg")
  expect_equal(diff(as.vector(v$bottom$groups)) + 1, 3)
})

test_that("die 2. Frauen-Bundesliga zieht ihre Aufstiegstabelle aus dem Sonderlauf", {
  # Ihre Zweitvertretungen duerfen nicht aufsteigen -- dieselbe Asymmetrie
  # wie in der 3. Liga: Aufstiegstabelle aus dem Lauf mit -50-Malus,
  # Heatmap und Abstieg aus der regulaeren Prognose.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_views.R"), local = env)
  v <- env$league_views()$zweite_frauen_bundesliga

  expect_equal(v$top$source, "Ergebnis_zweite_frauen_bundesliga_aufstieg")
  expect_equal(v$plot_source, "Ergebnis_zweite_frauen_bundesliga")
  expect_equal(v$bottom$source, "Ergebnis_zweite_frauen_bundesliga")
})

test_that("die drei Altligen bleiben unveraendert", {
  # Der Kern der Verhaltensneutralitaet: test-league-views.R pinnt diese
  # Werte weiterhin, hier noch einmal als Regression gegen den Umbau.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_views.R"), local = env)
  views <- env$league_views()

  expect_equal(views$bundesliga$slug, "index")
  expect_equal(views$bundesliga$plot_source, "Ergebnis")
  expect_equal(views$bundesliga$top$filter_cols, 1:6)
  expect_equal(views$dritte_liga$top$source, "Ergebnis3_Aufstieg")
  expect_equal(views$dritte_liga$bottom$filter_cols, 17:20)
})

# --- aus test-phase5-regionalligen.R ---

# Die fuenf RL in Registry-Reihenfolge. Sie ist Vertrag (Fetch-Reihenfolge
# und Navigation), deshalb hier einmal ausgeschrieben.
RL_SCHLUESSEL <- c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest",
                   "rl_bayern")

# ===========================================================================
# 2. league_views: die fuenf neuen Ansichten
# ===========================================================================

test_that("league_views kennt zehn Ligen in Registry-Reihenfolge", {
  env <- source_module("league_views")
  views <- env$league_views()

  expect_named(
    views,
    c("bundesliga", "zweite_bundesliga", "dritte_liga",
      "frauen_bundesliga", "zweite_frauen_bundesliga", RL_SCHLUESSEL)
  )
})

test_that("die Regionalliga-Slugs und nav_labels sind die der Registry", {
  views <- source_module("league_views")$league_views()

  expect_identical(
    unname(vapply(views[RL_SCHLUESSEL], function(v) v$slug, character(1))),
    RL_SLUGS
  )
  expect_identical(
    unname(vapply(views[RL_SCHLUESSEL], function(v) v$nav_label,
                  character(1))),
    c("Nord", "Nordost", "West", "SüdWest", "Bayern")
  )
})

test_that("jede Regionalliga liest Heatmap und Panels aus eigenen Objekten", {
  # Der Generator loest ueber diese Namen auf. Zwei Ligen, die versehentlich
  # dasselbe Objekt lesen, zeigen dieselben Zahlen unter verschiedenen
  # Ueberschriften -- und nichts schlaegt fehl.
  views <- source_module("league_views")$league_views()

  plot_quellen <- vapply(views[RL_SCHLUESSEL],
                         function(v) v$plot_source, character(1))
  expect_identical(
    unname(plot_quellen),
    paste0("Ergebnis_", RL_SCHLUESSEL)
  )
  expect_identical(length(unique(plot_quellen)), 5L)
})

test_that("Nord und Bayern zeigen oben Meister UND Aufstieg getrennt", {
  # 2026/27 haben beide keinen Direktplatz (BFV A&A 2026/27 I. Nr. 1).
  # Eine einzelne Spalte "Aufstieg" ueber P(Platz 1) waere die Aussage
  # "Meister = Aufsteiger" -- und die ist fuer diese beiden falsch. Der
  # Aufstiegswert steht als EXTRA-Wert rechts neben der
  # Meisterwahrscheinlichkeit.
  views <- source_module("league_views")$league_views()

  for (key in RL_AUFSTIEGSSPIELE) {
    v <- views[[key]]
    expect_identical(v$top$labels, c("Meister", "Aufstieg"), info = key)
  }
})

test_that("bei Nord und Bayern ist nur die Aufstiegsspalte berechnet", {
  # Gemischtes Panel: Die Meisterspalte bleibt eine Platzgruppe (Platz 1),
  # die Aufstiegsspalte kommt aus der Doppelsumme. `computed` traegt
  # deshalb einen Eintrag je Label -- steht dort ein einzelnes TRUE, waere
  # auch die Meisterspalte vorberechnet und die Platzgruppe wirkungslos.
  views <- source_module("league_views")$league_views()

  for (key in RL_AUFSTIEGSSPIELE) {
    v <- views[[key]]
    expect_identical(v$top$computed, c(FALSE, TRUE), info = key)
    # Die berechnete Spalte kommt aus einem EIGENEN Objekt, nicht aus der
    # Prognosematrix -- sonst waere es wieder nur eine Platzsumme.
    expect_false(identical(v$top$computed_source, v$plot_source), info = key)
    expect_true(is.character(v$top$computed_source), info = key)
  }
})

# --- 2b. Unten: variable Abstiegsgrenzen ------------------------------------

test_that("keine Regionalliga stellt den Abstieg als feste Platzgruppe dar", {
  # DER FACHLICHE KERN, aber nicht fuer alle fuenf aus demselben Grund.
  #
  # DREI Staffeln haben eine variable Zahl von Abstiegsplaetzen, abhaengig
  # davon, wie viele Drittligisten in die Staffel fallen:
  #   Nord     3-7  (3 + k, dazu 2 statt 3 als Basis, wenn der eigene
  #                  Meister aufsteigt -- die einzige Staffel mit beiden
  #                  Kopplungen)
  #   Nordost  1-2  (1 + k, Schema bis 2)
  #   SuedWest 3-5  (3 + k, Deckel 5)
  # Eine `groups`-Matrix koennte dort nur EINE Zahl behaupten und waere
  # fuer jede andere Auszaehlung falsch, ohne dass etwas fehlschlaegt.
  #
  # WEST und BAYERN sind dagegen KONSTANT (4 bzw. 2) -- sie koppeln nicht
  # an die 3. Liga. Sie stehen aus anderen Gruenden in dieser Gruppe:
  #
  #   West:   Die Zahl ist fest, die Ligagroesse aber nicht (teams_range
  #           16-22). "Die letzten vier" liesse sich nur als NEGATIVE
  #           Grenze c(-4, -1) schreiben -- und genau dort hat dieses
  #           Projekt schon zweimal falsch gerechnet, weil R negative
  #           Indizes als AUSSCHLUSS liest. Die berechnete Spalte loest
  #           die Plaetze gegen die tatsaechliche Teamzahl auf.
  #   Bayern: weist unten ZWEI Groessen aus (Relegation und Abstieg), von
  #           denen die Relegation bewusst nicht aufgeloest wird --
  #           ebenfalls keine reine Platzsumme.
  #
  # Hier stand zuvor "vier der fuenf ... (3-5 / 1-2 / 3-7 / 4-0)". Das
  # "4-0" beschrieb die gegenlaeufige West-Kopplung, die in babc828
  # verworfen wurde.
  views <- source_module("league_views")$league_views()

  for (key in RL_SCHLUESSEL) {
    v <- views[[key]]
    expect_true(isTRUE(v$bottom$computed), info = key)
    expect_null(v$bottom$groups, info = key)
    expect_null(v$bottom$filter_cols, info = key)
  }
})

test_that("die Altligen und Frauen-Ligen behalten ihre Platzgruppen", {
  # Gegenprobe: `computed` ist eine Ausnahme fuer die RL, keine stille
  # Verhaltensaenderung der uebrigen fuenf Ligen.
  views <- source_module("league_views")$league_views()
  alt <- c("bundesliga", "zweite_bundesliga", "dritte_liga",
           "frauen_bundesliga", "zweite_frauen_bundesliga")

  for (key in alt) {
    v <- views[[key]]
    for (panel in c("top", "bottom")) {
      expect_false(isTRUE(v[[panel]]$computed),
                   info = paste(key, panel))
      expect_false(is.null(v[[panel]]$groups), info = paste(key, panel))
    }
  }
})

test_that("vier Staffeln weisen unten nur den Abstieg aus", {
  views <- source_module("league_views")$league_views()

  for (key in setdiff(RL_SCHLUESSEL, "rl_bayern")) {
    expect_identical(views[[key]]$bottom$labels, "Abstieg", info = key)
  }
})

test_that("Bayern weist unten zwei getrennte Baender aus", {
  # "Fuer die Regionalliga Bayern gibt es nach unten nur die
  # Wahrscheinlichkeiten fuer Relegation und direkten Abstieg."
  # (Entscheidung Christoph, 2026-09-06, Modellannahmen 3.)
  #
  # Die Relegation wird NICHT in eine Abstiegswahrscheinlichkeit
  # aufgeloest: Wir simulieren die Bayernligen nicht, jede Gewinnquote
  # waere erfunden. Deshalb zwei Spalten, nicht eine Summe.
  views <- source_module("league_views")$league_views()
  v <- views$rl_bayern

  expect_identical(v$bottom$labels, c("Relegation", "Abstieg"))
})

# --- Die vier Spalten -------------------------------------------------------

test_that("die Aufstiegstabelle traegt genau vier Spalten", {
  # Team, P(Meister), P(Aufstieg), Siegquote. Nicht mehr -- die
  # Paarungsmatrix ist bewusst nicht Teil dieser Seite.
  views <- source_module("league_views")$league_views()
  v <- views[[AUFSTIEGSSEITE_SLUG]]

  expect_identical(v$columns, c("Meister", "Aufstieg", "Siegquote"))
})

test_that("die Aufstiegsseite deckt alle fuenf Staffeln ab", {
  # Auch die drei Direktaufsteiger stehen dort -- die Seite zeigt den
  # ganzen Weg in die 3. Liga, nicht nur die Aufstiegsspiele.
  views <- source_module("league_views")$league_views()
  v <- views[[AUFSTIEGSSEITE_SLUG]]

  expect_identical(v$staffeln, c("Nord", "Nordost", "West", "SuedWest",
                                 "Bayern"))
})
