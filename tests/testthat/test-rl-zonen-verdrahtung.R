# Verdrahtung der Auf-/Abstiegszonen (Issue #185, zweite Haelfte).
#
# PR #191 hat die Bausteine gebaut: rl_abstiegsprognose() reicht den
# Platzvektor als Attribut durch, render_liga_tabelle() nimmt ein
# zonen-Argument, render_zonen_fussnote() setzt das Kleingedruckte. Auf der
# Seite war davon nichts zu sehen -- niemand hat die Teile verbunden.
#
# Hier steht das fehlende Glied: rl_zonen() liest die Ergebnisobjekte des
# laufenden Zyklus und baut daraus das zonen-Objekt.
#
# DREI QUELLEN, nicht eine:
#   rot    attr(Ergebnis_<key>_abstieg, "platz_abstieg")
#   gelb   attr(Ergebnis_<key>_abstieg, "platz_relegation") -- nur Bayern
#   gruen  je nach Staffel verschieden (s. u.)
#
# Gruen ist der unangenehme Fall: Nordost, West und SuedWest stellen je
# einen DIREKTEN Aufsteiger (promotion_slots = 1), dort ist Platz 1 sicher.
# Nord und Bayern haben promotion_slots = 0 und kommen nur ueber das
# Aufstiegsspiel hoch (playoff_slots = 1) -- dort traegt Platz 1 die
# Gewinnwahrscheinlichkeit aus Ergebnis_<key>_aufstieg.

library(testthat)

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

# Ein Abstiegsergebnis, wie rl_abstiegsprognose() es liefert: data.frame je
# Team, Platzvektoren als Attribute.
mk_abstieg <- function(teams = 18L, platz_abstieg = NULL,
                       platz_relegation = NULL) {
  df <- data.frame(Abstieg = rep(0, teams),
                   row.names = paste0("T", seq_len(teams)))
  attr(df, "platz_abstieg") <- if (is.null(platz_abstieg)) {
    numeric(teams)
  } else {
    platz_abstieg
  }
  if (!is.null(platz_relegation)) {
    attr(df, "platz_relegation") <- platz_relegation
  }
  df
}

# Eine Aufstiegsspalte, wie rl_aufstiegsprognose() sie liefert.
mk_aufstieg <- function(teams = 18L, p = 0) {
  werte <- numeric(teams)
  werte[1] <- p
  data.frame(Aufstieg = werte, row.names = paste0("T", seq_len(teams)))
}

mk_rl_seiten_tabelle <- function(n = 18L) {
  data.frame(
    platz = seq_len(n), team_id = 100L + seq_len(n),
    name = paste("Verein", seq_len(n)), spiele = rep(10L, n),
    tore = rep(15L, n), gegentore = rep(12L, n), tordifferenz = rep(3L, n),
    punkte = rev(seq_len(n)), elo = 1500 + rev(seq_len(n)),
    delta_elo = rep(0, n), stringsAsFactors = FALSE
  )
}

mk_env <- function(...) {
  env <- new.env()
  for (nm in names(list(...))) assign(nm, list(...)[[nm]], envir = env)
  env
}

# ---------------------------------------------------------------------------

test_that("rl_zonen liefert NULL fuer Ligen ohne Zonen", {
  # Die fuenf Nicht-RL-Ligen rufen denselben Seitenaufbau. Sie duerfen kein
  # halbes zonen-Objekt bekommen, sondern gar keines -- dann rendert die
  # Tabelle zeichengleich wie vor #185.
  gen <- source_generator()

  expect_null(gen$rl_zonen("bundesliga", mk_env()))
  expect_null(gen$rl_zonen("frauen_bundesliga", mk_env()))
})

test_that("rl_zonen liest die Abstiegsgewichte aus dem Attribut", {
  gen <- source_generator()
  ab <- numeric(18); ab[18] <- 1; ab[17] <- 0.89; ab[16] <- 0.35

  zonen <- gen$rl_zonen("rl_nordost", mk_env(
    Ergebnis_rl_nordost_abstieg = mk_abstieg(18L, platz_abstieg = ab)
  ))

  expect_equal(zonen$abstieg, ab, tolerance = 1e-12)
})

