#!/usr/bin/env bash
# End-to-end smoke test for the virtual-monorepo plugin, SUBMODULE mode.
#
# Builds a throwaway "orchestration" root repo whose .gitmodules declares
# several service submodules, then drives the skills through ROOT_REPO /
# --root= resolution. Covers the cases the manifest-mode suite can't reach:
# how .gitmodules is parsed, and whether each repo lands on the branch it
# actually declares.
#
#   bash tests/smoke-submodule.sh

set -uo pipefail

# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# ---------------------------------------------------------------------------
# Fixture
#
# A root repo with four submodules, each exercising a different branch
# declaration:
#
#   service-a   no `branch` key            -> default (main)
#   service-b   branch = develop           -> develop
#   service-c   no `branch` key, declared  -> default (main), NOT develop:
#               immediately after service-b    regression test for a parser
#                                              that leaked the previous
#                                              stanza's branch forward
#   service-d   branch = .                 -> git's "same branch as the
#                                              superproject" shorthand
#
# Plus one submodule whose git name differs from its path, since the plugin
# keys everything off the path.
# ---------------------------------------------------------------------------

mkdir -p "$TMP/origins"
for r in service-a service-b service-c service-d service-e; do
  ws_test_make_origin "$r"
done

# service-b also gets a `develop` branch, which is what it pins.
(
  cd "$TMP/origins/seed-service-b" || exit 1
  git checkout -q -b develop
  echo develop > develop-only.txt
  git add -A && git commit -qm "develop branch of service-b"
  git push -q origin develop
)

git init -q "$TMP/origins/seed-root"
(
  cd "$TMP/origins/seed-root" || exit 1
  git submodule -q add "$TMP/origins/service-a.git" service-a
  git submodule -q add -b develop "$TMP/origins/service-b.git" service-b
  git submodule -q add "$TMP/origins/service-c.git" service-c
  git submodule -q add "$TMP/origins/service-d.git" service-d
  # `-b .` is not accepted by `submodule add` (git tries to check out a branch
  # literally named "."), so set the key the way a human editing .gitmodules
  # would. This is git's documented shorthand for "track the superproject's
  # own branch".
  git config -f .gitmodules submodule.service-d.branch .
  # Name deliberately != path.
  git submodule -q add --name internal-name-for-e "$TMP/origins/service-e.git" service-e
  git add -A && git commit -qm "orchestration root"
  git init -q --bare "$TMP/origins/root.git"
  git remote add origin "$TMP/origins/root.git"
  git push -q origin main
)

mkdir -p "$TMP/ws"
cd "$TMP/ws" || exit 1
cat > .workspace.conf <<CONF
ROOT_REPO="$TMP/origins/root.git"
CONF

# ---------------------------------------------------------------------------

section "init (submodule mode)"
out=$(skill init SUB-1 2>&1)
assert_eq "0" "$?" "init exits 0 in submodule mode"
[[ -d "$TMP/ws/.main/_root/.git" ]] && pass "root repo cloned to .main/_root" || fail "root repo cloned to .main/_root"

section ".gitmodules parsing"
assert_contains "$out" "service-a (default: main)" "submodule with no branch key defaults to main"
assert_contains "$out" "service-b (default: develop)" "declared 'branch = develop' is honoured"
assert_contains "$out" "service-c (default: main)" "branch does NOT leak from the previous submodule stanza"
assert_contains "$out" "service-d (default: main)" "'branch = .' resolves to the superproject's branch"
assert_contains "$out" "service-e (default: main)" "submodule whose name differs from its path is keyed by path"
# git's own "registered for path" chatter mentions the internal name, so assert
# on the plugin's repo list specifically rather than the whole transcript.
repo_list=$(printf '%s\n' "$out" | sed -n 's/^  - \(.*\) (default:.*/\1/p')
assert_not_contains "$repo_list" "internal-name-for-e" "the submodule's internal git name is not used as the repo name"

section "worktrees branch from the declared base"
for r in service-a service-b service-c service-d service-e; do
  [[ -d "$TMP/ws/worktrees/SUB-1/$r" ]] && pass "$r worktree created" || fail "$r worktree created"
done
assert_contains "$out" "creating service-b worktree on new branch SUB-1 from origin/develop" \
  "service-b branches from origin/develop, not origin/main"
assert_contains "$out" "creating service-a worktree on new branch SUB-1 from origin/main" \
  "service-a branches from origin/main"
