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
# test-league_views.R muss unveraendert gruen bleiben, ausser der einen
# Zeile, die "exakt drei Ligen" pinnt.

# --- Struktur ---------------------------------------------------------------

test_that("league_registry kennt alle zehn Ligen", {
  reg <- source_module("league_registry")$league_registry()

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
  # verloren. Die konkrete Liste pinnt der Test "league_registry kennt alle
  # zehn Ligen" oben.
  env <- source_module("league_registry")
  reg <- env$league_registry()
  aktiv <- Filter(function(l) isTRUE(l$active), reg)

  expect_equal(unname(vapply(aktiv, function(l) l$api_id, character(1))),
               env$league_ids())
  expect_length(aktiv, length(reg))
})

test_that("jede Liga traegt die Pflichtfelder", {
  reg <- source_module("league_registry")$league_registry()
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
  reg <- source_module("league_registry")$league_registry()

  expect_false(any(duplicated(vapply(reg, function(l) l$api_id, character(1)))))
  expect_false(any(duplicated(vapply(reg, function(l) l$slug, character(1)))))
})

test_that("teams_range ist eine plausible Spanne, keine Gleichheit", {
  # Teamzahlen schwanken je Saison -- Frauen-BL 12 bis 14, RL Nord 18 bis 22
  # (an den Spielplaenen 2019-2025 gemessen). Eine feste Zahl waere falsch.
  reg <- source_module("league_registry")$league_registry()

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
  reg <- source_module("league_registry")$league_registry()
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
  reg <- source_module("league_registry")$league_registry()

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
  reg <- source_module("league_registry")$league_registry()
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
  env <- source_module("league_registry")

  expect_equal(env$league_ids(),
               c("78", "79", "80", "82", "1034", "84", "85", "87", "86", "83"))
  expect_length(env$league_ids(active_only = FALSE), 10)
})

test_that("league_by_id findet eine Liga und meldet Unbekanntes", {
  env <- source_module("league_registry")

  expect_equal(env$league_by_id("78")$nav_label, "Bundesliga")
  expect_equal(env$league_by_id(78)$nav_label, "Bundesliga") # numerisch auch
  expect_null(env$league_by_id("999"))
})

test_that("league_name liefert die Anzeigenamen der Altligen unveraendert", {
  # Ersetzt die zwei duplizierten Namens-Maps in api_service.R. Die Namen
  # sind Teil der Ausgabe (Logs, Saisonwechsel-Dialoge) und duerfen sich
  # nicht aendern.
  env <- source_module("league_registry")

  expect_equal(env$league_name("78"), "Bundesliga")
  expect_equal(env$league_name("79"), "2. Bundesliga")
  expect_equal(env$league_name("80"), "3. Liga")
})

test_that("goal_model liefert die Tormodell-Parameter je Liga", {
  # NULL fuer die Herren heisst: nichts senden, Rust-Defaults greifen.
  env <- source_module("league_registry")

  expect_null(env$goal_model("78"))
  expect_equal(env$goal_model("82")$tore_slope, 0.0024058833)
  expect_equal(env$goal_model("1034")$tore_intercept, 1.6527603153)
})

# --- league_views bleibt abgeleitet, aber formgleich -------------------------

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
  # test-season_processor.R.
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
  env <- source_module("league_registry")

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

# --- aus test-frauen-ligen-aktivierung.R ---
# Livegang der beiden Frauen-Bundesligen: Der Scheduler ruft sie ab, und das
# Zeitfenster wird auf ihre Anstosszeiten angepasst.
#
# Phase 5a hat den Renderer vorbereitet; hier wird scharfgeschaltet. Der
# Schritt ist bewusst getrennt, weil er das Betriebsverhalten aendert: mehr
# API-Requests, mehr Simulationen, ein laengerer Tag.

# --- Registry: die Frauen-Ligen sind dabei ----------------------------------

