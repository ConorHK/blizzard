"""Tests which flake inputs count as bumped, and the upstream patch budget."""

import unittest
from typing import ClassVar

from claude_ci.upstream import MAX_COMMITS, changed_inputs, describe


def lock(**revs: str) -> dict:
    """Build a flake.lock with one GitHub input per name."""
    return {"nodes": {
        name: {"locked": {"type": "github", "owner": "o", "repo": name, "rev": rev}} for name, rev in revs.items()
    }}


def compare(total: int, patch: str) -> dict:
    """Build a GitHub compare response with one commit and one file."""
    return {
        "total_commits": total,
        "commits": [{"sha": "a" * 40, "commit": {"message": "fix: thing\n\nbody"}}],
        "files": [{"status": "modified", "filename": "f.nix", "additions": 1, "deletions": 1, "patch": patch}],
    }


class ChangedInputs(unittest.TestCase):
    """changed_inputs finds bumped revisions."""

    def test_only_changed_revs(self) -> None:
        """Unchanged inputs are skipped; new inputs have no old revision."""
        changes = changed_inputs(lock(a="1", b="2"), lock(a="1", b="3", c="4"))
        self.assertEqual([(c["name"], c["old"], c["new"]) for c in changes], [("b", "2", "3"), ("c", None, "4")])


class Describe(unittest.TestCase):
    """describe renders one input within the patch budget."""

    change: ClassVar[dict] = {"name": "b", "type": "github", "owner": "o", "repo": "b", "old": "2" * 40, "new": "3" * 40}

    def test_patch_within_budget(self) -> None:
        """A small patch is included and counted."""
        text, used = describe(self.change, compare(1, "+x"), 100)
        self.assertIn("+x", text)
        self.assertEqual(used, len("--- f.nix\n+x"))

    def test_patch_over_budget(self) -> None:
        """A large patch is named as omitted, never cut silently."""
        text, used = describe(self.change, compare(1, "+" + "x" * 200), 100)
        self.assertIn("Patches omitted", text)
        self.assertNotIn("xxxx", text)
        self.assertEqual(used, 0)

    def test_huge_history(self) -> None:
        """Inputs like nixpkgs get the count only."""
        text, _ = describe(self.change, compare(MAX_COMMITS + 1, "+x"), 100)
        self.assertIn("Too many commits", text)
        self.assertNotIn("fix: thing", text)

    def test_unavailable(self) -> None:
        """A refused comparison and a non-GitHub input say so."""
        self.assertIn("would not compare", describe(self.change, None, 100)[0])
        self.assertIn("Not hosted on GitHub", describe({**self.change, "type": "git"}, None, 100)[0])


if __name__ == "__main__":
    unittest.main()
