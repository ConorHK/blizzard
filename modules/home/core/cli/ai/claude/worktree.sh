# shellcheck shell=bash
# Claude Code worktree hooks: a jj workspace in a jj repo, else a git worktree.
# Usage: claude-worktree create|remove, with the hook's JSON on stdin.
# Only the created path may reach stdout, so everything else goes to stderr.
set -euo pipefail
exec 3>&1 1>&2

input=$(cat)
cwd=$(jq -r '.cwd' <<<"$input")

# A workspace's .jj/repo is the store, or a file naming it relative to .jj.
main_root() {
	(cd "$1/.jj" && if [ -f repo ]; then cd "$(cat repo)"; else cd repo; fi && cd ../.. && pwd)
}

create() {
	local name root path
	name=$(jq -r '.name' <<<"$input")
	if root=$(jj workspace root --ignore-working-copy -R "$cwd" 2>/dev/null); then
		path="$HOME/.herdr/workspaces/$(basename "$(main_root "$root")")/$name"
		mkdir -p "$(dirname "$path")"
		# Claude passes the main checkout, whose own @ may be old, so new work starts from trunk.
		jj workspace add --name "$name" -r "trunk()" -R "$root" "$path"
	else
		root=$(git -C "$cwd" rev-parse --show-toplevel)
		path="$root/.claude/worktrees/$name"
		git -C "$root" worktree add -b "worktree-$name" "$path" HEAD
	fi
	echo "$path" >&3
}

remove() {
	local path name
	path=$(jq -r '.worktree_path' <<<"$input")
	if [ -f "$path/.jj/repo" ]; then
		name=$(jj workspace list --ignore-working-copy -R "$path" -T 'if(current_workspace, name)')
		# jj snapshots the files into a commit before it deletes the folder.
		jj workspace remove -R "$(main_root "$path")" "$name"
	else
		git -C "$path" worktree remove --force "$path"
	fi
}

case "${1:-}" in
create) create ;;
remove) remove ;;
*)
	echo "usage: claude-worktree create|remove" >&2
	exit 2
	;;
esac