test_that("die Frauen-Ligen sind aktiv", {
  # ANGEPASST in Phase 5: Die Aussage dieses Tests ist, dass die beiden
  # Frauen-Bundesligen im Produktivpfad stehen -- nicht, wie viele Ligen es
  # insgesamt sind. Die Gesamtliste stand hier als feste Aufzaehlung und
  # wurde mit den Regionalligen falsch; sie ist ohnehin im Test
  # "league_registry kennt alle zehn Ligen" oben gepinnt.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  for (id in c("82", "1034")) {
    expect_true(id %in% env$league_ids(), info = id)
  }
  for (key in c("frauen_bundesliga", "zweite_frauen_bundesliga")) {
    expect_true(key %in% env$active_league_keys(), info = key)
  }
  # Und sie stehen hinter den Altligen, vor den Regionalligen -- die
  # Reihenfolge ist die Fetch-Reihenfolge.
  expect_equal(head(env$active_league_keys(), 5),
               c("bundesliga", "zweite_bundesliga", "dritte_liga",
                 "frauen_bundesliga", "zweite_frauen_bundesliga"))
})

# Der Test "die Regionalligen bleiben inaktiv" stand hier bis Phase 5. Er
# entfaellt ersatzlos: Seine Aussage ist genau das, was Phase 5 aufhebt --
# die fuenf Staffeln sind jetzt aktiv (Abschnitt "1. Registry: alle fuenf
# Regionalligen sind aktiv" weiter unten).

test_that("beide Frauen-Ligen tragen das Frauen-Tormodell", {
  # Ab jetzt wirksam: Der Loop sendet die Parameter an die Engine.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  for (id in c("82", "1034")) {
    gm <- env$goal_model(id)
    expect_equal(gm$tore_slope, 0.0024058833, info = id)
    expect_equal(gm$tore_intercept, 1.6527603153, info = id)
  }
  # Die Herren-Ligen senden weiterhin nichts -- Rust haelt die Defaults.
  for (id in c("78", "79", "80")) {
    expect_null(env$goal_model(id), info = id)
  }
})

# --- aus test-n-ligen-entflechtung.R ---
# Phase 2 des Ligen-Ausbaus: Update-Loop und Seitengenerator von "genau drei
# Ligen" auf "n Ligen" entflechten, gesteuert über die Liga-Registry.
#
# Diese Phase ist VERHALTENSNEUTRAL. Solange league_ids() nur die drei
# Altligen liefert, muss alles beim Alten bleiben -- insbesondere bleibt
# test-update_all_leagues_loop-gating.R (526 Zeilen, 12 Tests) unverändert grün. Diese
# Datei prüft, dass die Mechanik darüber hinaus n-fähig ist.
#
# Zwei Randbedingungen, an denen der Umbau scheitern würde:
#
#  1. mockery::stub() bindet an die Funktionsumgebung von
#     update_all_leagues_loop(). Verifiziert: Wandert ein Aufruf in eine
#     separate Top-Level-Funktion, greift der Stub NICHT mehr -- zehn Tests
#     bräche das auf einen Schlag. Der lapply-Umbau muss INLINE bleiben.
#  2. Die Aufrufe müssen weiterhin BENANNT erfolgen
#     (retrieveResults(league =, season =), generate_static_site(output_dir =,
#     league_data =)), weil die Stubs auf diese Namen hören.

# --- Registry-Helfer für die Verdrahtung ------------------------------------

test_that("die Registry liefert Schluessel in Fetch-Reihenfolge", {
  # league_data und league_views() sind über diese Schlüssel verbunden; der
  # Loop baut sie, der Generator indiziert damit. Die Reihenfolge bestimmt
  # zudem, in welcher Folge die Ligen abgerufen werden -- sie darf sich nicht
  # unbemerkt ändern (test-update_all_leagues_loop.R pinnt SENTINEL-1/2/3).
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  # ANGEPASST in Phase 5: Die Aufzaehlung wuchs mit jedem Livegang mit. Die
  # Aussage dieses Tests ist die REIHENFOLGE -- dass sie die der Registry
  # ist, nicht welche Ligen es gerade sind. Die konkrete Liste pinnt der
  # Test "league_ids liefert zehn Ligen in Registry-Reihenfolge" weiter
  # unten.
  expect_equal(env$active_league_keys(),
               names(Filter(function(l) isTRUE(l$active), env$league_registry())))
  expect_equal(env$active_league_keys(), names(env$active_leagues()))
  expect_equal(head(env$active_league_keys(), 3),
               c("bundesliga", "zweite_bundesliga", "dritte_liga"))
})

