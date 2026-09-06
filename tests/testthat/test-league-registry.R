library(testthat)

# Phase 1 des Ligen-Ausbaus: eine zentrale Liga-Registry ersetzt die
# verstreuten Liga-Literale.
#
# Heute stehen "78"/"79"/"80" an 63 Stellen in RCode/ und scripts/ -- als
# Ligamengen, Namens-Maps, Teamzahl-Erwartungen, Auf-/Abstiegsregeln und
# sogar in einem Dateinamen-Regex. Jede neue Liga muesste an jeder dieser
# Stellen nachgetragen werden; wird eine vergessen, faellt das nicht auf.
#
# Die Registry ist die eine Datenquelle. Sie traegt schon jetzt ALLE ZEHN
# Ligen -- die sieben neuen als Daten, aber inaktiv (`active = FALSE`), damit
# Phase 5 sie nur noch scharfschalten muss und die Struktur bis dahin an den
# echten Anforderungen erprobt ist (Staffeln, Wechselgemeinschaften,
# schwankende Teamzahlen).
#
# Diese Phase ist ausdruecklich VERHALTENSNEUTRAL fuer die drei Altligen:
# test-league-views.R muss unveraendert gruen bleiben, ausser der einen
# Zeile, die "exakt drei Ligen" pinnt.

source_registry <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  env
}

# --- Struktur ---------------------------------------------------------------

test_that("league_registry kennt alle zehn Ligen", {
  reg <- source_registry()$league_registry()

  expect_length(reg, 10)
  expect_setequal(
    vapply(reg, function(l) l$api_id, character(1)),
    c("78", "79", "80", "82", "1034", "83", "84", "85", "86", "87")
  )
})

test_that("genau die drei Altligen sind aktiv", {
  # Phase 1 aendert kein Verhalten: Der Produktivpfad sieht weiterhin nur
  # Bundesliga, 2. Bundesliga und 3. Liga.
  reg <- source_registry()$league_registry()
  aktiv <- Filter(function(l) isTRUE(l$active), reg)

  expect_equal(
    vapply(aktiv, function(l) l$api_id, character(1)),
    c(bundesliga = "78", zweite_bundesliga = "79", dritte_liga = "80")
  )
})

test_that("jede Liga traegt die Pflichtfelder", {
  reg <- source_registry()$league_registry()
  pflicht <- c("api_id", "active", "family", "slug", "nav_label", "nav_group",
               "teams_range", "first_season")

  for (key in names(reg)) {
    fehlend <- setdiff(pflicht, names(reg[[key]]))
    expect_equal(fehlend, character(0), info = key)
  }
})

test_that("api_id und slug sind eindeutig", {
  # Beide sind Primaerschluessel: api_id gegenueber der API, slug als
  # Dateiname der erzeugten Seite. Ein Duplikat wuerde eine Liga
  # stillschweigend ueberschreiben.
  reg <- source_registry()$league_registry()

  expect_false(any(duplicated(vapply(reg, function(l) l$api_id, character(1)))))
  expect_false(any(duplicated(vapply(reg, function(l) l$slug, character(1)))))
})

test_that("teams_range ist eine plausible Spanne, keine Gleichheit", {
  # Teamzahlen schwanken je Saison -- Frauen-BL 12 bis 14, RL Nord 18 bis 22
  # (an den Spielplaenen 2019-2025 gemessen). Eine feste Zahl waere falsch.
  reg <- source_registry()$league_registry()

  for (key in names(reg)) {
    r <- reg[[key]]$teams_range
    expect_length(r, 2)
    expect_true(r[[1]] <= r[[2]], info = key)
    expect_true(r[[1]] >= 8L, info = key)
    expect_true(r[[2]] <= 30L, info = key)
  }
})

# --- Wechselgemeinschaften und Tormodell ------------------------------------

test_that("die Ligen verteilen sich auf genau zwei Wechselgemeinschaften", {
  # ADR 0004: Herren (78, 79, 80, 83-87) und Frauen (82, 1034). ELO und
  # Tormodell sind nur innerhalb einer Wechselgemeinschaft vergleichbar.
  reg <- source_registry()$league_registry()
  fam <- vapply(reg, function(l) l$family, character(1))

  expect_setequal(unique(fam), c("herren", "frauen"))
  expect_setequal(
    vapply(reg[fam == "frauen"], function(l) l$api_id, character(1)),
    c("82", "1034")
  )
})

