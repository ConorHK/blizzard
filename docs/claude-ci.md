# Claude CI

[`claude-ci`](../modules/packages/claude-ci/) uses Claude Sonnet 5.5 to merge
Renovate and Dependabot PRs once CI is green, and to push a fix when CI fails
because blizzard itself needs a change.

```
bot PR -> build.yml -> claude-ci job dispatches claude-ci.yml (also hourly)
  green -> merge gate -> Claude review -> approve: squash-merge, dispatch build on main
  red   -> Claude diagnosis -> blizzard_config: fixer pushes a commit, dispatches build
```

## Which PRs

Only PRs into `main` from `github-actions[bot]` on `renovate/*` (Renovate runs
with the workflow token) and `dependabot[bot]` on `dependabot/*`, not drafts,
not forks ([`gate.py`](../modules/packages/claude-ci/claude_ci/gate.py)).

A PR counts as green when every check run on its head commit passed or was
skipped, `check` is among them, and every commit status (container-smoke)
succeeded. Any failure counts as red. Anything else waits for the next pass.

## The merge gate

The gate runs before Claude sees the PR, and Claude cannot override it.

- Bot commits may change `flake.lock`, `package.json`, `package-lock.json`,
  `image = "..."` lines and `# renovate:` comments in `.nix` files, and
  `uses:` pins in workflows. Any other change waits for the owner.
- Files the fixer's own commits touched pass the gate, so a fixed PR can
  still merge after Claude reviews the whole diff.
- Nobody may touch `.secrets/`, `*.age`, `.github/` (bots may still bump
  `uses:` pins), the runner module or `claude-ci` itself.

GitHub merges only the head commit Claude reviewed (`--match-head-commit`).
Merges made with the workflow token start no workflow, so claude-ci
dispatches `build.yml` on `main` itself.

## What the reviewer reads

Claude gets the PR title, the bot's PR body (Renovate's release notes,
Dependabot's commit list), blizzard's diff, and what changed upstream
([`upstream.py`](../modules/packages/claude-ci/claude_ci/upstream.py)). For
each flake input whose locked revision moved, nested inputs included,
GitHub's compare API supplies the commits, the changed files and, while they
fit a 150,000-character budget, the patches. Inputs with over 1,000 commits
(nixpkgs) show only the count, and inputs not on GitHub say so. Container
images and npm packages have no upstream diff; their release notes stand in.

## The fixer

Claude first classifies the failed run's logs as `blizzard_config`,
`upstream_breakage`, `infrastructure` or `unclear`. Only `blizzard_config`
gets a fix. An `infrastructure` failure on a run's first attempt gets its
failed jobs rerun once; a rerun that fails is diagnosed again, and is left for
the owner if it is infrastructure again.

The fixer works in a worktree of the PR branch through six tools: list,
read, search, write, run one flake check or host build, and finish. Writes
to protected paths are refused. It keeps the update and adapts blizzard to
it, never pins back or weakens a check. Its commit carries the
`Claude-CI-Fix: true` trailer. A PR gets at most two fix commits.

## Credentials

There is no API key. The job asks GitHub for an OIDC token with audience
`https://api.anthropic.com`, and the SDK exchanges it for a 10-minute
Anthropic token under the `claude-ci` federation rule. The rule matches
runs on `main` of `ConorHK/blizzard`, pinned to the owner's numeric ID
`43848548`, so branches, pull requests and forks cannot mint a token. It
works only in the `claude-ci` workspace. GitHub tokens last about
five minutes and each exchange needs an unused one, so claude-ci writes a
fresh one to `ANTHROPIC_IDENTITY_TOKEN_FILE` before every request. The rule
and organization IDs sit in the repository variables
`ANTHROPIC_FEDERATION_RULE_ID` and `ANTHROPIC_ORGANIZATION_ID`.

## Cost and stopping

- Usage bills to the rule's workspace, from prepaid credits.
- When the credits run out, the API returns `billing_error` (HTTP 402). The
  run stops at once and disables `claude-ci.yml`. Re-enable it with
  `gh workflow enable claude-ci.yml` after topping up.
- Each run stops itself after $5 at list prices.
- Auto-reload in the Console's billing settings is what would charge past
  the credits. Keep it off.

## Every decision leaves a comment

Each verdict, gate refusal, diagnosis and fix lands as a PR comment with a
hidden `claude-ci:<kind>:<sha>` marker. A commit gets one review and one fix
attempt, so a pass never repeats work or spends twice on the same commit.
