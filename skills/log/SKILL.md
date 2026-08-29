---
name: log
description: Show every commit across every repo in a virtual-monorepo workspace that carries the same Workspace-Change-Id trailer. Use when the user says "log of JIRA-123", "show commits for JIRA-123", "what changed for ABC-42 across all repos", or wants a unified cross-repo view of a workspace branch's history.
---

# virtual-monorepo:log

Query every repo's history for commits stamped with `Workspace-Change-Id: <branch>` and present them as one chronological view. This turns a cross-repo change from oral tradition into a first-class queryable object.

## When to use

- "log of JIRA-123"
- "show commits for JIRA-123"
- "what did we change for ABC-42?"
- "list every commit for FOO-9 across all repos"
- Any time the user wants the unified view of a multi-repo change.

Works **after** the relevant commits have been made in worktrees that were initialised by `virtual-monorepo:init`. Init installs a `prepare-commit-msg` hook in each main clone that stamps the trailer automatically — the user never has to type it.

## Inputs

- `<branch>` (required, positional): the workspace branch / JIRA id, e.g. `JIRA-123`. Matched literally against the trailer value.
- Standard config-override flags (`--workspace-dir`, `--repos`, `--root`, `--worktree-root`) — same as every other virtual-monorepo skill.

## What it does

1. Loads config + applies overrides as usual.
2. For each repo's main clone, runs:
   ```
   git log --all --grep="^Workspace-Change-Id: <branch>$" --format=…
   ```
   `--all` means it finds commits even if the workspace branch has been deleted, merged, or rewritten — as long as the commits are still reachable from any ref.
3. Sorts the combined results by author date and prints one line per commit, grouped by repo.

## How to invoke

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/log/log.sh" <branch> [flags…]
```

If `$CLAUDE_PLUGIN_ROOT` is not set (running directly from a checkout), fall back to the path `skills/log/log.sh` relative to the repo root.

## Example output

```
[workspace] log of Workspace-Change-Id: JIRA-123

=== service-shared-lib ===
  2026-05-16 10:14  9a3c4d2  Add SsoToken type for SSO login flow

=== service-a ===
  2026-05-16 10:31  4e7f1a8  Add /auth/sso endpoint
  2026-05-16 11:02  c2b9d56  Wire up SsoToken validation in /auth/sso

=== service-b ===
  2026-05-16 14:48  7d1ee20  Handle SsoLoggedIn event

[workspace] 4 commit(s) across 3 repos
```

## After running

- For a deeper view, suggest re-running with `--all --patch` against an individual repo's main clone:
  `git -C .main/service-a log --all --grep="^Workspace-Change-Id: JIRA-123$" --patch`.
- If the result is empty: the user is probably looking at a workspace that pre-dates the change-id feature, or made commits in a worktree the plugin didn't initialise. The trailer is opt-in via the hook installed by init.
