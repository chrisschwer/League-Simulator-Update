# Rollback Procedures

Safe version downgrade procedures for the League Simulator system.

## Overview

This guide covers rollback procedures for:
- Application rollbacks
- Database migration rollbacks
- Configuration rollbacks
- Emergency recovery procedures

## Rollback Strategy

### Version Management

```bash
# Tag releases properly
git tag -a v1.2.3 -m "Release version 1.2.3"
git push origin v1.2.3

# Docker image tagging
docker tag league-simulator:latest league-simulator:v1.2.3
docker push registry/league-simulator:v1.2.3
```

### Rollback Decision Matrix

| Scenario | Severity | Rollback Time | Procedure |
|----------|----------|---------------|-----------|
| Application crash | Critical | < 5 min | Quick rollback |
| Performance degradation | High | < 15 min | Gradual rollback |
| Minor bugs | Medium | < 1 hour | Scheduled rollback |
| Data corruption | Critical | Immediate | Emergency recovery |

## Docker Rollback

### Quick Rollback (< 5 minutes)

```bash
#!/bin/bash
# quick-rollback.sh

# Get current version
CURRENT_VERSION=$(docker ps --format "table {{.Image}}" | grep league-simulator | cut -d: -f2)
echo "Current version: $CURRENT_VERSION"

# Get previous version
PREVIOUS_VERSION=$(docker images league-simulator --format "{{.Tag}}" | grep -E "v[0-9]" | head -n 2 | tail -n 1)
echo "Rolling back to: $PREVIOUS_VERSION"

# Stop current containers
docker-compose down

# Update docker-compose.yml with previous version
sed -i "s|league-simulator:.*|league-simulator:$PREVIOUS_VERSION|g" docker-compose.yml

# Start with previous version
docker-compose up -d

# Verify rollback
sleep 10
docker-compose ps
docker-compose logs --tail=50
```

### Gradual Rollback (Blue-Green)

```bash
#!/bin/bash
# gradual-rollback.sh

# Deploy previous version alongside current
docker-compose -f docker-compose.blue-green.yml up -d league-simulator-green

# Test previous version
curl -f http://localhost:3839/health || exit 1

# Switch traffic gradually
for percent in 25 50 75 100; do
  echo "Switching $percent% traffic to previous version"
  # Update load balancer weights
  update_lb_weights $percent
  sleep 300  # Monitor for 5 minutes
  
  # Check error rates
  ERROR_RATE=$(get_error_rate)
  if (( $(echo "$ERROR_RATE > 0.05" | bc -l) )); then
    echo "Error rate too high, aborting rollback"
    exit 1
  fi
done

# Remove current version
docker-compose stop league-simulator-blue
```

## Kubernetes Rollback

### Deployment Rollback

```bash
# Check rollout history
kubectl rollout history deployment/league-simulator -n league-simulator

# Rollback to previous version
kubectl rollout undo deployment/league-simulator -n league-simulator

# Rollback to specific revision
kubectl rollout undo deployment/league-simulator --to-revision=2 -n league-simulator

# Monitor rollback
kubectl rollout status deployment/league-simulator -n league-simulator
```

### Helm Rollback

```bash
# List releases
helm list -n league-simulator

# Check history
helm history league-simulator -n league-simulator

# Rollback to previous release
helm rollback league-simulator -n league-simulator

# Rollback to specific revision
helm rollback league-simulator 3 -n league-simulator

# Verify rollback
helm status league-simulator -n league-simulator
```

## Database Rollback

### Schema Rollback

```sql
-- Rollback script template
-- rollback_v1.2.3.sql

BEGIN;

-- Verify current version
SELECT version FROM schema_versions WHERE active = true;

-- Rollback schema changes
ALTER TABLE league_data.teams DROP COLUMN IF EXISTS new_column;
ALTER TABLE league_data.simulations ALTER COLUMN results TYPE TEXT;

-- Update version
UPDATE schema_versions SET active = false WHERE version = '1.2.3';
UPDATE schema_versions SET active = true WHERE version = '1.2.2';

-- Verify rollback
SELECT * FROM schema_versions WHERE active = true;

COMMIT;
```

### Data Rollback

```bash
#!/bin/bash
# data-rollback.sh

BACKUP_DATE=$1
DB_NAME="league_simulator"

# Stop application
docker-compose stop league-simulator

# Create current backup before rollback
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME > "rollback_backup_$(date +%Y%m%d_%H%M%S).sql"

# Restore from backup
psql -h $DB_HOST -U $DB_USER -d $DB_NAME < "backup_$BACKUP_DATE.sql"

# Verify data integrity
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
  SELECT COUNT(*) as team_count FROM league_data.teams;
  SELECT MAX(created_at) as latest_simulation FROM league_data.simulations;
"

# Restart application
docker-compose start league-simulator
```

## Configuration Rollback

### Environment Variables

```bash
#!/bin/bash
# config-rollback.sh

# Backup current config
cp .env .env.rollback_$(date +%Y%m%d_%H%M%S)

# Get previous config from git
git show HEAD~1:.env > .env.previous

# Compare configurations
diff .env .env.previous

# Apply previous config
cp .env.previous .env

# Restart services with new config
docker-compose restart
```

### Application Configuration

