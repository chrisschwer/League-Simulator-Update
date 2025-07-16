# Claude Code Development Workflow

This document describes a sophisticated development workflow using Claude Code with GitHub Projects for quality-controlled software development.

## Overview

This workflow implements a rigorous development process where Claude Code handles implementation while humans maintain quality control through strategic review points. The system uses an 11-column GitHub Projects board with automated progression and human approval gates.

## Workflow Columns

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

All commands are in `.claude/commands/`:

### Development Commands
- `/setup-environment` - Initialize project-specific Claude Code configuration
- `/newissue` - Create a comprehensive GitHub issue (supports features, bugs, enhancements, documentation)
- `/makeprogress` - Progress issue through workflow
- `/analyze` - Perform in-depth analysis
- `/writetest` - Write comprehensive tests
- `/plan` - Create implementation plan
- `/implement` - Implement approved plan
- `/review` - Review code quality
- `/createpr` - Create pull request

### Human Review Commands
- `/list_human_todo` - List all issues awaiting human review
- `/approve_issue` - Approve an issue for the next phase
- `/reject_issue` - Send an issue back with feedback

### Planning & Coordination
- `/meta-plan` - Analyze all issues for priority, dependencies, and optimal work order

## Human Approval Gates

The workflow includes three critical human review points:

1. **Test Approval**: Ensure test quality before implementation
2. **Plan Approval**: Validate approach before coding
3. **PR Approval**: Final quality check before merge

## Rejection Handling

If a human rejects at any approval gate:
- Issue moves back to previous step
- Claude addresses feedback
- Process repeats until approved

## Benefits

- **Quality Control**: Human oversight at critical points
- **Automation**: Claude handles time-consuming implementation
- **Consistency**: Standardized workflow for all features
- **Efficiency**: Parallel issue processing possible
- **Traceability**: Complete history in GitHub

## Getting Started

1. Initialize project setup: `/setup-environment`
2. Create an issue: `/newissue "Feature description"`
3. Progress through workflow: `/makeprogress 123`
4. Review and approve at gates
5. Merge when ready

**Note**: `/setup-environment` is a custom command for project-specific setup. Claude Code's built-in `/init` command remains available for its standard initialization functionality.

This workflow balances AI efficiency with human judgment for high-quality software development.