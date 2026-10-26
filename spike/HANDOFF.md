# Mac lockdown spike: canonical handoff

This is the runbook for reproducing the POC, not an instruction to rerun it
whenever reviewing the repository. Run from the repository root on an Apple
Silicon Mac. Read README's acceptance table, session semantics and VM driver
integration contract first.

The original Mac run demonstrated Claude Code, PyPI, cap refusal, revoke and
recovery. Lima-QEMU also worked with the workarounds in `RESULTS.md`. Those are
recorded results for that revision. The updated kit adds positive controls,
explicit test errors and fresh-session preflight; its verification is recorded
separately in RESULTS. vz and WSL2 remain proposals. The cloud experiment is
**deferred**; no cloud account is required for this handoff.

## What the POC establishes

A small gateway keeps credentials, egress rules, observed model spend and its
audit outside the guest. QEMU's host-side `restrict=on` drops guest egress
except one guestfwd: `10.0.2.100:8080` to leash at `127.0.0.1:18080`.
Root inside the guest cannot edit that QEMU rule. The packet-drop tests and
gateway audit are distinct evidence; the gateway cannot log packets it never
receives. An approved tunnel can still carry uploads.

A session is a named capability and daily budget identity, not a Claude chat
or an automatically inferred VM lifetime. The host selects it. All processes
using that capability share its spend; restarts preserve the ledger.

## Prepare a take

1. Install `qemu`, `vhs`, `tmux`, and Python 3.10+. Run `make test` and
   `make lint`. Optional: `make test-docker` requires Docker Engine 28+ and
   builds the gateway image. It exercises a healthy host listener before and
   after bridge isolation, with no provider keys.
2. Use a dedicated Anthropic key with a low provider-side spend limit, held
   only in the host keychain under `leash-anthropic`. If missing, ask the
   owner to create it; never print it or put it in a repository file. Git is
   optional: supply only a fine-grained, read-only `GITHUB_TOKEN`, not a broad
   personal `gh auth token`.
3. Pick an unused session name and export it in **both gateway and VM
   terminals**. For another take choose another name; retain the ledger and
   audit. Do not reset either to make a demo pass.

   ```sh
   export LEASH_SESSION=demo-take-1
   ./leash -c spike/policy.json --session "$LEASH_SESSION" init
   ```

4. Provision a trusted VM once. **This rebuilds the selected VM disk.** To
   preserve an existing VM, set `LEASH_VM_STATE` to a fresh directory outside
   the repository and choose a free `LEASH_VM_SSH_PORT`; retain those settings
   for every later VM command. Do not reopen a VM that has processed untrusted
   work. Provisioning installs tools, runs direct HTTPS/DNS/ICMP and a known
   host-listener positive control, then powers off. A failed control prevents
   this VM being accepted as evidence; inspect the log rather than treating
   an unavailable destination as a successful block.

   ```sh
   ./spike/vm.sh provision
   ```

5. In the gateway terminal, with the same `LEASH_SESSION`:

   ```sh
   make spike-gw
   ```

6. In the VM terminal:

   ```sh
   make spike-up
   make spike-preflight
   ./spike/vm.sh ssh command -v claude
   ```

   Preflight queries the actual running gateway with the session capability.
   It prints enabled routes, current spend and remaining budget; it refuses
   a missing Anthropic route, mismatched session, exhausted budget or a used
   demo session. It makes no provider call and prints no capability. Reusing
   an already running VM refreshes its env file and scripts; new SSH logins
   load the selected session. Old interactive shells retain their old env.

## Acceptance sequence

1. `./spike/vm.sh ssh leash/works.sh`: expect pip download and exactly
   `LEASH_OK` from Claude (Haiku by default). Git is skipped only when its
   gateway route is disabled. Tool/client errors fail the script.
2. `make spike-verify`: the host supplies a healthy control listener and
   checks the gateway, then runs guest attacks. Guest root setup must
   succeed. Every direct probe must have a successful matching control from
   provisioning. Missing commands, unsupported probe errors and key-scan read
   errors are TEST ERROR, not PASS. Gateway denials must return the expected
   CONNECT 403/407; allowlisted PyPI must return 200. The key scan covers the
   environment and `/home`, `/root`, `/etc`, `/tmp`, `/var/tmp`, looking for an
   Anthropic key shape. This is not an all-filesystem or all-secret proof.
