#!/usr/bin/env bash

pkill -x conky 2>/dev/null || true

xrandr --current >/dev/null 2>&1 || true

# Suite root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$SCRIPT_DIR/conky-env.sh"
SUITE_DIR="$CONKY_SUITE_DIR"
CACHE_DIR="$CONKY_CACHE_DIR"
mkdir -p "$CACHE_DIR"

SUITE_NAME="$(basename "$SUITE_DIR")"
WALLPAPER_DIR="$SUITE_DIR/wallpapers"
CACHE_LAST="$CACHE_DIR/${SUITE_NAME}-wallpaper"
CACHE_SCREEN="$CACHE_DIR/${SUITE_NAME}-screen-size"

embed_flags="$(
  THEME="$SUITE_DIR/theme.lua" lua -e '
    local t = dofile(os.getenv("THEME"))
    local e = t.embedded_corners or {}
    local function on(v)
      if v == false then return "0" end
      return "1"
    end
    print(on(e.enabled))
    print(on(e.system and e.system.enabled))
    print(on(e.network and e.network.enabled))
    print(on(e.station_model and e.station_model.enabled))
    print(on(e.baro_gauge and e.baro_gauge.enabled))
  ' 2>/dev/null || true
)"
EMBED_ENABLED=0
EMBED_SYSTEM=0
EMBED_NETWORK=0
EMBED_STATION=0
EMBED_BARO=0
if [[ -n "$embed_flags" ]]; then
  mapfile -t EMBED_LINES <<< "$embed_flags"
  EMBED_ENABLED="${EMBED_LINES[0]:-0}"
  EMBED_SYSTEM="${EMBED_LINES[1]:-0}"
  EMBED_NETWORK="${EMBED_LINES[2]:-0}"
  EMBED_STATION="${EMBED_LINES[3]:-0}"
  EMBED_BARO="${EMBED_LINES[4]:-0}"
fi

if [ ! -f "$CACHE_SCREEN" ]; then
  if "$SUITE_DIR/scripts/set-screen-size.sh" >/dev/null 2>&1; then
    touch "$CACHE_SCREEN"
  fi
fi

mapfile -t WALLS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f -printf '%f\n' | sort)

if [ "${#WALLS[@]}" -eq 0 ]; then
  echo "No wallpapers found in: $WALLPAPER_DIR"
  exit 1
fi

DEFAULT_CHOICE=""
if [ -f "$CACHE_LAST" ]; then
  last="$(cat "$CACHE_LAST" 2>/dev/null || true)"
  for i in "${!WALLS[@]}"; do
    if [ "${WALLS[$i]}" = "$last" ]; then
      DEFAULT_CHOICE="$((i+1))"
      break
    fi
  done
fi

if [ "${#WALLS[@]}" -eq 1 ]; then
  choice="1"
else
  echo "Available wallpapers for $SUITE_NAME:"
  for i in "${!WALLS[@]}"; do
    printf "%d) %s\n" "$((i+1))" "${WALLS[$i]}"
  done
  if [ -n "$DEFAULT_CHOICE" ]; then
    read -rp "Select wallpaper [1-${#WALLS[@]}] (Enter=$DEFAULT_CHOICE): " choice
    choice="${choice:-$DEFAULT_CHOICE}"
  else
    read -rp "Select wallpaper [1-${#WALLS[@]}]: " choice
  fi
fi

if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#WALLS[@]} )); then
  echo "Invalid selection."
  exit 1
fi

WALLPAPER_FILE="${WALLS[$((choice-1))]}"
echo "$WALLPAPER_FILE" > "$CACHE_LAST"

WALLPAPER_PATH="$WALLPAPER_DIR/$WALLPAPER_FILE"
feh --no-xinerama --bg-fill "$WALLPAPER_PATH"

# Launch suite
conky -c "$SUITE_DIR/widgets/time.conky.conf" &
if [[ "$EMBED_ENABLED" != "1" || "$EMBED_STATION" != "1" ]]; then
  conky -c "$SUITE_DIR/widgets/station-model.conky.conf" &
fi
if [[ "$EMBED_ENABLED" != "1" || "$EMBED_SYSTEM" != "1" ]]; then
  conky -c "$SUITE_DIR/widgets/system.conky.conf" &
fi
if [[ "$EMBED_ENABLED" != "1" || "$EMBED_NETWORK" != "1" ]]; then
  conky -c "$SUITE_DIR/widgets/network.conky.conf" &
fi
if [[ "$EMBED_ENABLED" != "1" || "$EMBED_BARO" != "1" ]]; then
  conky -c "$SUITE_DIR/widgets/baro-gauge.conky.conf" &
fi

conky -c "$SUITE_DIR/widgets/music.conky.conf" &
conky -c "$SUITE_DIR/widgets/pfsense-conky.conf" &
# conky -c "$SUITE_DIR/widgets/sitrep.conky.conf" &
# conky -c "$SUITE_DIR/widgets/notes.conky.conf" &
# conky -c "$SUITE_DIR/widgets/doctor.conky.conf" &
