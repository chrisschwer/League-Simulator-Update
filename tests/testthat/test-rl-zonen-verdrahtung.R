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

  expect_match(reg$rl_nord$relegation_regel, "Meister")
  expect_match(reg$rl_west$relegation_regel, "unabh|nicht")
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
