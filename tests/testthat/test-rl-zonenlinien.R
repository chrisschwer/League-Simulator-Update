# Issue #185: Auf-/Abstiegszonen als farbige Linie an der Ligatabelle der
# fuenf Regionalligen.
#
# Der Wunsch (Leserfeedback 08.09.2026, praezisiert von Christoph):
# sichtbar machen, welcher Platz sicher absteigt, welcher nur vielleicht --
# und mit welcher Wahrscheinlichkeit. Bei drei der fuenf Staffeln haengt die
# Zahl der Absteiger an der 3. Liga; derselbe Tabellenplatz kann dort je
# nach deren Ausgang Abstiegsplatz sein oder nicht.
#
# WARUM DIE TABELLE UND NICHT DIE HEATMAP: Die Heatmap faerbt jede Zelle
# bereits nach der Wahrscheinlichkeit (.heat_style, weiss -> Tinte). Ein
# zweiter Farbverlauf im selben Kanal waere mehrdeutig -- eine dunkle Zelle
# hiesse dann entweder "wahrscheinlich" oder "sicherer Abstiegsplatz". Die
# Ligatabelle faerbt heute nichts; dort ist der Kanal frei.
#
# DREI FARBEN:
#   rot   P(Platz ist Abstiegsplatz), abgestuft
#   gelb  Relegationsplatz -- nur Bayern, und NICHT mit Rot verrechnet
#   gruen Aufstiegsplatz; bei Nordost/West/SuedWest fest (ein Aufsteiger),
#         bei Nord und Bayern abgestuft, weil sie nur ueber das
#         Aufstiegsspiel hochkommen
#
# MINDESTDECKKRAFT: Jedes P > 0 bekommt eine sichtbare Linie. Ohne
# Untergrenze verschwaende "unwahrscheinlich, aber moeglich" optisch in
# "ausgeschlossen" -- und genau diese Unterscheidung ist der Zweck.

library(testthat)

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

# Achtzehn Plaetze, damit die Zonen realistisch liegen.
mk_rl_tabelle <- function(n = 18L) {
  data.frame(
    platz = seq_len(n),
    team_id = 100L + seq_len(n),
    name = paste("Verein", seq_len(n)),
    spiele = rep(10L, n),
    tore = rep(15L, n),
    gegentore = rep(12L, n),
    tordifferenz = rep(3L, n),
    punkte = rev(seq_len(n)),
    elo = 1500 + rev(seq_len(n)),
    delta_elo = rep(0, n),
    stringsAsFactors = FALSE
  )
}

# Die Zonen, wie sie der Renderer bekommt: je ein Vektor ueber die Plaetze.
mk_zonen <- function(n = 18L, abstieg = NULL, relegation = NULL,
                     aufstieg = NULL) {
  leer <- numeric(n)
  list(
    abstieg = if (is.null(abstieg)) leer else abstieg,
    relegation = relegation,
    aufstieg = if (is.null(aufstieg)) leer else aufstieg
  )
}

# Die Zeile eines Platzes aus dem gerenderten HTML.
zeile_von <- function(html, platz) {
  zeilen <- regmatches(html, gregexpr("<tr[^>]*>.*?</tr>", html))[[1]]
  treffer <- zeilen[grepl(paste0('data-platz="', platz, '"'), zeilen, fixed = TRUE)]
  expect_length(treffer, 1L)
  treffer
}

# Die Deckkraft der Zonenlinie einer Zeile, oder NA wenn keine da ist.
deckkraft_von <- function(zeile) {
  m <- regmatches(zeile, regexpr("--zone-p:\\s*([0-9.]+)", zeile))
  if (length(m) == 0) return(NA_real_)
  as.numeric(sub("--zone-p:\\s*", "", m))
}

zone_von <- function(zeile) {
  m <- regmatches(zeile, regexpr('data-zone="[a-z]+"', zeile))
  if (length(m) == 0) return(NA_character_)
  sub('data-zone="([a-z]+)"', "\\1", m)
}

# ---------------------------------------------------------------------------

