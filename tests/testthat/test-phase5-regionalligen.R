library(testthat)

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
# die RL in Phase 5a zurueckgestellt (test-frauen-ligen-live.R, Kopf).
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

# --- Quellen ----------------------------------------------------------------

source_registry <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  env
}

source_views <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_views.R"), local = env)
  env
}

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

source_round_filter <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "round_filter.R"), local = env)
  env
}

# Der Aufstiegsteil braucht VIER Dateien, und die Reihenfolge ist nicht
# beliebig: rl_aufstieg.R ruft pruefe_staffel() auf, das in
# rl_abstiegskopplung.R steht, und p_sieg_matrix() aus aufstiegsspiele.R.
# Fehlt eine, faellt die Aufloesung ueber die Elternumgebung auf zufaellig
# vorhandene Definitionen aus anderen Testdateien zurueck -- der Test waere
# dann von der Ausfuehrungsreihenfolge abhaengig.
source_aufstieg <- function() {
  env <- new.env()
  for (datei in c("league_registry.R", "staffel_zuordnung.R",
                  "rl_abstiegskopplung.R", "aufstiegsspiele.R",
                  "rl_aufstieg.R")) {
    source(test_path("..", "..", "RCode", datei), local = env)
  }
  env
}

# Gleichverteilte Prognose: jeder Platz traegt 1/n. Damit sind die
# erwarteten Prozentwerte der Panels exakt bekannt.
mk_ergebnis <- function(teams) {
  m <- matrix(1 / teams, nrow = teams, ncol = teams,
              dimnames = list(paste0("T", seq_len(teams)),
                              as.character(seq_len(teams))))
  as.table(m)
}

# Die fuenf RL in Registry-Reihenfolge. Sie ist Vertrag (Fetch-Reihenfolge
# und Navigation), deshalb hier einmal ausgeschrieben.
RL_SCHLUESSEL <- c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest",
                   "rl_bayern")
RL_IDS <- c("84", "85", "87", "86", "83")
RL_SLUGS <- c("rl-nord", "rl-nordost", "rl-west", "rl-suedwest", "rl-bayern")

# Slug der Seite "Aufstieg in die 3. Liga". Steht hier und nicht erst bei
# den Aufstiegstests: testthat wertet Top-Level-Code sequenziell aus, und
# die Navigations- und Seitenzahl-Tests weiter oben brauchen den Wert
# bereits.
AUFSTIEGSSEITE_SLUG <- "rl-aufstieg"

# Die Staffeln mit Direktaufstieg 2026/27 (Par. 55b DFB-SpO Nr. 2 plus der
# Rotationsplatz, den 2026/27 Nordost traegt).
RL_DIREKTAUFSTIEG <- c("rl_nordost", "rl_west", "rl_suedwest")
# Nord und Bayern spielen stattdessen zwei Aufstiegsspiele gegeneinander.
RL_AUFSTIEGSSPIELE <- c("rl_nord", "rl_bayern")

# ===========================================================================
# 1. Registry: alle fuenf Regionalligen sind aktiv
# ===========================================================================

# ACHTUNG fuer die Implementierung: Diese drei Tests in
# test-frauen-ligen-aktivierung.R sagen heute das GEGENTEIL und werden mit
# der Aktivierung rot. Sie sind Bestand aus Phase 5a und muessen dort
# mitgezogen werden -- absichtlich NICHT von hier aus mit erledigt, damit
# der Schritt sichtbar bleibt:
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
  env <- source_registry()

  expect_identical(
    env$league_ids(),
    c("78", "79", "80", "82", "1034", "84", "85", "87", "86", "83")
  )
  expect_identical(env$league_ids(), env$league_ids(active_only = FALSE))
})

test_that("active_league_keys nennt die fuenf Regionalligen mit", {
  env <- source_registry()

  expect_identical(
    env$active_league_keys(),
    c("bundesliga", "zweite_bundesliga", "dritte_liga",
      "frauen_bundesliga", "zweite_frauen_bundesliga", RL_SCHLUESSEL)
  )
  expect_identical(env$active_league_keys(), names(env$active_leagues()))
})

test_that("jede Regionalliga traegt active = TRUE", {
  env <- source_registry()
  reg <- env$league_registry()

  for (key in RL_SCHLUESSEL) {
    expect_true(isTRUE(reg[[key]]$active), info = key)
  }
})

test_that("die nav_group ordnet die zehn Ligen drei Gruppen zu", {
  # Werte, nicht Vorhandensein: Jede Liga bekommt ihre Gruppe genannt.
  env <- source_registry()
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
  env <- source_registry()

  for (id in RL_IDS) {
    expect_null(env$goal_model(id), info = id)
    expect_identical(env$league_family(id), "herren", info = id)
  }
})

test_that("aus den Regionalligen duerfen Zweitvertretungen nicht aufsteigen", {
  # Wie in der 3. Liga: Die Aufstiegstabelle braucht einen zweiten Lauf mit
  # -50-Malus. has_promotion_restriction() steuert das.
  env <- source_registry()

  for (id in RL_IDS) {
    expect_true(env$has_promotion_restriction(id), info = id)
  }
})

test_that("Registry und AUFSTIEGSROTATION sagen dasselbe ueber 2026/27", {
  # Die promotion_slots/playoff_slots der Registry sind ABGELEITET; die
  # massgebliche Quelle ist AUFSTIEGSROTATION in RCode/rl_aufstieg.R. Wenn
  # beide auseinanderlaufen, zeigt die Seite einen anderen Modus als die
  # Rechnung -- ohne dass etwas fehlschlaegt.
  env <- source_registry()
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
  env <- source_registry()
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
  env <- source_registry()
  reg <- env$league_registry()

  expect_identical(reg$rl_bayern$relegation_playoff_slots, 2L)
  for (key in setdiff(RL_SCHLUESSEL, "rl_bayern")) {
    expect_null(reg[[key]]$relegation_playoff_slots, info = key)
  }
})

# ===========================================================================
# 2. league_views: die fuenf neuen Ansichten
# ===========================================================================

test_that("league_views kennt zehn Ligen in Registry-Reihenfolge", {
  env <- source_views()
  views <- env$league_views()

  expect_named(
    views,
    c("bundesliga", "zweite_bundesliga", "dritte_liga",
      "frauen_bundesliga", "zweite_frauen_bundesliga", RL_SCHLUESSEL)
  )
})

test_that("league_views und Registry stimmen in Schluesseln und Slugs ueberein", {
  # Ueber die Schluessel sind Loop, Registry und Generator verbunden; ueber
  # die Slugs entstehen die Dateinamen. Zwei Quellen, eine Aussage.
  reg <- source_registry()$league_registry()
  views <- source_views()$league_views()

  expect_identical(names(views), names(reg))
  expect_identical(
    vapply(views, function(v) v$slug, character(1)),
    vapply(reg, function(l) l$slug, character(1))
  )
})

test_that("die Regionalliga-Slugs und nav_labels sind die der Registry", {
  views <- source_views()$league_views()

  expect_identical(
    unname(vapply(views[RL_SCHLUESSEL], function(v) v$slug, character(1))),
    RL_SLUGS
  )
  expect_identical(
    unname(vapply(views[RL_SCHLUESSEL], function(v) v$nav_label,
                  character(1))),
    c("Nord", "Nordost", "West", "SüdWest", "Bayern")
  )
})

test_that("jede Regionalliga liest Heatmap und Panels aus eigenen Objekten", {
  # Der Generator loest ueber diese Namen auf. Zwei Ligen, die versehentlich
  # dasselbe Objekt lesen, zeigen dieselben Zahlen unter verschiedenen
  # Ueberschriften -- und nichts schlaegt fehl.
  views <- source_views()$league_views()

  plot_quellen <- vapply(views[RL_SCHLUESSEL],
                         function(v) v$plot_source, character(1))
  expect_identical(
    unname(plot_quellen),
    paste0("Ergebnis_", RL_SCHLUESSEL)
  )
  expect_identical(length(unique(plot_quellen)), 5L)
})

# --- 2a. Oben: Direktaufstieg vs. Aufstiegsspiele ---------------------------

test_that("Nordost, West und SuedWest zeigen oben eine Aufstiegsspalte", {
  # Direktaufsteiger: P(Aufstieg) = P(Meister), beide Groessen fallen
  # zusammen. Eine Spalte genuegt, und sie ist eine echte Platzgruppe
  # (Platz 1). Geprueft wird der WERT der gerenderten Tabelle: Bei 18
  # gleichverteilten Teams traegt Platz 1 genau 1/18 = 6 %.
  gen <- source_generator()
  views <- gen$league_views()

  for (key in RL_DIREKTAUFSTIEG) {
    v <- views[[key]]
    expect_identical(v$top$labels, "Aufstieg", info = key)
    # Direktaufstieg ist eine Platzgruppe, keine berechnete Spalte.
    expect_false(any(isTRUE(v$top$computed)), info = key)

    html <- gen$render_panel_table(mk_ergebnis(18), v$top)
    expect_match(html, "<td>6</td>", info = key)
    # Waere die Gruppe versehentlich 1:2, stuenden hier 11 %.
    expect_no_match(html, "<td>11</td>", info = key)
  }
})

