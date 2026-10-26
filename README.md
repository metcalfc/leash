# leash

Keep a coding agent's credentials, egress and spend outside the machine it
runs on. A throwaway proof of concept, in the spirit of
[imp](https://github.com/metcalfc/imp): the agent gets a per-session
**capability**, never a credential.

```
make test        # loopback and script checks, no Docker or provider keys
make test-docker # Docker 28+: host positive control, isolation, real gateway
make up          # gateway + agent container on a network with no way out but the gateway
make demo        # what the agent can and can't do
make report      # who did what, and what it cost
```

## What it shows

One gateway process, outside the agent's machine, does four jobs:

| | how | what the agent sees |
|---|---|---|
| **credential injection** | `/anthropic/…`, `/openai/…`, `/github/…` routes swap the session capability for the real key, after a per-route path allowlist | `ANTHROPIC_AUTH_TOKEN=lsh_…` — worthless anywhere else |
| **egress allowlist** | the agent's only route out is `HTTPS_PROXY`; `CONNECT` is allowed to listed hosts on listed ports | `403` from anything else |
| **spend cap** | usage is read out of each model response as it streams past, priced, charged to the session, and the next call is refused once a daily cap is passed | a `permission_error` naming the cap |
| **audit** | one JSON line per handled gateway decision, attributed when a valid capability is present; never headers or bodies | — |

```
agent machine (no route out)            leash (outside)
-----------------------------------------------------------------------------
claude  -- ANTHROPIC_BASE_URL -->  /anthropic + real key ---> api.anthropic.com
git     -- url.insteadOf ------->  /github    + real token -> github.com
npm/pip -- HTTPS_PROXY --------->  CONNECT allowlist ------> registry.npmjs.org
curl https://webhook.site ------>  403, audited
curl --noproxy '*' anything ---->  no DNS, no route
```

The last line is what makes the rest hold. `HTTPS_PROXY` alone is a
suggestion an agent can unset. In `compose.yaml` the agent sits on an
`internal: true` network with `gateway_mode_ipv4: isolated` (Docker Engine
28+): no default route, no outbound NAT, no host bridge address. Internal
mode alone still permits access to host services. The gateway is the only
container on this network that also touches the outside.

Two smaller rules worth noticing:

- A host that has a credentialed route can't also be tunnelled to. Otherwise
  `CONNECT api.anthropic.com` would bypass injection, metering and the cap.
- Spend is charged before HTTP completion, so the next call after HTTP
  completion sees the updated ledger. Calls already in flight can still
  overshoot.

## Running it

```sh
make init     # mints capabilities, writes run/<session>.env (0600, no secrets)

# Real keys go to the gateway container only, straight out of your keychain:
ANTHROPIC_API_KEY=$(security find-generic-password -s anthropic -w) \
make up
# Optional: supply a dedicated, fine-grained read-only GITHUB_TOKEN as well.

make demo
docker compose exec agent claude     # a real session, on a key it never sees
make report
make down                            # every capability goes inert
```

A route whose credential doesn't resolve is switched off, not left open, so
`make up` with only an Anthropic key gives you `/anthropic/` and nothing else.

Policy lives in `policy.json`: sessions, routes, egress allowlist, caps and a
price table. The prices are illustrative; check list prices before trusting a
cap.

`credential` takes `env:NAME`, `file:PATH`, or `cmd:<shell>`, so
`cmd:op read op://dev/anthropic/credential` works if leash runs on the host
instead of in a container.

## Evidence and acceptance

`make test` runs 22 tests with fake upstreams and script stubs: Anthropic and
OpenAI JSON/SSE usage, credential swaps, refusal before upstream, persistence
across a gateway rebuild, egress rules, validation-denial audit records, env
files, preflight, and test-script error handling. `make lint` checks Python
and shell scripts. These checks make no provider calls.

| Claim | Enforcing mechanism | Evidence | Status |
| --- | --- | --- | --- |
| Agent receives capabilities, not provider keys | Gateway strips presented auth and injects host-held credentials | Fake upstream inspects headers; env files checked for secrets | Automated; live Claude run recorded in `spike/RESULTS.md` |
| Credentialed model hosts cannot bypass metering through CONNECT | Credential-host exclusion before tunnel establishment | Denial before upstream | Automated |
| Docker agent cannot reach a host service directly | Internal bridge plus isolated gateway mode | `make test-docker`: same healthy listener reachable before isolation, blocked after; actual gateway remains reachable | Automated, passed on Docker 29.9.1 |
| Root in QEMU guest cannot bypass the network path | Host-side `restrict=on` plus one guestfwd | Original Mac run in RESULTS; revised `provision` records open controls and `verify` repeats them locked | Manual local VM check; see current validation in RESULTS |
| Completed model usage is priced and charged per session | Usage parser and host ledger; next call refused after crossing cap | Anthropic/OpenAI JSON and SSE tests; rebuild gateway and retry | Automated; live Anthropic cap recorded |
| Background OpenAI work is outside this POC | Refused before upstream; response retrieval paths not allowlisted | Rejection tests | Automated |
| Handled gateway decisions are attributed and audited | Capability lookup; route/CONNECT/status audit records | Denial, metering and validation tests | Automated; QEMU packet drops are separate evidence |
| Access stops with the gateway; restart preserves the budget | Gateway owns credentials and ledger | Original live revoke/recovery; persisted-cap test | Recorded live and automated; repeat in handoff order |
| One gateway policy can serve a customer cloud VM | Proposed deployment outside the VM | No cloud account/run | Deferred; not demonstrated |

OpenAI is tested against provider-shaped fake responses, not a live OpenAI
account. The recorded live client is Claude Code. Historical timings and the
original recording describe the run identified in RESULTS, not every later
revision of the kit.

## Sessions and budget semantics

A **session** is a named capability and daily budget identity in policy. It
is not inferred from a process, Claude conversation, VM or developer. Several
processes sharing a capability share its budget. Restarting the gateway or
rebooting the VM does not create a new session or reset its spend.

`--session NAME` on `init`, `serve` and `preflight` selects one explicit
identity. The spike Makefile and VM script use `LEASH_SESSION` (default
`demo`). A fresh demo take uses a new name; previous ledger and audit records
stay intact. This is host-authorized configuration, not something the guest
can use to grant itself another budget. Only the sessions selected by the
running gateway are accepted. `sessions.json` retains old identities; rotating
capabilities and mapping sessions to VM lifetimes are integration work.
`report --json` includes all recorded identities by default; the global
`--session NAME` option filters reporting to that identity without deleting
other evidence. Run without the filter to include unattributed denials.

Caps apply to observed usage using illustrative prices. In-flight calls may
overshoot. Interrupted streams can omit final usage and undercount; the audit
includes `usage_observed`, which means some usage was seen, not that it was
complete. This is a demonstration of usage-based enforcement, not a hard
billing guarantee. OpenAI Chat streams force usage reporting; background
Responses work and retrieval of stored responses are outside the POC.

## The VM spike

`spike/` swaps the container for a real VM, closer to what Ringleader runs on
a Mac. QEMU's user-mode network with `restrict=on` drops every packet the
guest sends except one forward: `10.0.2.100:8080` in the guest, spliced to
leash on the host's loopback. The rule lives in the QEMU process on the host,
so root in the guest has nothing to flush.

```
export LEASH_SESSION=demo-take-1
./leash -c spike/policy.json --session "$LEASH_SESSION" init
./spike/vm.sh provision          # once: network open, install tools, power off
make spike-gw                    # second terminal: the gateway, key from the keychain
./spike/vm.sh up                 # network locked
make spike-preflight            # gateway, enabled route and unused budget
./spike/vm.sh ssh leash/works.sh
make spike-verify               # controlled host listener + locked probes
# Revoke/recovery before cap.sh; follow spike/HANDOFF.md for the full sequence.
# After the acceptance sequence: stop the manual gateway; use an unused take.
LEASH_SESSION=demo-take-2 make spike-record
```

`spike/HANDOFF.md` is the canonical runbook, including repeatable demo state
and revoke/recovery order. `spike/RESULTS.md` records the original Mac/Lima
results and subsequent verification. Provisioning rebuilds the selected VM
disk; use a new `LEASH_VM_STATE` directory when preserving an existing VM.

## What this is not

- **Not novel on its own.** Several tools already ship host-side credential
  injection plus an egress allowlist:
  - [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`)
  - [Claude Code's sandbox](https://code.claude.com/docs/en/sandboxing) (credential masking)
  - [nono](https://nono.sh/), an open-source kernel-level sandbox for
    coding agents (Landlock on Linux, Seatbelt on macOS) from
    [nolabs](https://nolabs.ai/), started by Luke Hinds of Sigstore. Its
    "phantom token" proxy injects real secrets at the network boundary.
  - [Infisical Agent Vault](https://infisical.com/blog/agent-vault-the-open-source-credential-proxy-and-vault-for-agents)
  - [microsandbox](https://github.com/superradcompany/microsandbox)
  
  The point of leash is narrower:
  1. Ringleader's laptop gap (no network rules or credential gateway on Mac
     and Windows) can be explored with a small gateway and host-side VM network
     enforcement. Driver estimates in RESULTS are engineering estimates.
  2. A per-**session** spend cap, enforced where the agent can't reach it,
     is an integration capability to evaluate. The reviewed comparison did
     not identify an equivalent per-session model-token cap; that is not a
     claim that no other product can provide one.
  3. The same gateway and policy file could run in the customer's cloud
     account, next to the firewall rule. "One policy, laptop or cloud" is
     Ringleader's actual claim.
- **Separate boundary mechanisms.** Docker uses an isolated internal bridge;
  the Mac spike uses a real QEMU VM. Neither demonstrates the vz or WSL2 path.
- **Not secret from the agent's own machine.** Anything on the box can use
  the capability while the gateway is up. That is the same trade imp makes:
  a live session is worth inference within the cap, and nothing once the
  gateway stops.
- **No TLS between agent and gateway.** That hop runs on a private network.
- **No interception of TLS on tunnels.** Allowlisted hosts get an opaque
  tunnel, so credentials can only be injected on explicit routes.

- **An allowlist is not data-loss prevention.** An agent can send code to an
  approved provider or publish data through an allowed npm/PyPI tunnel. The
  mechanism bounds destinations; it does not inspect tunnel contents.

## VM driver integration contract

An engineering integration must provide these properties independently of
what environment variables the agent honors:

1. Give the guest exactly the intended outbound path, enforced outside the
   guest. Test direct IP, DNS, host access and guest-root rule changes using
   known working controls. QEMU's mechanism does not establish a vz/WSL2 one.
2. Keep provider credentials, policy, ledger and audit outside guest-writable
   storage. Mount only the intended workspace; no home-directory/keychain
   sharing, Docker control socket, SSH agent forwarding or equivalent host
   authority. The spike's SSH client explicitly disables agent forwarding.
3. Start and supervise the gateway with the VM lifecycle. Use a protected Unix
   socket for a product integration; the POC's TCP listener probe is only a
   guard against accidentally forwarding to a different service.
4. Provision while trusted and open, then run locked. Do not reopen a VM that
   has processed untrusted work to repair package installation. Bake images
   or use a fresh provisioning disk instead.
5. Define the product's budget identity (VM, developer, task or agent run),
   mint/select it on the host, preserve its ledger across restarts, and revoke
   or rotate capabilities when that identity's lifetime ends. A guest reboot
   must not grant a fresh budget.
6. Preserve evidence: handled gateway decisions in the audit; packet-drop
   checks in the acceptance transcript. Label estimated cost, incomplete usage
   and untested driver paths. The cloud experiment remains deferred.
