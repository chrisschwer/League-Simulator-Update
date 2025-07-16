# Approve Issue for Next Phase

For issue #$ARGUMENTS, please:

1. **Fetch issue details**:
   - Get title, current status, and labels
   - Identify which approval gate it's at

2. **Determine next phase**:
   - If `status:tests_written` → Add `tests:approved` label
   - If `status:plan_written` → Add `plan:approved` label
   - If `status:pr_created` → This needs PR merge, not label approval

3. **Confirm with user**:
   ```
   ✅ Approval Confirmation
   
   Issue #$ARGUMENTS: [Title]
   Current phase: tests_written
   Next phase: tests_approved
   
   Do you want to approve this issue for the next phase?
   This will add the label "tests:approved" and allow development to proceed.
   
   Type 'yes' to confirm or 'no' to cancel:
   ```

4. **If confirmed (yes)**:
   - Add the appropriate approval label
   - Add a comment: "✅ Approved for [next phase] by human review"
   - Run `/makeprogress $ARGUMENTS` to advance the workflow
   - Display: "Issue #$ARGUMENTS approved and progressing to next phase"

5. **If cancelled (no)**:
   - Display: "Approval cancelled. Issue remains in current phase."
   - Suggest: "Use `/reject_issue $ARGUMENTS \"feedback\"` to request changes"

6. **Error handling**:
   - If issue not found: "Issue #$ARGUMENTS not found"
   - If not at approval gate: "Issue #$ARGUMENTS is not awaiting approval (current status: [status])"
   - If already approved: "Issue #$ARGUMENTS has already been approved"

Make the approval process safe with clear confirmation to prevent accidental approvals.