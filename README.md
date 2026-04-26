# workspace-skills

A demo of **Pattern 4: Agent-Assisted Workspace Management** — Claude Code skills that
manage a multi-repo workspace where the same branch (typically a JIRA id) must exist
across several repos, with all work happening in **git worktrees** so the main clones
stay clean.

## Concepts

```
<workspace_dir>/                 # common project root: shared context lives here
├── .workspace.conf              # manifest: which repos, where worktrees go
├── .main/                       # main clones (one per repo, on default branch)
│   ├── service-a/
│   └── service-b/
└── worktrees/                   # worktree_root
    └── JIRA-123/                # branch name
        ├── service-a/           # worktree of .main/service-a on branch JIRA-123
        └── service-b/           # worktree of .main/service-b on branch JIRA-123
```

The pattern enforced by these skills is exactly:

```
<worktree_root>/<branch_name>/<repo>
```

Main branches stay in their main clones (`.main/<repo>`). Per-branch work happens
in worktrees attached to those main clones, so multiple JIRA branches across the
same repos cost almost nothing — git shares objects across worktrees.

## The four skills

| Skill | What it does |
|-------|--------------|
| **workspace-init** `<branch>` | Ensure a main clone exists per repo, then add a worktree per repo at `<worktree_root>/<branch>/<repo>` on a branch named `<branch>`. |
| **workspace-sync** `<branch>` | For each worktree: `git fetch origin && git rebase origin/<default>`. Stops on first conflict. |
| **workspace-exec** `<branch> -- <cmd>` | Run `<cmd>` sequentially in every worktree, with per-repo headers. Aggregates exit code. |
| **workspace-teardown** `<branch>` | Verify every worktree is clean (no uncommitted / unpushed work), then `git worktree remove` each and drop the per-branch dir. `--force` skips the cleanliness check. |

Each skill lives at `.claude/skills/workspace-<verb>/SKILL.md` with a sibling shell
script that does the actual work. The skills share `lib/workspace.sh`.

## Modes

Both modes are supported and can be selected per-invocation by flags:

### Manifest mode

A `.workspace.conf` lists repos directly. See
[`examples/manifest-mode/.workspace.conf`](examples/manifest-mode/.workspace.conf).

```bash
# in the workspace dir (the one containing .workspace.conf)
bash .claude/skills/workspace-init/init.sh JIRA-123
```

### Submodule mode

The workspace points at an orchestration repo whose `.gitmodules` defines the
constituent repos. See
[`examples/submodule-mode/.workspace.conf`](examples/submodule-mode/.workspace.conf).

```bash
# in the workspace dir
bash .claude/skills/workspace-init/init.sh JIRA-123 \
  --root=https://github.com/example/orchestration.git
```

### Inline (no manifest needed)

```bash
bash .claude/skills/workspace-init/init.sh JIRA-123 \
  --repos=service-a=https://github.com/example/service-a.git#main,service-b=https://github.com/example/service-b.git#main \
  --workspace-dir=/tmp/myworkspace
```

All four skills accept the same flags so you can drive any of them without a
manifest.

## End-to-end demo flow

Once the skills are installed in a workspace dir with a `.workspace.conf`:

```bash
# 1. Bootstrap worktrees for a new ticket
bash .claude/skills/workspace-init/init.sh JIRA-123

# 2. Do some work...
cd worktrees/JIRA-123/service-a
# edit, commit, push, etc.

# 3. Pick up upstream changes everywhere
bash .claude/skills/workspace-sync/sync.sh JIRA-123

# 4. Run a cross-repo task
bash .claude/skills/workspace-exec/exec.sh JIRA-123 -- git status -s
bash .claude/skills/workspace-exec/exec.sh JIRA-123 -- make test

# 5. After the PRs merge, clean up
bash .claude/skills/workspace-teardown/teardown.sh JIRA-123
```

## Driving via Claude Code

Because each skill has a `SKILL.md` with a `description:`, Claude Code will
auto-invoke them when the user asks things like:

- "init a workspace for JIRA-123"
- "sync the workspace"
- "run `git status` across all the JIRA-123 repos"
- "tear down JIRA-123"

Claude reads the SKILL.md, runs the script with the right flags, and reports the
result.

## Layout

```
.claude/skills/
├── workspace-init/        SKILL.md + init.sh
├── workspace-sync/        SKILL.md + sync.sh
├── workspace-exec/        SKILL.md + exec.sh
└── workspace-teardown/    SKILL.md + teardown.sh
lib/
└── workspace.sh           shared library (config loading, repo loops, git ops)
examples/
├── manifest-mode/.workspace.conf
└── submodule-mode/.workspace.conf
```

## Configuration reference

`.workspace.conf` is a bash file sourced by the skills. Variables:

| Variable | Default | Meaning |
|----------|---------|---------|
| `WORKTREE_ROOT` | `<workspace_dir>/worktrees` | Parent of per-branch worktree trees. |
| `MAIN_CLONES_DIR` | `<workspace_dir>/.main` | Where each repo's main clone lives. |
| `REPOS` | `()` | Bash array, one entry per repo: `"name url default_branch"`. |
| `ROOT_REPO` | unset | If set and `REPOS` is empty, the root repo's `.gitmodules` populates `REPOS`. |

CLI flags accepted by every skill:

- `--root=<url>`
- `--repos=name=url[#branch],…`
- `--workspace-dir=<path>`
- `--worktree-root=<path>`
- `--force` (teardown only)
