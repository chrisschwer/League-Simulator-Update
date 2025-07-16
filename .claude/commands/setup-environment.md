# Setup Environment Command
# This is a custom project setup command, distinct from Claude Code's built-in /init

Please initialize project-specific Claude Code configuration by:

## Step 1: Check for Existing GitHub Issues

First, check if there are existing GitHub issues in this repository:

```bash
gh issue list --limit 100 --state open --json number,title,labels,createdAt,body
```

If issues exist, ask the user:
"I found [X] existing open issues in this repository. Would you like me to integrate them into the quality-controlled workflow? This will:
- Analyze each issue to determine its type (feature/bug/enhancement/documentation)
- Add appropriate type labels
- Add 'status:new' label to enter them into the workflow
- Preserve all existing labels and information

Integrate existing issues? (yes/no)"

If user confirms, for each issue:
1. Analyze the title and body to determine issue type
2. Check existing labels to avoid duplicates
3. Apply appropriate labels:
   - Type label: `type:feature`, `type:bug`, `type:enhancement`, or `type:documentation`
   - Status label: `status:new` (to enter workflow)
   - Keep all existing labels
4. Add a comment: "Issue integrated into quality-controlled workflow"

## Step 2: Project Analysis and Setup

1. Analyzing the current project structure and technology stack
2. Creating a comprehensive project context file at `.claude/project_context.md`
3. Identifying key components, architecture patterns, and coding conventions
4. Setting up appropriate GitHub workflows if they don't exist
5. Creating a development workflow guide specific to this project
6. Documenting the testing approach and build commands

## Step 3: Workflow Integration

After setup, provide a summary:
- Number of existing issues integrated (if any)
- Key project characteristics identified
- Files created or updated
- Next steps for the user

Focus on understanding the project deeply so future Claude Code sessions have excellent context.