# Season Transition Guide

Complete guide for transitioning the League Simulator to a new season.

## Overview

Season transition is a critical process that:
- Updates team rosters for the new season
- Handles promotions and relegations
- Calculates starting ELO ratings
- Prepares the system for the new campaign

### Die TeamList ist gepflegt, nicht generiert

Der Saisonwechsel **erzeugt die TeamList nicht** — er schreibt sie fort und
schlägt vor. Über Kürzel und Zweitvertretungs-Status entscheidet der
Betreiber; die Kürzel 2026/27 stammen aus einer Handrecherche nach
DFL-Konvention (PR #186), nicht aus einem Lauf. Siehe
[ADR 0007](../adr/0007-teamlist-ist-gepflegtes-stammdatenblatt.md).

Daraus folgt ein zweiphasiger Ablauf: Phase 1 rechnet die Start-ELOs, benennt
Konflikte und schlägt für Neuzugänge etwas vor — sie schreibt einen
**Entwurf**. Phase 2 ist die Nacharbeit von Hand, und erst dadurch entsteht die
produktive `TeamList_<Jahr>.csv`.

### Wann der Lauf frühestens möglich ist

Die neue Ligazuordnung kommt **aus der API**: Der Lauf fragt
`/v3/teams?league=<id>&season=<Jahr>` je aktiver Liga einzeln ab. Ein Team
landet in der Liga, unter deren ID es zurückkommt — Auf- und Abstiege muss
niemand von Hand nachtragen.

Daraus folgt der früheste Termin: **erst, wenn api-football die Spielpläne der
kommenden Saison hinterlegt hat.** Vorher liefert die Abfrage nichts.

> **Achtung:** Ein zu früher Lauf scheitert nicht sauber. Bei einer leeren
> Antwort warnt `season_processor.R` nur („No teams for league …") und
> überspringt die Liga. Die abschliessende Teamzahl-Prüfung fängt das nicht
> zuverlässig — ihre Untergrenze ist die kleinste *einzelne* Liga (12 Teams)
> gegen 194 Soll-Teams über alle zehn. Ein Entwurf mit nur einer Liga bestünde
> sie. Deshalb: vor dem Lauf prüfen, dass alle zehn Ligen Teams liefern.

### Der Kürzel-Vertrag

Ein Kurzname (`ShortText`) muss **je Liga** eindeutig sein — dort wird er zum
Spaltennamen des Simulations-Data-Frames, und eine Dopplung vertauschte Teams
stillschweigend. Darüber hinaus gilt:

| Fall | Erlaubt? |
|---|---|
| zwei Teams derselben Liga | **nein** — das ist der Konfliktfall |
| Männer- und Frauenteam desselben Vereins | **ja, erwünscht** (SGE, HSV, SCF …, samt der „2“-Variante) |
| verschiedene Vereine in verschiedenen Ligen | **ja, geduldet** (VFB, FCH, RWE) |
| zwischen Nord, Nordost und Bayern | **nein** — sie stehen gemeinsam auf der Aufstiegsseite |

Kürzel dürfen vier Zeichen haben; das Muster `XXX2` bleibt Zweitvertretungen
vorbehalten. Maßgeblich ist stets `load_team_list()` in
`RCode/transform_data.R` — der Saisonwechsel meldet vorab, was das Laden sonst
erst hinterher ablehnt.

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
- [ ] **Rust simulation server reachable** (see below)

> **The Rust server is required.** Since [issue #146](https://github.com/chrisschwer/League-Simulator-Update/issues/146)
> the transition gets the end-of-season ELOs from `POST /league-details` instead of computing
> them in R. There is no fallback: without a reachable server the run aborts at the first
> league with `Error calculating final ELOs`.
>
> Running the command inside the production container (Method 1 and 2 below) satisfies this
> automatically — the container runs the server on port 8080. On host R, start one first or
> point `RUST_API_URL` at an existing instance:
>
> ```bash
> cd league-simulator-rust && cargo build --release
> PORT=8080 ./target/release/league-simulator-rust --api &
> curl -f http://localhost:8080/health   # expect {"status":"ok",...}
> ```
>
> This replaced a second ELO implementation in R that used a different home advantage
> (100 against the model's 40), so every season used to start on physics no forecast used.

## Season Transition Methods

### Method 1: Automated Interactive Mode

Best for: Administrators who can respond to prompts

```bash
# Run interactively
docker-compose exec -it scheduler \
  Rscript scripts/season_transition.R 2024 2025

# You will be prompted for:
# - Confirmation to proceed
# - New team information
# - Validation of changes
```

On success, the script validates the produced `TeamList_<target>.csv` and removes intermediate league files automatically.

### Method 2: Non-Interactive Mode

Best for: Automated deployments or CI/CD pipelines

```bash
# Run without prompts (uses defaults)
docker-compose exec scheduler \
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
docker-compose exec scheduler \
  Rscript scripts/season_transition.R 2024 2025 --config team_config.json
```

## Step-by-Step Process

### 1. Prepare for Transition

```bash
# Check current season data (semicolon-separated, seven columns --
# see docs/user-guide/team-management.md for the schema)
docker-compose exec scheduler Rscript -e "
  teams <- read.csv2('RCode/TeamList_2024.csv')
  cat('Current teams:', nrow(teams), '\n')
  table(teams\$League)
"

# Backup current data
tar -czf "backup_season_2024_$(date +%Y%m%d).tar.gz" RCode/TeamList_2024.csv
```

### 2. Identify Team Changes

League membership for the new season comes from the API during the
transition run itself (`/v3/teams?league=<id>&season=<Jahr>`, per active
league) — promotions and relegations do not need to be researched or
entered by hand. See "Die TeamList ist gepflegt, nicht generiert" above
and [ADR 0007](../adr/0007-teamlist-ist-gepflegtes-stammdatenblatt.md).

### 3. Gather New Team Information

For each newcomer the conflict report flags, verify:
- Official team ID from API-Football
- Correct short name (Kurzname) per DFL convention — see the Kürzel-Vertrag above
- Reserve-team promotion status

Team IDs can be looked up in the API-Football dashboard
(<https://dashboard.api-football.com>) or via the `/teams?search=<name>`
endpoint documented at <https://www.api-football.com/documentation-v3>.

### 4. Run Season Transition

```bash
# Execute transition
docker-compose exec -it scheduler \
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
docker-compose exec scheduler Rscript -e "
  teams_new <- read.csv2('RCode/TeamList_2025.csv')
  teams_old <- read.csv2('RCode/TeamList_2024.csv')

  cat('Old season teams:', nrow(teams_old), '\n')
  cat('New season teams:', nrow(teams_new), '\n')

  # Check league distribution
  cat('\nNew season league distribution:\n')
  table(teams_new\$League)

  # Show newcomers to the Bundesliga (League 78)
  cat('\nNew teams in Bundesliga:\n')
  new_bundesliga <- teams_new[teams_new\$League == 78 &
                              !(teams_new\$TeamID %in% teams_old[teams_old\$League == 78, 'TeamID']), ]
  print(new_bundesliga[, c('TeamID', 'Name', 'InitialELO')])
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

Verify the final standings against an official source (e.g. kicker.de or
the API-Football dashboard) before re-running the transition with a
corrected configuration file.

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
# Watch the scheduler pick up new TeamList file at next active window
docker-compose logs -f scheduler

# Check for errors
docker-compose logs --tail=100 scheduler | grep -i error
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
docker-compose exec -T scheduler \
  Rscript scripts/season_transition.R $OLD_SEASON $NEW_SEASON --non-interactive

# 3. Verify
echo "Verifying..."
if docker-compose exec -T scheduler test -f "RCode/TeamList_${NEW_SEASON}.csv"; then
  echo "✓ New team file created"
else
  echo "✗ ERROR: Team file not created"
  exit 1
fi

# 4. Update configuration
echo "Updating configuration..."
sed -i.bak "s/SEASON=$OLD_SEASON/SEASON=$NEW_SEASON/g" .env

echo "=== Season transition complete ==="
```

## Troubleshooting Guide

### Manual Recovery

If `scripts/season_transition.R` aborts mid-run, intermediate per-league CSV files may remain in `RCode/`. Use the recovery wrapper to remove them:

```bash
# Dry-run (default): list files that would be removed, do not delete
Rscript scripts/season_transition/cleanup.R 2025

# Actually delete
Rscript scripts/season_transition/cleanup.R 2025 --confirm
```

The wrapper only matches files of the form `TeamList_<season>_League(78|79|80)_temp.csv` in `RCode/`. It does **not** touch:

- `RCode/TeamList_<season>.csv` (the final season file)
- Any `.tmp` or `.lock` files
- Anything outside `RCode/`
- Files for other seasons

You normally do not need to run this manually — the main script auto-cleans intermediate files on successful runs. This wrapper exists for the failure-recovery case.

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
- [Quick Start](../deployment/quick-start.md) und [Deployment Overview](../deployment/README.md) — `RAPIDAPI_KEY` und die übrigen Umgebungsvariablen
- [Backup Procedures](../operations/backup-recovery.md)
- [Troubleshooting](../troubleshooting/common-issues.md#7-season-transition-failures)