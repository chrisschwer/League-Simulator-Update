# Log Analysis Guide

Comprehensive guide for analyzing League Simulator logs to diagnose issues.

## Log Structure Overview

```
logs/
├── simulation_20250119.log    # Main simulation logs
├── api_20250119.log          # API request/response logs
├── scheduler_20250119.log    # Scheduler activity
├── error_20250119.log        # Error-only logs
└── security_20250119.log     # Security events
```

## Log Entry Format

### Standard Log Format

```
[TIMESTAMP] [LEVEL] [COMPONENT] [SESSION_ID] Message
```

Example:
```
[2025-01-19 15:00:00] [INFO] [SCHEDULER] [SES-12345] Starting scheduled update for Bundesliga
[2025-01-19 15:00:01] [DEBUG] [API] [SES-12345] Fetching fixtures for league 78
[2025-01-19 15:00:03] [ERROR] [API] [SES-12345] Rate limit exceeded: 429
```

### Log Levels

| Level | Purpose | When to Investigate |
|-------|---------|---------------------|
| DEBUG | Detailed execution flow | During development |
| INFO | Normal operations | Routine monitoring |
| WARN | Potential issues | Daily review |
| ERROR | Failures requiring attention | Immediately |
| FATAL | Critical failures | Emergency response |

## Common Log Patterns

### 1. Successful Simulation Cycle

```log
[2025-01-19 15:00:00] [INFO] [SCHEDULER] Starting update cycle
[2025-01-19 15:00:01] [INFO] [API] Retrieving match results for league 78
[2025-01-19 15:00:05] [INFO] [ELO] Updating ELO ratings for 18 teams
[2025-01-19 15:00:06] [INFO] [SIMULATION] Starting Monte Carlo simulation (10000 iterations)
[2025-01-19 15:08:15] [INFO] [SIMULATION] Simulation completed successfully
[2025-01-19 15:08:16] [INFO] [STORAGE] Results saved to Ergebnis_78.Rds
[2025-01-19 15:08:17] [INFO] [SCHEDULER] Update cycle completed
```

### 2. API Rate Limit Pattern

```log
[2025-01-19 15:00:00] [INFO] [API] API call 95/100 for today
[2025-01-19 15:05:00] [WARN] [API] Approaching rate limit: 98/100
[2025-01-19 15:10:00] [ERROR] [API] Rate limit exceeded: 429 Too Many Requests
[2025-01-19 15:10:01] [INFO] [SCHEDULER] Pausing operations until 00:00:00
```

### 3. Memory Issues Pattern

```log
[2025-01-19 15:00:00] [INFO] [SIMULATION] Allocating memory for 10000 iterations
[2025-01-19 15:02:30] [WARN] [MEMORY] Memory usage at 85%
[2025-01-19 15:03:45] [ERROR] [SIMULATION] Cannot allocate vector of size 2.1 GB
[2025-01-19 15:03:46] [FATAL] [SYSTEM] Out of memory error
```

## Log Analysis Tools

### 1. Basic Log Searching

```bash
# Find all errors
grep ERROR logs/*.log

# Find errors in specific time range
grep "2025-01-19 15:" logs/*.log | grep ERROR

# Count errors by type
grep ERROR logs/*.log | awk -F'] ' '{print $4}' | sort | uniq -c

# Find specific session
grep "SES-12345" logs/*.log
```

### 2. Advanced Log Analysis

```bash
#!/bin/bash
# analyze_logs.sh

LOG_DIR="logs"
DATE=$(date +%Y%m%d)

echo "=== Log Analysis Report for $DATE ==="

# Error frequency by hour
echo -e "\n## Errors by Hour"
grep ERROR $LOG_DIR/*_$DATE.log | \
  awk -F'[\\[\\]]' '{print substr($2,12,2)}' | \
  sort | uniq -c | sort -k2n

# Top error messages
echo -e "\n## Top 10 Error Messages"
grep ERROR $LOG_DIR/*_$DATE.log | \
  awk -F'] ' '{print $NF}' | \
  sort | uniq -c | sort -rn | head -10

# API performance
echo -e "\n## API Response Times"
grep "API response time" $LOG_DIR/api_$DATE.log | \
  awk '{print $NF}' | \
  awk '{sum+=$1; count++} END {print "Average:", sum/count, "ms"}'

# Simulation duration
echo -e "\n## Simulation Performance"
grep "Simulation completed" $LOG_DIR/simulation_$DATE.log | \
  awk -F'in ' '{print $2}' | \
  awk '{sum+=$1; count++} END {print "Average:", sum/count, "seconds"}'
```