```r
# RCode/config_rollback.R

# Load configuration versions
config_versions <- list(
  "v1.2.3" = list(
    simulation_iterations = 10000,
    update_times = c("15:00", "18:00", "21:00")
  ),
  "v1.2.2" = list(
    simulation_iterations = 5000,
    update_times = c("15:00", "21:00")
  )
)

# Rollback to specific version
rollback_config <- function(version) {
  if (!version %in% names(config_versions)) {
    stop("Version not found")
  }
  
  config <- config_versions[[version]]
  
  # Apply configuration
  Sys.setenv(SIMULATION_ITERATIONS = config$simulation_iterations)
  writeLines(config$update_times, "update_times.txt")
  
  # Log rollback
  cat(sprintf("Rolled back configuration to %s\n", version))
}
```

## Emergency Recovery

### Complete System Recovery

```bash
#!/bin/bash
# emergency-recovery.sh

echo "EMERGENCY RECOVERY INITIATED"
echo "=============================="

# 1. Stop all services
echo "Stopping all services..."
docker-compose down
kubectl delete deployment --all -n league-simulator

# 2. Restore last known good backup
echo "Restoring from backup..."
LAST_GOOD_BACKUP=$(find /backups -name "*.tar.gz" -mtime -1 | head -1)
tar -xzf $LAST_GOOD_BACKUP -C /recovery

# 3. Reset to stable version
echo "Resetting to stable version..."
git checkout v1.2.0  # Last stable version
docker pull registry/league-simulator:v1.2.0

# 4. Restore database
echo "Restoring database..."
psql -h $DB_HOST -U $DB_USER -d $DB_NAME < /recovery/database.sql

# 5. Start minimal services
echo "Starting minimal services..."
docker run -d \
  --name league-simulator-recovery \
  -e RAPIDAPI_KEY=$RAPIDAPI_KEY \
  -e RECOVERY_MODE=true \
  registry/league-simulator:v1.2.0

# 6. Verify recovery
echo "Verifying recovery..."
./health_check.sh

echo "Recovery complete. System running in minimal mode."
```

### Disaster Recovery Runbook

1. **Assess Situation** (2 minutes)
   ```bash
   # Check service status
   docker-compose ps
   kubectl get pods -n league-simulator
   
   # Check recent logs
   docker-compose logs --tail=100
   ```

2. **Communicate** (1 minute)
   - Notify team via Slack/PagerDuty
   - Update status page
   - Inform stakeholders

3. **Execute Rollback** (5-15 minutes)
   ```bash
   # Use appropriate rollback script
   ./quick-rollback.sh  # For application issues
   ./data-rollback.sh 20240719  # For data issues
   ./emergency-recovery.sh  # For complete failure
   ```

4. **Verify** (5 minutes)
   ```bash
   # Run health checks
   ./health_check.sh
   
   # Check key metrics
   curl http://localhost:9090/metrics | grep -E "(error|success)"
   
   # Test functionality
   Rscript test_api_connection.R
   ```

5. **Document** (10 minutes)
   - Create incident report
   - Update runbook if needed
   - Schedule post-mortem

## Rollback Verification

### Health Checks

```bash
#!/bin/bash
# health_check.sh

# Application health
curl -f http://localhost:3838/health || echo "Shiny app unhealthy"

# API connectivity
docker exec league-simulator Rscript -e "source('test_api_connection.R')"

# Database connectivity
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT 1"

# Recent simulations
docker exec league-simulator Rscript -e "
  files <- list.files('ShinyApp/data', pattern='Rds$', full.names=TRUE)
  latest <- files[which.max(file.mtime(files))]
  cat('Latest simulation:', latest, '\n')
  cat('Age:', difftime(Sys.time(), file.mtime(latest), units='hours'), 'hours\n')
"
```

### Monitoring After Rollback

```r
# monitor_rollback.R
library(httr)

monitor_rollback <- function(duration_hours = 1) {
  start_time <- Sys.time()
  errors <- 0
  checks <- 0
  
  while(difftime(Sys.time(), start_time, units="hours") < duration_hours) {
    checks <- checks + 1
    
    # Check API
    api_check <- tryCatch({
      GET("http://localhost:3838/health")
      TRUE
    }, error = function(e) FALSE)
    
    if (!api_check) errors <- errors + 1
    
    # Log status
    cat(sprintf("[%s] Checks: %d, Errors: %d, Error Rate: %.2f%%\n",
                Sys.time(), checks, errors, (errors/checks)*100))
    
    Sys.sleep(60)  # Check every minute
  }
  
  list(total_checks = checks, total_errors = errors, error_rate = errors/checks)
}
```

## Best Practices

### Before Rollback

1. **Backup Current State**
   - Database snapshot
   - Configuration files
   - Application logs

2. **Test Rollback Procedure**
   - Use staging environment
   - Verify backup integrity
   - Test recovery time

3. **Prepare Communication**
   - Draft status updates
   - Prepare stakeholder notifications
   - Document timeline

### During Rollback

1. **Follow Runbook**
   - Don't skip steps
   - Document deviations
   - Keep team informed

2. **Monitor Closely**
   - Watch error rates
   - Check performance metrics
   - Verify functionality

3. **Be Ready to Abort**
   - Have fallback plan
   - Know escalation path
   - Preserve evidence

### After Rollback

1. **Verify Stability**
   - Extended monitoring
   - User acceptance testing
   - Performance validation

2. **Document Incident**
   - Timeline of events
   - Root cause analysis
   - Lessons learned

3. **Update Procedures**
   - Improve runbooks
   - Update automation
   - Train team

## Related Documentation

- [Deployment Guide](detailed-guide.md)
- [Monitoring Guide](../operations/monitoring.md)
- [Incident Response](../operations/incident-response.md)
- [Backup Procedures](../operations/backup-recovery.md)