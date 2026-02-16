#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/conky-env.sh"

CACHE_DIR="$CONKY_CACHE_DIR"
THEME_PATH="${CONKY_THEME_PATH:-$CONKY_SUITE_DIR/theme.lua}"

# Optional theme knob override (theme.lua: weather.icon_cache_dir)
theme_icon_cache_dir="$(THEME_PATH="$THEME_PATH" lua -e 'local p=os.getenv("THEME_PATH"); local ok,t=pcall(dofile,p); if ok and type(t)=="table" then local s=t.weather and t.weather.icon_cache_dir; if s and s~="" then print(s) end end' 2>/dev/null || true)"
ICON_DIR="$CACHE_DIR/icons"
if [[ -n "$theme_icon_cache_dir" ]]; then
  if [[ "$theme_icon_cache_dir" = /* ]]; then
    ICON_DIR="$theme_icon_cache_dir"
  else
    ICON_DIR="$CACHE_DIR/$theme_icon_cache_dir"
  fi
fi
FC_JSON="$CACHE_DIR/owm_forecast.json"
CUR_JSON="$CACHE_DIR/owm_current.json"
OUT_VARS="$CACHE_DIR/owm_days.vars"
LOG_FILE="$CACHE_DIR/owm_fetch.log"

mkdir -p "$CACHE_DIR" "$ICON_DIR"
[[ -s "$FC_JSON" ]] || exit 0

# Current temp (optional) for clamping today's high
CURRENT_TEMP=""
if [[ -s "$CUR_JSON" ]]; then
  CURRENT_TEMP="$(jq -r '.main.temp // empty' "$CUR_JSON" 2>>"$LOG_FILE" || true)"
fi
CUR_JSON_VAL="null"
if [[ -n "$CURRENT_TEMP" ]] && [[ "$CURRENT_TEMP" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
  CUR_JSON_VAL="$CURRENT_TEMP"
fi

# Use jq localtime+strftime instead of strflocaltime (for broader jq compatibility)
jq -r --argjson cur "$CUR_JSON_VAL" '
  (.city.timezone // 0) as $tz
  | (now + $tz | gmtime | strftime("%Y-%m-%d")) as $today
  | .list
  | map(. + {
      local_dt: (.dt + $tz),
      day:      ((.dt + $tz) | gmtime | strftime("%Y-%m-%d")),
      hour:     ((.dt + $tz) | gmtime | strftime("%H") | tonumber)
    })
  | group_by(.day)
  | map(select(.[0].day >= $today))
  | map({
      day:  .[0].day,
      name: (.[0].local_dt | gmtime | strftime("%a")),
      hi:   (max_by(.main.temp).main.temp),
      lo:   (min_by(.main.temp).main.temp),
      icon: (
        ( [ .[] | {icon:.weather[0].icon, hour:(.dt + $tz | gmtime | strftime("%H") | tonumber)} ] ) as $arr
        | ( [ $arr[] | select(.hour >= 10 and .hour <= 16) | .icon ] ) as $day
        | ( if ($day|length) > 0
            then ($day | group_by(.) | max_by(length)[0])
            else ($arr[0].icon)
          end )
        | sub("n$";"d")
      )
    })
  | .[:6]
  | to_entries[]
  | "D\(.key)_NAME=\(.value.name)\nD\(.key)_HI=\((if (.key == 0 and $cur != null and $cur > .value.hi) then $cur else .value.hi end)|tostring)\nD\(.key)_LO=\(.value.lo|tostring)\nD\(.key)_ICON=\(.value.icon)"
' "$FC_JSON" > "$OUT_VARS".tmp 2>>"$LOG_FILE" || {
  echo "$(date -Is) WARN: jq reduce failed" >> "$LOG_FILE"
  exit 0
}

mv -f "$OUT_VARS".tmp "$OUT_VARS"

# Cache icons to static filenames (fc0..fc5)
for i in 0 1 2 3 4 5; do
  code="$(grep -E "^D${i}_ICON=" "$OUT_VARS" | cut -d= -f2-)"
  [[ -n "$code" ]] || continue
  dst="$ICON_DIR/fc${i}.png"
  if [[ ! -f "$dst" ]]; then
    url="https://openweathermap.org/img/wn/${code}@2x.png"
    curl -fsS --max-time 6 -o "$dst" "$url" 2>>"$LOG_FILE" || true
  fi
done

exit 0