test_that("ohne Zonen rendert die Tabelle exakt wie bisher", {
  # Die fuenf Nicht-RL-Ligen rufen den Renderer weiterhin ohne Zonen auf.
  # Sie duerfen sich um kein Zeichen aendern -- sonst waere dieses Feature
  # ein Umbau aller zehn Seiten statt einer Ergaenzung von fuenfen.
  gen <- source_generator()

  expect_identical(
    gen$render_liga_tabelle(mk_rl_tabelle()),
    gen$render_liga_tabelle(mk_rl_tabelle(), zonen = NULL)
  )
  expect_false(grepl("data-zone", gen$render_liga_tabelle(mk_rl_tabelle()),
                     fixed = TRUE))
})

test_that("die Abstiegslinie folgt P -- voll, abgestuft, gar nicht", {
  gen <- source_generator()
  abstieg <- numeric(18)
  abstieg[18] <- 1.00 # sicher
  abstieg[17] <- 0.80 # sehr wahrscheinlich
  abstieg[16] <- 0.35 # moeglich
  # 15 bleibt 0 -- ausgeschlossen

  html <- gen$render_liga_tabelle(mk_rl_tabelle(),
                                  zonen = mk_zonen(abstieg = abstieg))

  expect_equal(deckkraft_von(zeile_von(html, 18)), 1.00, tolerance = 1e-9)
  expect_equal(deckkraft_von(zeile_von(html, 17)), 0.80, tolerance = 1e-9)
  expect_equal(deckkraft_von(zeile_von(html, 16)), 0.35, tolerance = 1e-9)

  expect_identical(zone_von(zeile_von(html, 18)), "abstieg")
  expect_identical(zone_von(zeile_von(html, 16)), "abstieg")

  # Platz 15: keine Zone, keine Linie.
  expect_true(is.na(zone_von(zeile_von(html, 15))))
})

test_that("jedes P groesser null bleibt sichtbar (Mindestdeckkraft)", {
  # Der Kern des Wunsches: "kann noch passieren" darf nicht wie
  # "ausgeschlossen" aussehen. Ein Prozent ist optisch nichts -- deshalb
  # eine Untergrenze, unterhalb derer nicht weiter abgeblendet wird.
  gen <- source_generator()
  abstieg <- numeric(18)
  abstieg[17] <- 0.01
  abstieg[18] <- 1

  html <- gen$render_liga_tabelle(mk_rl_tabelle(),
                                  zonen = mk_zonen(abstieg = abstieg))

  # --zone-p traegt die Wahrscheinlichkeit selbst; die Zeile existiert also
  # und traegt ihren echten Wert.
  p17 <- deckkraft_von(zeile_von(html, 17))
  expect_false(is.na(p17))
  expect_equal(p17, 0.01, tolerance = 1e-9)
  # Und die Abstufung bleibt: sicher ist kraeftiger als moeglich.
  expect_lt(p17, deckkraft_von(zeile_von(html, 18)))

  # Die Untergrenze selbst ist eine Frage der DARSTELLUNG und steht deshalb
  # im Stylesheet, nicht im Renderer: --zone-p bleibt die Wahrscheinlichkeit
  # und bleibt mit der Fussnote vergleichbar. Geprueft wird, dass das
  # Stylesheet sie anwendet -- sonst waere die Zusicherung nirgends.
  css <- paste(readLines(
    test_path("..", "..", "RCode", "site_assets", "site.css"), warn = FALSE
  ), collapse = "\n")
  expect_match(css, "--zone-p", fixed = TRUE)
  expect_match(css, "max(", fixed = TRUE)
})

test_that("Bayern faerbt Relegation gelb und Abstieg rot, ohne sie zu verrechnen", {
  # Punkt 3 aus Issue #185: Die zwei Groessen duerfen nicht zu einer Zahl
  # addiert werden. Die Relegation gegen die Bayernliga wird bewusst nicht
  # aufgeloest -- wir simulieren diese Ligen nicht.
  gen <- source_generator()
  n <- 19L
  abstieg <- numeric(n); abstieg[c(18, 19)] <- 1
  relegation <- numeric(n); relegation[c(16, 17)] <- 1

  html <- gen$render_liga_tabelle(
    mk_rl_tabelle(n),
    zonen = mk_zonen(n, abstieg = abstieg, relegation = relegation)
  )

  expect_identical(zone_von(zeile_von(html, 19)), "abstieg")
  expect_identical(zone_von(zeile_von(html, 17)), "relegation")
  expect_identical(zone_von(zeile_von(html, 16)), "relegation")
  expect_true(is.na(zone_von(zeile_von(html, 15))))
})

