# Cleanup Branches - Maintenance Command

Remove merged worktrees, clean up stale branches, and maintain a tidy development environment.

## Overview
This command helps maintain a clean workspace by identifying and removing worktrees and branches that are no longer needed, with safety checks to prevent data loss.

## Usage
```bash
/cleanup-branches [--dry-run] [--force] [--all]
```

## Options
- `--dry-run`: Show what would be cleaned without making changes
- `--force`: Skip confirmation prompts (use with caution)
- `--all`: Include all merged branches, not just worktree branches

## Process

1. **Identify Cleanup Candidates**:
   ```bash
   # Find merged worktrees
   MERGED_WORKTREES=()
   for worktree in $(git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2); do
     if [[ "$worktree" != "$(git rev-parse --show-toplevel)" ]]; then
       cd "$worktree" 2>/dev/null || continue
       
       # Check if branch is merged
       BRANCH=$(git branch --show-current)
       if git branch -r --merged main | grep -q "$BRANCH"; then
         MERGED_WORKTREES+=("$worktree|$BRANCH")
       fi
     fi
   done
   
   # Find stale worktrees (no corresponding issue)
   STALE_WORKTREES=()
   for worktree in $(git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2); do
     ISSUE_NUM=$(echo $worktree | grep -oE 'issue-([0-9]+)' | grep -oE '[0-9]+')
     if [ -n "$ISSUE_NUM" ]; then
       # Check if issue is closed
       STATE=$(gh issue view $ISSUE_NUM --json state --jq '.state' 2>/dev/null)
       if [[ "$STATE" == "CLOSED" ]]; then
         STALE_WORKTREES+=("$worktree|$ISSUE_NUM")
       fi
     fi
   done
   ```

2. **Safety Checks**:
   ```bash
   # Check for uncommitted changes
   check_uncommitted_changes() {
     local worktree=$1
     cd "$worktree"
     if [[ -n $(git status --porcelain) ]]; then
       echo "⚠️  Uncommitted changes in $worktree"
       return 1
     fi
     return 0
   }
   
   # Check for unpushed commits
   check_unpushed_commits() {
     local worktree=$1
     cd "$worktree"
     UNPUSHED=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
     if [[ $UNPUSHED -gt 0 ]]; then
       echo "⚠️  $UNPUSHED unpushed commits in $worktree"
       return 1
     fi
     return 0
   }
   ```

3. **Display Cleanup Plan**:
   ```
   🧹 Cleanup Analysis
   
   📦 Merged Worktrees (safe to remove):
   ✓ ../project-issue-123 (feature/issue-123-auth) - Merged to main
   ✓ ../project-issue-456 (feature/issue-456-api) - Merged to main
   
   📂 Stale Worktrees (issues closed):
   • ../project-issue-789 - Issue #789 is closed
     └─ ⚠️  Has 3 uncommitted changes
   
   🌿 Orphaned Branches (no worktree):
   • feature/issue-999-old - Merged 30 days ago
   • feature/issue-888-test - Merged 45 days ago
   
   📊 Summary:
   • 2 merged worktrees to remove
   • 1 stale worktree (needs manual review)
   • 2 orphaned branches to delete
   • Will free ~150 MB of disk space
   
   Proceed with cleanup? [y/N]
   ```

4. **Execute Cleanup**:
   ```bash
   # Remove merged worktrees
   cleanup_worktree() {
     local worktree=$1
     local branch=$2
     
     echo "🗑️  Removing worktree: $worktree"
     git worktree remove "$worktree" --force
     
     echo "🌿  Deleting branch: $branch"
     git branch -d "$branch" 2>/dev/null || git branch -D "$branch"
     
     # Also delete remote branch if it exists
     if git ls-remote --heads origin "$branch" | grep -q "$branch"; then
       echo "🌐  Deleting remote branch: origin/$branch"
       git push origin --delete "$branch"
     fi
   }
   
   # Archive before deletion (optional)
   archive_worktree() {
     local worktree=$1
     local archive_name="archive-$(basename $worktree)-$(date +%Y%m%d).tar.gz"
     
     echo "📦  Archiving to $archive_name"
     tar -czf "$archive_name" -C "$(dirname $worktree)" "$(basename $worktree)"
   }
   ```

5. **Cleanup Report**:
   ```
   ✅ Cleanup Complete
   
   🗑️  Removed:
   • 2 worktrees
   • 4 local branches  
   • 2 remote branches
   
   💾 Freed: 152 MB
   
   ⏭️  Skipped (manual review needed):
   • ../project-issue-789 - Has uncommitted changes
   
   💡 Next Steps:
   • Review skipped items manually
   • Run '/branch-status' to see current state
   • Use '/parallel' to start new work
   ```

## Safety Features

### Pre-cleanup Validation
- Checks for uncommitted changes
- Detects unpushed commits
- Verifies merge status
- Confirms with user

### Smart Detection
- Identifies truly merged branches
- Finds closed issue associations
- Detects orphaned branches
- Calculates space savings

### Recovery Options
- Archive before deletion
- Dry-run mode for preview
- Force flag for automation
- Detailed logging

## Examples

```bash
# Preview what would be cleaned
/cleanup-branches --dry-run

# Normal interactive cleanup
/cleanup-branches

# Force cleanup without prompts
/cleanup-branches --force

# Clean all merged branches
/cleanup-branches --all

# Combine options
/cleanup-branches --all --dry-run
```

## Error Handling

- **Uncommitted changes**: Skip worktree, show warning
- **Unpushed commits**: Skip worktree, suggest push
- **Active worktree**: Never remove main worktree
- **Permission errors**: Show clear error message

## Best Practices

1. **Regular Maintenance**: Run weekly to prevent buildup
2. **Review First**: Always use `--dry-run` first
3. **Archive Important Work**: Consider archiving before cleanup
4. **Check Status**: Run `/branch-status` before and after

## Integration

- Works with `/parallel` workflow
- Complements `/eod` cleanup
- Updates issue status if needed
- Maintains git repository health