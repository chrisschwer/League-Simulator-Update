# Zentrale Liga-Registry: die eine Datenquelle fuer alles, was eine Liga
# ausmacht.
#
# Vorher standen die Liga-IDs "78"/"79"/"80" an rund 60 Stellen in RCode/ und
# scripts/ -- als Ligamengen, Namens-Maps (dreifach dupliziert),
# Teamzahl-Erwartungen, Auf-/Abstiegsregeln und sogar in einem
# Dateinamen-Regex. Jede neue Liga haette an jeder dieser Stellen nachgetragen
# werden muessen; eine vergessene faellt nicht auf.
#
# Warum R und nicht YAML: bleibt bei den bestehenden Konventionen, ist ohne
# neue Dependency testbar und kann Ausdruecke tragen.
#
# ALLE ZEHN LIGEN stehen hier, die sieben neuen aber mit `active = FALSE`.
# Der Produktivpfad sieht ueber league_ids() weiterhin nur die drei Altligen;
# der Saisonwechsel und die Validierung kennen die neuen bereits. So ist die
# Struktur an den echten Anforderungen erprobt, bevor sie live gehen.

# --- Modellkonstanten -------------------------------------------------------

# Das Tormodell der Frauen-Ligen. Geschaetzt an 1917 Spielen, out-of-sample
# validiert (ADR 0004, docs/reports/2026-09-05-frauen-tormodell.md).
#
# Die Herren-Werte stehen bewusst NICHT hier: Sie sind die Defaults des
# Rust-Servers, und R soll sie nicht mitsenden -- sonst gaebe es zwei Quellen,
# die auseinanderlaufen koennen (ADR 0002). Nur die Abweichung wird
# uebertragen.
FRAUEN_TORE_SLOPE <- 0.0024058833
FRAUEN_TORE_INTERCEPT <- 1.6527603153

