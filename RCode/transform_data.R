library(dplyr)
library(tidyr)

# Am gruenen Tisch gewertete Spiele (api-football). Ihr Ergebnis steht fest
# und zaehlt fuer die Tabelle, bewegt aber die Staerkeschaetzung nicht
# (Issue #157). Eigene Konstante statt eines Verweises auf league_details.R,
# damit transform_data.R ohne dieses Modul lauffaehig bleibt -- die Tests
# sourcen es einzeln.
STATUS_AWARDED_SIM <- c("AWD", "WO")

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
#' Bei 56 Teams in drei Ligen war jede Dopplung ein Versehen. Mit zehn Ligen
#' und 175 aktiven Teams (247 Zeilen inklusive historischer) sind Kollisionen
#' ueber Ligagrenzen hinweg der Normalfall -- und teils gewollt.
#'
#' Massgeblich ist die LIGA, nicht die gesamte Liste und nicht die
#' Wechselgemeinschaft. transform_data() wird je Liga aufgerufen; nur Teams
#' derselben Liga werden je zu Spalten desselben Data-Frames. Eine Dopplung
#' ueber Ligagrenzen hinweg kann dort also keinen Schaden anrichten.
#'
#' Sie ist sogar erwuenscht: So traegt jeder Verein das Kuerzel, unter dem er
#' bekannt ist, statt eines Ausweichnamens -- die Frauenmannschaft dasselbe
#' wie die Herrenmannschaft (SCF, RBL, HSV), und VfB Stuttgart (78) wie VfB
#' Luebeck (84) beide VFB. In der Darstellung ueberschneiden sie sich nicht,
#' jede Liga hat ihre eigene Seite.
#'
#' KORRIGIERT mit Issue #129: Hier stand bis hierher, massgeblich sei die
#' WECHSELGEMEINSCHAFT. Das beschrieb den Stand vor PR #183 (Commit b680302)
#' und widersprach seither der Implementierung 40 Zeilen tiefer sowie dem
#' Inline-Kommentar direkt darueber. Die Lockerung war eine Entscheidung
#' Christophs: Wo ein Kuerzel fuer einen Verein eingefuehrt ist, bekommt er
#' es -- massgeblich ist nicht die Haeufigkeit des Namensbestandteils,
#' sondern welcher Verein darunter bekannt ist.
#'
#' EINE Ausnahme bleibt hart, s. u.: Nord (84), Nordost (85) und Bayern (83)
#' muessen UNTEREINANDER eindeutig sein. Zwei von ihnen bestreiten jaehrlich
#' die Aufstiegsspiele, und aufstiegswahrscheinlichkeit() ordnet die
#' Zweikampfquoten ueber NAMEN zu -- dort vertauschte ein doppeltes Kuerzel
#' zwei Teams, ohne dass etwas fehlschlaegt.
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

  # Kurznamen je LIGA pruefen, nicht je Wechselgemeinschaft.
  #
  # Bis September 2026 galt Eindeutigkeit je Wechselgemeinschaft. Das war zu
  # streng: Es verbot VFB fuer den VfB Stuttgart (78) neben dem VfB Luebeck
  # (84), obwohl beide Vereine unter diesem Kuerzel bekannt sind. Dasselbe
  # bei FCH (1. FC Heidenheim / F.C. Hansa Rostock) und RWE (Rot-Weiss
  # Essen / Rot-Weiss Erfurt). Entscheidung Christoph: Wo ein Kuerzel fuer
  # einen Verein eingefuehrt ist, bekommt er es -- massgeblich ist nicht die
  # Haeufigkeit des Namensbestandteils, sondern welcher Verein darunter
  # bekannt ist.
  #
  # Innerhalb einer Liga bleibt es scharf: Dort wird ShortText in
  # transform_data() zum Spaltennamen, eine Dopplung vertauschte Teams
  # stillschweigend. Ohne League-Spalte (TeamList bis Saison 2025) gilt die
  # ganze Liste als eine Gruppe.
  gruppe <- if ("League" %in% names(teams)) {
    as.character(teams$League)
  } else {
    rep("alle", nrow(teams))
  }

  dup_short <- unique(unlist(lapply(split(teams$ShortText, gruppe), function(x) {
    x[duplicated(x)]
  })))
  if (length(dup_short) > 0) {
    stop(sprintf(
      paste0(
        "load_team_list: Kurznamen sind innerhalb einer Liga nicht eindeutig ",
        "in %s: %s. ShortText wird in transform_data() zum Spaltennamen -- ",
        "doppelte Kurznamen vertauschen Teams stillschweigend."
      ),
      file_path, paste(dup_short, collapse = ", ")
    ), call. = FALSE)
  }

  # Die harte Ausnahme: Nord (84), Nordost (85) und Bayern (83) muessen
  # UNTEREINANDER eindeutig bleiben. Zwei von ihnen bestreiten jaehrlich die
  # Aufstiegsspiele und stehen dann GEMEINSAM auf der Aufstiegsseite -- zwei
  # gleiche Kuerzel nebeneinander waeren dort fuer den Leser nicht zu
  # unterscheiden. Welche zwei Staffeln es trifft, beschliesst das
  # DFB-Praesidium jaehrlich neu; alle drei frei zu halten ist die einzige
  # Fassung, die nicht jedes Jahr nachgezogen werden muss.
  #
  # KORRIGIERT (Issue #197): Hier stand, aufstiegswahrscheinlichkeit() ordne
  # ueber NAMEN zu und ein doppeltes Kuerzel vertausche zwei Teams. Das traegt
  # nicht: rl_aufstieg.R indiziert zwar per Name (p_sieg[names(x), names(y)]),
  # aber die eine Staffel steht auf der Zeilen-, die andere auf der
  # Spaltenachse -- ein gleiches Kuerzel ueber die Staffelgrenze hinweg
  # vertauscht nichts. Der stille Tausch (R liefert bei doppeltem Zeilennamen
  # zweimal die erste Zeile) braeuchte eine Dopplung INNERHALB einer Staffel,
  # und die verbietet bereits die Regel darueber. Die Ausnahme bleibt als
  # Lesbarkeitsregel -- mit dem Grund, der wirklich zutrifft.
  if ("League" %in% names(teams)) {
    playoff_ligen <- c("83", "84", "85")
    in_playoff <- as.character(teams$League) %in% playoff_ligen
    kurz <- teams$ShortText[in_playoff]
    dup_playoff <- unique(kurz[duplicated(kurz)])
    if (length(dup_playoff) > 0) {
      stop(sprintf(
        paste0(
          "load_team_list: Kurznamen sind zwischen den Aufstiegsspiel-Staffeln ",
          "(Nord, Nordost, Bayern) nicht eindeutig in %s: %s. Zwei dieser drei ",
          "spielen jaehrlich gegeneinander um den Aufstieg; die Doppelsumme ",
          "ordnet ueber Namen zu und vertauschte die Teams stillschweigend."
        ),
        file_path, paste(dup_playoff, collapse = ", ")
      ), call. = FALSE)
    }
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

  # Tore nur behalten, wenn das Ergebnis feststeht; sonst NA, damit die
  # Simulation das Spiel auswuerfelt.
  #
  # FT/AET/PEN sind regulaer beendet. AWD/WO sind am gruenen Tisch gewertet:
  # sportrechtlich ein Ergebnis, das fuer die Endtabelle zaehlt -- die
  # Simulation darf es also nicht neu auswuerfeln. Dass es die
  # Staerkeschaetzung trotzdem nicht bewegt, leistet nicht diese Funktion,
  # sondern das Flag `elo_neutral` im Simulations-Request (Issue #157).
  ergebnis_steht <- c("FT", "AET", "PEN", STATUS_AWARDED_SIM)
  unfinished <- !df_final$fixture_status_short %in% ergebnis_steht

  # Status vor dem select() sichern -- danach traegt df_final nur noch Tore
  # und Teamspalten. arrange(OriginalOrder) stellt die Eingabereihenfolge
  # wieder her, in der auch dieser Vektor steht.
  df_final_status <- df_final$fixture_status_short[order(df_final$OriginalOrder)]
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

  # Welche Spiele am gruenen Tisch gewertet wurden -- als Attribut, nicht als
  # Spalte: Die Spaltenstruktur ist Vertrag (ab Spalte 5 Teams, numberTeams =
  # ncol - 4), eine zusaetzliche Spalte wuerde sie brechen. Das Attribut reist
  # zeilengleich mit und wird von leagueSimulatorRust() als `elo_neutral` an
  # die Engine gereicht: Ergebnis zaehlt fuer die Endtabelle, ELO-Walk
  # ueberspringt es (Issue #157).
  attr(df_final, "elo_neutral") <-
    df_final_status %in% STATUS_AWARDED_SIM

  return(df_final)
}
