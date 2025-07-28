# CI/CD Monitoring Guide

## Overview

This guide describes how to monitor and maintain the League Simulator CI/CD pipeline health using the automated monitoring tools and dashboards implemented as part of the reliability improvements.

## Monitoring Components

### 1. CI Dashboard

The CI Dashboard provides real-time visibility into pipeline performance and health.

**Location**: `.github/workflows/ci-dashboard.yml`  
**Access**: GitHub Actions → CI Performance Dashboard

#### Key Metrics
- **Build Success Rate**: Overall percentage of successful builds
- **Average Build Time**: Rolling average of last 50 builds
- **Test Performance**: Execution time by test suite
- **Failure Analysis**: Categorized failure reasons

#### Dashboard Sections

##### Performance Overview
```
┌─────────────────────────────────────────────┐
│ CI/CD Performance Dashboard                  │
│ ═══════════════════════════════════════════ │
│                                             │
│ Build Success Rate: 94.2% ▲                 │
│ Average Build Time: 15m 32s ▼               │
│ Tests Passed: 1,247/1,298 (96.1%)          │
│ Flaky Tests Quarantined: 3                 │
└─────────────────────────────────────────────┘
```

##### Trend Analysis
- 7-day rolling average charts
- Success rate trends
- Performance regression detection
- Resource usage patterns

### 2. Workflow Monitor

Automated monitoring of workflow health with alerting capabilities.

**Location**: `.github/workflows/workflow-monitor.yml`  
**Schedule**: Every 6 hours

#### Health Checks
1. **Workflow Status**: Checks for stuck or hanging workflows
2. **Resource Usage**: Monitors CPU and memory consumption
3. **Queue Times**: Tracks job wait times
4. **Failure Patterns**: Identifies systematic issues

#### Alert Thresholds
```yaml
alerts:
  success_rate_threshold: 85%
  average_time_threshold: 25m
  queue_time_threshold: 10m
  consecutive_failures: 3
```

### 3. Flaky Test Detection

Automatic identification and quarantine of unstable tests.

**Location**: `.github/workflows/quarantine-flaky-tests.yml`  
**Script**: `.github/scripts/flaky-test-detector.R`

#### Detection Criteria
- Tests failing >20% of the time in last 10 runs
- Tests with high variance in execution time
- Tests failing only on specific platforms

#### Quarantine Process
1. Test identified as flaky
2. Automatically added to quarantine list
3. Issue created for investigation
4. Test excluded from CI until fixed

## Monitoring Procedures

### Daily Checks

1. **Review CI Dashboard**
   ```bash
   # View latest dashboard report
   gh run view --workflow=ci-dashboard.yml --status=completed --limit=1
   ```

2. **Check Failure Patterns**
   ```bash
   # List recent failures
   gh run list --workflow=R-tests.yml --status=failure --limit=10
   ```

3. **Monitor Queue Times**
   ```bash
   # Check workflow queue status
   gh api /repos/OWNER/REPO/actions/runs?status=queued
   ```

### Weekly Analysis

1. **Performance Trends**
   - Review 7-day performance charts
   - Identify any degradation patterns
   - Compare with baseline metrics

2. **Resource Optimization**
   - Analyze CPU/memory usage trends
   - Identify opportunities for optimization
   - Review Docker cache hit rates

3. **Test Suite Health**
   - Review quarantined tests
   - Analyze test execution times
   - Update test sharding if needed

### Monthly Review

1. **Cost Analysis**
   - GitHub Actions minute usage
   - Resource utilization efficiency
   - Cost per build trends

2. **Reliability Metrics**
   - Mean time between failures (MTBF)
   - Mean time to recovery (MTTR)
   - False positive rate

3. **Performance Baseline**
   - Update performance benchmarks
   - Adjust alert thresholds
   - Plan optimization initiatives

## Troubleshooting Common Issues

### High Failure Rate

1. **Check Recent Changes**
   ```bash
   # List recent commits
   git log --oneline -n 20
   
   # Check for infrastructure changes
   gh api /repos/OWNER/REPO/actions/runs?status=failure | jq '.workflow_runs[].head_commit.message'
   ```

2. **Analyze Failure Patterns**
   ```bash
   # Run failure analysis
   Rscript .github/scripts/test-summary.R --analyze-failures
   ```

3. **Review External Dependencies**
   - API rate limits
   - Package repository availability
   - GitHub Actions service status

### Performance Degradation