test_that("Nordost, West und SuedWest bekommen Platz 1 als sicheren Aufstieg", {
  # promotion_slots = 1: ein direkter Aufsteiger, keine Wahrscheinlichkeit
  # im Spiel. Die Zahl kommt aus der Registry, nicht aus einer Simulation.
  gen <- source_generator()

  for (key in c("rl_nordost", "rl_west", "rl_suedwest")) {
    objekt <- paste0("Ergebnis_", key, "_abstieg")
    env <- new.env()
    assign(objekt, mk_abstieg(18L), envir = env)

    zonen <- gen$rl_zonen(key, env)
    expect_equal(zonen$aufstieg[1], 1, tolerance = 1e-12, info = key)
    expect_true(all(zonen$aufstieg[-1] == 0), info = key)
  }
})

test_that("Nord und Bayern tragen die Gewinnquote des Aufstiegsspiels", {
  # promotion_slots = 0, playoff_slots = 1: Sie kommen nur ueber das
  # Aufstiegsspiel hoch. Platz 1 ist dort KEIN sicherer Aufstieg -- genau
  # das soll die abgestufte Linie zeigen.
  gen <- source_generator()

  zonen <- gen$rl_zonen("rl_nord", mk_env(
    Ergebnis_rl_nord_abstieg = mk_abstieg(18L),
    Ergebnis_rl_nord_aufstieg = mk_aufstieg(18L, p = 0.42)
  ))
  expect_equal(zonen$aufstieg[1], 0.42, tolerance = 1e-12)

  zonen_by <- gen$rl_zonen("rl_bayern", mk_env(
    Ergebnis_rl_bayern_abstieg = mk_abstieg(19L),
    Ergebnis_rl_bayern_aufstieg = mk_aufstieg(19L, p = 0.58)
  ))
  expect_equal(zonen_by$aufstieg[1], 0.58, tolerance = 1e-12)
})

test_that("nur Bayern traegt Relegationsgewichte", {
  # Die anderen vier Staffeln kennen keine Abstiegsrelegation. NULL heisst
  # "gibt es nicht" -- ein Nullvektor hiesse "moeglich, gerade null".
  gen <- source_generator()
  rel <- numeric(19); rel[c(16, 17)] <- 1

  zonen_by <- gen$rl_zonen("rl_bayern", mk_env(
    Ergebnis_rl_bayern_abstieg = mk_abstieg(19L, platz_relegation = rel),
    Ergebnis_rl_bayern_aufstieg = mk_aufstieg(19L, p = 0.5)
  ))
  expect_equal(zonen_by$relegation, rel, tolerance = 1e-12)

  zonen_no <- gen$rl_zonen("rl_nordost", mk_env(
    Ergebnis_rl_nordost_abstieg = mk_abstieg(18L)
  ))
  expect_null(zonen_no$relegation)
})

test_that("fehlt das Abstiegsobjekt, gibt es gar keine Zonen", {
  # Der Loop ueberspringt die RL-Spalten, wenn Voraussetzungen fehlen (etwa
  # ohne Zaehlung der 3. Liga) -- dokumentiertes Verhalten. Dann darf die
  # Seite keine halben Zonen zeigen: Eine Liga ohne Linien ist besser als
  # eine mit Linien, die nur die halbe Wahrheit tragen.
  gen <- source_generator()

  expect_null(gen$rl_zonen("rl_nordost", mk_env()))
})

test_that("fehlt bei Nord die Aufstiegsspalte, bleiben die Abstiegslinien", {
  # Gegenprobe zum Test darueber: Das Abstiegsobjekt ist die tragende
  # Quelle. Fehlt nur die Aufstiegsspalte, waere es falsch, deswegen auch
  # die Abstiegslinien wegzulassen -- sie sind vollstaendig da.
  gen <- source_generator()
  ab <- numeric(18); ab[18] <- 1

  zonen <- gen$rl_zonen("rl_nord", mk_env(
    Ergebnis_rl_nord_abstieg = mk_abstieg(18L, platz_abstieg = ab)
  ))

  expect_equal(zonen$abstieg, ab, tolerance = 1e-12)
  expect_true(all(zonen$aufstieg == 0))
})

