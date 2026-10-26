#!/usr/bin/env bash
# works.sh -- run inside the VM. The useful half: real tools, real work,
# through the gateway, on credentials the VM never holds.
set -euo pipefail

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "What this machine holds: capabilities, not keys"
env | grep -E '^(ANTHROPIC|HTTPS_PROXY|OPENAI)' | sed -E 's/(lsh_[A-Za-z0-9_-]{6})[A-Za-z0-9_-]*/\1.../g'

step "pip install from pypi.org (allowlisted)"
python3 -m pip download --no-deps -q -d /tmp/wheels requests && ls /tmp/wheels

GW=${LEASH_GW:-http://10.0.2.100:8080}

# The route is always advertised; the gateway says 404 when it holds no token.
if [[ $(curl -s -o /dev/null -m 5 -w '%{http_code}' "$GW/github/") == 404 ]]; then
  echo; echo "(skipping git clone: the gateway has no github token)"
elif [[ -n ${GIT_CONFIG_COUNT:-} ]]; then
  step "git clone github.com over the gateway (token injected outside)"
  rm -rf /tmp/imp && git clone -q --depth 1 https://github.com/metcalfc/imp /tmp/imp && git -C /tmp/imp log --oneline -1
fi

if [[ -n ${ANTHROPIC_BASE_URL:-} ]] && command -v claude >/dev/null; then
  step "Claude Code, on a key it never sees"
  out=$(CLAUDE_CODE_MAX_RETRIES=0 claude --model "${LEASH_DEMO_MODEL:-haiku}" -p "Reply with exactly: LEASH_OK")
  printf '%s\n' "$out"
  grep -qx LEASH_OK <<<"$out" || { echo 'TEST ERROR: Claude did not return LEASH_OK' >&2; exit 2; }
else
  echo 'TEST ERROR: anthropic route or Claude installation missing' >&2
  exit 2
fi
