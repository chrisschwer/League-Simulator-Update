# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Testing
```r
# Run all tests
source("tests/testthat.R")

# Run specific test file
testthat::test_file("tests/testthat/test-prozent.R")

# Test API connection
Rscript test_api_connection.R

# Test ELO calculation
Rscript test_elo_fix.R
```

### Running Updates
```bash
# Single update for initial prognoses
Rscript run_single_update_2025.R

# Continuous update loop (production)
Rscript RCode/updateScheduler.R
```

### Docker Operations
```bash
# Build Docker image
docker build -t league-simulator .

# Run container with required environment variables
docker run -e RAPIDAPI_KEY=your_api_key \
           -e SHINYAPPS_IO_SECRET=your_shiny_secret \
           -e DURATION=480 \
           -e SEASON=2024 \
           league-simulator
```

### Local Development
```r
# Install dependencies from packagelist.txt
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])

# Run Shiny app locally
shiny::runApp("ShinyApp/app.R")

# Run automated season transition script
Rscript scripts/season_transition.R 2023 2024

# Run season transition with configuration (recommended)
Rscript scripts/season_transition.R 2024 2025 --config examples/team_config.json

# Run season transition non-interactively
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

## Architecture

This is a football league simulation system with four main components:

1. **Simulation Engine (Rcpp)**: Core logic in `RCode/` that uses ELO ratings to simulate match outcomes. Key files:
   - `simulationsCPP.R`: Main simulation orchestrator that runs Monte Carlo simulations
   - `SpielNichtSimulieren.cpp`: Updates ELO ratings based on actual results
   - `leagueSimulatorCPP.R`: Wrapper that coordinates data retrieval and simulation

2. **Scheduler System**: Automated update cycle managed by:
   - `updateScheduler.R`: Runs updates at specific times (15:00, 15:30, 16:00, 17:30, 18:00, 21:00, 23:00 Berlin time)
   - `update_all_leagues_loop.R`: Processes all three leagues (Bundesliga, 2. Bundesliga, 3. Liga)
   - Active window: 14:45-23:00, then sleeps for 3 hours

3. **Season Transition System**: Automated season transition script that:
   - Validates season completion and creates team lists for new seasons
   - Calculates final ELO ratings and Liga3 relegation baselines
   - Fetches team data from API with interactive prompts for new teams
   - Generates properly formatted `TeamList_YYYY.csv` files
   - Main script: `scripts/season_transition.R` with 13 supporting modules

4. **Web Interface**: Shiny app in `ShinyApp/app.R` that:
   - Displays probability heatmaps for final league standings
   - Shows last update timestamp
   - Reads simulation results from `/ShinyApp/data/Ergebnis.Rds`

## Key Technical Details

- **API Integration**: Uses api-football via RapidAPI (requires `RAPIDAPI_KEY`)
- **ELO System**: Initial ratings in `TeamList_YYYY.csv`, updates based on match results
- **Simulation**: Default 10,000 Monte Carlo iterations per update cycle
- **Deployment**: Automated to shinyapps.io via `updateShiny.R`

## Environment Variables

Required for production:
- `RAPIDAPI_KEY`: API authentication for football data
- `SHINYAPPS_IO_SECRET`: Deployment credentials for shinyapps.io
- `DURATION`: Update cycle duration in minutes (default: 480)
- `SEASON`: Current season year (e.g., "2024")

## Development Workflow

This project uses a quality-controlled development pipeline with human approval gates. Issues progress through the following stages:

### Workflow Stages

1. **New Issue** (`status:new`)
   - Initial issue creation via `/newissue` command
   - Ready for analysis

2. **In-Depth Analysis** (`status:in_depth_analysis`)
   - Technical analysis of requirements and impact
   - Identifies risks and dependencies

3. **Tests Written** (`status:tests_written`)
   - Comprehensive test specifications created
   - **Human Approval Required**: Tests must be reviewed

4. **Tests Approved** (`tests:approved`)
   - Human has approved test specifications
   - Ready for implementation planning

5. **Plan Written** (`status:plan_written`)
   - Detailed implementation plan created
   - **Human Approval Required**: Plan must be reviewed

6. **Plan Approved** (`plan:approved`)
   - Human has approved implementation plan
   - Ready for coding

7. **Implementation** (`status:implementation`)
   - Active development phase
   - Following approved plan

8. **Tested** (`status:tested`)
   - All tests passing
   - Ready for quality checks

9. **Linting** (`status:linting`)
   - Code quality verification complete
   - Ready for PR

10. **PR Created** (`status:pr_created`)
    - Pull request submitted
    - **Human Approval Required**: Code review and merge

### Key Commands

- `/makeprogress [issue#]`: Advance issue to next workflow stage
- `/approve_issue [issue#]`: Human approval at quality gates
- `/reject_issue [issue#] "feedback"`: Human rejection with feedback
- `/list_human_todo`: Show all issues awaiting human review
- `/meta-plan`: Analyze dependencies and suggest work order

### GitHub Project Setup

Configure your GitHub Project board with these columns:
- **New Issues**: Items with `status:new`
- **Analysis**: Items with `status:in_depth_analysis`
- **Test Writing**: Items with `status:tests_written`
- **⏸️ Awaiting Test Approval**: Human review needed
- **Plan Writing**: Items with `status:plan_written`
- **⏸️ Awaiting Plan Approval**: Human review needed
- **Implementation**: Active development
- **Testing & QA**: Items in test/lint phase
- **⏸️ Awaiting PR Approval**: Code review needed
- **✅ Completed**: Merged PRs

### Required Labels

Create these labels in your GitHub repository:
- Status labels: `status:new`, `status:in_depth_analysis`, `status:tests_written`, `status:plan_written`, `status:implementation`, `status:tested`, `status:linting`, `status:pr_created`
- Approval labels: `tests:approved`, `plan:approved`, `needs:revision`
- Priority labels: `priority:critical`, `priority:high`, `priority:medium`, `priority:low`
- Type labels: `type:feature`, `type:bug`, `type:enhancement`, `type:documentation`

## Environment Variables & Security

### Required Variables (.Renviron)
```bash
# API-Football access via RapidAPI
RAPIDAPI_KEY=your_rapidapi_key_here

# ShinyApps.io deployment (optional)
SHINYAPPS_IO_NAME=your_username
SHINYAPPS_IO_TOKEN=your_token
SHINYAPPS_IO_SECRET=your_secret
```

### Security Best Practices
- Never commit `.Renviron` files (already in .gitignore)
- Rotate API keys regularly
- Use environment-specific keys (dev/prod)
- Never share credentials in chat/issues/logs

## Known Issues & Solutions

### Interactive Prompts in Season Transition (Fixed in PR #22)
**Issue**: Season transition script gets stuck in infinite loop when running via `Rscript`
**Root Cause**: `readline()` returns empty strings in non-interactive mode
**Solution**: Use universal input handler in `RCode/input_handler.R`

```r
# New approach that works in all contexts
get_user_input("Enter value: ", default = "default")
```

**Usage Options**:
- Interactive: `Rscript scripts/season_transition.R 2024 2025`
- Non-interactive: `Rscript scripts/season_transition.R 2024 2025 --non-interactive`
- Config file: `Rscript scripts/season_transition.R 2024 2025 --config examples/team_config.json`

### ELO Calculation Issues (Resolved - July 2025)
**Issue**: ELO ratings not updating during season transition despite teams playing many matches
**Root Cause**: Missing or invalid `RAPIDAPI_KEY` environment variable preventing API calls
**Solution**: Ensure valid API key is set before running season transition

```bash
# Required for ELO calculations
export RAPIDAPI_KEY="your_valid_rapidapi_key"
```

**Technical Details**:
- ELO system correctly maintains existing values when no match data available
- `retrieveResults(league, season)` requires valid API access to fetch match results
- Without matches, ELO calculations skip updates (expected behavior)
- Multi-season transitions (e.g., 2023→2025) work correctly when API key is valid

**Verification**: Check ELO changes in output logs:
```
Team 168 ELO change: 1765 -> 1834 ( +69 )  # With match data
Team 168 ELO change: 1765 -> 1765 ( 0 )    # Without match data
```