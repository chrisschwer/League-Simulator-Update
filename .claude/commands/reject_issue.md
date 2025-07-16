# Reject Issue with Enhanced Feedback

For issue #$ARGUMENTS, provide constructive feedback for revision:

1. **Parse arguments** to separate issue number and initial feedback:
   - First argument: Issue number
   - Remaining arguments: Feedback message

2. **Fetch and analyze issue**:
   - Get issue details, current status, and recent comments
   - Identify what's being reviewed (tests, plan, or PR)
   - Show a summary of what Claude Code submitted

3. **Display issue analysis**:
   ```
   📋 Issue Analysis
   
   Issue #[number]: [title]
   Current Phase: [phase] (awaiting [approval type])
   
   What was submitted:
   [Summary of tests/plan/implementation]
   
   Your feedback: "[initial feedback]"
   ```

4. **Evaluate feedback quality**:
   - Check if feedback is specific and actionable
   - Identify vague statements like "needs work", "not good enough", "try again"
   - Look for missing specifics about WHAT needs to change and HOW

5. **If feedback needs clarification**, provide guided prompts:
   ```
   🤔 Making Feedback More Actionable
   
   Your feedback seems general. Claude Code works best with specific guidance.
   
   For the [tests/plan/implementation] submitted, please clarify:
   
   📝 What specific issues did you find?
   - [ ] Missing test cases (which scenarios?)
   - [ ] Wrong approach (what would be better?)
   - [ ] Incomplete coverage (what's missing?)
   - [ ] Security concerns (which ones?)
   - [ ] Performance issues (where?)
   
   💡 Suggested enhanced feedback:
   "The tests are missing edge cases for [X]. Please add:
   - Test for concurrent user access
   - Error handling when database is unavailable
   - Validation for malformed input [specific example]"
   
   Options:
   1. Type your enhanced feedback
   2. Type "send now" to send original feedback as-is
   ```

6. **Process user response**:
   - If "send now": Use original feedback
   - If enhanced feedback provided: Use the improved version
   - Combine initial + enhanced feedback if both valuable

7. **Determine rollback** based on current status:
   - `status:tests_written` → `status:in_depth_analysis`
   - `status:plan_written` → `status:tests_approved`
   - `status:pr_created` → `status:linting`

8. **Execute rejection** with enhanced feedback:
   ```bash
   # Update labels
   gh issue edit [number] --remove-label "status:[current]" --add-label "status:[previous]"
   
   # Post comprehensive feedback
   gh issue comment [number] --body "❌ Changes Requested

   **Phase:** [Current Phase] → [Previous Phase]
   
   **What was reviewed:**
   [Brief summary of submitted work]
   
   **Specific changes needed:**
   [Enhanced feedback with clear action items]
   
   **Next steps:**
   1. Address each point above
   2. Run \`/makeprogress [number]\` when complete
   
   💡 Tip: Focus on [most critical issue] first.
   
   ---
   *Human review at $(date)*"
   ```

9. **Add helpful context**:
   - Add label `needs:revision`
   - If this is 2nd+ rejection, add `multiple:rejections` label
   - Track common rejection patterns

10. **Confirmation with tips**:
    ```
    ✅ Feedback Sent
    
    Issue #[number] returned to: [previous phase]
    
    Your feedback has been posted with:
    ✓ Specific action items
    ✓ Clear next steps
    ✓ Context about what was reviewed
    
    Claude Code will address your feedback and resubmit.
    Track progress with: /list_human_todo
    ```

11. **Error handling**:
    - If no feedback: "Please provide feedback: `/reject_issue [number] \"your feedback\"`"
    - If not at approval gate: "Issue #[number] is not awaiting approval"
    - If issue not found: "Issue #[number] not found"

The goal is to make rejections constructive and efficient, helping Claude Code understand exactly what needs improvement.