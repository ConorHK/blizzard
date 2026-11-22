"""Hard rules the model cannot override: which PRs qualify, CI state, and which diffs may merge."""

import re
from dataclasses import dataclass, field

# Renovate runs with the workflow token, so its PRs come from github-actions.
# gh names bot authors app/<slug>; the REST API names them <slug>[bot].
BOTS = {
    "app/github-actions": "renovate/",
    "github-actions[bot]": "renovate/",
    "app/dependabot": "dependabot/",
    "dependabot[bot]": "dependabot/",
}
FIX_TRAILER = "Claude-CI-Fix: true"
MAX_FIXES = 2

GREEN = {"success", "skipped", "neutral"}
RED = {"failure", "timed_out", "action_required", "startup_failure"}

IMAGE_LINE = re.compile(r'^\s*image\s*=\s*"[^"]*";\s*$')
RENOVATE_COMMENT = re.compile(r"^\s*#\s*renovate:\s")
ACTION_LINE = re.compile(r"^\s*(-\s*)?uses:\s*\S+@\S+\s*(#.*)?$")

# No commit from a bot or the fixer may touch these.
FORBIDDEN = (
    re.compile(r"(^|/)\.secrets/"),
    re.compile(r"\.age$"),
    re.compile(r"^modules/nixos/server/github-runner/"),
    re.compile(r"^modules/packages/claude-ci"),
    re.compile(r"^\.github/(?!workflows/)"),
)
WORKFLOW = re.compile(r"^\.github/workflows/[^/]+\.ya?ml$")


def is_bot_pr(pr: dict) -> bool:
    """Tell whether a PR comes from Renovate or Dependabot on their own branch."""
    login = (pr.get("author") or {}).get("login", "")
    prefix = BOTS.get(login)
    return bool(
        prefix
        and pr["headRefName"].startswith(prefix)
        and not pr.get("isCrossRepository")
        and not pr.get("isDraft")
        and pr.get("baseRefName") == "main"
    )


def ci_state(check_runs: list[dict], statuses: list[dict], own: str) -> str:
    """Return pending, green or red for a head commit; `own` names the dispatching job."""
    runs = [r for r in check_runs if r["name"] != own]
    if not any(r["name"] == "check" for r in runs):
        return "pending"
    if any(r["status"] == "completed" and r["conclusion"] in RED for r in runs):
        return "red"
    if any(s["state"] in ("failure", "error") for s in statuses):
        return "red"
    if any(r["status"] != "completed" or r["conclusion"] not in GREEN for r in runs):
        return "pending"
    if any(s["state"] != "success" for s in statuses):
        return "pending"
    return "green"


def changed_lines(patch: str) -> list[str]:
    """Return a patch's added and removed lines without their marker."""
    return [
        line[1:]
        for line in patch.splitlines()
        if line[:1] in "+-" and not line.startswith(("+++", "---"))
    ]


@dataclass
class Verdict:
    """Whether the gate passes, and why not."""

    ok: bool = True
    reasons: list[str] = field(default_factory=list)

    def block(self, reason: str) -> None:
        """Fail the gate with a reason."""
        self.ok = False
        self.reasons.append(reason)


def bot_change_ok(path: str, patch: str | None) -> str | None:
    """Return why a bot's change to one file needs a human, or None."""
    if path == "flake.lock":
        return None
    if path.endswith(("package.json", "package-lock.json")):
        return None
    if patch is None:
        return f"{path}: no text diff to check"
    lines = changed_lines(patch)
    if WORKFLOW.match(path):
        rule = ACTION_LINE
    elif path.endswith(".nix"):
        bad = [line for line in lines if not (IMAGE_LINE.match(line) or RENOVATE_COMMENT.match(line))]
        return f"{path}: changes more than image lines" if bad else None
    else:
        return f"{path}: not a file the bots update"
    return None if all(rule.match(line) for line in lines) else f"{path}: changes more than action pins"


def merge_gate(files: list[dict], fixer_files: set[str]) -> Verdict:
    """Check GitHub's PR files against the bot rules, exempting files the fixer touched."""
    verdict = Verdict()
    for f in files:
        path = f["filename"]
        if any(rule.search(path) for rule in FORBIDDEN):
            verdict.block(f"{path}: protected path")
        elif path in fixer_files:
            if WORKFLOW.match(path):
                verdict.block(f"{path}: the fixer may not edit workflows")
        elif reason := bot_change_ok(path, f.get("patch")):
            verdict.block(reason)
    return verdict


def writable(path: str) -> bool:
    """Tell whether the fixer may write a repo-relative path."""
    if path.startswith(("/", "../", ".git/")) or "/../" in path or path == ".git":
        return False
    return not WORKFLOW.match(path) and not any(rule.search(path) for rule in FORBIDDEN)
