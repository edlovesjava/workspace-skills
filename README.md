# workspace-skills

A demo of **Pattern 4: Agent-Assisted Workspace Management** from
*Managing Claude Code Across Multiple Repositories* — Claude Code skills
that manage a multi-repo **branch-based workspace** where the same branch
(typically a JIRA id) must exist across several repos, with all work
happening in **git worktrees** so the main clones stay clean.

## Vocabulary (matches the article)

| Term | Meaning in this demo |
|------|----------------------|
| **Root workspace** | The directory holding shared context (rules, skills, docs) plus the main clones and the branch-based workspaces. Pattern 1's "root workspace project" lives here. |
| **Main clone** | A normal `git clone` of a repo on its default branch, kept under the root workspace at `<root>/.main/<repo>`. Worktrees attach to it. |
| **Branch-based workspace** | The per-JIRA subdirectory `<worktree_root>/<branch>/` that groups one worktree per repo. This is what `workspace-init` creates. |
| **Worktree** | A git working directory attached to a main clone, on the JIRA branch — `<worktree_root>/<branch>/<repo>`. |

## Layout

```
<root_workspace>/                       # the root workspace
├── .workspace.conf                     # manifest: which repos, where worktrees go
├── .main/                              # main clones (one per repo, on default branch)
│   ├── service-a/
│   └── service-b/
└── worktrees/                          # parent of branch-based workspaces
    └── JIRA-123/                       # <-- a branch-based workspace
        ├── service-a/                  # worktree of .main/service-a on JIRA-123
        └── service-b/                  # worktree of .main/service-b on JIRA-123
```

The pattern enforced by these skills is exactly:

```
<worktree_root>/<branch_name>/<repo>
```

If you'd rather have branch dirs sit directly at the root workspace (no
`worktrees/` parent), pass `--worktree-root=$root_workspace` or set
`WORKTREE_ROOT="."` in `.workspace.conf`.

## The five skills

These match the "Useful Skills to Share" list in Pattern 4 of the article.

| Skill | Article spec | What it does |
|-------|--------------|--------------|
| **workspace-init** `<branch>` | `workspace:init <jira-id>` | Ensure a main clone exists per repo, then add a worktree per repo at `<worktree_root>/<branch>/<repo>` on a branch named `<branch>`. |
| **workspace-status** `<branch>` | `workspace:status <jira-id>` | Per-repo summary: branch, dirty file count, ahead/behind upstream, distance from default branch, last commit. |
| **workspace-sync** `<branch>` | `workspace:sync <jira-id>` | In submodule mode: pull root repo and refresh submodule pointers. Then per worktree: `git fetch origin && git rebase origin/<default>`. Stops on first conflict. |
| **workspace-test** `<branch>` | `workspace:test <jira-id>` | Run each repo's configured test command (`TEST_CMD_<repo>` / `TEST_CMD` / `--cmd=`). Repos with no command configured are skipped. |
| **workspace-teardown** `<branch>` | `workspace:teardown <jira-id>` | Verify every worktree is clean (no uncommitted / unpushed work), then `git worktree remove` each and drop the per-branch dir. `--force` skips the cleanliness check. |

There is also one general-purpose primitive used internally:

| Skill | Purpose |
|-------|---------|
| **workspace-exec** `<branch> -- <cmd>` | Run an arbitrary shell command in every worktree, with per-repo headers and aggregated exit code. `workspace-test` is the typed-up cousin; reach for `exec` for ad-hoc commands like `git status -s`. |

Each skill lives at `.claude/skills/workspace-<verb>/SKILL.md` with a sibling
shell script that does the actual work. The skills share `lib/workspace.sh`.

## Modes

Both modes from the article are supported and can be selected per-invocation
by flags:

### Manifest mode

A `.workspace.conf` lists repos directly. See
[`examples/manifest-mode/.workspace.conf`](examples/manifest-mode/.workspace.conf).

```bash
# in the root workspace (the dir containing .workspace.conf)
bash .claude/skills/workspace-init/init.sh JIRA-123
```

### Submodule mode (Pattern 1's first-class root repo)

The root workspace points at an orchestration repo whose `.gitmodules`
defines the constituent repos. See
[`examples/submodule-mode/.workspace.conf`](examples/submodule-mode/.workspace.conf).