test_that("bei den Direktaufsteigern sind Meister und Aufstieg wirklich gleich", {
  # Die Rechtfertigung der einen Spalte: Nur wenn rl_aufstiegsprognose()
  # dort exakt die Meisterwahrscheinlichkeit liefert, ist die Vereinfachung
  # keine stille Abweichung. Nicht angenommen, sondern nachgerechnet.
  auf <- source_aufstieg()

  # Ungleiche Meisterchancen, damit ein versehentliches "alle gleich"
  # nicht durchginge.
  prognose <- function(teams, praefix) {
    m <- matrix(1 / teams, nrow = teams, ncol = teams,
                dimnames = list(paste0(praefix, seq_len(teams)),
                                as.character(seq_len(teams))))
    m[, 1] <- c(0.5, 0.3, rep(0.2 / (teams - 2), teams - 2))
    m
  }
  prognosen <- list(Nord = prognose(18, "N"), Nordost = prognose(18, "O"),
                    West = prognose(18, "W"), SuedWest = prognose(18, "S"),
                    Bayern = prognose(19, "B"))

  for (staffel in c("Nordost", "West", "SuedWest")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026)
    expect_equal(unname(df$Aufstieg),
                 unname(prognosen[[staffel]][, 1]),
                 tolerance = 1e-12, info = staffel)
  }
})

test_that("Nord und Bayern zeigen oben Meister UND Aufstieg getrennt", {
  # 2026/27 haben beide keinen Direktplatz (BFV A&A 2026/27 I. Nr. 1).
  # Eine einzelne Spalte "Aufstieg" ueber P(Platz 1) waere die Aussage
  # "Meister = Aufsteiger" -- und die ist fuer diese beiden falsch. Der
  # Aufstiegswert steht als EXTRA-Wert rechts neben der
  # Meisterwahrscheinlichkeit.
  views <- source_views()$league_views()

  for (key in RL_AUFSTIEGSSPIELE) {
    v <- views[[key]]
    expect_identical(v$top$labels, c("Meister", "Aufstieg"), info = key)
  }
})

test_that("bei Nord und Bayern ist nur die Aufstiegsspalte berechnet", {
  # Gemischtes Panel: Die Meisterspalte bleibt eine Platzgruppe (Platz 1),
  # die Aufstiegsspalte kommt aus der Doppelsumme. `computed` traegt
  # deshalb einen Eintrag je Label -- steht dort ein einzelnes TRUE, waere
  # auch die Meisterspalte vorberechnet und die Platzgruppe wirkungslos.
  views <- source_views()$league_views()

  for (key in RL_AUFSTIEGSSPIELE) {
    v <- views[[key]]
    expect_identical(v$top$computed, c(FALSE, TRUE), info = key)
    # Die berechnete Spalte kommt aus einem EIGENEN Objekt, nicht aus der
    # Prognosematrix -- sonst waere es wieder nur eine Platzsumme.
    expect_false(identical(v$top$computed_source, v$plot_source), info = key)
    expect_true(is.character(v$top$computed_source), info = key)
  }
})

test_that("P(Aufstieg) ist fuer Nord und Bayern strikt kleiner als P(Meister)", {
  # Der inhaltliche Grund fuer die zweite Spalte: Wer Meister wird, muss
  # noch zwei Aufstiegsspiele gewinnen. Waeren beide Zahlen gleich, brauchte
  # es die Spalte nicht -- und die Seite behauptete einen Direktaufstieg.
  auf <- source_aufstieg()

  nord <- matrix(1 / 18, nrow = 18, ncol = 18,
                 dimnames = list(paste0("N", 1:18), as.character(1:18)))
  bayern <- matrix(1 / 19, nrow = 19, ncol = 19,
                   dimnames = list(paste0("B", 1:19), as.character(1:19)))
  prognosen <- list(Nord = nord, Nordost = nord, West = nord,
                    SuedWest = nord, Bayern = bayern)

  # Ausgeglichene Zweikaempfe: jede Paarung 50:50. Zeilen = Nord (in
  # STAFFELN frueher), Spalten = Bayern.
  p_sieg <- matrix(0.5, nrow = 18, ncol = 19,
                   dimnames = list(rownames(nord), rownames(bayern)))

  df_nord <- auf$rl_aufstiegsprognose("Nord", prognosen, 2026, p_sieg = p_sieg)
  df_bayern <- auf$rl_aufstiegsprognose("Bayern", prognosen, 2026,
                                        p_sieg = p_sieg)

  # P(Meister) = 1/18 bzw. 1/19; mit 50 % Siegquote genau die Haelfte.
  expect_equal(unname(df_nord$Aufstieg[[1]]), 0.5 / 18, tolerance = 1e-12)
  expect_equal(unname(df_bayern$Aufstieg[[1]]), 0.5 / 19, tolerance = 1e-12)

  expect_lt(df_nord$Aufstieg[[1]], 1 / 18)
  expect_lt(df_bayern$Aufstieg[[1]], 1 / 19)

  # Zusammen steigt genau EINE der beiden Staffeln auf.
  expect_equal(sum(df_nord$Aufstieg) + sum(df_bayern$Aufstieg), 1,
               tolerance = 1e-9)
})

# --- 2b. Unten: variable Abstiegsgrenzen ------------------------------------

test_that("keine Regionalliga stellt den Abstieg als feste Platzgruppe dar", {
  # DER FACHLICHE KERN, aber nicht fuer alle fuenf aus demselben Grund.
  #
  # DREI Staffeln haben eine variable Zahl von Abstiegsplaetzen, abhaengig
  # davon, wie viele Drittligisten in die Staffel fallen:
  #   Nord     3-7  (3 + k, dazu 2 statt 3 als Basis, wenn der eigene
  #                  Meister aufsteigt -- die einzige Staffel mit beiden
  #                  Kopplungen)
  #   Nordost  1-2  (1 + k, Schema bis 2)
  #   SuedWest 3-5  (3 + k, Deckel 5)
  # Eine `groups`-Matrix koennte dort nur EINE Zahl behaupten und waere
  # fuer jede andere Auszaehlung falsch, ohne dass etwas fehlschlaegt.
  #
  # WEST und BAYERN sind dagegen KONSTANT (4 bzw. 2) -- sie koppeln nicht
  # an die 3. Liga. Sie stehen aus anderen Gruenden in dieser Gruppe:
  #
  #   West:   Die Zahl ist fest, die Ligagroesse aber nicht (teams_range
  #           16-22). "Die letzten vier" liesse sich nur als NEGATIVE
  #           Grenze c(-4, -1) schreiben -- und genau dort hat dieses
  #           Projekt schon zweimal falsch gerechnet, weil R negative
  #           Indizes als AUSSCHLUSS liest. Die berechnete Spalte loest
  #           die Plaetze gegen die tatsaechliche Teamzahl auf.
  #   Bayern: weist unten ZWEI Groessen aus (Relegation und Abstieg), von
  #           denen die Relegation bewusst nicht aufgeloest wird --
  #           ebenfalls keine reine Platzsumme.
  #
  # Hier stand zuvor "vier der fuenf ... (3-5 / 1-2 / 3-7 / 4-0)". Das
  # "4-0" beschrieb die gegenlaeufige West-Kopplung, die in babc828
  # verworfen wurde.
  views <- source_views()$league_views()

  for (key in RL_SCHLUESSEL) {
    v <- views[[key]]
    expect_true(isTRUE(v$bottom$computed), info = key)
    expect_null(v$bottom$groups, info = key)
    expect_null(v$bottom$filter_cols, info = key)
  }
})

test_that("die Altligen und Frauen-Ligen behalten ihre Platzgruppen", {
  # Gegenprobe: `computed` ist eine Ausnahme fuer die RL, keine stille
  # Verhaltensaenderung der uebrigen fuenf Ligen.
  views <- source_views()$league_views()
  alt <- c("bundesliga", "zweite_bundesliga", "dritte_liga",
           "frauen_bundesliga", "zweite_frauen_bundesliga")

  for (key in alt) {
    v <- views[[key]]
    for (panel in c("top", "bottom")) {
      expect_false(isTRUE(v[[panel]]$computed),
                   info = paste(key, panel))
      expect_false(is.null(v[[panel]]$groups), info = paste(key, panel))
    }
  }
})

test_that("vier Staffeln weisen unten nur den Abstieg aus", {
  views <- source_views()$league_views()

  for (key in setdiff(RL_SCHLUESSEL, "rl_bayern")) {
    expect_identical(views[[key]]$bottom$labels, "Abstieg", info = key)
  }
})

test_that("Bayern weist unten zwei getrennte Baender aus", {
  # "Fuer die Regionalliga Bayern gibt es nach unten nur die
  # Wahrscheinlichkeiten fuer Relegation und direkten Abstieg."
  # (Entscheidung Christoph, 2026-09-06, Modellannahmen 3.)
  #
  # Die Relegation wird NICHT in eine Abstiegswahrscheinlichkeit
  # aufgeloest: Wir simulieren die Bayernligen nicht, jede Gewinnquote
  # waere erfunden. Deshalb zwei Spalten, nicht eine Summe.
  views <- source_views()$league_views()
  v <- views$rl_bayern

  expect_identical(v$bottom$labels, c("Relegation", "Abstieg"))
})

