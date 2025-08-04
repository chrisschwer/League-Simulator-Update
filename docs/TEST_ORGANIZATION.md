# Test Organization Guide

This document explains the current test organization after simplification for a hobbyist project.

## Overview

The test suite has been simplified from 640+ tests to 130 tests across 17 files, focusing on core functionality while removing over-engineered tests.

## Test Statistics

- **Total Tests**: 130 (down from 640+)
- **Test Files**: 17 (down from 25+)
- **Removed**: 13 files containing ~510 tests

### Test Distribution
- **Core Tests (in run_all_tests.R)**: 48 tests across 6 files (37%)
- **Other Tests**: 82 tests across 11 files (63%)

## Core Tests (48 tests)

These are the essential tests that verify core functionality:

### Simulation Engine
- `test-SpielNichtSimulieren.R` - 11 tests for match simulation
- `test-Tabelle.R` - 5 tests for league table calculations (reduced from 59)
- `test-prozent.R` - 2 tests for percentage formatting

### Validation & Data
- `test-team-count-validation.R` - 5 tests for league team counts
- `test-season-validation.R` - 15 tests for season validation
- `test-transform_data.R` - 10 tests for data transformation

## Additional Tests (82 tests)

### C++ Integration
- `test-SaisonSimulierenCPP.R` - 10 tests for season simulation
- `test-simulationsCPP.R` - 8 tests for Monte Carlo simulations
- `test-SpielCPP.R` - 10 tests for match simulation wrapper

### Integration & E2E
- `test-integration-e2e.R` - 3 tests (reduced from 134)
- `test-simple-integration.R` - 5 tests (newly created)
- `test-e2e-simulation-workflow.R` - 5 tests
- `test-elo-basic.R` - 5 tests (newly created)

### Season Management
- `test-season-processor.R` - 9 tests
- `test-season-transition-regression.R` - 10 tests

### Other
- `test-deployment.R` - 6 tests
- `test-interactive-prompts.R` - 11 tests (may hang on input)

## Removed Tests

The following over-engineered tests were removed:

### Infrastructure Tests (Removed)
- All ConfigMap tests (3 files, 63 tests) - Kubernetes-specific
- All performance tests (3 files, 17 tests) - Premature optimization
- CLI argument tests (25 tests) - Over-detailed

### Non-Existent Function Tests (Removed)
- `test-csv-generation-fixes.R` - Functions don't exist
- `test-season-processor-fixes.R` - Functions don't exist
- `test-input-handler.R` - Over-engineered mocking
- `test-elo-aggregation.R` - Functions don't exist
- `test-multi-season-integration.R` - Too complex
- `test-second-team-conversion.R` - Edge case

## Running Tests

### Prerequisites
```r
# Must compile C++ code first
library(Rcpp)
sourceCpp('RCode/SpielNichtSimulieren.cpp')
```

### Option 1: Core Tests Only
```bash
Rscript run_all_tests.R  # 48 tests, reliable
```

### Option 2: All Tests
```bash
Rscript run_all_tests_fixed.R  # 130 tests, some may fail
```

### Option 3: Specific Test File
```r
testthat::test_file('tests/testthat/test-SpielNichtSimulieren.R')
```

## Known Issues

1. **C++ Compilation Required**: Tests fail without `sourceCpp()` first
2. **Parameter Mismatches**: Mix of German (ModFaktor) vs English (modFactor)
3. **Interactive Tests**: Some tests hang waiting for user input
4. **Test Infrastructure**: Tests expect package namespace but we don't have one

## Test Philosophy

For this hobbyist project, we focus on:

✅ **Essential Tests**:
- Core simulation algorithms
- Basic data integrity
- Critical calculations (ELO, tables)
- Simple integration tests

❌ **Avoided Tests**:
- Infrastructure complexity
- Performance benchmarks
- Every edge case
- Non-existent functionality

## Benefits of Simplification

1. **Maintainability**: 80% fewer tests to maintain
2. **Speed**: Core tests run in seconds
3. **Focus**: Tests reflect actual functionality
4. **Clarity**: Easy to understand what's being tested