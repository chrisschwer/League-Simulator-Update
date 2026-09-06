#!/usr/bin/env Rscript

# Einmalige Offline-Kalibrierung der Start-ELOs fuer die sieben neuen Ligen
# (fuenf Regionalligen, Frauen-BL, 2. Frauen-BL).
#
# Ablauf:
#   1. Historische Spiele je Liga in den Fixture-Cache holen
#   2. ELO-Walk je Liga ueber alle verfuegbaren Saisons (Rust /league-details)
#   3. Regionalligen an die 3. Liga ankern (ueber Auf-/Absteiger)
#   4. Frauen an die Herren-Bundesliga ankern (Mittelwert-Konvention)
#   5. Ergebnis pruefen und -- nur mit --confirm -- schreiben
#
# Dry-Run ist der Default: ohne --confirm wird nichts geschrieben.
#
# Usage: Rscript scripts/calibrate_historical_elo.R [Optionen]
#   --confirm         Ergebnisse tatsaechlich schreiben
#   --refresh         Fixtures neu von der API holen statt aus dem Cache
#   --season <jahr>   Zielsaison fuer die TeamList (Default: 2026)
#   --out <datei>     Ausgabedatei (Default: RCode/TeamList_<saison>_neu.csv)
#
# Braucht einen laufenden Rust-Server (RUST_API_URL, Default localhost:8080)
# und RAPIDAPI_KEY, falls der Cache leer ist.

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
source(file.path(rcode_dir, "rust_integration.R"))
source(file.path(rcode_dir, "api_service.R"))       # get_team_short_name

get_opt <- function(flag, default) {
  i <- match(flag, args)
  if (!is.na(i) && length(args) > i) args[[i + 1]] else default
}

confirm <- "--confirm" %in% args
refresh <- "--refresh" %in% args
target_season <- as.integer(get_opt("--season", "2026"))
out_file <- get_opt("--out", file.path(rcode_dir, sprintf("TeamList_%d_neu.csv", target_season)))

# Historientiefe je Liga (verifiziert am API): Die Regionalligen liefern ab
# 2019, die Frauen-BL ab 2016, die 2. Frauen-BL erst ab 2023.
SEASONS <- list(
  "80"   = 2019:2025,   # 3. Liga als Anker
  "83"   = 2019:2025, "84" = 2019:2025, "85" = 2019:2025,
  "86"   = 2019:2025, "87" = 2019:2025,
  "82"   = 2016:2025,
  "1034" = 2023:2025
)

# Startniveau. Die Abstaende der bestehenden Ligen (BL 1682, 2. BL 1398,
# 3. Liga 1156) verengen sich von 284 auf 242; ein vergleichbarer Schritt
# unterhalb der 3. Liga ergibt ~920. Das ist der Startpunkt, nicht das
# Ergebnis -- die Ankerung an die 3. Liga korrigiert ihn.
RL_START_ELO <- 920
FRAUEN_START_ELO <- 1500
HERREN_BL_MEAN <- 1682   # Ankerziel fuer die Frauen-Bundesliga

cat("== Offline-ELO-Kalibrierung ==\n")
cat(sprintf("Modus: %s | Zielsaison: %d\n",
            if (confirm) "SCHREIBEN (--confirm)" else "Dry-Run", target_season))

# --- Vorbedingung: Rust-Server ----------------------------------------------

base_url <- Sys.getenv("RUST_API_URL", "http://localhost:8080")
if (!connect_rust_simulator()) {
  stop(sprintf(paste0("Rust-Server nicht erreichbar unter %s.\n",
                      "  Starten mit: cd league-simulator-rust && cargo run --release"),
               base_url))
}
cat(sprintf("Rust-Server: %s erreichbar\n\n", base_url))

# --- 1./2. Walk je Liga ------------------------------------------------------

cat("-- ELO-Walk je Liga --\n")
walked <- list()

