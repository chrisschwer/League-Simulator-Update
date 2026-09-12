#!/usr/bin/env Rscript

# Empirie-Report je Liga und Saison: Tore/Spiel, H/X/A-Anteile, impliziter
# Heimvorteil, beobachtete vs. modellierte Remisquote -- und die
# Poisson-Obergrenze, die zeigt, welche Luecke ueberhaupt schliessbar ist.
#
# Zweck: Die Zahlen des Ligen-Ausbauplans wurden ad hoc erhoben und sind
# derzeit nicht reproduzierbar. Dieses Skript macht sie nachrechenbar und
# dient nach der Kalibrierung als Regressionsnetz.
#
# Reiner Lesepfad -- schreibt nichts ausser dem Cache.
#
# Usage: Rscript scripts/analyze_league_empirics.R [--refresh] [--leagues 78,79,80]
#   --refresh        Fixtures neu von der API holen statt aus dem Cache
#   --leagues <ids>  Kommaliste von Liga-IDs (Default: alle zehn)
#   --seasons <yrs>  Kommaliste von Saisons (Default: 2024,2025)
#
# Braucht RAPIDAPI_KEY nur, wenn der Cache leer ist oder --refresh gesetzt ist.

args <- commandArgs(trailingOnly = TRUE)

script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
rcode_dir <- if (length(script_dir) == 1 && nzchar(script_dir)) {
  file.path(dirname(script_dir), "RCode")
} else {
  file.path("RCode")
}

source(file.path(rcode_dir, "elo_aggregation.R"))
source(file.path(rcode_dir, "fixture_cache.R"))
source(file.path(rcode_dir, "elo_calibration.R"))

get_opt <- function(flag, default) {
  i <- match(flag, args)
  if (!is.na(i) && length(args) > i) args[[i + 1]] else default
}

refresh <- "--refresh" %in% args

# Die zehn Ligen des Ausbaus. Namen nur fuer die Ausgabe.
ALL_LEAGUES <- list(
  "78"   = "Bundesliga",
  "79"   = "2. Bundesliga",
  "80"   = "3. Liga",
  "82"   = "Frauen-Bundesliga",
  "1034" = "2. Frauen-Bundesliga",
  "83"   = "RL Bayern",
  "84"   = "RL Nord",
  "85"   = "RL Nordost",
  "86"   = "RL SuedWest",
  "87"   = "RL West"
)

leagues <- strsplit(get_opt("--leagues", paste(names(ALL_LEAGUES), collapse = ",")), ",")[[1]]
seasons <- as.integer(strsplit(get_opt("--seasons", "2024,2025"), ",")[[1]])

#' Kennzahlen einer Spielmenge.
#'
#' Der implizite Heimvorteil wird ueber die ELO-Erwartungsformel aus dem
#' Heim-Score-Anteil (Sieg + 1/2 Remis) zurueckgerechnet -- also ueber
#' 1/(1+10^(-HA/400)). Achtung: Das ist eine andere Skala als der Heimvorteil
#' des Tormodells (40); die beiden Werte sind nicht direkt vergleichbar.
#'
#' Diese Formel war bis Issue #146, Teil 2 auch im Saisonwechsel verbaut
#' (calculate_elo_update(), mit home_advantage = 100). Sie ist dort entfallen;
#' hier bleibt sie als reines AUSWERTUNGSMASS, das nichts fortschreibt.
league_metrics <- function(m) {
  n <- nrow(m)
  if (n == 0) return(NULL)

  home <- sum(m$goals_home > m$goals_away)
  draw <- sum(m$goals_home == m$goals_away)
  away <- sum(m$goals_home < m$goals_away)
  goals <- mean(m$goals_home + m$goals_away)

  score_share <- (home + 0.5 * draw) / n
  # Umkehrung von 1/(1+10^(-HA/400))
  implied_ha <- if (score_share > 0 && score_share < 1) {
    400 * log10(score_share / (1 - score_share))
  } else {
    NA_real_
  }

  # Modellierte Remisquote bei BL-typischer Streuung und festem Intercept.
  modelled_draw <- .simulate_draw_rate(141, n = 100000)

  list(
    n = n,
    goals = goals,
    home = home / n, draw = draw / n, away = away / n,
    implied_ha = implied_ha,
    modelled_draw = modelled_draw,
    ceiling = poisson_draw_ceiling()
  )
}

cat("Empirie-Report -- beendete Hauptrundenspiele\n")
cat(sprintf("Saisons: %s | Modell: Intercept %.5f, HA %d\n",
            paste(seasons, collapse = ", "), TORE_INTERCEPT, HOME_ADVANTAGE_MODEL))
cat(sprintf("Poisson-Obergrenze fuer die Remisquote: %.1f%%\n\n",
            100 * poisson_draw_ceiling()))

cat(sprintf("%-22s %6s %7s %7s %7s %7s %8s %9s\n",
            "Liga", "Spiele", "Tore", "Heim%", "Remis%", "Ausw%", "impl.HA", "Modell-X%"))
cat(strrep("-", 84), "\n")

for (lid in leagues) {
  label <- if (!is.null(ALL_LEAGUES[[lid]])) ALL_LEAGUES[[lid]] else lid

  all_matches <- list()
  for (s in seasons) {
    fx <- tryCatch(
      cached_fixtures(lid, s, refresh = refresh),
      error = function(e) {
        message(sprintf("  (Liga %s, Saison %d: %s)", lid, s, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(fx) || !is.data.frame(fx) || nrow(fx) == 0) next

    # Nur beendete Hauptrundenspiele mit vollstaendigem Ergebnis.
    keep <- fx$fixture_status_short == "FT" &
      !is.na(fx$goals_home) & !is.na(fx$goals_away)
    if (!is.null(fx$round)) {
      keep <- keep & is_regular_season_round(fx$round)
    }
    all_matches[[length(all_matches) + 1]] <- fx[keep, , drop = FALSE]
  }

  if (length(all_matches) == 0) {
    cat(sprintf("%-22s %6s  (keine Daten)\n", label, "-"))
    next
  }

  m <- do.call(rbind, all_matches)
  k <- league_metrics(m)
  if (is.null(k)) {
    cat(sprintf("%-22s %6s  (keine Daten)\n", label, "-"))
    next
  }

  cat(sprintf("%-22s %6d %7.2f %6.1f%% %6.1f%% %6.1f%% %7.0f %8.1f%%\n",
              label, k$n, k$goals, 100 * k$home, 100 * k$draw, 100 * k$away,
              k$implied_ha, 100 * k$modelled_draw))
}

cat("\nLesehilfe:\n")
cat("  impl.HA    Heimvorteil auf der ELO-Erwartungsskala (nicht die 40 des Tormodells)\n")
cat("  Modell-X%  Remisquote, die das Modell bei BL-typischer Streuung (SD 141) liefert\n")
cat("  Liegt Remis% ueber der Obergrenze, ist die Quote mit diesem Modell nicht darstellbar.\n")
