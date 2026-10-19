# leash

Keep a coding agent's credentials, egress and spend outside the machine it
runs on. A throwaway proof of concept, in the spirit of
[imp](https://github.com/metcalfc/imp): the agent gets a per-session
**capability**, never a credential.

```
make test        # 13 tests, loopback only, no docker, no keys
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
| **audit** | one JSON line per decision, allow or deny, attributed to the session; never headers, never bodies | — |

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
`internal: true` network: no default route, no outbound NAT, no host. The
gateway is the only thing on it that also touches the outside.

Two smaller rules worth noticing:

- A host that has a credentialed route can't also be tunnelled to. Otherwise
  `CONNECT api.anthropic.com` would bypass injection, metering and the cap.
- Spend is charged before the client sees the end of the response, so the
  agent's next call can't beat the ledger. Calls already in flight can still
  overshoot, which is the same caveat Ringleader's own cap has.

## Running it

```sh
make init     # mints capabilities, writes run/<session>.env (0600, no secrets)

# Real keys go to the gateway container only, straight out of your keychain:
ANTHROPIC_API_KEY=$(security find-generic-password -s anthropic -w) \
GITHUB_TOKEN=$(gh auth token) \
make up

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

## Verified

- **Unit tests:** `make test`, 13 of them, against fake upstreams. They cover:
  - the key swap, and the OAuth/Max beta header (the same fix as imp);
  - refusal before upstream;
  - path traversal;
  - git's Basic-auth challenge;
  - SSE and JSON metering;
  - the per-session cap, including that it survives a restart;
  - the egress allowlist, port rules and credentialed-host rules;
  - env files holding no secrets.
- **End to end, on real containers:** a Docker internal network, with a curl container standing in for the agent:
  - a direct connection fails to resolve;
  - `example.com` is refused with 403;
  - tunnelling to `api.anthropic.com` is refused with 403;
  - a real-looking key without a capability is refused with 401;
  - every decision lands in the audit log, attributed to `chad-claude`.
- **Not verified:** a live Claude Code session. The machine this was built on intercepts outbound TLS, so upstream calls failed there for reasons unrelated to leash.

## The VM spike

`spike/` swaps the container for a real VM, closer to what Ringleader runs on
a Mac. QEMU's user-mode network with `restrict=on` drops every packet the
guest sends except one forward: `10.0.2.100:8080` in the guest, spliced to
leash on the host's loopback. The rule lives in the QEMU process on the host,
so root in the guest has nothing to flush.

```
./leash -c spike/policy.json init
./spike/vm.sh provision          # once: network open, install tools, power off
make spike-gw                    # second terminal: the gateway, key from the keychain
./spike/vm.sh up                 # network locked
./spike/vm.sh ssh                # then ~/leash/works.sh, attack.sh, cap.sh
make spike-record                # the demo, via VHS
```

`spike/HANDOFF.md` is the brief for running it on a Mac. `spike/RESULTS.md`
is where the numbers go.

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
     and Windows) is a few hundred lines in front of the VM's network, not a
     quarter of work.
  2. A per-**session** spend cap, enforced where the agent can't reach it,
     is the piece nobody in that list has.
  3. The same gateway and policy file could run in the customer's cloud
     account, next to the firewall rule. "One policy, laptop or cloud" is
     Ringleader's actual claim.
- **Not a VM boundary.** A container on an internal network stands in for
  Ringleader's VM. The gateway in front of it doesn't care which it is.
- **Not secret from the agent's own machine.** Anything on the box can use
  the capability while the gateway is up. That is the same trade imp makes:
  a live session is worth inference within the cap, and nothing once the
  gateway stops.
- **No TLS between agent and gateway.** That hop runs on a private network.
- **No interception of TLS on tunnels.** Allowlisted hosts get an opaque
  tunnel, so credentials can only be injected on explicit routes.
