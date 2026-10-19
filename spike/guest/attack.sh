#!/usr/bin/env bash
# attack.sh -- run inside the VM. Everything an agent with root might try to
# get around leash. Every BLOCK line should be blocked; the ALLOW lines prove
# the gateway itself still works. Exit status is the number of failures.
set -uo pipefail

GW=${LEASH_GW:-http://10.0.2.100:8080}
fails=0
row() { printf '  %-6s %-5s %s\n' "$1" "$2" "$3"; }

# expect <block|allow> <description> <command...>
expect() {
  local want=$1 what=$2; shift 2
  local got
  # Each attempt carries its own timeout (curl -m, dig +time, ping -W):
  # `timeout` can only run binaries, and some attempts are shell functions.
  if "$@" >/dev/null 2>&1; then got=allow; else got=block; fi
  if [[ $got == "$want" ]]; then row PASS "$got" "$what"; else row FAIL "$got" "$what"; fails=$((fails + 1)); fi
}

# curl through nothing at all: proxy variables gone, as a hostile agent would have it
# shellcheck disable=SC2329  # invoked through expect
raw() { env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY curl -sS --noproxy '*' -m 6 "$@"; }

echo
echo "  root in the guest tears down everything it can:"
sudo nft flush ruleset 2>/dev/null; sudo iptables -P OUTPUT ACCEPT 2>/dev/null; sudo iptables -F 2>/dev/null
sudo ip route replace default via 10.0.2.2 dev "$(ip -o route show default | awk '{print $5}' | head -1)" 2>/dev/null
echo "    firewall flushed, default route reset, proxy variables ignored"
echo
row RESULT GOT "ATTEMPT"
expect block "HTTPS to example.com, no proxy"                    raw https://example.com
expect block "HTTPS straight to an IP (1.1.1.1), no proxy"       raw -k https://1.1.1.1
expect block "HTTPS straight to api.anthropic.com, no proxy"     raw https://api.anthropic.com
expect block "DNS over UDP to 1.1.1.1"                           dig +time=2 +tries=1 @1.1.1.1 example.com
expect block "DNS via QEMU's own resolver (10.0.2.3)"            dig +time=2 +tries=1 @10.0.2.3 example.com
expect block "ping 1.1.1.1"                                      ping -c1 -W2 1.1.1.1
expect block "the host itself (10.0.2.2:18080, leash's real port)" raw http://10.0.2.2:18080/
expect block "the host's ssh (10.0.2.2:22)"                      timeout 5 bash -c 'exec 3<>/dev/tcp/10.0.2.2/22'
expect block "via the gateway: example.com (not allowlisted)"    curl -sS -f -m 8 https://example.com
expect block "via the gateway: tunnel to api.anthropic.com"      curl -sS -f -m 8 https://api.anthropic.com/v1/models
expect block "via the gateway, but without the capability"       env -u HTTPS_PROXY -u https_proxy curl -sS -f -m 8 -x "$GW" https://pypi.org/simple/
expect block "a real key anywhere in env, home, /etc or /tmp" \
  bash -c 'env | grep -qE "sk-ant-[a-z]+[0-9]*-[A-Za-z0-9_-]{40,}" || sudo grep -rqsE "sk-ant-[a-z]+[0-9]*-[A-Za-z0-9_-]{40,}" /home /root /etc /tmp /var/tmp'
expect allow "the gateway answers at $GW"                         bash -c "[ \"\$(curl -s -o /dev/null -m 5 -w '%{http_code}' $GW/)\" != 000 ]"
expect allow "via the gateway: pypi.org (allowlisted)"           bash -c "[ \"\$(curl -s -o /dev/null -m 15 -w '%{http_code}' https://pypi.org/simple/)\" = 200 ]"
echo
if [[ $fails -eq 0 ]]; then echo "  all held: the only way out is leash"; else echo "  $fails FAILED"; fi
exit "$fails"