test_that("die Abstiegsspalten heissen wie die Spalten von rl_abstiegsprognose", {
  # Der Vertrag zwischen Phase 6 und der View: rl_abstiegsprognose()
  # liefert einen data.frame mit rownames = Teams und genau diesen
  # Spalten. Laufen die Namen auseinander, faellt die Spalte beim Rendern
  # aus -- oder es steht die falsche unter der falschen Ueberschrift.
  views <- source_views()$league_views()

  rl <- new.env()
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = rl)
  source(test_path("..", "..", "RCode", "rl_abstiegskopplung.R"), local = rl)

  # Zaehlmatrix der 3. Liga: alle vier Absteiger sicher nach Nord.
  counts <- matrix(0, nrow = 5, ncol = 5,
                   dimnames = list(rl$STAFFELN, as.character(0:4)))
  counts["Nord", "4"] <- 1000
  for (s in c("Nordost", "West", "SuedWest", "Bayern")) {
    counts[s, "0"] <- 1000
  }

  staffel_von <- c(rl_nord = "Nord", rl_nordost = "Nordost",
                   rl_west = "West", rl_suedwest = "SuedWest",
                   rl_bayern = "Bayern")

  for (key in RL_SCHLUESSEL) {
    df <- rl$rl_abstiegsprognose(staffel_von[[key]], mk_ergebnis(18), counts)
    expect_identical(colnames(df), views[[key]]$bottom$labels, info = key)
  }
})

test_that("die Abstiegsgrenze von Nord verschiebt sich mit der 3. Liga", {
  # Das positive Gegenstueck zum Verbot der festen Platzgruppe: Es reicht
  # nicht, dass die View keine Grenze BEHAUPTET -- die zugrunde liegende
  # Zahl muss sich mit der 3. Liga auch wirklich bewegen. Sonst waere
  # `computed = TRUE` nur eine andere Schreibweise fuer dieselbe Konstante.
  rl <- new.env()
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = rl)
  source(test_path("..", "..", "RCode", "rl_abstiegskopplung.R"), local = rl)

  bauen <- function(k_nord) {
    m <- matrix(0, nrow = 5, ncol = 5,
                dimnames = list(rl$STAFFELN, as.character(0:4)))
    m["Nord", as.character(k_nord)] <- 1000
    # Die restlichen Absteiger muessen irgendwo hin -- die Summe der
    # Erwartungswerte ueber alle Staffeln ist exakt 4.
    m["West", as.character(4 - k_nord)] <- 1000
    for (s in c("Nordost", "SuedWest", "Bayern")) m[s, "0"] <- 1000
    m
  }

  # 18 Teams, gleichverteilt: jeder Platz 1/18. Bei d Abstiegsplaetzen
  # traegt jedes Team d/18.
  ohne <- rl$rl_abstiegsprognose("Nord", mk_ergebnis(18), bauen(0))
  mit  <- rl$rl_abstiegsprognose("Nord", mk_ergebnis(18), bauen(2))

  expect_equal(unname(ohne$Abstieg[[1]]), 3 / 18)   # Basis 3
  expect_equal(unname(mit$Abstieg[[1]]), 5 / 18)    # 3 + 2
  expect_gt(mit$Abstieg[[1]], ohne$Abstieg[[1]])
})

test_that("West bleibt bei jeder Auszaehlung der 3. Liga bei vier Absteigern", {
  # ACHTUNG, die haeufigste Fehlannahme in diesem Modell: Der
  # Registry-Kommentar bei rl_west spricht von "gegenlaeufig", die
  # Implementierung (abstiegsplaetze) und test-rl-abstiegskopplung.R:389
  # setzen dagegen FESTE 4. Massgeblich ist die Implementierung -- die
  # Verminderungsgruende des WDFV haengen an den Oberligen und an der
  # Lizenzierung, nicht an der 3. Liga (Modellannahmen 2 und 5.3).
  #
  # Der Test haelt genau das fest, damit die Seite nicht eines Tages einen
  # Abstieg zeigt, der mit k schrumpft.
  rl <- new.env()
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = rl)
  source(test_path("..", "..", "RCode", "rl_abstiegskopplung.R"), local = rl)

  bauen <- function(k_west) {
    m <- matrix(0, nrow = 5, ncol = 5,
                dimnames = list(rl$STAFFELN, as.character(0:4)))
    m["West", as.character(k_west)] <- 1000
    m["Nord", as.character(4 - k_west)] <- 1000
    for (s in c("Nordost", "SuedWest", "Bayern")) m[s, "0"] <- 1000
    m
  }

  for (k in 0:4) {
    df <- rl$rl_abstiegsprognose("West", mk_ergebnis(18), bauen(k))
    # 4 von 18 Plaetzen, gleichverteilt.
    expect_equal(unname(df$Abstieg[[1]]), 4 / 18, tolerance = 1e-12,
                 info = paste("k =", k))
  }
})

test_that("Nordost kann rechnerisch nie mehr als zwei Absteiger haben", {
  # Der Deckel bei 2 (Modellannahmen 5.1). Ein Team, das sicher Dritter von
  # unten wird, hat deshalb EXAKT 0 Abstiegswahrscheinlichkeit -- nicht
  # 1e-17. Wo rechnerisch nichts moeglich ist, muss die Zelle leer bleiben
  # und nicht "<1" zeigen.
  rl <- new.env()
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = rl)
  source(test_path("..", "..", "RCode", "rl_abstiegskopplung.R"), local = rl)

  m <- matrix(0, nrow = 5, ncol = 5,
              dimnames = list(rl$STAFFELN, as.character(0:4)))
  m["Nordost", "2"] <- 1000     # zwei Drittliga-Absteiger, Deckel greift
  m["Nord", "2"] <- 1000
  for (s in c("West", "SuedWest", "Bayern")) m[s, "0"] <- 1000

  # T1 wird sicher Drittletzter (Platz 16 von 18), T2 sicher Letzter.
  prognose <- matrix(0, nrow = 18, ncol = 18,
                     dimnames = list(paste0("T", 1:18), as.character(1:18)))
  prognose[1, 16] <- 1
  prognose[2, 18] <- 1
  for (i in 3:18) prognose[i, if (i <= 15) i else i - 1] <- 1

  df <- rl$rl_abstiegsprognose("Nordost", prognose, m)
  expect_identical(df["T1", "Abstieg"], 0)
  expect_identical(df["T2", "Abstieg"], 1)
})

# --- 2c. Die beiden Pflicht-Invarianten -------------------------------------

test_that("die Summe der Abstiegswahrscheinlichkeiten ist E[Absteigerzahl]", {
  # PFLICHTTEST (Vorgabe des Nutzers). Jede Platzspalte der Prognose
  # summiert ueber die Teams auf 1, also ist die Teamsumme der
  # Abstiegswahrscheinlichkeiten gleich der Summe der Platzgewichte -- und
  # die ist genau der Erwartungswert der Absteigerzahl.
  #
  # Enge Toleranz mit Absicht: Eine Gewichtung, die Wahrscheinlichkeitsmasse
  # verliert (etwa durch einen abgeschnittenen Deckel oder einen
  # Off-by-one bei der Platzaufloesung), faellt bei 0.01 nicht auf.
  rl <- new.env()
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = rl)
  source(test_path("..", "..", "RCode", "rl_abstiegskopplung.R"), local = rl)

  # Eine gemischte Zaehlung: Nord bekommt in 90 % der Iterationen einen
  # Drittliga-Absteiger, sonst keinen. E[k_Nord] = 0.9.
  m <- matrix(0, nrow = 5, ncol = 5,
              dimnames = list(rl$STAFFELN, as.character(0:4)))
  m["Nord", "0"] <- 1000
  m["Nord", "1"] <- 9000
  m["West", "1"] <- 10000
  m["Nordost", "1"] <- 10000
  m["SuedWest", "1"] <- 10000
  # Die Summe der Erwartungswerte ueber alle Staffeln muss exakt 4 sein:
  # 0.9 + 1 + 1 + 1 = 3.9, Bayern traegt die fehlenden 0.1.
  m["Bayern", "0"] <- 9000
  m["Bayern", "1"] <- 1000

  verteilung <- rl$absteiger_verteilung(m)
  ks <- as.numeric(colnames(verteilung))

  staffel_von <- c(rl_nord = "Nord", rl_nordost = "Nordost",
                   rl_west = "West", rl_suedwest = "SuedWest",
                   rl_bayern = "Bayern")

  for (key in names(staffel_von)) {
    staffel <- staffel_von[[key]]
    teams <- if (identical(staffel, "Bayern")) 19L else 18L

    # E[Absteigerzahl] = SUMME ueber k von P(k) * abstiegsplaetze(k).
    erwartet <- sum(verteilung[staffel, ] * rl$abstiegsplaetze(staffel, ks))

    df <- rl$rl_abstiegsprognose(staffel, mk_ergebnis(teams), m)
    expect_equal(sum(df$Abstieg), erwartet, tolerance = 1e-9, info = staffel)
  }
})

