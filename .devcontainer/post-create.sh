#!/usr/bin/env bash
# Provision the workspace-skills demo container.
# Runs once after the container is created; safe to re-run.

set -euo pipefail

echo "==> apt: installing jq, shellcheck"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  jq \
  shellcheck

echo "==> npm: installing Claude Code CLI"
sudo npm install -g @anthropic-ai/claude-code

echo "==> verifying tools"
git --version
gh --version | head -n1
node --version
jq --version
shellcheck --version | head -n2 | tail -n1
claude --version || echo "(claude CLI installed; auth required before first use)"

echo
echo "==> ready."
echo "    Try the demo: README.md -> 'End-to-end demo flow'."
echo "    Run a skill directly, e.g.:"
echo "      bash .claude/skills/workspace-status/status.sh JIRA-123 \\"
echo "        --workspace-dir=/tmp/myws \\"
echo "        --repos=foo=https://github.com/owner/foo.git#main"
