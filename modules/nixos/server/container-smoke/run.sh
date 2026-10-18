# shellcheck shell=bash
# Usage: container-smoke <id>
# Reads requests/<id>.json: {"spec": "/nix/store/...", "targets": [...]}.
# Runs each target on a ZFS clone of the data root, with no network.
set -euo pipefail

id=$1
[[ $id =~ ^[0-9a-z-]+$ ]] || { echo "bad id: $id" >&2; exit 2; }

request=$STATE_DIR/requests/$id.json
spec=$(jq -r .spec "$request")
[[ $spec == /nix/store/* && -f $spec ]] || { echo "spec not in store" >&2; exit 2; }
mapfile -t targets < <(jq -r '.targets[]' "$request")

work=$STATE_DIR/runs/$id
logs=$STATE_DIR/logs/$id
result=$STATE_DIR/results/$id.json
pod=smoke-$id
snapshot=$DATASET@smoke-$id
clone=${DATASET%%/*}/smoke-$id
uid=$(id -u containers)

# newuidmap lives in the setuid wrappers.
export PATH=/run/wrappers/bin:$PATH

# 75: try again after the upgrade.
if ! reason=$(container-smoke-gate); then
  jq -n --arg reason "$reason" '{gate: {status: "deferred", $reason}}' >"$result"
  echo "deferred: $reason"
  exit 75
fi

as_containers() {
  (cd / && runuser -u containers -- env XDG_RUNTIME_DIR="/run/user/$uid" HOME=/home/containers "$@")
}

# shellcheck disable=SC2329 # Runs from the EXIT trap.
cleanup() {
  as_containers podman pod rm --force --time 5 "$pod" >/dev/null 2>&1 || true
  zfs destroy "$clone" 2>/dev/null || true
  zfs destroy "$snapshot" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$work/empty" "$logs"
chmod 0711 "$work"
chmod 0700 "$logs"
echo '{}' >"$result"

record() {
  jq --arg name "$1" --arg status "$2" --arg reason "$3" \
    '.[$name] = {status: $status, reason: $reason}' "$result" >"$result.tmp"
  mv "$result.tmp" "$result"
  echo "$1: $2 $3"
}

zfs snapshot "$snapshot"
zfs clone -o mountpoint="$work/data" "$snapshot" "$clone"

entry() { jq -c --arg name "$1" '.[$name]' "$spec"; }

# Empty dir owned like $1, keeping its top-level dotfiles.
blank() {
  local source=$1 dir
  dir=$(mktemp -d "$work/empty/XXXX")
  chmod 0755 "$dir"
  if [[ -d $source ]]; then
    chown --reference="$source" "$dir"
    find "$source" -maxdepth 1 -type f -name '.*' -exec cp -a {} "$dir/" \;
  else
    chown containers:containers "$dir"
  fi
  echo "$dir"
}

# Maps a host volume onto the clone.
host_path() {
  local host=$1
  case $host in
    "$DATA_DIR" | "$DATA_DIR"/*)
      local cloned=$work/data${host#"$DATA_DIR"}
      [[ -e $cloned ]] || install -d -o containers -g containers "$cloned"
      echo "$cloned"
      ;;
    /nix/store/* | /etc/localtime) echo "$host" ;;
    *) blank "$host" ;;
  esac
}

volume_args() {
  local name=$1 json host target ro path source suffix
  json=$(entry "$name")
  mapfile -t empty < <(jq -r '.emptyPaths[]' <<<"$json")
  while IFS=$'\t' read -r host target ro; do
    path=$(host_path "$host")
    for blanked in "${empty[@]}"; do
      [[ $blanked == "$target" ]] && path=$(blank "$path")
    done
    suffix=""
    [[ $ro == true ]] && suffix=:ro
    echo "--volume=$path:$target$suffix"
    for blanked in "${empty[@]}"; do
      if [[ $blanked == "$target"/* ]]; then
        source=$path${blanked#"$target"}
        echo "--volume=$(blank "$source"):$blanked"
      fi
    done
  done < <(jq -r '.volumes[] | [.host, .target, .readOnly] | @tsv' <<<"$json")
}

# Members: targets and their requirement closure.
declare -A seen=()
order=()
visit() {
  [[ -n ${seen[$1]:-} ]] && return
  seen[$1]=1
  local dep
  for dep in $(entry "$1" | jq -r '.requires[]'); do visit "$dep"; done
  order+=("$1")
}
for target in "${targets[@]}"; do
  [[ $(entry "$target") != null ]] || { record "$target" fail "not in spec"; exit 1; }
  visit "$target"
done

# Pods fix one userns for all members.
mapfile -t userns < <(for name in "${order[@]}"; do entry "$name" | jq -r '.userns // empty'; done | sort -u)
pod_args=(--name "$pod" --network none --no-hosts)
((${#userns[@]} <= 1)) || { record "${targets[0]}" fail "mixed userns"; exit 1; }
((${#userns[@]} == 1)) && pod_args+=("--userns=${userns[0]}")

# Production hostnames resolve to the pod.
hosts=$work/hosts
printf '127.0.0.1 localhost %s\n::1 localhost\n' "${order[*]}" >"$hosts"
chmod 0644 "$hosts"
as_containers podman pod create "${pod_args[@]}" >/dev/null

infra=$(as_containers podman pod inspect "$pod" --format '{{.InfraContainerID}}')

start() {
  local name=$1 json image args=()
  json=$(entry "$name")
  image=$(jq -r .image <<<"$json")
  as_containers podman image exists "$image" || as_containers podman pull --quiet "$image" >/dev/null

  args=(run --detach --pod "$pod" --name "$pod-$name" "--volume=$hosts:/etc/hosts:ro")
  mapfile -t -O "${#args[@]}" args < <(volume_args "$name")
  mapfile -t -O "${#args[@]}" args < <(jq -r '
    (.environments | to_entries[] | "--env=\(.key)=\(.value)"),
    (.environmentFiles[] | select(startswith("/run/agenix/")) | "--env-file=\(.)"),
    (.addCapabilities[] | "--cap-add=\(.)"),
    (.user // empty | "--user=\(.)"),
    (.shmSize // empty | "--shm-size=\(.)"),
    (.entrypoint // empty | "--entrypoint=\(.)"),
    (select(.noNewPrivileges) | "--security-opt=no-new-privileges")
  ' <<<"$json")
  args+=("$image")
  mapfile -t -O "${#args[@]}" args < <(jq -r '.exec // [] | .[]' <<<"$json")
  as_containers podman "${args[@]}" >/dev/null
}

for name in "${order[@]}"; do start "$name"; done

pid=$(as_containers podman inspect "$infra" --format '{{.State.Pid}}')

links=$(nsenter --target "$pid" --net ip -o link show | awk -F': ' '{print $2}')
if [[ $links != lo ]]; then
  record "${targets[0]}" fail "pod has network: $links"
  exit 1
fi

state() { as_containers podman inspect "$pod-$1" --format '{{.State.Status}} {{.State.ExitCode}}'; }

answers() {
  local code rc address
  for address in 127.0.0.1 '[::1]'; do
    rc=0
    code=$(nsenter --target "$pid" --net curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$address:$1/") || rc=$?
    case $rc in
      0) [[ $code =~ ^[1-4] ]] && return 0 ;;
      # Connected, but not HTTP.
      1 | 8 | 52 | 56) return 0 ;;
    esac
  done
  return 1
}

# Port: wait for HTTP. Else: stay up 60s.
probe() {
  local name=$1 port status tries=12
  port=$(entry "$name" | jq -r '.port // empty')
  [[ -n $port ]] && tries=60
  for _ in $(seq "$tries"); do
    read -r status _ < <(state "$name")
    if [[ $status != running ]]; then
      record "$name" fail "$(state "$name")"
      return 1
    fi
    if [[ -n $port ]] && answers "$port"; then break; fi
    sleep 5
  done
  if [[ -n $port ]] && ! answers "$port"; then
    record "$name" fail "port $port silent after 300s"
    return 1
  fi
  sleep 10
  read -r status _ < <(state "$name")
  if [[ $status != running ]]; then
    record "$name" fail "$(state "$name")"
    return 1
  fi
  record "$name" pass "${port:+port $port answered}"
}

failed=0
for target in "${targets[@]}"; do probe "$target" || failed=1; done

for name in "${order[@]}"; do
  as_containers podman logs "$pod-$name" >"$logs/$name.log" 2>&1 || true
done

exit "$failed"