#' Die zehn Ligen und ihre Eigenschaften.
#'
#' Felder je Liga:
#'   api_id        ID bei api-football (String, auch numerisch akzeptiert)
#'   active        Nimmt der Produktivpfad die Liga auf?
#'   family        Wechselgemeinschaft: "herren" oder "frauen" (ADR 0004)
#'   staffel       Nur Regionalligen: die regionale Staffel
#'   slug          Dateiname der erzeugten Seite (ohne .html)
#'   nav_label     Beschriftung in der Navigation
#'   nav_group     Gruppe der zweistufigen Navigation (Phase 5)
#'   display_name  Ausgeschriebener Name fuer Logs und Dialoge
#'   teams_range   Spanne der Teamzahl, keine Gleichheit -- sie schwankt je
#'                 Saison (Frauen-BL 12-14, RL Nord 18-22). Gemessen an den
#'                 Spielplaenen 2019-2025, nur ueber Hauptrundenspiele.
#'   first_season  Erste bei api-football verfuegbare Saison
#'   promotion_to / relegation_to  Ziel-Liga(en); NULL = keine
#'   tore_slope / tore_intercept   Nur wo vom Rust-Default abweichend
league_registry <- function() {
  list(
    bundesliga = list(
      api_id = "78", active = TRUE, family = "herren",
      slug = "index", nav_label = "Bundesliga", nav_group = "Herren",
      display_name = "Bundesliga",
      teams_range = c(18L, 18L), first_season = 2010L,
      promotion_to = NULL, relegation_to = "79",
      promotion_slots = 0L, relegation_slots = 2L, playoff_slots = 1L
    ),
    zweite_bundesliga = list(
      api_id = "79", active = TRUE, family = "herren",
      slug = "2-bundesliga", nav_label = "2. Bundesliga", nav_group = "Herren",
      display_name = "2. Bundesliga",
      teams_range = c(18L, 18L), first_season = 2010L,
      promotion_to = "78", relegation_to = "80",
      promotion_slots = 2L, relegation_slots = 2L, playoff_slots = 1L
    ),
    dritte_liga = list(
      api_id = "80", active = TRUE, family = "herren",
      slug = "3-liga", nav_label = "3. Liga", nav_group = "Herren",
      display_name = "3. Liga",
      teams_range = c(20L, 20L), first_season = 2010L,
      promotion_to = "79",
      # Absteiger verteilen sich auf die fuenf Staffeln nach Stammregion
      # (Spalte Region der TeamList). Vorher stand hier der String
      # "Regional" -- kein Liga-Bezeichner.
      relegation_to = c("83", "84", "85", "86", "87"),
      promotion_slots = 2L, relegation_slots = 4L, playoff_slots = 1L,
      restrictions = "Zweitvertretungen duerfen nicht aufsteigen"
    ),

    # --- Frauen: eigene Wechselgemeinschaft, eigenes Tormodell -------------
    frauen_bundesliga = list(
      api_id = "82", active = FALSE, family = "frauen",
      slug = "frauen-bundesliga", nav_label = "Bundesliga",
      nav_group = "Frauen",
      display_name = "Frauen-Bundesliga",
      teams_range = c(12L, 14L), first_season = 2016L,
      promotion_to = NULL, relegation_to = "1034",
      promotion_slots = 0L, relegation_slots = 2L, playoff_slots = 0L,
      tore_slope = FRAUEN_TORE_SLOPE, tore_intercept = FRAUEN_TORE_INTERCEPT
    ),
    zweite_frauen_bundesliga = list(
      api_id = "1034", active = FALSE, family = "frauen",
      slug = "2-frauen-bundesliga", nav_label = "2. Bundesliga",
      nav_group = "Frauen",
      display_name = "2. Frauen-Bundesliga",
      teams_range = c(14L, 14L), first_season = 2023L,
      promotion_to = "82",
      # Abstieg in die Frauen-Regionalligen, die wir nicht fuehren -- daher
      # kein relegation_to, aber sehr wohl Abstiegsplaetze: "Die letzten drei
      # Mannschaften steigen ab" (kicker). An den Spielplaenen bestaetigt:
      # je drei Absteiger 2024/25 und 2025/26.
      relegation_to = NULL,
      promotion_slots = 2L, relegation_slots = 3L, playoff_slots = 0L,
      # Zweitvertretungen sind nicht aufstiegsberechtigt -- wie in der
      # 3. Liga braucht die Aufstiegstabelle einen eigenen Lauf.
      restrictions = "Zweitvertretungen duerfen nicht aufsteigen",
      tore_slope = FRAUEN_TORE_SLOPE, tore_intercept = FRAUEN_TORE_INTERCEPT
    ),

    # --- Regionalligen ------------------------------------------------------
    # Kein eigenes Tormodell: Sie tauschen Teams mit der 3. Liga, gehoeren
    # also zur Wechselgemeinschaft Herren. Ein staffelweiser Intercept wuerde
    # jeden Auf- und Absteiger stillschweigend umskalieren (ADR 0004).
    rl_nord = list(
      api_id = "84", active = FALSE, family = "herren", staffel = "Nord",
      slug = "rl-nord", nav_label = "Nord", nav_group = "Regionalliga",
      display_name = "Regionalliga Nord",
      teams_range = c(16L, 22L), first_season = 2019L,
      promotion_to = "80", relegation_to = NULL,
      promotion_slots = 1L, playoff_slots = 1L
    ),
    rl_nordost = list(
      api_id = "85", active = FALSE, family = "herren", staffel = "Nordost",
      slug = "rl-nordost", nav_label = "Nordost", nav_group = "Regionalliga",
      display_name = "Regionalliga Nordost",
      teams_range = c(16L, 22L), first_season = 2019L,
      promotion_to = "80", relegation_to = NULL,
      promotion_slots = 1L, playoff_slots = 1L
    ),
    rl_west = list(
      api_id = "87", active = FALSE, family = "herren", staffel = "West",
      slug = "rl-west", nav_label = "West", nav_group = "Regionalliga",
      display_name = "Regionalliga West",
      teams_range = c(16L, 22L), first_season = 2019L,
      promotion_to = "80", relegation_to = NULL,
      promotion_slots = 1L, playoff_slots = 0L
    ),
    rl_suedwest = list(
      api_id = "86", active = FALSE, family = "herren", staffel = "SuedWest",
      slug = "rl-suedwest", nav_label = "SüdWest", nav_group = "Regionalliga",
      display_name = "Regionalliga SüdWest",
      teams_range = c(16L, 22L), first_season = 2019L,
      promotion_to = "80", relegation_to = NULL,
      promotion_slots = 1L, playoff_slots = 0L
    ),
    rl_bayern = list(
      api_id = "83", active = FALSE, family = "herren", staffel = "Bayern",
      slug = "rl-bayern", nav_label = "Bayern", nav_group = "Regionalliga",
      display_name = "Regionalliga Bayern",
      teams_range = c(16L, 22L), first_season = 2019L,
      promotion_to = "80", relegation_to = NULL,
      promotion_slots = 1L, playoff_slots = 1L
    )
  )
}

