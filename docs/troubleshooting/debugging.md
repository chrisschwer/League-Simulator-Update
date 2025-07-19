# Debugging Guide

Step-by-step debugging procedures for League Simulator issues.

## Debugging Tools and Setup

### 1. R Debugging Tools

```r
# Enable debugging options
options(
  error = recover,  # Enter debugger on error
  warn = 2,         # Convert warnings to errors
  keep.source = TRUE  # Keep source for better traces
)

# Install debugging packages
install.packages(c("debugme", "lobstr", "whereami", "boomer"))
```

### 2. Docker Debugging Setup

```yaml
# docker-compose.debug.yml
services:
  league-simulator-debug:
    build:
      context: .
      dockerfile: Dockerfile.debug
    environment:
      - DEBUG=true
      - R_KEEP_PKG_SOURCE=yes
      - R_ENABLE_JIT=0  # Disable JIT for clearer debugging
    volumes:
      - ./RCode:/app/RCode
      - ./logs:/app/logs
    stdin_open: true
    tty: true
    command: /bin/bash
```

```dockerfile
# Dockerfile.debug
FROM rocker/r-ver:4.2.3

# Install debugging tools
RUN apt-get update && apt-get install -y \
    gdb \
    valgrind \
    strace \
    procps \
    vim \
    less

# Install R debugging packages
RUN R -e "install.packages(c('debugme', 'profvis', 'bench'))"

WORKDIR /app
```

## Common Debugging Scenarios

### 1. Debugging R Code Errors

#### Using browser()

```r
# Add breakpoints in code
update_league <- function(league_id) {
  cat("Starting update for league:", league_id, "\n")
  
  # Set breakpoint
  browser()  # Execution stops here
  
  # Fetch data
  matches <- retrieve_match_data(league_id)
  
  if (length(matches) == 0) {
    browser()  # Conditional breakpoint
  }
  
  # Continue processing...
}

# Debug commands in browser:
# n - next line
# s - step into function
# f - finish current function
# c - continue execution
# Q - quit debugger
# ls() - list variables
# str(variable) - examine structure
```

#### Using debug()

```r
# Debug specific function
debug(simulate_league)
simulate_league(78)  # Enters debugger

# Debug all calls to a function
trace(calculate_elo, tracer = browser)

# Remove debugging
undebug(simulate_league)
untrace(calculate_elo)
```

#### Stack Trace Analysis

```r
# Enhanced traceback
options(error = function() {
  calls <- sys.calls()
  cat("\n=== Enhanced Stack Trace ===\n")
  for (i in length(calls):1) {
    cat(i, ": ", deparse(calls[[i]])[1], "\n")
  }
  traceback()
})

# Get detailed error info
last_error <- function() {
  list(
    message = geterrmessage(),
    call = sys.call(-1),
    traceback = traceback(),
    search_path = search(),
    loaded_packages = loadedNamespaces()
  )
}
```

### 2. Debugging Rcpp Code

#### Print Debugging

```cpp
// SpielNichtSimulieren_debug.cpp
#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::export]]
NumericVector updateEloDebug(NumericVector ratings, List match) {
  Rcout << "=== ELO Update Debug ===" << std::endl;
  Rcout << "Input ratings: " << ratings << std::endl;
  
  int home_id = match["home_id"];
  int away_id = match["away_id"];
  
  Rcout << "Home ID: " << home_id << ", Away ID: " << away_id << std::endl;
  
  // Add validation
  if (home_id < 0 || home_id >= ratings.size()) {
    stop("Invalid home_id: " + std::to_string(home_id));
  }
  
  // Continue with calculations...
}
```

#### GDB Debugging

```bash
# Compile with debug symbols
R CMD SHLIB -d -g SpielNichtSimulieren.cpp

# Run R under GDB
R -d gdb

# In GDB:
(gdb) run
# In R:
> library(Rcpp)
> sourceCpp("SpielNichtSimulieren.cpp")

# Set breakpoint
(gdb) break updateEloRatings
(gdb) continue

# When breakpoint hits:
(gdb) print home_id
(gdb) print ratings
(gdb) backtrace
```

### 3. Debugging Data Issues

#### Data Validation Framework