test_that("die Invariante haelt auch bei ungleichverteilter Prognose", {
  # Die Aussage darf nicht an der Gleichverteilung haengen: Sie folgt
  # allein daraus, dass jede PLATZSPALTE auf 1 summiert. Eine Prognose, in
  # der jedes Team einen festen Platz belegt, ist der Gegenbeweis gegen
  # einen Test, der nur mit 1/n zufaellig aufgeht.
  rl <- new.env()
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = rl)
  source(test_path("..", "..", "RCode", "rl_abstiegskopplung.R"), local = rl)

  m <- matrix(0, nrow = 5, ncol = 5,
              dimnames = list(rl$STAFFELN, as.character(0:4)))
  m["SuedWest", "1"] <- 7000
  m["SuedWest", "2"] <- 3000
  m["Nord", "1"] <- 10000
  m["West", "1"] <- 10000
  # 1.3 + 1 + 1 = 3.3; Nordost traegt 0.7.
  m["Nordost", "0"] <- 3000
  m["Nordost", "1"] <- 7000
  m["Bayern", "0"] <- 10000

  # Permutationsmatrix: Team i belegt sicher Platz i.
  prognose <- diag(18)
  dimnames(prognose) <- list(paste0("T", 1:18), as.character(1:18))

  verteilung <- rl$absteiger_verteilung(m)
  ks <- as.numeric(colnames(verteilung))
  erwartet <- sum(verteilung["SuedWest", ] * rl$abstiegsplaetze("SuedWest", ks))

  df <- rl$rl_abstiegsprognose("SuedWest", prognose, m)
  expect_equal(sum(df$Abstieg), erwartet, tolerance = 1e-9)
  # 3 + k mit P(k=1) = 0.7 und P(k=2) = 0.3: E = 4.3.
  expect_equal(erwartet, 4.3, tolerance = 1e-12)
})

test_that("Bayern summiert exakt auf zwei Absteiger und zwei Releganten", {
  # PFLICHTTEST (Vorgabe des Nutzers). Bayern ist entkoppelt: Die zwei
  # Letzten steigen direkt ab, die zwei davor gehen in die Relegation. Hier
  # gibt es keinen Erwartungswert, der schwanken koennte -- beide Summen
  # sind exakt 2, unabhaengig von der 3. Liga und von der Ligagroesse.
  #
  # Die Summen duerfen NICHT verrechnet werden: 2 und 2, nicht 4 in einer
  # Spalte. Die Relegation wird bewusst nicht aufgeloest (wir simulieren
  # die Bayernligen nicht).
  rl <- new.env()
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = rl)
  source(test_path("..", "..", "RCode", "rl_abstiegskopplung.R"), local = rl)

  bauen <- function(k_bayern) {
    m <- matrix(0, nrow = 5, ncol = 5,
                dimnames = list(rl$STAFFELN, as.character(0:4)))
    m["Bayern", as.character(k_bayern)] <- 1000
    m["Nord", as.character(4 - k_bayern)] <- 1000
    for (s in c("Nordost", "West", "SuedWest")) m[s, "0"] <- 1000
    m
  }

  # 2026/27 spielt Bayern mit 19 Vereinen; 18 muss ebenso tragen.
  for (teams in c(18L, 19L)) {
    for (k in 0:4) {
      df <- rl$rl_abstiegsprognose("Bayern", mk_ergebnis(teams), bauen(k))

      expect_identical(colnames(df), c("Relegation", "Abstieg"))
      expect_equal(sum(df$Abstieg), 2, tolerance = 1e-9,
                   info = paste(teams, "Teams, k =", k))
      expect_equal(sum(df$Relegation), 2, tolerance = 1e-9,
                   info = paste(teams, "Teams, k =", k))
    }
  }
})

test_that("Bayerns Relegation trifft die zwei Plaetze VOR den Absteigern", {
  # Relativ gerechnet: n-3 und n-2 (Modellannahmen 5.4). Bei 19 Teams also
  # die Plaetze 16 und 17, direkt ab Platz 18 der Abstieg. Feste
  # Platznummern (17/18, aus der Regeldoku) waeren bei 19 Vereinen um eins
  # verschoben -- und niemand saehe es.
  rl <- new.env()
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = rl)
  source(test_path("..", "..", "RCode", "rl_abstiegskopplung.R"), local = rl)

  m <- matrix(0, nrow = 5, ncol = 5,
              dimnames = list(rl$STAFFELN, as.character(0:4)))
  m["Bayern", "0"] <- 1000
  m["Nord", "4"] <- 1000
  for (s in c("Nordost", "West", "SuedWest")) m[s, "0"] <- 1000

  # Team i belegt sicher Platz i, 19 Teams.
  prognose <- diag(19)
  dimnames(prognose) <- list(paste0("T", 1:19), as.character(1:19))

  df <- rl$rl_abstiegsprognose("Bayern", prognose, m)

  expect_identical(df[c("T16", "T17"), "Relegation"], c(1, 1))
  expect_identical(df[c("T18", "T19"), "Abstieg"], c(1, 1))
  # Und keine Ueberschneidung: Wer absteigt, ist nicht in der Relegation.
  expect_identical(df[c("T18", "T19"), "Relegation"], c(0, 0))
  expect_identical(df[c("T16", "T17"), "Abstieg"], c(0, 0))
  expect_identical(df["T15", "Relegation"], 0)
})

# ===========================================================================
# 3. Navigation: zweistufig, drei Gruppen, Methodik separat
# ===========================================================================

test_that(".nav_groups bildet drei Gruppen in Registry-Reihenfolge", {
  gen <- source_generator()
  gruppen <- gen$.nav_groups()

  expect_identical(vapply(gruppen, function(g) g$group, character(1)),
                   c("Herren", "Frauen", "Regionalliga"))
  expect_length(gruppen[[1]]$items, 3)
  expect_length(gruppen[[2]]$items, 2)
  # Fuenf Staffeln plus die Seite "Aufstieg in die 3. Liga", die der
  # Nutzer bewusst unter "Regionalliga" haengt statt in eine eigene Gruppe.
  expect_length(gruppen[[3]]$items, 6)
})

test_that("jede Liga steht in genau der Gruppe ihrer Registry", {
  # Gruppenzugehoerigkeit, nicht nur Vorhandensein der Links: Ein Test, der
  # nur prueft, dass "rl-nord.html" irgendwo im HTML steht, besteht auch,
  # wenn die Liga unter "Frauen" haengt.
  gen <- source_generator()
  gruppen <- gen$.nav_groups()

  slugs_je_gruppe <- lapply(gruppen, function(g) {
    vapply(g$items, function(i) i$slug, character(1))
  })
  names(slugs_je_gruppe) <- vapply(gruppen, function(g) g$group, character(1))

  expect_identical(slugs_je_gruppe$Herren,
                   c("index", "2-bundesliga", "3-liga"))
  expect_identical(slugs_je_gruppe$Frauen,
                   c("frauen-bundesliga", "2-frauen-bundesliga"))
  expect_identical(slugs_je_gruppe$Regionalliga,
                   c(RL_SLUGS, AUFSTIEGSSEITE_SLUG))
})

test_that("das Navigations-HTML ordnet die RL-Links der Regionalliga-Zeile zu", {
  # Geprueft wird die gerenderte STRUKTUR: Die fuenf RL-Links muessen in
  # DERSELBEN nav-row stehen wie das Gruppenlabel "Regionalliga" -- und
  # keiner davon in der Herren- oder Frauen-Zeile.
  gen <- source_generator()
  html <- gen$.nav_html("index")

  zeilen <- regmatches(
    html,
    gregexpr('<div class="nav-row">.*?</div>', html)
  )[[1]]

  gruppe_von <- function(zeile) {
    sub('.*<span class="nav-group">(.*?)</span>.*', "\\1", zeile)
  }
  labels <- vapply(zeilen, gruppe_von, character(1), USE.NAMES = FALSE)

  # Drei Ligagruppen plus die label-lose Methodik-Zeile.
  expect_identical(labels, c("Herren", "Frauen", "Regionalliga", ""))

  # Die fuenf Staffeln UND die Aufstiegsseite -- sie haengt bewusst hier
  # und nicht in einer eigenen Gruppe.
  rl_zeile <- zeilen[labels == "Regionalliga"]
  for (slug in c(RL_SLUGS, AUFSTIEGSSEITE_SLUG)) {
    expect_match(rl_zeile, paste0('href="', slug, '.html"'), fixed = TRUE,
                 info = slug)
  }

  # Kein RL-Link verirrt sich in eine andere Zeile.
  for (andere in zeilen[labels != "Regionalliga"]) {
    for (slug in c(RL_SLUGS, AUFSTIEGSSEITE_SLUG)) {
      expect_no_match(andere, paste0('href="', slug, '.html"'), fixed = TRUE,
                      info = slug)
    }
  }
})

test_that("Methodik bleibt eine eigene, gruppenlose Zeile", {
  gen <- source_generator()
  html <- gen$.nav_html("methodik")

  zeilen <- regmatches(
    html,
    gregexpr('<div class="nav-row">.*?</div>', html)
  )[[1]]
  methodik_zeile <- zeilen[grepl("methodik.html", zeilen, fixed = TRUE)]

  expect_length(methodik_zeile, 1)
  expect_match(methodik_zeile, '<span class="nav-group"></span>', fixed = TRUE)
  expect_match(methodik_zeile, 'aria-current="page"', fixed = TRUE)
})

# ===========================================================================
# 4. Seiten: zehn Liga-Seiten plus Methodik
# ===========================================================================

