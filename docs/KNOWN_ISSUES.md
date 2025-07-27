# Known Issues & Solutions

## Current Issues

### Test Suite Failures (In Progress)
**Status**: 🚧 38 tests failing - systematic repair in progress  
**Tracking**: See [Test Fix Plan](TEST_FIX_PLAN.md) for detailed progress  
**Temporary Note**: This will be removed once all tests pass

## Resolved Issues

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