test_that("nur die Frauen-Ligen tragen ein eigenes Tormodell", {
  # Die Herren-Ligen benutzen die Rust-Defaults; ein Wert in R waere eine
  # zweite Quelle, die auseinanderlaufen kann (ADR 0002).
  reg <- source_registry()$league_registry()

  for (key in names(reg)) {
    l <- reg[[key]]
    if (l$family == "frauen") {
      expect_equal(l$tore_slope, 0.0024058833, info = key)
      expect_equal(l$tore_intercept, 1.6527603153, info = key)
    } else {
      expect_null(l$tore_slope, info = key)
      expect_null(l$tore_intercept, info = key)
    }
  }
})

test_that("die Regionalligen tragen ihre Staffel und kein eigenes Tormodell", {
  # Sie tauschen Teams mit der 3. Liga, gehoeren also zur Wechselgemeinschaft
  # Herren -- ein staffelweiser Intercept wuerde jeden Auf- und Absteiger
  # stillschweigend umskalieren (ADR 0004).
  reg <- source_registry()$league_registry()
  rl <- Filter(function(l) l$api_id %in% c("83", "84", "85", "86", "87"), reg)

  expect_length(rl, 5)
  expect_setequal(
    vapply(rl, function(l) l$staffel, character(1)),
    c("Bayern", "Nord", "Nordost", "SuedWest", "West")
  )
  for (l in rl) {
    expect_equal(l$family, "herren")
    expect_null(l$tore_slope)
  }
})

# --- Zugriffshelfer ---------------------------------------------------------

test_that("league_ids liefert standardmaessig nur die aktiven Ligen", {
  # Der Produktivpfad fragt die Registry, nicht eine Literalliste. Solange
  # nur drei Ligen aktiv sind, muss dabei exakt die heutige Menge
  # herauskommen -- in der heutigen Reihenfolge, weil sie die
  # Fetch-Reihenfolge im Update-Loop bestimmt.
  env <- source_registry()

  expect_equal(env$league_ids(), c("78", "79", "80"))
  expect_length(env$league_ids(active_only = FALSE), 10)
})

test_that("league_by_id findet eine Liga und meldet Unbekanntes", {
  env <- source_registry()

  expect_equal(env$league_by_id("78")$nav_label, "Bundesliga")
  expect_equal(env$league_by_id(78)$nav_label, "Bundesliga") # numerisch auch
  expect_null(env$league_by_id("999"))
})

test_that("league_name liefert die Anzeigenamen der Altligen unveraendert", {
  # Ersetzt die zwei duplizierten Namens-Maps in api_service.R. Die Namen
  # sind Teil der Ausgabe (Logs, Saisonwechsel-Dialoge) und duerfen sich
  # nicht aendern.
  env <- source_registry()

  expect_equal(env$league_name("78"), "Bundesliga")
  expect_equal(env$league_name("79"), "2. Bundesliga")
  expect_equal(env$league_name("80"), "3. Liga")
})

test_that("goal_model liefert die Tormodell-Parameter je Liga", {
  # NULL fuer die Herren heisst: nichts senden, Rust-Defaults greifen.
  env <- source_registry()

  expect_null(env$goal_model("78"))
  expect_equal(env$goal_model("82")$tore_slope, 0.0024058833)
  expect_equal(env$goal_model("1034")$tore_intercept, 1.6527603153)
})

# --- league_views bleibt abgeleitet, aber formgleich -------------------------

test_that("league_views wird aus der Registry abgeleitet", {
  # Die Panel-Renderlogik bleibt unveraendert; league_views() behaelt seine
  # heutige Form (top/bottom mit filter_cols/labels/groups). Geprueft wird
  # hier nur, dass die Ableitung greift -- die Panel-Details pinnt
  # test-league-views.R.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_views.R"), local = env)
  views <- env$league_views()

  expect_named(views, c("bundesliga", "zweite_bundesliga", "dritte_liga",
                        "frauen_bundesliga", "zweite_frauen_bundesliga"))
  expect_equal(views$bundesliga$slug, "index")
  expect_equal(views$dritte_liga$teams, 20)
})