### 3. Real-time Log Monitoring

```bash
# Monitor all logs in real-time
tail -f logs/*.log

# Monitor with filtering
tail -f logs/*.log | grep --line-buffered ERROR

# Monitor with highlighting
tail -f logs/*.log | grep --color=always -E "(ERROR|WARN|FATAL)"

# Monitor specific patterns
tail -f logs/api_*.log | grep --line-buffered "429"
```

### 4. Log Parsing with R

```r
# log_analysis.R

library(tidyverse)
library(lubridate)

# Parse log files
parse_logs <- function(log_file) {
  logs <- readLines(log_file)
  
  # Extract components using regex
  pattern <- "\\[(.*?)\\] \\[(.*?)\\] \\[(.*?)\\] \\[(.*?)\\] (.*)"
  
  parsed <- str_match(logs, pattern)
  
  data.frame(
    timestamp = ymd_hms(parsed[,2]),
    level = parsed[,3],
    component = parsed[,4],
    session_id = parsed[,5],
    message = parsed[,6],
    stringsAsFactors = FALSE
  ) %>%
    filter(!is.na(timestamp))
}

# Analyze patterns
analyze_logs <- function(log_df) {
  # Error frequency over time
  error_timeline <- log_df %>%
    filter(level == "ERROR") %>%
    mutate(hour = hour(timestamp)) %>%
    count(hour, component)
  
  # Session analysis
  session_stats <- log_df %>%
    group_by(session_id) %>%
    summarise(
      start_time = min(timestamp),
      end_time = max(timestamp),
      duration = as.numeric(difftime(max(timestamp), min(timestamp), units = "mins")),
      error_count = sum(level == "ERROR"),
      warn_count = sum(level == "WARN")
    )
  
  # Component health
  component_health <- log_df %>%
    group_by(component, level) %>%
    count() %>%
    spread(level, n, fill = 0)
  
  list(
    error_timeline = error_timeline,
    session_stats = session_stats,
    component_health = component_health
  )
}

# Generate report
generate_log_report <- function(date = Sys.Date()) {
  log_files <- list.files("logs", 
                         pattern = format(date, "%Y%m%d"), 
                         full.names = TRUE)
  
  all_logs <- map_df(log_files, parse_logs)
  analysis <- analyze_logs(all_logs)
  
  # Create visualizations
  library(ggplot2)
  
  # Error timeline
  p1 <- ggplot(analysis$error_timeline, aes(x = hour, y = n, fill = component)) +
    geom_bar(stat = "identity") +
    labs(title = "Errors by Hour", x = "Hour", y = "Count")
  
  # Session duration distribution
  p2 <- ggplot(analysis$session_stats, aes(x = duration)) +
    geom_histogram(bins = 30) +
    labs(title = "Session Duration Distribution", x = "Duration (minutes)")
  
  # Save report
  ggsave("log_analysis_report.pdf", 
         gridExtra::grid.arrange(p1, p2, ncol = 1),
         width = 10, height = 12)
  
  return(analysis)
}
```

## Log Patterns to Watch For

### 1. Performance Degradation

```log
# Increasing simulation times
[2025-01-19 15:00:00] [INFO] Simulation completed in 480 seconds
[2025-01-19 18:00:00] [INFO] Simulation completed in 520 seconds
[2025-01-19 21:00:00] [INFO] Simulation completed in 610 seconds
[2025-01-19 23:00:00] [WARN] Simulation completed in 720 seconds
```

**Action**: Check memory usage, consider restart

### 2. API Degradation

```log
# Increasing API response times
[2025-01-19 15:00:00] [DEBUG] API response time: 245ms
[2025-01-19 15:05:00] [DEBUG] API response time: 890ms
[2025-01-19 15:10:00] [WARN] API response time: 2100ms
[2025-01-19 15:15:00] [ERROR] API timeout after 30000ms
```

**Action**: Check API status, implement retry logic

### 3. Data Quality Issues

```log
# Unexpected data patterns
[2025-01-19 15:00:00] [WARN] Team 999 not found in TeamList
[2025-01-19 15:00:01] [WARN] Match with negative goals: -1
[2025-01-19 15:00:02] [ERROR] Cannot calculate ELO with NULL rating
```