# --- Zugriffshelfer ---------------------------------------------------------

#' Liga-IDs, standardmaessig nur die aktiven.
#'
#' Die Reihenfolge ist die der Registry und bestimmt die Fetch-Reihenfolge im
#' Update-Loop -- sie darf sich nicht unbemerkt aendern.
#'
#' @param active_only TRUE (Default) = nur aktive Ligen.
#' @return Zeichenvektor der api_ids.
league_ids <- function(active_only = TRUE) {
  reg <- league_registry()
  if (active_only) {
    reg <- Filter(function(l) isTRUE(l$active), reg)
  }
  unname(vapply(reg, function(l) l$api_id, character(1)))
}

#' Die aktiven Ligen als benannte Liste, in Registry-Reihenfolge.
#'
#' Die Namen sind die Registry-Schluessel und zugleich die Schluessel von
#' league_views() und league_data -- ueber sie sind Loop und Seitengenerator
#' verbunden.
active_leagues <- function() {
  Filter(function(l) isTRUE(l$active), league_registry())
}

#' Schluessel der aktiven Ligen, in Registry-Reihenfolge.
active_league_keys <- function() {
  names(active_leagues())
}

#' Braucht diese Liga einen zweiten Simulationslauf fuer die Aufstiegstabelle?
#'
#' In der 3. Liga duerfen Zweitvertretungen nicht aufsteigen; die
#' Aufstiegstabelle entsteht deshalb aus einem zweiten Lauf mit -50 Punkten
#' Malus fuer sie. Bisher war das an die Liga-ID "80" gebunden -- jetzt ist es
#' eine Eigenschaft der Liga.
#'
#' Die Regionalligen brauchen dieselbe Einschraenkung, sobald sie live gehen:
#' Auch von dort steigen Zweitvertretungen nicht in die 3. Liga auf.
has_promotion_restriction <- function(id) {
  entry <- league_by_id(id)
  !is.null(entry) && !is.null(entry$restrictions)
}

#' Registry-Eintrag zu einer Liga-ID.
#'
#' @param id api_id, als String oder Zahl.
#' @return Der Eintrag oder NULL, wenn die Liga unbekannt ist.
league_by_id <- function(id) {
  id <- as.character(id)
  for (entry in league_registry()) {
    if (identical(entry$api_id, id)) {
      return(entry)
    }
  }
  NULL
}

#' Registry-Schluessel zu einer Liga-ID (bundesliga, rl_nord, ...).
league_key <- function(id) {
  id <- as.character(id)
  reg <- league_registry()
  hit <- names(reg)[vapply(reg, function(l) identical(l$api_id, id), logical(1))]
  if (length(hit) == 0) NULL else hit[[1]]
}

#' Anzeigename einer Liga.
#'
#' Faellt auf "League <id>" zurueck, wenn die Liga unbekannt ist -- dasselbe
#' Verhalten wie die abgeloeste Map in api_service.R.
league_name <- function(id) {
  entry <- league_by_id(id)
  if (is.null(entry)) paste("League", id) else entry$display_name
}

#' Wechselgemeinschaft einer Liga ("herren" / "frauen").
league_family <- function(id) {
  entry <- league_by_id(id)
  if (is.null(entry)) NA_character_ else entry$family
}

#' Abweichendes Tormodell einer Liga, sonst NULL.
#'
#' NULL heisst: nichts senden, der Rust-Server benutzt seine Defaults
#' (ADR 0002).
goal_model <- function(id) {
  entry <- league_by_id(id)
  if (is.null(entry) || is.null(entry$tore_slope)) {
    return(NULL)
  }
  list(tore_slope = entry$tore_slope, tore_intercept = entry$tore_intercept)
}

#' Tormodell als Argumentliste fuer die Rust-Aufrufe.
#'
#' Leere Liste = Defaults greifen. Eine Quelle fuer beide Endpunkte, damit
#' /simulate und /league-details nicht auseinanderlaufen koennen -- liefen sie
#' mit verschiedenen Tormodellen, widersprächen sich Heatmap und Score-Matrix
#' auf derselben Seite (ADR 0004).
goal_model_args <- function(id) {
  gm <- goal_model(id)
  if (is.null(gm)) list() else gm
}

#' Erwartete Teamzahl-Spanne einer Liga.
league_teams_range <- function(id) {
  entry <- league_by_id(id)
  if (is.null(entry)) NULL else entry$teams_range
}