test_that("active_leagues liefert die vollstaendigen Eintraege", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  aktiv <- env$active_leagues()
  expect_length(aktiv, length(env$league_ids()))
  expect_equal(aktiv$bundesliga$api_id, "78")
  expect_equal(aktiv$dritte_liga$api_id, "80")
  expect_true(all(vapply(aktiv, function(l) isTRUE(l$active), logical(1))))
})

test_that("die Registry weiss, welche Liga einen Aufstiegslauf braucht", {
  # Der -50-Malus für Zweitvertretungen ist heute für Liga 3 hartkodiert. Er
  # hängt an einer Liga-Eigenschaft, nicht an einer ID -- und gilt künftig
  # auch für die Regionalligen, deren Zweitvertretungen ebenfalls nicht in
  # die 3. Liga aufsteigen dürfen.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  expect_true(env$has_promotion_restriction("80"))
  expect_false(env$has_promotion_restriction("78"))
  expect_false(env$has_promotion_restriction("79"))
})

# --- aus test-phase5-regionalligen.R ---
# Phase 5: Die fuenf Regionalligen gehen live.
#
# Bisher aktiv: 78, 79, 80 (Herren) und 82, 1034 (Frauen) -- fuenf Ligen,
# fuenf Seiten plus Methodik. Danach: zehn Ligen, zehn Liga-Seiten, die
# Seite "Aufstieg in die 3. Liga" und Methodik -- zwoelf Seiten -- sowie
# eine Navigation mit drei Gruppen (Herren / Frauen / Regionalliga).
#
# Diese Datei ist test-first geschrieben: Sie MUSS rot sein, solange
# `active = FALSE` in RCode/league_registry.R steht und league_views() die
# fuenf RL-Eintraege nicht kennt.
#
# ===========================================================================
# DIE ENTSCHEIDUNG, DIE PHASE 5 VERLANGT: die Abstiegsdarstellung der RL
# ===========================================================================
#
# Die Altligen und die Frauen-Ligen stellen ihr unteres Panel als
# PLATZGRUPPE dar: `bottom = list(filter_cols = ..., labels = ...,
# groups = cbind(c(17, 18)))`. render_panel_table() summiert dann die
# Spalten 17 und 18 der Prognosematrix. Das setzt voraus, dass FESTSTEHT,
# welche Plaetze Abstiegsplaetze sind.
#
# Fuer DREI der fuenf Regionalligen steht das gerade NICHT fest. Wie viele
# Teams absteigen, haengt davon ab, wie viele Drittligisten in genau diese
# Staffel fallen (Phase 6, RCode/rl_abstiegskopplung.R):
#
#   Nord      3 + k, kein Deckel -- 3 bis 7, zusaetzlich gekoppelt an den
#                                   EIGENEN Meisteraufstieg (Basis 2 statt
#                                   3). Die einzige Staffel mit BEIDEN
#                                   Kopplungen.
#   Nordost   1 + k, Deckel 2    -- 1 bis 2
#   SuedWest  3 + k, Deckel 5    -- 3 bis 5
#
# West (konstant 4) und Bayern (konstant 2) koppeln NICHT an die 3. Liga.
# Sie brauchen die berechnete Spalte aus anderen Gruenden:
#
#   West    Die Zahl ist fest, die Ligagroesse aber nicht (teams_range
#           16-22). "Die letzten vier" liesse sich als feste Gruppe nur
#           mit NEGATIVEN Grenzen schreiben -- und dort hat dieses Projekt
#           schon zweimal falsch gerechnet, weil R negative Indizes als
#           AUSSCHLUSS liest.
#   Bayern  Weist unten ZWEI Groessen aus (Relegation und Abstieg), von
#           denen die Relegation bewusst nicht aufgeloest wird.
#
# Ein `groups = cbind(c(-3, -1))` waere fuer die drei koppelnden Staffeln
# nicht nur ungenau, sondern SICHTBAR FALSCH: Es behauptete eine Zahl von
# Abstiegsplaetzen, die das Modell selbst nicht kennt. Genau darum wurden
# die RL in Phase 5a zurueckgestellt (test-generate_static_site.R, Kopf des
# Abschnitts "aus test-frauen-ligen-live.R").
#
# Entscheidung des Nutzers (2026-09-07): "einfache gewichtete Aufaddition
# zur Abstiegswahrscheinlichkeit je Team" -- also Variante (C) unten. Die
# Alternativen und warum sie ausscheiden:
#
#   (A) Feste Platzgruppe wie die Altligen. AUSGESCHLOSSEN, s.o.: Sie
#       behauptet Wissen, das nicht existiert.
#   (B) Die "wahrscheinlichste" Platzzahl waehlen (etwa argmax P(k)) und
#       daraus eine feste Gruppe bauen. AUSGESCHLOSSEN: Das rundet eine
#       Verteilung auf einen Punkt und zeigt fuer jedes Team eine Zahl, die
#       nur unter EINER von mehreren Auszaehlungen stimmt -- lautlos falsch.
#   (C) Das untere Panel kommt aus einer BERECHNETEN Spalte statt aus einer
#       Platzgruppe: `rl_abstiegsprognose()` liefert je Team fertige
#       Wahrscheinlichkeiten, die ueber alle k gemischt sind. GEWAEHLT.
#
# Die View traegt dafuer im `bottom` KEINE `groups`/`filter_cols`, sondern
# eine Kennzeichnung, dass die Werte vorberechnet hereinkommen. Die hier
# gepruefte Form:
#
#   bottom = list(
#     source  = "Abstieg_rl_<staffel>",   # eigenes Objekt, kein Platzband
#     computed = TRUE,                     # -> keine Gruppenaufloesung
#     labels  = "Abstieg"                  # Bayern: c("Relegation", "Abstieg")
#   )
#
# `computed = TRUE` ist der Vertrag: Wo es steht, DARF weder `groups` noch
# `filter_cols` stehen, und render_league_page() reicht die Spalten des
# Objekts unveraendert durch, statt Platzspalten zu summieren. Die Spalten
# des Objekts sind genau die `labels` -- das ist die Form, die
# rl_abstiegsprognose() heute schon liefert (data.frame mit rownames =
# Teams und Spalte "Abstieg", fuer Bayern "Relegation" + "Abstieg").
#
# Warum ein eigenes Merkmal und nicht "leere groups": Ein NULL-Test waere
# implizit; `computed = TRUE` steht als Aussage da und laesst sich pruefen,
# ohne das Fehlen von etwas zu interpretieren.
#
# Beim oberen Panel von Nord und Bayern stehen eine Platzgruppe (Meister)
# und eine berechnete Spalte (Aufstieg) NEBENEINANDER. `computed` ist
# deshalb ein logischer Vektor ueber die Spalten -- ein Eintrag je Label:
#
#   top = list(
#     source   = "Ergebnis_rl_nord",        # fuer die Meister-Spalte
#     computed = c(FALSE, TRUE),
#     computed_source = "Aufstieg_rl_nord", # fuer die Aufstiegs-Spalte
#     filter_cols = 1L,
#     labels   = c("Meister", "Aufstieg"),
#     groups   = cbind(c(1, 1))             # nur fuer die NICHT-computed
#   )
#
# isTRUE(all(...$computed)) heisst "ganz berechnet", any() heisst
# "gemischt". Bei den drei Direktaufsteigern faellt der Fall weg: dort ist
# `computed` durchgehend FALSE und eine einzige Spalte genuegt.
#
# ---------------------------------------------------------------------------
# ZWEI PFLICHT-INVARIANTEN (Vorgabe des Nutzers, 2026-09-07)
# ---------------------------------------------------------------------------
#
# Die gerechnete Spalte hat eine Eigenschaft, die eine Platzgruppe nicht
# haette -- und die sie pruefbar macht:
#
#   SUMME ueber alle Teams P(Team steigt ab) = E[Zahl der Absteiger]
#
# Das ist Algebra, keine Naeherung: Jede Platzspalte der Prognosematrix
# summiert ueber die Teams auf 1 (genau ein Team belegt jeden Platz), also
# ist die Teamsumme der Abstiegswahrscheinlichkeiten gleich der Summe der
# Platzgewichte -- und die ist der Erwartungswert der Absteigerzahl.
#
# Fuer Bayern gilt beides EXAKT und ohne Erwartungswert, weil die Staffel
# entkoppelt ist: Summe Abstieg = 2 und Summe Relegation = 2.
#
# Die Toleranz ist deshalb 1e-9, nicht 0.01. Eine weite Toleranz wuerde
# genau den Fehler durchlassen, den diese Invariante fangen soll: eine
# Gewichtung, die "ungefaehr stimmt" und die Wahrscheinlichkeitsmasse
# verliert.
#
# ---------------------------------------------------------------------------
# OBEN: Meister und Aufstieg als ZWEI Spalten (Vorgabe des Nutzers)
# ---------------------------------------------------------------------------
#
# Phase 7, RCode/rl_aufstieg.R, Saison 2026/27:
#
#   West, SuedWest, Nordost  Direktaufstieg -- P(Aufstieg) = P(Meister)
#   Nord, Bayern             KEIN Direktaufstieg, sondern zwei
#                            Aufstiegsspiele gegeneinander. P(Aufstieg) ist
#                            die Doppelsumme ueber beide Staffeln und
#                            STRIKT KLEINER als P(Meister).
#
# Fuer Nord und Bayern steht deshalb ein EXTRA-Wert rechts neben der
# Meisterwahrscheinlichkeit: zwei Spalten, "Meister" und "Aufstieg". Die
# Meisterspalte ist eine echte Platzgruppe (Platz 1), die Aufstiegsspalte
# eine berechnete. Ein Panel traegt hier also BEIDES -- deshalb sitzt
# `computed` an der einzelnen Spalte und nicht am ganzen Panel.
#
# Fuer die drei Direktaufsteiger fallen beide Groessen zusammen; dort
# genuegt eine Spalte. Ein Test haelt fest, dass sie dort wirklich gleich
# sind -- sonst waere die Vereinfachung eine stille Abweichung.
#
# ---------------------------------------------------------------------------
# EIGENE SEITE "Aufstieg in die 3. Liga" -- entschieden
# ---------------------------------------------------------------------------
#
# Der Nutzer hat am 2026-09-07 Variante 2 gewaehlt (Randsummen), Navigation
# unter "Regionalliga". Die Tests dazu stehen in Abschnitt 4a; hier nur die
# verworfenen Alternativen, damit die Entscheidung nachvollziehbar bleibt.
#
#   Variante 1 -- die volle Paarungsmatrix, 18 x 19 Zellen. VERWORFEN:
#     342 Zellen, praktisch alle nahe null. Die Meisterwahrscheinlichkeit
#     konzentriert sich je Staffel auf zwei, drei Teams; das Produkt
#     zweier kleiner Zahlen ist noch kleiner. Auf Mobil unlesbar -- sie
#     zeigt viel und sagt wenig.
#
#   Variante 2 -- Randsummen je Team. GEWAEHLT: Team, P(Meister),
#     P(Aufstieg), Siegquote. Das ist die ueber den Gegner ausintegrierte
#     Matrix, also dieselbe Information ohne die 342 Zellen. Beantwortet
#     die Frage, die der Leser hat.
#
#   Variante 3 -- Variante 2 plus die wahrscheinlichsten Paarungen.
#     VERWORFEN: Der Schwellwert waere eine willkuerliche Setzung, und die
#     Tabelle wechselte im Saisonverlauf ihre Laenge.
#
# Begruendung des Nutzers fuer die einfachste Form: "Fuer naechste Saison
# muessen wir eh vermutlich neue Aufstiegsregeln implementieren, und dann
# bauen wir halt auch die Aufstiegsseite passend um." Also kein Vorbau fuer
# Regeln, die es noch nicht gibt.
#
# ===========================================================================

