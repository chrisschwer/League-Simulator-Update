# Season Transition Guide

Complete guide for transitioning the League Simulator to a new season.

## Overview

Season transition is a critical process that:
- Updates team rosters for the new season
- Handles promotions and relegations
- Calculates starting ELO ratings
- Prepares the system for the new campaign

## When to Run Season Transition

### Timing

- **Optimal time**: After all playoffs/relegation matches complete
- **Typical date**: Late May or early June
- **Before**: First matches of new season
- **Duration**: Allow 2-3 hours for full process

### Prerequisites

- [ ] All matches from previous season completed
- [ ] Promotion/relegation decided
- [ ] API key valid and has quota
- [ ] Backup of current season data completed
- [ ] Team information for promoted teams available

## Season Transition Methods

### Method 1: Automated Interactive Mode

Best for: Administrators who can respond to prompts

```bash
# Run interactively
docker-compose exec -it league-simulator \
  Rscript scripts/season_transition.R 2024 2025

# You will be prompted for:
# - Confirmation to proceed
# - New team information
# - Validation of changes
```

### Method 2: Non-Interactive Mode

Best for: Automated deployments or CI/CD pipelines

```bash
# Run without prompts (uses defaults)
docker-compose exec league-simulator \
  Rscript scripts/season_transition.R 2024 2025 --non-interactive

# Note: New teams will get default values
```

### Method 3: Configuration File Mode

Best for: Prepared transitions with known team changes

```bash
# First, create configuration file
cat > team_config.json << EOF
{
  "new_teams": {
    "999": {
      "name": "Holstein Kiel",
      "league": 1,
      "elo": 1400
    },
    "998": {
      "name": "St. Pauli",
      "league": 1,
      "elo": 1420
    }
  },
  "relegated_teams": [171, 164],
  "promoted_teams": [999, 998]
}
EOF

# Run with config
docker-compose exec league-simulator \
  Rscript scripts/season_transition.R 2024 2025 --config team_config.json
```

## Step-by-Step Process

### 1. Prepare for Transition

```bash
# Check current season data
docker-compose exec league-simulator Rscript -e "
  teams <- read.csv('RCode/TeamList_2024.csv')
  cat('Current teams:', nrow(teams), '\n')
  table(teams\$liga)
"

# Backup current data
./scripts/backup_season.sh 2024
```

### 2. Identify Team Changes

Research promoted and relegated teams:

**Bundesliga (League 78)**:
- Bottom 2 teams relegated to 2. Bundesliga
- 16th place enters relegation playoff
- Top 2 from 2. Bundesliga promoted
- 3rd place from 2. Bundesliga in playoff

**2. Bundesliga (League 79)**:
- Bottom 2 teams relegated to 3. Liga
- 16th place enters relegation playoff
- Top 2 from 3. Liga promoted
- 3rd place from 3. Liga in playoff

**3. Liga (League 80)**:
- Bottom 4 teams relegated to Regionalliga
- Champion from each Regionalliga eligible for promotion

### 3. Gather New Team Information

For each promoted team, collect:
- Official team ID from API-Football
- Correct team name spelling
- Previous season performance (for ELO calculation)

```bash
# Check API for team information
docker-compose exec league-simulator Rscript -e "
  source('RCode/api_helpers.R')
  # Search for team
  search_team('Holstein Kiel')
"
```

### 4. Run Season Transition

```bash
# Execute transition
docker-compose exec -it league-simulator \
  Rscript scripts/season_transition.R 2024 2025

# Monitor output for:
# - Teams being moved between leagues
# - ELO rating calculations
# - New team additions
# - File creation confirmation
```

### 5. Verify Results

```bash
# Check new team file
docker-compose exec league-simulator Rscript -e "
  teams_new <- read.csv('RCode/TeamList_2025.csv')
  teams_old <- read.csv('RCode/TeamList_2024.csv')
  
  cat('Old season teams:', nrow(teams_old), '\n')
  cat('New season teams:', nrow(teams_new), '\n')
  
  # Check league distribution
  cat('\nNew season league distribution:\n')
  table(teams_new\$liga)
  
  # Show promoted teams
  cat('\nNew teams in Bundesliga:\n')
  new_bundesliga <- teams_new[teams_new\$liga == 1 & 
                              !(teams_new\$id %in% teams_old[teams_old\$liga == 1, 'id']), ]
  print(new_bundesliga[, c('id', 'name', 'elo')])
"
```

## ELO Rating Calculations

### How ELO Ratings Are Determined

1. **Existing teams**: Carry forward from previous season
2. **Promoted teams**:
   - From 2. Bundesliga to Bundesliga: ~1400-1450
   - From 3. Liga to 2. Bundesliga: ~1350-1400
   - From Regionalliga to 3. Liga: ~1300-1350
3. **Relegated teams**: Keep current rating

### Manual ELO Adjustments

If needed, adjust ELO ratings post-transition:

```r
# Edit team file manually
teams <- read.csv("RCode/TeamList_2025.csv")

# Adjust specific team
teams[teams$name == "Holstein Kiel", "elo"] <- 1425

# Save changes
write.csv(teams, "RCode/TeamList_2025.csv", row.names = FALSE)
```

## Common Issues and Solutions

### Issue: Script Hangs Waiting for Input

**Solution**: Use non-interactive mode or config file

```bash
# Add --non-interactive flag
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

### Issue: New Team Not Found in API

**Solution**: Manually add team information

```r
# Create manual entry
new_team <- data.frame(
  id = 999,
  name = "Holstein Kiel",
  elo = 1400,
  liga = 1,
  season = 2025
)

