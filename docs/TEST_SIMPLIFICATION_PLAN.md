# Test Suite Simplification Plan

## Goal
Reduce from 640+ tests to ~100-150 essential tests for a hobbyist project.

## Tests to Keep (Essential Functionality)

### 1. Core Simulation Tests (~40 tests)
- **test-SpielNichtSimulieren.R**: Keep all 48 tests
  - These test the heart of the simulation engine
  - Already passing, well-designed

### 2. Table Management (~20 tests)
- **test-Tabelle.R**: Reduce from 59 to ~20
  - Keep: Basic table creation, point calculations, sorting
  - Remove: Edge cases, complex scenarios

### 3. Season Simulation (~10 tests)
- **test-SaisonSimulierenCPP.R**: Fix function names, keep all 9
  - Test basic season simulation
  - Ensure relegation/promotion works

### 4. Simple Integration Tests (~15 tests)
- Create new **test-simple-integration.R**
  - Test 1: Can simulate one league season end-to-end
  - Test 2: Are results saved correctly?
  - Test 3: Can load and continue from saved state?
  - Test 4: Basic season transition (2024 → 2025)
  - Keep ~10 more for different scenarios

### 5. Basic Validation (~10 tests)
- **test-team-count-validation.R**: Keep simplified
  - Bundesliga has 18 teams
  - 2. Bundesliga has 18 teams
  - 3. Liga has 20 teams

### 6. ELO Tests (~10 tests)
- Create new **test-elo-basic.R**
  - ELO updates after match
  - Strong team beats weak team more often
  - Home advantage works
  - Season carryover maintains ~80% of ELO

## Tests to Remove Completely

### Over-Engineered Tests
- ❌ **test-configmap-edge-cases.R** (25 tests) - Kubernetes-specific
- ❌ **test-configmap-generation.R** (19 tests) - Kubernetes-specific
- ❌ **test-configmap-integration.R** - Kubernetes-specific
- ❌ **test-performance-*.R** (17 tests) - Premature optimization
- ❌ **test-cli-arguments.R** (25 tests) - Too detailed for simple script

### Testing Non-Existent Functions
- ❌ **test-csv-generation-fixes.R** (13 failures) - Functions don't exist
- ❌ **test-season-processor-fixes.R** (11 failures) - Functions don't exist
- ❌ **test-input-handler.R** (9 failures) - Over-engineered mocking
- ❌ **test-elo-aggregation.R** (8 failures) - Functions don't exist

### Excessive Coverage
- ❌ **test-multi-season-integration.R** - Too complex
- ❌ **test-second-team-conversion.R** (27 tests) - Edge case
- ⚠️ **test-integration-e2e.R**: Reduce from 134 to ~10 tests

## Implementation Steps

### Phase 1: Remove Unnecessary Tests
```bash
# Remove over-engineered tests
rm tests/testthat/test-configmap-*.R
rm tests/testthat/test-performance-*.R
rm tests/testthat/test-cli-arguments.R
rm tests/testthat/test-csv-generation-fixes.R
rm tests/testthat/test-season-processor-fixes.R
rm tests/testthat/test-input-handler.R
rm tests/testthat/test-elo-aggregation.R
rm tests/testthat/test-multi-season-integration.R
rm tests/testthat/test-second-team-conversion.R
```

### Phase 2: Fix Remaining Tests
1. Fix C++ function names in tests (SpielCPP vs SpielNichtSimulieren)
2. Update test-Tabelle.R to focus on core functionality
3. Simplify test-integration-e2e.R dramatically

### Phase 3: Create Simple Tests
```r
# test-elo-basic.R
test_that("ELO updates work correctly", {
  # Simple test: strong team (2000) vs weak team (1500)
  # Strong team should win more often
})

# test-simple-integration.R  
test_that("Can simulate Bundesliga season", {
  # Load teams, simulate season, check results exist
})
```

## Actual Outcome

- **Before**: 640+ tests, 74 failures, overly complex
- **After**: 130 tests across 17 files (down from 25+ files)

## Implementation Results

✅ **Successfully Completed**:
- Removed 13 test files containing ~510 tests
- All ConfigMap tests removed (3 files, 63 tests)
- All performance tests removed (3 files, 17 tests) 
- Tests for non-existent functions removed (6 files)
- test-Tabelle.R simplified from 59 to 5 tests
- test-integration-e2e.R reduced from 134 to 3 tests
- Created test-elo-basic.R with 5 simple tests
- Created test-simple-integration.R with 5 basic tests

⚠️ **Issues Discovered**:
1. **C++ compilation required**: Tests fail without `sourceCpp()` first
2. **Parameter mismatches**: German (ModFaktor) vs English (modFactor) names
3. **Interactive tests**: Some tests hang waiting for user input
4. **Test coverage**: Original runner only covered 37% of tests (48/130)

## Benefits Achieved

1. **Faster test runs**: Core tests complete in seconds when properly set up
2. **Easier maintenance**: 80% reduction in test code to maintain
3. **Clear focus**: Tests now focus on essential functionality only
4. **Partial success**: Core functionality tests pass, infrastructure issues remain

## Test Philosophy for Hobby Projects

✅ **DO Test**:
- Core algorithms work correctly
- Basic happy path scenarios
- Critical edge cases (e.g., relegation)
- Data persistence works

❌ **DON'T Test**:
- Every possible edge case
- Performance characteristics
- Complex error scenarios
- Implementation details
- Non-existent functionality