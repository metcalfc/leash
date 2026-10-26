#!/usr/bin/env bash
# Walk through what the agent can and can't do. Run after `make up`.
# Each step prints what it's proving, then runs it inside the agent container.
# shellcheck disable=SC2016  # snippets expand in the container's shell
set -euo pipefail

in_agent() { docker compose exec -T agent bash -euo pipefail -c "$1"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "1. The agent's environment holds capabilities, not keys"
in_agent 'env | grep -E "ANTHROPIC|OPENAI|PROXY|LEASH" | sed -E "s/(lsh_[A-Za-z0-9_-]{6})[A-Za-z0-9_-]+/\1.../g"'

step "2. No direct external path (host isolation has a positive-control check in make test-docker)"
in_agent 'code=0; curl -sS --noproxy "*" -m 5 https://api.anthropic.com/v1/models -o /dev/null || code=$?; case $code in 6|7|28) echo "expected network failure" ;; *) echo "unexpected curl result: $code" >&2; exit 1 ;; esac'

step "3. Allowlisted egress works"
in_agent 'code=$(curl -sS -m 10 https://pypi.org/simple/requests/ -o /dev/null -w "%{http_code}"); echo "pypi.org -> $code"; test "$code" = 200'

step "4. Everything else is refused, and audited"
in_agent 'for host in example.com webhook.site; do code=$(curl -sS -m 10 "https://$host" -o /dev/null -w "%{http_connect}" 2>/dev/null) || true; echo "$host CONNECT -> $code"; test "$code" = 403; done'

step "5. Claude Code works, on a key it never sees"
docker compose exec -T leash ./leash -c policy.json --session chad-claude preflight --require-route anthropic
in_agent 'out=$(CLAUDE_CODE_MAX_RETRIES=0 claude --model haiku -p "Reply with exactly: LEASH_OK"); printf "%s\n" "$out"; grep -qx LEASH_OK <<<"$out"'

step "6. Who did what, and what it cost"
docker compose exec -T leash ./leash -c policy.json report
