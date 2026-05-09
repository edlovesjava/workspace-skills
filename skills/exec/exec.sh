#!/usr/bin/env bash
# virtual-monorepo:exec: run a shell command in every worktree of a workspace.
#
# Usage:
#   exec.sh <branch> [flags…] -- <command…>

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: exec.sh <branch> [flags…] -- <command…>" >&2
  exit 2
fi

JIRA=$1; shift

flags=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift; break;;
    *)  flags+=("$1"); shift;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "exec.sh: missing command after --" >&2
  exit 2
fi
CMD="$*"

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  LIB="$CLAUDE_PLUGIN_ROOT/lib/workspace.sh"
else
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  LIB="$SCRIPT_DIR/../../lib/workspace.sh"
fi
[[ -f "$LIB" ]] || { echo "$(basename "${BASH_SOURCE[0]}"): cannot find lib at $LIB" >&2; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

set -e
ws_pre_apply_overrides "${flags[@]+"${flags[@]}"}"
ws_load_config
ws_apply_overrides "${flags[@]+"${flags[@]}"}"
ws_finalise_repos
set +e

ws_log "exec across $JIRA: $CMD"
echo

failures=()
for entry in "${REPOS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  name=$1
  wt=$(ws_worktree_dir "$JIRA" "$name")
  if [[ ! -d "$wt" ]]; then
    echo "=== $name (skip: no worktree at $wt) ==="
    continue
  fi
  echo "=== $name ($wt) ==="
  ( cd "$wt" && bash -c "$CMD" )
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    failures+=("$name (exit $rc)")
  fi
  echo "--- $name exit=$rc ---"
  echo
done

if [[ ${#failures[@]} -gt 0 ]]; then
  ws_log "FAILED in: ${failures[*]}"
  exit 1
fi
ws_log "ok in all repos"
