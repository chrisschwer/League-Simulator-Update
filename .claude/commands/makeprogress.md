Progress issue #$ARGUMENTS through the development workflow based on its current status.

Check the issue's current status label and perform the appropriate next action:

**If status:new → Perform in-depth analysis:**
- Research similar implementations in the codebase
- Identify affected components and dependencies
- Analyze potential risks and edge cases
- Create detailed technical analysis
- Add findings as issue comment
- Update label to status:in_depth_analysis

**If status:in_depth_analysis → Write comprehensive tests:**
- Create test specifications covering all acceptance criteria
- Include unit tests, integration tests, and edge cases
- Write tests following TDD principles
- Ensure tests would catch potential regressions
- Add test suite as issue comment
- Update label to status:tests_written

**If status:tests_approved → Create implementation plan:**
- Break down implementation into clear phases
- Identify files to be created/modified
- Plan data flow and architecture changes
- Include rollback strategy
- Estimate time for each phase
- Add plan as issue comment
- Update label to status:plan_written

**If status:plan_approved → Implement the feature:**
- Follow the approved implementation plan
- Write clean, well-documented code
- Implement error handling and logging
- Ensure all tests pass
- Update label to status:implementation

**If status:implementation → Run tests and quality checks:**
- Execute all test suites
- Run linting and type checking
- Verify performance requirements
- Check security considerations
- Update label to status:tested

**If status:tested → Run final quality checks:**
- Execute linting tools
- Check code formatting
- Verify documentation completeness
- Update label to status:linting

**If status:linting → Create pull request:**
- Generate comprehensive PR description
- Include test results and coverage
- List all changes made
- Reference the issue
- Update label to status:pr_created

For any other status, provide guidance on next steps.