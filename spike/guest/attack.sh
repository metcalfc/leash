#!/usr/bin/env bash
# Run via vm.sh verify, which supplies a healthy host control listener.
# Only documented network failures count as blocks; setup failures stop the run.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=spike/guest/network.sh
source "$HERE/network.sh"
GW=${LEASH_GW:-http://10.0.2.100:8080}
BASELINE=/var/lib/leash/network-baseline.tsv
fails=0
row() { printf '  %-6s %-5s %s\n' "$1" "$2" "$3"; }
die() { printf 'TEST ERROR: %s\n' "$*" >&2; exit 2; }

for tool in curl dig ping sudo nft iptables ip grep; do
  command -v "$tool" >/dev/null || die "required tool missing: $tool"
done
[[ $(sudo -n id -u) == 0 ]] || die 'root setup unavailable'
[[ -s $BASELINE ]] || die 'no open-network baseline; reprovision the VM with the current kit'
[[ -n ${LEASH_CONTROL_PORT:-} ]] || die 'run ./spike/vm.sh verify on the host to supply a healthy control listener'

# Fail before the attack if root could not actually remove guest-side rules.
sudo -n nft flush ruleset
sudo -n iptables -P OUTPUT ACCEPT
sudo -n iptables -F
# With restrict=on DHCP may omit the default route. Select the slirp NIC from
# its address, then install the route explicitly to exercise a real root bypass.
iface=$(ip -o -4 addr show scope global | awk '$4 ~ /^10[.]0[.]2[.]/ {print $2; exit}')
[[ -n $iface ]] || die 'no guest interface found'
sudo -n ip route replace default via 10.0.2.2 dev "$iface"
echo '  root setup verified: firewall flushed, route reset; direct probes ignore proxies'
row RESULT GOT ATTEMPT

while read -r id kind target; do
  grep -Fxq "$(printf '%s\t%s' "$id" "$target")" "$BASELINE" || die "no successful positive control for $id at $target"
  code=0
  probe "$kind" "$target" || code=$?
  case $code in
    1) row PASS block "$id ($target)" ;;
    0) row FAIL allow "$id ($target)"; fails=$((fails + 1)) ;;
    *) die "probe $id failed to execute correctly" ;;
  esac
done < <(probes)

# Inspect the proxy's CONNECT response itself, so DNS/TLS/transport errors
# cannot masquerade as a policy denial. This does not make a model API call.
proxy_status() {
  local expected=$1 target=$2 authenticated=$3 code
  local args=(--proxy "$GW" --noproxy '' --proxytunnel -sS -I -m 8 -o /dev/null -w '%{http_connect}')
  if [[ $authenticated == yes ]]; then args+=(--proxy-user "agent:${LEASH_CAPABILITY:?capability missing}"); fi
  code=$(env -u ALL_PROXY -u all_proxy curl "${args[@]}" "$target" 2>/dev/null) || true
  if [[ $code == "$expected" ]]; then row PASS block "CONNECT $target -> $code"
  else row FAIL error "CONNECT $target expected $expected, got ${code:-no response}"; fails=$((fails + 1)); fi
}
proxy_status 403 https://example.com yes
proxy_status 403 https://api.anthropic.com/v1/models yes
proxy_status 407 https://pypi.org/simple/ no

# grep: 0=actual key found, 1=no match, 2=scan error. Permission/read errors
# must not become a passing no-secret result. Scope is explicit, not all disks.
pattern='sk-ant-[a-z]+[0-9]*-[A-Za-z0-9_-]{40,}'
scan=0
env | grep -E "$pattern" >/dev/null || scan=$?
[[ $scan == 0 || $scan == 1 ]] || die 'environment key scan failed'
if [[ $scan == 0 ]]; then
  row FAIL key 'Anthropic key shape in environment'; fails=$((fails + 1))
fi
scan=0
sudo -n grep -rIE "$pattern" /home /root /etc /tmp /var/tmp >/dev/null || scan=$?
case $scan in
  0) row FAIL key 'Anthropic key shape in scanned directories'; fails=$((fails + 1)) ;;
  1) row PASS block 'no Anthropic key shape in scanned directories' ;;
  *) die 'key scan encountered read errors' ;;
esac
status=$(raw -sS -m 5 -o /dev/null -w '%{http_code}' "$GW/") || die 'gateway unreachable'
[[ $status == 404 ]] || die "unexpected gateway status: $status"
row PASS allow 'gateway responds'
status=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' https://pypi.org/simple/) || die 'allowlisted PyPI request failed'
[[ $status == 200 ]] || die "PyPI expected 200, got $status"
row PASS allow 'PyPI through authenticated gateway'
if [[ $fails == 0 ]]; then echo '  all held: tested bypasses blocked; allow checks passed'
else echo "  $fails FAILED"; fi
exit "$fails"
