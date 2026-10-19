#!/bin/sh
# Registers the VPN exit IP with MAM.
set -u

DIR=/mam
JAR=$DIR/cookies
SEED=$DIR/mam_id
STATE=$DIR/state
API=https://t.myanonamouse.net/json/dynamicSeedbox.php
INTERVAL=${INTERVAL:-300}
RETRY=${RETRY:-900}

log() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }

jar_has_session() {
  awk -F'\t' '$6=="mam_id"{f=1} END{exit !f}' "$JAR" 2>/dev/null
}

is_ip() {
  case $1 in
    '' | *[!0-9.]*) ;;
    *.*.*.*) return 0 ;;
  esac
  case $1 in
    '' | *[!0-9a-fA-F:]*) return 1 ;;
    *:*:*) return 0 ;;
  esac
  return 1
}

current_ip() {
  for u in https://api.ipify.org https://checkip.amazonaws.com https://ipinfo.io/ip; do
    ip=$(curl -fsS -m 15 "$u" 2>/dev/null | tr -d '[:space:]')
    if is_ip "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 1
}

update() {
  if jar_has_session; then
    set -- -b "$JAR"
  elif [ -s "$SEED" ]; then
    set -- -b "mam_id=$(tr -d '[:space:]' < "$SEED")"
  else
    log "no session; write your mam_id to $SEED"
    return 1
  fi

  body=$(mktemp) || return 1
  new=$(mktemp) || { rm -f "$body"; return 1; }

  code=$(curl -sS -m 30 -o "$body" -w '%{http_code}' "$@" -c "$new" "$API" 2>/dev/null)
  msg=$(sed -n 's/.*"msg":"\([^"]*\)".*/\1/p' "$body")
  seen=$(sed -n 's/.*"ip":"\([^"]*\)".*/\1/p' "$body")

  # Promote the rotated cookie only on success.
  if grep -q '"Success":true' "$body"; then
    if awk -F'\t' '$6=="mam_id"{f=1} END{exit !f}' "$new"; then
      cat "$new" > "$JAR"
    fi
    [ -n "$seen" ] && printf '%s\n' "$seen" > "$STATE"
    log "ok $code: $msg ($seen)"
    rc=0
  else
    log "failed $code: ${msg:-unparsed} ($seen)"
    rc=1
  fi

  rm -f "$body" "$new"
  return $rc
}

log "started; poll ${INTERVAL}s retry ${RETRY}s"
while :; do
  if ip=$(current_ip); then
    last=$(cat "$STATE" 2>/dev/null) || last=
    if [ "$ip" = "$last" ]; then
      sleep "$INTERVAL"
      continue
    fi
    log "ip changed: ${last:-none} -> $ip"
    if update; then sleep "$INTERVAL"; else sleep "$RETRY"; fi
  else
    log "no public ip; vpn down?"
    sleep "$RETRY"
  fi
done