# Vollstaendige Ergebnisliste fuer alle zehn Ligen inklusive der
# Sonderlaeufe (Aufstiegstabellen ohne Zweitvertretungen) und der
# berechneten RL-Spalten.
alle_ergebnisse <- function() {
  ergebnisse <- list(
    bundesliga = mk_ergebnis(18),
    zweite_bundesliga = mk_ergebnis(18),
    dritte_liga = mk_ergebnis(20),
    dritte_liga_aufstieg = mk_ergebnis(20),
    frauen_bundesliga = mk_ergebnis(14),
    zweite_frauen_bundesliga = mk_ergebnis(14),
    zweite_frauen_bundesliga_aufstieg = mk_ergebnis(14)
  )

  teams <- paste0("T", seq_len(18))
  for (key in RL_SCHLUESSEL) {
    ergebnisse[[key]] <- mk_ergebnis(18)
    # Die berechnete Abstiegsspalte: ein data.frame in genau der Form, die
    # rl_abstiegsprognose() liefert.
    ergebnisse[[paste0(key, "_abstieg")]] <-
      if (identical(key, "rl_bayern")) {
        data.frame(Relegation = rep(2 / 18, 18), Abstieg = rep(2 / 18, 18),
                   row.names = teams)
      } else {
        data.frame(Abstieg = rep(3 / 18, 18), row.names = teams)
      }
  }
  # Nord und Bayern: berechnete Aufstiegsspalte aus den Aufstiegsspielen.
  # Die Spalte heisst wie bei rl_aufstiegsprognose() "Aufstieg"; sie steht
  # als EXTRA-Wert rechts neben der Meisterspalte.
  for (key in RL_AUFSTIEGSSPIELE) {
    ergebnisse[[paste0(key, "_aufstieg")]] <-
      data.frame(Aufstieg = rep(0.5 / 18, 18), row.names = teams)
  }
  ergebnisse
}

test_that("generate_static_site schreibt zehn Liga-Seiten und die Methodik", {
  gen <- source_generator()
  out <- withr::local_tempdir()

  paths <- gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = alle_ergebnisse()
  )

  # Zehn Liga-Seiten, die Aufstiegsseite und Methodik.
  expect_length(paths, 12)
  for (f in c("index.html", "2-bundesliga.html", "3-liga.html",
              "frauen-bundesliga.html", "2-frauen-bundesliga.html",
              paste0(RL_SLUGS, ".html"),
              paste0(AUFSTIEGSSEITE_SLUG, ".html"), "methodik.html")) {
    expect_true(file.exists(file.path(out, f)), info = f)
  }
})

test_that("jede Regionalliga-Seite traegt ihren eigenen Titel", {
  # Zehn Seiten aus einer Schleife: Ein vertauschter Index faellt sonst
  # nicht auf, weil alle Seiten gleich aussehen.
  gen <- source_generator()
  out <- withr::local_tempdir()

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = alle_ergebnisse()
  )

  erwartet <- c("rl-nord" = "Nord", "rl-nordost" = "Nordost",
                "rl-west" = "West", "rl-suedwest" = "SüdWest",
                "rl-bayern" = "Bayern")
  for (slug in names(erwartet)) {
    html <- paste(readLines(file.path(out, paste0(slug, ".html")),
                            warn = FALSE), collapse = "\n")
    expect_match(html,
                 paste0("<title>30 Punkte · ", erwartet[[slug]], "</title>"),
                 fixed = TRUE, info = slug)
    expect_match(html, 'aria-current="page"', fixed = TRUE, info = slug)
  }
})

test_that("die Bayern-Seite zeigt Relegation und Abstieg als zwei Spalten", {
  # Ende zu Ende: Die zwei Groessen duerfen nicht zu einer Zahl
  # verschmelzen. Gemessen an Werten, die sich unterscheiden -- waeren sie
  # gleich, bewiese die Tabelle nichts.
  gen <- source_generator()
  out <- withr::local_tempdir()

  ergebnisse <- alle_ergebnisse()
  ergebnisse$rl_bayern_abstieg <- data.frame(
    Relegation = rep(0.11, 18),
    Abstieg = rep(0.22, 18),
    row.names = paste0("T", seq_len(18))
  )

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = ergebnisse
  )

  html <- paste(readLines(file.path(out, "rl-bayern.html"), warn = FALSE),
                collapse = "\n")

  expect_match(html, "Relegation", fixed = TRUE)
  expect_match(html, "<td>11</td><td>22</td>", fixed = TRUE)
  # Nicht zu 33 % addiert.
  expect_no_match(html, "<td>33</td>", fixed = TRUE)
})

test_that("die Nord-Seite zeigt oben Meister und Aufstieg nebeneinander", {
  # Ende zu Ende fuer das GEMISCHTE Panel: Die Meisterspalte kommt als
  # Platzsumme aus der Prognosematrix (1/18 = 6 %), die Aufstiegsspalte
  # unveraendert aus dem berechneten Objekt. Die Zahlen sind bewusst
  # verschieden, sonst bewiese die Tabelle nichts.
  gen <- source_generator()
  out <- withr::local_tempdir()

  ergebnisse <- alle_ergebnisse()
  ergebnisse$rl_nord_aufstieg <- data.frame(
    Aufstieg = rep(0.37, 18), row.names = paste0("T", seq_len(18))
  )

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = ergebnisse
  )

  html <- paste(readLines(file.path(out, "rl-nord.html"), warn = FALSE),
                collapse = "\n")

  expect_match(html, "Meister", fixed = TRUE)
  # 6 % Meister, 37 % Aufstieg -- in dieser Reihenfolge, in einer Zeile.
  expect_match(html, "<td>6</td><td>37</td>", fixed = TRUE)
})

test_that("die berechnete Abstiegsspalte landet unveraendert in der Tabelle", {
  # Der schaerfste Test des `computed`-Pfades: Der Wert darf NICHT ueber
  # Platzspalten summiert werden. Bei einer gleichverteilten Prognose ueber
  # 18 Plaetze waere jede Platzsumme ein Vielfaches von 1/18 (6, 11, 17 %)
  # -- 41 % kann nur durchgereicht sein.
  gen <- source_generator()
  out <- withr::local_tempdir()

  ergebnisse <- alle_ergebnisse()
  ergebnisse$rl_nord_abstieg <- data.frame(
    Abstieg = rep(0.41, 18), row.names = paste0("T", seq_len(18))
  )

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = ergebnisse
  )

  html <- paste(readLines(file.path(out, "rl-nord.html"), warn = FALSE),
                collapse = "\n")
  expect_match(html, "<td>41</td>", fixed = TRUE)
})

# ===========================================================================
# 4a. Die Seite "Aufstieg in die 3. Liga"
# ===========================================================================
#
# ENTSCHIEDEN (Nutzer, 2026-09-07): Variante 2 aus dem Kopfentwurf --
# Randsummen, keine Matrix. Navigation unter "Regionalliga".
#
# Je Team eine Zeile mit vier Spalten:
#
#   Team | P(Meister) | P(Aufstieg) | Siegquote
#
# P(Meister) ist Spalte 1 der jeweiligen Prognose, P(Aufstieg) kommt aus
# rl_aufstiegsprognose(), und die Siegquote ist deren Quotient:
#
#   Siegquote = P(Aufstieg) / P(Meister)
#
# Das ist die ueber den Gegner ausintegrierte Zweikampfquote -- also genau
# die Zahl, die die 18x19-Matrix aus Variante 1 zusammenfasst. Fuer die
# Direktaufsteiger ist sie 1, weil dort P(Aufstieg) = P(Meister) gilt.
#
# WAS BEWUSST NICHT GEBAUT WIRD: keine Paarungsmatrix, keine Liste der
# wahrscheinlichsten Paarungen. Begruendung des Nutzers: "Fuer naechste
# Saison muessen wir eh vermutlich neue Aufstiegsregeln implementieren, und
# dann bauen wir halt auch die Aufstiegsseite passend um." Also die
# einfachste tragfaehige Form, kein Vorbau fuer Regeln, die es noch nicht
# gibt. Wer hier spaeter eine Matrix ergaenzt, faengt bewusst neu an --
# diese Tests stehen ihm nicht im Weg, weil sie nur die vier Spalten
# festhalten.
#
# DIE UNDEFINIERTE STELLE: Bei P(Meister) = 0 ist der Quotient undefiniert
# (0/0). Festgelegt: Die Zelle bleibt LEER. Weder 0 noch NaN noch "100 %".
#
#   Eine 0 waere eine Aussage ueber die Spielstaerke ("verliert das
#   Aufstiegsspiel sicher"), die aus den Daten nicht folgt -- das Team
#   erreicht das Spiel ja gar nicht. NaN waere ein sichtbarer Rechenfehler
#   auf einer veroeffentlichten Seite. Leer sagt genau das Richtige: Zu
#   dieser Frage weiss das Modell nichts, weil sie sich nicht stellt.
#
#   Dieselbe Konvention wie in der Heatmap, wo eine Null-Zelle leer bleibt
#   (render_heatmap / .heatmap_cell).
#
# SAISONABHAENGIGKEIT -- die Falle: Die Paarung Nord-Bayern gilt fuer
# 2026/27 und NUR dafuer. Wer den dritten Direktplatz bekommt, beschliesst
# das DFB-Praesidium jaehrlich (Regeldoku 3.3). Die Seite darf die Paarung
# deshalb nicht verdrahten, sondern muss aufstiegsmodus(season) folgen.
# Ein Test injiziert eine ANDERE Rotation und verlangt eine andere
# Playoff-Staffel -- ohne Fakten fuer kuenftige Saisons zu erfinden: Die
# injizierte Rotation ist Testeingabe, keine Behauptung ueber 2027/28.
# Eine unbekannte Saison muss abbrechen.

# Prognosematrix mit vorgegebenen Meisterchancen. Nur Spalte 1 traegt die
# Aussage; der Rest ist Fuellmasse, damit die Matrix quadratisch bleibt.
mk_meister <- function(praefix, p_meister) {
  n <- length(p_meister)
  m <- matrix(0, nrow = n, ncol = n,
              dimnames = list(paste0(praefix, seq_len(n)),
                              as.character(seq_len(n))))
  m[, 1] <- p_meister
  m
}

