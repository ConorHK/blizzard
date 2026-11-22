"""One pass over the open bot PRs: merge the green ones Claude approves, fix the red ones it can."""

import argparse
import json
import subprocess
import sys
import tempfile
import traceback
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from . import claude, upstream
from .gate import FIX_TRAILER, MAX_FIXES, ci_state, is_bot_pr, merge_gate
from .gh import GitHub

# The build.yml job that dispatches this one; its own check run must not block the gate.
OWN_JOB = "claude-ci"
FIXER = ("github-actions[bot]", "41898282+github-actions[bot]@users.noreply.github.com")
LOG_LINES = 1500


def git(*args: str, cwd: Path | None = None) -> str:
    """Run git and return its output."""
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout  # noqa: S603, S607


def fix_commits(gh: GitHub, number: int) -> list[dict]:
    """List the PR's commits that the fixer pushed."""
    return [
        c for c in gh.commits(number)
        if FIX_TRAILER in c["commit"]["message"] and (c.get("committer") or {}).get("login") == FIXER[0]
    ]


def review_lines(r: claude.Review) -> list[str]:
    """Format a review as comment lines."""
    lines = [f"**Claude review: {r.verdict}**", "", r.summary]
    for title, items in (("Security concerns", r.security_concerns), ("Breaking risks", r.breaking_risks)):
        if items:
            lines += ["", f"{title}:", *[f"- {item}" for item in items]]
    return lines


def handle_green(gh: GitHub, pr: dict) -> None:
    """Gate, review and maybe merge a green PR, once per head commit."""
    number, sha = pr["number"], pr["headRefOid"]
    if gh.has_marker(number, "review", sha):
        return
    fixes = fix_commits(gh, number)
    fixer_files = {f for c in fixes for f in gh.commit_files(c["sha"])}
    gate = merge_gate(gh.files(number), fixer_files)
    if not gate.ok:
        body = ["**Not auto-merging.** This diff needs a human:", *[f"- {r}" for r in gate.reasons]]
        gh.comment(number, "review", sha, "\n".join(body))
        return
    try:
        base = gh.api(f"pulls/{number}")["base"]["sha"]
        review = claude.review(pr, gh.diff(number), upstream.report(gh, base, sha))
    except claude.RefusedError as e:
        gh.comment(number, "review", sha, f"**Claude review failed:** {e}. Leaving this for a human.")
        return
    body = review_lines(review)
    if review.verdict == "approve" and fixes:
        # Fixer commits read untrusted logs, so the owner merges them, never Claude.
        body += ["", "**Contains Claude fix commits: waiting for the owner to merge.**"]
    elif review.verdict == "approve":
        try:
            gh.merge(number, sha)
            gh.dispatch("build.yml", "main")
            body += ["", "Merged."]
        except subprocess.CalledProcessError as e:
            body += ["", f"Merge failed: {e.stderr.strip()}"]
    gh.comment(number, "review", sha, "\n".join(body))


@contextmanager
def worktree(branch: str) -> Iterator[Path]:
    """Check the PR branch out beside the main checkout."""
    with tempfile.TemporaryDirectory(prefix="claude-ci-") as tmp:
        path = Path(tmp) / "repo"
        git("fetch", "origin", f"refs/heads/{branch}")
        git("worktree", "add", "--detach", str(path), "FETCH_HEAD")
        try:
            yield path
        finally:
            git("worktree", "remove", "--force", str(path))


def attr_names(path: Path, attr: str) -> set[str]:
    """List a flake attribute set's names."""
    out = subprocess.run(  # noqa: S603
        ["nix", "--extra-experimental-features", "pipe-operators", "eval", "--json", f".#{attr}", "--apply", "builtins.attrNames"],  # noqa: S607
        cwd=path, check=True, capture_output=True, text=True,
    ).stdout
    return set(json.loads(out))