for (lid in c("80", REGIONALLIGEN, "82", "1034")) {
  start <- if (lid == "80") 1156 else if (lid %in% REGIONALLIGEN) RL_START_ELO else FRAUEN_START_ELO
  e <- walk_league_history(lid, SEASONS[[lid]], start_elo = start,
                           refresh = refresh, base_url = base_url)
  if (is.null(e)) {
    cat(sprintf("  Liga %-4s: keine Daten\n", lid))
    next
  }
  walked[[lid]] <- e
  cat(sprintf("  Liga %-4s: %3d Teams  Mittel %6.1f  SD %5.1f  Spanne %.0f-%.0f\n",
              lid, length(e), mean(e), stats::sd(e), min(e), max(e)))
}

# --- 3. Regionalligen an die 3. Liga ankern ---------------------------------

cat("\n-- Ankerung (i): Regionalligen -> 3. Liga --\n")

# Auf- und Absteiger ueber alle Saisonwechsel sammeln.
promoted_all <- integer(0)
relegated_all <- integer(0)
for (s in 2020:2025) {
  ids_of <- function(lid, season) {
    m <- load_season_matches(lid, season, refresh = FALSE)
    if (is.null(m)) integer(0) else unique(c(m$teams_home_id, m$teams_away_id))
  }
  rl_prev <- unlist(lapply(REGIONALLIGEN, ids_of, season = s - 1))
  rl_now <- unlist(lapply(REGIONALLIGEN, ids_of, season = s))
  movers <- find_league_movers(rl_prev, ids_of("80", s - 1), rl_now, ids_of("80", s))
  promoted_all <- c(promoted_all, movers$promoted)
  relegated_all <- c(relegated_all, movers$relegated)
}

l3 <- walked[["80"]]
rl_pool <- unlist(walked[REGIONALLIGEN])
names(rl_pool) <- sub("^[0-9]+\\.", "", names(rl_pool))

promoted_elo <- rl_pool[as.character(unique(promoted_all))]
relegated_elo <- l3[as.character(unique(relegated_all))]
promoted_elo <- promoted_elo[!is.na(promoted_elo)]
relegated_elo <- relegated_elo[!is.na(relegated_elo)]

cat(sprintf("  Aufsteiger (RL):   %2d Teams, Mittel %.1f\n",
            length(promoted_elo), mean(promoted_elo)))
cat(sprintf("  Absteiger (3.Liga): %2d Teams, Mittel %.1f\n",
            length(relegated_elo), mean(relegated_elo)))

rl_shift <- mean(relegated_elo) - mean(promoted_elo)
cat(sprintf("  -> Verschiebung des RL-Blocks: %+.1f ELO\n", rl_shift))

for (lid in REGIONALLIGEN) {
  if (!is.null(walked[[lid]])) walked[[lid]] <- walked[[lid]] + rl_shift
}

# Die Staffeln gegeneinander: Wie stark waren IHRE Aufsteiger spaeter in der
# 3. Liga? Das ist die einzige Evidenz, die die fuenf Staffeln vergleichbar
# macht -- sie spielen nie gegeneinander.
#
# Bewusst gedaempft: Je Staffel liegen nur 2-6 Aufsteiger vor. Die rohe
# Differenz (Spanne ~195 ELO) waere ueberangepasst, deshalb wirkt nur die
# Haelfte -- dieselbe Logik wie bei der Relegationskopplung.
cat("\n-- Ankerung (i-b): Staffeln gegeneinander --\n")

promoted_by_region <- merge(
  data.frame(TeamID = as.integer(unique(promoted_all))),
  derive_club_regions(2019:2025, refresh = FALSE),
  by = "TeamID"
)
promoted_by_region$elo <- unname(l3[as.character(promoted_by_region$TeamID)])
promoted_by_region <- promoted_by_region[!is.na(promoted_by_region$elo), ]

