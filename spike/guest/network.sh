#!/usr/bin/env bash
# Shared probes: 0=reachable, 1=expected network failure, 2=test/setup error.
# Provisioning records the open-network controls. attack.sh repeats these exact
# destinations with restrict=on; verify keeps the host control listener alive.
set -uo pipefail

raw() { env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy curl --noproxy '*' "$@"; }

probe() {
  local kind=$1 target=$2 out code
  case $kind in
    https|host)
      out=$(raw -k -sS -m 6 "$target" 2>/dev/null); code=$?
      if [[ $code == 0 ]]; then
        if [[ $kind == host && $out != leash-host-control ]]; then return 2; fi
        return 0
      fi
      case $code in 6|7|28) return 1 ;; *) return 2 ;; esac
      ;;
    dns)
      out=$(dig +time=2 +tries=1 "@$target" example.com A 2>/dev/null); code=$?
      if [[ $code == 9 ]]; then return 1; fi
      if [[ $code != 0 || $out != *"status: NOERROR"* || ! $out =~ ANSWER:\ [1-9] ]]; then return 2; fi
      ;;
    ping)
      ping -c1 -W2 "$target" >/dev/null 2>&1; code=$?
      case $code in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
      ;;
    *) return 2 ;;
  esac
}

# Fixed IDs and destinations are shared by the baseline and the locked checks.
probes() {
  printf '%s\n' \
    'https-name https https://example.com' \
    'https-ip https https://1.1.1.1' \
    'https-model https https://api.anthropic.com' \
    'dns-public dns 1.1.1.1' \
    'dns-qemu dns 10.0.2.3' \
    'icmp ping 1.1.1.1' \
    "host-control host http://10.0.2.2:${LEASH_CONTROL_PORT:?host control port required}/"
}

baseline() {
  local target_file=/var/lib/leash/network-baseline.tsv id kind target failures=0
  mkdir -p "$(dirname "$target_file")"
  : > "$target_file"
  while read -r id kind target; do
    if probe "$kind" "$target"; then
      printf '%s\t%s\n' "$id" "$target" >> "$target_file"
      printf '  CONTROL PASS %s\n' "$id"
    else
      printf '  CONTROL FAILED %s (not evidence of isolation)\n' "$id" >&2
      failures=$((failures + 1))
    fi
  done < <(probes)
  if [[ $failures != 0 ]]; then return 1; fi
  echo leash-network-baseline-passed
}

if [[ ${1:-} == baseline ]]; then
  LEASH_CONTROL_PORT=${2:?control port required}
  baseline
fi
