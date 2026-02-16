#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/conky-env.sh"
f="$CONKY_CACHE_DIR/wan_ip"
if [[ -f "$f" ]]; then
  v="$(tr -d '\r\n' < "$f" 2>/dev/null)"
else
  v=""
fi
[ -n "$v" ] && printf '%s\n' "$v" || printf '(resolving...)\n'
