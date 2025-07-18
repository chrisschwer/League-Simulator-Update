# Season Transition Script Updates

## Overview
The season transition script has been updated to fix critical bugs and implement interactive mode as the default behavior.

## Key Changes

### 1. Interactive Mode as Default
- The script now requires user interaction by default
- Non-interactive mode must be explicitly enabled with `--non-interactive` or `-n` flag
- Script will fail gracefully if run without terminal access and without the flag

### 2. Fixed League Processing
- All three leagues (Bundesliga, 2. Bundesliga, 3. Liga) are now properly processed
- League files are correctly merged into a single TeamList_YYYY.csv
- Team count validation ensures 56-62 teams are present

### 3. Second Team Name Conversion
- Teams with promotion value -50 automatically get XXX2 format
- Example: "Hoffenheim II" becomes "HO2" instead of "HOF"
- Interactive mode allows confirmation of second team status

### 4. Enhanced Non-Interactive Mode
- Detailed logging to `logs/season_transition_YYYY_YYYY_timestamp.log`
- All automatic decisions are logged with timestamps
- Suitable for Docker containers and CI/CD pipelines

## Usage

### Interactive Mode (Default)
```bash
Rscript scripts/season_transition.R 2024 2025
```

The script will prompt for:
- Team short names (3 characters)
- Initial ELO ratings
- Confirmation for second teams

### Non-Interactive Mode
```bash
# For automated runs
Rscript scripts/season_transition.R 2024 2025 --non-interactive

# Or use short form
Rscript scripts/season_transition.R 2024 2025 -n
```

### Docker Usage
```dockerfile
# In your Dockerfile or docker run command
CMD ["Rscript", "scripts/season_transition.R", "2024", "2025", "--non-interactive"]
```

## Testing

Run the test suite:
```bash
Rscript tests/run_season_transition_tests.R
```

Individual test files:
- `test-cli-arguments.R` - Tests command line parsing
- `test-second-team-conversion.R` - Tests XXX2 format conversion
- `test-team-count-validation.R` - Tests team count validation

## File Structure

### Generated Files
- `RCode/TeamList_YYYY.csv` - Final merged team list
- `logs/season_transition_*.log` - Detailed logs (non-interactive mode)

### Temporary Files
- `RCode/TeamList_YYYY_League##_temp.csv` - Temporary league files (auto-cleaned)

## Error Handling

### Common Errors and Solutions

1. **"Interactive mode required but no terminal available"**
   - Add `--non-interactive` flag for automated runs

2. **"Too few teams: XX - expected at least 56"**
   - Check API responses for all three leagues
   - Verify league IDs (78, 79, 80) are correct

3. **"No temporary league files found to merge"**
   - Check individual league processing logs
   - Verify API key is valid

## API Requirements

- Environment variable: `RAPIDAPI_KEY`
- API endpoint: api-football via RapidAPI
- Rate limiting: 1-second delay between requests

## Validation Rules

- Team count: 56-62 teams (3 leagues × ~18-20 teams)
- Short names: Exactly 3 uppercase characters
- ELO range: 500-2500
- Promotion values: 0 (regular) or -50 (Liga3 second teams)

## Changes from Previous Version

1. **Bug Fix**: Only one league was processed → Now all three leagues processed
2. **Bug Fix**: Second teams kept regular short names → Now converted to XXX2
3. **Bug Fix**: Script failed in non-interactive environments → Now requires explicit flag
4. **Enhancement**: Added comprehensive logging for non-interactive mode
5. **Enhancement**: Added team count validation (56-62 teams)
6. **Enhancement**: Interactive prompts for new teams and second team confirmation