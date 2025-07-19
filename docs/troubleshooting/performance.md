# Performance Tuning Guide

Optimize League Simulator performance for speed, efficiency, and scalability.

## Performance Benchmarks

### Target Performance Metrics

| Component | Target | Acceptable | Action Required |
|-----------|--------|------------|-----------------|
| Single simulation | < 1ms | < 5ms | > 10ms |
| 10,000 iterations | < 8 min | < 12 min | > 15 min |
| API response | < 500ms | < 1s | > 2s |
| Memory usage | < 2GB | < 3GB | > 4GB |
| CPU usage | < 80% | < 90% | > 95% |

### Current Performance Profile

```r
# benchmark_current.R
library(microbenchmark)
library(profvis)

benchmark_system <- function() {
  results <- list()
  
  # Benchmark simulation speed
  results$simulation <- microbenchmark(
    single_match = simulate_match(1800, 1700),
    full_season = simulate_season(team_data, iterations = 100),
    monte_carlo = simulate_league(78, iterations = 1000),
    times = 10
  )
  
  # Memory usage
  results$memory <- pryr::mem_used()
  
  # Profile full update
  results$profile <- profvis({
    source("RCode/update_league.R")
    update_league(78)
  })
  
  return(results)
}
```

## Performance Optimization Strategies

### 1. R Code Optimization

#### Vectorization

**Before (Slow):**
```r
# Loop-based approach
calculate_points_slow <- function(matches) {
  points <- rep(0, max(c(matches$home_id, matches$away_id)))
  
  for (i in 1:nrow(matches)) {
    if (matches$home_goals[i] > matches$away_goals[i]) {
      points[matches$home_id[i]] <- points[matches$home_id[i]] + 3
    } else if (matches$home_goals[i] < matches$away_goals[i]) {
      points[matches$away_id[i]] <- points[matches$away_id[i]] + 3
    } else {
      points[matches$home_id[i]] <- points[matches$home_id[i]] + 1
      points[matches$away_id[i]] <- points[matches$away_id[i]] + 1
    }
  }
  
  return(points)
}
```

**After (Fast):**
```r
# Vectorized approach
calculate_points_fast <- function(matches) {
  # Determine winners
  home_wins <- matches$home_goals > matches$away_goals
  away_wins <- matches$home_goals < matches$away_goals
  draws <- matches$home_goals == matches$away_goals
  
  # Calculate points
  home_points <- home_wins * 3 + draws * 1
  away_points <- away_wins * 3 + draws * 1
  
  # Aggregate by team
  all_points <- c(
    tapply(home_points, matches$home_id, sum),
    tapply(away_points, matches$away_id, sum)
  )
  
  # Combine points for same teams
  aggregate(all_points, by = list(names(all_points)), sum)$x
}
```

#### Memory Pre-allocation

**Before:**
```r
# Growing vectors (slow)
results <- c()
for (i in 1:10000) {
  results <- c(results, simulate_match())
}
```

**After:**
```r
# Pre-allocated (fast)
results <- numeric(10000)
for (i in 1:10000) {
  results[i] <- simulate_match()
}
```

### 2. Rcpp Optimization

#### Optimize Critical Functions

```cpp
// SpielNichtSimulieren_optimized.cpp
#include <Rcpp.h>
#include <unordered_map>
using namespace Rcpp;

// [[Rcpp::export]]
NumericVector updateEloRatingsOptimized(NumericVector elo_ratings, 
                                        IntegerVector team_ids,
                                        DataFrame matches) {
  // Use hash map for O(1) lookups
  std::unordered_map<int, int> team_index;
  for (int i = 0; i < team_ids.size(); i++) {
    team_index[team_ids[i]] = i;
  }
  
  // Extract match data once
  IntegerVector home_ids = matches["home_id"];
  IntegerVector away_ids = matches["away_id"];
  IntegerVector home_goals = matches["home_goals"];
  IntegerVector away_goals = matches["away_goals"];
  
  // Clone ratings to avoid modifying input
  NumericVector new_ratings = clone(elo_ratings);
  
  // Process all matches
  const double K = 32.0;
  for (int i = 0; i < home_ids.size(); i++) {
    int home_idx = team_index[home_ids[i]];
    int away_idx = team_index[away_ids[i]];
    
    double home_elo = new_ratings[home_idx];
    double away_elo = new_ratings[away_idx];
    
    // Expected scores
    double expected_home = 1.0 / (1.0 + pow(10.0, (away_elo - home_elo) / 400.0));
    
    // Actual scores
    double actual_home = (home_goals[i] > away_goals[i]) ? 1.0 :
                        (home_goals[i] < away_goals[i]) ? 0.0 : 0.5;
    
    // Update ratings
    new_ratings[home_idx] += K * (actual_home - expected_home);
    new_ratings[away_idx] += K * ((1.0 - actual_home) - (1.0 - expected_home));
  }
  
  return new_ratings;
}
```