```r
# data_validator.R
validate_team_data <- function(teams, verbose = TRUE) {
  errors <- list()
  warnings <- list()
  
  # Check structure
  required_cols <- c("id", "name", "elo", "liga", "season")
  missing_cols <- setdiff(required_cols, names(teams))
  if (length(missing_cols) > 0) {
    errors$structure <- paste("Missing columns:", paste(missing_cols, collapse = ", "))
  }
  
  # Check data types
  if (exists("id", teams) && !is.numeric(teams$id)) {
    errors$types <- "ID column must be numeric"
  }
  
  # Check values
  if (any(teams$elo < 0 | teams$elo > 3000, na.rm = TRUE)) {
    warnings$elo_range <- "ELO ratings outside normal range (0-3000)"
  }
  
  # Check duplicates
  if (any(duplicated(teams$id))) {
    dup_ids <- teams$id[duplicated(teams$id)]
    errors$duplicates <- paste("Duplicate IDs:", paste(dup_ids, collapse = ", "))
  }
  
  # Verbose output
  if (verbose) {
    cat("=== Data Validation Report ===\n")
    cat("Rows:", nrow(teams), "\n")
    cat("Columns:", ncol(teams), "\n")
    
    if (length(errors) > 0) {
      cat("\nERRORS:\n")
      for (name in names(errors)) {
        cat("-", name, ":", errors[[name]], "\n")
      }
    }
    
    if (length(warnings) > 0) {
      cat("\nWARNINGS:\n")
      for (name in names(warnings)) {
        cat("-", name, ":", warnings[[name]], "\n")
      }
    }
    
    if (length(errors) == 0 && length(warnings) == 0) {
      cat("\nValidation PASSED\n")
    }
  }
  
  return(list(valid = length(errors) == 0, errors = errors, warnings = warnings))
}

# Data comparison tool
compare_data <- function(before, after, id_col = "id") {
  # Find changes
  both_ids <- intersect(before[[id_col]], after[[id_col]])
  
  changes <- list()
  for (id in both_ids) {
    row_before <- before[before[[id_col]] == id, ]
    row_after <- after[after[[id_col]] == id, ]
    
    diffs <- which(row_before != row_after)
    if (length(diffs) > 0) {
      changes[[as.character(id)]] <- list(
        columns = names(before)[diffs],
        before = row_before[diffs],
        after = row_after[diffs]
      )
    }
  }
  
  # Summary
  cat("Total IDs compared:", length(both_ids), "\n")
  cat("IDs with changes:", length(changes), "\n")
  
  return(changes)
}
```

### 4. Debugging API Issues

#### API Request Interceptor

```r
# api_debug.R
library(httr)

# Wrap API calls with debugging
debug_api_call <- function(url, ..., verbose = TRUE) {
  if (verbose) {
    cat("\n=== API Request Debug ===\n")
    cat("URL:", url, "\n")
    cat("Time:", format(Sys.time()), "\n")
  }
  
  # Capture request
  response <- tryCatch({
    RETRY(
      "GET",
      url = url,
      ...,
      times = 3,
      pause_base = 2,
      pause_cap = 10
    )
  }, error = function(e) {
    cat("ERROR:", e$message, "\n")
    return(NULL)
  })
  
  if (verbose && !is.null(response)) {
    cat("Status:", status_code(response), "\n")
    cat("Headers:\n")
    print(headers(response))
    
    if (status_code(response) != 200) {
      cat("Response body:\n")
      print(content(response, "text"))
    }
  }
  
  return(response)
}

# Mock API for testing
mock_api <- function(endpoint, response_data, status = 200) {
  with_mock(
    `httr::GET` = function(url, ...) {
      if (grepl(endpoint, url)) {
        structure(
          list(
            status_code = status,
            headers = list("content-type" = "application/json"),
            content = charToRaw(jsonlite::toJSON(response_data))
          ),
          class = "response"
        )
      } else {
        stop("Unexpected endpoint")
      }
    },
    {
      # Your test code here
    }
  )
}
```

### 5. Memory Debugging

#### Memory Profiling