```bash
# in the root workspace
bash .claude/skills/workspace-init/init.sh JIRA-123 \
  --root=https://github.com/example/orchestration.git
```

### Inline (no manifest needed)

```bash
bash .claude/skills/workspace-init/init.sh JIRA-123 \
  --repos=service-a=https://github.com/example/service-a.git#main,service-b=https://github.com/example/service-b.git#main \
  --workspace-dir=/tmp/myworkspace
```

All skills accept the same flags so you can drive any of them without a manifest.

## End-to-end demo flow

Once the skills are installed in a root workspace dir with a `.workspace.conf`:

```bash
# 1. Bootstrap the branch-based workspace for a new ticket
bash .claude/skills/workspace-init/init.sh JIRA-123

# 2. See the state at a glance
bash .claude/skills/workspace-status/status.sh JIRA-123

# 3. Do some work...
cd worktrees/JIRA-123/service-a
# edit, commit, push, etc.

# 4. Pick up upstream changes everywhere
bash .claude/skills/workspace-sync/sync.sh JIRA-123

# 5. Run the tests across every repo with a configured command
bash .claude/skills/workspace-test/test.sh JIRA-123

# 6. Or run an ad-hoc command across the workspace
bash .claude/skills/workspace-exec/exec.sh JIRA-123 -- git status -s

# 7. After the PRs merge, clean up
bash .claude/skills/workspace-teardown/teardown.sh JIRA-123
```

## Try it in a dev container or Codespace

This repo ships a [`.devcontainer`](.devcontainer/) so you can exercise the
skills end-to-end without installing anything locally:

- **VS Code locally:** open the repo, run *"Dev Containers: Reopen in Container"*.
- **GitHub Codespaces:** Code button -> Codespaces tab -> *"Create codespace on this branch"*.

The container is `mcr.microsoft.com/devcontainers/base:bookworm` plus:

- `gh` (GitHub CLI feature)
- Node.js LTS (so we can `npm install -g`)
- `@anthropic-ai/claude-code` (the Claude Code CLI itself)
- `jq`, `shellcheck`
- VS Code shellcheck extension

You can then run any skill directly, or have Claude Code invoke them:

```bash
# inside the container, in a scratch dir:
mkdir -p /tmp/myws && cd /tmp/myws
bash $REPO/.claude/skills/workspace-init/init.sh JIRA-123 \
  --repos=foo=https://github.com/owner/foo.git#main,bar=https://github.com/owner/bar.git#main
```

Authentication note: `claude` and `gh` will both prompt to log in on first
use. The container does not embed any credentials.

## Driving via Claude Code

Because each skill has a `SKILL.md` with a `description:`, Claude Code will
auto-invoke them when the user asks things like:

- "init a workspace for JIRA-123"
- "status of JIRA-123"
- "sync the workspace"
- "run the tests across the JIRA-123 repos"
- "tear down JIRA-123"

Claude reads the SKILL.md, runs the script with the right flags, and reports
the result.

## Layout (this repo)

```
.claude/skills/
├── workspace-init/        SKILL.md + init.sh
├── workspace-status/      SKILL.md + status.sh
├── workspace-sync/        SKILL.md + sync.sh
├── workspace-test/        SKILL.md + test.sh
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
| `WORKTREE_ROOT` | `<root_workspace>/worktrees` | Parent of branch-based workspaces. |
| `MAIN_CLONES_DIR` | `<root_workspace>/.main` | Where each repo's main clone lives. |
| `REPOS` | `()` | Bash array, one entry per repo: `"name url default_branch"`. |
| `ROOT_REPO` | unset | If set and `REPOS` is empty, the root repo's `.gitmodules` populates `REPOS` (submodule mode). |
| `TEST_CMD` | unset | Default test command for `workspace-test` when no per-repo override exists. |
| `TEST_CMD_<repo>` | unset | Per-repo test command override. Non-alphanumerics in `<repo>` become `_`. |

CLI flags accepted by every skill:

- `--root=<url>`
- `--repos=name=url[#branch],…`
- `--workspace-dir=<path>`
- `--worktree-root=<path>`

Skill-specific flags:

- `workspace-test`: `--cmd=<shell>` — default test command for this run.
- `workspace-teardown`: `--force` — discard dirty/unpushed work.
- `workspace-exec`: positional `--` separator before the command to run.