#### Parallel Processing with OpenMP

```cpp
// [[Rcpp::plugins(openmp)]]
// [[Rcpp::export]]
NumericMatrix simulateSeasonParallel(NumericVector elo_ratings,
                                    DataFrame fixtures,
                                    int iterations = 10000) {
  int n_teams = elo_ratings.size();
  NumericMatrix position_counts(n_teams, n_teams);
  
  #pragma omp parallel for
  for (int iter = 0; iter < iterations; iter++) {
    // Each thread gets its own workspace
    NumericVector iter_points(n_teams);
    NumericVector iter_elos = clone(elo_ratings);
    
    // Simulate season
    // ... simulation code ...
    
    // Update position matrix (thread-safe)
    #pragma omp critical
    {
      for (int i = 0; i < n_teams; i++) {
        position_counts(i, final_positions[i])++;
      }
    }
  }
  
  return position_counts / iterations;
}
```

### 3. Data Structure Optimization

#### Use Efficient Data Structures

```r
# Use data.table for large datasets
library(data.table)

# Convert to data.table
matches_dt <- as.data.table(matches)

# Fast aggregation
team_stats <- matches_dt[, .(
  games = .N,
  goals_for = sum(goals),
  goals_against = sum(goals_conceded)
), by = team_id]

# Fast joins
setkey(matches_dt, home_id)
setkey(teams_dt, id)
matches_with_teams <- teams_dt[matches_dt]
```

#### Cache Frequently Used Data

```r
# cache_manager.R
CacheManager <- R6::R6Class("CacheManager",
  private = list(
    cache = list(),
    max_size = 100,
    
    evict_lru = function() {
      # Remove least recently used
      access_times <- sapply(private$cache, function(x) x$accessed)
      oldest <- which.min(access_times)
      private$cache[[oldest]] <- NULL
    }
  ),
  
  public = list(
    get = function(key) {
      if (key %in% names(private$cache)) {
        private$cache[[key]]$accessed <- Sys.time()
        return(private$cache[[key]]$value)
      }
      return(NULL)
    },
    
    set = function(key, value) {
      if (length(private$cache) >= private$max_size) {
        private$evict_lru()
      }
      
      private$cache[[key]] <- list(
        value = value,
        accessed = Sys.time()
      )
    }
  )
)

# Use cache
cache <- CacheManager$new()
get_team_data <- function(team_id) {
  cached <- cache$get(paste0("team_", team_id))
  if (!is.null(cached)) return(cached)
  
  # Fetch data
  data <- fetch_team_data(team_id)
  cache$set(paste0("team_", team_id), data)
  return(data)
}
```

### 4. Database Optimization

#### Indexing Strategy

```sql
-- Create indexes for common queries
CREATE INDEX idx_matches_date ON matches(match_date);
CREATE INDEX idx_matches_teams ON matches(home_team_id, away_team_id);
CREATE INDEX idx_teams_league ON teams(league_id, season);

-- Composite index for complex queries
CREATE INDEX idx_matches_league_date 
ON matches(league_id, season, match_date) 
WHERE status = 'completed';

-- Analyze tables for optimizer
ANALYZE matches;
ANALYZE teams;
```

#### Query Optimization

```r
# Inefficient: Multiple queries
get_team_stats_slow <- function(team_ids) {
  stats <- list()
  for (id in team_ids) {
    stats[[id]] <- dbGetQuery(con, 
      sprintf("SELECT * FROM team_stats WHERE team_id = %d", id))
  }
  return(stats)
}

# Efficient: Single query
get_team_stats_fast <- function(team_ids) {
  dbGetQuery(con, 
    sprintf("SELECT * FROM team_stats WHERE team_id IN (%s)",
            paste(team_ids, collapse = ",")))
}
```

