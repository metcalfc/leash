#!/usr/bin/env bash
# vm.sh -- a VM whose only way out is leash.
#
# QEMU's user-mode network (slirp) with restrict=on drops every packet the
# guest sends to the host or the outside world. The one exception is an
# explicit guestfwd rule: 10.0.2.100:8080 in the guest is spliced to leash on
# the host's loopback. Enforcement lives in the QEMU process on the host, so
# root in the guest has nothing to flush, unset or route around.
#
#   vm.sh fetch       download the Ubuntu 24.04 minimal cloud image
#   vm.sh provision   first boot, network OPEN: install tools, then power off
#   vm.sh up          boot with the network LOCKED; push env + guest scripts
#   vm.sh ssh [cmd]   a login shell in the guest (capabilities loaded)
#   vm.sh down        power off
#   vm.sh status      is it running, and how is its network set up
#   vm.sh destroy     delete the VM disk (keeps the downloaded image)
#
# Environment: LEASH_VM_STATE (default spike/.vm), LEASH_VM_SSH_PORT (2222),
# LEASH_VM_MEM (4096), LEASH_VM_CPUS (4), LEASH_SESSION (demo),
# LEASH_PORT (18080, where leash listens on the host's loopback),
# LEASH_VM_INSTALL_CLAUDE (1).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
STATE=${LEASH_VM_STATE:-$HERE/.vm}
SSH_PORT=${LEASH_VM_SSH_PORT:-2222}
MEM=${LEASH_VM_MEM:-4096}
CPUS=${LEASH_VM_CPUS:-4}
SESSION=${LEASH_SESSION:-demo}
LEASH_PORT=${LEASH_PORT:-18080}
INSTALL_CLAUDE=${LEASH_VM_INSTALL_CLAUDE:-1}
GW_ADDR=10.0.2.100   # what the guest dials; must sit inside slirp's 10.0.2.0/24
GW_PORT=8080
RELEASE=noble

log() { printf '[vm] %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }

# ---------------------------------------------------------------- platform

FIRMWARE=()
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)
    ARCH=arm64; QEMU=qemu-system-aarch64
    MACHINE=(-M virt -accel hvf -cpu host)
    fw="$(brew --prefix qemu 2>/dev/null)/share/qemu/edk2-aarch64-code.fd"
    [[ -f $fw ]] || die "UEFI firmware not found at $fw -- brew install qemu"
    FIRMWARE=(-bios "$fw")
    ;;
  Darwin/x86_64)
    ARCH=amd64; QEMU=qemu-system-x86_64
    MACHINE=(-M q35 -accel hvf -cpu host)
    ;;
  Linux/x86_64)
    ARCH=amd64; QEMU=qemu-system-x86_64
    if [[ -w /dev/kvm ]]; then MACHINE=(-M q35 -accel kvm -cpu host)
    else MACHINE=(-M q35 -accel tcg -cpu max); log "no /dev/kvm: emulating, expect it to be slow"; fi
    ;;
  Linux/aarch64)
    ARCH=arm64; QEMU=qemu-system-aarch64
    if [[ -w /dev/kvm ]]; then MACHINE=(-M virt -accel kvm -cpu host)
    else MACHINE=(-M virt -accel tcg -cpu max); fi
    FIRMWARE=(-bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd)
    ;;
  *) die "unsupported platform $(uname -s)/$(uname -m)" ;;
esac
command -v "$QEMU" >/dev/null || die "$QEMU not found -- brew install qemu (or apt install qemu-system)"

IMAGE_URL="https://cloud-images.ubuntu.com/minimal/releases/$RELEASE/release/ubuntu-24.04-minimal-cloudimg-$ARCH.img"
BASE=$STATE/base-$ARCH.img
DISK=$STATE/disk.qcow2
KEY=$STATE/id_ed25519
PIDFILE=$STATE/qemu.pid

