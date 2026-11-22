"""GitHub through the gh CLI, always as argument lists."""

import json
import subprocess

MARKER = "<!-- claude-ci:{kind}:{sha} -->"


class GitHub:
    """The repository's PRs, checks and comments through gh."""

    def __init__(self, repo: str) -> None:
        """Bind to one owner/name repository."""
        self.repo = repo

    def run(self, *args: str) -> str:
        """Run gh and return its output."""
        return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout  # noqa: S603, S607

    def api(self, path: str, *args: str) -> dict:
        """Call one REST endpoint of the repository."""
        return json.loads(self.run("api", f"repos/{self.repo}/{path}", *args))

    def pages(self, path: str) -> list:
        """Fetch every item of a paginated list endpoint."""
        pages = json.loads(self.run("api", "--paginate", "--slurp", f"repos/{self.repo}/{path}"))
        return [item for page in pages for item in (page if isinstance(page, list) else [page])]

    def open_prs(self) -> list[dict]:
        """List open PRs."""
        fields = "number,title,body,author,headRefName,headRefOid,baseRefName,isDraft,isCrossRepository,url"
        return json.loads(self.run("pr", "list", "--repo", self.repo, "--state", "open", "--limit", "100", "--json", fields))

    def check_runs(self, sha: str) -> list[dict]:
        """List a commit's check runs, newest per name."""
        runs = self.api(f"commits/{sha}/check-runs?per_page=100")["check_runs"]
        # A rerun leaves the old run behind: keep the newest per name.
        newest: dict[str, dict] = {}
        for run in sorted(runs, key=lambda r: r.get("started_at") or ""):
            newest[run["name"]] = run
        return list(newest.values())

    def statuses(self, sha: str) -> list[dict]:
        """List a commit's statuses."""
        return self.api(f"commits/{sha}/status")["statuses"]

    def files(self, number: int) -> list[dict]:
        """List a PR's files with their patches."""
        return self.pages(f"pulls/{number}/files?per_page=100")

    def diff(self, number: int) -> str:
        """Return a PR's full diff."""
        return self.run("pr", "diff", str(number), "--repo", self.repo)

    def commits(self, number: int) -> list[dict]:
        """List a PR's commits."""
        return self.pages(f"pulls/{number}/commits?per_page=100")

    def commit_files(self, sha: str) -> list[str]:
        """List the paths one commit changed."""
        return [f["filename"] for f in self.api(f"commits/{sha}")["files"]]

    def comments(self, number: int) -> list[str]:
        """Return a PR's comment bodies."""
        return [c["body"] for c in self.pages(f"issues/{number}/comments?per_page=100")]

    def has_marker(self, number: int, kind: str, sha: str) -> bool:
        """Tell whether a decision of this kind exists for this commit."""
        marker = MARKER.format(kind=kind, sha=sha)
        return any(marker in body for body in self.comments(number))

    def comment(self, number: int, kind: str, sha: str, body: str) -> None:
        """Post a decision, marked with its kind and commit."""
        text = f"{MARKER.format(kind=kind, sha=sha)}\n{body}"
        self.run("pr", "comment", str(number), "--repo", self.repo, "--body", text)

    def merge(self, number: int, sha: str) -> None:
        """Squash-merge the PR only if its head is still the reviewed commit."""
        self.run("pr", "merge", str(number), "--repo", self.repo, "--squash", "--delete-branch", "--match-head-commit", sha)

    def dispatch(self, workflow: str, ref: str) -> None:
        """Start a workflow on a ref."""
        # Pushes and merges made with the workflow token start no workflows.
        self.run("workflow", "run", workflow, "--repo", self.repo, "--ref", ref)

    def failed_logs(self, sha: str, workflow: str) -> str:
        """Return the failed steps' logs of the newest failed run on a commit."""
        runs = json.loads(self.run(
            "run", "list", "--repo", self.repo, "--workflow", workflow, "--commit", sha,
            "--json", "databaseId,conclusion", "--limit", "5",
        ))
        failed = [r["databaseId"] for r in runs if r["conclusion"] == "failure"]
        if not failed:
            return ""
        return self.run("run", "view", str(failed[0]), "--repo", self.repo, "--log-failed")
