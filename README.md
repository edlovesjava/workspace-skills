# virtual-monorepo

A Claude Code plugin for managing **virtual (logical) monorepos** — one shared
branch (typically a JIRA id) across multiple repositories, with all work done
in **git worktrees** grouped per-branch under a single parent directory.

Think of it as the multi-repo counterpart to Claude Code's built-in worktree
support: that gives you parallel branches in *one* repo; this gives you
parallel branches across *all* the repos that need to change together.

This is the reference implementation of **Pattern 4: Agent-Assisted
Workspace Management** from
[*Managing Claude Code Across Multiple Repositories*](managing_claude_code_across_multiple_repositories_draft%20%282%29.md).

## What you get

Six skills, namespaced under the `virtual-monorepo` plugin:

| Skill | What it does |
|-------|--------------|
| **`virtual-monorepo:init`** `<branch>` | Ensure a main clone exists per repo, then add a worktree per repo at `<worktree_root>/<branch>/<repo>` on a branch named `<branch>`. |
| **`virtual-monorepo:status`** `<branch>` | Per-repo summary: branch, dirty file count, ahead/behind upstream, distance from default branch, last commit. |
| **`virtual-monorepo:sync`** `<branch>` | In submodule mode: pull root repo and refresh submodule pointers. Then per worktree: `git fetch origin && git rebase origin/<default>`. Stops on first conflict. |
| **`virtual-monorepo:test`** `<branch>` | Run each repo's configured test command (`TEST_CMD_<repo>` / `TEST_CMD` / `--cmd=`). Repos with no command configured are skipped. |
| **`virtual-monorepo:exec`** `<branch> -- <cmd>` | Run an arbitrary shell command in every worktree, with per-repo headers and aggregated exit code. The general-purpose primitive that backs `virtual-monorepo:test` for ad-hoc commands. |
| **`virtual-monorepo:teardown`** `<branch>` | Verify every worktree is clean (no uncommitted / unpushed work), then `git worktree remove` each and drop the per-branch dir. `--force` skips the cleanliness check. |

## Vocabulary (matches the article)

| Term | Meaning in this plugin |
|------|------------------------|
| **Root workspace** | The directory holding shared context (rules, skills, docs) plus the main clones and the branch-based workspaces. The article's "root workspace project" lives here. |
| **Main clone** | A normal `git clone` of a repo on its default branch, kept under the root workspace at `<root>/.main/<repo>`. Worktrees attach to it. |
| **Branch-based workspace** | The per-JIRA subdirectory `<worktree_root>/<branch>/` that groups one worktree per repo. This is what `virtual-monorepo:init` creates. |
| **Worktree** | A git working directory attached to a main clone, on the JIRA branch — `<worktree_root>/<branch>/<repo>`. |

## Layout enforced by the plugin

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

Pattern enforced:

```
<worktree_root>/<branch_name>/<repo>
```

If you'd rather have branch dirs sit directly at the root workspace (no
`worktrees/` parent), pass `--worktree-root=$root_workspace` or set
`WORKTREE_ROOT="."` in `.workspace.conf`.

## Install

Inside Claude Code:

```text
/plugin marketplace add edlovesjava/workspace-skills
/plugin install virtual-monorepo@workspace-skills
```

After install, the skills are available as `/virtual-monorepo:init`,
`/virtual-monorepo:status`, etc., and Claude will auto-invoke them when the
intent matches their descriptions.

## Modes

Both modes from the article are supported and can be selected per invocation
by flags.

### Manifest mode

A `.workspace.conf` lists repos directly. See
[`examples/manifest-mode/.workspace.conf`](examples/manifest-mode/.workspace.conf).

```text
/virtual-monorepo:init JIRA-123
```

### Submodule mode (Pattern 1's first-class root repo)

The root workspace points at an orchestration repo whose `.gitmodules`
defines the constituent repos. See
[`examples/submodule-mode/.workspace.conf`](examples/submodule-mode/.workspace.conf).

```text
/virtual-monorepo:init JIRA-123 --root=https://github.com/example/orchestration.git
```

### Inline (no manifest needed)

