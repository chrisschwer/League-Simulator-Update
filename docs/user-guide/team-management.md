# Team Management Guide

Complete guide for managing team data in the League Simulator system.

## Team Data Structure

### CSV File Format

Team data is stored in `RCode/TeamList_YYYY.csv`:

```csv
id,name,elo,liga,season
157,Bayern Munich,1923.45,1,2025
165,Borussia Dortmund,1876.32,1,2025
168,Bayer Leverkusen,1834.49,1,2025
```

### Field Descriptions

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| id | Integer | Unique team identifier from API | 157 |
| name | String | Official team name | Bayern Munich |
| elo | Float | Current ELO rating | 1923.45 |
| liga | Integer | League level (1, 2, or 3) | 1 |
| season | Integer | Season year | 2025 |

### League Codes

- **1**: Bundesliga (18 teams)
- **2**: 2. Bundesliga (18 teams)
- **3**: 3. Liga (20 teams)

## Managing Teams

### Adding a New Team

#### Step 1: Find Team ID

```bash
# Search for team in API
docker-compose exec league-simulator Rscript -e "
  source('RCode/api_helpers.R')
  
  # Search by name
  search_team <- function(name) {
    response <- GET(
      'https://v3.football.api-sports.io/teams',
      query = list(search = name),
      add_headers('X-RapidAPI-Key' = Sys.getenv('RAPIDAPI_KEY'))
    )
    
    teams <- content(response)\$response
    for (team in teams) {
      cat(sprintf('ID: %d, Name: %s, Country: %s\n', 
                  team\$team\$id, 
                  team\$team\$name,
                  team\$team\$country))
    }
  }
  
  search_team('Holstein')
"
```

#### Step 2: Add to CSV

```r
# Load current teams
teams <- read.csv("RCode/TeamList_2025.csv")

# Create new team entry
new_team <- data.frame(
  id = 184,
  name = "Holstein Kiel",
  elo = 1400,  # Default for promoted team
  liga = 1,    # Bundesliga
  season = 2025
)

# Add to dataframe
teams <- rbind(teams, new_team)

# Sort by league and name
teams <- teams[order(teams$liga, teams$name), ]

# Save
write.csv(teams, "RCode/TeamList_2025.csv", row.names = FALSE)
```

### Updating Team Information

#### Change Team Name

```r
# Update team name (e.g., after rebranding)
teams <- read.csv("RCode/TeamList_2025.csv")

# Find and update
teams[teams$id == 167, "name"] <- "RB Leipzig"

# Save changes
write.csv(teams, "RCode/TeamList_2025.csv", row.names = FALSE)
```

#### Adjust ELO Rating

```r
# Manual ELO adjustment
adjust_team_elo <- function(team_id, new_elo, reason = "") {
  teams <- read.csv("RCode/TeamList_2025.csv")
  
  old_elo <- teams[teams$id == team_id, "elo"]
  teams[teams$id == team_id, "elo"] <- new_elo
  
  # Log change
  cat(sprintf("Team %d ELO changed: %.2f -> %.2f (%+.2f) Reason: %s\n",
              team_id, old_elo, new_elo, new_elo - old_elo, reason))
  
  write.csv(teams, "RCode/TeamList_2025.csv", row.names = FALSE)
}

# Example: Adjust after winter break
adjust_team_elo(157, 1950, "Strong winter transfers")
```

### Removing Teams

```r
# Remove relegated or dissolved teams
teams <- read.csv("RCode/TeamList_2025.csv")

# Remove team
teams <- teams[teams$id != 999, ]

# Verify removal
if (!999 %in% teams$id) {
  cat("Team 999 successfully removed\n")
}

write.csv(teams, "RCode/TeamList_2025.csv", row.names = FALSE)
```

## Bulk Operations

### Import from Previous Season