3. **Revoke and recover before exhausting the budget.** Stop the gateway with
   Ctrl-C. With `CLAUDE_CODE_MAX_RETRIES=0`, a guest Claude call must fail.
   Restart with the same session and policy, then expect `BACK_AGAIN`:

   ```sh
   ./spike/vm.sh ssh "CLAUDE_CODE_MAX_RETRIES=0 claude --model haiku -p 'Reply with exactly: BACK_AGAIN'"
   ```

   Record the failed call and recovered call. Do not rotate the capability,
   reset spend or change the guest. If the budget was already exhausted,
   start a fresh take rather than changing the ledger.
4. `./spike/vm.sh ssh leash/cap.sh`: expect a failed Claude call containing
   `leash: daily spend cap reached`. Other client errors are failures, not
   successful inference. The default is at most 15 calls; cache behavior can
   change the count. You may choose an explicit higher limit, e.g.
   `./spike/vm.sh ssh '~/leash/cap.sh 30'`. Reaching the limit without refusal
   fails this check; it does not justify a success claim.
5. Stop/restart the gateway again with the same session. Another model call
   must still be refused for the cap, showing that restart did not reset it.
6. `make spike-report`: retain the audit and ledger alongside the transcript.
   Verify attributed gateway decisions and the recorded charge. Expected
   packet drops are in the test transcript, not the gateway log. Compare the
   cap with the ledger; the report sums historical audit entries.
7. Record only after these checks pass. Stop the manual gateway first; the
   tape owns its own gateway and tmux session. Select a new unused
   `LEASH_SESSION`, then `make spike-record`. The tape initializes that
   identity and checks fresh budget and Claude installation before showing
   the demo. Existing evidence is retained. Watch the complete result for
   errors and secrets; an old recording does not validate changed scripts.

## Evidence and engineering handoff

- Record revision, machine, tool versions, session name, positive controls,
  locked results, timings, actual cap refusal and any error or skipped check.
  Update RESULTS with a new section; preserve the original run history.
- Explain the product's intended budget identity before implementation: VM,
  developer, task or agent run. The POC deliberately does not infer one.
- Use README's driver integration contract: host-enforced network boundary;
  no credential-bearing mounts, host control sockets or forwarded SSH agents;
  policy/ledger outside writable workspaces; supervised gateway; trusted
  provisioning followed by lockdown; host-owned session lifecycle.
- The TCP guestfwd trusts the listener on that port. The startup identity probe
  catches accidental wrong services; a protected Unix socket is integration
  work. DNS/name binding, per-tool scopes and audit export are later hardening.
- Treat QEMU/Lima-QEMU delivery ranges in RESULTS as estimates. vz and WSL2
  need independent proof. Cloud portability remains untested and deferred.

## Research implications for implementation

The [independently augmented comparison](<../Agent sandboxes compared Docker Sandboxes, nono, microsandbox.md>) adds two reuse candidates: nono's standalone
proxy for external workloads and budgeted virtual keys from an LLM gateway
such as LiteLLM. Neither was integrated or runtime-tested here. Evaluate them
before treating the POC gateway as the implementation plan. Microsandbox's
network engine currently implements libkrun interfaces; reuse with another
VM driver would require integration work.

Keep request-rate limits, model-usage budgets and sandbox compute billing
separate. Choose whether a budget refuses calls after observed spend or
reserves estimated in-flight costs. Credential custody depends on the selected
mode, and forwarded agents or host tools can confer authority without exposing
secret bytes. Across drivers, require equivalent effective policy or explicit
startup failure for unsupported controls. A shared configuration file alone
does not establish parity. Cloud validation remains deferred.

## Working rules

Use `spike/mac-lockdown`, conventional commits, and never push to main.
Never print real keys, copy them into the VM, or commit `run/`, `spike/run/`,
`spike/.vm/`, workspace data or recordings. Keep Python typed and lint clean;
use shell strict mode. Document allowlist changes and failures in RESULTS.
Do not expand the POC to production features just to complete the demo.
