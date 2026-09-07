"""DNS selection fixtures contain documentation addresses, not host settings."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "latency.sh"


class DnsTargetTests(unittest.TestCase):
    def status_target(self, status):
        return subprocess.check_output(
            ["bash", "-c", 'source "$1"; dns_from_status', "test", str(SCRIPT)],
            input=status, text=True, timeout=5,
        ).strip()

    def configured_target(self, config, status="", status_exit=0):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            resolver_file = directory / "resolv.conf"
            resolver_file.write_text(config)
            resolver = directory / "resolvectl"
            resolver.write_text(
                '#!/usr/bin/env bash\n'
                '[[ "$*" == "--no-pager status" ]] || exit 9\n'
                'printf "%s\\n" "$DNS_TEST_STATUS"\n'
                'exit "$DNS_TEST_EXIT"\n'
            )
            resolver.chmod(0o755)
            env = dict(os.environ)
            env.update(PATH=str(directory) + os.pathsep + env["PATH"],
                       DNS_TEST_STATUS=status, DNS_TEST_EXIT=str(status_exit))
            return subprocess.check_output(
                ["bash", "-c", 'source "$1"; dns_target "$2"',
                 "test", str(SCRIPT), str(resolver_file)],
                env=env, text=True, timeout=5,
            ).strip()

    def test_static_dns_takes_precedence_over_resolved(self):
        self.assertEqual(self.configured_target(
            "# comment\nnameserver 192.0.2.53\nnameserver 192.0.2.54\n",
            "Global\n DNS Servers: 198.51.100.53\n"), "192.0.2.53")

    def test_ipv6_static_dns(self):
        self.assertEqual(self.configured_target("nameserver 2001:db8::53\n"), "2001:db8::53")

    def test_default_dns_link_beats_domain_specific_vpn(self):
        self.assertEqual(self.status_target("""Global
  DNS Servers: 203.0.113.53
Link 2 (vpn-test)
  Protocols: -DefaultRoute
  Current DNS Server: 192.0.2.53
  DNS Domain: ~internal.example
Link 3 (eth-test)
  Protocols: +DefaultRoute
  Current DNS Server: 198.51.100.54
  DNS Servers: 198.51.100.53 198.51.100.54
"""), "198.51.100.54")

    def test_catch_all_vpn_wins(self):
        self.assertEqual(self.status_target("""Global
  DNS Servers: 203.0.113.53
Link 2 (eth-test)
  Protocols: +DefaultRoute
  Current DNS Server: 198.51.100.53
Link 3 (vpn-test)
  Protocols: -DefaultRoute
  Current DNS Server: 192.0.2.53
  DNS Domain: ~internal.example
              ~.
"""), "192.0.2.53")

    def test_first_server_when_none_is_current(self):
        self.assertEqual(self.status_target("""Link 2 (eth-test)
  DNS Servers: 192.0.2.53 192.0.2.54
  Default Route: yes
"""), "192.0.2.53")

    def test_global_fallback(self):
        self.assertEqual(self.status_target("Global\n DNS Servers: 192.0.2.53\n"), "192.0.2.53")

    def test_stub_uses_upstream(self):
        for stub in ("127.0.0.53", "127.0.0.54"):
            self.assertEqual(self.configured_target(
                f"nameserver {stub}\n", "Global\n Current DNS Server: 192.0.2.53\n"), "192.0.2.53")

    def test_scoped_ipv6_and_tls_name(self):
        for address, expected in (("[2001:db8::53]:853#dns.example", "2001:db8::53"),
                                  ("fe80::53", "fe80::53%eth-test"),
                                  ("fe80::53%eth-test", "fe80::53%eth-test"),
                                  ("192.0.2.53:853#dns.example", "192.0.2.53")):
            self.assertEqual(self.status_target(
                f"Link 2 (eth-test)\n Protocols: +DefaultRoute\n Current DNS Server: {address}\n"), expected)

    def test_no_public_or_loopback_fallback(self):
        for config, status, code in (("", "", 0),
                                     ("nameserver 127.0.0.1\n", "", 0),
                                     ("nameserver ::1\n", "", 0),
                                     ("nameserver 127.0.0.53\n", "", 1),
                                     ("nameserver 127.0.0.53\n", "Global\n DNS Servers: 127.0.0.1\n", 0),
                                     ("nameserver 127.0.0.53\n", "Link 2 (vpn-test)\n DNS Servers: 192.0.2.53\n DNS Domain: ~internal.example\n", 0)):
            self.assertEqual(self.configured_target(config, status, code), "")

    def test_default_mode_discovers_dns(self):
        result = subprocess.check_output(
            ["bash", "-c", 'source "$1"; dns_target() { printf "\\n"; }; main', "test", str(SCRIPT)],
            text=True, timeout=5,
        ).strip()
        self.assertEqual(result, "-1")


if __name__ == "__main__":
    unittest.main()
