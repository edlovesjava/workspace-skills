#!/usr/bin/env bash
# virtual-monorepo:test: run each repo's configured test command across a branch-based workspace.
#
# Usage:
#   test.sh <branch> [--cmd=DEFAULT] [--root=URL] [--repos=...] [--workspace-dir=PATH] [--worktree-root=PATH]

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: test.sh <branch> [--cmd=DEFAULT] [other flags…]" >&2
  exit 2
fi

JIRA=$1; shift

# Pull --cmd= out of the args; everything else is forwarded to the lib.
DEFAULT_CMD=""
flags=()
for arg in "$@"; do
  case "$arg" in
    --cmd=*) DEFAULT_CMD="${arg#--cmd=}";;
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

set -e
ws_pre_apply_overrides "${flags[@]+"${flags[@]}"}"
ws_load_config
ws_apply_overrides "${flags[@]+"${flags[@]}"}"
ws_finalise_repos
set +e

# --cmd flag wins over conf-level TEST_CMD; per-repo TEST_CMD_<name> still wins over both.
[[ -n "$DEFAULT_CMD" ]] && TEST_CMD="$DEFAULT_CMD"

ws_log "test across $JIRA (branch-based workspace at $WORKTREE_ROOT/$JIRA)"
echo

failures=()
skipped=()
for entry in "${REPOS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  name=$1
  cmd=$(ws_test_cmd_for "$name")
  if [[ -z "$cmd" ]]; then
    echo "=== $name (skip: no TEST_CMD configured) ==="
    skipped+=("$name")
    echo
    continue
  fi

  wt=$(ws_worktree_dir "$JIRA" "$name")
  if [[ ! -d "$wt" ]]; then
    echo "=== $name (skip: no worktree at $wt) ==="
    skipped+=("$name (no worktree)")
    echo
    continue
  fi

  echo "=== $name ($wt) ==="
  echo "    $ $cmd"
  ( cd "$wt" && bash -c "$cmd" )
  rc=$?
  echo "--- $name exit=$rc ---"
  echo
  if [[ "$rc" -ne 0 ]]; then
    failures+=("$name (exit $rc)")
  fi
done

if [[ ${#skipped[@]} -gt 0 ]]; then
  ws_log "skipped: ${skipped[*]}"
fi
if [[ ${#failures[@]} -gt 0 ]]; then
  ws_log "FAILED in: ${failures[*]}"
  exit 1
fi
ws_log "ok in all configured repos"
