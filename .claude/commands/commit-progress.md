# Commit Progress - Progressive Commit Helper

Create a contextual commit for the current work phase.

## Overview
This command helps create progressive commits during development, automatically detecting the current work phase and generating appropriate commit messages.

## Usage
```bash
/commit-progress [issue-number] [optional-message]
```

## Process

1. **Detect Current Context**:
   - Check if in a worktree (get issue number from path)
   - Identify current workflow phase from issue labels
   - Analyze changed files to understand work scope

2. **Generate Commit Message**:
   ```bash
   # Get issue details
   ISSUE_NUM=$1
   if [ -z "$ISSUE_NUM" ]; then
     # Extract from worktree path if available
     WORKTREE_PATH=$(pwd)
     ISSUE_NUM=$(echo $WORKTREE_PATH | grep -oE 'issue-([0-9]+)' | grep -oE '[0-9]+')
   fi
   
   # Determine commit type based on changes
   if git diff --cached --name-only | grep -q "test"; then
     TYPE="test"
   elif git diff --cached --name-only | grep -q "docs"; then
     TYPE="docs"
   elif git diff --cached --name-only | grep -q ".claude/commands"; then
     TYPE="feat"
   else
     TYPE="chore"
   fi
   
   # Get current phase from issue
   PHASE=$(gh issue view $ISSUE_NUM --json labels --jq '.labels[] | select(.name | startswith("status:")) | .name' | sed 's/status://')
   ```

3. **Stage Changes Intelligently**:
   ```bash
   # If no files staged, stage based on phase
   if [ -z "$(git diff --cached --name-only)" ]; then
     case $PHASE in
       "in_depth_analysis")
         git add -A "*.md" "*.txt" 2>/dev/null || true
         ;;
       "tests_written"|"tests_approved")
         git add -A "*test*" "*.spec.*" 2>/dev/null || true
         ;;
       "implementation")
         git add -A
         ;;
     esac
   fi
   ```

4. **Create Commit**:
   ```bash
   # Generate contextual message
   if [ -n "$2" ]; then
     # Use provided message
     MESSAGE="$2"
   else
     # Auto-generate based on phase
     case $PHASE in
       "in_depth_analysis")
         MESSAGE="complete technical analysis and research"
         ;;
       "tests_written")
         MESSAGE="add comprehensive test specifications"
         ;;
       "implementation")
         MESSAGE="implement $(git diff --cached --name-only | head -1 | xargs basename)"
         ;;
       *)
         MESSAGE="update work in progress"
         ;;
     esac
   fi
   
   # Create commit
   git commit -m "$TYPE(#$ISSUE_NUM): $MESSAGE"
   ```

5. **Provide Feedback**:
   ```
   ✅ Progress Committed
   
   Issue: #[number]
   Phase: [current phase]
   Commit: [type](#[number]): [message]
   
   Files included:
   [list of committed files]
   
   Next: Continue with /makeprogress [number]
   ```

## Features

### Smart Staging
- Stages files based on current phase
- Analyzes file patterns to determine commit type
- Handles partial work appropriately

### Contextual Messages
- Auto-detects work phase from issue labels
- Generates meaningful commit messages
- Allows custom messages when needed

### WIP Support
- Marks incomplete work appropriately
- Maintains commit history for rollback
- Integrates with squash-on-merge workflow

## Examples

```bash
# Auto-detect everything
/commit-progress

# Specify issue number
/commit-progress 123

# Custom message
/commit-progress 123 "add validation logic for user input"

# In a worktree (issue auto-detected)
cd ../project-issue-456
/commit-progress
```

## Error Handling

- **No changes**: "No changes to commit. Make some changes first!"
- **No issue**: "Cannot determine issue number. Specify: /commit-progress [number]"
- **Not in repo**: "Not in a git repository"
- **Commit failed**: Show git error and suggest fixes

## Integration

Works seamlessly with:
- `/makeprogress` - Commits at phase transitions
- `/eod` - Handles uncommitted progress
- `/parallel` - Works across multiple worktrees