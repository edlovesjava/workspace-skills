---
name: workspace-init
description: Initialize a branch-based workspace (Pattern 4) for a shared branch -- typically a JIRA id. Ensures each repo has a main clone under the root workspace, then creates a worktree per repo at <worktree_root>/<branch>/<repo> on a branch named after the JIRA id. Use when the user says "init workspace", "create worktrees for JIRA-123", "set up workspace for ABC-42", or similar.
---

# workspace-init

Bootstrap a **branch-based workspace** for a shared branch — the per-JIRA subdirectory of worktrees described in Pattern 3 / Pattern 4 of *Managing Claude Code Across Multiple Repositories*. The result is a tree of worktrees, one per repo, all on the same branch, ready for cross-repo work.

This implements the `workspace:init <jira-id>` skill from Pattern 4: "Create the root workspace, attach repositories, create or check out worktrees, fetch latest, and align branches."

## When to use

- "init workspace JIRA-123"
- "create worktrees for ABC-42"
- "set up a workspace for FOO-9 with these repos: …"
- Any request to bootstrap multi-repo work where the same branch needs to exist in several repos.

## Inputs

- `<branch>` (required, positional): branch / JIRA id, e.g. `JIRA-123`. Used as both the directory name under the worktree root and the git branch name in every repo.
- `--root=<git-url>` (optional): submodule mode. Clone this repo as the orchestration root and use its submodules as the repo list.
- `--repos=name=url[#branch],…` (optional): inline repo list. Overrides `REPOS` from `.workspace.conf`.
- `--workspace-dir=<path>` (optional): override the **root workspace** directory. Defaults to the nearest ancestor containing `.workspace.conf`, otherwise `$PWD`.
- `--worktree-root=<path>` (optional): override where branch-based workspaces live. Defaults to `<workspace_dir>/worktrees`. Set this equal to `<workspace_dir>` if you want branch dirs at the workspace root.

If neither `--root` nor `--repos` is passed, the skill reads `REPOS` from `.workspace.conf` in the root workspace directory.

## What it does

1. Loads `.workspace.conf` (if any) and applies CLI overrides.
2. For each repo:
   - Ensures a main clone exists at `<main_clones_dir>/<repo>` on its default branch (this is the per-repo "main branch attachment" referred to in Pattern 1).
   - Adds a worktree at `<worktree_root>/<branch>/<repo>`:
     - Reuses an existing local or remote branch named `<branch>` if present.
     - Otherwise creates a new branch from `origin/<default_branch>`.
3. Prints a summary so the user can see exactly what was created.

The branch-based workspace this produces matches the article's Pattern 3 layout:

```
<worktree_root>/
  └── <branch>/                   <-- the branch-based workspace
        ├── <repo-a>/
        ├── <repo-b>/
        └── …
```

## How to invoke

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/skills/workspace-init/init.sh" <branch> [flags…]
```

If `$CLAUDE_PROJECT_DIR` is not set, fall back to a path relative to the current workspace dir (the script lives at `.claude/skills/workspace-init/init.sh` in this repo).

## Examples

Manifest mode (uses `.workspace.conf`):

```bash
bash .claude/skills/workspace-init/init.sh JIRA-123
```

Submodule mode (no manifest needed):

```bash
bash .claude/skills/workspace-init/init.sh JIRA-123 \
  --root=https://github.com/example/orchestration.git
```

Inline repos:

```bash
bash .claude/skills/workspace-init/init.sh JIRA-123 \
  --repos=service-a=https://github.com/example/service-a.git#main,service-b=https://github.com/example/service-b.git#main
```

## After running

Tell the user the worktree paths and suggest `cd <worktree_root>/<branch>/<repo>` for the repo they want to start in. To align the new branch with upstream changes, follow up with `workspace-sync`. To get a single overview of the branch-based workspace, use `workspace-status`.