```text
/virtual-monorepo:init JIRA-123 \
  --repos=service-a=https://github.com/example/service-a.git#main,service-b=https://github.com/example/service-b.git#main \
  --workspace-dir=/tmp/myworkspace
```

All skills accept the same flags so you can drive any of them without a
manifest.

## End-to-end demo flow

Once the plugin is installed and there's a `.workspace.conf` in your root
workspace dir:

```text
# 1. Bootstrap the branch-based workspace for a new ticket
/virtual-monorepo:init JIRA-123

# 2. See the state at a glance
/virtual-monorepo:status JIRA-123

# 3. Do some work...
cd worktrees/JIRA-123/service-a
# edit, commit, push, etc.

# 4. Pick up upstream changes everywhere
/virtual-monorepo:sync JIRA-123

# 5. Run the tests across every repo with a configured command
/virtual-monorepo:test JIRA-123

# 6. Or run an ad-hoc command across the workspace
/virtual-monorepo:exec JIRA-123 -- git status -s

# 7. After the PRs merge, clean up
/virtual-monorepo:teardown JIRA-123
```

## Running the scripts directly (no Claude needed)

Every skill is a thin SKILL.md plus a self-contained shell script, so you can
run them outside Claude Code as well:

```bash
bash skills/init/init.sh JIRA-123
bash skills/status/status.sh JIRA-123
bash skills/sync/sync.sh JIRA-123
bash skills/test/test.sh JIRA-123
bash skills/exec/exec.sh JIRA-123 -- git status -s
bash skills/teardown/teardown.sh JIRA-123
```

This is what the SKILL.md files instruct Claude Code to do under the hood.

## Try it in a dev container or Codespace

This repo ships a [`.devcontainer`](.devcontainer/) so you can exercise the
plugin end-to-end without installing anything locally:

- **VS Code locally:** open the repo, run *"Dev Containers: Reopen in Container"*.
- **GitHub Codespaces:** Code button → Codespaces tab → *"Create codespace on this branch"*.

The container is `mcr.microsoft.com/devcontainers/base:bookworm` plus
`gh`, Node.js LTS, `@anthropic-ai/claude-code`, `jq`, and `shellcheck`.
`gh` and `claude` will both prompt to log in on first use; no credentials
are baked into the image.

## Repository layout

```
.claude-plugin/
└── plugin.json                       plugin manifest (name: virtual-monorepo)
skills/
├── init/        SKILL.md + init.sh
├── status/      SKILL.md + status.sh
├── sync/        SKILL.md + sync.sh
├── test/        SKILL.md + test.sh
├── exec/        SKILL.md + exec.sh
└── teardown/    SKILL.md + teardown.sh
lib/
└── workspace.sh                      shared bash library (config, git ops)
examples/
├── manifest-mode/.workspace.conf
└── submodule-mode/.workspace.conf
.devcontainer/
├── devcontainer.json
└── post-create.sh
```

## Configuration reference

`.workspace.conf` is a bash file sourced by the skills.

| Variable | Default | Meaning |
|----------|---------|---------|
| `WORKTREE_ROOT` | `<root_workspace>/worktrees` | Parent of branch-based workspaces. |
| `MAIN_CLONES_DIR` | `<root_workspace>/.main` | Where each repo's main clone lives. |
| `REPOS` | `()` | Bash array, one entry per repo: `"name url default_branch"`. |
| `ROOT_REPO` | unset | If set and `REPOS` is empty, the root repo's `.gitmodules` populates `REPOS` (submodule mode). |
| `TEST_CMD` | unset | Default test command for `virtual-monorepo:test` when no per-repo override exists. |
| `TEST_CMD_<repo>` | unset | Per-repo test command override. Non-alphanumerics in `<repo>` become `_`. |

CLI flags accepted by every skill:

- `--root=<url>`
- `--repos=name=url[#branch],…`
- `--workspace-dir=<path>`
- `--worktree-root=<path>`

Skill-specific flags:

- `virtual-monorepo:test` → `--cmd=<shell>` (default test command for this run).
- `virtual-monorepo:teardown` → `--force` (discard dirty/unpushed work).
- `virtual-monorepo:exec` → positional `--` separator before the command to run.