if (nrow(promoted_by_region) > 0) {
  region_mean <- tapply(promoted_by_region$elo, promoted_by_region$Region, mean)
  region_n <- tapply(promoted_by_region$elo, promoted_by_region$Region, length)
  overall <- mean(region_mean)

  for (lid in REGIONALLIGEN) {
    label <- unname(RL_LABELS[lid])
    if (is.na(region_mean[label])) {
      cat(sprintf("  %-9s keine Aufsteiger -- unveraendert\n", label))
      next
    }
    adj <- (region_mean[[label]] - overall) * 0.5
    walked[[lid]] <- walked[[lid]] + adj
    cat(sprintf("  %-9s n=%d  Aufsteiger-Mittel %7.1f  -> %+6.1f ELO\n",
                label, region_n[[label]], region_mean[[label]], adj))
  }
}

# --- 4. Frauen an die Herren-BL ankern --------------------------------------

cat("\n-- Ankerung (ii): Frauen -> Herren-Bundesliga --\n")
cat("  Konvention: Beide obersten Ligen gleich stark. Da Frauen und Herren\n")
cat("  nie gegeneinander spielen, ist jede Abstufung unbelegbar.\n")

# Zuerst die 2. Frauen-BL an die Frauen-BL ankern -- genau wie die
# Regionalligen an die 3. Liga. Beide Ligen sind unabhaengig von 1500
# gelaufen und haben deshalb noch keinen Abstand zueinander; ihn einfach
# gleich zu lassen hiesse, beide Ligen fuer gleich stark zu erklaeren.
if (!is.null(walked[["82"]]) && !is.null(walked[["1034"]])) {
  f_up <- integer(0); f_dn <- integer(0)
  for (s in 2024:2025) {
    ids2 <- function(lid, season) {
      m <- load_season_matches(lid, season, refresh = FALSE)
      if (is.null(m)) integer(0) else unique(c(m$teams_home_id, m$teams_away_id))
    }
    mv <- find_league_movers(ids2("1034", s - 1), ids2("82", s - 1),
                             ids2("1034", s), ids2("82", s))
    f_up <- c(f_up, mv$promoted); f_dn <- c(f_dn, mv$relegated)
  }

  up_elo <- walked[["1034"]][as.character(unique(f_up))]
  dn_elo <- walked[["82"]][as.character(unique(f_dn))]
  up_elo <- up_elo[!is.na(up_elo)]; dn_elo <- dn_elo[!is.na(dn_elo)]

  if (length(up_elo) > 0 && length(dn_elo) > 0) {
    shift_1034 <- mean(dn_elo) - mean(up_elo)
    walked[["1034"]] <- walked[["1034"]] + shift_1034
    cat(sprintf("  2. Frauen-BL: %d Aufsteiger (Mittel %.1f) vs %d Absteiger (Mittel %.1f)\n",
                length(up_elo), mean(up_elo), length(dn_elo), mean(dn_elo)))
    cat(sprintf("  -> Verschiebung 2. Frauen-BL: %+.1f ELO\n", shift_1034))
  } else {
    cat("  WARNUNG: keine Wechsler gefunden, 2. Frauen-BL bleibt ungeankert\n")
  }
}

# Erst danach die ganze Familie auf das Herren-Niveau heben. Der zuvor
# gemessene Abstand zwischen den beiden Frauen-Ligen bleibt dabei erhalten.
if (!is.null(walked[["82"]])) {
  before <- mean(walked[["82"]])
  frauen_shift <- HERREN_BL_MEAN - before
  for (lid in c("82", "1034")) {
    if (!is.null(walked[[lid]])) walked[[lid]] <- walked[[lid]] + frauen_shift
  }
  cat(sprintf("  Frauen-BL Mittel %.1f -> %.1f (Verschiebung %+.1f)\n",
              before, mean(walked[["82"]]), frauen_shift))
}

# --- 5. Pruefung -------------------------------------------------------------

