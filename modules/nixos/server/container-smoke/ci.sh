#!/usr/bin/env bash
# Smoke tests containers whose image changed against main.
set -euo pipefail

host=${1:-$(hostname)}
nix=(nix --extra-experimental-features pipe-operators)

base=$(git merge-base HEAD origin/main)
if [[ $base == "$(git rev-parse HEAD)" ]]; then
  echo "No commits beyond main."
  exit 0
fi
if ! git diff "$base" HEAD -- '*.nix' | grep -qE '^[+-][[:space:]]*image ='; then
  echo "No image changes."
  exit 0
fi

images() {
  "${nix[@]}" eval --json "$1#nixosConfigurations.$host.config.home-manager.users.containers.virtualisation.quadlet.containers" \
    --apply 'builtins.mapAttrs (_: c: c.containerConfig.image)'
}

targets=$(jq -cn --argjson old "$(images "git+file://$PWD?rev=$base")" --argjson new "$(images .)" \
  '[$new | to_entries[] | select($old[.key] != .value) | .key]')
if [[ $targets == "[]" ]]; then
  echo "No container images changed on $host."
  exit 0
fi
echo "Testing on $host: $targets"

spec=$("${nix[@]}" build --no-link --print-out-paths ".#containerSmoke.$host")
id=${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-$$}
state=/var/lib/container-smoke

jq -n --arg spec "$spec" --argjson targets "$targets" '{$spec, $targets}' >"$state/requests/$id.json"

status=0
systemctl start "container-smoke@$id.service" || status=$?

jq -r 'to_entries[] | "\(.key): \(.value.status) \(.value.reason)"' "$state/results/$id.json"
if ((status != 0)); then
  echo "Container logs stay on $host: $state/logs/$id"
fi
exit "$status"
