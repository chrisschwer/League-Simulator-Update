# Fixture-Cache fuer die einmalige Offline-ELO-Kalibrierung.
#
# Die Kalibrierung braucht alle historischen Spiele der neuen Ligen (RL 83-87
# ab 2019, Frauen-BL 82 ab 2016, 2. Frauen-BL 1034 ab 2023). Das sind rund
# 60-80 API-Requests. Ohne Cache waere jeder Wiederholungslauf -- und davon
# gibt es beim Kalibrieren viele -- erneut so teuer.
#
# Abgrenzung zu ADR 0002 ("Es entsteht keine Persistenzschicht"): Dieser Cache
# gehoert NICHT zum Produktivpfad. Der Scheduler liest ihn nie; er existiert
# nur fuer das Offline-Skript, liegt unter data/fixture_cache/ und ist
# gitignored. Committet werden ausschliesslich die Ergebnisse.

FIXTURE_CACHE_DIR <- "data/fixture_cache"

# Runden, die keine Hauptrunde sind. Negativliste statt Positivliste:
# Die Regionalligen liefern ihre Spieltage als "Bayern - 34" oder "Nord - 20"
# -- und wechseln zwischen Saisons sogar die Sprache ("Nord" vs. "North").
# Ein Filter auf startsWith("Regular Season") wuerde jedes Regionalliga-Spiel
# verwerfen und klaglos eine leere Liga simulieren.
KO_ROUND_PATTERNS <- c(
  "Relegation",
  "Promotion",
  "Play-?off",
  "Final",
  "Semi-?final",
  "Quarter-?final",
  "8th Finals",
  "16th Finals",
  "Round of"
)

#' Pfad der Cache-Datei fuer eine Liga-Saison-Kombination.
cache_path <- function(league, season, cache_dir = FIXTURE_CACHE_DIR) {
  file.path(cache_dir, paste0(league, "_", season, ".json"))
}

#' Holt Fixtures einer Liga-Saison, bevorzugt aus dem Cache.
#'
#' Beim ersten Aufruf wird `fetch_fn` befragt und das Ergebnis als JSON
#' abgelegt; danach kommt es ohne Netzzugriff von Platte. Ein NULL-Ergebnis
#' (Liga/Saison gibt es nicht) wird NICHT gecacht -- sonst waere ein
#' voruebergehender API-Fehler dauerhaft eingefroren.
#'
#' @param league Liga-ID als String.
#' @param season Saison als Zahl oder String.
#' @param fetch_fn Funktion(league, season) -> data.frame oder NULL.
#' @param cache_dir Verzeichnis fuer die Cache-Dateien.
#' @param refresh TRUE erzwingt einen Neuabruf.
#' @return data.frame der Fixtures oder NULL.
cached_fixtures <- function(league, season,
                            fetch_fn = fetch_league_results,
                            cache_dir = FIXTURE_CACHE_DIR,
                            refresh = FALSE) {
  path <- cache_path(league, season, cache_dir)

  if (!refresh && file.exists(path)) {
    return(jsonlite::fromJSON(path))
  }

  fixtures <- fetch_fn(league, season)

  if (is.null(fixtures) || (is.data.frame(fixtures) && nrow(fixtures) == 0)) {
    return(NULL)
  }

  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE)
  }
  jsonlite::write_json(fixtures, path, dataframe = "columns", digits = NA)

  fixtures
}

#' Ist diese Runde eine Hauptrundenpartie?
#'
#' Negativliste (siehe KO_ROUND_PATTERNS): Alles zaehlt als Hauptrunde, was
#' keine bekannte K.-o.-Runde ist. Das ueberlebt sowohl "Bayern - 34" als auch
#' den Wechsel von "Nord" zu "North".
is_regular_season_round <- function(round_label) {
  if (length(round_label) == 0) return(logical(0))

  ko <- Reduce(
    `|`,
    lapply(KO_ROUND_PATTERNS, function(p) grepl(p, round_label, ignore.case = TRUE)),
    init = rep(FALSE, length(round_label))
  )

  !is.na(round_label) & nzchar(round_label) & !ko
}

#' Ist diese Runde eine Relegations- oder Aufstiegspartie?
#'
#' Diese Spiele sind die einzige direkte Evidenz dafuer, wie zwei sonst
#' getrennte Ligen zueinander stehen -- die Kalibrierung braucht sie fuer die
#' Staffel-Kopplung (apply_relegation_coupling).
is_relegation_round <- function(round_label) {
  if (length(round_label) == 0) return(logical(0))

  !is.na(round_label) &
    (grepl("Relegation", round_label, ignore.case = TRUE) |
       grepl("Promotion", round_label, ignore.case = TRUE) |
       grepl("Play-?off", round_label, ignore.case = TRUE))
}
