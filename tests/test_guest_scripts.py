"""Exercise failure reporting without a VM, sudo, real keys or provider calls."""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

GUEST = Path(__file__).resolve().parent.parent / "spike/guest"


class GuestScriptsTest(unittest.TestCase):
    def test_missing_probe_command_is_a_test_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dirname = Path(directory) / "dirname"
            dirname.write_text('#!/bin/bash\nprintf "%s\\n" "${1%/*}"\n')
            dirname.chmod(0o755)
            result = subprocess.run(
                ["/bin/bash", str(GUEST / "attack.sh")], text=True, capture_output=True,
                env={**os.environ, "PATH": directory},
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("required tool missing: curl", result.stderr)
        self.assertNotIn("PASS", result.stdout)

    def test_probe_does_not_turn_command_or_tls_errors_into_blocks(self) -> None:
        for status in (35, 127):
            with self.subTest(status=status):
                result = subprocess.run(
                    ["/bin/bash", "-c", 'source "$1"; raw() { return "$2"; }; '
                     'code=0; probe https https://example.com || code=$?; echo "$code"',
                     "test", str(GUEST / "network.sh"), str(status)],
                    text=True, capture_output=True, check=True,
                )
                self.assertEqual(result.stdout.strip(), "2")

    def test_cap_script_distinguishes_auth_failure_from_cap_refusal(self) -> None:
        for message, expected in (("authentication failed", 2), ("leash: daily spend cap reached", 0)):
            with self.subTest(message=message), tempfile.TemporaryDirectory() as directory:
                claude = Path(directory) / "claude"
                claude.write_text(f"#!/bin/bash\necho '{message}'\nexit 1\n")
                claude.chmod(0o755)
                result = subprocess.run(
                    ["/bin/bash", str(GUEST / "cap.sh"), "1"], text=True, capture_output=True,
                    env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"]},
                )
                self.assertEqual(result.returncode, expected)
                self.assertNotIn(": ok", result.stdout)
                self.assertIn("REFUSED" if expected == 0 else "ERROR", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
