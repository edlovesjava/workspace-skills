---
name: test
description: Run each repo's configured test command across a branch-based virtual-monorepo workspace. Reads TEST_CMD_<repo> overrides (or a default TEST_CMD) from .workspace.conf or CLI flags, and uses the same per-repo loop as virtual-monorepo:exec. Use when the user says "test the workspace", "run the tests across all repos for JIRA-123", "validate the workspace", or wants the full mix of unit/integration/e2e tests across the affected repos.
---

# virtual-monorepo:test

Run the configured test command in every repo of a branch-based workspace. This is the `virtual-monorepo:test <jira-id>` skill from Pattern 4 of the *Managing Claude Code Across Multiple Repositories* article — "Run the right mix of unit, integration, REST, UI, and end-to-end tests across the affected repositories."

It is a thin wrapper over `virtual-monorepo:exec`: this skill picks the right command per repo and `virtual-monorepo:exec` runs it.

## When to use

- "test the workspace for JIRA-123"
- "run the tests across all repos"
- "validate JIRA-123"
- After a `virtual-monorepo:sync`, before opening PRs.

## Inputs

- `<branch>` (required, positional): the workspace key.
- `--cmd=<shell>` (optional): default test command for repos that do not have a per-repo override. Equivalent to setting `TEST_CMD` in `.workspace.conf`.
- `--root=…` / `--repos=…` / `--workspace-dir=…` / `--worktree-root=…` — same as the other workspace skills.

## How test commands are resolved

For each repo named `<name>`, the script picks the first of these that is set, in order:

1. `TEST_CMD_<sanitized-name>` (env var or `.workspace.conf` variable; non-alphanumerics in `<name>` become `_`).
2. The `--cmd=` flag passed on this invocation.
3. `TEST_CMD` (env var or `.workspace.conf` variable).

If nothing is configured for a repo, that repo is **skipped with a warning** (not failed). This makes it safe to run `virtual-monorepo:test` on a workspace where only some repos have test suites defined.

## What it does

For each repo with a resolved test command:

1. Print `=== <repo> ===` and the command.
2. `cd` into the worktree at `<worktree_root>/<branch>/<repo>` and run the command via `bash -c`.
3. Aggregate exit codes; non-zero in any repo fails the whole run.

Sequential, not parallel — keeps output readable in a demo.

## How to invoke

```bash
bash "$CLAUDE_PROJECT_DIR/skills/test/test.sh" <branch> [flags…]
```

## Examples

With per-repo commands in `.workspace.conf`:

```bash
# .workspace.conf
TEST_CMD_service_a="npm test"
TEST_CMD_service_b="make test"

bash skills/test/test.sh JIRA-123
```

With a single default command:

```bash
bash skills/test/test.sh JIRA-123 --cmd='make test'
```

Inline (no manifest):

```bash
bash skills/test/test.sh JIRA-123 \
  --workspace-dir=/tmp/ws \
  --repos=service-a=...#main,service-b=...#main \
  --cmd='echo "would run tests in $(basename $PWD)"'
```