cat("\n-- Pruefung --\n")
cat(sprintf("%-22s %5s %8s %7s %9s %9s\n",
            "Liga", "Teams", "Mittel", "SD", "Remis Mod", "Remis real"))

OBSERVED_DRAW <- c("80" = 0.243, "82" = 0.159, "1034" = 0.175,
                   "83" = 0.254, "84" = 0.224, "85" = 0.247,
                   "86" = 0.225, "87" = 0.253)
LABELS <- c("80" = "3. Liga", "82" = "Frauen-BL", "1034" = "2. Frauen-BL",
            "83" = "RL Bayern", "84" = "RL Nord", "85" = "RL Nordost",
            "86" = "RL SuedWest", "87" = "RL West")

for (lid in names(walked)) {
  e <- walked[[lid]]
  obs <- OBSERVED_DRAW[[lid]]
  mod <- .simulate_draw_rate(stats::sd(e), n = 100000)
  cat(sprintf("%-22s %5d %8.1f %7.1f %8.1f%% %8.1f%%\n",
              LABELS[[lid]], length(e), mean(e), stats::sd(e), 100 * mod, 100 * obs))
}

cat("\nHinweis: Die Streuung ist das Ergebnis des Walks, kein freier Parameter.\n")
cat("Bei den Frauen-Ligen bleibt eine Remis-Luecke von rund 5 Prozentpunkten:\n")
cat("Der Walk erreicht nicht die Spreizung, die das unabhaengige Poisson-Modell\n")
cat("dafuer braeuchte. Bewusst nicht nachjustiert -- siehe docs/reports/.\n")

# --- 6. Schreiben ------------------------------------------------------------

regions <- derive_club_regions(2019:2025, refresh = FALSE)

# Die 3. Liga dient als Anker; ihre Teams stehen bereits in der TeamList.
# ABER: Wer sie verlaesst, steht dort in der falschen Liga -- und wer sie
# durchgehend bespielt hat, taucht in keiner anderen Liga auf und faellt
# unten aus `last_league` heraus. Beides betrifft genau die Absteiger.
#
# Ohne diese Ausnahme fehlten in der Saison 2026 Erzgebirge Aue (-> RL
# Nordost) und TSV 1860 Muenchen (-> RL Bayern) vollstaendig; Schweinfurt
# und Ulm kamen nur durch, weil sie im Betrachtungszeitraum ZUSAETZLICH in
# einer Regionalliga gespielt hatten.
#
# Ihr Walk-Endwert wird unveraendert uebernommen: Sie stehen bereits auf der
# Drittliga-Skala, an die der RL-Block geankert wurde (ADR 0003). Eine
# Staffelverschiebung waere hier falsch.
records <- do.call(rbind, lapply(names(walked), function(lid) {
  if (lid == "80") return(NULL)   # ueber liga3_leavers unten behandelt
  e <- walked[[lid]]
  data.frame(
    TeamID = as.integer(names(e)),
    InitialELO = as.numeric(e),
    League = lid,
    stringsAsFactors = FALSE
  )
}))
# Ein Team kann in mehreren Ligen gelaufen sein (Auf-/Abstieg innerhalb des
# Betrachtungszeitraums, etwa zwischen den beiden Frauen-Ligen). Es gehoert
# genau einmal in die TeamList -- und zwar in die Liga, in der es zuletzt
# gespielt hat.
last_league <- do.call(rbind, lapply(setdiff(names(walked), "80"), function(lid) {  # nolint
  seen <- integer(0)
  for (s in SEASONS[[lid]]) {
    m <- load_season_matches(lid, s, refresh = FALSE)
    if (is.null(m)) next
    seen <- unique(c(seen, m$teams_home_id, m$teams_away_id))
    last_seen <- s
  }
  if (length(seen) == 0) return(NULL)
  # Letzte Saison je Team in dieser Liga
  per_team <- do.call(rbind, lapply(SEASONS[[lid]], function(s) {
    m <- load_season_matches(lid, s, refresh = FALSE)
    if (is.null(m)) return(NULL)
    data.frame(TeamID = unique(c(m$teams_home_id, m$teams_away_id)),
               League = lid, LastSeason = s, stringsAsFactors = FALSE)
  }))
  per_team
}))
last_league <- last_league[order(last_league$TeamID, -last_league$LastSeason), ]
last_league <- last_league[!duplicated(last_league$TeamID), c("TeamID", "League")]

