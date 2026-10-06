# rl_verdrahtung.R: rl_group_of_team() ordnet eine UNGEFILTERTE TeamList (wie
# update_all_leagues_loop.R sie uebergibt) den fuenf RL-Staffeln zu.
#
# Zwei Bloecke: eine Kuerzel-Kollision in einer Attrappe (FCH doppelt, in
# zwei Ligen) und eine Datenpruefung, dass in der aktuellen TeamList jedes
# Drittliga-Team seine eigene Staffel bekommt -- welche Kollisionen es dort
# gerade gibt, haengt von der Ligazusammensetzung ab.

library(testthat)
library(mockery)

# --- rl_group_of_team: der Produktivpfad, ungefiltert ----------------------
#
# Diese Funktion hatte keinen Test. Das ist der zweite Grund, warum die
# Kuerzel-Kollision (s. test-staffel_zuordnung.R) unbemerkt blieb: Getestet
# war nur group_of_team() -- und zwar stets mit einer schon auf eine Liga
# gefilterten TeamList. Der Loop uebergibt aber die GANZE TeamList, und
# genau dort entstand der Fehler.
#
# Die Tests fahren deshalb bewusst so auf, wie update_all_leagues_loop.R es
# tut: ungefiltert, mit der echten Kollision im Datensatz.

test_that("rl_group_of_team filtert die TeamList selbst auf die Liga", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  source(test_path("..", "..", "RCode", "rl_verdrahtung.R"), local = env)

  # Spielplan-Attrappe: vier Spielspalten, dann je Team eine ELO-Spalte.
  # Die Spaltennamen ab 5 sind die Kurznamen in Spielplan-Reihenfolge.
  spielplan <- data.frame(
    1L, 2L, NA_integer_, NA_integer_,
    FCH = 0, AAA = 0,
    check.names = FALSE
  )
  names(spielplan)[1:4] <- c("heim", "gast", "th", "ta")

  # "FCH" zweimal: Liga 79 (SuedWest) zuerst, Liga 80 (Nordost) danach --
  # so wie in TeamList_2026 (Heidenheim vor Hansa Rostock).
  teams <- data.frame(
    ShortText = c("FCH", "AAA", "FCH"),
    League    = c(79L, 80L, 80L),
    Region    = c("SuedWest", "Nord", "Nordost"),
    stringsAsFactors = FALSE
  )

  idx <- env$rl_group_of_team(spielplan, teams, liga = "80")

  # FCH muss Nordost (1) sein, nicht SuedWest (3).
  expect_equal(idx, c(1L, 0L))
})

test_that("Datenpruefung: rl_group_of_team gibt jedem Drittligisten der aktuellen TeamList seine Staffel", {
  # Der Regressionstest am echten Datensatz. Anlass war Hansa Rostock (FCH),
  # 2026 der EINZIGE Nordost-Drittligist, dessen Kuerzel auch Heidenheim in
  # Liga 79 traegt: Ungefiltert aufgeloest landete er in SuedWest, die
  # Nordost-Zeile der Auszaehlung stand auf P(0 Absteiger) = 1, und der
  # Regionalliga Nordost fehlte die Abstiegszone auf Platz 17.
  #
  # Geprueft wird deshalb nicht FCH allein, sondern JEDES Drittliga-Team mit
  # Region -- so faengt der Test auch die Kollisionen kuenftiger Saisons
  # und kippt nicht, wenn Hansa die Liga verlaesst. (Bis Oktober 2026 fest
  # auf TeamList_2026 und FCH verdrahtet, #271.)
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  source(test_path("..", "..", "RCode", "rl_verdrahtung.R"), local = env)

  tl <- read.csv2(aktuelle_teamlist_pfad(), stringsAsFactors = FALSE)
  liga3 <- tl[tl$League == 80, ]

  spielplan <- as.data.frame(c(
    list(heim = 1L, gast = 2L, th = NA_integer_, ta = NA_integer_),
    stats::setNames(as.list(rep(0, nrow(liga3))), liga3$ShortText)
  ), check.names = FALSE)

  # Ungefiltert uebergeben -- genau wie der Loop es tut.
  idx <- env$rl_group_of_team(spielplan, tl, liga = "80")

  expect_false(is.null(idx))
  mit_region <- !is.na(liga3$Region) & nzchar(liga3$Region)
  expect_equal(idx[mit_region], env$staffel_index(liga3$Region[mit_region]))
})
