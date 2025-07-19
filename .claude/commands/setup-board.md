Create or configure a GitHub Projects board for the Claude Code Workflow visual tracking system.

## Overview

This command sets up a GitHub Projects board that provides visual representation of the 11-stage workflow, enabling teams to track issues through their entire lifecycle from creation to completion.

## What This Command Does

1. **Creates Projects Board**: Creates a "Claude Code Workflow" board with 11 columns representing workflow stages
2. **Configures Custom Fields**: Adds tracking fields for stage, priority, timestamps, and assignments
3. **Sets Up Automation**: Configures rules for automatic issue movement and status updates
4. **Validates Configuration**: Ensures the board is properly connected to the repository

## Prerequisites

Before running this command, ensure:
- You're in a GitHub repository
- GitHub CLI is installed and authenticated (`gh auth status`)
- You have admin permissions on the repository
- The repository has issues enabled

## Board Structure

The board will be created with these 11 columns representing the workflow stages:

1. **🆕 New Issues** - Issues awaiting triage and initial analysis
2. **📋 Requirements** - Requirements gathering and analysis phase
3. **🎨 Design** - Technical design and architecture planning
4. **📝 Planning** - Implementation planning and task breakdown
5. **💻 Development** - Active development and coding
6. **👀 Review** - Code review and quality assurance
7. **🧪 Testing** - Testing and validation phase
8. **✅ Validation** - Pre-production validation and approval
9. **🚀 Deployment** - Production deployment and rollout
10. **📊 Monitoring** - Post-deployment monitoring and observation
11. **✅ Complete** - Completed and retrospective

## Custom Fields Configuration

The board will include these custom fields for enhanced tracking:

- **Stage**: Single-select field matching the 11 workflow stages
- **Priority**: Single-select field with P0-Critical, P1-High, P2-Medium, P3-Low options
- **Stage Entry Time**: Date field to track when issues enter each stage
- **Assigned Developer**: Person field for development assignments
- **Review Status**: Single-select field for review gate tracking

## Automation Rules

The command will configure automation rules for:

- **Auto-add Issues**: New issues automatically added to "New Issues" column
- **Label Synchronization**: Priority labels sync with Priority field
- **Status Updates**: Issue status updates when moved between columns
- **Notifications**: Team notifications for stage transitions

## Usage

Simply run the command to create and configure the board:

```
/setup-board
```

## Board Management

After creation, you can:

1. **View the Board**: Navigate to your repository → Projects → "Claude Code Workflow"
2. **Move Issues**: Drag and drop issues between columns as they progress
3. **Filter Issues**: Use built-in filtering by priority, assignee, or labels
4. **Track Progress**: Monitor cycle time and identify bottlenecks
5. **Generate Reports**: Export data for team metrics and analysis

## Integration with Existing Commands

The board integrates seamlessly with existing workflow commands:

- `/newissue` - New issues automatically appear in "New Issues" column
- `/makeprogress` - Moving issues updates board position
- `/review` - Updates review status and moves to appropriate column
- `/createpr` - Transitions issues to deployment tracking

## Troubleshooting

If board creation fails:

1. **Check Permissions**: Ensure you have admin access to the repository
2. **Verify Authentication**: Run `gh auth status` to confirm GitHub CLI access
3. **Repository Status**: Confirm you're in a valid GitHub repository
4. **API Limits**: GitHub Projects API has rate limits; retry if needed

## Board Access

The board is created as **public** by default, meaning:
- Repository collaborators can view and edit
- Public repositories: board is visible to all
- Private repositories: board follows repository visibility rules

## Success Indicators

You'll know the setup succeeded when:
- ✅ Board appears in your repository's Projects tab
- ✅ All 11 workflow columns are present
- ✅ Custom fields are configured
- ✅ Automation rules are active
- ✅ Existing issues are automatically added

## Next Steps

After board creation:
1. Review the board layout and customize if needed
2. Train team members on board usage
3. Start moving existing issues to appropriate columns
4. Monitor board metrics for workflow optimization
5. Use filtering and sorting to manage large issue backlogs

The board provides a powerful visual interface for managing the sophisticated 11-stage workflow, making it easier for teams to track progress, identify bottlenecks, and communicate status to stakeholders.