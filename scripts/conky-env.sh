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