# --- Verbraucher: die Literale verschwinden, das Verhalten bleibt -----------
#
# Die meisten dieser Stellen sind heute UNGETESTET (verifiziert: kein Test
# ruft validate_league_id(), get_league_promotion_rules(), get_league_name()
# oder checkAPILimits() auf). Der Umbau ist dort risikoarm, aber ungeschuetzt
# -- diese Tests spannen das Netz vor der Aenderung.

test_that("validate_league_id akzeptiert die Altligen weiterhin", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "input_validation.R"), local = env)

  for (id in c("78", "79", "80")) {
    expect_true(env$validate_league_id(id)$valid, info = id)
  }
})

test_that("validate_league_id akzeptiert die neuen Ligen", {
  # Bisher lehnte die Whitelist c("78","79","80") jede neue Liga ab. Die
  # Registry kennt sie -- auch die noch inaktiven, denn der Saisonwechsel
  # muss sie verarbeiten koennen, bevor sie live gehen.
  env <- new.env()
  source(test_path("..", "..", "RCode", "input_validation.R"), local = env)

  for (id in c("82", "1034", "83", "87")) {
    expect_true(env$validate_league_id(id)$valid, info = id)
  }
})

test_that("validate_league_id lehnt Unbekanntes weiterhin ab", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "input_validation.R"), local = env)

  expect_false(env$validate_league_id("999")$valid)
  expect_false(env$validate_league_id("")$valid)
})

test_that("validate_team_count traegt zehn Ligen", {
  # Die alte Spanne 56-62 war 18+18+20 plus willkuerliche Toleranz. Mit zehn
  # Ligen sind es 237 Teams -- der Saisonwechsel bricht sonst hart ab
  # (season_processor.R ruft die Pruefung und stoppt bei Ablehnung).
  env <- new.env()
  source(test_path("..", "..", "RCode", "input_validation.R"), local = env)

  schreibe <- function(n) {
    f <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame(2))
    utils::write.table(
      data.frame(TeamID = seq_len(n), ShortText = paste0("T", seq_len(n)),
                 Promotion = 0, InitialELO = 1500),
      f, sep = ";", row.names = FALSE, quote = FALSE
    )
    f
  }

  # Die echte TeamList_2026 muss durchgehen.
  expect_true(env$validate_team_count(schreibe(237))$valid)
  # Die drei Altligen ebenfalls -- der Saisonwechsel laeuft je Liga.
  expect_true(env$validate_team_count(schreibe(56))$valid)
  # Offensichtlicher Unfug bleibt abgelehnt.
  expect_false(env$validate_team_count(schreibe(3))$valid)
})

test_that("get_league_name liefert die Namen aller zehn Ligen", {
  # Ersetzt zwei duplizierte Maps in api_service.R (plus eine dritte in
  # scripts/analyze_league_empirics.R).
  env <- new.env()
  source(test_path("..", "..", "RCode", "api_service.R"), local = env)

  expect_equal(env$get_league_name("78"), "Bundesliga")
  expect_equal(env$get_league_name("80"), "3. Liga")
  expect_equal(env$get_league_name("82"), "Frauen-Bundesliga")
  expect_equal(env$get_league_name("84"), "Regionalliga Nord")
})

test_that("retrieveLiveFixtures pollt die aktiven Ligen", {
  # Der Live-Poll deckt alle Ligen mit EINEM Request ab (API-Syntax
  # "78-79-80"). Die Ligamenge kam bisher aus einem Default-Argument, das
  # unabhaengig von der Fetch-Liste im Update-Loop gepflegt wurde -- zwei
  # Quellen, die auseinanderlaufen koennen.
  env <- new.env()
  source(test_path("..", "..", "RCode", "retrieveResults.R"), local = env)

  expect_equal(formals(env$retrieveLiveFixtures)$league_ids |> eval(),
               c("78", "79", "80"))
})

test_that("get_league_promotion_rules kennt die Regionalligen als Ziel", {
  # Bisher stand dort der String-Sentinel "Regional" -- keine Liga-ID. Mit
  # den nun bekannten Staffeln 83-87 wird daraus eine echte Referenz.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_processor.R"), local = env)

  liga3 <- env$get_league_promotion_rules("80")
  expect_equal(liga3$promotion_to, "79")
  expect_setequal(liga3$relegation_to, c("83", "84", "85", "86", "87"))

  # Die Altligen behalten ihre Regeln unveraendert.
  expect_equal(env$get_league_promotion_rules("78")$relegation_to, "79")
  expect_null(env$get_league_promotion_rules("78")$promotion_to)
})

