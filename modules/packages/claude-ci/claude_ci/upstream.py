"""What changed upstream in each flake input a PR bumps, for the reviewer to read."""

import json
import subprocess

from .gh import GitHub

# Above this many commits (nixpkgs), only the count is shown: a list would be noise.
MAX_COMMITS = 1000
# Total characters of upstream patches one review may include.
PATCH_BUDGET = 150_000


def changed_inputs(old_lock: dict, new_lock: dict) -> list[dict]:
    """List the flake inputs whose locked revision changed, with where they live."""
    changes = []
    old_nodes = old_lock.get("nodes", {})
    for name, node in sorted(new_lock.get("nodes", {}).items()):
        new = node.get("locked") or {}
        old = (old_nodes.get(name) or {}).get("locked") or {}
        if not new.get("rev") or new.get("rev") == old.get("rev"):
            continue
        changes.append({
            "name": name,
            "type": new.get("type"),
            "owner": new.get("owner"),
            "repo": new.get("repo"),
            "old": old.get("rev"),
            "new": new["rev"],
        })
    return changes


def describe(change: dict, compare: dict | None, budget: int) -> tuple[str, int]:
    """Render one input's upstream change within the patch budget; return text and budget used."""
    where = f"{change['owner']}/{change['repo']}" if change["type"] == "github" else change["type"]
    head = f"## {change['name']}: {where} {str(change['old'])[:12]} -> {change['new'][:12]}"
    if change["type"] != "github":
        return f"{head}\nNot hosted on GitHub; no upstream diff available.", 0
    if not change["old"]:
        return f"{head}\nNew input; no earlier revision to compare.", 0
    if compare is None:
        return f"{head}\nGitHub would not compare these revisions (private, force-pushed or gone).", 0
    total, files = compare.get("total_commits", 0), compare.get("files") or []
    lines = [f"{head} ({total} commits, {len(files)} files)"]
    if total > MAX_COMMITS:
        lines.append("Too many commits to list; judge this input from the PR body.")
        return "\n".join(lines), 0
    commits = compare.get("commits") or []
    if len(commits) < total:
        lines.append(f"Commits (the first {len(commits)} of {total}):")
    else:
        lines.append("Commits:")
    lines += [f"- {c['sha'][:12]} {c['commit']['message'].splitlines()[0]}" for c in commits]
    lines.append("Files:")
    lines += [f"- {f['status']} {f['filename']} (+{f['additions']} -{f['deletions']})" for f in files]
    patches = "\n".join(f"--- {f['filename']}\n{f['patch']}" for f in files if f.get("patch"))
    if not patches:
        return "\n".join(lines), 0
    if len(patches) > budget:
        lines.append(f"Patches omitted: {len(patches)} characters is over the remaining budget of {budget}.")
        return "\n".join(lines), 0
    lines += ["Patches:", patches]
    return "\n".join(lines), len(patches)


def lock_at(gh: GitHub, sha: str) -> dict:
    """Read flake.lock at a commit, or an empty lock where it does not exist."""
    try:
        text = gh.run("api", "-H", "Accept: application/vnd.github.raw", f"repos/{gh.repo}/contents/flake.lock?ref={sha}")
    except subprocess.CalledProcessError:
        return {}
    return json.loads(text)


def compare(gh: GitHub, change: dict) -> dict | None:
    """Ask GitHub for the upstream comparison, or None when it refuses."""
    path = f"repos/{change['owner']}/{change['repo']}/compare/{change['old']}...{change['new']}"
    try:
        return json.loads(gh.run("api", path))
    except subprocess.CalledProcessError:
        return None


def report(gh: GitHub, base_sha: str, head_sha: str) -> str:
    """Describe every flake input the PR bumps, or an empty string when it bumps none."""
    changes = changed_inputs(lock_at(gh, base_sha), lock_at(gh, head_sha))
    sections, budget = [], PATCH_BUDGET
    for change in changes:
        data = compare(gh, change) if change["type"] == "github" and change["old"] else None
        text, used = describe(change, data, budget)
        sections.append(text)
        budget -= used
    return "\n\n".join(sections)
