#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/conky-env.sh"
DAILY="${1:-$CONKY_CACHE_DIR/owm_forecast.json}"
THEME_DIR="${2:-$CONKY_SUITE_DIR/icons/owm}"
THEME_PATH="${CONKY_THEME_PATH:-$CONKY_SUITE_DIR/theme.lua}"

# Optional theme knob override (theme.lua: weather.icon_set)
theme_icon_set="$(THEME_PATH="$THEME_PATH" lua -e 'local p=os.getenv("THEME_PATH"); local ok,t=pcall(dofile,p); if ok and type(t)=="table" then local s=t.weather and t.weather.icon_set; if s and s~="" then print(s) end end' 2>/dev/null || true)"
if [[ -n "$theme_icon_set" ]]; then
  if [[ "$theme_icon_set" = /* ]]; then
    THEME_DIR="$theme_icon_set"
  elif [[ "$theme_icon_set" == icons/* ]]; then
    THEME_DIR="$CONKY_SUITE_DIR/$theme_icon_set"
  else
    THEME_DIR="$CONKY_SUITE_DIR/icons/$theme_icon_set"
  fi
fi

theme_icon_cache_dir="$(THEME_PATH="$THEME_PATH" lua -e 'local p=os.getenv("THEME_PATH"); local ok,t=pcall(dofile,p); if ok and type(t)=="table" then local s=t.weather and t.weather.icon_cache_dir; if s and s~="" then print(s) end end' 2>/dev/null || true)"
OUTDIR="$CONKY_CACHE_DIR/icons"
if [[ -n "$theme_icon_cache_dir" ]]; then
  if [[ "$theme_icon_cache_dir" = /* ]]; then
    OUTDIR="$theme_icon_cache_dir"
  else
    OUTDIR="$CONKY_CACHE_DIR/$theme_icon_cache_dir"
  fi
fi

mkdir -p "$OUTDIR" "$THEME_DIR"

ensure_code_png() {
  local code="$1" dst="$THEME_DIR/${code}.png"
  [[ -s "$dst" ]] && return 0
  curl -fsSL "https://openweathermap.org/img/wn/${code}@2x.png" -o "$dst" || return 1
}

codes="$(jq -r '
  (.city.timezone // 0) as $tz
  | .list
  | map(. + {
      local_dt: (.dt + $tz),
      day:      ((.dt + $tz) | gmtime | strftime("%Y-%m-%d")),
      hour:     ((.dt + $tz) | gmtime | strftime("%H") | tonumber)
    })
  | group_by(.day)
  | .[:6]
  | map(
      ( [ .[] | {icon:.weather[0].icon, hour:.hour} ] ) as $arr
      | ( [ $arr[] | select(.hour >= 10 and .hour <= 16) | .icon ] ) as $day
      | ( if ($day|length) > 0
          then ($day | group_by(.) | max_by(length)[0])
          else ($arr[0].icon)
        end )
      | sub("n$";"d")
    )
  | .[]
' "$DAILY" 2>/dev/null || true)"

if [[ -z "$codes" ]] && [[ -s "$CONKY_CACHE_DIR/owm_days.vars" ]]; then
  codes="$(grep -E '^D[0-5]_ICON=' "$CONKY_CACHE_DIR/owm_days.vars" | cut -d= -f2-)"
fi

i=0
while read -r code; do
  [[ -z "$code" ]] && continue
  ensure_code_png "$code" || true
  src="$THEME_DIR/${code}.png"
  dest="$OUTDIR/fc${i}.png"
  [[ -s "$src" ]] && cp -f "$src" "$dest"
  i=$((i+1))
  [[ $i -ge 6 ]] && break
done <<< "$codes"

# --- Daylight override for fc0: if it's daytime, mirror the current icon ---
CUR_JSON="$CONKY_CACHE_DIR/owm_current.json"
ICON_DIR="$OUTDIR"

if [ -f "$CUR_JSON" ]; then
  now=$(date +%s)
  sr=$(jq -r '.sys.sunrise // 0' "$CUR_JSON" 2>/dev/null)
  ss=$(jq -r '.sys.sunset  // 0' "$CUR_JSON" 2>/dev/null)
  # Only override in daylight and if we have a current.png
  if [ "$now" -ge "$sr" ] && [ "$now" -le "$ss" ] && [ -f "$ICON_DIR/current.png" ]; then
    cp -f "$ICON_DIR/current.png" "$ICON_DIR/fc0.png"
  fi
fi
