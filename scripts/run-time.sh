#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/conky-env.sh"

"$SCRIPT_DIR/sky_update.py" || true

SUITE="$CONKY_SUITE_DIR"
CONF="$SUITE/widgets/time.conky.conf"
THEME="$SUITE/theme.lua"

head="$(
  THEME="$THEME" lua -e '
    local p = os.getenv("THEME")
    local t = dofile(p)
    local v = t.monitor_head
    if v == nil then os.exit(2) end
    io.write(tostring(v))
  ' 2>/dev/null || true
)"

tmp="$(mktemp --tmpdir conky-time.XXXXXX.conf)"
trap 'rm -f "$tmp"' EXIT

if [[ -n "$head" ]]; then
  awk -v head="$head" '
    BEGIN{done=0}
    {print}
    /alignment[[:space:]]*=/ && done==0 { print "  xinerama_head         = " head ","; done=1 }
  ' "$CONF" > "$tmp"
else
  cp "$CONF" "$tmp"
fi

exec conky -c "$tmp"