```r
# Copy teams with ELO updates
migrate_teams <- function(old_season, new_season, league_changes = list()) {
  old_teams <- read.csv(sprintf("RCode/TeamList_%d.csv", old_season))
  
  # Update season
  new_teams <- old_teams
  new_teams$season <- new_season
  
  # Apply league changes
  for (change in league_changes) {
    new_teams[new_teams$id == change$team_id, "liga"] <- change$new_liga
  }
  
  # Save new file
  write.csv(new_teams, sprintf("RCode/TeamList_%d.csv", new_season), 
            row.names = FALSE)
}

# Example with promotions/relegations
league_changes <- list(
  list(team_id = 171, new_liga = 2),  # Relegated
  list(team_id = 184, new_liga = 1)   # Promoted
)

migrate_teams(2024, 2025, league_changes)
```

### Batch ELO Updates

```r
# Update multiple teams at once
batch_elo_update <- function(updates) {
  teams <- read.csv("RCode/TeamList_2025.csv")
  
  for (update in updates) {
    team_idx <- which(teams$id == update$id)
    if (length(team_idx) > 0) {
      old_elo <- teams[team_idx, "elo"]
      teams[team_idx, "elo"] <- update$new_elo
      
      cat(sprintf("%s: %.2f -> %.2f (%+.2f)\n",
                  teams[team_idx, "name"],
                  old_elo,
                  update$new_elo,
                  update$new_elo - old_elo))
    }
  }
  
  write.csv(teams, "RCode/TeamList_2025.csv", row.names = FALSE)
}

# Apply updates
updates <- list(
  list(id = 157, new_elo = 1920),
  list(id = 165, new_elo = 1880),
  list(id = 168, new_elo = 1850)
)

batch_elo_update(updates)
```

## Validation and Quality Checks

### Team Data Validator

```r
# Comprehensive validation
validate_team_file <- function(file_path) {
  teams <- read.csv(file_path)
  errors <- list()
  warnings <- list()
  
  # Check structure
  required_cols <- c("id", "name", "elo", "liga", "season")
  missing <- setdiff(required_cols, names(teams))
  if (length(missing) > 0) {
    errors$structure <- paste("Missing columns:", paste(missing, collapse = ", "))
  }
  
  # Check duplicates
  if (any(duplicated(teams$id))) {
    dup_ids <- unique(teams$id[duplicated(teams$id)])
    errors$duplicates <- paste("Duplicate IDs:", paste(dup_ids, collapse = ", "))
  }
  
  # Check league sizes
  league_counts <- table(teams$liga)
  if ("1" %in% names(league_counts) && league_counts["1"] != 18) {
    warnings$bundesliga <- sprintf("Bundesliga has %d teams (expected 18)", 
                                   league_counts["1"])
  }
  if ("2" %in% names(league_counts) && league_counts["2"] != 18) {
    warnings$bundesliga2 <- sprintf("2. Bundesliga has %d teams (expected 18)", 
                                    league_counts["2"])
  }
  if ("3" %in% names(league_counts) && league_counts["3"] != 20) {
    warnings$liga3 <- sprintf("3. Liga has %d teams (expected 20)", 
                              league_counts["3"])
  }
  
  # Check ELO ranges
  elo_issues <- teams[teams$elo < 1000 | teams$elo > 2200, ]
  if (nrow(elo_issues) > 0) {
    warnings$elo_range <- sprintf("%d teams have unusual ELO ratings", 
                                  nrow(elo_issues))
  }
  
  # Check season consistency
  if (length(unique(teams$season)) > 1) {
    errors$season <- "Multiple seasons in same file"
  }
  
  # Report
  cat("=== Validation Report ===\n")
  if (length(errors) > 0) {
    cat("\nERRORS:\n")
    for (name in names(errors)) {
      cat("✗", name, ":", errors[[name]], "\n")
    }
  }
  
  if (length(warnings) > 0) {
    cat("\nWARNINGS:\n")
    for (name in names(warnings)) {
      cat("⚠", name, ":", warnings[[name]], "\n")
    }
  }
  
  if (length(errors) == 0 && length(warnings) == 0) {
    cat("\n✓ All checks passed!\n")
  }
  
  return(list(valid = length(errors) == 0, errors = errors, warnings = warnings))
}

# Run validation
validate_team_file("RCode/TeamList_2025.csv")
```

### Find Data Inconsistencies

