#!/usr/bin/env bash
# workspace-init: bootstrap a multi-repo worktree workspace for a shared branch.
#
# Usage:
#   init.sh <branch> [--root=URL] [--repos=name=url[#branch],...]
#           [--workspace-dir=PATH] [--worktree-root=PATH]

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: init.sh <branch> [--root=URL] [--repos=...] [--workspace-dir=PATH] [--worktree-root=PATH]" >&2
  exit 2
fi

JIRA=$1; shift

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$SCRIPT_DIR/../../../lib/workspace.sh"
[[ -f "$LIB" ]] || { echo "init.sh: cannot find lib at $LIB" >&2; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

ws_pre_apply_overrides "$@"
ws_load_config
ws_apply_overrides "$@"
ws_finalise_repos

ws_log "initialising workspace for branch: $JIRA"
ws_print_summary "$JIRA"
echo

ws_log "step 1/2: ensuring main clones exist"
ws_for_each_repo ws_ensure_main_clone

echo
ws_log "step 2/2: adding worktrees"
ws_for_each_repo_init_worktree() {
  ws_add_worktree "$1" "$JIRA" "$3"
}
for entry in "${REPOS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  ws_add_worktree "$1" "$JIRA" "${3:-main}"
done

echo
ws_log "done. worktrees live under: $WORKTREE_ROOT/$JIRA"
ws_log "next: cd into a worktree, or run workspace-sync $JIRA to rebase against default branches."
