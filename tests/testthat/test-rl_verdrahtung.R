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

# --- rl_aktuelle_elo: gewertete Spiele bewegen die Playoff-ELO nicht (#293) --
#
# Die aktuelle ELO, mit der die Aufstiegsspiele der Regionalliga-Meister
# gerechnet werden, kommt aus POST /league-details. Ueberall sonst
# (Simulation, Ligaseite, Verlaufsseite) bewegt ein am gruenen Tisch
# gewertetes Spiel (AWD, WO) die ELO nicht; transform_data() markiert es im
# Attribut `elo_neutral` des Spielplans, zeilengleich. rl_aktuelle_elo()
# muss dieses Kennzeichen an den Endpunkt weiterreichen -- nach derselben
# Konvention wie simulate_league_rust(): senden, sobald ein Spiel gewertet
# ist; sonst das Feld weglassen, damit der Payload der Altfaelle bleibt.

# Spielplan in der Form, die transform_data() liefert: vier Spielspalten,
# ab Spalte 5 je Team die Start-ELO in Zeile 1. Zeile 2 ist das gewertete
# Spiel (3:0 fuer B), Zeile 1 regulaer gespielt, Zeile 3 offen.
rl_elo_spielplan <- function(elo_neutral = c(FALSE, TRUE, FALSE)) {
  spielplan <- data.frame(
    TeamHeim = c("A", "B", "C"),
    TeamGast = c("C", "A", "B"),
    ToreHeim = c(1, 3, NA),
    ToreGast = c(1, 0, NA),
    A = c(1600, NA, NA), B = c(1500, NA, NA), C = c(1400, NA, NA),
    stringsAsFactors = FALSE
  )
  if (!is.null(elo_neutral)) {
    attr(spielplan, "elo_neutral") <- elo_neutral
  }
  spielplan
}

# Minimale, von parse_league_details_response() lesbare Antwort.
rl_elo_antwort <- function() {
  jsonlite::toJSON(list(
    matches = list(list(index = 0L, score_matrix = list(c(1, 0), c(0, 0)))),
    current_elos = c(1600, 1500, 1400),
    team_names = c("A", "B", "C")
  ), auto_unbox = TRUE)
}

# Laedt rl_verdrahtung.R mit league_details.R und ersetzt den HTTP-Client
# durch eine Attrappe, die den Payload festhaelt.
rl_elo_env_mit_abfang <- function() {
  env <- source_module("league_details", "rl_verdrahtung")
  env$abgefangen <- NULL
  env$fetch_league_details <- function(payload, ...) {
    env$abgefangen <- payload
    rl_elo_antwort()
  }
  env
}

test_that("rl_aktuelle_elo sendet elo_neutral zeilengleich, wenn ein Spiel gewertet ist (#293)", {
  env <- rl_elo_env_mit_abfang()

  elo <- fn(env, "rl_aktuelle_elo")(rl_elo_spielplan(c(FALSE, TRUE, FALSE)))

  expect_false(is.null(elo))
  payload <- env$abgefangen
  expect_false(is.null(payload))
  # Ein Eintrag je Schedule-Zeile, true genau beim gewerteten Spiel.
  expect_identical(payload$elo_neutral, c(FALSE, TRUE, FALSE))
  expect_length(payload$schedule, 3L)
  # Die Tore des gewerteten Spiels bleiben im Schedule: Das Kennzeichen,
  # nicht das Weglassen der Tore, haelt sie aus dem ELO-Walk -- wie bei
  # /simulate.
  expect_equal(payload$schedule[[2]][3:4], list(3L, 0L))
})

test_that("rl_aktuelle_elo: auch ein WO-Spiel in der letzten Zeile wird zeilengleich gekennzeichnet (#293)", {
  env <- rl_elo_env_mit_abfang()

  fn(env, "rl_aktuelle_elo")(rl_elo_spielplan(c(FALSE, FALSE, TRUE)))

  expect_identical(env$abgefangen$elo_neutral, c(FALSE, FALSE, TRUE))
  # Im JSON an den Server steht ein Array, kein Skalar (auto_unbox!).
  json <- jsonlite::toJSON(env$abgefangen, auto_unbox = TRUE, null = "null",
                           digits = NA)
  expect_match(as.character(json), '"elo_neutral":\\[false,false,true\\]')
})

test_that("rl_aktuelle_elo laesst elo_neutral weg, wenn kein Spiel gewertet ist (#293, Gegenprobe)", {
  env <- rl_elo_env_mit_abfang()
  rl_aktuelle_elo <- fn(env, "rl_aktuelle_elo")

  # Attribut vorhanden, aber alles FALSE -- der Normalfall aus transform_data().
  rl_aktuelle_elo(rl_elo_spielplan(c(FALSE, FALSE, FALSE)))
  expect_false(is.null(env$abgefangen))
  expect_false("elo_neutral" %in% names(env$abgefangen))

  # Attribut fehlt ganz (handgebaute Spielplaene, aeltere Aufrufer).
  env$abgefangen <- NULL
  rl_aktuelle_elo(rl_elo_spielplan(NULL))
  expect_false(is.null(env$abgefangen))
  expect_false("elo_neutral" %in% names(env$abgefangen))
})

test_that("rl_aktuelle_elo: ein gewertetes Spiel laesst die aktuelle ELO stehen -- echter Rust-Server (#293)", {
  skip_if_not_installed("sys")
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")

  handle <- start_rust_server(18083L) # eigener Port neben :18080 bis :18082
  on.exit(stop_rust_server(handle), add = TRUE)
  if (!handle$ok) {
    skip(sprintf("Rust server failed to come up on port %d; log: %s",
                 handle$port, handle$log))
  }

  env <- source_module("league_details", "rl_verdrahtung")
  rl_aktuelle_elo <- fn(env, "rl_aktuelle_elo")
  basis <- Sys.getenv("RUST_API_URL")

  # Einziges Ergebnis ist das gewertete 3:0 von B gegen A; das zweite Spiel
  # ist offen. Mit elo_neutral darf sich keine ELO bewegen.
  spielplan <- data.frame(
    TeamHeim = c("B", "C"), TeamGast = c("A", "B"),
    ToreHeim = c(3, NA), ToreGast = c(0, NA),
    A = c(1600, NA), B = c(1500, NA), C = c(1400, NA),
    stringsAsFactors = FALSE
  )
  attr(spielplan, "elo_neutral") <- c(TRUE, FALSE)

  elo <- rl_aktuelle_elo(spielplan, base_url = basis)
  expect_false(is.null(elo))
  expect_equal(elo[c("A", "B", "C")], c(A = 1600, B = 1500, C = 1400),
               tolerance = 1e-9)

  # Gegenprobe, dass der Aufbau trennscharf ist: Als regulaeres Spiel
  # bewegt dasselbe 3:0 die ELO von A und B.
  attr(spielplan, "elo_neutral") <- c(FALSE, FALSE)
  elo_regulaer <- rl_aktuelle_elo(spielplan, base_url = basis)
  expect_false(is.null(elo_regulaer))
  expect_gt(elo_regulaer[["B"]], 1500)
  expect_lt(elo_regulaer[["A"]], 1600)
})
