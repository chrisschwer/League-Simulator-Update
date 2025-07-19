Create a comprehensive pull request for issue #$ARGUMENTS with:

## Pre-PR Checklist

**Worktree & Branch Verification**:
```bash
# Ensure we're in the correct worktree
current_branch=$(git branch --show-current)
if [[ ! "$current_branch" =~ "issue-$ARGUMENTS" ]]; then
    echo "⚠️ Not in issue worktree. Switching..."
    worktree_path="../$(basename "$(pwd)")-issue-$ARGUMENTS"
    if [ -d "$worktree_path" ]; then
        cd "$worktree_path"
    else
        echo "❌ No worktree found for issue #$ARGUMENTS"
        exit 1
    fi
fi

# Clean up WIP commits if desired
echo "Current commits:"
git log --oneline main..HEAD
echo ""
echo "Consider squashing WIP commits with: git rebase -i main"

# Push the feature branch
git push -u origin $(git branch --show-current)
```

## PR Structure

1. **Title**: Clear, concise description following conventional commits format

2. **Summary**: 
   - What this PR accomplishes
   - Why these changes were made
   - High-level approach taken

3. **Changes Made**:
   - List all significant changes
   - Group by component/module
   - Highlight breaking changes

4. **Testing**:
   - Test coverage percentage
   - Types of tests added/modified
   - Manual testing performed
   - Performance impact measured

5. **Screenshots/Examples** (if applicable):
   - Before/after comparisons
   - API request/response examples
   - UI changes

6. **Checklist**:
   - [ ] Code follows project style guidelines
   - [ ] Self-review completed
   - [ ] Tests pass locally
   - [ ] Documentation updated
   - [ ] No console logs or debug code
   - [ ] Security considerations addressed
   - [ ] Performance impact acceptable

7. **Dependencies**:
   - Related PRs or issues
   - Required deployment order
   - Configuration changes needed

8. **Rollback Plan**:
   - How to revert if needed
   - Feature flags to disable

Make the PR description thorough enough for effective review while remaining concise and scannable.

## Automated PR Creation

After preparing the PR content above, create the PR using GitHub CLI:

```bash
# Create PR from feature branch to main
gh pr create \
  --base main \
  --head $(git branch --show-current) \
  --title "feat(#$ARGUMENTS): [concise description]" \
  --body "[Full PR description from above]" \
  --assignee @me

# Link to the issue
gh pr edit --add-label "issue-$ARGUMENTS"

# Output PR URL for reference
echo "✅ Pull request created successfully!"
echo "   View at: $(gh pr view --json url -q .url)"
```

## Projects Board Integration

After creating the PR, update the issue status on the Projects board:

```bash
# Move issue to Validation stage on Projects board
if command -v ./scripts/board-automation.sh &> /dev/null; then
    ./scripts/board-automation.sh move-issue $ARGUMENTS "✅ Validation"
    echo "✅ Issue #$ARGUMENTS moved to Validation stage on Projects board"
else
    echo "ℹ️  Board automation script not found - manually update Projects board"
fi

# Update issue label to reflect PR creation
gh issue edit $ARGUMENTS --add-label "status:pr_created"
```

## Post-PR Worktree Management

Consider whether to:
1. **Keep worktree active** for addressing PR feedback
2. **Remove worktree** if work is complete:
   ```bash
   cd ..
   git worktree remove "$(basename "$(pwd)")-issue-$ARGUMENTS"
   ```
3. **Archive worktree** for future reference