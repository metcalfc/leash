# Spike results: a Mac VM whose only way out is leash

Fill this in as you go. Numbers beat adjectives.

## Pre-flight (Linux cloud workspace, Oct 19, 2026)

Run before handoff, on x86_64 under QEMU 8 emulation (no KVM, so timings
are meaningless), with a fake Anthropic key.

- `provision` 467 s, `up` to ssh 61 s (emulated).
- `attack.sh`: all 11 block attempts held, including root flushing
  nftables/iptables, resetting the default route, DNS through QEMU's own
  resolver at 10.0.2.3, and the host's real ports at 10.0.2.2.
- The pypi.org allow test failed for an environmental reason: that
  workspace intercepts outbound TLS with its own CA, which the guest doesn't
  trust. With `curl -k` it returns 200 through leash. This shouldn't happen on
  the Mac.
- The anthropic route reached the real API: 401 for the fake key.
- Revoke worked: gateway stopped gave nothing to talk to; restarted gave the
  same capability working again with no change to the VM.
- **Bug found and fixed:** `CONNECT` to an allowlisted host worked with no
  capability, so any process in the VM got out unattributed. Now 407, with a
  unit test and an `attack.sh` line.
- Not run: Claude Code in the guest, `cap.sh`, `works.sh`, the recording.

## Setup

- Machine: (model, chip, RAM, macOS version)
- QEMU version: (`qemu-system-aarch64 --version`)
- Guest: Ubuntu 24.04 minimal cloud image, arm64
- leash commit: (`git rev-parse --short HEAD`)

## Timings

| Step | Time |
| --- | --- |
| `vm.sh provision` (first boot, tools installed) | |
| `vm.sh up` to ssh ready | |
| `claude -p` through leash (median of 5) | |
| Same call from the host, direct (median of 5) | |
| `pip download requests` through leash | |

## Acceptance

| Check | Expected | Result |
| --- | --- | --- |
| `make test` | 13 pass | |
| `works.sh`: Claude Code returns LEASH_OK | works | |
| `works.sh`: pip from pypi.org | works | |
| `works.sh`: git clone via the github route (if a token is set) | works | |
| `attack.sh`: every BLOCK line | blocked | |
| `attack.sh`: DNS via 10.0.2.3 | blocked (if not: note it, it's a DNS channel) | |
| No `sk-ant-` anywhere in the guest | none | |
| `cap.sh` trips the cap | REFUSED within a few calls | |
| `leash report` attributes everything to `demo` | yes | |
| Ctrl-C leash, then `claude` in the VM | fails | |
| Restart leash, `claude` again | works, same capability | |

## Stretch: Lima

- Lima with `vmType: qemu` and a `QEMU_SYSTEM_AARCH64` wrapper that adds
  `restrict=on` and the `guestfwd`: (works / breaks what)
- Lima with `vmType: vz`: is there a way to cut its user-mode network's
  internet access while keeping ssh? (findings, one hour max)

## Findings

- What surprised you:
- What a real implementation in Ringleader would need:
- Estimate for Ringleader's QEMU driver, Lima driver, WSL2:
