# Claude Code Development Workflow

This file provides guidance to Claude Code when working with this project using the sophisticated GitHub Projects workflow for quality-controlled software development.

## Overview

This workflow implements a rigorous development process with 11 workflow stages and 3 human approval gates. Claude Code handles all implementation details while humans maintain quality control at strategic checkpoints.

## Workflow Stages

The system uses an 11-column GitHub Projects board:

### 1. **new**
- Fresh issues created via `/newissue` command
- Awaiting initial analysis
- No work started yet

### 2. **in_depth_analysis**
- Claude performs comprehensive requirement analysis
- Researches codebase for similar patterns
- Identifies risks and dependencies
- **Output**: Detailed technical analysis comment

### 3. **tests_written**
- Comprehensive test suite created
- Includes unit, integration, and edge cases
- Following TDD principles
- **Output**: Complete test specifications

### 4. **tests_approved** ✅
- **HUMAN APPROVAL GATE**
- Review test coverage and quality
- Ensure all scenarios covered
- Approve or request modifications

### 5. **plan_written**
- Detailed implementation plan created
- Phased approach with time estimates
- File changes mapped out
- **Output**: Step-by-step implementation guide

### 6. **plan_approved** ✅
- **HUMAN APPROVAL GATE**
- Review technical approach
- Validate architecture decisions
- Approve or suggest changes

### 7. **implementation**
- Code being written following approved plan
- All tests should pass
- Following project standards
- **Output**: Working implementation

### 8. **tested**
- All tests passing
- Coverage requirements met
- Performance validated
- **Output**: Test results summary

### 9. **linting**
- Code quality checks passed
- Style guidelines followed
- No security issues
- **Output**: Linting report

### 10. **pr_created**
- Pull request generated
- Comprehensive description
- Ready for final review
- **Output**: PR link

### 11. **fixed** (pr_approved) ✅
- **HUMAN APPROVAL GATE**
- Final code review
- PR approved and merged
- Issue closed

## Available Commands

All workflow commands are Markdown files in `.claude/commands/`:

### Core Workflow Progression
- `/newissue "description"` - Create GitHub issue with comprehensive PRD
- `/makeprogress [issue_number]` - Progress issue through workflow stages

### Development Stage Commands
- `/analyze` - In-depth technical analysis
- `/writetest` - Generate comprehensive test suite
- `/plan` - Create implementation plan
- `/implement` - Write production code
- `/review` - Code quality review
- `/createpr` - Generate pull request

### Human Review Commands
- `/list_human_todo` - List issues awaiting human review
- `/approve_issue [number]` - Approve with confirmation
- `/reject_issue [number] "feedback"` - Reject with enhanced feedback

### Planning & Coordination
- `/meta-plan` - Analyze all issues for priority, dependencies, and optimal work order
- `/eod` - End-of-day cleanup with progress summary, documentation updates, and atomic commits

## Key Design Principles

### Automation with Human Oversight
- Claude Code handles all implementation details
- Humans review at strategic checkpoints only
- Rejection at any gate moves issue back one stage

### Command Structure
- Each command is a simple Markdown prompt file
- Commands use `$ARGUMENTS` placeholder for parameters
- Located in `.claude/commands/` directory

### Workflow Progression
- `/makeprogress` intelligently determines next action based on current status
- Automatic progression through non-gate stages
- Stops and waits at human approval gates

## Critical Implementation Details

### Label Management
- Issues use status labels matching column names (e.g., `status:tests_written`)
- Approval adds specific labels: `tests:approved`, `plan:approved`
- Labels drive workflow progression logic

### Priority Labels
All issues should be assigned one priority label:
- **P0-Critical**: System down, data loss risk, or security vulnerability (immediate action required)
- **P1-High**: Major functionality broken, significant user impact (sprint commitment)
- **P2-Medium**: Important features or bugs affecting subset of users (plan for upcoming sprints)
- **P3-Low**: Nice-to-have improvements, minor issues (backlog)

## GitHub Projects Board Integration

The workflow includes a **"Claude Code Workflow"** Projects board that provides visual tracking of issues through all 11 stages:

