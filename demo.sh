#!/usr/bin/env bash
# Walk through what the agent can and can't do. Run after `make up`.
# Each step prints what it's proving, then runs it inside the agent container.
set -euo pipefail

in_agent() { docker compose exec -T agent bash -lc "$1"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "1. The agent's environment holds capabilities, not keys"
in_agent 'env | grep -E "ANTHROPIC|OPENAI|PROXY|LEASH" | sed -E "s/(lsh_[A-Za-z0-9_-]{6})[A-Za-z0-9_-]+/\1.../g"'

step "2. No route around the gateway (direct connection, proxy bypassed)"
in_agent 'curl -sS --noproxy "*" -m 5 https://api.anthropic.com/v1/models -o /dev/null -w "%{http_code}\n" || echo "unreachable -- good"'

step "3. Allowlisted egress works"
in_agent 'curl -sS -m 10 https://pypi.org/simple/requests/ -o /dev/null -w "pypi.org -> %{http_code}\n"'

step "4. Everything else is refused, and audited"
in_agent 'curl -sS -m 10 https://example.com -o /dev/null -w "example.com -> %{http_code}\n" || true'
in_agent 'curl -sS -m 10 https://webhook.site -o /dev/null -w "webhook.site -> %{http_code}\n" || true'

step "5. Claude Code works, on a key it never sees"
if grep -q '^ANTHROPIC_BASE_URL' run/chad-claude.env; then
  in_agent 'claude -p "Reply with exactly: LEASH_OK" 2>&1 | tail -3'
else
  echo "(skipped: no ANTHROPIC_API_KEY was given to the gateway)"
fi

step "6. Who did what, and what it cost"
docker compose exec -T leash ./leash -c policy.json report
