# shellcheck shell=bash
# Invites the assistant to every bridge portal the token's owner has joined.
api="$MATRIX_HOMESERVER/_matrix/client/v3"
auth="Authorization: Bearer $MATRIX_TOKEN"
response=$(mktemp)
trap 'rm -f "$response"' EXIT

# Synapse rate-limits invites, so wait out each 429 instead of failing the room.
invite() {
  local encoded=$1 status wait_ms
  for _ in 1 2 3 4 5; do
    status=$(curl -sS -o "$response" -w '%{http_code}' -X POST -H "$auth" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg u "$ASSISTANT" '{user_id: $u}')" \
      "$api/rooms/$encoded/invite")
    case $status in
      200) return 0 ;;
      429)
        wait_ms=$(jq -r '.retry_after_ms // 5000' "$response")
        sleep $(((wait_ms + 999) / 1000))
        ;;
      *)
        cat "$response" >&2
        return 1
        ;;
    esac
  done
  return 1
}

curl -fsS -H "$auth" "$api/joined_rooms" | jq -r '.joined_rooms[]' | while read -r room; do
  encoded=$(jq -rn --arg r "$room" '$r | @uri')
  members=$(curl -fsS -H "$auth" "$api/rooms/$encoded/joined_members") || continue

  # Portals hold a bridge bot plus at least one contact; the bridge management DM holds only two members.
  if ! jq -e --argjson bots "$BRIDGE_BOTS" --arg assistant "$ASSISTANT" '
    (.joined | keys) as $members
    | ($members | length) >= 3
      and ($members | index($assistant)) == null
      and any($bots[]; . as $bot | $members | index($bot) != null)
  ' <<<"$members" >/dev/null; then
    continue
  fi

  if invite "$encoded"; then
    echo "invited $ASSISTANT to $room"
  else
    echo "invite failed for $room" >&2
  fi
done