### 5. API Optimization

#### Request Batching

```r
# batch_api_requests.R
BatchAPIClient <- R6::R6Class("BatchAPIClient",
  private = list(
    queue = list(),
    max_batch_size = 20,
    
    execute_batch = function() {
      if (length(private$queue) == 0) return()
      
      # Combine requests
      batch_request <- list(
        requests = private$queue
      )
      
      # Single API call for multiple items
      response <- POST(
        url = "https://api.example.com/batch",
        body = batch_request,
        encode = "json"
      )
      
      # Clear queue
      private$queue <- list()
      
      return(content(response))
    }
  ),
  
  public = list(
    add_request = function(endpoint, params) {
      private$queue[[length(private$queue) + 1]] <- list(
        endpoint = endpoint,
        params = params
      )
      
      if (length(private$queue) >= private$max_batch_size) {
        return(private$execute_batch())
      }
    },
    
    flush = function() {
      private$execute_batch()
    }
  )
)
```

#### Response Caching

```r
# api_cache.R
cache_api_response <- function(endpoint, params, ttl = 3600) {
  cache_key <- digest::digest(list(endpoint, params))
  cache_file <- file.path("cache", paste0(cache_key, ".rds"))
  
  # Check cache
  if (file.exists(cache_file)) {
    cache_data <- readRDS(cache_file)
    if (difftime(Sys.time(), cache_data$timestamp, units = "secs") < ttl) {
      return(cache_data$response)
    }
  }
  
  # Make request
  response <- make_api_request(endpoint, params)
  
  # Save to cache
  saveRDS(list(
    response = response,
    timestamp = Sys.time()
  ), cache_file)
  
  return(response)
}
```

### 6. Docker Optimization

#### Multi-stage Build

```dockerfile
# Dockerfile.optimized
# Build stage
FROM rocker/r-ver:4.2.3 AS builder

# Install compilation dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    build-essential

# Install R packages
COPY renv.lock .
RUN R -e "install.packages('renv')" && \
    R -e "renv::restore()"

# Compile Rcpp code
COPY RCode/*.cpp /tmp/
RUN R CMD SHLIB /tmp/*.cpp

# Runtime stage
FROM rocker/r-ver:4.2.3-slim

# Copy only necessary files
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library
COPY --from=builder /tmp/*.so /app/RCode/

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

COPY . /app
WORKDIR /app

CMD ["Rscript", "RCode/updateScheduler.R"]
```

#### Resource Limits

```yaml
# docker-compose.yml
services:
  league-simulator:
    image: league-simulator:optimized
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 3G
        reservations:
          cpus: '1'
          memory: 2G
    environment:
      - R_MAX_VSIZE=3000000000  # 3GB max memory for R
```

## Performance Monitoring

### 1. Real-time Monitoring

```r
# performance_monitor.R
library(profvis)

monitor_performance <- function(duration_minutes = 60) {
  start_time <- Sys.time()
  metrics <- list()
  
  while (difftime(Sys.time(), start_time, units = "mins") < duration_minutes) {
    # Capture metrics
    current_metrics <- list(
      timestamp = Sys.time(),
      memory_used = pryr::mem_used(),
      cpu_percent = system("ps aux | grep R | head -1 | awk '{print $3}'", intern = TRUE),
      open_files = length(system("lsof -p $$ | wc -l", intern = TRUE))
    )
    
    metrics[[length(metrics) + 1]] <- current_metrics
    
    # Sleep
    Sys.sleep(60)
  }
  
  # Generate report
  performance_report(metrics)
}
```

### 2. Profiling Tools

```r
# Profile simulation
profvis({
  source("RCode/simulationsCPP.R")
  simulate_league(78, iterations = 1000)
})

# Memory profiling
Rprof("simulation.prof", memory.profiling = TRUE)
simulate_league(78, iterations = 1000)
Rprof(NULL)
summaryRprof("simulation.prof", memory = "both")

# Line profiling
library(lineprof)
l <- lineprof(simulate_league(78, iterations = 1000))
shine(l)
```

