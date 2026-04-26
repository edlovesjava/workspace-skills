#!/usr/bin/env bash
# Shared library for workspace-* skills.
# Sourced by .claude/skills/workspace-{init,sync,exec,teardown}/*.sh.
#
# Concepts:
#   workspace_dir   - common project root (default: $PWD). Holds shared
#                     context, main clones, and worktrees.
#   main_clones_dir - where each repo is cloned on its default branch
#                     (default: $workspace_dir/.main).
#   worktree_root   - parent of per-branch worktree trees
#                     (default: $workspace_dir/worktrees).
#   worktree path   - <worktree_root>/<branch_name>/<repo_name>.

set -euo pipefail

ws_die() { echo "workspace: $*" >&2; exit 1; }
ws_log() { echo "[workspace] $*"; }

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

# Find the workspace dir by walking upward looking for .workspace.conf.
# Falls back to $WORKSPACE_DIR or $PWD.
ws_find_workspace_dir() {
  if [[ -n "${WORKSPACE_DIR:-}" ]]; then echo "$WORKSPACE_DIR"; return; fi
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/.workspace.conf" ]]; then echo "$d"; return; fi
    d=$(dirname "$d")
  done
  echo "$PWD"
}

# Pre-pass: scan flags for --workspace-dir and set WORKSPACE_DIR before
# ws_load_config runs, so config is loaded from the right place.
ws_pre_apply_overrides() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --workspace-dir=*) WORKSPACE_DIR=$(cd "${arg#--workspace-dir=}" && pwd);;
    esac
  done
}

# Populate WORKSPACE_DIR, WORKTREE_ROOT, MAIN_CLONES_DIR, REPOS, ROOT_REPO.
# Honours .workspace.conf in the workspace dir, then applies defaults.
ws_load_config() {
  WORKSPACE_DIR=$(ws_find_workspace_dir)
  WORKSPACE_DIR=$(cd "$WORKSPACE_DIR" && pwd)

  WORKTREE_ROOT=""
  MAIN_CLONES_DIR=""
  ROOT_REPO=""
  REPOS=()

  local conf="$WORKSPACE_DIR/.workspace.conf"
  if [[ -f "$conf" ]]; then
    # shellcheck source=/dev/null
    source "$conf"
  fi

  # Resolve relative paths against WORKSPACE_DIR.
  WORKTREE_ROOT="${WORKTREE_ROOT:-$WORKSPACE_DIR/worktrees}"
  MAIN_CLONES_DIR="${MAIN_CLONES_DIR:-$WORKSPACE_DIR/.main}"
  WORKTREE_ROOT=$(_ws_abs "$WORKTREE_ROOT")
  MAIN_CLONES_DIR=$(_ws_abs "$MAIN_CLONES_DIR")
}

# Resolve to an absolute, normalised path. Works whether the path exists or not.
_ws_abs() {
  local p=$1
  case "$p" in /*) ;; *) p="$WORKSPACE_DIR/$p";; esac
  # Strip /./ and trailing /. -- realpath may not be available everywhere.
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$p"
  else
    # Best-effort normalisation.
    p=${p//\/.\//\/}
    p=${p%/.}
    echo "$p"
  fi
}

# Apply CLI overrides. Accepts a series of --key=value pairs after the
# positional jira-id, in any order.
#
# Supported:
#   --root=<git-url>            submodule mode: clone <url>, then for each
#                               submodule treat its path as the repo name
#   --repos=name=url[#branch],...  inline repo list (overrides REPOS)
#   --workspace-dir=<path>      override workspace dir
#   --worktree-root=<path>      override worktree root
ws_apply_overrides() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --root=*)          ROOT_REPO="${arg#--root=}";;
      --repos=*)         _ws_parse_repos "${arg#--repos=}";;
      --workspace-dir=*) WORKSPACE_DIR=$(cd "${arg#--workspace-dir=}" && pwd)
                         WORKTREE_ROOT=$(_ws_abs "${WORKTREE_ROOT:-$WORKSPACE_DIR/worktrees}")
                         MAIN_CLONES_DIR=$(_ws_abs "${MAIN_CLONES_DIR:-$WORKSPACE_DIR/.main}")
                         ;;
      --worktree-root=*) WORKTREE_ROOT=$(_ws_abs "${arg#--worktree-root=}")
                         ;;
      --*) ws_die "unknown flag: $arg";;
    esac
  done
}

_ws_parse_repos() { # name=url[#branch],...
  local spec=$1
  REPOS=()
  IFS=',' read -ra _items <<< "$spec"
  local item name url branch
  for item in "${_items[@]}"; do
    [[ -z "$item" ]] && continue
    name="${item%%=*}"
    url="${item#*=}"
    branch="main"
    if [[ "$url" == *"#"* ]]; then
      branch="${url##*#}"
      url="${url%#*}"
    fi
    REPOS+=("$name $url $branch")
  done
}

# Resolve REPOS from ROOT_REPO submodules if ROOT_REPO is set and REPOS empty.
ws_resolve_root_submodules() {
  [[ -z "$ROOT_REPO" ]] && return 0
  [[ ${#REPOS[@]} -gt 0 ]] && return 0

  local root_dir="$MAIN_CLONES_DIR/_root"
  if [[ ! -d "$root_dir/.git" ]]; then
    mkdir -p "$(dirname "$root_dir")"
    ws_log "cloning root repo $ROOT_REPO -> $root_dir"
    git clone "$ROOT_REPO" "$root_dir"
  fi
  git -C "$root_dir" submodule update --init --recursive --remote >/dev/null

  local gm="$root_dir/.gitmodules"
  [[ -f "$gm" ]] || ws_die "root repo has no .gitmodules"

  local name url branch
  while IFS= read -r line; do
    case "$line" in
      \[submodule*) name=$(echo "$line" | sed -E 's/.*"([^"]+)".*/\1/');;
      *url*=*) url=$(echo "$line" | sed -E 's/.*=[[:space:]]*//');;
      *branch*=*) branch=$(echo "$line" | sed -E 's/.*=[[:space:]]*//');;
    esac
    if [[ -n "${name:-}" && -n "${url:-}" ]]; then
      REPOS+=("$name $url ${branch:-main}")
      name=""; url=""; branch=""
    fi
  done < "$gm"
}

