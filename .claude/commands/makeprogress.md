Progress issue #$ARGUMENTS through the development workflow based on its current status.

**Projects Board Integration:**
- Automatically update the GitHub Projects board to reflect issue progress
- Sync issue position through the 11-stage workflow visualization
- Update stage entry timestamps and cycle time tracking
- Maintain consistency between labels and board status

**Worktree Management:**
- Check if we're in a worktree using `git rev-parse --show-toplevel` and `git worktree list`
- For implementation phases (status:plan_approved), create a dedicated worktree:
  ```bash
  git worktree add ../claude-code-setup-issue-$ARGUMENTS -b feature/issue-$ARGUMENTS-description
  ```
- Navigate to the worktree automatically and continue work there
- Ensure all subsequent work happens in the isolated worktree

**First, ensure issue is on the Projects board:**
- If issue is not already on the board, add it to "🆕 New Issues" stage
- Sync priority labels with board Priority field
- Update stage entry timestamp

Check the issue's current status label and perform the appropriate next action:

**If status:new → Perform in-depth analysis:**
- Research similar implementations in the codebase
- Identify affected components and dependencies
- Analyze potential risks and edge cases
- Create detailed technical analysis
- Add findings as issue comment
- Create progress commit: `git commit -m "docs(#$ARGUMENTS): complete technical analysis"`
- Update label to status:in_depth_analysis
- **Board Update:** Move issue to "📋 Requirements" stage

**If status:in_depth_analysis → Write comprehensive tests:**
- Create test specifications covering all acceptance criteria
- Include unit tests, integration tests, and edge cases
- Write tests following TDD principles
- Ensure tests would catch potential regressions
- Add test suite as issue comment
- Create progress commit: `git commit -m "test(#$ARGUMENTS): add comprehensive test suite"`
- Update label to status:tests_written
- **Board Update:** Move issue to "🎨 Design" stage

**If status:tests_approved → Create implementation plan:**
- Break down implementation into clear phases
- Identify files to be created/modified
- Plan data flow and architecture changes
- Include rollback strategy
- Estimate time for each phase
- Add plan as issue comment
- Create progress commit: `git commit -m "docs(#$ARGUMENTS): create implementation plan"`
- Update label to status:plan_written
- **Board Update:** Move issue to "📝 Planning" stage

**If status:plan_approved → Implement the feature:**
- **Create dedicated worktree for implementation:**
  - Check if worktree exists: `git worktree list | grep "issue-$ARGUMENTS"`
  - If not, create: `git worktree add ../claude-code-setup-issue-$ARGUMENTS -b feature/issue-$ARGUMENTS`
  - Navigate to worktree: `cd ../claude-code-setup-issue-$ARGUMENTS`
- Follow the approved implementation plan
- Write clean, well-documented code
- **Create progress commits after each implementation phase:**
  - Phase completion: `git commit -m "feat(#$ARGUMENTS): implement [phase description]"`
  - WIP commits allowed: `git commit -m "WIP(#$ARGUMENTS): [current progress]"`
- Implement error handling and logging
- Ensure all tests pass
- Update label to status:implementation
- **Board Update:** Move issue to "💻 Development" stage

**If status:implementation → Run tests and quality checks:**
- Ensure you're in the issue worktree
- Execute all test suites
- Run linting and type checking
- Verify performance requirements
- Check security considerations
- Create commit for test results: `git commit -m "test(#$ARGUMENTS): verify all tests pass"`
- Update label to status:tested
- **Board Update:** Move issue to "🧪 Testing" stage

**If status:tested → Run final quality checks:**
- Execute linting tools
- Check code formatting
- Verify documentation completeness
- Update label to status:linting
- **Board Update:** Move issue to "👀 Review" stage

**If status:linting → Create pull request:**
- Ensure you're in the issue worktree
- Push worktree branch: `git push -u origin feature/issue-$ARGUMENTS`
- Generate comprehensive PR description
- Include test results and coverage
- List all changes made
- Reference the issue
- Use `gh pr create --base main --head feature/issue-$ARGUMENTS`
- Update label to status:pr_created
- **Board Update:** Move issue to "✅ Validation" stage

**If status:pr_approved → Deploy to production:**
- Execute deployment procedures
- Monitor deployment health
- Verify feature functionality in production
- Create deployment commit: `git commit -m "deploy(#$ARGUMENTS): release to production"`
- Update label to status:deployed
- **Board Update:** Move issue to "🚀 Deployment" stage

**If status:deployed → Monitor and complete:**
- Monitor production metrics
- Verify acceptance criteria are met
- Gather user feedback
- Create completion commit: `git commit -m "feat(#$ARGUMENTS): complete implementation"`
- Update label to status:complete
- **Board Update:** Move issue to "📊 Monitoring" stage

**If status:complete → Final retrospective:**
- Document lessons learned
- Update project documentation
- Clean up temporary resources
- Archive issue
- **Board Update:** Move issue to "🎉 Complete" stage

For any other status, provide guidance on next steps.

**Safety Checks & Edge Cases:**

1. **Worktree Conflict Detection:**
   - Before creating worktree, check if branch exists: `git branch -r | grep feature/issue-$ARGUMENTS`
   - If exists, fetch and checkout instead of creating new
   - Handle case where worktree path already exists

2. **Commit Safety:**
   - Always check for uncommitted changes before phase transitions
   - Create automatic stash if needed: `git stash push -m "Auto-stash for issue #$ARGUMENTS"`
   - Verify commits were successful before proceeding

3. **Recovery Helpers:**
   - If worktree is corrupted: `git worktree repair`
   - If branch diverged: offer to rebase or merge
   - Provide clear instructions for manual recovery if automation fails

4. **Resource Management:**
   - Check number of active worktrees: `git worktree list | wc -l`
   - Warn if >5 worktrees active (configurable limit)
   - Suggest cleanup of completed work: `git worktree remove`