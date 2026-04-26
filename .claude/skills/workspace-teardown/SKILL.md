---
name: workspace-teardown
description: Tear down a branch-based workspace (Pattern 4) once a JIRA branch is merged or abandoned. Refuses to remove worktrees with uncommitted or unpushed work unless --force is given. Use when the user says "teardown workspace", "clean up JIRA-123 worktrees", "remove the workspace for ABC-42", or similar.
---

# workspace-teardown

Remove every worktree in a branch-based workspace and delete the per-branch directory under the worktree root. Main clones in the root workspace are left intact.

This implements the `workspace:teardown <jira-id>` skill from Pattern 4 of *Managing Claude Code Across Multiple Repositories*: "Clean up worktrees and temporary workspace structure once the work is complete."

## When to use

- "teardown workspace JIRA-123"
- "remove the worktrees for ABC-42"
- "the PR merged, clean up FOO-9"

## Inputs

- `<branch>` (required, positional): the workspace key.
- `--force` (optional): proceed even if some worktree has uncommitted changes or unpushed commits.
- `--root=…` / `--repos=…` / `--workspace-dir=…` / `--worktree-root=…` — same as `workspace-init`.

## What it does

1. For each repo's worktree under `<worktree_root>/<branch>/<repo>`:
   - Verifies it is clean: no `git status` changes, no commits ahead of upstream.
   - If anything is dirty/unpushed and `--force` is not set, aborts before removing anything.
2. Calls `git worktree remove --force <path>` for each repo (the `--force` here just bypasses the lock-file check; cleanliness is enforced by step 1).
3. Removes the empty `<worktree_root>/<branch>` directory.
4. Leaves main clones in `<main_clones_dir>` untouched.

## Safety

The skill is **non-destructive by default**. If any repo would lose work, nothing is removed. The user must explicitly opt into `--force` to discard local-only commits or uncommitted edits.

Branches in the main clones are not deleted automatically — local branches in `.main/<repo>` may still reference the JIRA branch. The skill prints a hint at the end so the user can prune if they want.

## How to invoke

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/skills/workspace-teardown/teardown.sh" <branch> [--force] [other flags…]
```

## Examples

```bash
bash .claude/skills/workspace-teardown/teardown.sh JIRA-123
bash .claude/skills/workspace-teardown/teardown.sh JIRA-123 --force
```