# The develop-only file proves the worktree really came off develop.
[[ -f "$TMP/ws/worktrees/SUB-1/service-b/develop-only.txt" ]] \
  && pass "service-b worktree contains develop's content" \
  || fail "service-b worktree contains develop's content"

section "the other skills work in submodule mode"
out=$(skill status SUB-1 2>&1)
assert_eq "0" "$?" "status exits 0"
assert_contains "$out" "=== service-e ===" "status covers every submodule"

out=$(skill exec SUB-1 -- git rev-parse --abbrev-ref HEAD 2>&1)
assert_eq "0" "$?" "exec exits 0"
assert_contains "$out" "SUB-1" "exec runs inside the submodule-mode worktrees"

(cd worktrees/SUB-1/service-b && echo w > w.txt && git add -A && git commit -qm "work in b")
out=$(skill log SUB-1 2>&1)
assert_contains "$out" "work in b" "log finds trailer-stamped commits in submodule mode"

section "sync rebases each repo onto its OWN default branch"
# Move develop forward; service-b must pick it up, and must not be dragged to main.
(
  cd "$TMP/origins/seed-service-b" || exit 1
  git checkout -q develop
  echo more > more.txt
  git add -A && git commit -qm "develop moves on"
  git push -q origin develop
)
out=$(skill sync SUB-1 2>&1)
assert_eq "0" "$?" "sync exits 0"
assert_contains "$out" "rebase service-b SUB-1 onto origin/develop" "service-b rebases onto origin/develop"
log=$(git -C worktrees/SUB-1/service-b log --format=%s)
assert_contains "$log" "develop moves on" "service-b picked up the new develop commit"
assert_contains "$log" "work in b" "service-b kept its own work across the rebase"

section "a submodule added later is picked up"
(
  cd "$TMP/origins/seed-root" || exit 1
  ws_test_make_origin service-f >/dev/null 2>&1
  git submodule -q add "$TMP/origins/service-f.git" service-f
  git add -A && git commit -qm "add service-f"
  git push -q origin main
)
out=$(skill sync SUB-1 2>&1)
assert_contains "$out" "refreshing root repo" "sync refreshes the root repo's submodule view"
out=$(skill init SUB-1 2>&1)
assert_contains "$out" "service-f" "a later init picks up the newly added submodule"
[[ -d "$TMP/ws/worktrees/SUB-1/service-f" ]] && pass "service-f worktree created" || fail "service-f worktree created"

section "--root= flag without a manifest"
mkdir -p "$TMP/ws-noconf"
out=$(cd "$TMP/ws-noconf" && skill status SUB-2 --root="$TMP/origins/root.git" --workspace-dir="$TMP/ws-noconf" 2>&1)
assert_eq "0" "$?" "--root= resolves submodules with no .workspace.conf present"
assert_contains "$out" "service-b" "--root= sees the same submodule set"

section "error handling"
git init -q "$TMP/origins/seed-empty-root"
(
  cd "$TMP/origins/seed-empty-root" || exit 1
  echo hi > README.md && git add -A && git commit -qm "no submodules here"
  git init -q --bare "$TMP/origins/empty-root.git"
  git remote add origin "$TMP/origins/empty-root.git"
  git push -q origin main
)
mkdir -p "$TMP/ws-empty"
out=$(cd "$TMP/ws-empty" && skill status NOPE --root="$TMP/origins/empty-root.git" --workspace-dir="$TMP/ws-empty" 2>&1)
rc=$?
[[ "$rc" -ne 0 ]] && pass "a root repo with no .gitmodules fails loudly" || fail "a root repo with no .gitmodules fails loudly"
assert_contains "$out" "no .gitmodules" "the error names the actual problem"

section "teardown (submodule mode)"
skill teardown SUB-1 >/dev/null 2>&1
[[ "$?" -ne 0 ]] && pass "teardown refuses while service-b has unpushed work" || fail "teardown refuses while service-b has unpushed work"
(cd worktrees/SUB-1/service-b && git push -q -u origin SUB-1)
skill teardown SUB-1 >/dev/null 2>&1
assert_eq "0" "$?" "teardown succeeds once the work is pushed"
[[ ! -d "$TMP/ws/worktrees/SUB-1" ]] && pass "branch-based workspace removed" || fail "branch-based workspace removed"
[[ -d "$TMP/ws/.main/_root/.git" ]] && pass "the root clone survives teardown" || fail "the root clone survives teardown"

ws_test_summary
