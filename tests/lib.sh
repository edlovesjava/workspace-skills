#!/usr/bin/env bash
# Shared harness for the virtual-monorepo test suites.
# Sourced by tests/smoke.sh and tests/smoke-submodule.sh.
#
# Provides: a temp dir with an isolated git config, assertion helpers that
# tally pass/fail, and a `skill` runner. Call ws_test_summary at the end --
# it exits non-zero if anything failed.

PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Isolate from the developer's real git config, and from any ambient
# GIT_* the caller happens to be exporting.
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.email smoke@example.com
git config --file "$GIT_CONFIG_GLOBAL" user.name "Smoke Test"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
# Submodules over file:// paths are refused by default since the CVE-2022-39253
# fix. The fixtures are local throwaway dirs, so allow it inside the test only.
git config --file "$GIT_CONFIG_GLOBAL" protocol.file.allow always

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '         %s\n' "$2"; }

assert_eq() { # want got label
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3" "want [$1] got [$2]"; fi
}

assert_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3" "missing [$2]"; fi
}

assert_not_contains() { # haystack needle label
  if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail "$3" "unexpectedly found [$2]"; fi
}

section() { printf '\n== %s ==\n' "$1"; }

skill() { # skill-name args...
  local s=$1; shift
  bash "$PLUGIN_ROOT/skills/$s/$s.sh" "$@"
}

# Create a bare origin at $TMP/origins/<name>.git with one commit on main.
ws_test_make_origin() { # name
  local name=$1
  git init -q --bare "$TMP/origins/$name.git"
  git init -q "$TMP/origins/seed-$name"
  (
    cd "$TMP/origins/seed-$name" || exit 1
    echo "$name" > README.md
    git add -A && git commit -qm "pre-init seed $name"
    git remote add origin "$TMP/origins/$name.git"
    git push -q origin main
  )
}

ws_test_summary() {
  printf '\n%s\n' "-----------------------------"
  printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]]
}
