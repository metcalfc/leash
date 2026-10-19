# Shot list: "Your agent's machine never sees your API key"

About 4 minutes. Two panes: leash's log on the left, the agent's VM on the
right. `demo.tape` records the same beats unattended; this is the version
with a voice over it.

| # | On screen | Say |
|---|---|---|
| 0 | Title card, then the two panes | Coding agents run for hours on the one machine that holds everything: your code, your keys, your VPN. This is how to give the agent a machine where none of that can leak. |
| 1 | `vm.sh status`: QEMU with `restrict=on` and one `guestfwd` | This VM has exactly one way out. QEMU drops every packet it sends except to one address, which is spliced to a gateway on my laptop. That rule lives in the QEMU process on the host, not in the VM. |
| 2 | In the VM: `env`, showing `lsh_…` values | The VM holds capabilities, not keys. They're worthless anywhere except through this gateway. |
| 3 | `claude -p …` returns `LEASH_OK`; the left pane logs `allow … $0.0x` | Claude Code works normally. The gateway swaps the capability for the real key on the way out, and prices the call as it streams back. |
| 4 | `attack.sh`: a column of PASS/block | Now I'm root, and I try every way around it: flush the firewall, unset the proxy, hit an IP directly, DNS over UDP, ping, the host itself, tunnel straight to Anthropic. Every one is refused, and the refusals land in the log. |
| 5 | `cap.sh`: a few calls ok, then REFUSED | Spend is capped per session, and the cap lives on the host. The agent can't raise it. A real deployment would set it in dollars per day. |
| 6 | `leash report`: per-session requests, denials, spend | One line per decision, attributed to the session. That's the evidence a security team asks for. |
| 7 | Ctrl-C the gateway; `claude` in the VM fails | Stop the gateway and access is gone. Nothing to rotate, nothing to scrub off the VM, because there was never a key on it. |
| 8 | Back to the title | The same file and the same rules can run in your own cloud account, next to a firewall rule your security team can see. That's the bridge. |

## Before recording

- Use a dedicated Anthropic key with a low limit set in the console, stored in
  the keychain as `leash-anthropic`. Never `echo` it.
- Provision the VM off camera (`./spike/vm.sh provision`), then boot it with
  `./spike/vm.sh up` before rolling.
- Set the cap in `spike/policy.json` so it trips in three or four calls.
  $0.25 is about right for Claude Code's default model; check the left pane's
  per-call cost on a dry run. A warm prompt cache roughly halves it: one take
  tripped on call 5, the next on call 11.
- Check the frame for secrets before publishing: the env output is masked,
  the key never appears, and the capability is truncated.

## What not to claim

- This isn't Ringleader's product. It's a proof that the Mac gap is a gateway
  in front of the VM's network, not a quarter of work.
- `restrict=on` is QEMU-only. Lima's vz driver and Docker's own VMM need a
  different mechanism; see RESULTS.md for what the spike found.
- A live session can still spend up to the cap. The cap bounds it; it doesn't
  prevent it.
