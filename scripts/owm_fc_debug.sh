#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/conky-env.sh"
SUITE_DIR="$CONKY_SUITE_DIR"
CACHE_DIR="$CONKY_CACHE_DIR"
THEME_PATH="${CONKY_THEME_PATH:-$CONKY_SUITE_DIR/theme.lua}"
J="$CACHE_DIR/owm_forecast.json"
echo "Chosen codes (one per day):"
jq -r '
  .list
  | group_by(.dt | strftime("%Y-%m-%d"))
  | map(select((.[0].dt | strftime("%Y-%m-%d")) != (now | strftime("%Y-%m-%d"))))
  | .[:5]
  | map(
      ( [ .[] | {icon:.weather[0].icon, hour:(.dt | strftime("%H") | tonumber)} ] ) as $arr
      | ( [ $arr[] | select(.hour >= 10 and .hour <= 16) | .icon ] ) as $day
      | ( if ($day|length) > 0
          then ($day | group_by(.) | max_by(length)[0])
          else ($arr[0].icon)
        end )
    )
  | @tsv
' "$J"
theme_icon_set="$(THEME_PATH="$THEME_PATH" lua -e 'local p=os.getenv("THEME_PATH"); local ok,t=pcall(dofile,p); if ok and type(t)=="table" then local s=t.weather and t.weather.icon_set; if s and s~="" then print(s) end end' 2>/dev/null || true)"
ICON_DIR="$SUITE_DIR/icons/owm"
if [[ -n "$theme_icon_set" ]]; then
  if [[ "$theme_icon_set" = /* ]]; then
    ICON_DIR="$theme_icon_set"
  elif [[ "$theme_icon_set" == icons/* ]]; then
    ICON_DIR="$SUITE_DIR/$theme_icon_set"
  else
    ICON_DIR="$SUITE_DIR/icons/$theme_icon_set"
  fi
fi
echo "---- THEME (code PNGs in $ICON_DIR):"
ls -l "$ICON_DIR" | head -n 20 || true
theme_icon_cache_dir="$(THEME_PATH="$THEME_PATH" lua -e 'local p=os.getenv("THEME_PATH"); local ok,t=pcall(dofile,p); if ok and type(t)=="table" then local s=t.weather and t.weather.icon_cache_dir; if s and s~="" then print(s) end end' 2>/dev/null || true)"
ICON_CACHE_DIR="$CACHE_DIR/icons"
if [[ -n "$theme_icon_cache_dir" ]]; then
  if [[ "$theme_icon_cache_dir" = /* ]]; then
    ICON_CACHE_DIR="$theme_icon_cache_dir"
  else
    ICON_CACHE_DIR="$CACHE_DIR/$theme_icon_cache_dir"
  fi
fi
echo "---- FC files (cache in $ICON_CACHE_DIR):"
ls -l "$ICON_CACHE_DIR"/fc*.png 2>/dev/null || echo "(no fc*.png)"
