library(tidyverse)
library(tidyr)

transform_data <- function(fixtures, teams) {
  
  temp_ELO <- 0
  
  fixtures_flat <- fixtures %>% unnest(cols = c(teams, goals, fixture), names_sep = "_")
  fixtures_flat <- fixtures_flat %>% unnest(cols = c(teams_home, teams_away, fixture_status), names_sep = "_")
  fixtures_flat$fixture_status_short <- replace_na(fixtures_flat$fixture_status_short, "NA")
  fixtures_flat <- fixtures_flat %>% mutate(OriginalOrder = row_number())
  
  df_home <- merge(fixtures_flat, teams, by.x = "teams_home_id", by.y = "TeamID", all.x = TRUE)
  df_home <- df_home %>% rename(TeamHeim = ShortText, ToreHeim = goals_home, ELOHome = InitialELO)
  
  df_final <- merge(df_home, teams, by.x = "teams_away_id", by.y = "TeamID", all.x = TRUE)
  df_final <- df_final %>% rename(TeamGast = ShortText, ToreGast = goals_away, ELOAway = InitialELO)
  
  for (team in unique(c(df_final$TeamHeim, df_final$TeamGast))) {
    df_final[[team]] <- ifelse(df_final$TeamHeim == team, df_final$ELOHome,
                               ifelse(df_final$TeamGast == team, df_final$ELOAway, NA))
  }
  
  # set goals to NA unless game is finished ("FT")
  
  for (i in 1:dim(df_final)[1]) {
    if (df_final$fixture_status_short[i] != "FT") {
      df_final$ToreHeim[i] <- NA
      df_final$ToreGast[i] <- NA
    }
  }
  
   
  df_final <- df_final %>%
    select(TeamHeim, TeamGast, ToreHeim, ToreGast, sort(unique(c(df_final$TeamHeim, df_final$TeamGast))), OriginalOrder) %>%
    arrange(OriginalOrder) %>%
    select(-OriginalOrder)  # remove the OriginalOrder column
  
  df_final <- as_tibble(df_final)
  df_final$ToreHeim <- as.numeric(df_final$ToreHeim)
  df_final$ToreGast <- as.numeric(df_final$ToreGast)
  
  # Find ELO-Values for team and write to first line 
  
  for (i in 5:dim(df_final)[2]) {
    for (j in 1:50) {
      if (!is.na(df_final[j, i])) {
        temp_ELO <- df_final[j, i]
      } # find the ELO-Value for the column
      df_final[1, i] <- temp_ELO # and write it to the first line
    }
    for (j in 2:dim(df_final)[1]) {
      df_final[j, i] <- NA
    } # set all other lines to NA
  }

  return(df_final)
}
