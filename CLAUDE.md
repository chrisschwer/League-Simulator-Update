# CLAUDE.md

This file provides essential context for Claude Code when working with the League Simulator codebase.

## Project Overview

League Simulator is a football league prediction system using Monte Carlo simulations and ELO ratings to predict final standings for German football leagues (Bundesliga, 2. Bundesliga, 3. Liga).

## Quick Commands

```bash
# Run tests
source("tests/testthat.R")

# Run single update
Rscript run_single_update_2025.R

# Build and run Docker (simple version)
docker build -f Dockerfile.simple -t league-simulator:simple .
docker-compose -f docker-compose.simple.yml up -d

# Season transition
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

For complete command reference, see @docs/COMMANDS.md

## Architecture

Four main components:
1. **Simulation Engine** - Rcpp-based Monte Carlo simulations with ELO ratings
2. **Scheduler** - Automated updates at match times (Berlin timezone)
3. **Season Transition** - Handles promotions/relegations between seasons
4. **Web Interface** - Shiny app displaying probability heatmaps

For detailed architecture, see @docs/architecture/overview.md

## Required Environment

```bash
RAPIDAPI_KEY=your_api_key  # Required for API-Football access
```

For all environment variables, see @docs/deployment/quick-start.md

## Workflow

This project uses the Claude Code development workflow with human approval gates.

Key commands:
- `/newissue` - Create GitHub issue
- `/makeprogress` - Advance issue through workflow
- `/list_human_todo` - Show issues awaiting review

For complete workflow documentation, see @.claude/workflow.md

## Current Status

- **Test Suite**: 🚧 38 tests failing - repair in progress (see @docs/TEST_FIX_PLAN.md)
- **Season**: 2024-2025
- **API**: api-football via RapidAPI

## Documentation

- **Documentation Index**: @docs/README.md
- **Known Issues**: @docs/KNOWN_ISSUES.md
- **Commands**: @docs/COMMANDS.md
- **Architecture**: @docs/architecture/
- **Deployment**: @docs/deployment/
  - **Simple Deployment** (Recommended): @docs/deployment/simple-monolithic.md
  - **Quick Start**: @docs/deployment/quick-start.md
- **Operations**: @docs/operations/
- **Troubleshooting**: @docs/troubleshooting/

## Note on Documentation

This file is intentionally concise. Detailed information is lazy-loaded via @mentions from the docs/ directory to improve Claude Code performance and context management.
