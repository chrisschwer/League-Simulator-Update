# Branch Status - Worktree and Branch Overview

Display a comprehensive view of all worktrees, branches, and their relationships.

## Overview
This command provides a visual overview of your entire development workspace, showing all active worktrees, their associated issues, and current status.

## Usage
```bash
/branch-status [--verbose]
```

## Process

1. **Gather Worktree Information**:
   ```bash
   # Get all worktrees with details
   git worktree list --porcelain > /tmp/worktrees.txt
   
   # Parse worktree data
   while IFS= read -r line; do
     if [[ $line == worktree* ]]; then
       WORKTREE_PATH="${line#worktree }"
     elif [[ $line == HEAD* ]]; then
       COMMIT="${line#HEAD }"
     elif [[ $line == branch* ]]; then
       BRANCH="${line#branch refs/heads/}"
     elif [[ -z $line ]]; then
       # Process complete worktree entry
       process_worktree
     fi
   done < /tmp/worktrees.txt
   ```

2. **Extract Issue Information**:
   ```bash
   # For each worktree, get associated issue
   ISSUE_NUM=$(echo $WORKTREE_PATH | grep -oE 'issue-([0-9]+)' | grep -oE '[0-9]+')
   
   if [ -n "$ISSUE_NUM" ]; then
     # Get issue details
     ISSUE_INFO=$(gh issue view $ISSUE_NUM --json title,labels,assignees 2>/dev/null)
     ISSUE_TITLE=$(echo $ISSUE_INFO | jq -r '.title' | cut -c1-50)
     ISSUE_STATUS=$(echo $ISSUE_INFO | jq -r '.labels[] | select(.name | startswith("status:")) | .name')
   fi
   ```

3. **Check Working Tree Status**:
   ```bash
   # For each worktree, check for changes
   cd "$WORKTREE_PATH"
   MODIFIED=$(git status --porcelain | wc -l)
   AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
   BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
   ```

4. **Display Visual Overview**:
   ```
   🌳 Worktree Status Overview
   
   📍 Main Repository
   └─ /path/to/main (main) ✓ clean
   
   🔧 Active Development
   ├─ ../project-issue-123 (feature/issue-123-auth) 
   │  └─ #123: "Implement user authentication" [status:implementation]
   │     📝 5 modified files | ↑2 ahead
   │
   ├─ ../project-issue-456 (feature/issue-456-api) 
   │  └─ #456: "Create REST API endpoints" [status:tests_written]
   │     ✓ clean | ↑5 ↓1 (needs rebase)
   │
   └─ ../project-issue-789 (feature/issue-789-docs) 
      └─ #789: "Update documentation" [status:plan_written]
        📝 2 modified files | no remote
   
   📊 Summary
   • Total worktrees: 4 (1 main + 3 feature)
   • Active issues: 3
   • Uncommitted changes: 2 worktrees
   • Ready to push: 2 branches
   
   💡 Suggestions
   ⚠️  Issue #456 needs rebase with main
   📤  Issue #123 has changes ready to commit
   🧹  No stale worktrees to clean up
   ```

5. **Verbose Mode Details**:
   ```bash
   if [[ "$1" == "--verbose" ]]; then
     # Show detailed file changes
     echo -e "\n📄 Detailed Changes:"
     
     for worktree in "${WORKTREES[@]}"; do
       if [ $MODIFIED -gt 0 ]; then
         echo -e "\n$WORKTREE_PATH:"
         cd "$WORKTREE_PATH"
         git status --short
       fi
     done
     
     # Show recent commits
     echo -e "\n📝 Recent Commits:"
     for worktree in "${WORKTREES[@]}"; do
       echo -e "\n$WORKTREE_PATH:"
       cd "$WORKTREE_PATH"
       git log --oneline -3
     done
   fi
   ```

## Features

### Visual Hierarchy
- Tree structure showing relationships
- Clear status indicators (✓, 📝, ⚠️)
- Issue associations and titles
- Workflow phase visibility

### Smart Analysis
- Detects branches needing rebase
- Identifies uncommitted work
- Shows push/pull status
- Suggests next actions

### Integration Points
- Links to issue numbers
- Shows workflow status
- Identifies stale worktrees
- Highlights blockers

## Output Sections

### Status Indicators
- `✓ clean` - No uncommitted changes
- `📝 N modified` - Uncommitted changes
- `↑N ahead` - Commits to push
- `↓N behind` - Needs pull/rebase
- `⚠️` - Needs attention

### Summary Statistics
- Total worktree count
- Active development count
- Changes needing commit
- Branches ready to push

### Intelligent Suggestions
- Rebase recommendations
- Commit reminders
- Cleanup opportunities
- Next logical actions

## Examples

```bash
# Basic status overview
/branch-status

# Detailed view with file changes
/branch-status --verbose

# Pipe to less for large projects
/branch-status --verbose | less
```

## Error Handling

- **No worktrees**: "No active worktrees. Use /parallel to start multi-issue work"
- **Git not initialized**: "Not in a git repository"
- **GH CLI issues**: Gracefully degrade without issue details

## Related Commands

- `/parallel` - Create new worktrees
- `/cleanup-branches` - Remove stale worktrees
- `/commit-progress` - Commit changes in worktrees