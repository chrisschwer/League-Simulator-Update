# Season Transition Interactive Prompts Fix

## Overview

This document describes the fix implemented for issue #21, which resolved the infinite loop problem in the season transition script when running via `Rscript`.

## Problem

When running the season transition script using `Rscript`, the interactive prompts for new team information would not display to the user. Instead, `readline()` would immediately return empty strings, causing infinite loops in the confirmation prompts.

## Solution

We implemented a multi-layered solution:

1. **Universal Input Handler**: Created a new `input_handler.R` module that detects the execution environment and uses the appropriate input method
2. **Scan() Fallback**: For Rscript execution with a terminal, we use `scan()` instead of `readline()`
3. **Configuration File Support**: Added ability to provide team data via JSON configuration files
4. **Retry Limits**: Implemented maximum retry limits to prevent infinite loops

## Usage

### Interactive Mode (Default)

Run the script normally and it will prompt for team information:

```bash
Rscript scripts/season_transition.R 2024 2025
```

If you have a terminal attached, you'll now see prompts like:
```
=== New Team Information Required ===
Team Name: Energie Cottbus
League: 3. Liga
Enter 3-character short name for Energie Cottbus
Suggested: ENE
Short name (press Enter for suggestion): 
```

### Non-Interactive Mode

For automated environments without user interaction:

```bash
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

This uses default values for all prompts.

### Configuration File Mode

Provide team data via a JSON configuration file:

```bash
Rscript scripts/season_transition.R 2024 2025 --config team_config.json
```

Example configuration file:

```json
{
  "new_teams": {
    "Energie Cottbus": {
      "short_name": "ENE",
      "initial_elo": 1046,
      "promotion_value": 0,
      "league": "3. Liga"
    },
    "Alemannia Aachen": {
      "short_name": "AAC",
      "initial_elo": 1050,
      "promotion_value": 0,
      "league": "3. Liga"
    }
  }
}
```

## Environment Variables

You can also set the configuration file via environment variable:

```bash
export TEAM_CONFIG_FILE=team_config.json
Rscript scripts/season_transition.R 2024 2025
```

## Execution Contexts

The fix works correctly in all contexts:

1. **Interactive R Session**: Uses `readline()` as normal
2. **Rscript with Terminal**: Uses `scan()` to read from stdin
3. **Rscript without Terminal**: Uses defaults or configuration file
4. **Docker/CI Environment**: Use `--non-interactive` or `--config`

## Technical Details

### Input Detection Logic

```r
get_user_input <- function(prompt, default = NULL) {
  # 1. Check for explicit non-interactive flag
  if (getOption("season_transition.non_interactive", FALSE)) {
    return(default)
  }
  
  # 2. Check if in interactive R session
  if (interactive()) {
    return(readline(prompt))
  }
  
  # 3. Check for terminal in Rscript mode
  if (isatty(stdin())) {
    # Use scan() to read from terminal
    return(scan("stdin", what = character(), nlines = 1, quiet = TRUE))
  }
  
  # 4. No input available - use default or error
  if (!is.null(default)) {
    return(default)
  }
  
  stop("Cannot read input without terminal or default value")
}
```

### Retry Prevention

All prompt functions now include a retry counter:

```r
prompt_for_team_info <- function(team_name, league, existing_short_names = NULL, retry_count = 0) {
  MAX_RETRIES <- 10
  if (retry_count >= MAX_RETRIES) {
    stop("Maximum retry limit reached")
  }
  # ... rest of function
}
```

## Troubleshooting

### "Cannot read input" Error

If you see this error, you're running in a non-terminal environment. Solutions:
- Use `--non-interactive` flag
- Provide a `--config` file
- Run with `R --interactive` instead of `Rscript`

### Empty Responses

If prompts seem to accept empty responses:
- Check that you have a proper terminal attached
- Try running with `R --interactive -f script.R` instead
- Use the configuration file approach

### Docker/Container Environments

Always use one of these approaches in containers:
```bash
# Option 1: Non-interactive with defaults
Rscript scripts/season_transition.R 2024 2025 --non-interactive

# Option 2: With configuration file
Rscript scripts/season_transition.R 2024 2025 --config /config/teams.json

# Option 3: Force interactive mode (requires pseudo-TTY)
docker run -it your-image R --interactive -f scripts/season_transition.R --args 2024 2025
```

## Migration Guide

If you have existing scripts that call the season transition:

1. **No changes needed** if running interactively
2. **Add `--non-interactive`** for automated scripts
3. **Create config files** for complex team setups

Example migration:

```bash
# Old (might fail)
Rscript scripts/season_transition.R 2024 2025

# New (works everywhere)
Rscript scripts/season_transition.R 2024 2025 --non-interactive

# Or with config
echo '{"new_teams": {}}' > empty_config.json
Rscript scripts/season_transition.R 2024 2025 --config empty_config.json
```