```r
# Check for common issues
find_team_issues <- function() {
  teams <- read.csv("RCode/TeamList_2025.csv")
  
  # Teams with very low ELO
  low_elo <- teams[teams$elo < 1200, ]
  if (nrow(low_elo) > 0) {
    cat("Teams with unusually low ELO:\n")
    print(low_elo[, c("id", "name", "elo")])
  }
  
  # Teams with very high ELO  
  high_elo <- teams[teams$elo > 2000, ]
  if (nrow(high_elo) > 0) {
    cat("\nTeams with unusually high ELO:\n")
    print(high_elo[, c("id", "name", "elo")])
  }
  
  # Check name formatting
  name_issues <- teams[grepl("[0-9]", teams$name) | 
                      nchar(teams$name) < 3, ]
  if (nrow(name_issues) > 0) {
    cat("\nTeams with potential name issues:\n")
    print(name_issues[, c("id", "name")])
  }
  
  # League distribution
  cat("\nLeague distribution:\n")
  print(table(teams$liga))
}

find_team_issues()
```

## ELO Management

### Understanding ELO Ratings

- **Starting point**: 1500 (average team)
- **Range**: Typically 1200-2000
- **Changes**: ±32 points maximum per match (K-factor)
- **Meaning**:
  - < 1300: Weak team, relegation candidate
  - 1300-1500: Below average
  - 1500-1700: Average to above average
  - 1700-1900: Strong team, European qualification
  - > 1900: Title contender

### Calculate Initial ELO

```r
# For new teams without history
calculate_initial_elo <- function(league_level, promoted = FALSE) {
  base_elo <- switch(as.character(league_level),
    "1" = 1600,  # Bundesliga average
    "2" = 1450,  # 2. Bundesliga average
    "3" = 1350   # 3. Liga average
  )
  
  if (promoted) {
    # Promoted teams typically start below average
    base_elo <- base_elo - 150
  }
  
  # Add small random variation
  base_elo + runif(1, -25, 25)
}

# Example for promoted team
new_elo <- calculate_initial_elo(league_level = 1, promoted = TRUE)
cat("Suggested ELO for promoted team:", round(new_elo, 2), "\n")
```

### Track ELO Changes

```r
# Monitor ELO progression
track_elo_changes <- function(team_id, matches) {
  elo_history <- numeric(length(matches) + 1)
  elo_history[1] <- get_team_elo(team_id)
  
  for (i in seq_along(matches)) {
    match <- matches[[i]]
    # Apply ELO change
    elo_history[i + 1] <- calculate_new_elo(
      elo_history[i], 
      match$opponent_elo,
      match$result
    )
  }
  
  # Plot progression
  plot(elo_history, type = "l", 
       main = paste("ELO Progression for Team", team_id),
       xlab = "Matches", ylab = "ELO Rating")
  
  return(elo_history)
}
```

## Backup and Recovery

### Create Backups

```bash
#!/bin/bash
# backup_teams.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="backups/teams"

mkdir -p $BACKUP_DIR

# Backup all team files
for file in RCode/TeamList_*.csv; do
  if [ -f "$file" ]; then
    cp "$file" "$BACKUP_DIR/$(basename $file .csv)_$DATE.csv"
    echo "Backed up: $file"
  fi
done

# Create compressed archive
tar -czf "$BACKUP_DIR/teams_backup_$DATE.tar.gz" -C RCode TeamList_*.csv

echo "Backup complete: $BACKUP_DIR/teams_backup_$DATE.tar.gz"
```

### Restore from Backup

```r
# Restore team file
restore_team_file <- function(backup_date, season) {
  backup_file <- sprintf("backups/teams/TeamList_%d_%s.csv", 
                        season, backup_date)
  
  if (!file.exists(backup_file)) {
    stop("Backup file not found: ", backup_file)
  }
  
  # Create safety backup of current
  current_file <- sprintf("RCode/TeamList_%d.csv", season)
  if (file.exists(current_file)) {
    file.copy(current_file, 
              sprintf("RCode/TeamList_%d_before_restore.csv", season))
  }
  
  # Restore
  file.copy(backup_file, current_file, overwrite = TRUE)
  
  cat("Restored from:", backup_file, "\n")
  
  # Validate restored file
  validate_team_file(current_file)
}
```

## Integration with API

### Sync with API Data

