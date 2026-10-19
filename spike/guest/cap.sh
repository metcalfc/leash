#!/usr/bin/env bash
# cap.sh -- run inside the VM. Keep calling the model until the gateway's
# per-session spend cap refuses. The agent can't raise the cap: it lives in
# policy.json on the host.
set -uo pipefail
max=${1:-15}
for i in $(seq 1 "$max"); do
  out=$(claude -p "In one short sentence, name a prime number bigger than $((i * 100))." 2>&1)
  if grep -qi "spend cap" <<<"$out"; then
    printf '  call %2d: REFUSED  %s\n' "$i" "$(grep -oi 'daily spend cap[^"]*' <<<"$out" | head -1)"
    exit 0
  fi
  printf '  call %2d: ok       %s\n' "$i" "$(tr '\n' ' ' <<<"$out" | cut -c1-70)"
done
echo "  cap never tripped in $max calls -- lower spend.per_session_usd_per_day"
exit 1