# After load + overrides, this should be called to make REPOS usable.
ws_finalise_repos() {
  ws_resolve_root_submodules
  [[ ${#REPOS[@]} -gt 0 ]] || ws_die "no repos configured (set REPOS in .workspace.conf, pass --repos=, or --root=)"
}

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

ws_main_dir()     { echo "$MAIN_CLONES_DIR/$1"; }                # $1=name
ws_worktree_dir() { echo "$WORKTREE_ROOT/$1/$2"; }               # $1=jira $2=name
ws_branch_dir()   { echo "$WORKTREE_ROOT/$1"; }                  # $1=jira

# ---------------------------------------------------------------------------
# Per-repo operations
# ---------------------------------------------------------------------------

ws_ensure_main_clone() { # name url default_branch
  local name=$1 url=$2 branch=$3
  local dir; dir=$(ws_main_dir "$name")
  if [[ ! -d "$dir/.git" ]]; then
    mkdir -p "$(dirname "$dir")"
    ws_log "  cloning $name <- $url ($branch)"
    git clone --branch "$branch" "$url" "$dir"
  else
    ws_log "  main clone exists: $name"
  fi
}

ws_add_worktree() { # name jira default_branch
  local name=$1 jira=$2 base=$3
  local main wt
  main=$(ws_main_dir "$name")
  wt=$(ws_worktree_dir "$jira" "$name")

  if [[ -d "$wt" ]]; then
    ws_log "  worktree exists: $name -> $wt"
    return 0
  fi
  mkdir -p "$(dirname "$wt")"
  git -C "$main" fetch --quiet origin

  if git -C "$main" show-ref --verify --quiet "refs/heads/$jira"; then
    ws_log "  attaching $name worktree to existing local branch $jira"
    git -C "$main" worktree add "$wt" "$jira"
  elif git -C "$main" show-ref --verify --quiet "refs/remotes/origin/$jira"; then
    ws_log "  attaching $name worktree to origin/$jira"
    git -C "$main" worktree add -B "$jira" "$wt" "origin/$jira"
  else
    ws_log "  creating $name worktree on new branch $jira from origin/$base"
    git -C "$main" worktree add -b "$jira" "$wt" "origin/$base"
  fi
}

ws_sync_worktree() { # name jira default_branch
  local name=$1 jira=$2 base=$3
  local wt; wt=$(ws_worktree_dir "$jira" "$name")
  [[ -d "$wt" ]] || { ws_log "  skip $name (no worktree at $wt)"; return 0; }

  ws_log "  fetch $name"
  git -C "$wt" fetch --quiet origin

  ws_log "  rebase $name $jira onto origin/$base"
  if ! git -C "$wt" rebase "origin/$base"; then
    ws_log "  rebase conflict in $name -- resolve in $wt then re-run sync"
    return 1
  fi
}

ws_check_clean() { # name jira -> 0 if clean, 1 otherwise
  local name=$1 jira=$2
  local wt; wt=$(ws_worktree_dir "$jira" "$name")
  [[ -d "$wt" ]] || return 0

  if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
    echo "  dirty: $name has uncommitted changes" >&2
    return 1
  fi
  local upstream
  upstream=$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "")
  if [[ -n "$upstream" ]]; then
    local ahead
    ahead=$(git -C "$wt" rev-list --count "$upstream..HEAD")
    if [[ "$ahead" != "0" ]]; then
      echo "  unpushed: $name has $ahead commit(s) ahead of $upstream" >&2
      return 1
    fi
  else
    local has_commits
    has_commits=$(git -C "$wt" rev-list --count "HEAD" "^origin/HEAD" 2>/dev/null || echo "?")
    if [[ "$has_commits" != "0" && "$has_commits" != "?" ]]; then
      echo "  unpushed: $name branch $jira has no upstream and $has_commits local commit(s)" >&2
      return 1
    fi
  fi
}

ws_remove_worktree() { # name jira
  local name=$1 jira=$2
  local main wt
  main=$(ws_main_dir "$name")
  wt=$(ws_worktree_dir "$jira" "$name")
  [[ -d "$wt" ]] || { ws_log "  skip $name (no worktree)"; return 0; }
  ws_log "  removing worktree: $name"
  git -C "$main" worktree remove --force "$wt"
}

# ---------------------------------------------------------------------------
# Iteration
# ---------------------------------------------------------------------------

# Call $1 with (name url default_branch) for each repo.
ws_for_each_repo() {
  local fn=$1
  local entry name url branch
  for entry in "${REPOS[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    name=$1; url=$2; branch=${3:-main}
    "$fn" "$name" "$url" "$branch"
  done
}

ws_print_summary() {
  local jira=$1
  echo
  ws_log "workspace_dir = $WORKSPACE_DIR"
  ws_log "worktree_root = $WORKTREE_ROOT"
  ws_log "branch        = $jira"
  ws_log "repos         = ${#REPOS[@]}"
  local entry
  for entry in "${REPOS[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    echo "  - $1 (default: ${3:-main})"
  done
}