### Board Structure
- **🆕 New Issues**: Fresh issues awaiting triage and initial analysis
- **📋 Requirements**: In-depth analysis and requirement gathering
- **🎨 Design**: Technical design and test specification
- **📝 Planning**: Implementation planning and architecture
- **💻 Development**: Active development and coding
- **👀 Review**: Code review and quality assurance
- **🧪 Testing**: Testing and validation phase
- **✅ Validation**: Pre-production validation and PR review
- **🚀 Deployment**: Production deployment and rollout
- **📊 Monitoring**: Post-deployment monitoring and verification
- **🎉 Complete**: Completed issues and retrospective

### Automatic Synchronization
The board automatically stays in sync with the workflow:
- **Issue Creation**: New issues via `/newissue` are automatically added to "🆕 New Issues"
- **Progress Tracking**: `/makeprogress` moves issues through appropriate stages
- **Label Integration**: Priority labels sync with the board's Priority field
- **Timestamp Tracking**: Stage Entry Time field tracks when issues enter each stage
- **Status Consistency**: Board status remains consistent with issue labels

### Custom Fields
The board includes enhanced tracking fields:
- **Status**: The 11-stage workflow progression (creates the board columns)
- **Priority**: P0-Critical, P1-High, P2-Medium, P3-Low (synced with labels)
- **Stage Entry Time**: Date when issue entered current stage
- **Cycle Time**: Total time spent in workflow (automatically calculated)

### Board Commands
- **Setup**: `/setup-board` - Create and configure the board manually
- **View**: Access via GitHub repository → Projects tab → "Claude Code Workflow"
- **Automation**: Built-in scripts handle all board updates automatically

### Board Benefits
- **Visual Progress**: See all issues and their workflow stage at a glance
- **Bottleneck Detection**: Identify stages where issues accumulate
- **Team Coordination**: Enhanced visibility for distributed teams
- **Stakeholder Communication**: Easy status updates for non-technical stakeholders
- **Performance Metrics**: Track cycle times and workflow efficiency
- **Parallel Development**: Visualize multiple concurrent work streams

### Rejection Handling
- `/reject_issue` includes feedback enhancement
- Analyzes issue and feedback to ensure actionable guidance
- Provides "send now" option or helps clarify feedback

### Human Review Helper Integration
- Shell aliases for quick access: `cht`, `cap`, `crj`
- Confirmation prompts prevent accidental approvals
- Enhanced feedback system for rejections

## Important Workflow Behaviors

1. **Issue Creation**: Always use `/newissue` to ensure proper structure and labels
   - Command asks clarifying questions for complete issues
   - Supports features, bugs, enhancements, documentation
   - Applies appropriate type label while keeping status:new

2. **Progression**: Use `/makeprogress` exclusively - it handles all stage transitions

3. **Approvals**: Must add exact labels (`tests:approved`, `plan:approved`) for progression

4. **Rejections**: Always provide specific, actionable feedback when rejecting

5. **Commands**: Are project-agnostic - copy `.claude/` directory to any project

6. **Commits**: Progressive commit strategy with worktree isolation
   - Each issue gets its own worktree and feature branch
   - Progressive commits during implementation phases
   - Format: `type(#issue): description`
   - WIP commits allowed: `WIP(#issue): current progress`
   - EOD command handles atomic commits and cleanup

## Common GitHub Commands

### Approve at gates
```bash
gh issue edit [number] --add-label "tests:approved"
gh issue edit [number] --add-label "plan:approved"
gh pr review [number] --approve
```

### Check issue status
```bash
gh issue view [number]
```

### Review and comment
```bash
gh issue comment [number] --body "Feedback here"
gh pr comment [number] --body "Review comments"
```

## Worktree-Based Development

## Overview

This workflow uses Git worktrees to enable parallel development on multiple issues:

- **Isolation**: Each issue gets its own working directory
- **Parallel Work**: Run multiple Claude Code sessions simultaneously
- **Safety**: Main branch remains protected from accidental changes
- **Progressive Commits**: Save work frequently without polluting history