### 3. Bottleneck Analysis

```r
# identify_bottlenecks.R
analyze_bottlenecks <- function() {
  # Time each component
  timings <- list()
  
  # API calls
  timings$api <- system.time({
    retrieve_match_data(78, 2025)
  })
  
  # ELO calculations
  timings$elo <- system.time({
    update_elo_ratings(teams, matches)
  })
  
  # Simulations
  timings$simulation <- system.time({
    run_monte_carlo(teams, fixtures, 1000)
  })
  
  # I/O operations
  timings$io <- system.time({
    saveRDS(large_object, "test.rds")
    readRDS("test.rds")
  })
  
  # Identify slowest
  slowest <- names(which.max(sapply(timings, function(x) x["elapsed"])))
  
  cat("Bottleneck identified:", slowest, "\n")
  print(timings)
}
```

## Performance Tuning Checklist

### Quick Wins (< 1 hour)
- [ ] Enable compiler optimization: `compiler::enableJIT(3)`
- [ ] Increase memory limit: `memory.limit(8000)`
- [ ] Use faster BLAS: Install OpenBLAS
- [ ] Reduce simulation iterations temporarily
- [ ] Clear cache and temp files

### Medium Effort (1-4 hours)
- [ ] Vectorize loop operations
- [ ] Implement caching layer
- [ ] Add database indexes
- [ ] Optimize Docker images
- [ ] Profile and fix hot spots

### Major Optimizations (> 4 hours)
- [ ] Rewrite critical functions in Rcpp
- [ ] Implement parallel processing
- [ ] Move to faster data structures
- [ ] Database query optimization
- [ ] Horizontal scaling setup

## Performance Testing

### Load Testing

```r
# load_test.R
library(parallel)

load_test <- function(concurrent_leagues = 3, iterations = 10000) {
  # Test concurrent simulations
  start_time <- Sys.time()
  
  results <- mclapply(1:concurrent_leagues, function(i) {
    league_id <- c(78, 79, 80)[i]
    simulate_league(league_id, iterations)
  }, mc.cores = concurrent_leagues)
  
  duration <- difftime(Sys.time(), start_time, units = "secs")
  
  cat("Load test completed:\n")
  cat("- Concurrent leagues:", concurrent_leagues, "\n")
  cat("- Iterations per league:", iterations, "\n")
  cat("- Total time:", duration, "seconds\n")
  cat("- Average per league:", duration / concurrent_leagues, "seconds\n")
}
```

### Stress Testing

```bash
#!/bin/bash
# stress_test.sh

echo "Starting stress test..."

# Gradually increase load
for ITERATIONS in 1000 5000 10000 20000 50000; do
  echo "Testing with $ITERATIONS iterations..."
  
  TIME=$(time -p docker-compose exec league-simulator Rscript -e "
    source('RCode/simulationsCPP.R')
    simulate_league(78, iterations = $ITERATIONS)
  " 2>&1 | grep real | awk '{print $2}')
  
  echo "Time: ${TIME}s"
  echo "Rate: $(bc <<< "scale=2; $ITERATIONS / $TIME") iterations/second"
  
  # Check memory
  docker stats --no-stream league-simulator
done
```

## Scaling Strategies

### Vertical Scaling

```yaml
# docker-compose.scaled.yml
services:
  league-simulator:
    image: league-simulator:latest
    deploy:
      resources:
        limits:
          cpus: '8'
          memory: 16G
    environment:
      - PARALLEL_CORES=8
      - R_MAX_VSIZE=15000000000
```

### Horizontal Scaling

```yaml
# docker-compose.horizontal.yml
services:
  league-simulator-1:
    image: league-simulator:latest
    environment:
      - LEAGUES=78  # Bundesliga only
      
  league-simulator-2:
    image: league-simulator:latest
    environment:
      - LEAGUES=79  # 2. Bundesliga only
      
  league-simulator-3:
    image: league-simulator:latest
    environment:
      - LEAGUES=80  # 3. Liga only
```

## Related Documentation

- [Architecture Overview](../architecture/overview.md)
- [Common Issues](common-issues.md)
- [Monitoring Guide](../operations/monitoring.md)
- [Scaling Guide](../deployment/production.md#scaling)