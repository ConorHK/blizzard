"""Tests how the zmx switcher reports each host."""

import importlib.util
import sys
import unittest
from collections.abc import Callable
from pathlib import Path
from types import ModuleType


def result_handler(**_: object) -> Callable[[Callable], Callable]:
    """Stand in for kitty's decorator."""
    return lambda handler: handler


def stub(name: str, **attrs: object) -> None:
    """Register a fake kitty module."""
    module = ModuleType(name)
    vars(module).update(attrs)
    sys.modules[name] = module


stub("kittens")
stub("kittens.tui")
stub("kittens.tui.handler", result_handler=result_handler)
stub("kitty")
stub("kitty.utils", path_from_osc7_url=str)

kitty_dir = Path(sys.argv.pop(1))
sys.path.insert(0, str(kitty_dir))
spec = importlib.util.spec_from_file_location("zmx_switch", kitty_dir / "zmx-switch.py")
switch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(switch)

REMOTE = "far-away-host"


class Query(unittest.TestCase):
    """query labels why a host has no sessions."""

    def run_as(self, script: str) -> dict:
        """Query a remote host whose list command runs script."""
        switch.list_command = lambda _host: ["sh", "-c", script]
        return switch.query(REMOTE)

    def test_sessions(self) -> None:
        """A good report lists its sessions."""
        report = self.run_as("""echo '{"sessions": [{"name": "a.1"}]}'""")
        self.assertEqual(report["sessions"], [{"name": "a.1"}])
        self.assertNotIn("error", report)

    def test_ssh_failure(self) -> None:
        """Exit 255 from ssh means unreachable."""
        self.assertEqual(self.run_as("exit 255")["error"], "unreachable")

    def test_old_helper(self) -> None:
        """A reachable host without --list is not unreachable."""
        report = self.run_as("echo 'usage: zmx-open'; exit 2")
        self.assertEqual(report["error"], "cannot list sessions")

    def test_timeout(self) -> None:
        """A slow host times out."""
        timeout = switch.TIMEOUT
        switch.TIMEOUT = 0.2
        self.addCleanup(setattr, switch, "TIMEOUT", timeout)
        self.assertEqual(self.run_as("sleep 5")["error"], "timed out")

    def test_header(self) -> None:
        """The host header shows the reason."""
        entries = switch.build_entries([switch.failed(REMOTE, "timed out")])
        self.assertEqual(entries[0], (None, f"{REMOTE} (timed out)"))


if __name__ == "__main__":
    unittest.main()
