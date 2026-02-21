#!/usr/bin/env bash
# Shared environment for Conky widgets (exports only)

export CONKY_SUITE_DIR="${CONKY_SUITE_DIR:-$HOME/.config/conky/gtex62-tech-hud}"   # suite install dir (set if you moved the folder)
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"                            # base cache dir (standard XDG)
# export XDG_CACHE_HOME="/dev/shm"  # RAM cache: uncomment and comment the line above
export CONKY_CACHE_DIR="${CONKY_CACHE_DIR:-$XDG_CACHE_HOME/conky}"                 # conky cache dir
export PFSENSE_HOST="${PFSENSE_HOST:-192.168.40.1}"                                # pfSense host/IP (optional)
export AP_IPS="${AP_IPS:-192.168.40.4,192.168.40.5,192.168.40.6}"                   # AP IPs (optional)
export AP_LABELS="${AP_LABELS:-Closet,Office,Great Room}"                          # AP labels (optional)
export WD_BLACK_PATH="${WD_BLACK_PATH:-/mnt/WD_Black}"                             # optional: your extra disk mount

# Optional: primary screen size for layout auto-scaling (set for best accuracy).
export CONKY_SCREEN_W="3840"
export CONKY_SCREEN_H="2160"

if [ -z "${CONKY_SCREEN_W:-}" ] || [ -z "${CONKY_SCREEN_H:-}" ]; then
  if command -v xrandr >/dev/null 2>&1; then
    xr_line="$(xrandr --current 2>/dev/null | awk '/ primary / {print; exit}')"
    if [ -z "$xr_line" ]; then
      xr_line="$(xrandr --current 2>/dev/null | awk '/ connected / {print; exit}')"
    fi
    if [ -n "$xr_line" ]; then
      read -r xr_w xr_h <<< "$(awk 'match($0,/([0-9]+)x([0-9]+)/,a){print a[1],a[2]; exit}' <<< "$xr_line")"
      if [ -n "$xr_w" ] && [ -n "$xr_h" ]; then
export CONKY_SCREEN_W="3840"
export CONKY_SCREEN_H="2160"
      fi
    fi
  fi
fi
