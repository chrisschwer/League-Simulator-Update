# Per-league configuration. The leagues are asymmetric: 3. Liga's promotion
# table comes from Ergebnis3_Aufstieg while its relegation table and heatmap
# come from Ergebnis3. These assertions pin that down.

source_league_views <- function() {
  source(test_path("..", "..", "RCode", "league_views.R"), local = TRUE)
  environment()$league_views
}

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
  views <- source_league_views()()
  expect_named(views, c("bundesliga", "zweite_bundesliga", "dritte_liga",
                        "frauen_bundesliga", "zweite_frauen_bundesliga",
                        "rl_nord", "rl_nordost", "rl_west", "rl_suedwest",
                        "rl_bayern"))
})

test_that("Bundesliga is the canonical index page", {
  v <- source_league_views()()$bundesliga
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
  v <- source_league_views()()$zweite_bundesliga
  expect_equal(v$slug, "2-bundesliga")
  expect_equal(v$plot_source, "Ergebnis2")
  expect_equal(v$top$source, "Ergebnis2")
  expect_equal(v$bottom$source, "Ergebnis2")
  expect_equal(v$top$labels, c("Aufstieg", "Relegation Bundesliga"))
  expect_equal(v$top$filter_cols, 1:3)
})

test_that("3. Liga draws its top table from Ergebnis3_Aufstieg but its bottom from Ergebnis3", {
  v <- source_league_views()()$dritte_liga
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
  views <- source_league_views()()
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
