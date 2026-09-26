# rl_verdrahtung.R: rl_group_of_team() ordnet eine UNGEFILTERTE TeamList (wie
# update_all_leagues_loop.R sie uebergibt) den fuenf RL-Staffeln zu.
#
# Zwei Bloecke: eine Kuerzel-Kollision in einer Attrappe (FCH doppelt, in
# zwei Ligen) und dieselbe Kollision am echten Datensatz (Hansa Rostock/FCH
# in Nordost).

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

test_that("rl_group_of_team loest FCH in der echten TeamList auf Nordost auf", {
  # Der Regressionstest am echten Datensatz: Hansa Rostock ist der EINZIGE
  # Nordost-Drittligist. Faellt er aus, steht die Nordost-Zeile der
  # Auszaehlung auf P(0 Absteiger) = 1, und der Regionalliga Nordost fehlt
  # die Abstiegszone auf Platz 17.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  source(test_path("..", "..", "RCode", "rl_verdrahtung.R"), local = env)

  tl <- read.csv2(test_path("..", "..", "RCode", "TeamList_2026.csv"),
                  stringsAsFactors = FALSE)
  liga3 <- tl[tl$League == 80, ]

  spielplan <- as.data.frame(c(
    list(heim = 1L, gast = 2L, th = NA_integer_, ta = NA_integer_),
    stats::setNames(as.list(rep(0, nrow(liga3))), liga3$ShortText)
  ), check.names = FALSE)

  # Ungefiltert uebergeben -- genau wie der Loop es tut.
  idx <- env$rl_group_of_team(spielplan, tl, liga = "80")

  expect_false(is.null(idx))
  nordost <- env$staffel_index("Nordost")
  expect_equal(idx[match("FCH", liga3$ShortText)], nordost)
  # Und die Staffel darf ueberhaupt vorkommen.
  expect_true(nordost %in% idx)
})