```r
# memory_debug.R
library(pryr)
library(lobstr)

# Track memory usage
memory_profile <- function(expr) {
  start_mem <- mem_used()
  gc()
  
  # Create memory log
  mem_log <- list()
  
  # Set up tracking
  trace_mem <- function() {
    mem_log[[length(mem_log) + 1]] <<- list(
      time = Sys.time(),
      used = mem_used(),
      objects = length(ls(envir = .GlobalEnv))
    )
  }
  
  # Run expression with periodic memory checks
  result <- eval(expr)
  
  # Report
  end_mem <- mem_used()
  
  cat("Memory Profile:\n")
  cat("Start:", format(start_mem), "\n")
  cat("End:", format(end_mem), "\n")
  cat("Increase:", format(end_mem - start_mem), "\n")
  
  # Find large objects
  obj_sizes <- object_size(mget(ls(envir = .GlobalEnv), envir = .GlobalEnv))
  large_objects <- sort(obj_sizes, decreasing = TRUE)[1:10]
  
  cat("\nLargest objects:\n")
  print(large_objects)
  
  return(result)
}

# Memory leak detection
detect_memory_leak <- function(fun, iterations = 100) {
  memory_usage <- numeric(iterations)
  
  for (i in 1:iterations) {
    gc()
    memory_usage[i] <- mem_used()
    fun()
  }
  
  # Plot memory usage
  plot(memory_usage, type = "l", 
       main = "Memory Usage Over Iterations",
       xlab = "Iteration", ylab = "Memory (bytes)")
  
  # Check for increasing trend
  trend <- lm(memory_usage ~ seq_along(memory_usage))
  if (coef(trend)[2] > 0) {
    warning("Possible memory leak detected!")
  }
  
  return(trend)
}
```

### 6. Debugging Docker Containers

#### Interactive Container Debugging

```bash
#!/bin/bash
# debug_container.sh

CONTAINER="league-simulator"

echo "=== Docker Container Debug ==="

# 1. Check if running
if ! docker ps | grep -q $CONTAINER; then
  echo "Container not running. Starting..."
  docker-compose up -d $CONTAINER
fi

# 2. Enter container
echo "Entering container..."
docker exec -it $CONTAINER bash

# Inside container:
# - Check processes: ps aux
# - Check memory: free -h
# - Check disk: df -h
# - Run R interactively: R
# - Check logs: tail -f logs/*.log
```

#### Container Health Debugging

```r
# container_health.R
check_container_health <- function() {
  health_checks <- list()
  
  # File system check
  health_checks$filesystem <- list(
    can_read_teams = file.exists("RCode/TeamList_2025.csv"),
    can_write_results = file.access("ShinyApp/data", 2) == 0,
    log_directory = dir.exists("logs")
  )
  
  # Environment check
  health_checks$environment <- list(
    api_key_set = nchar(Sys.getenv("RAPIDAPI_KEY")) > 0,
    season_set = !is.na(as.numeric(Sys.getenv("SEASON"))),
    timezone = Sys.timezone()
  )
  
  # Dependencies check
  health_checks$packages <- list(
    rcpp_loaded = require(Rcpp, quietly = TRUE),
    httr_loaded = require(httr, quietly = TRUE),
    shiny_loaded = require(shiny, quietly = TRUE)
  )
  
  # System resources
  health_checks$resources <- list(
    memory_available = as.numeric(system("free -m | awk 'NR==2{print $7}'", intern = TRUE)),
    disk_space = as.numeric(system("df -m . | awk 'NR==2{print $4}'", intern = TRUE)),
    cpu_count = parallel::detectCores()
  )
  
  # Print report
  cat("=== Container Health Check ===\n")
  for (category in names(health_checks)) {
    cat("\n", toupper(category), ":\n", sep = "")
    for (check in names(health_checks[[category]])) {
      status <- if (isTRUE(health_checks[[category]][[check]]) || 
                   is.numeric(health_checks[[category]][[check]])) "✓" else "✗"
      cat(sprintf("  %s %s: %s\n", status, check, 
                  health_checks[[category]][[check]]))
    }
  }
  
  return(health_checks)
}
```

## Advanced Debugging Techniques

### 1. Time Travel Debugging

