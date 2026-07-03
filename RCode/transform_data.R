library(dplyr)
library(tidyr)

transform_data <- function(fixtures, teams) {
  # API-Football includes relegation playoff games as round "Final" in the
  # league fixture list; only regular-season rounds belong in the simulation
  rounds <- if ("league" %in% names(fixtures)) fixtures$league$round else NULL
  if (!is.null(rounds)) {
    fixtures <- fixtures[startsWith(as.character(rounds), "Regular Season"), ]
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
