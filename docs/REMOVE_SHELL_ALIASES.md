# Shell aliases to remove

The retired `.claude/` workflow installed a set of zsh aliases (per the now-deleted `.claude/workflow.md`). They are still in your shell rc and now point to commands that no longer exist.

## What to remove

Look for these in `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.bashrc`, or any sourced file:

### Aliases (11)

```sh
alias cni="claude /newissue"
alias cmp="claude /makeprogress"
alias cht="claude /list_human_todo"
alias cap="claude /approve_issue"
alias crj="claude /reject_issue"
alias cplan="claude /meta-plan"
alias ceod="claude /eod"
alias cpar="claude /parallel"
alias cws="claude_worktree_status"
alias cwc="claude_worktree_cleanup"
alias cwn="claude_worktree_create"
```

### Functions (typically named, defined in the same file)

- `claude_worktree_create`
- `claude_worktree_status`
- `claude_worktree_cleanup`

### Setup-script artifact

If a previous setup ran a `claude-code-setup` install script, look in:
- `~/.claude-code-setup/` (if the directory exists, review and remove)
- Any sourced shell-rc snippet referencing `claude-code-setup`

## How to find them

```bash
grep -nE "claude_worktree|claude /(newissue|makeprogress|list_human_todo|approve_issue|reject_issue|meta-plan|eod|parallel)|alias c(ni|mp|ht|ap|rj|plan|eod|par|ws|wc|wn)=" ~/.zshrc ~/.zshenv ~/.zprofile ~/.bashrc 2>/dev/null
```

## How to remove them

Edit each rc file by hand, delete the matching lines, save, then `source ~/.zshrc` (or open a new shell) to confirm the aliases are gone:

```bash
type cni 2>&1
# expected: "cni not found"
```

## Why this is a manual step

The repo can't safely edit your shell rc — too many ways to corrupt a profile. This doc is the checklist; the edit is yours.

## Related

- Issue #75 — the removal of the in-repo workflow tooling these aliases were paired with.
- The result record at `docs/superpowers/plans/2026-05-02-prune-local-claude-tooling-RESULT.md` lists everything else that was removed.
