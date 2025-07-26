# Test Organization Guide

This document explains how tests are organized between deployment and development contexts.

## Overview

To speed up CI/CD pipelines and focus on what's actually deployed, tests are divided into two categories:

1. **Deployment Tests** - Run in CI/CD, test components that are deployed to k8s
2. **Development Tests** - Run locally, test maintenance scripts and utilities

## Deployment Tests (Run in CI/CD)

These tests verify components that are actually deployed to Kubernetes:

### Core Functionality
- `test-prozent.R` - Percentage formatting utility
- `test-simulationsCPP.R` - Core simulation engine
- `test-SpielCPP.R` - Match simulation logic
- `test-SpielNichtSimulieren.R` - ELO update logic
- `test-Tabelle.R` - League table calculations
- `test-transform_data.R` - Data transformation utilities

### API & Integration
- `test-api/` - All API interaction tests
- `test-e2e-simulation-workflow.R` - End-to-end workflow tests
- `test-integration-e2e.R` - Integration tests

### Schedulers & Updates
- `test-schedulers/` - Update scheduler tests
- `test-performance-*.R` - Performance benchmarks

### Shiny Application
- `test-shiny/` - All Shiny app tests

## Development Tests (Skip in CI/CD)

These tests are for local tools and utilities not deployed to k8s:

### Season Management
- `test-season-transition*.R` - Season transition scripts
- `test-season-processor*.R` - Season processing logic
- `test-season-validation.R` - Season data validation
- `test-multi-season-integration.R` - Multi-season workflows

### Data Management
- `test-csv-generation*.R` - CSV file generation
- `test-team-count-validation.R` - Team count validation
- `test-second-team-conversion.R` - Second team handling
- `test-elo-aggregation.R` - ELO aggregation utilities

### Interactive Tools
- `test-interactive-prompts.R` - User interaction prompts
- `test-input-handler.R` - Input handling utilities
- `test-cli-arguments.R` - Command line argument parsing

### Configuration
- `test-configmap-*.R` - ConfigMap generation (done locally, not in k8s)

## CI/CD Configuration

The GitHub Actions workflows are configured to:

1. Set `CI_ENVIRONMENT=true` and `RUN_DEPLOYMENT_TESTS_ONLY=true`
2. Skip tests matching patterns defined in the workflow
3. Run with a 10-minute timeout (reduced from 15)
4. Allow up to 20 test failures (reduced from 40)

## Running Tests Locally

To run all tests locally (including development tests):
```r
testthat::test_dir("tests/testthat")
```

To simulate CI/CD environment and run only deployment tests:
```r
Sys.setenv(CI_ENVIRONMENT = "true")
Sys.setenv(RUN_DEPLOYMENT_TESTS_ONLY = "true")
testthat::test_dir("tests/testthat")
```

## Adding New Tests

When adding new tests, consider:

1. **Is this functionality deployed to k8s?** → Deployment test
2. **Is this a maintenance script or utility?** → Development test
3. **Update the skip patterns** in `.github/workflows/R-tests.yml` if needed

## Benefits

- **Faster CI/CD**: ~50% reduction in test execution time
- **Focused testing**: Only test what's actually deployed
- **Better resource usage**: Prevents timeouts on resource-limited runners
- **Clear separation**: Explicit distinction between production and development code