test_that("der Aufstiegsplatz ist gruen -- fest oder abgestuft", {
  # Nordost, West, SuedWest stellen je einen direkten Aufsteiger: Platz 1
  # ist sicher. Nord und Bayern kommen nur ueber das Aufstiegsspiel hoch;
  # dort traegt Platz 1 die Gewinnwahrscheinlichkeit.
  gen <- source_generator()

  fest <- numeric(18); fest[1] <- 1
  html_fest <- gen$render_liga_tabelle(mk_rl_tabelle(),
                                       zonen = mk_zonen(aufstieg = fest))
  expect_identical(zone_von(zeile_von(html_fest, 1)), "aufstieg")
  expect_equal(deckkraft_von(zeile_von(html_fest, 1)), 1, tolerance = 1e-9)

  spiel <- numeric(18); spiel[1] <- 0.5
  html_spiel <- gen$render_liga_tabelle(mk_rl_tabelle(),
                                        zonen = mk_zonen(aufstieg = spiel))
  expect_identical(zone_von(zeile_von(html_spiel, 1)), "aufstieg")
  expect_equal(deckkraft_von(zeile_von(html_spiel, 1)), 0.5, tolerance = 1e-9)
})

test_that("die Linien sind an den Tabellenplatz gebunden, nicht an die Zeile", {
  # ENTSCHEIDEND (Entscheidung Christoph): Die Tabelle ist client-seitig
  # sortierbar. Die Zonen gehoeren zum PLATZ, nicht zum Team -- nach ELO
  # sortiert stuende sonst neben dem ELO-Schlechtesten ein rotes "steigt
  # sicher ab", obwohl er tabellarisch Achter ist. Das waere nicht nur
  # missverstaendlich, sondern schlicht falsch.
  #
  # Deshalb traegt die Tabelle einen Zustand, den nur die Platz-Sortierung
  # setzt; jede andere Sortierung blendet die Linien aus. Das ist zugleich
  # robust gegen kuenftige Sortierspalten: Sie sind dann automatisch aus,
  # statt still falsch zu liegen.
  gen <- source_generator()
  abstieg <- numeric(18); abstieg[18] <- 1

  html <- gen$render_liga_tabelle(mk_rl_tabelle(),
                                  zonen = mk_zonen(abstieg = abstieg))

  # Im Ausgangszustand (nach Platz) sind die Linien an.
  expect_match(html, 'data-zonen="platz"', fixed = TRUE)

  # Und das Sortierskript pflegt diesen Zustand, statt ihn zu ignorieren.
  expect_match(gen$.LIGA_SORT_SCRIPT, "data-zonen", fixed = TRUE)
  expect_match(gen$.LIGA_SORT_SCRIPT, "platz", fixed = TRUE)
})

test_that("das Kleingedruckte nennt die Regel und die Zahlen je Platz", {
  # Fuer die Nerds, die es genau wissen wollen -- unter der Tabelle, nicht
  # in ihr. Die Regel erklaert, WARUM die Zahl schwankt; ohne sie wirken
  # abgestufte Linien wie Messfehler.
  gen <- source_generator()
  abstieg <- numeric(18)
  abstieg[18] <- 1
  abstieg[17] <- 0.89

  html <- gen$render_zonen_fussnote(
    zonen = mk_zonen(abstieg = abstieg),
    regel = "Ein Regelabsteiger, je Drittliga-Absteiger einer mehr."
  )

  expect_match(html, "Regelabsteiger", fixed = TRUE)
  # Die Plaetze mit ihrer Wahrscheinlichkeit, in deutscher Schreibweise.
  expect_match(html, "17", fixed = TRUE)
  expect_match(html, "89", fixed = TRUE)
  # Plaetze ohne Abstiegsrisiko stehen nicht in der Liste -- sonst waeren
  # es 18 Eintraege, von denen 16 "0 %" sagen.
  expect_false(grepl("Platz 10", html, fixed = TRUE))
})