# --- Der Regeltext ---------------------------------------------------------

test_that("jede Regionalliga traegt einen Regeltext in der Registry", {
  # Die Fussnote erklaert, WARUM die Zahl schwankt. Der Text stand bisher
  # nur als Kommentar in der Registry und war damit nicht auslesbar.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  reg <- env$league_registry()

  for (key in c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest", "rl_bayern")) {
    regel <- reg[[key]]$relegation_regel
    expect_true(is.character(regel) && nzchar(regel), info = key)
  }
})

test_that("Nord und West nennen ihre Besonderheit im Regeltext", {
  # Zwei Faelle, die ohne Hinweis wie ein Fehler aussehen:
  #
  # Nord  -- steigt der Meister auf, hat Nord einen Abstiegsplatz weniger.
  #          Gruen und Rot haengen dort zusammen; ohne Erklaerung wirken
  #          die Zahlen inkonsistent.
  # West  -- koppelt als einzige Staffel NICHT an die 3. Liga. Alle Linien
  #          sind voll deckend, die Abstufung laeuft leer. Korrekt, sieht
  #          aber neben den anderen vier Staffeln nach Defekt aus.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  reg <- env$league_registry()

  # Nord nennt den Mechanismus, nicht das Wort "Meister": Christoph hat die
  # laengere Fassung "Gewinnt Nord das Aufstiegsspiel" bewusst behalten,
  # weil sie erklaert, WIE der Abstiegsplatz wegfaellt.
  expect_match(reg$rl_nord$relegation_regel, "Aufstiegsspiel")
  expect_match(reg$rl_west$relegation_regel, "ändert die 3. Liga diese Zahl nicht",
               fixed = TRUE)
})

test_that("die Nicht-RL-Ligen tragen keinen Regeltext", {
  # Sie haben feste Abstiegsplaetze und brauchen keine Erklaerung. Ein Text
  # dort waere ein Versprechen auf eine Fussnote, die nicht kommt.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  reg <- env$league_registry()

  for (key in c("bundesliga", "zweite_bundesliga", "dritte_liga",
                "frauen_bundesliga", "zweite_frauen_bundesliga")) {
    expect_null(reg[[key]]$relegation_regel, info = key)
  }
})

# --- Die Zahl der Absteiger ------------------------------------------------
#
# Die Linien sagen, welcher PLATZ betroffen ist. Die Fussnote soll davor
# sagen, WIE VIELE Vereine ueberhaupt absteigen -- bei Nord, Nordost und
# SuedWest steht das nicht fest, sondern haengt an der 3. Liga.
#
# Diese Verteilung muss NICHT neu gerechnet und auch nicht durch den Loop
# gereicht werden: Sie steckt bereits im Platzvektor aus platz_gewichte().
# Der ist die Ueberlebensfunktion P(Platz p ist Abstiegsplatz) und faellt
# monoton von 1 auf 0; seine Differenzen sind genau P(genau j Absteiger).
#
# Das ist mehr als eine Abkuerzung: Linien und Fussnote haben damit EINE
# Quelle und koennen nicht auseinanderlaufen. Eine zweite Herleitung aus
# der Zaehlmatrix waere eine zweite Wahrheit auf derselben Seite.
#
# Nebeneffekt, der einen Sonderfall von selbst erledigt: Bei Nordost
# liefert das NOFV-Schema fuer einen und fuer zwei Drittliga-Absteiger
# DIESELBE Zahl (zwei). Ueber k gerechnet stuende "2 Absteiger" zweimal in
# der Liste; ueber die Absteigerzahl gerechnet summiert es sich richtig.

