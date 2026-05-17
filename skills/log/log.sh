#!/usr/bin/env bash
# virtual-monorepo:log: show every commit across every repo that carries
# Workspace-Change-Id: <branch>, as one chronological view.
#
# Usage:
#   log.sh <branch> [--root=URL] [--repos=...] [--workspace-dir=PATH] [--worktree-root=PATH]

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: log.sh <branch> [flags…]" >&2
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

set -e
ws_pre_apply_overrides "$@"
ws_load_config
ws_apply_overrides "$@"
ws_finalise_repos
set +e

ws_log "log of Workspace-Change-Id: $JIRA"
echo

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

repos_with_commits=0
total=0
for entry in "${REPOS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  name=$1
  main=$(ws_main_dir "$name")
  if [[ ! -d "$main/.git" ]]; then
    echo "=== $name ==="
    echo "  (no main clone -- run virtual-monorepo:init first)"
    echo
    continue
  fi

  # %ai is sortable AND human readable: "2026-05-16 10:14:32 +0000"
  lines=$(git -C "$main" log --all \
    --grep="^Workspace-Change-Id: $JIRA\$" \
    --format="%ai%x09%h%x09%s" 2>/dev/null)

  if [[ -z "$lines" ]]; then
    echo "=== $name ==="
    echo "  (no commits with this trailer)"
    echo
    continue
  fi

  count=$(printf '%s\n' "$lines" | wc -l | tr -d ' ')
  repos_with_commits=$((repos_with_commits + 1))
  total=$((total + count))

  echo "=== $name ==="
  # Strip the timezone half of %ai for display; preserve YYYY-MM-DD HH:MM.
  printf '%s\n' "$lines" \
    | sort \
    | awk -F'\t' '{
        # $1 = "2026-05-16 10:14:32 +0000" -- take first 16 chars
        date = substr($1, 1, 16);
        printf "  %s  %s  %s\n", date, $2, $3
      }'
  echo

  # Stash for the across-repos sort (annotated with repo name).
  printf '%s\n' "$lines" | awk -F'\t' -v r="$name" '{print $0 "\t" r}' >> "$tmp"
done

if [[ "$total" -eq 0 ]]; then
  ws_log "no commits found with Workspace-Change-Id: $JIRA"
  ws_log "tip: the hook stamps commits made in worktrees created by virtual-monorepo:init."
  exit 0
fi

# Cross-repo chronological merge (handy when several repos share commits in the same window).
if [[ "$repos_with_commits" -gt 1 ]]; then
  echo "=== cross-repo timeline ==="
  sort "$tmp" | awk -F'\t' '{
      date = substr($1, 1, 16);
      printf "  %s  %-22s  %s  %s\n", date, $4, $2, $3
    }'
  echo
fi

ws_log "$total commit(s) across $repos_with_commits repo(s)"
