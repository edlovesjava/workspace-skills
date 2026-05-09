#!/usr/bin/env bash
# virtual-monorepo:teardown: remove all worktrees for a workspace branch.
#
# Usage:
#   teardown.sh <branch> [--force] [--root=URL] [--repos=...] [--workspace-dir=PATH] [--worktree-root=PATH]

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: teardown.sh <branch> [--force] [other flags…]" >&2
  exit 2
fi

JIRA=$1; shift

FORCE=0
flags=()
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1;;
    *)       flags+=("$arg");;
  esac
done

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  LIB="$CLAUDE_PLUGIN_ROOT/lib/workspace.sh"
else
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  LIB="$SCRIPT_DIR/../../lib/workspace.sh"
fi
[[ -f "$LIB" ]] || { echo "$(basename "${BASH_SOURCE[0]}"): cannot find lib at $LIB" >&2; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

ws_pre_apply_overrides "${flags[@]+"${flags[@]}"}"
ws_load_config
ws_apply_overrides "${flags[@]+"${flags[@]}"}"
ws_finalise_repos

ws_log "tearing down workspace for branch: $JIRA (force=$FORCE)"
ws_print_summary "$JIRA"
echo

if [[ "$FORCE" -ne 1 ]]; then
  ws_log "step 1/2: verifying every worktree is clean"
  unclean=0
  for entry in "${REPOS[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    if ! ws_check_clean "$1" "$JIRA"; then
      unclean=1
    fi
  done
  if [[ "$unclean" -eq 1 ]]; then
    ws_die "refusing to teardown: some worktrees are dirty or unpushed. Pass --force to discard."
  fi
  ws_log "  all worktrees clean"
  echo
fi

ws_log "step 2/2: removing worktrees"
for entry in "${REPOS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  ws_remove_worktree "$1" "$JIRA"
done

branch_dir=$(ws_branch_dir "$JIRA")
if [[ -d "$branch_dir" ]]; then
  rmdir "$branch_dir" 2>/dev/null || rm -rf "$branch_dir"
  ws_log "removed $branch_dir"
fi

echo
ws_log "teardown complete for $JIRA."
ws_log "main clones in $MAIN_CLONES_DIR are untouched."
ws_log "to also drop local branches: for d in $MAIN_CLONES_DIR/*; do git -C \"\$d\" branch -D $JIRA 2>/dev/null; done"
