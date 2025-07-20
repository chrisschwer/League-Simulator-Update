# Test Suite Repair Plan

**Status**: 🚧 In Progress  
**Current State**: 16 failures, 6 warnings, 1 skip, 143 passed  
**Last Updated**: 2025-07-20  
**Strategy**: Fix each test systematically, verify it passes, then move to next  

## Overview

This document tracks the systematic repair of all failing tests in the League Simulator codebase. Each fix is tested individually before proceeding to ensure no regressions. The plan is designed for automated execution with `--dangerously-skip-permissions`.

## Test Failure Summary

| Category | Current Count | Status | Priority |
|----------|--------------|--------|----------|
| Missing Function Imports | 0 | ✅ Fixed | High |
| C++ Compilation Issues | 0 | ✅ Fixed | High |
| CSV Generation Issues | 0 | ✅ Fixed | High |
| Input Handler (pkgload) | 9 | ❌ Active | High |
| Table Calculation Logic | 3 | ❌ Active | Medium |
| Locale-Dependent | 2 | ❌ Active | Low |
| ELO Baseline Mismatch | 2 | ❌ Active | Medium |

## Phase Progress Tracker

- [x] Phase 1: Infrastructure Setup ✅
- [x] Phase 2: Second Team Detection Fix ✅
- [x] Phase 3: CSV Generation Fixes ✅
- [ ] Phase 4: Interactive Prompt Fixes
- [ ] Phase 5: API and Error Handling
- [ ] Phase 6: Integration Test Fixes
- [ ] Phase 7: Missing Functions (Input Handler)
- [ ] Phase 8: Table and Performance
- [ ] Phase 9: Final Validation

## Phase 1: Infrastructure Setup

### 1.1 Create Test Helper Infrastructure
**Status**: ✅ Complete  
**File**: `tests/testthat/helper-test-setup.R`

This helper successfully:
- Loads all required packages
- Sources all R modules from RCode directory
- Compiles C++ files
- Sets consistent locale for tests

**Result**: All cli-arguments tests passing (25/25)

### 1.2 Fix C++ Compilation
**Status**: ✅ Complete  
**Files**: `src/simulationCPP.cpp`, `src/SpielCPP.cpp`, `src/SpielNichtSimulieren.cpp`

**Result**: C++ compilation working correctly

## Phase 2: Second Team Detection Fix

### 2.1 Fix Second Team Regex Patterns
**Status**: ✅ Complete  
**File**: `RCode/api_service.R`

**Result**: Second team detection working correctly

## Phase 3: CSV Generation Fixes

### 3.1 Implement Missing CSV Functions
**Status**: ✅ Complete  
**File**: `RCode/csv_generation.R`

All CSV functions implemented and working:
- `validate_csv_data()`
- `backup_existing_file()`
- `write_team_list_safely()`
- `verify_csv_integrity()`
- `merge_league_files()`

### 3.2 Fix Error Handling
**Status**: ✅ Complete

**Result**: All CSV generation tests passing (22/22 across all CSV test files)

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

## Current Failing Tests (2025-07-20)

### Input Handler Tests (9 failures)
**Files**: `test-input-handler.R`  
**Issue**: All failures due to `dev_package()` error: "No packages loaded with pkgload"  
**Root Cause**: Tests using `testthat::local_mocked_bindings()` without proper package context  
**Solution**: Either load package with pkgload or use alternative mocking approach

### ConfigMap Integration Tests (2 failures, 1 warning)
**File**: `test-configmap-integration.R`  
**Issues**:
1. Locale-dependent error message (German vs English)
2. Promotion field validation failure

### E2E Simulation Workflow (3 failures)
**File**: `test-e2e-simulation-workflow.R`  
**Issues**:
1. Table calculation: `Played` field mismatch
2. Win/Draw/Loss sum doesn't equal matches played
3. ELO change symmetry broken

### ELO Aggregation (2 failures)
**File**: `test-elo-aggregation.R`  
**Issues**:
1. Liga3 baseline calculation off by 21 points (1046 vs 1025)
2. Mixed file scenario fails to find team data

## Final Report

### Current Status (2025-07-20)
- **Total Tests**: 159
- **Passing**: 143 (89.9%)
- **Failing**: 16 (10.1%)
- **Major Improvements**: 
  - All CSV generation tests fixed ✅
  - All C++ compilation issues resolved ✅
  - CLI arguments tests fully passing ✅
  - ConfigMap generation tests passing ✅

### Recommendations for Next Steps
1. **Priority 1**: Fix input handler tests by addressing pkgload issue
2. **Priority 2**: Fix table calculation logic in simulation workflow
3. **Priority 3**: Address locale-dependent test failures
4. **Priority 4**: Investigate ELO baseline calculation discrepancy

### Issues 43, 44, 45 Assessment
- **Issue 43 (Season Transition Baseline)**: Partially improved - was 14 failures, now 2 failures remain in ELO aggregation
- **Issue 44 (Multi-Season Integration)**: Likely improved - dependencies (CSV, C++ compilation) are now fixed
- **Issue 45 (E2E Workflow)**: Still failing - same 3 failures in standings calculation and ELO symmetry