# Realistische, ungleiche Meisterchancen -- ein versehentliches "alle
# gleich" wuerde damit auffallen. Nord und Bayern spielen 2026/27 mit 18
# bzw. 19 Vereinen.
aufstiegs_prognosen <- function() {
  list(
    Nord     = mk_meister("N", c(0.42, 0.31, 0.15, 0.08, 0.04, rep(0, 13))),
    Nordost  = mk_meister("O", c(0.50, 0.30, 0.20, rep(0, 15))),
    West     = mk_meister("W", c(0.45, 0.35, 0.20, rep(0, 15))),
    SuedWest = mk_meister("S", c(0.60, 0.25, 0.15, rep(0, 15))),
    Bayern   = mk_meister("B", c(0.55, 0.20, 0.12, 0.09, 0.04, rep(0, 14)))
  )
}

# Ungleiche Zweikampfquoten: Zeilen = Nord (in STAFFELN frueher), Spalten
# = Bayern. Eine konstante Matrix wuerde einen Positionsfehler in der
# Doppelsumme nicht sichtbar machen.
aufstiegs_p_sieg <- function(prognosen = aufstiegs_prognosen()) {
  n <- nrow(prognosen$Nord)
  m <- nrow(prognosen$Bayern)
  matrix(seq(0.2, 0.8, length.out = n * m), nrow = n, ncol = m,
         dimnames = list(rownames(prognosen$Nord),
                         rownames(prognosen$Bayern)))
}

# --- Die Seite existiert und haengt unter "Regionalliga" --------------------

test_that("die Aufstiegsseite steht in der Regionalliga-Gruppe der Navigation", {
  # Entscheidung des Nutzers: keine eigene Gruppe. Geprueft wird die
  # ZUGEHOERIGKEIT, nicht nur das Vorhandensein des Links -- ein Test auf
  # "rl-aufstieg.html steht irgendwo im HTML" bestuende auch, wenn die
  # Seite unter "Frauen" haengt.
  gen <- source_generator()
  gruppen <- gen$.nav_groups()

  namen <- vapply(gruppen, function(g) g$group, character(1))
  expect_true("Regionalliga" %in% namen)

  rl_gruppe <- gruppen[[which(namen == "Regionalliga")]]
  slugs <- vapply(rl_gruppe$items, function(i) i$slug, character(1))

  expect_true(AUFSTIEGSSEITE_SLUG %in% slugs)
  # Fuenf Staffeln plus die Aufstiegsseite, und die Seite steht hinter den
  # Staffeln -- sie fasst sie zusammen, sie leitet sie nicht ein.
  expect_identical(slugs, c(RL_SLUGS, AUFSTIEGSSEITE_SLUG))
})

test_that("die Aufstiegsseite wird mitgerendert und traegt ihren Titel", {
  gen <- source_generator()
  out <- withr::local_tempdir()

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = alle_ergebnisse()
  )

  pfad <- file.path(out, paste0(AUFSTIEGSSEITE_SLUG, ".html"))
  expect_true(file.exists(pfad))

  html <- paste(readLines(pfad, warn = FALSE), collapse = "\n")
  expect_match(html, "Aufstieg in die 3. Liga", fixed = TRUE)
  expect_match(html, 'aria-current="page"', fixed = TRUE)
})

# --- Die vier Spalten -------------------------------------------------------

test_that("die Aufstiegstabelle traegt genau vier Spalten", {
  # Team, P(Meister), P(Aufstieg), Siegquote. Nicht mehr -- die
  # Paarungsmatrix ist bewusst nicht Teil dieser Seite.
  views <- source_views()$league_views()
  v <- views[[AUFSTIEGSSEITE_SLUG]]

  expect_identical(v$columns, c("Meister", "Aufstieg", "Siegquote"))
})

test_that("die Aufstiegsseite deckt alle fuenf Staffeln ab", {
  # Auch die drei Direktaufsteiger stehen dort -- die Seite zeigt den
  # ganzen Weg in die 3. Liga, nicht nur die Aufstiegsspiele.
  views <- source_views()$league_views()
  v <- views[[AUFSTIEGSSEITE_SLUG]]

  expect_identical(v$staffeln, c("Nord", "Nordost", "West", "SuedWest",
                                 "Bayern"))
})

# --- Direktaufsteiger: Meister = Aufstieg, Siegquote 100 % ------------------

test_that("bei den Direktaufsteigern sind Meister und Aufstieg exakt gleich", {
  # Die Rechtfertigung dafuer, dass die Siegquote dort entfaellt: Es gibt
  # kein Spiel, das noch zu gewinnen waere. Exakt gleich, nicht ungefaehr
  # -- rl_aufstiegsprognose() reicht P(Meister) unveraendert durch.
  auf <- source_aufstieg()
  prognosen <- aufstiegs_prognosen()

  for (staffel in c("Nordost", "West", "SuedWest")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026)
    expect_identical(unname(df$Aufstieg),
                     unname(prognosen[[staffel]][, 1]), info = staffel)
  }
})

test_that("die Siegquote der Direktaufsteiger ist exakt eins, wo es einen Meister gibt", {
  # Der Quotient P(Aufstieg)/P(Meister) ist dort definitionsgemaess 1. Die
  # Seite darf ihn als "100 %" zeigen oder weglassen -- was sie NICHT darf,
  # ist eine andere Zahl.
  auf <- source_aufstieg()
  prognosen <- aufstiegs_prognosen()

  for (staffel in c("Nordost", "West", "SuedWest")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026)
    p_meister <- prognosen[[staffel]][, 1]
    hat_chance <- p_meister > 0

    quote <- unname(df$Aufstieg[hat_chance]) / unname(p_meister[hat_chance])
    expect_equal(quote, rep(1, sum(hat_chance)), tolerance = 1e-12,
                 info = staffel)
  }
})

# --- Nord und Bayern: die Doppelsumme und ihr Quotient ----------------------

test_that("die Siegquote von Nord und Bayern liegt strikt zwischen null und eins", {
  # Der inhaltliche Kern der Spalte: Wer Meister wird, muss noch zwei
  # Spiele gewinnen -- also weniger als 1. Und die Gegner sind nicht
  # unschlagbar -- also mehr als 0. Genau eine Zahl dazwischen macht die
  # Spalte ueberhaupt sinnvoll.
  auf <- source_aufstieg()
  prognosen <- aufstiegs_prognosen()
  p_sieg <- aufstiegs_p_sieg(prognosen)

  for (staffel in c("Nord", "Bayern")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026, p_sieg = p_sieg)
    p_meister <- prognosen[[staffel]][, 1]
    hat_chance <- p_meister > 0

    quote <- unname(df$Aufstieg[hat_chance]) / unname(p_meister[hat_chance])
    expect_true(all(quote > 0), info = staffel)
    expect_true(all(quote < 1), info = staffel)
  }
})

test_that("die Siegquote ist wirklich die ausintegrierte Zweikampfquote", {
  # Nicht nur ein Wertebereich, sondern die Zahl selbst: Bei einer
  # konstanten Zweikampfquote q muss der Quotient fuer JEDES Nord-Team
  # exakt q sein, weil die Meisterchancen der Gegenstaffel auf 1 summieren.
  # Damit ist die Formel gepinnt, nicht nur ihr Vorzeichen.
  auf <- source_aufstieg()
  prognosen <- aufstiegs_prognosen()

  q <- 0.37
  p_sieg <- matrix(q, nrow = nrow(prognosen$Nord),
                   ncol = nrow(prognosen$Bayern),
                   dimnames = list(rownames(prognosen$Nord),
                                   rownames(prognosen$Bayern)))

  df_nord <- auf$rl_aufstiegsprognose("Nord", prognosen, 2026,
                                      p_sieg = p_sieg)
  p_meister <- prognosen$Nord[, 1]
  hat_chance <- p_meister > 0

  quote <- unname(df_nord$Aufstieg[hat_chance]) / unname(p_meister[hat_chance])
  expect_equal(quote, rep(q, sum(hat_chance)), tolerance = 1e-12)

  # Und die Gegenrichtung: Ueber zwei Spiele gibt es kein Remis, Bayern
  # traegt also 1 - q.
  df_bayern <- auf$rl_aufstiegsprognose("Bayern", prognosen, 2026,
                                        p_sieg = p_sieg)
  p_meister_b <- prognosen$Bayern[, 1]
  hat_chance_b <- p_meister_b > 0
  quote_b <- unname(df_bayern$Aufstieg[hat_chance_b]) /
    unname(p_meister_b[hat_chance_b])
  expect_equal(quote_b, rep(1 - q, sum(hat_chance_b)), tolerance = 1e-12)
})

test_that("ohne Meisterchance ist die Aufstiegschance exakt null", {
  # Die Vorbedingung fuer die Leer-Regel: Wo P(Meister) = 0 ist, muss auch
  # P(Aufstieg) IDENTISCH 0 sein -- nicht 1e-18. Sonst zeigte die Seite
  # ein "<1" fuer ein Team, das rechnerisch gar nicht aufsteigen kann, und
  # der Quotient waere kein 0/0, sondern eine erfundene Zahl.
  auf <- source_aufstieg()
  prognosen <- aufstiegs_prognosen()
  p_sieg <- aufstiegs_p_sieg(prognosen)

  df <- auf$rl_aufstiegsprognose("Nord", prognosen, 2026, p_sieg = p_sieg)
  ohne_chance <- prognosen$Nord[, 1] == 0
  expect_gt(sum(ohne_chance), 0)   # der Fall kommt in der Fixture vor

  expect_identical(unname(df$Aufstieg[ohne_chance]),
                   rep(0, sum(ohne_chance)))
})