def handle_red(gh: GitHub, pr: dict) -> None:
    """Diagnose a red PR's failed build, once per run attempt: rerun, fix, or leave it."""
    number, sha, branch = pr["number"], pr["headRefOid"], pr["headRefName"]
    run = gh.failed_run(sha, "build.yml")
    # A rerun is a new attempt, so its failure gets its own diagnosis.
    key = f"{sha}-{run['attempt']}" if run else sha
    if gh.has_marker(number, "fix", key):
        return
    if not run:
        gh.comment(number, "fix", key, "**Claude fixer:** no failed build.yml run to read (container-smoke failures need a human).")
        return
    if len(fix_commits(gh, number)) >= MAX_FIXES:
        gh.comment(number, "fix", key, f"**Claude fixer:** still failing after {MAX_FIXES} fix commits. Leaving this for a human.")
        return
    logs = gh.failed_logs(run["id"])
    lines = logs.splitlines()
    if len(lines) > LOG_LINES:
        logs = f"(showing the last {LOG_LINES} of {len(lines)} lines)\n" + "\n".join(lines[-LOG_LINES:])
    diff = gh.diff(number)
    try:
        diagnosis = claude.diagnose(pr, diff, logs)
    except claude.RefusedError as e:
        gh.comment(number, "fix", key, f"**Claude fixer failed:** {e}.")
        return
    head = f"**Claude diagnosis: {diagnosis.category}** ({diagnosis.failing_target})\n\n{diagnosis.explanation}"
    if diagnosis.category == "infrastructure":
        if run["attempt"] == 1:
            gh.rerun_failed(run["id"])
            gh.comment(number, "fix", key, f"{head}\n\n**Rerunning the failed jobs once.**")
        else:
            gh.comment(number, "fix", key, f"{head}\n\nAlready rerun once; leaving this for a human.")
        return
    if diagnosis.category != "blizzard_config":
        gh.comment(number, "fix", key, f"{head}\n\nNot a blizzard change, so no fix attempted.")
        return
    agents = Path("AGENTS.md").read_text()
    with worktree(branch) as path:
        ws = claude.Workspace(path, attr_names(path, "checks.x86_64-linux"), attr_names(path, "nixosConfigurations"))
        fixed, summary = claude.fix(pr, diff, logs, diagnosis, ws, agents)
        changed = git("status", "--porcelain", cwd=path).strip()
        if not (fixed and changed):
            gh.comment(number, "fix", key, f"{head}\n\n**No fix pushed.** {summary}")
            return
        title = f"fix: adapt blizzard to {pr['title']}"[:72]
        git("add", "-A", cwd=path)
        git("-c", f"user.name={FIXER[0]}", "-c", f"user.email={FIXER[1]}",
            "commit", "-m", f"{title}\n\n{summary}\n\n{FIX_TRAILER}", cwd=path)
        # No force: if the bot pushed meanwhile, this fails and the next pass retries.
        git("push", "origin", f"HEAD:refs/heads/{branch}", cwd=path)
    gh.dispatch("build.yml", branch)
    gh.comment(number, "fix", key, f"{head}\n\n**Pushed a fix.** {summary}")


def main() -> None:
    """Process every open bot PR once."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="owner/name")
    args = parser.parse_args()
    gh = GitHub(args.repo)
    failed = False
    for pr in filter(is_bot_pr, gh.open_prs()):
        state = ci_state(gh.check_runs(pr["headRefOid"]), gh.statuses(pr["headRefOid"]), OWN_JOB)
        print(f"#{pr['number']} {pr['headRefName']}: {state}", flush=True)
        try:
            if state == "green":
                handle_green(gh, pr)
            elif state == "red":
                handle_red(gh, pr)
        except claude.StopError as e:
            print(f"::error::Stopping all Claude work: {e}", flush=True)
            if e.billing:
                # Out of credits: stay off until the owner turns the workflow back on.
                gh.run("workflow", "disable", "claude-ci.yml", "--repo", gh.repo)
            sys.exit(2)
        except Exception:  # noqa: BLE001
            # One PR's failure must not stop the others.
            failed = True
            traceback.print_exc()
    sys.exit(1 if failed else 0)
