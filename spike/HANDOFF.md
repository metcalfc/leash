# Handoff: the Mac lockdown spike

Paste this into Claude Code from the repo root on your Mac.

---

You're running a one-day spike on my Mac (Apple Silicon). The repo is
`leash`, a throwaway gateway that keeps a coding agent's credentials, egress
rules and spend outside the machine it runs on. Read `README.md` and this
file before doing anything else.

## Why

I'm advising Ringleader (ringleader.dev). They give each developer and coding
agent its own VM, on the laptop (QEMU, Lima, WSL2) or in the customer's own
cloud account. In the cloud, network rules and credentials live outside the
VM. On Mac and Windows laptops they have no network enforcement and no
credential gateway. Docker Sandboxes ships both for free, so this is the gap
that matters.

The question this spike answers: **how much work is it to make a gateway the
only way out of a laptop VM, so that root in the guest can't get around it?**
Weeks or a quarter? We're testing the cheapest mechanism first: QEMU's
user-mode network with `restrict=on`, which drops everything except explicit
forwards, plus one `guestfwd` to leash on the host's loopback.

## What's here

- `leash`: the gateway, with 13 tests (`make test`).
- `spike/vm.sh`: fetch, provision, boot and ssh into an Ubuntu 24.04 VM.
  `provision` boots once with the network open to install tools.
  `up` boots with the network locked.
- `spike/policy.json`: the spike's policy. leash listens on
  127.0.0.1:8080; the guest reaches it at 10.0.2.100:8080. The spend cap is
  $0.25 per day so it trips on camera.
- `spike/guest/`: `works.sh` (real work through the gateway), `attack.sh`
  (root trying every way out) and `cap.sh` (calls until the cap refuses).
  `vm.sh up` copies them to `~/leash/` in the guest.
- `spike/record/`: `demo.tape` (a VHS recording) and `SHOTLIST.md`.
- `spike/RESULTS.md`: the template you fill in.
- `spike/lima/qemu-wrapper.sh`: an untested sketch for the Lima stretch goal.

This kit was built and partly tested in a Linux cloud workspace under QEMU
emulation (x86_64, no KVM). Nothing has run on a Mac yet. Expect to fix
small things on macOS: firmware path, `hdiutil`, `nc` behaviour.

## Do this

1. `brew install qemu vhs tmux` (and `python3` 3.10+ if missing). Run `make test`.
2. Credentials, held on the host only:
   - I'll create a dedicated Anthropic API key with a low spend limit and
     store it with
     `security add-generic-password -a "$USER" -s leash-anthropic -w`.
     If it isn't there, stop and ask me.
   - Optional: a fine-grained, read-only GitHub token as `GITHUB_TOKEN`.
     Don't use my `gh auth token`; it's too broad.
3. `./leash -c spike/policy.json init`, then `./spike/vm.sh provision`.
   Record how long provisioning takes.
4. In a second terminal, start the gateway:
   `ANTHROPIC_API_KEY=$(security find-generic-password -s leash-anthropic -w) ./leash -c spike/policy.json serve`
5. `./spike/vm.sh up`, then in the guest run `~/leash/works.sh`, then
   `~/leash/attack.sh`, then `~/leash/cap.sh`.
6. Fill in every row of `spike/RESULTS.md`, including the timings.
7. Revoke test: Ctrl-C the gateway, check that `claude` in the VM fails,
   restart the gateway, check it works again.
8. Record: `vhs spike/record/demo.tape` produces
   `spike/record/leash-demo.mp4`. Watch it all the way through. Check that no
   key appears and that every beat in `SHOTLIST.md` lands, then re-record if
   needed. If the VHS version lacks `Wait`, upgrade it or swap in `Sleep`s.
9. Stretch, only once 1–8 pass:
   - Try Lima `vmType: qemu` with `spike/lima/qemu-wrapper.sh`.
   - Spend at most an hour on whether Lima's `vz` driver can lose
     internet access while keeping ssh.
   - Write down what you find either way.

## Acceptance

- Every BLOCK line in `attack.sh` is blocked and both ALLOW lines pass.
- Claude Code works in the guest, and no `sk-ant-` string exists anywhere
  in it.
- The cap trips.
- Ctrl-C revokes access, and a restart restores it.
- `RESULTS.md` is complete, and the recording exists and is clean.

If something in `attack.sh` gets through, that's the most important result
of the spike. Don't paper over it: write it up, and fix it only if the fix is
clearly in leash or `vm.sh`.

## Rules

- **Keys:** the real key never enters the VM, never appears on screen, and is
  never written to a file in the repo. Don't `echo` it, and don't print
  `ANTHROPIC_API_KEY`.
- **Ignored paths:** `run/`, `spike/run/`, `spike/.vm/` and recordings are
  never committed. Check `.gitignore` covers them before your first commit.
- **Git:** work on the branch `spike/mac-lockdown`. Use conventional commits.
  Never push to main.
- **Scope:** don't add egress allowlist entries to make something work
  without noting it in RESULTS.md. Each one is a finding.
- **Leash code:** leave leash's core alone unless you find a bug. If you do,
  fix it with a test.
- **Style:** bash with `set -euo pipefail`; Python 3.10+ with type hints,
  clean under ruff.
- **Report:** when done, give me a short summary with the acceptance table,
  the timings, anything that got through, and your estimate of the work for
  Ringleader's QEMU, Lima and WSL2 drivers.