# RL_SCHLUESSEL (die fuenf RL in Registry-Reihenfolge) steht in helper-fixtures.R.

# ===========================================================================
# 1. Registry: alle fuenf Regionalligen sind aktiv
# ===========================================================================

# ACHTUNG fuer die Implementierung: Diese drei Tests, damals alle in einer
# Datei (heute aufgeteilt auf test-checkAPILimits.R und
# test-season_validation.R, der erste entfaellt ersatzlos), sagten zum
# Zeitpunkt dieses Kommentars das GEGENTEIL und wurden mit der Aktivierung
# rot. Sie sind Bestand aus Phase 5a und mussten dort mitgezogen werden --
# absichtlich NICHT von hier aus mit erledigt, damit der Schritt sichtbar
# blieb:
#
#   "die Regionalligen bleiben inaktiv" (Zeile 22)  -- entfaellt ersatzlos;
#       ihre Aussage ist genau das, was Phase 5 aufhebt.
#   "checkAPILimits skaliert mit fuenf Ligen" (Zeile 146) -- die Formel
#       1 + 5/2 wird zu 1 + 10/2. Der Default folgt der Ligazahl, also
#       laesst sich das aus league_ids() ableiten, statt die Zahl zu
#       wiederholen.
#   "die Saisonvalidierung prueft nur die Altligen" (Zeile 131) -- bleibt
#       gruen: SEASON_TRANSITION_LEAGUES ist bewusst bei 78/79/80, weil es
#       fuer die neuen Ligen keine aufgezeichneten API-Antworten gibt. Das
#       ist eine eigene Entscheidung, kein Versehen.

