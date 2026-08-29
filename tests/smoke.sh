#!/usr/bin/env bash
# End-to-end smoke test for the virtual-monorepo plugin.
#
# Builds two throwaway bare "origins" in a temp dir, drives every skill
# against them, and asserts on the observable behaviour. No network, no
# fixtures checked in -- everything is created and torn down per run.
#
#   bash tests/smoke.sh
#
# Exits non-zero on the first failed assertion.

set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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

# ---------------------------------------------------------------------------
# Fixture: two bare origins + a workspace pointing at them
# ---------------------------------------------------------------------------

export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.email smoke@example.com
git config --file "$GIT_CONFIG_GLOBAL" user.name "Smoke Test"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false

mkdir -p "$TMP/origins" "$TMP/ws"
for r in service-a service-b; do
  git init -q --bare "$TMP/origins/$r.git"
  git init -q "$TMP/origins/seed-$r"
  (
    cd "$TMP/origins/seed-$r" || exit 1
    echo "$r" > README.md
    git add -A && git commit -qm "pre-init seed $r"
    git remote add origin "$TMP/origins/$r.git"
    git push -q origin main
  )
done

cat > "$TMP/ws/.workspace.conf" <<CONF
REPOS=(
  "service-a $TMP/origins/service-a.git main"
  "service-b $TMP/origins/service-b.git main"
)
TEST_CMD="echo default-test"
TEST_CMD_service_a="echo a-test"
CONF

cd "$TMP/ws" || exit 1

# ---------------------------------------------------------------------------

section "init"
out=$(skill init SMOKE-1 2>&1)
assert_eq "0" "$?" "init exits 0"
[[ -d "$TMP/ws/worktrees/SMOKE-1/service-a" ]] && pass "service-a worktree created" || fail "service-a worktree created"
[[ -d "$TMP/ws/worktrees/SMOKE-1/service-b" ]] && pass "service-b worktree created" || fail "service-b worktree created"
assert_eq "SMOKE-1" "$(git -C worktrees/SMOKE-1/service-a rev-parse --abbrev-ref HEAD)" "worktree is on the workspace branch"

# init is idempotent
out=$(skill init SMOKE-1 2>&1)
assert_eq "0" "$?" "re-running init exits 0"
assert_contains "$out" "worktree exists" "re-running init is idempotent"

section "branch tracking (no origin/<default> footgun)"
up=$(git -C worktrees/SMOKE-1/service-a rev-parse --abbrev-ref '@{u}' 2>&1)
assert_not_contains "$up" "origin/main" "new branch does NOT track origin/main"
push_hint=$(cd worktrees/SMOKE-1/service-a && git push 2>&1)
assert_contains "$push_hint" "--set-upstream origin SMOKE-1" "git push suggests --set-upstream, not HEAD:main"
assert_not_contains "$push_hint" "HEAD:main" "git push never suggests pushing to main"

section "Workspace-Change-Id hook"
[[ -x "$TMP/ws/.main/service-a/.git/hooks/prepare-commit-msg" ]] && pass "hook installed in main clone" || fail "hook installed in main clone"
(cd worktrees/SMOKE-1/service-a && echo work > f.txt && git add -A && git commit -qm "work in a")
(cd worktrees/SMOKE-1/service-b && echo work > f.txt && git add -A && git commit -qm "work in b")
msg=$(git -C worktrees/SMOKE-1/service-a log -1 --format=%B)
assert_contains "$msg" "Workspace-Change-Id: SMOKE-1" "worktree commit gets the trailer"

(cd worktrees/SMOKE-1/service-a && git commit -q --amend --no-edit)
n=$(git -C worktrees/SMOKE-1/service-a log -1 --format=%B | grep -c "^Workspace-Change-Id:")
assert_eq "1" "$n" "amend does not double-stamp the trailer"

(cd .main/service-b && git checkout -q main && echo x > main-only.txt && git add -A && git commit -qm "main clone commit")
msg=$(git -C .main/service-b log -1 --format=%B)
assert_not_contains "$msg" "Workspace-Change-Id" "commits in the main clone are NOT stamped"

