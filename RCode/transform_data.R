library(dplyr)
library(tidyr)

# Rundenfilter (Negativliste) und Postcondition. Pfadunabhaengig sourcen: die
# Datei wird aus dem Repo-Root, aus tests/testthat und aus dem Container
# geladen. source() legt den eigenen Pfad als `ofile` in seinem Frame ab.
if (!exists("is_regular_season_round") || !exists("assert_rounds_kept")) {
  local({
    d <- NULL
    for (f in rev(sys.frames())) {
      if (!is.null(f$ofile)) {
        d <- dirname(f$ofile)
        break
      }
    }
    if (is.null(d) || is.na(d) || !nzchar(d)) d <- "RCode"
    source(file.path(d, "round_filter.R"))
  })
}

# Die beiden Wechselgemeinschaften (ADR 0004, CONTEXT.md): Ligen, zwischen
# denen Mannschaften auf- und absteigen. Herren umfasst 78, 79, 80 und die
# fuenf Regionalligen 83-87; Frauen die beiden Frauen-Bundesligen 82 und 1034.
# Sie tauschen nie Teams -- ELO und Tormodell gelten nur innerhalb einer.
FRAUEN_LIGEN <- c("82", "1034")

#' Wechselgemeinschaft je Liga-ID.
#'
#' @param league_id Vektor von Liga-IDs (Zahl oder Zeichen).
#' @return Zeichenvektor "herren" / "frauen".
wechselgemeinschaft <- function(league_id) {
  ifelse(as.character(league_id) %in% FRAUEN_LIGEN, "frauen", "herren")
}

#' Laedt die TeamList und prueft die Invarianten, auf die transform_data baut.
#'
#' transform_data() macht aus jedem ShortText einen SPALTENNAMEN des
#' Simulations-Data-Frames. Kollidieren zwei Kurznamen, entstehen doppelte
#' Spalten -- und damit stillschweigend vertauschte Teams. R meldet das nicht.
#' Eine doppelte TeamID vervielfacht ueber den merge() Zeilen, ebenso leise.
#'
#' Bis zum Ligen-Ausbau wurde Eindeutigkeit nur JE LIGA hergestellt
#' (generate_unique_short_name() bekommt die Namen einer Liga). Bei 56 Teams
#' in drei Ligen trug das; bei 237 Teams in zehn Ligen, darunter rund 30
#' Zweitvertretungen, sind Kollisionen ueber Ligagrenzen hinweg der Normalfall.
#'
#' Massgeblich ist die WECHSELGEMEINSCHAFT, nicht die gesamte Liste. Zwei
#' Gruende:
#'
#'  - Notwendig: Innerhalb einer Wechselgemeinschaft wechseln Teams die Liga.
#'    Ein Kurzname muss deshalb ueber alle ihre Ligen hinweg eindeutig sein,
#'    nicht nur innerhalb einer.
#'  - Ausreichend: transform_data() wird JE LIGA aufgerufen; nur Teams
#'    derselben Liga werden je zu Spalten desselben Data-Frames. Herren und
#'    Frauen tauschen nie Teams (ADR 0004) und teilen nie einen Data-Frame --
#'    eine Kollision zwischen ihnen kann keinen Schaden anrichten.
#'
#' Und sie ist erwuenscht: So traegt die Frauenmannschaft eines Vereins
#' dasselbe Kuerzel wie die Herrenmannschaft (SCF, RBL, HSV) statt eines
#' Ausweichnamens (SCFA, RBLA, HAM). In der Darstellung ueberschneiden sie
#' sich nicht -- jede Liga hat ihre eigene Seite.
#'
#' Bewusst NICHT geprueft wird die Laenge der Kurznamen: Die neuen Ligen
#' brauchen vier Zeichen (WACA, BAYB, FR2B). Entscheidend ist Eindeutigkeit,
#' nicht Format.
#'
#' @param file_path Pfad zur TeamList-CSV (Semikolon-getrennt).
#' @return data.frame der TeamList.
load_team_list <- function(file_path) {
  if (!file.exists(file_path)) {
    stop(sprintf("load_team_list: TeamList nicht gefunden: %s", file_path),
         call. = FALSE)
  }

  teams <- utils::read.csv(file_path, sep = ";", stringsAsFactors = FALSE)

  pflicht <- c("TeamID", "ShortText", "InitialELO")
  fehlend <- pflicht[!pflicht %in% names(teams)]
  if (length(fehlend) > 0) {
    stop(sprintf(
      "load_team_list: Pflichtspalten fehlen in %s: %s",
      file_path, paste(fehlend, collapse = ", ")
    ), call. = FALSE)
  }

  # Kurznamen je Wechselgemeinschaft pruefen. Ohne League-Spalte (TeamList
  # bis Saison 2025) gilt die ganze Liste als eine Gruppe -- dort gab es nur
  # die drei Herren-Ligen.
  gruppe <- if ("League" %in% names(teams)) {
    wechselgemeinschaft(teams$League)
  } else {
    rep("herren", nrow(teams))
  }

  dup_short <- unique(unlist(lapply(split(teams$ShortText, gruppe), function(x) {
    x[duplicated(x)]
  })))
  if (length(dup_short) > 0) {
    stop(sprintf(
      paste0(
        "load_team_list: Kurznamen sind innerhalb einer Wechselgemeinschaft ",
        "nicht eindeutig in %s: %s. ShortText wird in transform_data() zum ",
        "Spaltennamen -- doppelte Kurznamen vertauschen Teams stillschweigend."
      ),
      file_path, paste(dup_short, collapse = ", ")
    ), call. = FALSE)
  }

  dup_id <- unique(teams$TeamID[duplicated(teams$TeamID)])
  if (length(dup_id) > 0) {
    stop(sprintf(
      paste0(
        "load_team_list: TeamID ist nicht eindeutig in %s: %s. ",
        "Doppelte IDs vervielfachen beim Merge die Spielzeilen."
      ),
      file_path, paste(dup_id, collapse = ", ")
    ), call. = FALSE)
  }

  teams
}