test_that("league_ids liefert zehn Ligen in Registry-Reihenfolge", {
  # Die Reihenfolge bestimmt, in welcher Folge der Loop abruft und in
  # welcher Reihenfolge die Navigation baut -- sie darf sich nicht
  # unbemerkt aendern. Deshalb der exakte Vektor, nicht nur die Laenge.
  # (Seit Issue #178 gilt das nur noch fuer den Abruf: Die Navigation hat
  # eine eigene Angabe in NAV_GRUPPEN_REIHENFOLGE und bewegt sich
  # unabhaengig von dieser Reihenfolge.)
  env <- source_module("league_registry")

  expect_identical(
    env$league_ids(),
    c("78", "79", "80", "82", "1034", "84", "85", "87", "86", "83")
  )
  expect_identical(env$league_ids(), env$league_ids(active_only = FALSE))
})

test_that("active_league_keys nennt die fuenf Regionalligen mit", {
  env <- source_module("league_registry")

  expect_identical(
    env$active_league_keys(),
    c("bundesliga", "zweite_bundesliga", "dritte_liga",
      "frauen_bundesliga", "zweite_frauen_bundesliga", RL_SCHLUESSEL)
  )
  expect_identical(env$active_league_keys(), names(env$active_leagues()))
})

test_that("jede Regionalliga traegt active = TRUE", {
  env <- source_module("league_registry")
  reg <- env$league_registry()

  for (key in RL_SCHLUESSEL) {
    expect_true(isTRUE(reg[[key]]$active), info = key)
  }
})

