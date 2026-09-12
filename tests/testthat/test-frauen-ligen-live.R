library(testthat)

# Phase 5a des Ligen-Ausbaus: Die beiden Frauen-Bundesligen gehen live.
#
# Die fünf Regionalligen folgen erst nach Phase 6: Ihre Absteigerzahl hängt
# davon ab, wie viele Teams aus der 3. Liga in die jeweilige Staffel fallen
# (Verbandsrecherche). Ein Abstiegs-Panel mit fester Platzspanne wäre auf der
# veröffentlichten Seite sichtbar falsch.
#
# Vier Dinge müssen sich ändern, damit eine Liga mit 14 statt 18 Teams
# überhaupt gerendert werden kann:
#
#  1. Panel-Grenzen sind heute ABSOLUTE Platzindizes. "Abstieg 17:18" auf
#     eine 14-Team-Liga angewandt bricht mit "Indizierung außerhalb der
#     Grenzen" -- verifiziert. Abstiegspanels müssen von UNTEN zählen.
#  2. Die Teamzahl schwankt je Saison (Frauen-BL 12-14): Die Grenzen können
#     nicht statisch sein, sondern folgen der tatsächlichen Spaltenzahl.
#  3. Die zweistufige Navigation, weil zehn Ligen die flache Zeile sprengen.
#  4. scripts/preview_site.R muss weiterlaufen, obwohl seine Fixture nur die
#     drei Altligen kennt.
#
# Die europaeischen Plaetze stehen bewusst in league_views() und NICHT in der
# Registry -- wie schon bei der Bundesliga. Sie folgen dem UEFA-Koeffizienten
# und aendern sich unabhaengig von Auf- und Abstieg; ein Registry-Feld
# suggerierte eine Systematik, die es nicht gibt.

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

mk_ergebnis <- function(teams) {
  m <- matrix(1 / teams, nrow = teams, ncol = teams,
              dimnames = list(paste0("T", seq_len(teams)),
                              as.character(seq_len(teams))))
  as.table(m)
}

# --- 1. Panel-Grenzen relativ zur Teamzahl ----------------------------------

test_that("negative Panel-Grenzen zaehlen von unten", {
  # -1 ist der letzte Platz, -2 der vorletzte. Damit beschreibt ein
  # Abstiegspanel "die letzten beiden" unabhaengig von der Ligagroesse.
  gen <- source_generator()

  expect_equal(gen$.resolve_bounds(cbind(c(-2, -1)), n = 14), cbind(c(13, 14)))
  expect_equal(gen$.resolve_bounds(cbind(c(-2, -1)), n = 18), cbind(c(17, 18)))
  # Positive Grenzen bleiben, was sie sind.
  expect_equal(gen$.resolve_bounds(cbind(c(1, 1), c(2, 4)), n = 18),
               cbind(c(1, 1), c(2, 4)))
})

test_that("gemischte Grenzen werden korrekt aufgeloest", {
  gen <- source_generator()

  expect_equal(gen$.resolve_bounds(cbind(c(-3, -1)), n = 14), cbind(c(12, 14)))
})

test_that("render_panel_table rechnet mit den richtigen Spalten", {
  # ACHTUNG, subtile Falle: R liest negative Indizes als AUSSCHLUSS.
  # `data[, c(-2,-1)]` liefert alle Spalten AUSSER den ersten beiden -- das
  # Panel rendert dann klaglos, zeigt aber die Summe der falschen Spalten.
  # Bei Gleichverteilung ueber 14 Plaetze waeren das 86 % statt 14 %.
  #
  # Der Test prueft deshalb den WERT, nicht nur die Existenz der Tabelle.
  gen <- source_generator()
  panel <- list(source = "x", filter_cols = c(-2, -1),
                labels = "Abstieg", groups = cbind(c(-2, -1)))

  html <- gen$render_panel_table(mk_ergebnis(14), panel)

  expect_match(html, "<table class=\"panel\">")
  # Zwei von vierzehn Plaetzen, gleichverteilt: 14 %.
  expect_match(html, "<td>14</td>")
  expect_no_match(html, "<td>86</td>")
})

