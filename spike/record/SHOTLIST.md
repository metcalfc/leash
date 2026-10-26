# Shot list: the agent's machine never receives the provider key

Two panes: leash's gateway log on the left, the agent's VM on the right.
The tape records this shorter walkthrough after the complete acceptance
sequence in `../HANDOFF.md`. The original 85-second recording is historical;
changed scripts require a new take before being described as recorded evidence.

| # | On screen | Say |
| --- | --- | --- |
| 0 | Title, then both panes | This POC keeps provider keys and network policy outside the coding agent's VM. It limits destinations and accounts for observed model usage. |
| 1 | `vm.sh status`: `restrict=on` and one guestfwd | QEMU enforces the outbound path on the host. Root inside this guest cannot change that rule. |
| 2 | Guest env, showing truncated `lsh_…` values | This VM holds a session capability. The real provider key stays in the gateway. A session is the budget identity selected on the host. |
| 3 | Claude returns `LEASH_OK`; gateway logs usage | Claude works through the gateway. The gateway replaces the capability with the real key and prices usage from the response. |
| 4 | Host `vm.sh verify`, PASS/block and PASS/allow | These destinations worked during open provisioning. Now, after removing the guest's firewall rules, the same direct probes are blocked. Gateway denials appear in the left log; packet drops are evidenced by this test transcript. |
| 5 | `cap.sh`: successful calls, then REFUSED | Once observed usage crosses the session's daily cap, the gateway refuses the next call. The guest cannot edit the policy or ledger. In-flight calls can overshoot. |
| 6 | `leash report` | These are gateway decisions, attributed when a valid capability was supplied, and the estimated charges from observed usage. |
| 7 | Ctrl-C gateway; guest call fails | Stop the gateway and access stops. The earlier acceptance sequence also checked recovery with the same capability and persistence of the cap across restart. |
| 8 | Title | This is an integration direction for the QEMU driver. Reusing the gateway in a customer cloud is a proposal; we have not run that experiment. |

## Before a take

- Use a dedicated provider key with a low provider-side limit, stored only in
  the host keychain. Never print it.
- Complete the canonical handoff's acceptance sequence, including successful
  positive controls, revoke/recovery before exhausting the cap, and refusal
  after restarting an exhausted session.
- The tape starts its own gateway. Stop any manual gateway on 18080 first.
  Use an unused session, e.g. `LEASH_SESSION=demo-take-2 make spike-record`.
  The tape initializes that identity and checks live routes, unused budget and
  the installed Claude binary before revealing the screen. It keeps prior
  ledger and audit evidence. Never reset either to make a take pass.
- Keep `LEASH_VM_STATE` and `LEASH_VM_SSH_PORT` consistent with the provisioned
  VM. The updated probes require a baseline from the current provisioning kit.
- The cap call count depends on model pricing and prompt caching. A failure or
  absent refusal must stop the take. The tape waits for successful acceptance
  output, not a generic failure marker.
- The dedicated tmux socket is `leash-record`. After a failed take, inspect it
  with `tmux -L leash-record attach -t leash`; stop its gateway and remove that
  demo session before retrying. Do not reuse a partly spent session for a
  fresh take. The tape does not delete old evidence.
- Watch the whole recording for secrets and errors before publishing. Masked
  env output is not a substitute for checking the result.

## Scope of the claims

Allowlisted hosts can still receive code, and opaque npm/PyPI tunnels can carry
uploads. This is not data-loss prevention. Missing final usage in interrupted
streams may undercount spend; prices are illustrative. `usage_observed` in the
audit says some usage was seen, not that all usage was captured.

QEMU and Lima-QEMU have recorded evidence. vz and WSL2 require independent
validation. The cloud experiment is deferred. The VM driver contract is in
README; the competitive comparison does not establish that this pattern is
exclusive to leash or Ringleader.