test_that("die Siegquote bleibt leer, wo es keine Meisterchance gibt", {
  # FESTGELEGT: leer, nicht 0 und nicht NaN. Eine 0 waere eine Aussage
  # ueber die Spielstaerke, die aus den Daten nicht folgt -- das Team
  # erreicht das Aufstiegsspiel ja gar nicht. NaN waere ein sichtbarer
  # Rechenfehler auf einer veroeffentlichten Seite.
  gen <- source_generator()

  # 0/0 muss zur leeren Zelle werden, jeder definierte Wert bleibt.
  expect_identical(gen$.siegquote(0, 0), "")
  expect_identical(gen$.siegquote(0.2, 0.4), gen$prozent(0.5))

  # Auch der Grenzfall "Aufstieg > 0, Meister = 0" darf nicht durchrutschen
  # -- er ist rechnerisch unmoeglich und deshalb ein Fehler in den Daten,
  # keine Unendlichkeit auf der Seite.
  expect_identical(gen$.siegquote(0.1, 0), "")
})

test_that("die gerenderte Seite laesst die Zelle ohne Meisterchance leer", {
  # Ende zu Ende: Weder "0" noch "NaN" noch "Inf" darf im HTML stehen.
  gen <- source_generator()
  out <- withr::local_tempdir()

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = alle_ergebnisse()
  )

  html <- paste(readLines(file.path(out, paste0(AUFSTIEGSSEITE_SLUG, ".html")),
                          warn = FALSE), collapse = "\n")

  expect_no_match(html, "NaN", fixed = TRUE)
  expect_no_match(html, "Inf", fixed = TRUE)
  # Eine leere Zelle, nicht eine mit Inhalt.
  expect_match(html, "<td></td>", fixed = TRUE)
})

# --- Die beiden Pflicht-Invarianten -----------------------------------------

test_that("Nord und Bayern stellen zusammen genau einen Aufsteiger", {
  # PFLICHTTEST (Vorgabe des Nutzers). Genau eine der beiden Staffeln
  # gewinnt die Aufstiegsspiele, also summiert P(Aufstieg) ueber BEIDE
  # Staffeln auf exakt 1.
  #
  # Das ist keine Zufallseigenschaft der Zahlen: P(X Meister) summiert je
  # Staffel auf 1, und p_sieg[x, y] + (1 - p_sieg[x, y]) = 1 fuer jede
  # Paarung -- ueber zwei Spiele gibt es keinen dritten Ausgang. Die
  # Doppelsumme zerlegt damit die Eins vollstaendig.
  #
  # Toleranz 1e-9, nicht 0.01: Eine Doppelsumme, die Masse verliert (etwa
  # weil eine Zeile ueber die Position statt ueber den Namen zugeordnet
  # wird), faellt bei weiter Toleranz nicht auf.
  auf <- source_aufstieg()
  prognosen <- aufstiegs_prognosen()
  p_sieg <- aufstiegs_p_sieg(prognosen)

  df_nord <- auf$rl_aufstiegsprognose("Nord", prognosen, 2026,
                                      p_sieg = p_sieg)
  df_bayern <- auf$rl_aufstiegsprognose("Bayern", prognosen, 2026,
                                        p_sieg = p_sieg)

  expect_equal(sum(df_nord$Aufstieg) + sum(df_bayern$Aufstieg), 1,
               tolerance = 1e-9)

  # Und beide Anteile sind echt positiv -- die Eins liegt nicht ganz auf
  # einer Seite, sonst pruefte die Summe nichts.
  expect_gt(sum(df_nord$Aufstieg), 0)
  expect_gt(sum(df_bayern$Aufstieg), 0)
})

test_that("jede Direktaufsteiger-Staffel stellt genau einen Aufsteiger", {
  # PFLICHTTEST (Vorgabe des Nutzers). Genau ein Team wird Meister, und der
  # Meister steigt auf -- die Spalte summiert je Staffel auf exakt 1.
  auf <- source_aufstieg()
  prognosen <- aufstiegs_prognosen()

  for (staffel in c("Nordost", "West", "SuedWest")) {
    df <- auf$rl_aufstiegsprognose(staffel, prognosen, 2026)
    expect_equal(sum(df$Aufstieg), 1, tolerance = 1e-9, info = staffel)
  }
})

test_that("ueber alle fuenf Staffeln steigen genau vier Teams auf", {
  # Die Zusammenschau beider Invarianten -- und die Zahl, die Par. 55b
  # DFB-SpO vorgibt: drei Direktaufsteiger plus einer aus den
  # Aufstiegsspielen. Waere eine Staffel doppelt gezaehlt oder eine
  # vergessen, stuende hier 3 oder 5.
  auf <- source_aufstieg()
  prognosen <- aufstiegs_prognosen()
  p_sieg <- aufstiegs_p_sieg(prognosen)

  summe <- sum(vapply(c("Nord", "Nordost", "West", "SuedWest", "Bayern"),
                      function(s) {
                        df <- auf$rl_aufstiegsprognose(s, prognosen, 2026,
                                                       p_sieg = p_sieg)
                        sum(df$Aufstieg)
                      }, numeric(1)))

  expect_equal(summe, 4, tolerance = 1e-9)
})

# --- Saisonabhaengigkeit: die Paarung ist nicht verdrahtet ------------------

test_that("die Seite folgt einer injizierten Rotation statt der verdrahteten Paarung", {
  # DIE FALLE: Nord gegen Bayern gilt fuer 2026/27 und NUR dafuer. Wer den
  # dritten Direktplatz bekommt, beschliesst das DFB-Praesidium jaehrlich.
  #
  # Der Test injiziert eine ANDERE Rotation und verlangt eine andere
  # Playoff-Paarung. Die injizierte Rotation ist Testeingabe, KEINE
  # Behauptung darueber, wer 2027/28 wirklich dran ist -- deshalb eine
  # Saison, die in AUFSTIEGSROTATION bewusst nicht steht.
  auf <- source_aufstieg()

  # Stand 2026/27: Nordost direkt, Nord gegen Bayern.
  modus_2026 <- auf$aufstiegsmodus(2026)
  expect_setequal(modus_2026$direkt, c("West", "SuedWest", "Nordost"))
  expect_setequal(modus_2026$playoff, c("Nord", "Bayern"))

  # Injiziert: Nord traegt den Rotationsplatz -- dann spielen Nordost und
  # Bayern.
  modus_alt <- auf$aufstiegsmodus(2027, rotation = c("2027" = "Nord"))
  expect_setequal(modus_alt$direkt, c("West", "SuedWest", "Nord"))
  expect_setequal(modus_alt$playoff, c("Nordost", "Bayern"))

  # Und der dritte Fall, damit nicht bloss zwei Zustaende geprueft sind.
  modus_bayern <- auf$aufstiegsmodus(2027, rotation = c("2027" = "Bayern"))
  expect_setequal(modus_bayern$playoff, c("Nord", "Nordost"))
})

test_that("die Aufstiegsprognose folgt der injizierten Rotation", {
  # Nicht nur der Modus, sondern die RECHNUNG: Unter einer Rotation, in der
  # Nord direkt aufsteigt, muss Nord P(Meister) bekommen -- und Nordost
  # stattdessen die Doppelsumme gegen Bayern. Waere die Paarung
  # verdrahtet, kaeme hier weiterhin die Nord-Bayern-Rechnung heraus.
  auf <- source_aufstieg()
  prognosen <- aufstiegs_prognosen()
  rotation <- c("2027" = "Nord")

  df_nord <- auf$rl_aufstiegsprognose("Nord", prognosen, 2027,
                                      rotation = rotation)
  expect_identical(unname(df_nord$Aufstieg),
                   unname(prognosen$Nord[, 1]))

  # Nordost bestreitet jetzt die Aufstiegsspiele -- gegen Bayern. Zeilen =
  # Nordost (in STAFFELN frueher als Bayern), Spalten = Bayern.
  p_sieg <- matrix(0.5, nrow = nrow(prognosen$Nordost),
                   ncol = nrow(prognosen$Bayern),
                   dimnames = list(rownames(prognosen$Nordost),
                                   rownames(prognosen$Bayern)))
  df_nordost <- auf$rl_aufstiegsprognose("Nordost", prognosen, 2027,
                                         p_sieg = p_sieg, rotation = rotation)
  df_bayern <- auf$rl_aufstiegsprognose("Bayern", prognosen, 2027,
                                        p_sieg = p_sieg, rotation = rotation)

  # Halbe Meisterchance, weil jede Paarung 50:50 steht.
  expect_equal(unname(df_nordost$Aufstieg),
               unname(prognosen$Nordost[, 1]) / 2, tolerance = 1e-12)
  # Die Invariante gilt auch unter der anderen Rotation.
  expect_equal(sum(df_nordost$Aufstieg) + sum(df_bayern$Aufstieg), 1,
               tolerance = 1e-9)
})