transform_data <- function(fixtures, teams) {
  # Nur Hauptrundenspiele gehoeren in die Simulation: API-Football liefert die
  # Relegations-Playoffs als Runde "Final" im Liga-Feed mit, und der
  # Playoff-Gegner aus der anderen Liga wuerde sonst als zusaetzliches Team
  # auftauchen.
  #
  # `league` kommt als flache data.frame-Spalte durch jsonlite::fromJSONs
  # Simplification (fixtures$league$round greift direkt), aber als
  # List-Column einzeiliger data.frames, wenn fixtures von Hand genestet
  # gebaut wurde (fixtures$league$round ist dann NULL) -- beide Formen
  # behandeln, sonst wird im genesteten Fall stillschweigend nicht gefiltert.
  rounds <- if ("league" %in% names(fixtures)) fixtures$league$round else NULL
  if (is.null(rounds) && "league" %in% names(fixtures) && is.list(fixtures$league)) {
    rounds <- vapply(fixtures$league, function(x) as.character(x$round[[1]]), character(1))
  }
  if (!is.null(rounds)) {
    rounds <- as.character(rounds)
    keep <- is_regular_season_round(rounds)
    assert_rounds_kept(length(rounds), sum(keep), rounds, "transform_data")
    fixtures <- fixtures[keep, ]
  }

  # Ohne Spiele gibt es nichts zu entschachteln -- die unnest()-Kette unten
  # scheitert an den dann fehlenden Spalten. Eine Liga ohne angesetzte Spiele
  # ist zum Saisonstart normal und darf den Scheduler nicht anhalten; sie
  # liefert einfach ein leeres Gerüst. (Der Fall, dass der FILTER alles
  # entfernt hat, ist oben bereits abgefangen.)
  if (nrow(fixtures) == 0) {
    return(tibble::tibble(
      TeamHeim = character(0), TeamGast = character(0),
      ToreHeim = numeric(0), ToreGast = numeric(0)
    ))
  }

  fixtures_flat <- fixtures %>% unnest(cols = c("teams", "goals", "fixture"), names_sep = "_")
  fixtures_flat <- fixtures_flat %>% unnest(cols = c("teams_home", "teams_away", "fixture_status"), names_sep = "_")
  fixtures_flat$fixture_status_short <- replace_na(fixtures_flat$fixture_status_short, "NA")
  fixtures_flat <- fixtures_flat %>% mutate(OriginalOrder = row_number())

  df_home <- merge(fixtures_flat, teams, by.x = "teams_home_id", by.y = "TeamID", all.x = TRUE)
  df_home <- df_home %>% rename(TeamHeim = ShortText, ToreHeim = goals_home, ELOHome = InitialELO)

  df_final <- merge(df_home, teams, by.x = "teams_away_id", by.y = "TeamID", all.x = TRUE)
  df_final <- df_final %>% rename(TeamGast = ShortText, ToreGast = goals_away, ELOAway = InitialELO)

  for (team in unique(c(df_final$TeamHeim, df_final$TeamGast))) {
    df_final[[team]] <- ifelse(df_final$TeamHeim == team, df_final$ELOHome,
      ifelse(df_final$TeamGast == team, df_final$ELOAway, NA)
    )
  }

  # set goals to NA unless game is finished
  # (FT = full time, AET = after extra time, PEN = decided on penalties)
  unfinished <- !df_final$fixture_status_short %in% c("FT", "AET", "PEN")
  df_final$ToreHeim[unfinished] <- NA
  df_final$ToreGast[unfinished] <- NA


  df_final <- df_final %>%
    select(
      TeamHeim, TeamGast, ToreHeim, ToreGast,
      all_of(sort(unique(c(df_final$TeamHeim, df_final$TeamGast)))),
      OriginalOrder
    ) %>%
    arrange(OriginalOrder) %>%
    select(-OriginalOrder) # remove the OriginalOrder column

  df_final <- as_tibble(df_final)
  df_final$ToreHeim <- as.numeric(df_final$ToreHeim)
  df_final$ToreGast <- as.numeric(df_final$ToreGast)

  # Each team column carries the team's InitialELO in every row where the
  # team plays. Keep it only in the first line; all other lines become NA.
  for (i in 5:ncol(df_final)) {
    col_values <- df_final[[i]]
    first_elo <- col_values[which(!is.na(col_values))[1]]
    df_final[[i]] <- c(first_elo, rep(NA_real_, nrow(df_final) - 1))
  }

  return(df_final)
}
