---
name: status
description: Summarise the state of every repo in a branch-based virtual-monorepo workspace -- current branch, dirty files, ahead/behind upstream, distance from the default branch, and last commit. Use when the user says "status of workspace", "where is JIRA-123", "what's the state across the repos", or wants a single overview of a multi-repo workspace.
---

# virtual-monorepo:status

Print a per-repo summary for a branch-based workspace (the directory created by `virtual-monorepo:init` at `<worktree_root>/<branch>/`). One block per repo, designed to fit on a screen and answer "where am I across the system?".

This is the `virtual-monorepo:status <jira-id>` skill from Pattern 4 of the *Managing Claude Code Across Multiple Repositories* article.

## When to use

- "status of JIRA-123"
- "what's the state of the workspace?"
- "show me ahead/behind across all the repos"
- Whenever the user wants one-shot situational awareness of a multi-repo branch.

## Inputs

- `<branch>` (required, positional): the workspace key.
- `--root=…` / `--repos=…` / `--workspace-dir=…` / `--worktree-root=…` — same as the other workspace skills.

## What it reports per repo

- worktree path
- current branch
- dirty file count (or "clean")
- upstream tracking branch + ahead/behind counts
- distance from `origin/<default_branch>` (the rebase target)
- last commit (short SHA + subject)

It does **not** call out to GitHub or CI yet — those are obvious extensions but kept out of scope here so the skill works offline.

## How to invoke

```bash
bash "$CLAUDE_PROJECT_DIR/skills/status/status.sh" <branch> [flags…]
```

## Example

```bash
bash skills/status/status.sh JIRA-123
```

Sample output:

```
=== service-a ===
  worktree : /workspace/worktrees/JIRA-123/service-a
  branch   : JIRA-123
  dirty    : 2 uncommitted file(s)
  upstream : origin/JIRA-123 (ahead 1, behind 0)
  vs main  : ahead 3, behind 0
  last     : 7c7b4b3 add display_name column
```
