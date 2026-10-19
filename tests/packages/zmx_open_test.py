"""Tests zmx-open's session naming and ssh parsing."""

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType


def load(path: str) -> ModuleType:
    """Import a script by path."""
    spec = importlib.util.spec_from_file_location("zmx_open", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


zmx = load(sys.argv.pop(1))


class SshDestination(unittest.TestCase):
    """ssh_destination finds the host in an ssh argv."""

    def test_skips_flag_values(self) -> None:
        """Flag values are not the host."""
        argv = ["ssh", "-p", "22", "-o", "A=b", "me@box"]
        self.assertEqual(zmx.ssh_destination(argv), "box")

    def test_bundled_flags(self) -> None:
        """Bundled flags take no value."""
        self.assertEqual(zmx.ssh_destination(["/bin/ssh", "-tt", "box", "ls"]), "box")

    def test_not_ssh(self) -> None:
        """Other commands have no destination."""
        self.assertEqual(zmx.ssh_destination(["vim", "box"]), "")
        self.assertEqual(zmx.ssh_destination([]), "")


class SplitCwd(unittest.TestCase):
    """split_cwd parses OSC 7 cwd reports."""

    def test_url(self) -> None:
        """Hosts are shortened and paths unquoted."""
        url = "file://dullahan.lan/home/a%20b"
        self.assertEqual(zmx.split_cwd(url), ("dullahan", "/home/a b"))

    def test_plain_path(self) -> None:
        """A bare path has no host."""
        self.assertEqual(zmx.split_cwd("/srv/x"), ("", "/srv/x"))


class Names(unittest.TestCase):
    """Session names stay valid and unique."""

    def test_sanitize(self) -> None:
        """Dots and spaces become dashes, capped at 32."""
        self.assertEqual(zmx.sanitize("my.repo name!"), "my-repo-name")
        self.assertEqual(len(zmx.sanitize("x" * 40)), 32)

    def test_next_session(self) -> None:
        """The first free slot wins."""
        self.assertEqual(zmx.next_session({"a.1", "a.2", "b.1"}, "a"), "a.3")


class ProjectName(unittest.TestCase):
    """project_name names a directory by its repo."""

    def setUp(self) -> None:
        """Point HOME at a scratch directory."""
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.home = Path(scratch.name)
        os.environ["HOME"] = str(self.home)

    def test_repo_root(self) -> None:
        """A subdirectory takes the repo's name."""
        sub = self.home / "blizzard" / "modules"
        sub.mkdir(parents=True)
        (self.home / "blizzard" / ".jj").mkdir()
        self.assertEqual(zmx.project_name(sub), "blizzard")

    def test_plain_dir(self) -> None:
        """Outside a repo, the directory names itself."""
        notes = self.home / "notes"
        notes.mkdir()
        self.assertEqual(zmx.project_name(notes), "notes")

    def test_home(self) -> None:
        """HOME is home."""
        self.assertEqual(zmx.project_name(self.home), "home")


if __name__ == "__main__":
    unittest.main()
