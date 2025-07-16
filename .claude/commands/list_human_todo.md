# List Human Review Tasks

Please list all GitHub issues that require human review, organized by approval gate and priority.

1. **Fetch all open issues** with status labels indicating they're at approval gates:
   - `status:tests_written` → Awaiting test approval
   - `status:plan_written` → Awaiting plan approval  
   - `status:pr_created` → Awaiting PR approval

2. **Group by approval phase**:
   - Test Approvals (earliest in workflow)
   - Plan Approvals (mid-workflow)
   - PR Approvals (final stage)

3. **Sort within each group** by:
   - Priority labels (critical → high → medium → low)
   - Age of issue (oldest first)

4. **Display format**:
   ```
   ## 🔍 Human Review Required

   ### Test Approvals
   - #123 [HIGH] Add user authentication (3 days old)
     Status: tests_written → Needs: tests:approved
   - #125 [MEDIUM] Update dashboard UI (1 day old)
     Status: tests_written → Needs: tests:approved

   ### Plan Approvals
   - #120 [CRITICAL] Fix security vulnerability (5 hours old)
     Status: plan_written → Needs: plan:approved

   ### PR Approvals
   - #118 [LOW] Refactor utility functions (2 days old)
     Status: pr_created → Needs: PR merge

   Total: 4 items awaiting review
   ```

5. **Include helpful commands** for each item:
   - Quick approve: `/approve_issue [number]`
   - Review details: `gh issue view [number]`
   - Request changes: `/reject_issue [number] "feedback"`

Focus on making it easy for humans to see what needs their attention and take action quickly.