```r
# Update team names from API
sync_team_names <- function(season) {
  teams <- read.csv(sprintf("RCode/TeamList_%d.csv", season))
  updated <- 0
  
  for (i in 1:nrow(teams)) {
    team_id <- teams$id[i]
    
    # Fetch from API
    api_team <- get_team_from_api(team_id)
    
    if (!is.null(api_team) && api_team$name != teams$name[i]) {
      cat(sprintf("Updating team %d: '%s' -> '%s'\n",
                  team_id, teams$name[i], api_team$name))
      teams$name[i] <- api_team$name
      updated <- updated + 1
    }
  }
  
  if (updated > 0) {
    write.csv(teams, sprintf("RCode/TeamList_%d.csv", season), 
              row.names = FALSE)
    cat(sprintf("Updated %d team names\n", updated))
  } else {
    cat("All team names are current\n")
  }
}
```

### Verify API IDs

```r
# Check if team IDs are valid
verify_team_ids <- function() {
  teams <- read.csv("RCode/TeamList_2025.csv")
  invalid_ids <- c()
  
  for (team_id in unique(teams$id)) {
    response <- GET(
      sprintf("https://v3.football.api-sports.io/teams?id=%d", team_id),
      add_headers("X-RapidAPI-Key" = Sys.getenv("RAPIDAPI_KEY"))
    )
    
    if (status_code(response) == 200) {
      data <- content(response)
      if (length(data$response) == 0) {
        invalid_ids <- c(invalid_ids, team_id)
      }
    }
  }
  
  if (length(invalid_ids) > 0) {
    cat("Invalid team IDs found:", paste(invalid_ids, collapse = ", "), "\n")
  } else {
    cat("All team IDs are valid\n")
  }
  
  return(invalid_ids)
}
```

## Team Management Scripts

### Complete Management Script

Save as `manage_teams.R`:

```r
#!/usr/bin/env Rscript

# Team management utility
library(optparse)

# Command line options
option_list <- list(
  make_option(c("-a", "--action"), type = "character", 
              help = "Action: add, update, remove, validate, backup"),
  make_option(c("-i", "--id"), type = "integer",
              help = "Team ID"),
  make_option(c("-n", "--name"), type = "character",
              help = "Team name"),
  make_option(c("-e", "--elo"), type = "numeric",
              help = "ELO rating"),
  make_option(c("-l", "--liga"), type = "integer",
              help = "League (1, 2, or 3)"),
  make_option(c("-s", "--season"), type = "integer",
              default = as.integer(format(Sys.Date(), "%Y")),
              help = "Season year")
)

opt <- parse_args(OptionParser(option_list = option_list))

# Load functions
source("RCode/team_management_functions.R")

# Execute action
switch(opt$action,
  "add" = {
    add_team(opt$id, opt$name, opt$elo, opt$liga, opt$season)
  },
  "update" = {
    update_team(opt$id, opt$name, opt$elo, opt$liga, opt$season)
  },
  "remove" = {
    remove_team(opt$id, opt$season)
  },
  "validate" = {
    validate_team_file(sprintf("RCode/TeamList_%d.csv", opt$season))
  },
  "backup" = {
    backup_teams(opt$season)
  },
  {
    cat("Unknown action. Use: add, update, remove, validate, backup\n")
  }
)
```

### Usage Examples

```bash
# Add new team
Rscript manage_teams.R --action add --id 999 --name "New FC" --elo 1400 --liga 2

# Update ELO
Rscript manage_teams.R --action update --id 157 --elo 1950

# Validate file
Rscript manage_teams.R --action validate --season 2025

# Create backup
Rscript manage_teams.R --action backup --season 2025
```

## Best Practices

1. **Always backup** before making changes
2. **Validate after** bulk operations
3. **Document changes** in commit messages
4. **Use official** team names from API
5. **Maintain consistent** ELO ranges
6. **Test simulations** after major changes
7. **Keep historical** files for reference

## Related Documentation

- [Season Transition](season-transition.md)
- [ELO System](../architecture/data-flow.md#elo-calculation)
- [API Reference](../architecture/api-reference.md)
- [Data Validation](../troubleshooting/debugging.md#data-validation)