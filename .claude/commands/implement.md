Implement the approved plan for issue #$ARGUMENTS by:

**Pre-Implementation Setup**:
- Ensure you're in the appropriate worktree:
  ```bash
  # Check if we're in a worktree for this issue
  current_branch=$(git branch --show-current)
  if [[ ! "$current_branch" =~ "issue-$ARGUMENTS" ]]; then
      # Switch to or create worktree
      worktree_path="../$(basename "$(pwd)")-issue-$ARGUMENTS"
      if [ -d "$worktree_path" ]; then
          cd "$worktree_path"
      else
          git worktree add "$worktree_path" -b "feature/issue-$ARGUMENTS"
          cd "$worktree_path"
      fi
  fi
  ```

1. **Following the implementation plan exactly**:
   - Work through each phase systematically
   - Create/modify files as specified
   - Maintain the planned architecture
   - **Create progress commits after each phase**:
     ```bash
     git add -A
     git commit -m "feat(#$ARGUMENTS): [phase description]"
     ```

2. **Code Quality Standards**:
   - Write clean, readable code with meaningful names
   - Add appropriate comments for complex logic
   - Follow project coding conventions
   - Ensure proper error handling throughout

3. **Testing as you go**:
   - Run tests after each significant change
   - Ensure no regressions are introduced
   - Verify the implementation matches test expectations

4. **Documentation**:
   - Update code comments
   - Add/update API documentation
   - Document any deviations from the plan

5. **Performance Considerations**:
   - Implement efficient algorithms
   - Avoid unnecessary computations
   - Consider caching where appropriate

6. **Security Best Practices**:
   - Validate all inputs
   - Use parameterized queries
   - Follow principle of least privilege
   - Never log sensitive data

Create production-ready code that passes all tests and meets all requirements.

**Progressive Commit Strategy**:
1. **After each implementation phase**:
   ```bash
   # Check what changed
   git status
   
   # Create descriptive commit
   git add -A
   git commit -m "feat(#$ARGUMENTS): complete [phase name]
   
   - [List key changes]
   - [Note any important decisions]"
   ```

2. **For work-in-progress saves**:
   ```bash
   # When stopping mid-phase
   git add -A
   git commit -m "WIP(#$ARGUMENTS): [current progress description]"
   ```

3. **Before risky operations**:
   ```bash
   # Create safety checkpoint
   git stash push -m "Safety checkpoint before [operation]"
   # or
   git commit -m "checkpoint(#$ARGUMENTS): before [risky operation]"
   ```

**Safety Measures**:
- **Auto-save uncommitted work**: Stash changes before switching contexts
- **Backup refs**: Create backup branches before major refactoring
- **Test continuously**: Run tests after each significant change
- **Incremental commits**: Never lose more than 30 minutes of work