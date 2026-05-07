#!/usr/bin/env bash
# virtual-monorepo:status: print a per-repo summary for a branch-based workspace.
#
# Usage:
#   status.sh <branch> [--root=URL] [--repos=...] [--workspace-dir=PATH] [--worktree-root=PATH]

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: status.sh <branch> [flags…]" >&2
  exit 2
fi

JIRA=$1; shift

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$SCRIPT_DIR/../../lib/workspace.sh"
[[ -f "$LIB" ]] || { echo "status.sh: cannot find lib at $LIB" >&2; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

ws_pre_apply_overrides "$@"
ws_load_config
ws_apply_overrides "$@"
ws_finalise_repos

ws_log "status of branch-based workspace: $JIRA"
ws_log "worktree_root = $WORKTREE_ROOT"
echo

for entry in "${REPOS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  ws_status_worktree "$1" "$JIRA" "${3:-main}"
  echo
done