test_that("dieselbe Panel-Definition traegt 12 und 14 Teams", {
  # Die Frauen-Bundesliga wuchs 2025 von 12 auf 14. Eine Definition muss
  # beide Groessen ueberstehen, ohne dass jemand nachpflegt -- und in beiden
  # Faellen die letzten zwei Plaetze meinen.
  gen <- source_generator()
  panel <- list(source = "x", filter_cols = c(-2, -1),
                labels = "Abstieg", groups = cbind(c(-2, -1)))

  # 2/12 = 17 %, 2/14 = 14 %
  expect_match(gen$render_panel_table(mk_ergebnis(12), panel), "<td>17</td>")
  expect_match(gen$render_panel_table(mk_ergebnis(14), panel), "<td>14</td>")
})

test_that("die Altligen rendern unveraendert", {
  # Verhaltensneutralitaet: Absolute Grenzen bleiben erlaubt und wirken wie
  # bisher.
  gen <- source_generator()
  alt <- list(source = "x", filter_cols = 16:18, labels = c("Relegation", "Abstieg"),
              groups = cbind(c(16, 16), c(17, 18)))

  expect_match(gen$render_panel_table(mk_ergebnis(18), alt), "Relegation")
})

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

# Die folgenden Tests pruefen die GERENDERTE TABELLE, nicht die Konfiguration.
#
# Eine Zusicherung wie `expect_equal(v$bottom$groups, cbind(c(-2,-1)))` waere
# wertlos: Sie besteht, sobald die Zeichen "-2, -1" irgendwo stehen -- auch
# wenn die Aufloesung gar nicht existiert oder falsch rechnet. Sie pinnt eine
# Schreibweise, kein Verhalten.
#
# Gemessen wird deshalb an gleichverteilten Prognosen, wo jeder Platz
# 1/n traegt und die erwarteten Prozentwerte exakt bekannt sind.

test_that("die Frauen-Bundesliga zeigt Meister und CL-Qualifikation", {
  # "Der Meister erreicht direkt die Ligaphase der Champions League.
  # Vizemeister und Drittplatzierter erreichen die Qualifikation."
  # Zwei Gruppen, weil sich die Konsequenz unterscheidet.
  gen <- source_generator()
  v <- gen$league_views()$frauen_bundesliga

  expect_equal(v$slug, "frauen-bundesliga")
  expect_equal(v$top$labels, c("Meister", "Champions League Quali"))

  # Bei 14 gleichverteilten Teams: Platz 1 = 7 %, Plaetze 2-3 = 14 %.
  html <- gen$render_panel_table(mk_ergebnis(14), v$top)
  expect_match(html, "Meister")
  expect_match(html, "Champions League Quali")
  expect_match(html, "<td>7</td><td>14</td>")
})

test_that("die Frauen-Bundesliga hat zwei Abstiegsplaetze", {
  # "Die letzten zwei Teams steigen ab" -- und zwar die letzten, egal ob die
  # Liga 12 oder 14 Teams hat. 2025 ist sie gewachsen.
  gen <- source_generator()
  v <- gen$league_views()$frauen_bundesliga

  expect_equal(v$bottom$labels, "Abstieg")

  # 2/14 = 14 %, 2/12 = 17 %. Waere die Aufloesung kaputt (R liest negative
  # Indizes als Ausschluss), stuenden hier 86 % bzw. 83 %.
  expect_match(gen$render_panel_table(mk_ergebnis(14), v$bottom), "<td>14</td>")
  expect_match(gen$render_panel_table(mk_ergebnis(12), v$bottom), "<td>17</td>")
})

