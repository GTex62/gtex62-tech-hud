#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/conky-env.sh"
CUR_JSON="${1:-$CONKY_CACHE_DIR/owm_current.json}"
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
ICON_CACHE_DIR="$CONKY_CACHE_DIR/icons"
if [[ -n "$theme_icon_cache_dir" ]]; then
  if [[ "$theme_icon_cache_dir" = /* ]]; then
    ICON_CACHE_DIR="$theme_icon_cache_dir"
  else
    ICON_CACHE_DIR="$CONKY_CACHE_DIR/$theme_icon_cache_dir"
  fi
fi
mkdir -p "$ICON_CACHE_DIR"
OUTPNG="$ICON_CACHE_DIR/current.png"

code="$(jq -r '.weather[0].icon // empty' "$CUR_JSON" 2>/dev/null || true)"
# --- Daylight override based on cloud cover (when no precip) ---
now=$(date +%s)
sr=$(jq -r '.sys.sunrise // 0' "$CUR_JSON" 2>/dev/null)
ss=$(jq -r '.sys.sunset  // 0' "$CUR_JSON" 2>/dev/null)
clouds=$(jq -r '.clouds.all // empty' "$CUR_JSON" 2>/dev/null || true)
rain1=$(jq -r '.rain["1h"] // 0' "$CUR_JSON" 2>/dev/null)
snow1=$(jq -r '.snow["1h"] // 0' "$CUR_JSON" 2>/dev/null)

if [[ -n "$clouds" ]] && [[ "$rain1" == "0" && "$snow1" == "0" ]] && [[ "$now" -ge "$sr" && "$now" -le "$ss" ]]; then
  c=${clouds%.*}  # integer
  if   (( c <= 15 )); then code="01d"   # clear
  elif (( c <= 40 )); then code="02d"   # few clouds
  elif (( c <= 70 )); then code="03d"   # scattered
  else                    code="04d"   # broken/overcast
  fi
fi

[[ -z "$code" ]] && exit 0

src="$THEME_DIR/${code}.png"
# If your pack is missing a specific code, optionally fall back to day variant:
[[ -f "$src" ]] || src="$THEME_DIR/$(printf '%s' "$code" | sed 's/n$/d/')"
# Final safety: if still missing, try OWM CDN once
# if [[ ! -f "$src" ]]; then
#   mkdir -p "$THEME_DIR"
#   curl -fsSL "https://openweathermap.org/img/wn/${code}@2x.png" -o "$THEME_DIR/${code}.png" || true
#   src="$THEME_DIR/${code}.png"
# fi

[[ -f "$src" ]] && cp -f "$src" "$OUTPNG"