assert_not_contains "$(git -C worktrees/SMOKE-1/service-a log --format=%B | tail -3)" "Workspace-Change-Id" "pre-init seed commit is not stamped"

section "status"
out=$(skill status SMOKE-1 2>&1)
assert_eq "0" "$?" "status exits 0"
assert_contains "$out" "=== service-a ===" "status reports service-a"
assert_contains "$out" "=== service-b ===" "status reports service-b"
assert_contains "$out" "branch   : SMOKE-1" "status shows the workspace branch"
assert_contains "$out" "git push -u origin SMOKE-1" "status tells you how to publish an unpublished branch"

section "test"
out=$(skill test SMOKE-1 2>&1)
rc=$?
assert_eq "0" "$rc" "test exits 0 when every repo passes"
assert_contains "$out" "a-test" "per-repo TEST_CMD_<repo> override is used"
assert_contains "$out" "default-test" "default TEST_CMD is used as fallback"

out=$(skill test SMOKE-1 --cmd="exit 3" 2>&1)
rc=$?
[[ "$rc" -ne 0 ]] && pass "test propagates a failing repo's exit code" || fail "test propagates a failing repo's exit code" "got rc=$rc"

section "exec"
out=$(skill exec SMOKE-1 -- git rev-parse --abbrev-ref HEAD 2>&1)
assert_eq "0" "$?" "exec exits 0"
assert_contains "$out" "SMOKE-1" "exec runs the command inside the worktrees"

section "sync"
# Land a new commit upstream, then confirm sync rebases onto it.
(
  cd "$TMP/origins/seed-service-a" || exit 1
  echo upstream > upstream.txt
  git add -A && git commit -qm "upstream moves on"
  git push -q origin main
)
out=$(skill sync SMOKE-1 2>&1)
assert_eq "0" "$?" "sync exits 0"
log=$(git -C worktrees/SMOKE-1/service-a log --format=%s)
assert_contains "$log" "upstream moves on" "sync rebased the workspace branch onto the new upstream commit"

section "log"
out=$(skill log SMOKE-1 2>&1)
assert_eq "0" "$?" "log exits 0"
assert_contains "$out" "work in a" "log finds the service-a commit by trailer"
assert_contains "$out" "work in b" "log finds the service-b commit by trailer"
assert_contains "$out" "cross-repo timeline" "log prints the cross-repo timeline for multi-repo changes"

out=$(skill log NOPE-9999 2>&1)
assert_eq "0" "$?" "log exits 0 for an unknown change id"
assert_contains "$out" "no commits found" "log degrades gracefully for an unknown change id"

section "teardown"
echo dirty > worktrees/SMOKE-1/service-a/dirty.txt
skill teardown SMOKE-1 >/dev/null 2>&1
[[ "$?" -ne 0 ]] && pass "teardown refuses while a worktree is dirty" || fail "teardown refuses while a worktree is dirty"
rm worktrees/SMOKE-1/service-a/dirty.txt

skill teardown SMOKE-1 >/dev/null 2>&1
[[ "$?" -ne 0 ]] && pass "teardown refuses while commits are unpushed" || fail "teardown refuses while commits are unpushed"

(cd worktrees/SMOKE-1/service-a && git push -q -u origin SMOKE-1)
(cd worktrees/SMOKE-1/service-b && git push -q -u origin SMOKE-1)
skill teardown SMOKE-1 >/dev/null 2>&1
rc=$?
assert_eq "0" "$rc" "teardown succeeds once all work is pushed"
[[ ! -d "$TMP/ws/worktrees/SMOKE-1" ]] && pass "branch-based workspace dir is removed" || fail "branch-based workspace dir is removed"
[[ -d "$TMP/ws/.main/service-a/.git" ]] && pass "main clones survive teardown" || fail "main clones survive teardown"

section "log survives teardown"
out=$(skill log SMOKE-1 2>&1)
assert_contains "$out" "work in a" "trailer is still queryable after the worktrees are gone"

# ---------------------------------------------------------------------------

printf '\n%s\n' "-----------------------------"
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