test_that("eine unbekannte Saison bricht ab, statt die Paarung zu raten", {
  # Der wichtigste Teil der Saisonabhaengigkeit: Fuer 2027/28 ist noch
  # nicht bekannt, wer den Rotationsplatz traegt. Die Seite darf dann NICHT
  # mit dem Vorjahreswert weiterrechnen -- das waere eine Prognose, die
  # falsch ist, ohne dass etwas fehlschlaegt.
  auf <- source_aufstieg()

  expect_error(auf$aufstiegsmodus(2027), "2027")
  expect_error(auf$aufstiegsmodus(2027), "DFB-Praesidium")

  # Auch die ganze Kette bricht ab, nicht erst irgendein Folgeschritt.
  expect_error(
    auf$rl_aufstiegsprognose("Nord", aufstiegs_prognosen(), 2027),
    "2027"
  )
})

test_that("die Aufstiegsseite verdrahtet keine Staffelnamen im Renderer", {
  # Maschineller Schutz gegen die Falle: Stuende "Bayern" oder "Nord" als
  # Playoff-Paarung im Seitengenerator, waere die Seite ab 2027/28 lautlos
  # falsch. Die Namen duerfen dort nur als Anzeigetext vorkommen, nicht als
  # Bedingung.
  #
  # Geprueft wird der Code OHNE Kommentare -- ein Staffelname im Kommentar
  # ist eine Erklaerung, keine Verdrahtung.
  code <- readLines(test_path("..", "..", "RCode", "generate_static_site.R"))
  code <- sub("#.*$", "", code)

  for (muster in c('"Bayern"\\s*(==|%in%)', '(==|%in%)\\s*c?\\(?"Bayern"',
                   '"Nord"\\s*(==|%in%)', '(==|%in%)\\s*c?\\(?"Nord"')) {
    expect_false(any(grepl(muster, code)), info = muster)
  }
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
# validate_league_composition() (RCode/league_processor.R) prueft die Teams
# eines KONKRETEN Laufs gegen league_teams_range(). Diese Tests sichern
# beides ab: dass die Spanne die echten Spielplaene traegt, und dass die
# TeamList sie NICHT traegt.

rl_fixture_teams <- function(liga, saison = 2025) {
  pfad <- test_path("..", "..", "data", "fixture_cache",
                    paste0(liga, "_", saison, ".json"))
  skip_if_not(file.exists(pfad), paste("Fixture fehlt:", basename(pfad)))

  x <- jsonlite::fromJSON(pfad)
  rf <- source_round_filter()
  keep <- rf$is_regular_season_round(x$round)
  unique(c(x$teams_home_name[keep], x$teams_away_name[keep]))
}

test_that("die echten RL-Spielplaene 2025 liegen in der teams_range", {
  # 2025 spielten alle fuenf Staffeln mit 18 Teams. Der Wert wird gemessen,
  # nicht angenommen -- er kommt aus dem committeten Spielplan.
  env <- source_registry()

  for (i in seq_along(RL_IDS)) {
    id <- RL_IDS[[i]]
    teams <- rl_fixture_teams(id)
    spanne <- env$league_teams_range(id)

    expect_identical(length(teams), 18L, info = id)
    expect_gte(length(teams), spanne[[1]])
    expect_lte(length(teams), spanne[[2]])
  }
})

test_that("validate_league_composition nimmt einen echten RL-Spielplan an", {
  # Die Postcondition, die spaeter kippen koennte: Sobald jemand die
  # teams_range enger zieht (etwa auf die TeamList-Zahl oder auf feste 18),
  # scheitert der naechste Livegang an einer Saison mit 19 oder 22 Teams.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "league_processor.R"), local = env)

  for (id in RL_IDS) {
    teams <- lapply(rl_fixture_teams(id), function(nm) list(name = nm))
    ergebnis <- env$validate_league_composition(id, teams)
    expect_true(ergebnis$valid, info = paste(id, ergebnis$message))
    expect_identical(ergebnis$actual_count, 18L, info = id)
  }
})

test_that("die TeamList fuehrt weit mehr Eintraege als eine Staffel Teams hat", {
  # Der Grund, warum die Validierung NICHT gegen die TeamList laufen darf.
  # Geprueft wird der Abstand, nicht nur die Ungleichheit: Er ist gross und
  # strukturell, nicht ein Rundungsfehler.
  env <- source_registry()
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
  env <- source_registry()
  verzeichnis <- test_path("..", "..", "data", "fixture_cache")
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
# 6. Rundenfilter an den echten RL-Spielplaenen
# ===========================================================================

# Der Cache hat 83-87 nur bis 2025; 2026 gibt es dort noch nicht. Die
# 2025er-Spielplaene sind die schaerfste verfuegbare Probe, weil genau dort
# die beiden Fallen liegen:
#
#   Liga 84 wechselte 2025 die Sprache: "Nord - 12" -> "North - 12"
#   Liga 86 schreibt "Suedwest - 12" mit Umlaut im ue
#
# Eine Positivliste (startsWith "Regular Season") haette JEDES dieser Spiele
# verworfen und die Liga leer simuliert -- ohne Fehlermeldung. Das ist der
# Regressionsschutz fuer den Livegang.

test_that("der Rundenfilter behaelt alle Hauptrundenspiele der fuenf RL", {
  rf <- source_round_filter()

  # Gemessen an den committeten Spielplaenen: 34 Spieltage, 18 Teams.
  erwartet_spieltage <- 34L

  for (id in RL_IDS) {
    pfad <- test_path("..", "..", "data", "fixture_cache",
                      paste0(id, "_2025.json"))
    skip_if_not(file.exists(pfad), paste("Fixture fehlt:", id))

    x <- jsonlite::fromJSON(pfad)
    keep <- rf$is_regular_season_round(x$round)

    # Kein Hauptrundenspiel darf verlorengehen: Alles, was nicht als
    # K.-o.-Runde erkannt wird, bleibt drin.
    expect_identical(length(unique(x$round[keep])), erwartet_spieltage,
                     info = id)
    expect_gte(sum(keep), 300L)
  }
})

test_that("Liga 84 ueberlebt den Sprachwechsel Nord -> North", {
  # 2024 hiess der Spieltag "Nord - 12", 2025 "North - 12". Beide muessen
  # durchkommen; eine Positivliste haette beim Wechsel lautlos eine leere
  # Liga erzeugt.
  rf <- source_round_filter()

  for (saison in c(2024, 2025)) {
    pfad <- test_path("..", "..", "data", "fixture_cache",
                      paste0("84_", saison, ".json"))
    skip_if_not(file.exists(pfad))

    x <- jsonlite::fromJSON(pfad)
    keep <- rf$is_regular_season_round(x$round)
    expect_identical(sum(!keep), 0L, info = as.character(saison))
  }

  # Und beide Schreibweisen kommen wirklich vor -- sonst prueft der Test
  # oben nichts.
  labels_2024 <- jsonlite::fromJSON(
    test_path("..", "..", "data", "fixture_cache", "84_2024.json"))$round
  labels_2025 <- jsonlite::fromJSON(
    test_path("..", "..", "data", "fixture_cache", "84_2025.json"))$round
  expect_true(any(grepl("^Nord - ", labels_2024)))
  expect_true(any(grepl("^North - ", labels_2025)))
})

test_that("Liga 86 ueberlebt den Umlaut in Suedwest", {
  rf <- source_round_filter()
  pfad <- test_path("..", "..", "data", "fixture_cache", "86_2025.json")
  skip_if_not(file.exists(pfad))

  x <- jsonlite::fromJSON(pfad)
  # Die Schreibweise steht wirklich mit Umlaut im Spielplan.
  expect_true(any(grepl("dwest - ", x$round)))
  expect_identical(sum(!rf$is_regular_season_round(x$round)), 0L)
})

test_that("Liga 83 verwirft die Relegationsrunde und behaelt den Rest", {
  # Bayern 2025 enthaelt eine "Relegation Round". Sie MUSS raus -- sie ist
  # kein Hauptrundenspiel und wuerde die Tabelle verfaelschen. Alles andere
  # bleibt.
  rf <- source_round_filter()
  pfad <- test_path("..", "..", "data", "fixture_cache", "83_2025.json")
  skip_if_not(file.exists(pfad))

  x <- jsonlite::fromJSON(pfad)
  keep <- rf$is_regular_season_round(x$round)

  expect_identical(unique(x$round[!keep]), "Relegation Round")
  expect_identical(length(unique(x$round[keep])), 34L)
})

test_that("assert_rounds_kept schuetzt jede der fuenf neuen Ligen", {
  # Das Schutznetz aus Phase 0, jetzt scharf: Wuerde eine kuenftige
  # Schreibweise am Filter scheitern, bricht der Lauf mit den beobachteten
  # Labels ab -- statt eine leere Liga zu simulieren.
  rf <- source_round_filter()

  expect_error(
    rf$assert_rounds_kept(306, 0, c("Bayern - 1", "Bayern - 2"),
                          context = "RL Bayern"),
    "Bayern - 1"
  )
  # Kein Abbruch, wenn ueberhaupt keine Spiele angesetzt sind.
  expect_true(rf$assert_rounds_kept(0, 0, character(0)))
})

# ===========================================================================
# 7. Waechter: keine Modellkonstante wandert mit den neuen Ligen nach R
# ===========================================================================

test_that("keine Regionalliga sendet ein eigenes Tormodell", {
  # ADR 0004: Die RL gehoeren zur Wechselgemeinschaft Herren. Ein
  # staffelweiser Intercept wuerde jeden Auf- und Absteiger stillschweigend
  # umskalieren -- und test-modellkonstanten-nur-in-rust.R rot faerben.
  env <- source_registry()

  for (id in RL_IDS) {
    expect_identical(env$goal_model_args(id), list(), info = id)
  }
})