```r
# time_travel_debug.R
library(testr)

# Record execution
testr::testr_start("simulation_recording")
simulate_league(78, iterations = 100)
testr::testr_stop()

# Replay with modifications
replay_simulation <- function() {
  # Load recording
  recording <- testr::testr_load("simulation_recording")
  
  # Modify inputs
  recording$inputs$iterations <- 1000
  
  # Replay
  testr::testr_replay(recording)
}
```

### 2. Conditional Debugging

```r
# conditional_debug.R

# Debug only when condition met
debug_on_condition <- function(fun, condition) {
  force(fun)
  force(condition)
  
  function(...) {
    if (condition(...)) {
      browser()
    }
    fun(...)
  }
}

# Example: Debug when ELO change is extreme
calculate_elo_debug <- debug_on_condition(
  calculate_elo,
  function(before, after) abs(after - before) > 100
)

# Smart breakpoints
smart_browser <- function(expr, vars_to_watch = NULL) {
  if (!is.null(vars_to_watch)) {
    cat("Watching:", paste(vars_to_watch, collapse = ", "), "\n")
    for (var in vars_to_watch) {
      if (exists(var, envir = parent.frame())) {
        cat(var, "=", get(var, envir = parent.frame()), "\n")
      }
    }
  }
  browser()
}
```

### 3. Distributed Debugging

```r
# distributed_debug.R

# Debug across multiple containers
debug_all_services <- function() {
  services <- c("league-simulator", "shiny-app")
  
  for (service in services) {
    cat("\n=== Debugging", service, "===\n")
    
    # Get logs
    logs <- system(sprintf("docker-compose logs --tail=50 %s", service), 
                   intern = TRUE)
    
    # Look for errors
    errors <- grep("ERROR|FATAL", logs, value = TRUE)
    if (length(errors) > 0) {
      cat("Errors found:\n")
      print(errors)
    }
    
    # Check resource usage
    stats <- system(sprintf("docker stats --no-stream %s", service), 
                    intern = TRUE)
    cat("\nResource usage:\n")
    cat(stats, sep = "\n")
  }
}
```

## Debugging Workflow

### Step-by-Step Debugging Process

1. **Reproduce the Issue**
   ```r
   # Create minimal reproducible example
   reprex::reprex({
     library(LeagueSimulator)
     teams <- data.frame(id = 1:2, elo = c(1500, 1600))
     simulate_match(teams[1,], teams[2,])
   })
   ```

2. **Isolate the Problem**
   ```r
   # Binary search for issue
   test_half <- function(data) {
     n <- nrow(data)
     first_half <- data[1:(n/2), ]
     second_half <- data[(n/2+1):n, ]
     
     if (process_data(first_half) fails) {
       test_half(first_half)
     } else {
       test_half(second_half)
     }
   }
   ```

3. **Collect Evidence**
   ```r
   # Comprehensive diagnostics
   collect_debug_info <- function() {
     list(
       session_info = sessionInfo(),
       traceback = traceback(),
       warnings = warnings(),
       search_path = search(),
       global_objects = ls(envir = .GlobalEnv),
       memory_usage = mem_used(),
       open_connections = showConnections()
     )
   }
   ```

4. **Test Hypothesis**
   ```r
   # A/B testing for debugging
   test_hypothesis <- function(original_fun, modified_fun, test_data) {
     result_original <- tryCatch(
       original_fun(test_data),
       error = function(e) list(error = e$message)
     )
     
     result_modified <- tryCatch(
       modified_fun(test_data),
       error = function(e) list(error = e$message)
     )
     
     list(
       original = result_original,
       modified = result_modified,
       fixed = !is.null(result_modified) && is.null(result_modified$error)
     )
   }
   ```

## Debugging Checklist

### Before Starting
- [ ] Can you reproduce the issue?
- [ ] Do you have a minimal example?
- [ ] Are logs available?
- [ ] Is the environment documented?

### During Debugging
- [ ] Use version control to track changes
- [ ] Document each hypothesis tested
- [ ] Keep a debugging log
- [ ] Test fixes in isolation

### After Fixing
- [ ] Add regression test
- [ ] Document the fix
- [ ] Update error handling
- [ ] Share knowledge with team

## Related Documentation

- [Common Issues](common-issues.md)
- [Log Analysis](log-analysis.md)
- [Performance Profiling](performance.md)
- [Testing Guide](../testing/testing-guide.md)