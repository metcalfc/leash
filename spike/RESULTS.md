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

- Machine: Mac mini (Mac16,1), Apple M4, 32 GB, macOS 26.6.2
- QEMU version: 11.1.2 (Homebrew), `-accel hvf`
- Guest: Ubuntu 24.04 minimal cloud image, arm64; Claude Code 2.1.303
- leash commit: 68a2b1c plus the fixes on this branch (see Findings)
- Run: Oct 18, 2026, with a dedicated `sk-ant-usr-` key (Max-plan API
  credit) from the keychain. No GitHub token, so the git route was not run.

## Timings

| Step | Time |
| --- | --- |
| `vm.sh provision` (first boot, tools installed) | 84 s (124 s including the 224 MB image download) |
| `vm.sh up` to ssh ready | 7 s |
| `claude -p` through leash (median of 5) | 1058 ms (899 to 1073) |
| Same call from the host, direct (median of 5) | 1037 ms (927 to 1805) |
| `pip download requests` through leash | 395 ms |

Both `claude -p` sets used `--model haiku` and Claude Code 2.1.303 to keep
spend down; the host set ran with an empty `HOME` so local config and MCP
servers didn't skew it. Leash's overhead is inside the noise.

## Acceptance

| Check | Expected | Result |
| --- | --- | --- |
| `make test` | 13 pass | 15 pass (14 shipped, plus 1 for the env bug below) |
| `works.sh`: Claude Code returns LEASH_OK | works | works |
| `works.sh`: pip from pypi.org | works | works |
| `works.sh`: git clone via the github route (if a token is set) | works | not run: no token; skipped cleanly |
| `attack.sh`: every BLOCK line | blocked | all 12 blocked, both ALLOW lines pass |
| `attack.sh`: DNS via 10.0.2.3 | blocked (if not: note it, it's a DNS channel) | blocked (real timeout, `dig` present) |
| No `sk-ant-` anywhere in the guest | none | none: full-filesystem scan for a key shape found 0 files. The only literal `sk-ant-` is sudo's journal of the scan's own grep pattern |
| `cap.sh` trips the cap | REFUSED within a few calls | call 5: REFUSED at $0.27 of $0.25 (in-flight overshoot, as documented) |
| `leash report` attributes everything to `demo` | yes | yes for all 16 capability-carrying requests; 5 denials without a capability show as `-`, by design |
| Ctrl-C leash, then `claude` in the VM | fails | fails: `API Error: Connection dropped (ECONNRESET)`, but only after 173 s of retries; instant with `CLAUDE_CODE_MAX_RETRIES=0` |
| Restart leash, `claude` again | works, same capability | works (`BACK_AGAIN`), no change to the VM. The cap survives the restart, so the ledger had to be reset first |
| Recording | clean, every beat lands | `leash-demo.mp4`, 85 s, take 3. Every SHOTLIST beat lands; no key on screen, capability truncated. Takes 1 and 2 failed, see Findings |

### Beyond attack.sh

Also run as root in the locked guest, all refused:

| Attempt | Result |
| --- | --- |
| The host's other loopback services via 10.0.2.2 (e.g. :8080) | connect refused |
| IPv6 to the host (fec0::2) or the internet | no route; the guest has no global v6 address |
| Other ports on the gateway address (10.0.2.100:22, :80) and UDP | refused |
| Plain-HTTP proxying through leash (`http://example.com`, `http://pypi.org`) | 403 |
| CONNECT to pypi's IP, or to `pypi.org:22` | denied, audited to `demo` |
| Anthropic route: `/v1/organizations/me` | 403, path not on the allowlist |
| Anthropic route: `../` and `%2e%2e` traversal | 400 |
| Anthropic route with a forged capability | 401 |

## Stretch: Lima (Lima 2.2.1)

- **`vmType: qemu` with `qemu-wrapper.sh`: works.** The wrapper rewrites
  Lima's slirp netdev (`192.168.5.0/24`) to add `restrict=on` and a
  guestfwd at `192.168.5.100:8080`. Lima reaches READY. In the guest, leash
  answers through the guestfwd; direct HTTPS, raw IPs, every host port
  (including other loopback services) and Lima's DNS are refused. Two things
  broke and were worked around:
  - Lima looks for UEFI firmware relative to the QEMU binary, so behind a
    wrapper it can't find it. Fix: `firmware.images` pointing at
    Homebrew's `edk2-aarch64-code.fd`.
  - Lima's `30-install-packages.sh` runs apt on every boot. Locked from the
    first boot, it hangs for 8 min (READY at 519 s). Booting once open and
    then restarting locked, the way `vm.sh` does, gives 19 s open, then
    **7 s locked**, with no stall.
  - `mounts: []` is essential. Lima's default mounts your home directory
    into the guest, which is a bigger leak than the network.
- **`vmType: vz`: there's no knob, but there is a host-side lever** (about
  10 min of the hour's budget).
  - The guest's internet path is Lima's built-in user-mode NIC
    (gvisor-tap-vsock, in-process). There's no `restrict=on` equivalent and
    no documented way to drop that NIC. Doing it inside the guest doesn't
    count: root can bring it back.
  - ssh over vsock is Lima's default for vz Linux guests, which would let
    the NIC go entirely. But it needs sshd on vsock (systemd 256+), and
    Ubuntu 24.04 has 255, so Lima logged "using usernet forwarder" and ssh
    rode the user network.
  - Guest egress leaves as an ordinary host socket owned by the `limactl
    hostagent` process, running as the user (seen with `lsof` while the
    guest held a connection to 1.1.1.1:443). So it can be enforced on the
    host, three ways:
    1. pf `user` rules, with the host agent running as a dedicated uid and
       only 127.0.0.1:18080 allowed. Needs root to load. **Not tested**,
       because it needs sudo.
    2. A Network Extension content filter keyed on the process. Needs a
       signed system extension.
    3. A small patch to Lima's user network: a dial filter that allows only
       the ssh forward and one gateway address. This is the cleanest,
       because it's what `restrict=on` is for QEMU.

## Findings

What surprised me:

- **The guestfwd trusts whatever holds the port.** On this Mac, 8080 was
  already taken by another local service (a mail-archive server). The first
  `vm.sh up` booted anyway, with the guest's only way out spliced to that
  service instead of leash, for about 7 s before I caught it. Nothing in the
  guest dialed it in that window. The same thing happens during the revoke
  test: once leash stops, any local process that binds the port receives the
  guest's traffic. Fixed for the spike in two ways:
  - leash moved to 18080;
  - `vm.sh up` refuses to boot unless the listener answers as leash.

  The real fix is a Unix socket in a 0700 directory
  (`guestfwd=…-cmd:nc -U …`), so only the gateway's owner can stand in.
- **Bug in leash, fixed with a test.** `init` only advertised routes whose
  key resolved *in the shell that ran init*. `init` doesn't need keys, so
  run without them (as the handoff and `make spike-up` both do) it wrote an
  env file with no `ANTHROPIC_BASE_URL`, and the VM quietly had no Claude.
  Now every configured route is advertised, and `serve` refuses (audited
  404) any route whose key is missing.
- **`attack.sh`'s key check only knew `sk-ant-api` and `sk-ant-oat`.** The
  key for this run is `sk-ant-usr-` (Max-plan API credit). A plain
  `sk-ant-` grep can't replace it: the check would match its own source in
  `~/leash/`. It now matches the shape of a key (any `sk-ant-<kind>-`
  followed by 40+ secret characters).
- **Revoke takes 3 minutes to show.** Claude Code retries a dead endpoint
  with backoff for 173 s before printing `ECONNRESET`. Access is gone at
  once; the client just doesn't say so. `CLAUDE_CODE_MAX_RETRIES=0` makes it
  instant, and the tape uses it.
- **The cap refusal reads as an auth failure.** Claude Code shows leash's
  403 `permission_error` as "Failed to authenticate. API Error: 403 leash:
  daily spend cap reached…". The message is right; the framing isn't. A real
  gateway should pick the status Claude Code renders best.
- **The report and the cap read different sources.** Enforcement uses the
  ledger (`spend.json`); `report` sums the audit log. Reset one (as I did to
  re-test) and the report shows $0.62 against a $0.25 cap that is in fact
  holding. Harmless, but on camera it looked like a broken cap. A real gateway
  should report from the ledger.
- **The cap's call count depends on caching.** Cold, `cap.sh` tripped on
  call 5 ($0.03 per call). Warm, call 11 ($0.012 per call). The shot list's
  "three or four calls" assumes a cold cache.
- **VHS waits are Go regexps over the whole screen.** Take 1 hung because
  `/host\$ $/` can never match (`$` is the end of the screen). Two more
  waits would have matched the typed command or the other tmux pane. All
  three are fixed in `demo.tape`, with comments.
- Leash adds no measurable latency: a 1058 ms median through leash vs
  1037 ms direct.
- Spend for the whole spike: $0.90 through leash (28 metered calls), plus
  about $0.05 for the direct host timings.

What a real implementation in Ringleader would need:

- The gateway on a Unix socket owned by the user, not a TCP port. The VM
  driver should start and supervise it, and refuse to boot the VM without it.
- Two-phase VM lifecycle: provision open, then run locked. Or bake the
  image, so nothing in the boot path needs the internet. Lima's boot scripts
  assume the internet and stall without it.
- Per-VM capabilities minted at VM create and rotated at destroy, with the
  key in the host keychain and never in the driver's config.
- Ledger-backed reporting and audit shipping. Error statuses Claude Code
  presents sensibly.
- An egress story for allowlisted hosts: pypi and npm are open tunnels, so
  an agent can still publish data to them. The allowlist bounds where data
  can go, not what goes there.

Estimate (one engineer who knows the driver):

| Driver | Mechanism | Estimate |
| --- | --- | --- |
| QEMU (theirs) | `restrict=on` + one guestfwd to the gateway's Unix socket; two-phase boot | **1 to 2 weeks** to ship behind a flag. Proven here, about a day of spike work |
| Lima, `vmType: qemu` | the same, but injected via `QEMU_SYSTEM_AARCH64`, which is fragile; better as an upstream Lima option | **2 to 3 weeks**, including upstreaming |
| Lima, `vmType: vz` | patch Lima's gvisor-tap-vsock user network with a dial filter (or pf by uid as a stopgap) | **3 to 5 weeks**, mostly upstream review. Not proven; the lever is confirmed |
| WSL2 | not tested. Candidate: Hyper-V firewall rules for the WSL VM (Windows 11 22H2+), which sit outside the guest | **3 to 6 weeks**, unverified, needs its own spike |

The gateway is the same for all four, and it's the part that's already
working. So the answer to the spike's question is **weeks, not a quarter**,
for QEMU and Lima-qemu. Lima vz and WSL2 each need a spike of their own to
earn the same confidence.