test_that("validate_league_composition prueft gegen teams_range", {
  # Statt fester Erwartung +-2: eine Spanne je Liga. Frauen-BL schwankte
  # 12-14, RL Nord 18-22 (an den Spielplaenen 2019-2025 gemessen).
  #
  # Signatur ist (league_id, teams); die Funktion braucht get_league_name()
  # aus api_service.R, deshalb beide Module in dieselbe Umgebung.
  env <- new.env()
  source(test_path("..", "..", "RCode", "api_service.R"), local = env)
  source(test_path("..", "..", "RCode", "league_processor.R"), local = env)

  expect_true(env$validate_league_composition("78", rep("t", 18))$valid)
  expect_false(env$validate_league_composition("78", rep("t", 30))$valid)

  # Liga 80 hat eine Sonderregel (max. 4 Zweitvertretungen) und braucht
  # deshalb Team-Objekte statt blosser Namen.
  liga3 <- lapply(1:20, function(i) list(name = paste("T", i),
                                         is_second_team = FALSE))
  expect_true(env$validate_league_composition("80", liga3)$valid)

  # Die neuen Ligen mit ihren echten Spannen.
  expect_true(env$validate_league_composition("82", rep("t", 12))$valid)
  expect_true(env$validate_league_composition("82", rep("t", 14))$valid)
  expect_true(env$validate_league_composition("84", rep("t", 22))$valid)
})

# --- Tormodell: die Frauen-Werte erreichen beide Endpunkte ------------------

test_that("simulate_league_rust sendet das Tormodell nur, wenn es abweicht", {
  # ADR 0002: Modellkonstanten leben in Rust. Fuer die Herren-Ligen darf R
  # nichts senden -- sonst gibt es zwei Quellen. Fuer die Frauen-Ligen MUSS
  # R senden, weil Rust die Herren-Werte als Default haelt.
  env <- new.env()
  source(test_path("..", "..", "RCode", "rust_integration.R"), local = env)

  fang <- function(...) {
    captured <- NULL
    mockery::stub(env$simulate_league_rust, "POST", function(url, body, ...) {
      captured <<- jsonlite::fromJSON(body)
      stop("abbruch nach payload-erfassung")
    })
    try(env$simulate_league_rust(
      schedule = matrix(c(1, 2, NA, NA), nrow = 1),
      elo_values = c(1500, 1500), team_names = c("AAA", "BBB"), ...
    ), silent = TRUE)
    captured
  }

  ohne <- fang()
  expect_false("tore_slope" %in% names(ohne))
  expect_false("tore_intercept" %in% names(ohne))

  mit <- fang(tore_slope = 0.0024058833, tore_intercept = 1.6527603153)
  expect_equal(mit$tore_slope, 0.0024058833)
  expect_equal(mit$tore_intercept, 1.6527603153)
})

test_that("build_league_details_payload traegt das Tormodell", {
  # Beide Endpunkte zwingend gemeinsam (ADR 0004): Liefen Prognose-Heatmap
  # (/simulate) und Score-Matrix (/league-details) mit verschiedenen
  # Tormodellen, widersprächen sich die Zahlen auf derselben Seite.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_details.R"), local = env)

  details <- make_details(
    fd_row(1, 1, "2026-08-01 13:00", "FT", 101, 102, 2, 1)
  )

  ohne <- env$build_league_details_payload(details, make_test_teams())
  expect_false("tore_slope" %in% names(ohne))

  mit <- env$build_league_details_payload(
    details, make_test_teams(),
    tore_slope = 0.0024058833, tore_intercept = 1.6527603153
  )
  expect_equal(mit$tore_slope, 0.0024058833)
  expect_equal(mit$tore_intercept, 1.6527603153)
})

test_that("goal_model_args liefert die Argumente fuer beide Endpunkte", {
  # Eine Quelle fuer beide Aufrufpfade -- damit ist strukturell
  # ausgeschlossen, dass sie auseinanderlaufen.
  env <- source_registry()

  expect_equal(env$goal_model_args("78"), list())
  expect_equal(
    env$goal_model_args("82"),
    list(tore_slope = 0.0024058833, tore_intercept = 1.6527603153)
  )
})
