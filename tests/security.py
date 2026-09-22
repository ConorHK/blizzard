"""Exercise audited script boundaries."""

import concurrent.futures
import http.client
import importlib.util
import os
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "clip_server", ROOT / "modules/nixos/clip-server.py"
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Missing clipboard module")
CLIP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLIP)
BASH = shutil.which("bash")
if BASH is None:
    raise RuntimeError("Missing Bash")


class ClipTests(unittest.TestCase):
    """Exercise HTTP framing and atomic writes."""

    def setUp(self) -> None:
        """Create isolated fixtures."""
        self.temp = tempfile.TemporaryDirectory()
        CLIP.ROOT = Path(self.temp.name)
        self.server = CLIP.Server(("127.0.0.1", 0), CLIP.Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        """Release isolated fixtures."""
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(
        self,
        method: str,
        path: str,
        body: bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, bytes]:
        """Send a request to the fixture."""
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=3)
        try:
            connection.request(method, path, body, headers or {})
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_slot_collision(self) -> None:
        """Check slot collision."""
        self.assertEqual(self.request("PUT", "/note.tmp", b"original")[0], 200)
        self.assertEqual(self.request("PUT", "/note", b"replacement")[0], 200)
        self.assertEqual(self.request("GET", "/note.tmp"), (200, b"original"))

    def test_concurrent_writes(self) -> None:
        """Check concurrent writes."""
        values = [bytes([index]) * 65536 for index in range(16)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(
                pool.map(lambda body: self.request("PUT", "/shared", body), values)
            )
        self.assertTrue(all(status == 200 for status, _ in results))
        self.assertIn(self.request("GET", "/shared")[1], values)
        self.assertEqual(list((CLIP.ROOT / ".pending").iterdir()), [])

    def test_bad_lengths(self) -> None:
        """Check bad lengths."""
        for length in ("-1", "+1", "invalid", "1,1"):
            with self.subTest(length=length):
                self.assertEqual(
                    self.request("PUT", "/bad", b"x", {"Content-Length": length})[0],
                    400,
                )
        self.assertEqual(self.request("GET", "/bad")[0], 404)

    def test_bad_chunks(self) -> None:
        """Check bad chunks."""
        for body in (b"-1\r\nx\r\n0\r\n\r\n", b"1\r\nxXX0\r\n\r\n", b"100001\r\n"):
            with self.subTest(body=body):
                status, _ = self.request(
                    "PUT", "/bad", body, {"Transfer-Encoding": "chunked"}
                )
                self.assertIn(status, (400, 413))
        self.assertEqual(self.request("GET", "/bad")[0], 404)

    def test_valid_chunks(self) -> None:
        """Check valid chunks."""
        body = b"3\r\nabc\r\n0\r\nTrailer: value\r\n\r\n"
        self.assertEqual(
            self.request("PUT", "/chunk", body, {"Transfer-Encoding": "chunked"})[0],
            200,
        )
        self.assertEqual(self.request("GET", "/chunk"), (200, b"abc"))

    def test_private_paths(self) -> None:
        """Check private paths."""
        for path in ("/.pending", "/..", "/../escaped"):
            self.assertEqual(self.request("PUT", path, b"x")[0], 400)


class ShellTests(unittest.TestCase):
    """Replace privileged tools with harmless fixtures."""

    def setUp(self) -> None:
        """Create isolated fixtures."""
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.env = dict(os.environ, PATH=f"{self.directory}:{os.environ['PATH']}")

    def tearDown(self) -> None:
        """Release isolated fixtures."""
        self.temp.cleanup()

    def executable(self, name: str, body: str) -> None:
        """Install a harmless command fixture."""
        path = self.directory / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + body)
        path.chmod(0o700)

    def run_script(self, path: str, *args: str) -> subprocess.CompletedProcess[str]:
        """Run against stubbed privileged commands."""
        return subprocess.run(  # noqa: S603
            [BASH, str(ROOT / path), *args],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )

    @unittest.skipUnless(shutil.which("bwrap"), "Bubblewrap unavailable")
    def test_jail_boundaries(self) -> None:
        """Keep host controls outside the jail."""
        home = self.directory / "home"
        workspace = self.directory / "workspace"
        workspace.mkdir()
        (home / ".pi/agent/extensions").mkdir(parents=True)
        (home / "private").write_text("hidden")
        env = dict(
            self.env,
            HOME=str(home),
            DBUS_SESSION_BUS_ADDRESS="host-bus",
            SSH_AUTH_SOCK="host-agent",
            PWD=str(workspace),
        )
        probe = """
            set -eu
            test ! -e /nix/var/nix/daemon-socket/socket
            test ! -e "$HOME/private"
            test -z "${DBUS_SESSION_BUS_ADDRESS-}"
            test -z "${SSH_AUTH_SOCK-}"
            test -d "$XDG_RUNTIME_DIR"
            touch "$PWD/ok" "$HOME/.pi/agent/ok"
            if touch "$HOME/.pi/agent/extensions/injected"; then exit 1; fi
        """
        result = subprocess.run(  # noqa: S603
            [
                BASH,
                str(ROOT / "modules/home/core/cli/ai/pi/jail.sh"),
                str(Path(BASH).resolve()),
                "-c",
                probe,
            ],
            cwd=workspace,
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((workspace / "ok").exists())
        self.assertFalse((home / ".pi/agent/extensions/injected").exists())

    def test_snoop_rejects_flags(self) -> None:
        """Check snoop rejects flags."""
        self.executable("podman", 'printf "%s\\n" "$@"\n')
        for args in (
            ("info", "--runtime=/tmp/probe"),
            ("ps", "--cpu-profile=/tmp/file"),
            ("inspect", "--latest"),
            ("logs", "app", "--follow"),
            ("port", "app", "extra"),
            ("run", "image"),
        ):
            with self.subTest(args=args):
                result = self.run_script("modules/nixos/server/snoop-command.sh", *args)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")

    def test_snoop_fixed_commands(self) -> None:
        """Check snoop fixed commands."""
        self.executable("podman", 'printf "%s\\n" "$@"\n')
        for args, expected in (
            (("logs", "app", "40"), ["logs", "--tail", "40", "app"]),
            (("inspect", "app"), ["inspect", "--format", "{{json .State}}", "app"]),
            (("stats",), ["stats", "--no-stream"]),
            (("info",), ["info"]),
        ):
            with self.subTest(args=args):
                result = self.run_script("modules/nixos/server/snoop-command.sh", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), expected)

    def pause_fixtures(self) -> None:
        """Simulate user and system service managers."""
        self.env["RESTIC_PAUSE_STATE"] = str(self.directory / "paused")
        self.env["COMMAND_LOG"] = str(self.directory / "commands")
        self.executable("id", "echo 1001\n")
        self.executable("runuser", 'shift 3\nexec "$@"\n')
        self.executable(
            "systemctl",
            """
            if [ "$1" = --user ]; then shift; fi
            action=$1
            unit=${!#}
            if [ "$action" = show ]; then
                if [ "$unit" = missing ]; then exit 1; fi
                active=active
                if [ "$unit" = stopped ]; then active=inactive; fi
                printf 'LoadState=loaded\\nActiveState=%s\\n' "$active"
            else
                printf '%s %s\\n' "$action" "$unit" >> "$COMMAND_LOG"
                if [ "$action:$unit" = stop:broken ]; then exit 1; fi
                if [ "$action:$unit" = start:restart-fails ]; then exit 1; fi
            fi
        """,
        )

    def test_pause_failure(self) -> None:
        """Restore services after partial stop failures."""
        self.pause_fixtures()
        result = self.run_script(
            "modules/nixos/server/restic/pause.sh",
            "stop",
            "user:running",
            "system:stopped",
            "system:broken",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            (self.directory / "paused").read_text(), "user running\nsystem broken\n"
        )
        result = self.run_script("modules/nixos/server/restic/pause.sh", "start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.directory / "commands").read_text().splitlines(),
            ["stop running", "stop broken", "start running", "start broken"],
        )

    def test_pause_missing(self) -> None:
        """Refuse backups when service state fails."""
        self.pause_fixtures()
        result = self.run_script(
            "modules/nixos/server/restic/pause.sh", "stop", "user:missing"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.directory / "paused").read_text(), "")

    def test_pause_restarts_others(self) -> None:
        """Restart remaining services after one failure."""
        self.pause_fixtures()
        (self.directory / "paused").write_text("system restart-fails\nuser running\n")
        result = self.run_script("modules/nixos/server/restic/pause.sh", "start")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            (self.directory / "commands").read_text().splitlines(),
            ["start restart-fails", "start running"],
        )

    def firewall_stub(self) -> None:
        """Check firewall stub."""
        self.env["RULE_LOG"] = str(self.directory / "rules")
        self.executable("iptables", 'printf "%s\\n" "$*" >> "$RULE_LOG"\n')

    def test_firewall_cleanup(self) -> None:
        """Check firewall cleanup."""
        self.firewall_stub()
        self.executable("python", "exit 7\n")
        result = self.run_script("modules/packages/serve-here.sh", "8000")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(
            (self.directory / "rules").read_text().splitlines(),
            [
                "-I nixos-fw -p tcp --dport 8000 -j ACCEPT",
                "-D nixos-fw -p tcp --dport 8000 -j ACCEPT",
            ],
        )

    def test_signal_cleanup(self) -> None:
        """Check signal cleanup."""
        self.firewall_stub()
        ready = self.directory / "ready"
        self.env["READY"] = str(ready)
        self.executable("python", 'echo "$$" > "$READY"\nexec sleep 30\n')
        process = subprocess.Popen(  # noqa: S603
            [BASH, str(ROOT / "modules/packages/serve-here.sh")], env=self.env
        )
        try:
            deadline = time.monotonic() + 3
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists())
            process.send_signal(signal.SIGTERM)
            self.assertEqual(process.wait(timeout=3), 143)
            self.assertIn("-D nixos-fw", (self.directory / "rules").read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(int(ready.read_text()), 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


class ImageTests(unittest.TestCase):
    """Keep image pins inside Renovate coverage."""

    def test_image_policy(self) -> None:
        """Check every production image declaration."""
        import json
        import re

        config = json.loads((ROOT / "renovate.json").read_text())
        pattern = config["customManagers"][0]["matchStrings"][0]
        matcher = re.compile(pattern.replace("(?<", "(?P<"))
        count = 0
        for path in (ROOT / "modules/nixos/server").rglob("*.nix"):
            if path.name.endswith("tests.nix"):
                continue
            source = path.read_text()
            images = re.findall(r'(?:image|dawarichImage) = "([^"\n]+)";', source)
            matches = list(matcher.finditer(source))
            self.assertEqual(len(images), len(matches), str(path))
            for image, match in zip(images, matches, strict=True):
                self.assertRegex(image, r"@sha256:[a-f0-9]{64}$")
                self.assertEqual(
                    image,
                    match["depName"]
                    + ":"
                    + match["currentValue"]
                    + "@"
                    + match["currentDigest"],
                )
                count += 1
        self.assertGreater(count, 20)


if __name__ == "__main__":
    unittest.main()
