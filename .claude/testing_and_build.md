# Testing and Build Documentation

## Testing Strategy

### Current Test Coverage
- **Unit Tests**: Limited coverage with testthat framework
- **Integration Tests**: Not yet implemented
- **Manual Testing**: Primary validation method

### Test Structure
```
tests/
├── testthat.R          # Test runner
└── testthat/
    └── test-prozent.R  # Basic unit test example
```

## Running Tests

### All Tests
```r
source("tests/testthat.R")
```

### Specific Test Files
```r
testthat::test_file("tests/testthat/test-prozent.R")
```

### Interactive Testing
```r
library(testthat)
test_dir("tests/testthat")
```

## Build Commands

### R Package Dependencies
```r
# Install from packagelist.txt
packages <- readLines("packagelist.txt")
packages <- trimws(packages[packages != ""])
install.packages(packages[!packages %in% installed.packages()[,"Package"]])

# Verify installation
lapply(packages, require, character.only = TRUE)
```

### C++ Compilation
```bash
# Navigate to RCode directory
cd RCode

# Compile C++ source
R CMD SHLIB SpielNichtSimulieren.cpp

# Verify compilation
ls -la *.so  # Linux/Mac
ls -la *.dll # Windows
```

### Docker Builds

#### Monolithic Build
```bash
# Development build
docker build -t league-simulator:dev .

# Production build with version tag
docker build -t league-simulator:v1.0.0 .

# Build with build arguments
docker build \
  --build-arg R_VERSION=4.3.1 \
  -t league-simulator:custom .
```

#### Microservices Builds
```bash
# League updater service
docker build -f Dockerfile.league -t league-updater:latest .

# Shiny updater service  
docker build -f Dockerfile.shiny -t shiny-updater:latest .

# Build all services
for service in league shiny; do
  docker build -f Dockerfile.$service -t ${service}-updater:latest .
done
```

### Local Development Build
```bash
# Quick build for testing (no cache)
docker build --no-cache -t league-simulator:test .

# Build with specific platform
docker build --platform linux/amd64 -t league-simulator:amd64 .
```

## Testing Scenarios

### 1. Unit Test Template
Create new test files following this pattern:

```r
# tests/testthat/test-elo-calculations.R
context("ELO Rating Calculations")

test_that("ELO ratings update correctly after match", {
  # Setup
  initial_elo_home <- 1500
  initial_elo_away <- 1500
  
  # Test home win
  result <- updateEloRatings(initial_elo_home, initial_elo_away, 
                            home_goals = 2, away_goals = 0)
  
  expect_true(result$home_elo > initial_elo_home)
  expect_true(result$away_elo < initial_elo_away)
  expect_equal(result$home_elo + result$away_elo, 
               initial_elo_home + initial_elo_away)
})
```

### 2. Integration Test Example
```r
# tests/testthat/test-simulation-integration.R
test_that("Full simulation cycle completes successfully", {
  skip_if_not(Sys.getenv("RAPIDAPI_KEY") != "", 
              "API key not available")
  
  # Run minimal simulation
  result <- tryCatch({
    source("RCode/leagueSimulatorCPP.R")
    TRUE
  }, error = function(e) {
    FALSE
  })
  
  expect_true(result, "Simulation should complete without errors")
})
```

### 3. API Mock Testing
```r
# tests/testthat/test-api-mocks.R
test_that("API response parsing handles edge cases", {
  # Mock empty response
  mock_response <- list(response = list())
  
  result <- parseAPIResponse(mock_response)
  expect_equal(nrow(result), 0)
  expect_true(is.data.frame(result))
})
```

## Continuous Integration Commands

### GitHub Actions Test Commands
```yaml
# Extract from .github/workflows/test.yml
- name: Run R tests
  run: |
    Rscript -e 'source("tests/testthat.R")'
    
- name: Check code coverage
  run: |
    Rscript -e 'covr::codecov()'
```

### Pre-commit Hooks (Optional Setup)
```bash
# .git/hooks/pre-commit
#!/bin/bash
echo "Running tests..."
Rscript -e 'source("tests/testthat.R")'
if [ $? -ne 0 ]; then
  echo "Tests failed. Commit aborted."
  exit 1
fi
```

## Build Verification

### Docker Image Testing
```bash
# Test monolithic image
docker run --rm \
  -e RAPIDAPI_KEY="test" \
  -e SHINYAPPS_IO_SECRET="test" \
  league-simulator:dev \
  Rscript -e "print('Build verification passed')"

# Test microservices
docker run --rm league-updater:latest \
  Rscript -e "file.exists('/RCode/update_league.R')"
```

### Dependency Verification
```r
# verify_build.R
required_packages <- readLines("packagelist.txt")
required_packages <- trimws(required_packages[required_packages != ""])

missing_packages <- required_packages[!required_packages %in% 
                                     installed.packages()[,"Package"]]

if (length(missing_packages) > 0) {
  stop("Missing packages: ", paste(missing_packages, collapse = ", "))
} else {
  message("All required packages installed successfully")
}

# Test C++ compilation
if (!file.exists("RCode/SpielNichtSimulieren.so") && 
    !file.exists("RCode/SpielNichtSimulieren.dll")) {
  stop("C++ code not compiled")
} else {
  message("C++ compilation verified")
}
```

## Performance Testing

### Simulation Benchmarking
```r
# benchmark_simulation.R
library(microbenchmark)

benchmark_results <- microbenchmark(
  small_simulation = {
    # Run with 1000 iterations
    Sys.setenv(SIMULATION_ITERATIONS = "1000")
    source("RCode/simulationsCPP.R")
  },
  medium_simulation = {
    # Run with 5000 iterations  
    Sys.setenv(SIMULATION_ITERATIONS = "5000")
    source("RCode/simulationsCPP.R")
  },
  times = 5
)

print(benchmark_results)
```

### Memory Profiling
```r
# profile_memory.R
library(profmem)

mem_profile <- profmem({
  source("RCode/leagueSimulatorCPP.R")
})

print(sum(mem_profile$bytes, na.rm = TRUE) / 1024^2) # MB used
```

## Troubleshooting Build Issues

### Common Build Problems

1. **Package Installation Failures**
   ```r
   # Use binary packages when available
   options(pkgType = "binary")
   
   # Install with dependencies
   install.packages("package_name", dependencies = TRUE)
   ```

2. **C++ Compilation Errors**
   ```bash
   # Check R configuration
   R CMD config --all
   
   # Verbose compilation
   R CMD SHLIB -v SpielNichtSimulieren.cpp
   ```

3. **Docker Build Failures**
   ```bash
   # Debug with intermediate containers
   docker build --rm=false -t debug:latest .
   
   # Inspect failed layer
   docker run -it <intermediate_container_id> /bin/bash
   ```

### Build Environment Requirements

| Component | Minimum Version | Recommended |
|-----------|----------------|-------------|
| R | 4.3.0 | 4.3.1+ |
| gcc/g++ | 7.0 | 9.0+ |
| Docker | 19.03 | 20.10+ |
| Make | 3.82 | 4.0+ |

## Quality Assurance Checklist

Before deployment, ensure:

- [ ] All tests pass locally
- [ ] C++ code compiles without warnings
- [ ] Docker images build successfully
- [ ] No hardcoded credentials in code
- [ ] API rate limits are respected
- [ ] Memory usage is reasonable
- [ ] Error handling is comprehensive
- [ ] Logging is appropriate
- [ ] Documentation is updated