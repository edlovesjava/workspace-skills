---
name: workspace-sync
description: Sync a branch-based workspace (Pattern 4) by fetching origin and rebasing the shared branch onto each repo's default branch, plus refreshing submodules in submodule mode. Use when the user says "sync workspace", "rebase JIRA-123 against main", "update worktrees", or wants to pull upstream changes into a multi-repo branch.
---

# workspace-sync

Bring every worktree in a branch-based workspace up to date by rebasing its branch onto the latest upstream default branch, and (in submodule mode) refresh submodule pointers in the root workspace.

This implements the `workspace:sync <jira-id>` skill from Pattern 4 of *Managing Claude Code Across Multiple Repositories*: "Rebase or merge latest changes, refresh submodules or directory mappings, and validate that the workspace is still coherent."

## When to use

- "sync workspace JIRA-123"
- "rebase ABC-42 onto main everywhere"
- "pull upstream changes into the worktrees"
- After someone merges into `main` and the user wants their multi-repo branch caught up.

## Inputs

- `<branch>` (required, positional): branch / JIRA id used as the workspace key.
- `--root=<git-url>` / `--repos=…` / `--workspace-dir=…` / `--worktree-root=…` — same as `workspace-init`.

## What it does

1. **Submodule-mode only:** if the workspace has a `ROOT_REPO`, pull the root repo (fast-forward) and re-run `git submodule update --init --recursive --remote` so the manifest reflects upstream submodule changes. New submodules will only be picked up by a follow-up `workspace-init`; sync logs a hint if it sees any.
2. For each repo in the branch-based workspace:
   - `git fetch origin` inside the worktree.
   - `git rebase origin/<default_branch>` on the shared branch.
3. If a rebase conflicts, stops there with a clear message — the user must resolve and re-run.

This is the multi-repo equivalent of `git pull --rebase` against the upstream main branch, plus the "refresh submodules or directory mappings" step from Pattern 4 of the article.

## How to invoke

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/skills/workspace-sync/sync.sh" <branch> [flags…]
```

## Examples

```bash
bash .claude/skills/workspace-sync/sync.sh JIRA-123
bash .claude/skills/workspace-sync/sync.sh JIRA-123 --root=https://github.com/example/orchestration.git
```

## Behaviour on conflict

The script aborts at the first conflicting repo and surfaces the path. The user resolves there with normal git tools (`git rebase --continue` / `--abort`), then re-runs `workspace-sync` to pick up the rest. Already-synced repos are idempotent — running again is safe.