SSH=(ssh -i "$KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o LogLevel=ERROR -o ConnectTimeout=5 dev@127.0.0.1)

# The two networks. Same NIC, same guest address; the only difference is
# restrict=on and the one forward that survives it.
NET_OPEN="user,id=n0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
NET_LOCKED="user,id=n0,restrict=on,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22,guestfwd=tcp:$GW_ADDR:$GW_PORT-cmd:nc 127.0.0.1 $LEASH_PORT"

running() { [[ -f $PIDFILE ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

# ---------------------------------------------------------------- commands

cmd_fetch() {
  mkdir -p "$STATE"
  if [[ -f $BASE ]]; then log "have $BASE"; return; fi
  log "downloading $IMAGE_URL"
  curl -fL --progress-bar -o "$BASE.part" "$IMAGE_URL"
  mv "$BASE.part" "$BASE"
}

make_seed() {
  local dir=$STATE/seed
  rm -rf "$dir" && mkdir -p "$dir"
  [[ -f $KEY ]] || ssh-keygen -q -t ed25519 -N '' -C leash-spike -f "$KEY"
  sed -e "s|__PUBKEY__|$(cat "$KEY.pub")|" -e "s|__CLAUDE__|$INSTALL_CLAUDE|" \
    "$HERE/cloud-init.yaml" > "$dir/user-data"
  printf 'instance-id: leash-agent-vm\nlocal-hostname: agent-vm\n' > "$dir/meta-data"
  local iso=$STATE/seed.iso
  rm -f "$iso"
  if command -v hdiutil >/dev/null; then
    hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o "$iso" "$dir"
  elif command -v genisoimage >/dev/null; then
    genisoimage -quiet -output "$iso" -volid cidata -joliet -rock "$dir"
  elif command -v xorriso >/dev/null; then
    xorriso -as mkisofs -quiet -output "$iso" -volid cidata -joliet -rock "$dir"
  else
    die "need hdiutil, genisoimage or xorriso to build the cloud-init seed"
  fi
}

cmd_provision() {
  cmd_fetch
  running && die "VM is running; vm.sh down first"
  rm -f "$DISK"
  qemu-img create -q -f qcow2 -F qcow2 -b "$BASE" "$DISK" 20G
  make_seed
  log "first boot, network OPEN, installing tools; the VM powers off when done"
  log "  follow along: tail -f $STATE/console-provision.log"
  local t0=$SECONDS
  "$QEMU" "${MACHINE[@]}" ${FIRMWARE[@]+"${FIRMWARE[@]}"} -m "$MEM" -smp "$CPUS" \
    -drive "if=virtio,file=$DISK,format=qcow2" \
    -drive "if=virtio,file=$STATE/seed.iso,format=raw,readonly=on" \
    -netdev "$NET_OPEN" -device virtio-net-pci,netdev=n0 \
    -display none -serial "file:$STATE/console-provision.log"
  grep -q 'leash-provision-done' "$STATE/console-provision.log" \
    || die "provisioning did not finish cleanly -- see $STATE/console-provision.log"
  log "provisioned in $((SECONDS - t0))s"
}

push_files() {
  local env=$HERE/run/$SESSION.env
  [[ -f $env ]] || die "no $env -- run: ./leash -c spike/policy.json init"
  "${SSH[@]}" 'umask 077; cat > ~/.leash.env' < "$env"
  "${SSH[@]}" 'mkdir -p ~/leash'
  local f
  for f in "$HERE"/guest/*.sh; do
    # shellcheck disable=SC2094  # the remote path only shares the basename
    "${SSH[@]}" "cat > ~/leash/$(basename "$f") && chmod +x ~/leash/$(basename "$f")" < "$f"
  done
}

wait_ssh() {
  local _
  for _ in $(seq 1 "${1:-120}"); do
    if "${SSH[@]}" true 2>/dev/null; then return 0; fi
    sleep 2
  done
  die "ssh never came up -- see $STATE/console-up.log"
}

# The guestfwd splices the guest to whatever holds the port, not to leash by
# name. Refuse to boot unless the listener answers the way leash does.
check_gateway() {
  local body
  body=$(curl -s -m 3 "http://127.0.0.1:$LEASH_PORT/leash-probe/" 2>/dev/null || true)
  [[ $body == *"no route /leash-probe/"* ]] && return 0
  if lsof -nP -iTCP:"$LEASH_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    die "something that is not leash holds 127.0.0.1:$LEASH_PORT; the VM would be spliced to it"
  fi
  die "leash is not listening on 127.0.0.1:$LEASH_PORT -- start it first (make spike-gw)"
}

cmd_up() {
  [[ -f $DISK ]] || die "no VM disk -- run: vm.sh provision"
  running && { log "already running"; return; }
  check_gateway
  log "booting with the network LOCKED: restrict=on, guestfwd $GW_ADDR:$GW_PORT -> 127.0.0.1:$LEASH_PORT"
  local t0=$SECONDS
  "$QEMU" "${MACHINE[@]}" ${FIRMWARE[@]+"${FIRMWARE[@]}"} -m "$MEM" -smp "$CPUS" \
    -drive "if=virtio,file=$DISK,format=qcow2" \
    -netdev "$NET_LOCKED" -device virtio-net-pci,netdev=n0 \
    -display none -serial "file:$STATE/console-up.log" \
    -daemonize -pidfile "$PIDFILE"
  wait_ssh 300
  log "ssh up in $((SECONDS - t0))s"
  push_files
  log "pushed run/$SESSION.env and guest scripts; try: vm.sh ssh"
}

cmd_ssh() {
  if [[ $# -eq 0 ]]; then exec "${SSH[@]}" -t; fi
  exec "${SSH[@]}" -t "bash -lc $(printf '%q' "$*")"
}

cmd_down() {
  running || { log "not running"; rm -f "$PIDFILE"; return; }
  "${SSH[@]}" 'sudo poweroff' 2>/dev/null || true
  local _
  for _ in $(seq 1 30); do running || break; sleep 1; done
  running && kill "$(cat "$PIDFILE")"
  rm -f "$PIDFILE"
  log "down"
}

cmd_status() {
  if running; then
    log "running, pid $(cat "$PIDFILE")"
    # The netdev value holds spaces (the guestfwd command), so cut it out whole.
    ps -o args= -p "$(cat "$PIDFILE")" | sed -nE 's/.*-netdev (user,.*) -device .*/\1/p' | tr ',' '\n' | sed 's/^/  /' || true
  else
    log "not running"
  fi
}

cmd_destroy() { cmd_down; rm -rf "$DISK" "$STATE/seed" "$STATE/seed.iso" "$STATE"/console-*.log; log "disk removed"; }

case "${1:-}" in
  fetch|provision|up|down|status|destroy) "cmd_$1" ;;
  ssh) shift; cmd_ssh "$@" ;;
  *) sed -n '2,24p' "$0"; exit 2 ;;
esac