**Action**: Validate input data, check API response format

### 4. Cascading Failures

```log
# One failure leading to others
[2025-01-19 15:00:00] [ERROR] Database connection failed
[2025-01-19 15:00:01] [ERROR] Cannot save team data
[2025-01-19 15:00:02] [ERROR] Simulation aborted: no team data
[2025-01-19 15:00:03] [FATAL] System entering degraded mode
```

**Action**: Address root cause (database), implement circuit breakers

## Log Rotation and Management

### 1. Rotation Configuration

```bash
# /etc/logrotate.d/league-simulator
/app/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 appuser appuser
    postrotate
        docker-compose kill -s HUP league-simulator
    endscript
}
```

### 2. Log Archival

```bash
#!/bin/bash
# archive_logs.sh

ARCHIVE_DIR="/archives/logs"
CURRENT_MONTH=$(date +%Y%m)

# Compress old logs
find logs/ -name "*.log" -mtime +30 -exec gzip {} \;

# Move to archive
mkdir -p "$ARCHIVE_DIR/$CURRENT_MONTH"
mv logs/*.gz "$ARCHIVE_DIR/$CURRENT_MONTH/"

# Create index
ls -la "$ARCHIVE_DIR/$CURRENT_MONTH/" > "$ARCHIVE_DIR/$CURRENT_MONTH/index.txt"
```

## Troubleshooting Specific Issues via Logs

### Issue: "No results generated"

```bash
# Check simulation completion
grep "Simulation completed" logs/simulation_*.log | tail -5

# If no recent completions, check for starts
grep "Starting Monte Carlo" logs/simulation_*.log | tail -5

# Check for interruptions
grep -B5 -A5 "SIGTERM\|SIGKILL" logs/*.log
```

### Issue: "Incorrect standings"

```bash
# Check ELO updates
grep "ELO.*change" logs/simulation_*.log | tail -20

# Verify match processing
grep "Processing match" logs/simulation_*.log | wc -l

# Check for data inconsistencies
grep "WARN.*team.*not found" logs/*.log
```

### Issue: "Random crashes"

```bash
# Look for memory issues
grep -i "memory\|heap\|stack" logs/*.log

# Check for segfaults
dmesg | grep -i segfault

# Review fatal errors
grep "FATAL" logs/*.log | tail -20
```

## Log Analysis Dashboard

Create a simple monitoring dashboard:

```r
# log_dashboard.R
library(shiny)
library(shinydashboard)

ui <- dashboardPage(
  dashboardHeader(title = "Log Analysis Dashboard"),
  dashboardSidebar(
    dateInput("date", "Select Date:", value = Sys.Date())
  ),
  dashboardBody(
    fluidRow(
      valueBoxOutput("error_count"),
      valueBoxOutput("api_calls"),
      valueBoxOutput("simulations")
    ),
    fluidRow(
      box(
        title = "Error Timeline",
        plotOutput("error_plot"),
        width = 12
      )
    ),
    fluidRow(
      box(
        title = "Recent Errors",
        tableOutput("error_table"),
        width = 12
      )
    )
  )
)

server <- function(input, output, session) {
  logs <- reactive({
    parse_logs_for_date(input$date)
  })
  
  output$error_count <- renderValueBox({
    valueBox(
      value = sum(logs()$level == "ERROR"),
      subtitle = "Total Errors",
      color = "red"
    )
  })
  
  output$api_calls <- renderValueBox({
    valueBox(
      value = sum(logs()$component == "API"),
      subtitle = "API Calls",
      color = "blue"
    )
  })
  
  output$simulations <- renderValueBox({
    valueBox(
      value = sum(grepl("completed", logs()$message)),
      subtitle = "Simulations",
      color = "green"
    )
  })
}

shinyApp(ui, server)
```

## Best Practices

1. **Regular Reviews**: Check logs daily for warnings
2. **Automated Alerts**: Set up alerts for ERROR/FATAL
3. **Log Retention**: Keep 30 days local, 1 year archived
4. **Performance Baselines**: Track normal metrics
5. **Correlation**: Cross-reference logs with metrics

## Related Documentation

- [Common Issues](common-issues.md)
- [Performance Monitoring](performance.md)
- [Debugging Guide](debugging.md)
- [Monitoring Setup](../operations/monitoring.md)