## Worktree Commands

### Create worktree for an issue
```bash
# Automatic: happens when reaching implementation phase
/makeprogress 123  # Creates worktree if needed

# Manual: create worktree directly
cwn 123  # Alias for claude_worktree_create
```

### Manage multiple issues
```bash
/parallel 123 456 789  # Create worktrees for multiple issues
cpar                   # Alias for parallel command
```

### Check worktree status
```bash
cws  # Show all active worktrees
/parallel  # Show detailed dashboard
```

### Cleanup completed work
```bash
cwc  # Cleanup merged worktrees
/eod  # Includes worktree cleanup options
```

## Shell Aliases

These aliases are automatically added by the setup script:

```bash
# Development workflow
alias cni="claude /newissue"
alias cmp="claude /makeprogress"

# Human review
alias cht="claude /list_human_todo"
alias cap="claude /approve_issue"
alias crj="claude /reject_issue"

# Planning
alias cplan="claude /meta-plan"
alias ceod="claude /eod"

# Parallel development
alias cpar="claude /parallel"

# Worktree management
alias cws="claude_worktree_status"
alias cwc="claude_worktree_cleanup"
alias cwn="claude_worktree_create"
```

## Getting Started with This Workflow

1. **Initialize project setup**: Claude's `/init` command handles project initialization
   - Creates project-specific memory and configuration
   - Sets up GitHub integration via setup script

2. **Create your first issue**: `/newissue "Feature description"`
   - Claude will ask clarifying questions
   - Creates properly structured GitHub issue

3. **Progress through workflow**: `/makeprogress 123`
   - Claude handles each stage automatically
   - Creates worktree when reaching implementation
   - Makes progressive commits during development
   - Stops at approval gates for human review

4. **Review and approve at gates**
   - Check `/list_human_todo` for pending reviews
   - Use GitHub labels or `/approve_issue` command

5. **Merge when ready**
   - Final PR approval completes the cycle

## Benefits

- **Quality Control**: Human oversight at critical points
- **Automation**: Claude handles time-consuming implementation
- **Consistency**: Standardized workflow for all features
- **Efficiency**: True parallel development with worktrees
- **Safety**: Work isolation prevents conflicts
- **Recovery**: Progressive commits prevent work loss
- **Traceability**: Complete history in GitHub

## Workflow Philosophy

This setup maximizes Claude Code's capabilities while maintaining human quality control. It's designed for teams that want:
- Consistent, high-quality development process
- Efficient use of AI for implementation
- Strategic human oversight without micromanagement
- Complete traceability through GitHub

**Note**: This workflow integrates with Claude Code's built-in `/init` command for project initialization. The setup script enhances the generated project memory with workflow-specific guidance.

## Troubleshooting Worktrees

### Common Issues

1. **"fatal: branch already exists"**
   ```bash
   # Fetch and checkout existing branch
   git fetch origin
   git worktree add ../project-issue-123 origin/feature/issue-123
   ```

2. **Worktree path already exists**
   ```bash
   # Remove old worktree
   git worktree remove ../project-issue-123
   # Or force removal
   git worktree remove --force ../project-issue-123
   ```

3. **Too many worktrees warning**
   ```bash
   # List all worktrees
   git worktree list
   # Remove completed ones
   cwc  # Cleanup merged worktrees
   ```

4. **Uncommitted changes in worktree**
   ```bash
   # Stash changes before switching
   git stash push -m "WIP: issue description"
   # Or commit as WIP
   git commit -am "WIP(#123): current progress"
   ```

### Recovery Commands

- **Repair corrupted worktree**: `git worktree repair`
- **Find lost commits**: `git reflog`
- **Restore deleted worktree**: Check `.git/worktrees/` for metadata

## Best Practices

1. **One worktree per issue**: Maintains clean separation
2. **Regular commits**: Use progressive commits during development
3. **Clean up regularly**: Remove worktrees after PR merge
4. **Stay under 5 worktrees**: Prevents resource issues
5. **Use descriptive commits**: Even for WIP saves