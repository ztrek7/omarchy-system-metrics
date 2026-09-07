"""Exercise the latency helper with a fake ping; no network requests."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LatencyTests(unittest.TestCase):
    def probe(self, target, output, exit_code=0):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            ping = directory / "ping"
            ping.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "with open(os.environ['PROBE_ARGS'], 'w') as log:\n"
                "    json.dump(sys.argv[1:], log)\n"
                "assert os.environ['LC_ALL'] == 'C'\n"
                "print(os.environ['PROBE_OUTPUT'])\n"
                "sys.exit(int(os.environ['PROBE_EXIT']))\n"
            )
            ping.chmod(0o755)
            args_file = directory / "args.json"
            env = dict(os.environ)
            env.update(
                PATH=str(directory) + os.pathsep + env["PATH"],
                PROBE_ARGS=str(args_file),
                PROBE_OUTPUT=output,
                PROBE_EXIT=str(exit_code),
            )
            result = subprocess.run(
                ["bash", str(ROOT / "latency.sh"), target],
                env=env, capture_output=True, text=True, check=True, timeout=5,
            )
            return result.stdout.strip(), json.loads(args_file.read_text())

    def test_round_trip(self):
        value, args = self.probe(
            "192.0.2.1",
            "rtt min/avg/max/mdev = 12.345/12.345/12.345/0.000 ms",
        )
        self.assertEqual(value, "12.345")
        self.assertEqual(args, ["-n", "-q", "-c", "1", "-W", "1", "--", "192.0.2.1"])

    def test_unreachable(self):
        value, _ = self.probe("192.0.2.1", "100% packet loss", exit_code=1)
        self.assertEqual(value, "-1")

    def test_unparseable_response(self):
        value, _ = self.probe("192.0.2.1", "unexpected response")
        self.assertEqual(value, "-1")

    def test_target_cannot_add_ping_options(self):
        value, args = self.probe("-f", "", exit_code=2)
        self.assertEqual(value, "-1")
        self.assertEqual(args[-2:], ["--", "-f"])

    def test_target_is_a_literal_argument(self):
        target = "$(printf unexpected); example.invalid"
        _, args = self.probe(target, "", exit_code=2)
        self.assertEqual(args[-1], target)


if __name__ == "__main__":
    unittest.main()
