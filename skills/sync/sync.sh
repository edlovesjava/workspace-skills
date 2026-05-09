#!/usr/bin/env bash
# virtual-monorepo:sync: fetch + rebase every worktree in a workspace.
#
# Usage:
#   sync.sh <branch> [--root=URL] [--repos=...] [--workspace-dir=PATH] [--worktree-root=PATH]

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: sync.sh <branch> [--root=URL] [--repos=...] [--workspace-dir=PATH] [--worktree-root=PATH]" >&2
  exit 2
fi

JIRA=$1; shift

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  LIB="$CLAUDE_PLUGIN_ROOT/lib/workspace.sh"
else
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  LIB="$SCRIPT_DIR/../../lib/workspace.sh"
fi
[[ -f "$LIB" ]] || { echo "$(basename "${BASH_SOURCE[0]}"): cannot find lib at $LIB" >&2; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

ws_pre_apply_overrides "$@"
ws_load_config
ws_apply_overrides "$@"
ws_finalise_repos

ws_log "syncing workspace for branch: $JIRA"
ws_print_summary "$JIRA"
echo

if [[ -n "${ROOT_REPO:-}" ]]; then
  ws_log "step 0: refreshing root repo submodules (submodule mode)"
  ws_refresh_root_submodules
  echo
fi

failed=0
for entry in "${REPOS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  name=$1; branch=${3:-main}
  if ! ws_sync_worktree "$name" "$JIRA" "$branch"; then
    failed=1
    break
  fi
done

if [[ "$failed" -eq 0 ]]; then
  echo
  ws_log "all repos in sync for $JIRA"
else
  echo
  ws_log "sync stopped on conflict; resolve and re-run."
  exit 1
fi
