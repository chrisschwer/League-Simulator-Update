# Pod Lifecycle Management Analysis (Issue #26)

## Corrected Requirement Understanding

**Goal**: Resource optimization through pod lifecycle management, NOT scheduling logic replacement.

### What to Keep
- Existing internal scheduling logic in R code
- Smart API usage optimization (maximize free calls)
- Time window calculations and sleep logic
- All current application functionality

### What to Change
- Pod startup/shutdown timing only
- Use CronJobs to scale deployments from 0→1 and 1→0
- Reduce idle resource consumption

## Recommended Solution: Simple CronJob Scaling

### Architecture
```
Current: Deployments run 24/7 (96 pod-hours/day)
         ↓
Proposed: CronJobs scale deployments at precise times (20 pod-hours/day)
          79% resource reduction
```

### Implementation
- 16 CronJobs total (start/stop × 4 deployments × 2 schedules each)
- Use `kubectl scale` commands in CronJob containers
- ServiceAccount with deployment scaling permissions
- 5-minute buffer before/after actual schedule windows

### Schedule Examples
```yaml
# Start Bundesliga weekend
schedule: "15 17 * * 0,6"  # 17:15 Sat/Sun
command: kubectl scale deployment league-updater-bl --replicas=1

# Stop Bundesliga weekend  
schedule: "50 21 * * 0,6"  # 21:50 Sat/Sun
command: kubectl scale deployment league-updater-bl --replicas=0
```

## Why This Approach is Clean

1. **Native Kubernetes patterns** - CronJobs designed for time-based operations
2. **Standard scaling** - kubectl scale is the official method
3. **Zero code changes** - No R application modifications needed
4. **Easy maintenance** - Simple YAML manifests, standard monitoring
5. **Clean rollback** - Delete CronJobs, deployments stay running

## Resource Impact

- **Current**: 4 pods × 24h = 96 pod-hours/day
- **Proposed**: ~20 pod-hours/day across all leagues
- **Savings**: 79% reduction (exceeds 70% target)

## Next Steps

If approved, implementation will focus on:
1. Creating 16 CronJob manifests with precise schedules
2. ServiceAccount and RBAC for scaling permissions
3. Monitoring for CronJob execution success
4. Gradual rollout testing (one league first)

---
*Analysis completed after rejection feedback clarified actual requirements*