test_that("die nav_group ordnet die zehn Ligen drei Gruppen zu", {
  # Werte, nicht Vorhandensein: Jede Liga bekommt ihre Gruppe genannt.
  env <- source_module("league_registry")
  reg <- env$league_registry()

  gruppen <- vapply(reg, function(l) l$nav_group %||% NA_character_,
                    character(1))
  expect_identical(
    unname(gruppen),
    c("Herren", "Herren", "Herren", "Frauen", "Frauen",
      rep("Regionalliga", 5))
  )
})

test_that("die Regionalligen behalten das Herren-Tormodell", {
  # Sie tauschen Teams mit der 3. Liga, gehoeren also zur
  # Wechselgemeinschaft Herren (ADR 0004). goal_model() muss NULL liefern:
  # nichts senden, der Rust-Default greift. Ein eigener Intercept wuerde
  # jeden Auf- und Absteiger stillschweigend umskalieren.
  env <- source_module("league_registry")

  for (id in RL_IDS) {
    expect_null(env$goal_model(id), info = id)
    expect_identical(env$league_family(id), "herren", info = id)
  }
})

test_that("aus den Regionalligen duerfen Zweitvertretungen nicht aufsteigen", {
  # Wie in der 3. Liga: Die Aufstiegstabelle braucht einen zweiten Lauf mit
  # -50-Malus. has_promotion_restriction() steuert das.
  env <- source_module("league_registry")

  for (id in RL_IDS) {
    expect_true(env$has_promotion_restriction(id), info = id)
  }
})

