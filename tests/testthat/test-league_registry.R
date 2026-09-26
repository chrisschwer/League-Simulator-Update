library(testthat)
library(mockery)

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

test_that("seit Phase 5 sind alle zehn Ligen aktiv", {
  # ANGEPASST in Phase 5. Der Test hiess "genau die drei Altligen sind aktiv"
  # und wuchs seither zweimal mit -- er fuehrte die aktive Menge als zweite
  # Quelle neben der Registry, und die musste jedes Mal nachgezogen werden.
  #
  # Er prueft jetzt die Aussage, die ueber Phasen hinweg gilt: `active` und
  # league_ids() sagen dasselbe, und der Produktivpfad hat keine Liga
  # verloren. Die konkrete Liste pinnt test-phase5-regionalligen.R.
  env <- source_registry()
  reg <- env$league_registry()
  aktiv <- Filter(function(l) isTRUE(l$active), reg)

  expect_equal(unname(vapply(aktiv, function(l) l$api_id, character(1))),
               env$league_ids())
  expect_length(aktiv, length(reg))
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
  # Der Produktivpfad fragt die Registry, nicht eine Literalliste. Die
  # aktive Menge muss exakt herauskommen -- in der Registry-Reihenfolge,
  # weil sie die Fetch-Reihenfolge im Update-Loop bestimmt. Seit Phase 5
  # sind alle zehn Ligen aktiv; `active_only = FALSE` bleibt trotzdem
  # gepinnt, damit ein spaeteres Deaktivieren hier auffaellt.
  env <- source_registry()

  expect_equal(env$league_ids(),
               c("78", "79", "80", "82", "1034", "84", "85", "87", "86", "83"))
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

  expect_named(views, names(source_registry()$league_registry()))
  expect_equal(views$bundesliga$slug, "index")
  expect_equal(views$dritte_liga$teams, 20)
})

# --- Verbraucher: die Literale verschwinden, das Verhalten bleibt -----------
#
# get_league_promotion_rules() und validate_league_id() hatten ausserhalb
# ihrer eigenen Tests keinen Aufrufer (weder RCode noch scripts) und sind
# mit league_processor.R bzw. input_validation.R in #209 entfallen; ihre
# Tests sind mitgegangen. validate_team_count() lebt seit #209 in
# season_processor.R und wird dort weiter geprueft.

test_that("validate_team_count traegt zehn Ligen", {
  # Die alte Spanne 56-62 war 18+18+20 plus willkuerliche Toleranz. Mit zehn
  # Ligen sind es 237 Teams -- der Saisonwechsel bricht sonst hart ab
  # (season_processor.R ruft die Pruefung und stoppt bei Ablehnung).
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "season_validation.R"), local = env)
  source(test_path("..", "..", "RCode", "transform_data.R"), local = env)
  source(test_path("..", "..", "RCode", "csv_generation.R"), local = env)
  source(test_path("..", "..", "RCode", "season_processor.R"), local = env)

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
  # Offensichtlicher Unfug bleibt abgelehnt.
  expect_false(env$validate_team_count(schreibe(3))$valid)

  # ANGEPASST (Issue #195): Hier stand, 56 Teams muessten durchgehen, weil
  # "der Saisonwechsel je Liga laeuft". Das trifft nicht zu --
  # validate_team_count() hat genau einen Aufrufer (season_processor.R) und
  # bekommt dort immer die ZUSAMMENGEFUEHRTE Liste.
  #
  # 56 bleibt trotzdem gueltig, aber aus einem anderen Grund: Es ist die
  # Sollstaerke der drei Ligen, die der Saisonwechsel ueber
  # SEASON_TRANSITION_LEAGUES tatsaechlich abruft. Genau daran misst die
  # Untergrenze jetzt -- nicht mehr an der kleinsten einzelnen Liga (12),
  # gegen die praktisch nichts durchfiel. Die Grenzen pinnt
  # test-saisonwechsel-schutzgrenzen.R.
  expect_true(env$validate_team_count(schreibe(56))$valid)
  # Eine einzelne Liga reicht dagegen nicht mehr.
  expect_false(env$validate_team_count(schreibe(18))$valid)
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
  # "78-79-80"). Die Ligamenge kommt aus der Registry, nicht aus einer
  # zweiten Liste, die unabhaengig gepflegt wird.
  #
  # Geprueft wird der PARAMETERLOSE Aufruf -- so ruft der Produktivpfad die
  # Funktion auf (update_all_leagues_loop.R). Eine frühere Fassung dieses
  # Tests las stattdessen das Default-Argument aus. Damit blieb unbemerkt,
  # dass `league_ids = league_ids()` sich im Funktions-Scope selbst findet
  # und rekursiv aufruft: Der Scheduler stuerzte ab Loop 2 reproduzierbar ab,
  # waehrend der Test gruen blieb.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "retrieveResults.R"), local = env)

  gesehen <- NULL
  mockery::stub(env$retrieveLiveFixtures, "VERB", function(verb, url, ..., query) {
    gesehen <<- query$live
    stop("abbruch nach payload-erfassung")
  })

  try(env$retrieveLiveFixtures(), silent = TRUE)

  expect_equal(gesehen, "78-79-80-82-1034-84-85-87-86-83")
})

test_that("retrieveLiveFixtures nimmt eine explizite Ligamenge", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "retrieveResults.R"), local = env)

  gesehen <- NULL
  mockery::stub(env$retrieveLiveFixtures, "VERB", function(verb, url, ..., query) {
    gesehen <<- query$live
    stop("abbruch nach payload-erfassung")
  })

  try(env$retrieveLiveFixtures(c("78", "82")), silent = TRUE)

  expect_equal(gesehen, "78-82")
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

# --- aus test-rl-zonen-verdrahtung.R ---
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
