#!/usr/bin/env bash
# cap.sh -- run inside the VM. Keep calling the model until the gateway's
# per-session spend cap refuses. The agent can't raise the cap: it lives in
# policy.json on the host.
set -uo pipefail
command -v claude >/dev/null || { echo 'TEST ERROR: claude is not installed' >&2; exit 2; }
max=${1:-15}
[[ $max =~ ^[1-9][0-9]*$ ]] || { echo 'TEST ERROR: expected a positive call limit' >&2; exit 2; }
for i in $(seq 1 "$max"); do
  code=0
  out=$(CLAUDE_CODE_MAX_RETRIES=0 claude -p "In one short sentence, name a prime number bigger than $((i * 100))." 2>&1) || code=$?
  if [[ $code != 0 ]] && grep -qi 'leash: daily spend cap reached' <<<"$out"; then
    printf '  call %2d: REFUSED  %s\n' "$i" "$(grep -oi 'daily spend cap[^"]*' <<<"$out" | head -1)"
    exit 0
  fi
  if [[ $code != 0 ]]; then
    printf '  call %2d: ERROR (exit %s) %s\n' "$i" "$code" "$(tr '\n' ' ' <<<"$out" | cut -c1-140)" >&2
    exit 2
  fi
  printf '  call %2d: ok       %s\n' "$i" "$(tr '\n' ' ' <<<"$out" | cut -c1-70)"
done
echo "  cap never tripped in $max calls -- lower spend.per_session_usd_per_day"
exit 1
