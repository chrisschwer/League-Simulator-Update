# End of Day Cleanup

Perform comprehensive end-of-day housekeeping for the Claude Code workflow environment.

Optional parameter: $ARGUMENTS (additional context for the session summary)

## 1. Workflow Status Analysis

### Worktree Overview
Generate a comprehensive view of all active development:
```bash
echo "🌳 Active Development Worktrees:"
git worktree list | while read -r line; do
    path=$(echo "$line" | awk '{print $1}')
    branch=$(echo "$line" | awk '{print $3}' | tr -d '[]')
    if [ "$path" != "$(pwd)" ]; then
        echo "  📁 $path"
        echo "     └─ Branch: $branch"
        cd "$path" 2>/dev/null && echo "     └─ Status: $(git status --porcelain | wc -l) uncommitted changes"
    fi
done
```

### Standard Workflow Analysis
- Execute `/meta-plan` internally to understand current state
- Identify issues that have been stuck in stages
- Calculate key metrics:
  - Issues progressed today
  - Average time in review
  - Completion rate
  - Blockers identified
  - Active worktrees per issue

## 2. Progress Summary

Generate a detailed summary of today's work:
- List all issues touched today with their transitions
- Highlight completed work (PRs merged, issues closed)
- Show human approvals given
- Calculate productivity metrics

## 3. Documentation Updates

Update project documentation with today's learnings:

### CLAUDE.md Updates
- Add any new workflow patterns discovered
- Document issue-specific preferences learned
- Update command usage examples if needed
- Record any workflow optimizations identified

### Session Handoff Notes
Create `.claude/session_notes/YYYY-MM-DD.md` with:
- Context for next Claude session
- Unfinished work and next steps
- Important decisions made
- Blockers encountered

## 4. Human Review Preparation

Prepare summary for human reviewers:
```
🔍 Awaiting Human Review:
- Issue #123 (tests_approved) - Waiting 2 days ⚠️
- Issue #456 (plan_approved) - High priority
- PR #789 (pr_approved) - Ready to merge
```

## 5. Git Operations

### Worktree Analysis
```bash
# List all active worktrees
git worktree list --porcelain

# For each worktree, check status
for worktree in $(git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2); do
    echo "\n🌳 Worktree: $worktree"
    cd "$worktree" 2>/dev/null || continue
    branch=$(git branch --show-current)
    echo "   Branch: $branch"
    changes=$(git status --porcelain | wc -l)
    echo "   Uncommitted changes: $changes"
done
```

### Analyze Uncommitted Changes Per Worktree
```bash
# Check current location
pwd
git branch --show-current

# Check uncommitted changes
git status --porcelain

# Identify which issues changes relate to
git diff --name-only | xargs grep -l "#[0-9]+" 2>/dev/null
```

### Create Atomic Commits
**For main repository:**
1. Stage only files related to each issue
2. Create descriptive commit message:
   - Format: `type(#issue): description`
   - Types: feat, fix, docs, refactor, test, chore
   - Example: `feat(#123): Add user authentication middleware`

**For worktrees:**
1. Navigate to each worktree with changes
2. Commit all changes in that worktree (since it's issue-specific)
3. Option to squash multiple commits:
   ```bash
   # Interactive rebase to clean up WIP commits
   git rebase -i main
   ```
4. Push worktree branches:
   ```bash
   git push -u origin feature/issue-NUMBER
   ```

### Handle Branch Management
**Main Repository:**
- If on feature branch: commit to current branch
- If on main with changes: 
  - Warn user strongly ⚠️
  - Create feature branch for uncommitted work
  - Stage and commit appropriately

**Worktrees:**
- Each worktree should be on its feature branch
- Verify no worktree is on main branch
- Push all worktree branches:
  ```bash
  for worktree in $(git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2); do
      cd "$worktree" 2>/dev/null || continue
      branch=$(git branch --show-current)
      if [ "$branch" != "main" ] && [ -n "$(git status --porcelain)" ]; then
          git add -A
          git commit -m "feat(#${branch##*/issue-}): end of day checkpoint"
          git push -u origin "$branch"
      fi
  done
  ```

## 6. Repository Validation

Run housekeeping checks:
```bash
# Run validation script
./scripts/validate-setup.sh

# Check for label consistency
gh issue list --json number,labels | jq '.[] | select(.labels | length == 0)'

# Verify workflow integrity
gh issue list --json number,labels | jq '.[] | select(.labels | map(.name) | contains(["status:"]) | not)'
```

## 7. Generate EOD Report

```
🌅 End of Day Summary - [Date]
================================

📊 Today's Metrics:
   ✅ Issues Completed: 3
   🔄 Issues Progressed: 7
   ⏳ Avg Review Time: 1.2 days
   🎯 Completion Rate: 75%

🏆 Achievements:
   ✨ Merged PR #123: User authentication
   ✨ Completed feature: API integration
   ✨ Fixed critical bug: Login timeout

👥 Human Reviews:
   ⏰ Urgent: Issue #456 (blocking 2 others)
   📋 Pending: 3 issues await approval
   ✅ Completed: 5 reviews today

🔄 Git Summary:
   📝 Commits: 12 atomic commits created
   🌿 Active Worktrees: 3
      - ../claude-code-setup-issue-1 (feature/issue-1)
      - ../claude-code-setup-issue-2 (feature/issue-2)
      - ../claude-code-setup-issue-3 (feature/issue-3)
   ⬆️ Pushed: All changes synced across worktrees

📅 Tomorrow's Priorities:
   1. Issue #456 - Complete API error handling
   2. Review #789 - Performance optimizations
   3. Start #234 - Documentation update

💡 Insights:
   - Consider batching similar reviews
   - API tests taking longer than expected
   - Good progress on authentication track

🎉 Great work today! You've made significant progress on the authentication feature
   and maintained excellent code quality throughout. The team's review velocity
   is improving, and we're on track for the sprint goals.

✨ Rest well and see you tomorrow!
```

## 8. Worktree Cleanup

### Identify Completed Work
```bash
# Find worktrees with merged branches
for worktree in $(git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2); do
    cd "$worktree" 2>/dev/null || continue
    branch=$(git branch --show-current)
    if git branch -r --merged main | grep -q "$branch"; then
        echo "✅ Worktree ready for cleanup: $worktree"
    fi
done
```

### Cleanup Options
- **Auto-cleanup merged worktrees**: Remove worktrees whose branches are merged
- **Archive mode**: Move completed worktrees to archive directory
- **Manual review**: List candidates but let user decide

## 9. Celebration & Motivation

Always end on a positive note:
- Highlight biggest achievement of the day
- Recognize quality improvements
- Thank human reviewers for their time
- Generate encouraging message based on progress
- Include a relevant motivational quote about software development

## Example Usage

```
> /eod "Completed authentication feature and API integration"

[Generates comprehensive EOD report with all sections above]
```

## Safety Checks

Before committing:
- Scan for sensitive data (API keys, passwords)
- Warn about large files (>1MB)
- Verify no .env or config files staged
- Check branch protection rules
- Confirm all tests pass