test_that("Registry und AUFSTIEGSROTATION sagen dasselbe ueber 2026/27", {
  # Die promotion_slots/playoff_slots der Registry sind ABGELEITET; die
  # massgebliche Quelle ist AUFSTIEGSROTATION in RCode/rl_aufstieg.R. Wenn
  # beide auseinanderlaufen, zeigt die Seite einen anderen Modus als die
  # Rechnung -- ohne dass etwas fehlschlaegt.
  env <- source_module("league_registry")
  auf <- new.env()
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = auf)
  source(test_path("..", "..", "RCode", "rl_aufstieg.R"), local = auf)

  reg <- env$league_registry()
  for (key in RL_SCHLUESSEL) {
    eintrag <- reg[[key]]
    slots <- auf$rl_aufstiegs_slots(eintrag$staffel, 2026)
    expect_identical(eintrag$promotion_slots, slots$promotion_slots,
                     info = key)
    expect_identical(eintrag$playoff_slots, slots$playoff_slots, info = key)
  }
})

test_that("Nord und Bayern haben 2026/27 exakt null Direktaufstiegsplaetze", {
  # Rechnerisch nicht moeglich heisst exakt 0, nicht "klein". Wo das kippt,
  # zeigte die Seite einen Direktaufstieg, den es nicht gibt.
  env <- source_module("league_registry")
  reg <- env$league_registry()

  for (key in RL_AUFSTIEGSSPIELE) {
    expect_identical(reg[[key]]$promotion_slots, 0L, info = key)
    expect_identical(reg[[key]]$playoff_slots, 1L, info = key)
  }
  for (key in RL_DIREKTAUFSTIEG) {
    expect_identical(reg[[key]]$promotion_slots, 1L, info = key)
    expect_identical(reg[[key]]$playoff_slots, 0L, info = key)
  }
})

test_that("nur Bayern traegt Relegationsplaetze nach unten", {
  # playoff_slots ist richtungslos; Bayern braucht das eigene Feld
  # relegation_playoff_slots, weil es BEIDES hat.
  env <- source_module("league_registry")
  reg <- env$league_registry()

  expect_identical(reg$rl_bayern$relegation_playoff_slots, 2L)
  for (key in setdiff(RL_SCHLUESSEL, "rl_bayern")) {
    expect_null(reg[[key]]$relegation_playoff_slots, info = key)
  }
})

test_that("league_views und Registry stimmen in Schluesseln und Slugs ueberein", {
  # Ueber die Schluessel sind Loop, Registry und Generator verbunden; ueber
  # die Slugs entstehen die Dateinamen. Zwei Quellen, eine Aussage.
  reg <- source_module("league_registry")$league_registry()
  views <- source_module("league_views")$league_views()

  expect_identical(names(views), names(reg))
  expect_identical(
    vapply(views, function(v) v$slug, character(1)),
    vapply(reg, function(l) l$slug, character(1))
  )
})

# ===========================================================================
# 5. teams_range gegen die FIXTURES, nicht gegen die TeamList
# ===========================================================================