# Append to team list
teams <- rbind(teams, new_team)
```

### Issue: Wrong Teams Relegated

**Solution**: Verify final standings and adjust

```bash
# Check final standings
docker-compose exec league-simulator Rscript -e "
  source('RCode/get_final_standings.R')
  standings <- get_final_standings(78, 2024)
  print(tail(standings, 5))  # Bottom 5 teams
"
```

### Issue: ELO Ratings Seem Wrong

**Solution**: Recalculate based on recent performance

```r
# Adjust ELO based on final position
adjust_elo_by_position <- function(team_id, final_position, league_size) {
  base_elo <- teams[teams$id == team_id, "elo"]
  
  # Adjustment based on final position
  position_factor <- (league_size - final_position) / league_size
  adjustment <- (position_factor - 0.5) * 100
  
  new_elo <- base_elo + adjustment
  return(max(1200, min(2000, new_elo)))  # Keep within bounds
}
```

## Configuration File Format

### Complete Configuration Example

```json
{
  "season_info": {
    "old_season": 2024,
    "new_season": 2025,
    "transition_date": "2024-06-01"
  },
  
  "new_teams": {
    "999": {
      "name": "Holstein Kiel",
      "league": 1,
      "elo": 1400,
      "api_football_id": 184
    },
    "998": {
      "name": "FC St. Pauli",
      "league": 1,
      "elo": 1420,
      "api_football_id": 185
    }
  },
  
  "league_changes": {
    "relegated_from_bundesliga": [171, 164],
    "promoted_to_bundesliga": [999, 998],
    "relegated_from_2bundesliga": [180, 181],
    "promoted_to_2bundesliga": [996, 997],
    "relegated_from_3liga": [190, 191, 192, 193],
    "promoted_to_3liga": [994, 995]
  },
  
  "elo_adjustments": {
    "171": -50,
    "999": 25
  },
  
  "validation": {
    "expected_bundesliga_teams": 18,
    "expected_2bundesliga_teams": 18,
    "expected_3liga_teams": 20
  }
}
```

## Post-Transition Checklist

### Immediate Verification

- [ ] New TeamList CSV file created
- [ ] Correct number of teams per league
- [ ] All promoted teams included
- [ ] All relegated teams moved
- [ ] ELO ratings look reasonable
- [ ] No duplicate team IDs
- [ ] Season column updated

### First Simulation Test

```bash
# Run test simulation
docker-compose exec league-simulator \
  Rscript run_single_update_2025.R

# Check for errors
docker-compose logs --tail=100 league-simulator | grep ERROR
```

### Update Configuration

```bash
# Update environment for new season
sed -i 's/SEASON=2024/SEASON=2025/g' .env

# Restart services
docker-compose restart
```

## Automation Script

Save as `auto_season_transition.sh`:

```bash
#!/bin/bash
# Automated season transition script

OLD_SEASON=$1
NEW_SEASON=$2

echo "=== Automated Season Transition ==="
echo "From: $OLD_SEASON"
echo "To: $NEW_SEASON"

# 1. Backup
echo "Creating backup..."
tar -czf "backup_season_${OLD_SEASON}.tar.gz" RCode/TeamList_${OLD_SEASON}.csv

# 2. Run transition
echo "Running transition..."
docker-compose exec -T league-simulator \
  Rscript scripts/season_transition.R $OLD_SEASON $NEW_SEASON --non-interactive

# 3. Verify
echo "Verifying..."
if docker-compose exec -T league-simulator test -f "RCode/TeamList_${NEW_SEASON}.csv"; then
  echo "✓ New team file created"
else
  echo "✗ ERROR: Team file not created"
  exit 1
fi

# 4. Test simulation
echo "Testing simulation..."
docker-compose exec -T league-simulator \
  timeout 300 Rscript -e "
    Sys.setenv(SEASON = '$NEW_SEASON')
    source('RCode/leagueSimulatorCPP.R')
    simulate_league(78, iterations = 100)
  "

if [ $? -eq 0 ]; then
  echo "✓ Test simulation successful"
else
  echo "✗ ERROR: Test simulation failed"
  exit 1
fi

# 5. Update configuration
echo "Updating configuration..."
sed -i.bak "s/SEASON=$OLD_SEASON/SEASON=$NEW_SEASON/g" .env

echo "=== Season transition complete ==="
```

## Troubleshooting Guide

### Debug Mode

Run with verbose output:

```r
# Enable debugging
Sys.setenv(SEASON_TRANSITION_DEBUG = "TRUE")

# Run transition
source("scripts/season_transition.R")
```

### Manual Recovery

If transition fails partially:

```r
# Load partial results
if (file.exists("RCode/TeamList_2025_partial.csv")) {
  teams <- read.csv("RCode/TeamList_2025_partial.csv")
  
  # Complete missing steps manually
  # ... make corrections ...
  
  # Save final version
  write.csv(teams, "RCode/TeamList_2025.csv", row.names = FALSE)
}
```

### Rollback Procedure

If transition needs to be reverted:

```bash
# Restore backup
cp backup_season_2024.tar.gz /tmp/
cd /tmp && tar -xzf backup_season_2024.tar.gz
cp TeamList_2024.csv /app/RCode/

# Revert configuration
sed -i 's/SEASON=2025/SEASON=2024/g' .env

# Restart services
docker-compose restart
```

## Best Practices

1. **Always backup** before running transition
2. **Test in development** environment first
3. **Verify team changes** against official sources
4. **Document any manual** adjustments made
5. **Run test simulations** before going live
6. **Monitor first few** update cycles closely
7. **Keep transition log** for future reference

## Related Documentation

- [Team Management](team-management.md)
- [API Configuration](../deployment/quick-start.md#api-configuration)
- [Backup Procedures](../operations/backup-recovery.md)
- [Troubleshooting](../troubleshooting/common-issues.md#season-transition)