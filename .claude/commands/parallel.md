Create and manage multiple worktrees for parallel issue development.

Usage: /parallel [issue-numbers...]
Example: /parallel 123 456 789

## 1. Multi-Issue Worktree Creation

When provided with multiple issue numbers, create worktrees for each:

```bash
# Parse arguments into array
issues=($ARGUMENTS)

# Validate we have issues to work on
if [ ${#issues[@]} -eq 0 ]; then
    echo "❌ Please provide issue numbers: /parallel 123 456 789"
    exit 1
fi

# Check current worktree count
current_count=$(git worktree list | wc -l)
if [ $((current_count + ${#issues[@]})) -gt 6 ]; then
    echo "⚠️ Warning: This would create more than 5 worktrees (current: $current_count)"
    echo "Consider using /cleanup-branches first"
fi

# Create worktree for each issue
for issue in "${issues[@]}"; do
    worktree_path="../$(basename "$(pwd)")-issue-$issue"
    branch_name="feature/issue-$issue"
    
    # Check if worktree already exists
    if git worktree list | grep -q "$worktree_path"; then
        echo "✅ Worktree already exists: $worktree_path"
    else
        # Fetch issue title for branch description
        issue_title=$(gh issue view $issue --json title -q .title | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g' | cut -c1-30)
        branch_name="feature/issue-$issue-$issue_title"
        
        echo "🌳 Creating worktree for issue #$issue..."
        git worktree add "$worktree_path" -b "$branch_name"
        echo "✅ Created: $worktree_path (branch: $branch_name)"
    fi
done
```

## 2. Parallel Development Dashboard

Show status of all active worktrees:

```bash
echo "📊 Parallel Development Status"
echo "=============================="
echo ""

# Main repository status
echo "🏠 Main Repository ($(pwd)):"
echo "   Branch: $(git branch --show-current)"
echo "   Status: $(git status --porcelain | wc -l) uncommitted changes"
echo ""

# Worktree status
echo "🌳 Active Worktrees:"
git worktree list | while read -r line; do
    path=$(echo "$line" | awk '{print $1}')
    branch=$(echo "$line" | awk '{print $3}' | tr -d '[]')
    
    if [ "$path" != "$(pwd)" ]; then
        # Extract issue number from branch name
        issue_num=$(echo "$branch" | grep -o 'issue-[0-9]*' | cut -d'-' -f2)
        
        # Get issue details
        if [ -n "$issue_num" ]; then
            issue_info=$(gh issue view $issue_num --json title,labels,assignees 2>/dev/null)
            title=$(echo "$issue_info" | jq -r '.title' 2>/dev/null || echo "Unknown")
            status=$(echo "$issue_info" | jq -r '.labels[] | select(.name | startswith("status:")) | .name' 2>/dev/null || echo "Unknown")
            
            echo ""
            echo "📁 Issue #$issue_num: $title"
            echo "   Path: $path"
            echo "   Branch: $branch"
            echo "   Status: $status"
            
            # Check for uncommitted changes
            cd "$path" 2>/dev/null && {
                changes=$(git status --porcelain | wc -l)
                if [ $changes -gt 0 ]; then
                    echo "   ⚠️ Uncommitted changes: $changes files"
                else
                    echo "   ✅ Clean working directory"
                fi
                
                # Check if behind/ahead of origin
                if git rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
                    ahead=$(git rev-list @{u}..HEAD --count)
                    behind=$(git rev-list HEAD..@{u} --count)
                    if [ $ahead -gt 0 ] || [ $behind -gt 0 ]; then
                        echo "   📊 Git: ↑$ahead ↓$behind"
                    fi
                fi
            }
        fi
    fi
done
```

## 3. Quick Switch Between Worktrees

Provide quick navigation commands:

```bash
# If single issue number provided, switch to that worktree
if [ ${#issues[@]} -eq 1 ]; then
    worktree_path="../$(basename "$(pwd)")-issue-${issues[0]}"
    if [ -d "$worktree_path" ]; then
        echo "🔄 Switching to worktree for issue #${issues[0]}..."
        cd "$worktree_path"
        echo "✅ Now in: $(pwd)"
        echo "   Branch: $(git branch --show-current)"
    else
        echo "❌ Worktree not found: $worktree_path"
        echo "   Create it first with: /parallel ${issues[0]}"
    fi
fi
```

## 4. Resource Management

Monitor and manage worktree resources:

```bash
# Count active worktrees
worktree_count=$(git worktree list | wc -l)
echo ""
echo "📊 Resource Usage:"
echo "   Active worktrees: $worktree_count / 5 (recommended limit)"

# Calculate disk usage
total_size=0
git worktree list | while read -r line; do
    path=$(echo "$line" | awk '{print $1}')
    if [ -d "$path" ]; then
        size=$(du -sh "$path" 2>/dev/null | cut -f1)
        echo "   $path: $size"
    fi
done

# Memory warning if too many worktrees
if [ $worktree_count -gt 5 ]; then
    echo ""
    echo "⚠️ Warning: Many active worktrees may impact performance"
    echo "   Consider running: /cleanup-branches"
fi
```

## 5. Batch Operations

Enable operations across multiple worktrees:

### Batch Status Check
```bash
echo "🔍 Checking all worktrees for uncommitted changes..."
git worktree list | while read -r line; do
    path=$(echo "$line" | awk '{print $1}')
    cd "$path" 2>/dev/null || continue
    if [ -n "$(git status --porcelain)" ]; then
        echo "⚠️ $path has uncommitted changes"
    fi
done
```

### Batch Pull Updates
```bash
echo "🔄 Updating all worktrees..."
git worktree list | while read -r line; do
    path=$(echo "$line" | awk '{print $1}')
    branch=$(echo "$line" | awk '{print $3}' | tr -d '[]')
    
    cd "$path" 2>/dev/null || continue
    if [ "$branch" != "main" ]; then
        echo "Updating $path..."
        git pull origin main --rebase
    fi
done
```

## Safety Features

1. **Worktree Limit**: Warn when creating more than 5 worktrees
2. **Branch Protection**: Prevent creating worktrees on main branch
3. **Conflict Detection**: Check for existing branches before creating
4. **Resource Monitoring**: Track disk usage and provide cleanup suggestions
5. **State Validation**: Ensure worktrees are in valid state before operations

## Example Workflows

### Starting Multiple Features
```
/parallel 123 456 789
# Creates three worktrees for parallel development
```

### Quick Status Check
```
/parallel
# Shows dashboard of all active worktrees
```

### Switch to Specific Issue
```
/parallel 123
# Switches to worktree for issue #123
```

### Cleanup Completed Work
```
/parallel cleanup
# Lists worktrees ready for removal
```