test_that("das Abstiegspanel trifft wirklich die letzten Plaetze", {
  # Schaerfster Test der Aufloesung: eine Prognose, in der ein Team sicher
  # Letzter wird. Nur wenn -2:-1 auf die Plaetze 13-14 zeigt, steht dort
  # 100 % -- zeigte es auf 1-12, waere es 0 %.
  gen <- source_generator()
  v <- gen$league_views()$frauen_bundesliga

  m <- matrix(0, nrow = 14, ncol = 14,
              dimnames = list(paste0("T", 1:14), as.character(1:14)))
  m[1, 14] <- 1      # T1 wird sicher Letzter
  m[2, 1] <- 1       # T2 wird sicher Meister
  for (i in 3:14) m[i, i - 1] <- 1

  html <- gen$render_panel_table(as.table(m), v$bottom)

  expect_match(html, "T1")
  expect_no_match(html, "T2")   # der Meister taucht im Abstiegspanel nicht auf
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

# --- 3. Zweistufige Navigation ----------------------------------------------

test_that("die Navigation gruppiert nach nav_group", {
  # Fuenf Ligen sprengen die flache Zeile. Gruppen: Herren, Frauen --
  # Methodik bleibt eigenstaendig.
  #
  # ANGEPASST in Phase 5: Dazu kommt die Gruppe "Regionalliga". Geprueft
  # wird hier weiterhin nur die Aussage dieser Phase -- es gibt eine Gruppe
  # "Herren" mit drei und eine Gruppe "Frauen" mit zwei Ligen.
  #
  # ANGEPASST mit Issue #178: Hier stand, Herren und Frauen seien die ersten
  # BEIDEN Gruppen. Das war eine Aussage ueber die Reihenfolge, die dieser
  # Test gar nicht treffen wollte -- seit #178 steht "Regionalliga"
  # zwischen ihnen. Geprueft wird jetzt die Zugehoerigkeit, nicht die
  # Nachbarschaft; die Reihenfolge pinnt test-phase5-regionalligen.R.
  gen <- source_generator()
  gruppen <- gen$.nav_groups()

  je_gruppe <- vapply(gruppen, function(g) g$group, character(1))
  expect_true(all(c("Herren", "Frauen") %in% je_gruppe))
  expect_length(gruppen[[which(je_gruppe == "Herren")]]$items, 3)
  expect_length(gruppen[[which(je_gruppe == "Frauen")]]$items, 2)
})

test_that("das Navigations-HTML traegt Gruppenlabels und alle Ligen", {
  gen <- source_generator()
  html <- gen$.nav_html("index")

  expect_match(html, "Herren")
  expect_match(html, "Frauen")
  expect_match(html, "frauen-bundesliga\\.html")
  expect_match(html, "methodik\\.html")
  # Die aktuelle Seite bleibt markiert.
  expect_match(html, "nav-current")
})

# --- 4. Ende-zu-Ende ---------------------------------------------------------

test_that("generate_static_site rendert sechs Seiten", {
  # Fuenf Ligen plus Methodik.
  gen <- source_generator()
  out <- withr::local_tempdir()

  paths <- gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-08-01 12:00", tz = "Europe/Berlin"),
    ergebnisse = list(
      bundesliga = mk_ergebnis(18),
      zweite_bundesliga = mk_ergebnis(18),
      dritte_liga = mk_ergebnis(20),
      dritte_liga_aufstieg = mk_ergebnis(20),
      frauen_bundesliga = mk_ergebnis(14),
      zweite_frauen_bundesliga = mk_ergebnis(14),
      zweite_frauen_bundesliga_aufstieg = mk_ergebnis(14)
    )
  )

  expect_length(paths, 6)
  for (f in c("index.html", "2-bundesliga.html", "3-liga.html",
              "frauen-bundesliga.html", "2-frauen-bundesliga.html",
              "methodik.html")) {
    expect_true(file.exists(file.path(out, f)), info = f)
  }
})

test_that("preview_site laeuft mit einer Fixture, die nur die Altligen kennt", {
  # scripts/preview_site.R laedt ShinyApp/data/Ergebnis.Rds -- dort stehen
  # nur die drei Altligen. Der Guard aus Phase 2 wuerde sonst abbrechen.
  #
  # processx::run statt system2(): Der Projektpfad enthaelt Leerzeichen
  # ("Coding Projects/"), die system2() bei unquoted args zerlegt -- und im
  # CI-Container scheitert system2() ganz ("Function not implemented").
  # processx nutzt exec() direkt und ist eine testthat-Abhaengigkeit, also
  # immer verfuegbar. Dasselbe Muster wie in
  # test-season-transition-cleanup-wrapper.R.
  project_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
  skript <- file.path(project_root, "scripts", "preview_site.R")
  fixture <- file.path(project_root, "ShinyApp", "data", "Ergebnis.Rds")
  skip_if_not(file.exists(skript))
  # Das Produktions-Image mountet nur tests/, scripts/ und die Paketliste --
  # ShinyApp/ ist dort nicht vorhanden.
  skip_if_not(file.exists(fixture), "Fixture ausserhalb des Container-Mounts")

  out <- withr::local_tempdir()
  p <- processx::run(
    "Rscript",
    args = c(skript, fixture, out),
    error_on_status = FALSE
  )

  expect_true(file.exists(file.path(out, "index.html")),
              info = paste(p$stdout, p$stderr, sep = "\n"))
})
