---
name: workspace-exec
description: Run the same shell command in every repo's worktree of a multi-repo workspace, sequentially, with per-repo headers. Aggregates exit code so any repo failing fails the whole run. Use when the user says "run X across all repos", "exec ... in JIRA-123 worktrees", "build everything in the workspace", or wants to fan out a command across the workspace.
---

# workspace-exec

Run a shell command in every worktree of a workspace. Useful for cross-repo `git status`, build, lint, or any per-repo task.

## When to use

- "run `npm test` in every repo of JIRA-123"
- "show git status across the workspace"
- "exec `make lint` in the ABC-42 worktrees"
- Any time the user wants to fan a command out across all repos in a workspace.

## Inputs

- `<branch>` (required, positional): the workspace key.
- `--` (separator, required): everything after `--` is the command to run.
- `--root=…` / `--repos=…` / `--workspace-dir=…` / `--worktree-root=…` — same as `workspace-init`.

## What it does

For each repo:

1. `cd <worktree_root>/<branch>/<repo>`.
2. Print a header `=== <repo> ===`.
3. Run the command via `bash -c`.
4. Print a footer with the exit code.

Runs sequentially. Continues through all repos even if one fails, then exits non-zero if any failed. Output is interleaved with headers so the user can see which repo produced what.

## How to invoke

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/skills/workspace-exec/exec.sh" <branch> [flags…] -- <command>
```

## Examples

```bash
bash .claude/skills/workspace-exec/exec.sh JIRA-123 -- git status -s
bash .claude/skills/workspace-exec/exec.sh JIRA-123 -- make test
bash .claude/skills/workspace-exec/exec.sh JIRA-123 --root=https://… -- 'echo "hi from $(basename $PWD)"'
```

## Notes

- The command runs through `bash -c "$CMD"`, so shell features (pipes, variables, quoting) work — but quote carefully on the caller side.
- `$PWD` inside the command is the worktree directory.
