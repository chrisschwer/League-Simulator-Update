# Meta Planning Analysis

Analyze all open issues in the repository to create a strategic work plan. Consider:

1. **Issue Analysis**
   - Current status and workflow stage
   - Priority levels (critical, high, medium, low)
   - Dependencies between issues
   - Estimated effort
   - Time in current stage
   - Blocked vs ready to progress

2. **Human Review Queue**
   - Issues awaiting approval at gates (tests_approved, plan_approved, pr_approved)
   - How long they've been waiting
   - Priority order for reviews
   - Risk of blocking other work

3. **Claude Code Work Queue**
   - Issues ready for progression
   - No blocking dependencies
   - Optimal order based on priority and dependencies
   - Parallel execution opportunities

4. **Dependency Analysis**
   - Create dependency graph
   - Identify blocking chains
   - Suggest order to minimize blockages
   - Highlight circular dependencies

5. **Resource Optimization**
   - Which issues can progress in parallel
   - Human review bottlenecks
   - Estimated time to completion
   - Risk factors

## Output Format

### 🚨 Immediate Actions
**For Humans:**
- [ ] Review issue #X (blocking 3 other issues, waiting 2 days)
- [ ] Approve tests for #Y (high priority)

**For Claude Code:**
- [ ] Progress issue #A (no dependencies, high priority)
- [ ] Progress issue #B (can run in parallel with #A)

### 📊 Current Status Overview
```
Workflow Stage    | Count | Oldest
------------------|-------|--------
new               |   3   | 2 days
tests_approved*   |   2   | 3 days  ⚠️
implementation    |   1   | 1 day
pr_approved*      |   1   | 4 hours

* Human approval required
```

### 🔗 Dependency Chains
```
#123 (auth) → #145 (user profile) → #167 (settings)
             ↘ #156 (permissions)

#134 (database) → #178 (caching)
                → #189 (performance)
```

### 📋 Recommended Work Order

**Phase 1 (Can start immediately):**
- #123 - Authentication (no dependencies)
- #134 - Database refactor (no dependencies)
- #101 - Documentation update (independent)

**Phase 2 (After Phase 1 reviews):**
- #145 - User profile (depends on #123)
- #178 - Caching (depends on #134)

**Phase 3 (Parallel execution possible):**
- #156 - Permissions (depends on #123)
- #189 - Performance (depends on #134)
- #167 - Settings (depends on #145)

### ⚠️ Risks and Warnings
- Issue #234 has been in review for 5 days
- Issues #145, #156, #167 all blocked by #123
- No progress possible on performance track until #134 reviewed

### 💡 Optimization Suggestions
1. Prioritize reviewing #123 to unblock 3 dependent issues
2. Claude can work on #101 while waiting for reviews
3. Consider splitting #234 if review is taking too long
4. Start documentation tasks during review wait times

### 📈 Metrics
- Average time in review: 2.3 days
- Issues ready to progress: 4
- Issues blocked: 6
- Parallel execution opportunities: 3

Use the GitHub CLI to gather this data:
```bash
# List all open issues with labels
gh issue list --limit 100 --json number,title,labels,createdAt,updatedAt,body,comments

# Get project status
gh project item-list PROJECT_NUMBER --format json
```

Provide actionable recommendations for both human reviewers and Claude Code to maximize throughput while maintaining quality.