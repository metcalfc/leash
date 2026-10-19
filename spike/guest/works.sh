#!/usr/bin/env bash
# works.sh -- run inside the VM. The useful half: real tools, real work,
# through the gateway, on credentials the VM never holds.
set -uo pipefail

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "What this machine holds: capabilities, not keys"
env | grep -E '^(ANTHROPIC|HTTPS_PROXY|OPENAI)' | sed -E 's/(lsh_[A-Za-z0-9_-]{6})[A-Za-z0-9_-]*/\1.../g'

step "pip install from pypi.org (allowlisted)"
python3 -m pip download --no-deps -q -d /tmp/wheels requests && ls /tmp/wheels

if [[ -n ${GIT_CONFIG_COUNT:-} ]]; then
  step "git clone github.com over the gateway (token injected outside)"
  rm -rf /tmp/imp && git clone -q --depth 1 https://github.com/metcalfc/imp /tmp/imp && git -C /tmp/imp log --oneline -1
fi

if [[ -n ${ANTHROPIC_BASE_URL:-} ]] && command -v claude >/dev/null; then
  step "Claude Code, on a key it never sees"
  claude -p "Reply with exactly: LEASH_OK"
else
  echo; echo "(skipping Claude Code: no anthropic route on the gateway, or claude not installed)"
fi