records <- records[!duplicated(records[, c("TeamID", "League")]), ]
records <- merge(records[, c("TeamID", "InitialELO", "League")],
                 last_league, by = c("TeamID", "League"))

# Absteiger aus der 3. Liga nachtragen: Teams, die zuletzt dort spielten,
# in der Zielsaison aber in einer der neuen Ligen stehen. Sie fehlen oben,
# weil `last_league` die 3. Liga ausklammert.
liga3_final <- walked[["80"]]
if (!is.null(liga3_final)) {
  ziel_ligen <- setdiff(names(SEASONS), "80")
  leavers <- do.call(rbind, lapply(ziel_ligen, function(lid) {
    m <- load_season_matches(lid, target_season, refresh = FALSE)
    if (is.null(m)) return(NULL)
    ids <- unique(c(m$teams_home_id, m$teams_away_id))
    treffer <- ids[as.character(ids) %in% names(liga3_final) &
                     !(ids %in% records$TeamID)]
    if (length(treffer) == 0) return(NULL)
    data.frame(
      TeamID = as.integer(treffer),
      InitialELO = as.numeric(liga3_final[as.character(treffer)]),
      League = lid,
      stringsAsFactors = FALSE
    )
  }))
  if (!is.null(leavers) && nrow(leavers) > 0) {
    cat(sprintf("\nAbsteiger aus der 3. Liga nachgetragen: %d\n", nrow(leavers)))
    records <- rbind(records, leavers)
  }
}

records <- merge(records, regions, by = "TeamID", all.x = TRUE)
records$Region[is.na(records$Region)] <- ""

# Kurznamen: global eindeutig gegen die bereits vergebenen der Altligen.
# ShortText wird in transform_data() zum Spaltennamen -- Kollisionen wuerden
# Teams stillschweigend vertauschen.
existing_tl <- file.path(rcode_dir, sprintf("TeamList_%d.csv", target_season))
reserved <- if (file.exists(existing_tl)) {
  utils::read.csv(existing_tl, sep = ";", stringsAsFactors = FALSE)$ShortText
} else {
  character()
}

names_df <- collect_team_names(setdiff(names(walked), "80"), SEASONS)
names_df <- names_df[names_df$TeamID %in% records$TeamID, ]
short_df <- assign_short_names(names_df, reserved = reserved)

records <- merge(records, short_df, by = "TeamID", all.x = TRUE)
records <- records[!is.na(records$ShortText), ]
records <- records[, c("TeamID", "ShortText", "Promotion", "InitialELO",
                       "League", "Region", "Name")]

stopifnot(!any(duplicated(records$ShortText)),
          !any(records$ShortText %in% reserved))
cat(sprintf("Kurznamen: %d vergeben, alle eindeutig (gegen %d bestehende)\n",
            nrow(records), length(reserved)))

cat(sprintf("\n%d Teams aus %d neuen Ligen kalibriert.\n",
            nrow(records), length(setdiff(names(walked), "80"))))

if (!confirm) {
  cat("\nDry-Run: nichts geschrieben. Mit --confirm wiederholen.\n")
  cat(sprintf("Wuerde schreiben nach: %s\n", out_file))
} else {
  utils::write.table(records, out_file, sep = ";", row.names = FALSE, quote = FALSE)
  cat(sprintf("\nGeschrieben: %s\n", out_file))
}
