#!/usr/bin/env bash
# qemu-wrapper.sh -- stretch goal, UNTESTED: lock a Lima (vmType: qemu) VM's
# network the same way vm.sh does, by rewriting Lima's QEMU command line.
#
# Lima lets you override the QEMU binary it runs:
#   QEMU_SYSTEM_AARCH64=$PWD/spike/lima/qemu-wrapper.sh limactl start --vm-type=qemu ...
#
# This finds Lima's user-mode -netdev (slirp, 192.168.5.0/24) and appends
# restrict=on plus one guestfwd to leash. Lima's ssh is a hostfwd, so it
# survives restrict=on; its guest agent talks over virtio-serial, not the
# network. If Lima is using its socket-based network (user-v2) instead,
# there is no slirp netdev to rewrite and this does nothing: say so in
# RESULTS.md.
set -euo pipefail

REAL=${LEASH_REAL_QEMU:-$(brew --prefix qemu)/bin/qemu-system-aarch64}
GW=${LEASH_LIMA_GW:-192.168.5.100:8080}
LEASH_PORT=${LEASH_PORT:-18080}
LOG=${LEASH_WRAPPER_LOG:-/tmp/leash-qemu-wrapper.log}

args=()
rewrote=0
prev=""
for a in "$@"; do
  if [[ $prev == -netdev && $a == user,* ]]; then
    a="$a,restrict=on,guestfwd=tcp:$GW-cmd:nc 127.0.0.1 $LEASH_PORT"
    rewrote=1
  fi
  args+=("$a")
  prev=$a
done
printf '%s rewrote=%s %s\n' "$(date +%T)" "$rewrote" "${args[*]}" >> "$LOG"
exec "$REAL" "${args[@]}"
