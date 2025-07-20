# Test Suite Repair Plan

**Status**: 🚧 In Progress  
**Total Tests to Fix**: 38 failing tests across 13 files  
**Strategy**: Fix each test systematically, verify it passes, then move to next  

## Overview

This document tracks the systematic repair of all failing tests in the League Simulator codebase. Each fix is tested individually before proceeding to ensure no regressions. The plan is designed for automated execution with `--dangerously-skip-permissions`.

## Test Failure Summary

| Category | Count | Priority |
|----------|-------|----------|
| Missing Function Imports | 15 | High |
| C++ Compilation Issues | 10 | High |
| Regex Pattern Deficiencies | 5 | High |
| Error Handling | 5 | Medium |
| Mock Data Quality | 3 | Medium |
| Locale-Dependent | 3 | Low |
| Performance Baselines | 2 | Low |

## Phase Progress Tracker

- [ ] Phase 1: Infrastructure Setup
- [ ] Phase 2: Second Team Detection Fix  
- [ ] Phase 3: CSV Generation Fixes
- [ ] Phase 4: Interactive Prompt Fixes
- [ ] Phase 5: API and Error Handling
- [ ] Phase 6: Integration Test Fixes
- [ ] Phase 7: Missing Functions
- [ ] Phase 8: Table and Performance
- [ ] Phase 9: Final Validation

## Phase 1: Infrastructure Setup

### 1.1 Create Test Helper Infrastructure
**Status**: 🚧 In Progress  
**File**: `tests/testthat/helper-test-setup.R`

This helper will:
- Load all required packages
- Source all R modules from RCode directory
- Compile C++ files
- Set consistent locale for tests

**Test Command**: 
```bash
Rscript -e "testthat::test_file('tests/testthat/test-cli-arguments.R')"
```

### 1.2 Fix C++ Compilation
**Status**: ⏳ Pending  
**Files**: `src/simulationCPP.cpp`, `src/SpielCPP.cpp`, `src/SpielNichtSimulieren.cpp`

**Test Command**:
```bash
Rscript -e "testthat::test_file('tests/testthat/test-SaisonSimulierenCPP.R')"
```

## Phase 2: Second Team Detection Fix

### 2.1 Fix Second Team Regex Patterns
**Status**: ⏳ Pending  
**File**: `RCode/api_service.R`

The current regex pattern `\b2\b` incorrectly matches "2. Bundesliga". Need to:
- Exclude league names first
- Add hyphenated U-21/U-23 patterns
- Add "Reserves" (plural) pattern

**Test Command**:
```bash
Rscript -e "testthat::test_file('tests/testthat/test-second-team-conversion.R')"
```

**Expected**: All 5 tests pass

## Phase 3: CSV Generation Fixes

### 3.1 Implement Missing CSV Functions
**Status**: ⏳ Pending  
**File**: `RCode/csv_generation.R`

Functions to implement:
- `validate_csv_data()`
- `backup_existing_file()`
- `write_team_list_safely()`
- `verify_csv_integrity()`
- `merge_league_files()`

### 3.2 Fix Error Handling
**Status**: ⏳ Pending

Add early validation in `generate_team_list_csv()` to check for NULL/empty data.

**Test Command**:
```bash
Rscript -e "testthat::test_file('tests/testthat/test-csv-generation-fixes.R')"
```

**Expected**: All 5 tests pass

## Phase 4: Interactive Prompt Fixes

### 4.1 Fix Short Name Validation
**Status**: ⏳ Pending  
**File**: `RCode/interactive_prompts.R`

Change validation from exactly 3 characters to 2-4 characters.

### 4.2 Add Retry Limit
**Status**: ⏳ Pending

Add maximum retry counter to prevent infinite loops.

**Test Command**:
```bash
Rscript -e "testthat::test_file('tests/testthat/test-interactive-prompts.R')"
```

## Phase 5: API and Error Handling

### 5.1 Season Validation Error Handling
**Status**: ⏳ Pending  
**File**: `RCode/season_validation.R`

Add graceful API failure handling.

**Test Command**:
```bash
Rscript -e "testthat::test_file('tests/testthat/test-season-validation.R')"
```

### 5.2 Transform Data Error Handling
**Status**: ⏳ Pending  
**File**: `RCode/transform_data.R`

Handle missing teams in teams list.

## Phase 6: Integration Test Fixes

### 6.1 Fix Mock Data Generators
**Status**: ⏳ Pending  
**File**: `tests/testthat/test-integration-e2e.R`

- Add more randomness to break high correlation
- Fix ELO bounds to be realistic

### 6.2 Update Test Expectations
**Status**: ⏳ Pending

Adjust overly strict test assertions.

**Test Command**:
```bash
Rscript -e "testthat::test_file('tests/testthat/test-integration-e2e.R')"
```

## Phase 7: Missing Functions

### 7.1 Add Source Statements
**Status**: ⏳ Pending

Add proper source statements to:
- `test-season-transition-regression.R`
- `test-season-processor.R`
- `test-cli-arguments.R`

### 7.2 Verify All Functions Available
**Status**: ⏳ Pending

## Phase 8: Table and Performance

### 8.1 Fix Table Calculations
**Status**: ⏳ Pending  
**File**: `RCode/Tabelle.R`

Fix points calculation logic.

### 8.2 Update Performance Baselines
**Status**: ⏳ Pending

Add tolerances to performance tests.

## Phase 9: Final Validation

### 9.1 Run Full Test Suite
**Status**: ⏳ Pending

```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```

### 9.2 Create PR
**Status**: ⏳ Pending

## Test Strictness Notes

During implementation, any tests found to be unreasonably strict will be documented here:

1. **Test**: [Name]  
   **Issue**: [Why it's too strict]  
   **Recommendation**: [Proposed change]

## Commit Log

Each phase will be committed separately:

1. `fix(tests): Phase 1 - Infrastructure setup and C++ compilation`
2. `fix(tests): Phase 2 - Second team detection regex patterns`
3. `fix(tests): Phase 3 - CSV generation functions and error handling`
4. `fix(tests): Phase 4 - Interactive prompts and validation`
5. `fix(tests): Phase 5 - API and error handling improvements`
6. `fix(tests): Phase 6 - Integration and E2E test fixes`
7. `fix(tests): Phase 7 - Source missing functions in tests`
8. `fix(tests): Phase 8 - Table calculations and performance`
9. `fix(tests): Phase 9 - Final cleanup and validation`

## Final Report

Upon completion, this section will contain:
- Summary of all fixes
- Performance improvements achieved
- Recommendations for future test maintenance
- Any remaining issues or concerns