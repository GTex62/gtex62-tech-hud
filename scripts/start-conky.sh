#!/usr/bin/env bash

pkill -x conky 2>/dev/null || true

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
# conky -c "$SUITE_DIR/widgets/sitrep.conky.conf" &
conky -c "$SUITE_DIR/widgets/pfsense-conky.conf" &
conky -c "$SUITE_DIR/widgets/time.conky.conf" &
conky -c "$SUITE_DIR/widgets/doctor.conky.conf" &
conky -c "$SUITE_DIR/widgets/station-model.conky.conf" &
conky -c "$SUITE_DIR/widgets/system.conky.conf" &
conky -c "$SUITE_DIR/widgets/network.conky.conf" &
# conky -c "$SUITE_DIR/widgets/notes.conky.conf" &
conky -c "$SUITE_DIR/widgets/baro-gauge.conky.conf" &
conky -c "$SUITE_DIR/widgets/music.conky.conf" &
# conky -c "$SUITE_DIR/widgets/doctor.conky.conf" &