1. **Identify Slow Tests**
   ```bash
   # Generate performance report
   Rscript .github/scripts/test-summary.R --performance-report
   ```

2. **Check Resource Contention**
   - Review concurrent workflow runs
   - Check for resource-intensive tests
   - Analyze Docker layer cache misses

3. **Optimize Test Distribution**
   ```bash
   # Rebalance test shards
   Rscript .github/scripts/shard-tests.R --rebalance
   ```

### Flaky Test Issues

1. **Review Quarantine List**
   ```r
   # Check quarantined tests
   source(".github/scripts/flaky-test-detector.R")
   list_quarantined_tests()
   ```

2. **Analyze Flakiness Patterns**
   - Platform-specific failures
   - Time-based failures
   - Resource dependency issues

3. **Fix and Re-enable**
   ```r
   # Remove from quarantine after fixing
   remove_from_quarantine("test-name")
   ```

## Alert Response

### Immediate Actions

1. **Build Failure Alert**
   - Check failure reason in dashboard
   - Determine if widespread or isolated
   - Communicate status to team

2. **Performance Alert**
   - Identify performance bottleneck
   - Consider temporary mitigation
   - Plan optimization work

3. **Resource Alert**
   - Check for runaway processes
   - Review resource limits
   - Scale resources if needed

### Escalation Procedures

1. **Level 1**: Automated retry (built-in)
2. **Level 2**: Dev team notification (>3 consecutive failures)
3. **Level 3**: Infrastructure team involvement (systemic issues)

## Best Practices

### Proactive Monitoring

1. **Set Up Notifications**
   ```yaml
   # .github/workflows/workflow-monitor.yml
   notifications:
     slack:
       webhook: ${{ secrets.SLACK_WEBHOOK }}
       channel: "#ci-alerts"
   ```

2. **Regular Reviews**
   - Weekly team review of CI metrics
   - Monthly performance baseline updates
   - Quarterly infrastructure planning

3. **Documentation**
   - Document all incidents and resolutions
   - Update runbooks with new patterns
   - Share learnings with team

### Continuous Improvement

1. **Metric Collection**
   - Add custom metrics for specific concerns
   - Track business-relevant metrics
   - Correlate with deployment success

2. **Optimization Cycles**
   - Monthly performance review
   - Quarterly architecture review
   - Annual tool evaluation

3. **Team Training**
   - Regular CI/CD best practices sessions
   - Incident response drills
   - Tool usage workshops

## Integration with External Tools

### GitHub Insights
- Use GitHub's built-in analytics
- Track workflow run trends
- Monitor API usage

### Third-Party Monitoring
```yaml
# Example: Datadog integration
- name: Send metrics to Datadog
  env:
    DD_API_KEY: ${{ secrets.DATADOG_API_KEY }}
  run: |
    curl -X POST "https://api.datadoghq.com/api/v1/series" \
      -H "Content-Type: application/json" \
      -H "DD-API-KEY: ${DD_API_KEY}" \
      -d @metrics.json
```

### Custom Dashboards
- Export metrics to external systems
- Create custom visualizations
- Set up advanced alerting rules

## Maintenance Calendar

### Daily
- [ ] Check CI dashboard
- [ ] Review failure queue
- [ ] Monitor active workflows

### Weekly
- [ ] Analyze performance trends
- [ ] Review quarantined tests
- [ ] Update test sharding

### Monthly
- [ ] Cost analysis review
- [ ] Performance baseline update
- [ ] Infrastructure planning

### Quarterly
- [ ] Tool evaluation
- [ ] Architecture review
- [ ] Team training session

## Quick Reference

### Useful Commands
```bash
# View CI dashboard
gh workflow run ci-dashboard.yml

# Check workflow status
gh run list --limit=20

# Analyze test performance
Rscript .github/scripts/test-summary.R

# Monitor resource usage
docker stats --no-stream

# Check flaky tests
Rscript .github/scripts/flaky-test-detector.R --report
```

### Key Files
- Dashboard: `.github/workflows/ci-dashboard.yml`
- Monitor: `.github/workflows/workflow-monitor.yml`
- Flaky Detection: `.github/scripts/flaky-test-detector.R`
- Test Analysis: `.github/scripts/test-summary.R`
- Performance Report: `docs/ci-performance-report.md`

### Support Contacts
- CI/CD Issues: Create issue with `ci/cd` label
- Infrastructure: Contact DevOps team
- Monitoring Setup: See IT support