test_that("absteigerzahl_verteilung gewinnt die Verteilung aus dem Platzvektor", {
  gen <- source_generator()

  # Nord-Fall: 3 Absteiger sicher, der 4. mit 80 %, der 5. mit 30 %.
  g <- numeric(18)
  g[18] <- 1; g[17] <- 1; g[16] <- 1   # drei sichere
  g[15] <- 0.8
  g[14] <- 0.3

  v <- gen$absteigerzahl_verteilung(g)

  expect_equal(v[["3"]], 0.2, tolerance = 1e-9)  # 1 - 0.8
  expect_equal(v[["4"]], 0.5, tolerance = 1e-9)  # 0.8 - 0.3
  expect_equal(v[["5"]], 0.3, tolerance = 1e-9)
  expect_equal(sum(v), 1, tolerance = 1e-9)
})

test_that("eine feste Absteigerzahl ergibt genau einen Eintrag mit 100 Prozent", {
  # West koppelt nicht: vier Absteiger, Punkt. Die Fussnote soll das als
  # eine Zeile zeigen, nicht als Verteilung ueber einen einzigen Wert.
  gen <- source_generator()
  g <- numeric(18); g[15:18] <- 1

  v <- gen$absteigerzahl_verteilung(g)

  expect_named(v, "4")
  expect_equal(unname(v[[1]]), 1, tolerance = 1e-9)
})

test_that("Plaetze mit Wahrscheinlichkeit null tauchen nicht auf", {
  # Sonst stuenden in der Liste 14 Eintraege mit "0 %", die die drei
  # interessanten Zahlen zudecken.
  gen <- source_generator()
  g <- numeric(18); g[18] <- 1; g[17] <- 0.5

  v <- gen$absteigerzahl_verteilung(g)

  expect_setequal(names(v), c("1", "2"))
})

test_that("die Fussnote nennt die Zahl der Absteiger VOR den Platz-Zahlen", {
  # Reihenfolge ist Aussage: Erst warum die Zahl schwankt, dann was daraus
  # je Platz folgt. Andersherum stuenden die Platzzahlen unerklaert da.
  gen <- source_generator()
  ab <- numeric(18)
  ab[18] <- 1; ab[17] <- 1; ab[16] <- 0.4

  html <- gen$render_zonen_fussnote(
    zonen = list(abstieg = ab, relegation = NULL, aufstieg = numeric(18)),
    regel = "Zwei Vereine steigen ab, je Absteiger aus der 3. Liga einer mehr."
  )

  expect_match(html, "Absteiger", fixed = TRUE)
  # Die Verteilung steht vor der Platzliste.
  expect_lt(regexpr("Zahl der Absteiger", html, fixed = TRUE),
            regexpr("Platz 16", html, fixed = TRUE))
})

test_that("bei fester Absteigerzahl entfaellt der Verteilungssatz", {
  # West und Bayern haben nichts zu erklaeren -- ein Satz "4 Absteiger mit
  # 100 %" waere Fuellmaterial und saehe aus, als gaebe es eine Unsicherheit.
  gen <- source_generator()
  ab <- numeric(18); ab[15:18] <- 1

  html <- gen$render_zonen_fussnote(
    zonen = list(abstieg = ab, relegation = NULL, aufstieg = numeric(18)),
    regel = "Vier Vereine steigen ab."
  )

  expect_false(grepl("Zahl der Absteiger", html, fixed = TRUE))
  expect_match(html, "Vier Vereine steigen ab.", fixed = TRUE)
})

# --- Die fertige Seite -----------------------------------------------------

test_that("die RL-Seite traegt Zonenlinien und Fussnote", {
  # Der Endpunkt: Was #191 gebaut hat, muss auf der Seite ankommen. Ohne
  # diesen Test bliebe die Verdrahtung unbewiesen -- genau der Zustand, den
  # dieser PR beendet.
  gen <- source_generator()
  ab <- numeric(18); ab[18] <- 1; ab[17] <- 0.5

  env <- mk_env(
    Ergebnis_rl_nordost_abstieg = mk_abstieg(18L, platz_abstieg = ab)
  )
  zonen <- gen$rl_zonen("rl_nordost", env)
  html <- gen$render_liga_tabelle(mk_rl_seiten_tabelle(), zonen = zonen)

  expect_match(html, 'data-zonen="platz"', fixed = TRUE)
  expect_match(html, 'data-zone="abstieg"', fixed = TRUE)
})
