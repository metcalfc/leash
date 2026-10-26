#!/usr/bin/env python3
"""Opt-in Docker acceptance check. Builds the real gateway; uses no provider keys.

A healthy host listener is reachable on a plain internal bridge, unreachable
from the isolated agent bridge, and the actual leash gateway remains reachable.
All containers, networks and the test image are removed, even after a failure.
"""
from __future__ import annotations

import json
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def docker(*args: str) -> str:
    return subprocess.check_output(["docker", *args], text=True, cwd=ROOT).strip()


def main() -> None:
    version = docker("version", "--format", "{{.Server.Version}}")
    if int(version.split(".")[0]) < 28:
        raise SystemExit("Docker Engine 28+ is required for isolated bridge gateways")
    # Read the checked-in network settings. If compose.yaml loses isolation,
    # this test must fail rather than validating a separate hardcoded setup.
    configuration = json.loads(docker(
        "compose", "config", "--no-env-resolution", "--no-interpolate", "--format", "json",
    ))
    agentnet = configuration["networks"]["agentnet"]
    if not agentnet.get("internal"):
        raise SystemExit("agentnet must be internal")
    name = "leash-check-" + uuid.uuid4().hex[:10]
    image, control, isolated = name + ":test", name + "-control", name + "-isolated"
    listener, gateway = name + "-host", name + "-gateway"
    try:
        subprocess.run(["docker", "build", "-t", image, "."], cwd=ROOT, check=True)
        docker("network", "create", "--internal", control)
        host_ip = docker("network", "inspect", control, "--format", "{{(index .IPAM.Config 0).Gateway}}")
        options = []
        for key, value in agentnet.get("driver_opts", {}).items():
            options.extend(["-o", f"{key}={value}"])
        docker("network", "create", "--internal", *options, isolated)
        server = (
            "import socket; s=socket.socket(); s.bind(('0.0.0.0',0)); s.listen(); "
            "print(s.getsockname()[1],flush=True)\n"
            "while True:\n c,_=s.accept(); c.sendall(b'HOST_CONTROL'); c.close()"
        )
        docker("run", "-d", "--name", listener, "--network", "host", "--entrypoint", "python3", image, "-uc", server)
        port = ""
        for _ in range(50):
            port = docker("logs", listener)
            if port:
                break
            time.sleep(0.1)
        if not port.isdigit():
            raise RuntimeError("host control listener did not start")
        probe = (
            "import socket,sys; "
            "s=socket.create_connection((sys.argv[1],int(sys.argv[2])),3); "
            "assert s.recv(64)==b'HOST_CONTROL'; print('host reachable')"
        )
        docker("run", "--rm", "--user", "1000", "--network", control, "--entrypoint", "python3",
               image, "-c", probe, host_ip, port)
        print("PASS: non-root positive control reaches the healthy host listener")
        blocked_probe = (
            "import socket,sys,errno\n"
            "try:\n s=socket.create_connection((sys.argv[1],int(sys.argv[2])),3)\n"
            "except OSError as e:\n"
            " allowed=(errno.ENETUNREACH,errno.EHOSTUNREACH,errno.ECONNREFUSED)\n"
            " assert isinstance(e,TimeoutError) or e.errno in allowed,e\n"
            " print('host blocked')\n"
            "else:\n s.close(); raise SystemExit('FAIL: isolated agent reached the host')"
        )
        docker("run", "--rm", "--user", "1000", "--network", isolated, "--entrypoint", "python3",
               image, "-c", blocked_probe, host_ip, port)
        # Recheck the same listener so its failure cannot masquerade as isolation.
        docker("run", "--rm", "--user", "1000", "--network", control, "--entrypoint", "python3",
               image, "-c", probe, host_ip, port)
        print("PASS: isolated agent cannot reach that same, still-healthy host listener")
        docker("run", "-d", "--name", gateway, "--network", isolated, image)
        docker("network", "connect", control, gateway)
        gateway_probe = (
            "import http.client,sys,time\n"
            "for i in range(50):\n"
            " try:\n"
            "  c=http.client.HTTPConnection(sys.argv[1],8080,timeout=2)\n"
            "  c.request('GET','/leash-probe/'); r=c.getresponse()\n"
            "  assert r.status==404 and b'no route /leash-probe/' in r.read(); break\n"
            " except OSError:\n  time.sleep(.1)\n"
            "else:\n raise SystemExit('FAIL: gateway unreachable')\n"
            "print('gateway reachable')"
        )
        docker("run", "--rm", "--user", "1000", "--network", isolated, "--entrypoint", "python3",
               image, "-c", gateway_probe, gateway)
        print("PASS: isolated agent can reach the actual leash gateway")
        print(json.dumps({"docker": version, "result": "passed", "provider_calls": 0}))
    finally:
        for container in (gateway, listener):
            subprocess.run(["docker", "rm", "-f", container], capture_output=True)
        for network in (isolated, control):
            subprocess.run(["docker", "network", "rm", network], capture_output=True)
        subprocess.run(["docker", "image", "rm", image], capture_output=True)


if __name__ == "__main__":
    main()