# Die TeamList fuehrt je RL-Staffel 29-33 Eintraege: alle Teams, die je in
# dieser Staffel aufgetreten sind, damit ein Auf- oder Absteiger seinen
# ELO-Wert wiederfindet. Tatsaechlich spielen 18-19. Wer die Validierung
# gegen die TeamList laufen laesst, bekommt entweder eine falsche Spanne
# (bis 33) oder einen Fehlalarm.
#
# Dieser Test sichert ab, dass die Spanne die echten Spielplaene traegt;
# der Test weiter unten sichert ab, dass die TeamList sie NICHT traegt.

rl_fixture_teams <- function(liga, saison = 2025) {
  pfad <- test_path("fixtures", "fixture_cache",
                    paste0(liga, "_", saison, ".json"))
  skip_if_not(file.exists(pfad), paste("Fixture fehlt:", basename(pfad)))

  x <- jsonlite::fromJSON(pfad)
  rf <- source_module("round_filter")
  keep <- rf$is_regular_season_round(x$round)
  unique(c(x$teams_home_name[keep], x$teams_away_name[keep]))
}

test_that("die echten RL-Spielplaene 2025 liegen in der teams_range", {
  # 2025 spielten alle fuenf Staffeln mit 18 Teams. Der Wert wird gemessen,
  # nicht angenommen -- er kommt aus dem committeten Spielplan.
  env <- source_module("league_registry")

  for (i in seq_along(RL_IDS)) {
    id <- RL_IDS[[i]]
    teams <- rl_fixture_teams(id)
    spanne <- env$league_teams_range(id)

    expect_identical(length(teams), 18L, info = id)
    expect_gte(length(teams), spanne[[1]])
    expect_lte(length(teams), spanne[[2]])
  }
})

test_that("die TeamList fuehrt weit mehr Eintraege als eine Staffel Teams hat", {
  # Der Grund, warum die Validierung NICHT gegen die TeamList laufen darf.
  # Geprueft wird der Abstand, nicht nur die Ungleichheit: Er ist gross und
  # strukturell, nicht ein Rundungsfehler.
  env <- source_module("league_registry")
  tl <- utils::read.csv(
    test_path("..", "..", "RCode", "TeamList_2026.csv"),
    sep = ";", stringsAsFactors = FALSE
  )

  for (id in RL_IDS) {
    eintraege <- sum(as.character(tl$League) == id)
    spanne <- env$league_teams_range(id)

    expect_gt(eintraege, spanne[[2]])
    expect_gte(eintraege, 29L)
  }
})

test_that("die teams_range traegt jede belegte RL-Saison seit 2019", {
  # Der Cache reicht von 2019 bis 2025 und enthaelt Staffeln mit 17 bis 22
  # Teams (Corona-Jahrgaenge). Eine zu enge Spanne faellt hier auf, bevor
  # sie im Betrieb einen Saisonwechsel blockiert.
  env <- source_module("league_registry")
  verzeichnis <- test_path("fixtures", "fixture_cache")
  skip_if_not(dir.exists(verzeichnis))

  dateien <- list.files(verzeichnis, pattern = "^8[3-7]_[0-9]{4}\\.json$")
  skip_if(length(dateien) == 0, "kein RL-Fixture-Cache vorhanden")

  for (datei in dateien) {
    teile <- strsplit(sub("\\.json$", "", datei), "_")[[1]]
    teams <- rl_fixture_teams(teile[[1]], teile[[2]])
    spanne <- env$league_teams_range(teile[[1]])

    expect_gte(length(teams), spanne[[1]], label = datei)
    expect_lte(length(teams), spanne[[2]], label = datei)
  }
})

# ===========================================================================
# 7. Waechter: keine Modellkonstante wandert mit den neuen Ligen nach R
# ===========================================================================

test_that("keine Regionalliga sendet ein eigenes Tormodell", {
  # ADR 0004: Die RL gehoeren zur Wechselgemeinschaft Herren. Ein
  # staffelweiser Intercept wuerde jeden Auf- und Absteiger stillschweigend
  # umskalieren -- und test-waechter-quelltext.R rot faerben.
  env <- source_module("league_registry")

  for (id in RL_IDS) {
    expect_identical(env$goal_model_args(id), list(), info = id)
  }
})
